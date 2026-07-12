import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences: AppPreferences

    override convenience init() {
        self.init(preferences: .standard)
    }

    init(preferences: AppPreferences) {
        self.preferences = preferences
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        preferences.quitAfterLastWindowClosed
    }
}
