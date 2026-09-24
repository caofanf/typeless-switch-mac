import Foundation

enum ConnectionState: String, Codable, Sendable {
    case disconnected, connecting, connected, degraded
}

struct ConnectionStatus: Codable, Equatable, Sendable {
    var state: ConnectionState
    var port: Int
    var cdpReachable: Bool
    var restarted: Bool?

    enum CodingKeys: String, CodingKey {
        case state, port, restarted
        case cdpReachable = "cdp_reachable"
    }

    static let disconnected = ConnectionStatus(state: .disconnected, port: 9222, cdpReachable: false)
}

struct VersionStatus: Codable, Equatable, Sendable {
    var current: String?
    var lastSeen: String?
    var drifted: Bool
    var recordedAt: Date?

    enum CodingKeys: String, CodingKey {
        case current, drifted
        case lastSeen = "last_seen"
        case recordedAt = "recorded_at"
    }
}

struct BackupSource: Codable, Identifiable, Equatable, Sendable {
    let key: String
    let label: String
    let path: String
    let exists: Bool
    let modifiedAtMilliseconds: Double
    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, path, exists
        case modifiedAtMilliseconds = "mtime_ms"
    }
}

struct RuntimeBackup: Codable, Equatable, Sendable {
    var name: String
    var path: String
    var modifiedAtMilliseconds: Double
    var modifiedAt: Date?
    var reason: String

    enum CodingKeys: String, CodingKey {
        case name, path, reason
        case modifiedAtMilliseconds = "mtime_ms"
        case modifiedAt = "mtime"
    }
}

enum BackupState: String, Codable, Sendable { case noData = "no_data"; case backedUp = "backed_up"; case needsBackup = "needs_backup" }

struct BackupStatus: Codable, Equatable, Sendable {
    var status: BackupState
    var backedUp: Bool
    var hasData: Bool
    var sources: [BackupSource]
    var latestDataModifiedAt: Date?
    var latestBackup: RuntimeBackup?
    var backupDirectory: String
    var backupPath: String?

    enum CodingKeys: String, CodingKey {
        case status, sources
        case backedUp = "backed_up"
        case hasData = "has_data"
        case latestDataModifiedAt = "latest_data_mtime"
        case latestBackup = "latest_backup"
        case backupDirectory = "backup_dir"
        case backupPath = "backup_path"
    }
}

struct PatchStatus: Codable, Equatable, Sendable {
    var exists: Bool
    var patched: Bool?
    var detectedFile: String?
    var filePath: String?
    var replacementsSource: String?
    var hasBackup: Bool?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case exists, patched, error
        case detectedFile = "detected_file"
        case filePath = "file_path"
        case replacementsSource = "replacements_source"
        case hasBackup = "has_backup"
    }
}

struct SystemOverview: Codable, Equatable, Sendable {
    var connection: ConnectionStatus
    var accounts: [Account]
    var version: VersionStatus
    var backup: BackupStatus
    var patch: PatchStatus
    var rotation: RotationStatus?
    var activeTasks: [CoreTask]

    enum CodingKeys: String, CodingKey {
        case connection, accounts, version, backup, patch, rotation
        case activeTasks = "active_tasks"
    }
    var connectionState: ConnectionState { connection.state }
    var accountCount: Int { accounts.count }
    var activeTaskCount: Int { activeTasks.count }

    static let empty = SystemOverview(
        connection: .disconnected,
        accounts: [],
        version: .init(current: nil, lastSeen: nil, drifted: false, recordedAt: nil),
        backup: .init(status: .noData, backedUp: false, hasData: false, sources: [], latestDataModifiedAt: nil, latestBackup: nil, backupDirectory: "", backupPath: nil),
        patch: .init(exists: false, patched: nil, detectedFile: nil, filePath: nil, replacementsSource: nil, hasBackup: nil, error: nil),
        rotation: .disabled,
        activeTasks: []
    )
}

struct AccountList: Codable, Sendable { let accounts: [Account] }
struct ActiveTaskList: Codable, Sendable { let tasks: [CoreTask] }
struct Confirmation: Codable, Equatable, Sendable {
    let token: String
    let expiresAt: Date
    let summary: JSONValue
    enum CodingKeys: String, CodingKey { case token = "confirmation_token"; case expiresAt = "expires_at"; case summary }
}
struct BackupInspectionSummary: Codable, Equatable, Sendable {
    let type: String; let version: Int; let createdAt: Date?; let fileCount: Int; let size: Int
    enum CodingKeys: String, CodingKey { case type, version, size; case createdAt = "created_at"; case fileCount = "file_count" }
}
struct BackupInspection: Codable, Equatable, Sendable {
    let inspectionID: String; let expiresAt: Date; let summary: BackupInspectionSummary
    enum CodingKeys: String, CodingKey { case inspectionID = "inspection_id"; case expiresAt = "expires_at"; case summary }
}
struct PathResult: Codable, Equatable, Sendable { let path: String }
struct DeviceStatus: Codable, Equatable, Sendable { let connection: ConnectionStatus; let backup: BackupStatus }

struct DiagnosticTypelessStatus: Codable, Equatable, Sendable {
    let appPath: String
    let appFound: Bool
    let binPath: String
    let binFound: Bool
    let asarPath: String
    let asarFound: Bool
    let infoPlist: String
    let infoPlistFound: Bool
    let userDataDirectory: String
    let userDataFound: Bool

    enum CodingKeys: String, CodingKey {
        case appPath = "app_path"
        case appFound = "app_found"
        case binPath = "bin_path"
        case binFound = "bin_found"
        case asarPath = "asar_path"
        case asarFound = "asar_found"
        case infoPlist = "info_plist"
        case infoPlistFound = "info_plist_found"
        case userDataDirectory = "user_data_dir"
        case userDataFound = "user_data_found"
    }
}

struct DiagnosticCDPStatus: Codable, Equatable, Sendable {
    let port: Int
    let reachable: Bool
    let state: ConnectionState
}

struct DiagnosticDataStatus: Codable, Equatable, Sendable {
    let directory: String
    let codeDirectory: String
    let writable: Bool
    let migration: JSONValue
    let accountsFile: String
    let accountCount: Int
    let profilesDirectory: String
    let runtimeBackupsDirectory: String
    let backup: BackupStatus

    enum CodingKeys: String, CodingKey {
        case directory = "dir"
        case codeDirectory = "code_dir"
        case writable, migration
        case accountsFile = "accounts_file"
        case accountCount = "accounts_count"
        case profilesDirectory = "profiles_dir"
        case runtimeBackupsDirectory = "runtime_backups_dir"
        case backup
    }
}

struct DiagnosticReport: Codable, Equatable, Sendable {
    let typeless: DiagnosticTypelessStatus
    let cdp: DiagnosticCDPStatus
    let data: DiagnosticDataStatus
    let connection: ConnectionStatus
    let version: VersionStatus
    let backup: BackupStatus
    let patch: PatchStatus
}

enum RotationMode: String, Codable, Sendable, CaseIterable {
    case notify
    case auto

    var title: String {
        switch self {
        case .notify: return "弹窗提醒"
        case .auto: return "自动切换"
        }
    }

    var description: String {
        switch self {
        case .notify: return "用量达到提醒线时弹出系统确认框，由你决定切换或稍后"
        case .auto: return "用量达到阈值后直接自动切换到下一个可用账号并同步词库"
        }
    }
}

enum RotationPhase: String, Codable, Sendable {
    case disabled
    case waiting
    case checking
    case prompting
    case switching
    case paused
    case error

    var title: String {
        switch self {
        case .disabled: return "未开启"
        case .waiting: return "等待检查"
        case .checking: return "检查中"
        case .prompting: return "等待确认"
        case .switching: return "正在切号"
        case .paused: return "已暂停"
        case .error: return "异常"
        }
    }

    var displayName: String { title }
}

struct RotationSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var mode: RotationMode
    var wordThreshold: Int
    var warningWords: Int
    var intervalMinutes: Int

    enum CodingKeys: String, CodingKey {
        case enabled, mode
        case wordThreshold = "word_threshold"
        case warningWords = "warning_words"
        case intervalMinutes = "interval_minutes"
    }

    static let `default` = RotationSettings(
        enabled: false,
        mode: .notify,
        wordThreshold: 2000,
        warningWords: 100,
        intervalMinutes: 15
    )
}

struct RotationIssue: Codable, Equatable, Sendable, Identifiable {
    var code: String
    var message: String
    var action: String
    var accountId: String?
    var retryable: Bool

    var id: String {
        if let accountId { return "\(code):\(accountId)" }
        return code
    }

    enum CodingKeys: String, CodingKey {
        case code, message, action, retryable
        case accountId = "account_id"
    }
}

struct RotationStatus: Codable, Equatable, Sendable {
    var phase: RotationPhase
    var message: String
    var lastCheckAt: Date?
    var nextCheckAt: Date?
    var currentUserId: String?
    var usedWords: Int?
    var lastResult: String?
    var issue: RotationIssue?
    var candidateIssues: [RotationIssue]
    var notificationError: String?

    enum CodingKeys: String, CodingKey {
        case phase, message, issue
        case lastCheckAt = "last_check_at"
        case nextCheckAt = "next_check_at"
        case currentUserId = "current_user_id"
        case usedWords = "used_words"
        case lastResult = "last_result"
        case candidateIssues = "candidate_issues"
        case notificationError = "notification_error"
    }

    static let disabled = RotationStatus(
        phase: .disabled,
        message: "账号轮动未开启",
        lastCheckAt: nil,
        nextCheckAt: nil,
        currentUserId: nil,
        usedWords: nil,
        lastResult: nil,
        issue: nil,
        candidateIssues: [],
        notificationError: nil
    )
}

struct RotationViewPayload: Codable, Equatable, Sendable {
    var settings: RotationSettings
    var status: RotationStatus
}

