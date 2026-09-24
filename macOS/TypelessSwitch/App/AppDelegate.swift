import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences: AppPreferences
    private var shutdownHandler: (@Sendable () async -> Void)?
    private var terminationIsPending = false

    override convenience init() {
        self.init(preferences: .standard)
    }

    init(preferences: AppPreferences) {
        UserDefaults.standard.register(defaults: [
            "NSInitialToolTipDelay": 1000
        ])
        UserDefaults.standard.set(1000, forKey: "NSInitialToolTipDelay")
        self.preferences = preferences
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func configureShutdown(_ handler: @escaping @Sendable () async -> Void) {
        shutdownHandler = handler
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let shutdownHandler else { return .terminateNow }
        guard !terminationIsPending else { return .terminateLater }
        terminationIsPending = true
        Task {
            await shutdownHandler()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        preferences.quitAfterLastWindowClosed
    }
}
