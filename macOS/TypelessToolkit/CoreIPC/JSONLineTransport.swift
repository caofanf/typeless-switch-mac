import Foundation

enum JSONLineDecoderError: Error, Equatable, LocalizedError {
    case frameTooLarge(maxBytes: Int)

    var errorDescription: String? {
        switch self {
        case .frameTooLarge(let maxBytes):
            "JSON Lines frame exceeds the \(maxBytes)-byte limit"
        }
    }
}

struct JSONLineDecoder: Sendable {
    private var buffer = Data()
    let maxFrameBytes: Int

    init(maxFrameBytes: Int = 8 * 1024 * 1024) {
        precondition(maxFrameBytes > 0)
        self.maxFrameBytes = maxFrameBytes
    }

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []

        while let newline = buffer.firstIndex(of: 0x0A) {
            let frameLength = buffer.distance(from: buffer.startIndex, to: newline)
            guard frameLength <= maxFrameBytes else {
                buffer.removeAll(keepingCapacity: false)
                throw JSONLineDecoderError.frameTooLarge(maxBytes: maxFrameBytes)
            }

            var frame = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if frame.last == 0x0D { frame.removeLast() }
            if !frame.isEmpty { frames.append(frame) }
        }

        guard buffer.count <= maxFrameBytes else {
            buffer.removeAll(keepingCapacity: false)
            throw JSONLineDecoderError.frameTooLarge(maxBytes: maxFrameBytes)
        }
        return frames
    }
}

enum IPCTransportError: Error, LocalizedError, Sendable {
    case connectionClosed
    case invalidMessage
    case remote(JSONRPCErrorPayload)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionClosed: "Sidecar connection closed"
        case .invalidMessage: "Sidecar sent an invalid JSON-RPC message"
        case .remote(let error): error.message
        case .writeFailed(let message): "Unable to write to sidecar: \(message)"
        }
    }
}

protocol RPCTransportProtocol: Sendable {
    func call(method: String, params: JSONValue) async throws -> JSONValue
    func close() async
}

actor JSONLineTransport: RPCTransportProtocol {
    nonisolated let notifications: AsyncStream<JSONRPCNotification>

    private let input: FileHandle
    private let output: FileHandle
    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private var decoder: JSONLineDecoder
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var isClosed = false

    init(input: FileHandle, output: FileHandle, maxFrameBytes: Int = 8 * 1024 * 1024) {
        self.input = input
        self.output = output
        self.decoder = JSONLineDecoder(maxFrameBytes: maxFrameBytes)
        let stream = AsyncStream<JSONRPCNotification>.makeStream()
        self.notifications = stream.stream
        self.notificationContinuation = stream.continuation
    }

    func start() {
        guard !isClosed else { return }
        input.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.consume(data) }
        }
    }

    func call(method: String, params: JSONValue = .object([:])) async throws -> JSONValue {
        guard !isClosed else { throw IPCTransportError.connectionClosed }
        let id = UUID().uuidString
        let request = JSONRPCRequest(id: id, method: method, params: params)
        var data = try JSONEncoder().encode(request)
        data.append(0x0A)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try output.write(contentsOf: data)
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: IPCTransportError.writeFailed(error.localizedDescription))
            }
        }
    }

    func close() {
        finish(with: IPCTransportError.connectionClosed)
        try? output.close()
        try? input.close()
    }

    func failAll(with error: Error) {
        finish(with: error)
    }

    private func consume(_ data: Data) {
        guard !isClosed else { return }
        if data.isEmpty {
            finish(with: IPCTransportError.connectionClosed)
            return
        }

        do {
            for frame in try decoder.append(data) {
                try route(frame)
            }
        } catch {
            finish(with: error)
        }
    }

    private func route(_ frame: Data) throws {
        let message: JSONRPCIncomingMessage
        do {
            message = try JSONDecoder().decode(JSONRPCIncomingMessage.self, from: frame)
        } catch {
            throw IPCTransportError.invalidMessage
        }
        guard message.jsonrpc == "2.0" else { throw IPCTransportError.invalidMessage }

        if let method = message.method {
            notificationContinuation.yield(JSONRPCNotification(jsonrpc: message.jsonrpc, method: method, params: message.params))
            return
        }
        guard let id = message.id, let continuation = pending.removeValue(forKey: id) else { return }
        if let error = message.error {
            continuation.resume(throwing: IPCTransportError.remote(error))
        } else if let result = message.result {
            continuation.resume(returning: result)
        } else {
            continuation.resume(throwing: IPCTransportError.invalidMessage)
        }
    }

    private func finish(with error: Error) {
        guard !isClosed else { return }
        isClosed = true
        input.readabilityHandler = nil
        let continuations = pending.values
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
        notificationContinuation.finish()
    }
}
