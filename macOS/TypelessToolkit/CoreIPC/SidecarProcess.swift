import Foundation
import OSLog

struct CoreHello: Equatable, Sendable {
    let protocolName: String
    let protocolVersion: String
    let coreVersion: String?
    let architecture: String?
    let capabilities: [String]

    init(json: JSONValue) throws {
        guard let object = json.objectValue,
              let protocolName = object["protocol_name"]?.stringValue,
              let protocolVersion = object["protocol_version"]?.stringValue else {
            throw SidecarProcessError.invalidHandshake
        }
        self.protocolName = protocolName
        self.protocolVersion = protocolVersion
        self.coreVersion = object["core_version"]?.stringValue
        self.architecture = object["architecture"]?.stringValue ?? object["arch"]?.stringValue
        if case .array(let values) = object["capabilities"] {
            self.capabilities = values.compactMap(\.stringValue)
        } else {
            self.capabilities = []
        }
    }
}

enum SidecarProcessError: Error, LocalizedError, Sendable {
    case bundledRuntimeMissing(String)
    case launchFailed(String)
    case handshakeTimedOut
    case invalidHandshake
    case incompatibleProtocol(name: String, version: String)
    case terminated(status: Int32)

    var errorDescription: String? {
        switch self {
        case .bundledRuntimeMissing(let path): "Bundled sidecar runtime is missing: \(path)"
        case .launchFailed(let message): "Unable to launch sidecar: \(message)"
        case .handshakeTimedOut: "Sidecar handshake timed out"
        case .invalidHandshake: "Sidecar returned an invalid handshake"
        case .incompatibleProtocol(let name, let version): "Unsupported sidecar protocol \(name) \(version)"
        case .terminated(let status): "Sidecar exited unexpectedly with status \(status)"
        }
    }
}

actor SidecarProcess {
    struct Configuration: Sendable {
        let nodeURL: URL
        let mainScriptURL: URL
        let workingDirectoryURL: URL
        var environment: [String: String]

        static func bundled(resourceURL: URL? = Bundle.main.resourceURL) throws -> Configuration {
            guard let resourceURL else {
                throw SidecarProcessError.bundledRuntimeMissing("Bundle resources")
            }
            let sidecarURL = resourceURL.appendingPathComponent("Sidecar", isDirectory: true)
            let nodeURL = sidecarURL.appendingPathComponent("node", isDirectory: false)
            let mainURL = sidecarURL
                .appendingPathComponent("sidecar", isDirectory: true)
                .appendingPathComponent("main.js", isDirectory: false)
            guard FileManager.default.isExecutableFile(atPath: nodeURL.path) else {
                throw SidecarProcessError.bundledRuntimeMissing(nodeURL.path)
            }
            guard FileManager.default.fileExists(atPath: mainURL.path) else {
                throw SidecarProcessError.bundledRuntimeMissing(mainURL.path)
            }
            return Configuration(
                nodeURL: nodeURL,
                mainScriptURL: mainURL,
                workingDirectoryURL: sidecarURL,
                environment: ProcessInfo.processInfo.environment
            )
        }
    }

    private static let logger = Logger(subsystem: "com.typelesstoolkit.mac", category: "Sidecar")
    private let configuration: Configuration
    private var process: Process?
    private var transport: JSONLineTransport?
    private var stderrPipe: Pipe?
    private(set) var eventRouter: EventRouter?
    private(set) var hello: CoreHello?
    private var restartAttempted = false
    private var isShuttingDown = false

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func start() async throws -> CoreHello {
        if let hello, process?.isRunning == true { return hello }
        isShuttingDown = false
        restartAttempted = false
        return try await launchAndHandshake()
    }

    func call(method: String, params: JSONValue = .object([:])) async throws -> JSONValue {
        if transport == nil { _ = try await start() }
        guard let transport else { throw IPCTransportError.connectionClosed }
        return try await transport.call(method: method, params: params)
    }

    func shutdown() async {
        isShuttingDown = true
        if let transport {
            _ = try? await withTimeout(seconds: 2) {
                try await transport.call(method: "core.shutdown", params: .object([:]))
            }
        }

        if let process, process.isRunning {
            let deadline = ContinuousClock.now + .seconds(2)
            while process.isRunning && ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning { process.terminate() }
        }
        await transport?.close()
        clearRuntimeState()
    }

    private func launchAndHandshake() async throws -> CoreHello {
        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = configuration.nodeURL
        process.arguments = [
            configuration.mainScriptURL.path,
            "--transport=stdio",
            "--parent-pid=\(ProcessInfo.processInfo.processIdentifier)",
        ]
        process.currentDirectoryURL = configuration.workingDirectoryURL
        var environment = configuration.environment
        environment.removeValue(forKey: "NODE_OPTIONS")
        environment.removeValue(forKey: "NODE_PATH")
        process.environment = environment
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.terminationHandler = { [weak self, weak process] terminated in
            guard process != nil else { return }
            Task { await self?.didTerminate(terminated) }
        }
        standardError.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let message = String(data: data, encoding: .utf8) else { return }
            Self.logger.error("\(message, privacy: .private(mask: .hash))")
        }

        do {
            try process.run()
        } catch {
            standardError.fileHandleForReading.readabilityHandler = nil
            throw SidecarProcessError.launchFailed(error.localizedDescription)
        }

        let transport = JSONLineTransport(
            input: standardOutput.fileHandleForReading,
            output: standardInput.fileHandleForWriting
        )
        await transport.start()
        self.process = process
        self.transport = transport
        self.stderrPipe = standardError
        self.eventRouter = EventRouter(notifications: transport.notifications)

        do {
            let response = try await withTimeout(seconds: 5) {
                try await transport.call(method: "core.hello", params: .object([:]))
            }
            let hello = try CoreHello(json: response)
            guard hello.protocolName == "typeless-toolkit-core", hello.protocolVersion == "1.0" else {
                throw SidecarProcessError.incompatibleProtocol(
                    name: hello.protocolName,
                    version: hello.protocolVersion
                )
            }
            self.hello = hello
            return hello
        } catch is TimeoutMarker {
            await transport.failAll(with: SidecarProcessError.handshakeTimedOut)
            process.terminate()
            clearRuntimeState()
            throw SidecarProcessError.handshakeTimedOut
        } catch {
            await transport.failAll(with: error)
            process.terminate()
            clearRuntimeState()
            throw error
        }
    }

    private func didTerminate(_ terminatedProcess: Process) async {
        guard process === terminatedProcess else { return }
        let status = terminatedProcess.terminationStatus
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        await transport?.failAll(with: SidecarProcessError.terminated(status: status))
        clearRuntimeState()

        guard !isShuttingDown, !restartAttempted else { return }
        restartAttempted = true
        do {
            _ = try await launchAndHandshake()
            Self.logger.notice("Sidecar restarted after an unexpected exit")
        } catch {
            Self.logger.error("Sidecar restart failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearRuntimeState() {
        process = nil
        transport = nil
        stderrPipe = nil
        eventRouter = nil
        hello = nil
    }
}

private struct TimeoutMarker: Error, Sendable {}

private func withTimeout<T: Sendable>(
    seconds: Int,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutMarker()
        }
        guard let result = try await group.next() else { throw TimeoutMarker() }
        group.cancelAll()
        return result
    }
}
