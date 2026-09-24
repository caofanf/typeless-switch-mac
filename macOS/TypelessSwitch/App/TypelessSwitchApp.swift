import OSLog
import SwiftUI

@MainActor
final class AppRuntime {
    private static let logger = Logger(subsystem: "com.typelessswitch.mac", category: "AppRuntime")

    let model: AppModel
    private let coreClient: any CoreClientProtocol

    init(preferences: AppPreferences, transport: any RPCTransportProtocol) {
        let coreClient = LiveCoreClient(transport: transport)
        self.coreClient = coreClient
        self.model = AppModel(coreClient: coreClient, preferences: preferences)
    }

    private init(preferences: AppPreferences, coreClient: any CoreClientProtocol) {
        self.coreClient = coreClient
        self.model = AppModel(coreClient: coreClient, preferences: preferences)
    }

    static func bundled(preferences: AppPreferences) -> AppRuntime {
        do {
            let configuration = try SidecarProcess.Configuration.bundled()
            return AppRuntime(preferences: preferences, transport: SidecarProcess(configuration: configuration))
        } catch {
            logger.fault("Unable to configure bundled sidecar: \(error.localizedDescription, privacy: .public)")
            return AppRuntime(preferences: preferences, coreClient: UnavailableCoreClient())
        }
    }

    func shutdown() async {
        await coreClient.close()
    }
}

@main
struct TypelessSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var preferences: AppPreferences
    @State private var model: AppModel
    private let runtime: AppRuntime

    init() {
        UserDefaults.standard.register(defaults: [
            "NSInitialToolTipDelay": 1000
        ])
        UserDefaults.standard.set(1000, forKey: "NSInitialToolTipDelay")
        let preferences = AppPreferences.standard
        let runtime = AppRuntime.bundled(preferences: preferences)
        self.runtime = runtime
        _preferences = State(initialValue: preferences)
        _model = State(initialValue: runtime.model)
    }

    var body: some Scene {
        WindowGroup("Typeless Switch", id: "main") {
            RootView(model: model)
                .frame(minWidth: AppLayout.mainMinimumWidth, minHeight: 640)
                .onAppear {
                    appDelegate.configureShutdown {
                        await runtime.shutdown()
                    }
                }
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(model: model)
        }

        MenuBarExtra(isInserted: $preferences.showsMenuBarExtra) {
            MenuBarContent(model: model)
        } label: {
            Label("Typeless Switch", systemImage: menuBarSystemImage)
        }
    }

    private var menuBarSystemImage: String {
        switch model.connectionState {
        case .connected: "checkmark.circle.fill"
        case .connecting: "arrow.trianglehead.2.clockwise.rotate.90.circle"
        case .degraded: "exclamationmark.triangle.fill"
        case .disconnected: "bolt.horizontal.circle"
        }
    }
}
