import Foundation
import Observation
import UserNotifications

enum DiagnosticLogLevel: String, CaseIterable, Identifiable, Sendable {
    case info
    case debug

    var id: Self { self }

    var title: String {
        switch self {
        case .info: "信息"
        case .debug: "调试（仅本次运行）"
        }
    }
}

@Observable
@MainActor
final class AppPreferences {
    static let standard = AppPreferences()

    private enum Key {
        static let showsMenuBarExtra = "showsMenuBarExtra"
        static let quitAfterLastWindowClosed = "quitAfterLastWindowClosed"
        static let refreshOnActivation = "refreshOnActivation"
        static let notificationsEnabled = "notificationsEnabled"
        static let recentActivityLimit = "recentActivityLimit"
    }

    private let defaults: UserDefaults

    var showsMenuBarExtra: Bool {
        didSet { defaults.set(showsMenuBarExtra, forKey: Key.showsMenuBarExtra) }
    }
    var quitAfterLastWindowClosed: Bool {
        didSet { defaults.set(quitAfterLastWindowClosed, forKey: Key.quitAfterLastWindowClosed) }
    }
    var refreshOnActivation: Bool {
        didSet { defaults.set(refreshOnActivation, forKey: Key.refreshOnActivation) }
    }
    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }
    private var recentActivityLimitValue: Int
    var recentActivityLimit: Int {
        get { recentActivityLimitValue }
        set {
            let normalized = Self.allowedActivityLimits.contains(newValue) ? newValue : 100
            recentActivityLimitValue = normalized
            defaults.set(normalized, forKey: Key.recentActivityLimit)
        }
    }

    /// 调试日志故意不写入 UserDefaults，重新启动 App 后始终回到 info。
    var diagnosticLogLevel: DiagnosticLogLevel = .info

    static let allowedActivityLimits = [25, 50, 100, 200]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsMenuBarExtra = Self.bool(defaults, key: Key.showsMenuBarExtra, fallback: true)
        quitAfterLastWindowClosed = Self.bool(defaults, key: Key.quitAfterLastWindowClosed, fallback: false)
        refreshOnActivation = Self.bool(defaults, key: Key.refreshOnActivation, fallback: true)
        notificationsEnabled = Self.bool(defaults, key: Key.notificationsEnabled, fallback: false)
        let storedLimit = defaults.object(forKey: Key.recentActivityLimit) as? Int ?? 100
        recentActivityLimitValue = Self.allowedActivityLimits.contains(storedLimit) ? storedLimit : 100
    }

    private static func bool(_ defaults: UserDefaults, key: String, fallback: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }
}

@MainActor
protocol AppNotificationDelivering: AnyObject {
    func deliver(title: String, body: String?) async
}

@MainActor
final class SystemNotificationCenter: AppNotificationDelivering {
    func deliver(title: String, body: String?) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        } else if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        if let body, !body.isEmpty { content.body = body }
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
