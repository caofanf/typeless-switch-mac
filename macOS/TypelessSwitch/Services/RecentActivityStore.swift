import Foundation
import Observation

enum RecentActivityKind: String, Codable, Sendable {
    case information
    case success
    case warning
    case failure

    var systemImage: String {
        switch self {
        case .information: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }
}

struct RecentActivity: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let occurredAt: Date
    let title: String
    let detail: String?
    let kind: RecentActivityKind
}

@Observable
@MainActor
final class RecentActivityStore {
    private let defaults: UserDefaults
    private let storageKey: String
    private var limit: Int
    private(set) var activities: [RecentActivity]

    init(defaults: UserDefaults = .standard, storageKey: String = "recentActivities", limit: Int = 100) {
        let normalizedLimit = max(1, limit)
        self.defaults = defaults
        self.storageKey = storageKey
        self.limit = normalizedLimit
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([RecentActivity].self, from: data) {
            activities = Array(decoded.prefix(normalizedLimit))
        } else {
            activities = []
        }
    }

    func record(title: String, detail: String?, kind: RecentActivityKind, date: Date = Date()) {
        let activity = RecentActivity(
            id: UUID(),
            occurredAt: date,
            title: sanitize(title),
            detail: detail.map(sanitize),
            kind: kind
        )
        activities.insert(activity, at: 0)
        trimAndPersist()
    }

    func updateLimit(_ newLimit: Int) {
        limit = max(1, newLimit)
        trimAndPersist()
    }

    func clear() {
        activities.removeAll()
        defaults.removeObject(forKey: storageKey)
    }

    private func trimAndPersist() {
        if activities.count > limit { activities.removeLast(activities.count - limit) }
        if let data = try? JSONEncoder().encode(activities) { defaults.set(data, forKey: storageKey) }
    }

    private func sanitize(_ value: String) -> String {
        var result = value
        let patterns = [
            #"(?i)(authorization\s*[:=]\s*bearer\s+)[^\s,;]+"#,
            #"(?i)((?:access_)?token\s*[:=]\s*)[^\s,;]+"#,
            #"(?i)(cookie\s*[:=]\s*)[^\n]+"#,
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "$1[已隐藏]", options: .regularExpression)
        }
        return result
    }
}
