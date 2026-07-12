import SwiftUI

@main
struct TypelessToolkitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel(coreClient: UnavailableCoreClient())

    var body: some Scene {
        WindowGroup("Typeless Toolkit", id: "main") {
            RootView(model: model)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(model: model)
        }

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Label("Typeless Toolkit", systemImage: menuBarSystemImage)
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
