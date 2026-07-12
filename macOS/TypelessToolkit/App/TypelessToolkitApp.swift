import SwiftUI

@main
struct TypelessToolkitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel(coreClient: UnavailableCoreClient())

    var body: some Scene {
        WindowGroup("Typeless Toolkit") {
            RootView(model: model)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
    }
}
