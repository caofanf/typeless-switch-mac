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
    var activeTasks: [CoreTask]

    enum CodingKeys: String, CodingKey { case connection, accounts, version, backup, patch; case activeTasks = "active_tasks" }
    var connectionState: ConnectionState { connection.state }
    var accountCount: Int { accounts.count }
    var activeTaskCount: Int { activeTasks.count }

    static let empty = SystemOverview(
        connection: .disconnected,
        accounts: [],
        version: .init(current: nil, lastSeen: nil, drifted: false, recordedAt: nil),
        backup: .init(status: .noData, backedUp: false, hasData: false, sources: [], latestDataModifiedAt: nil, latestBackup: nil, backupDirectory: "", backupPath: nil),
        patch: .init(exists: false, patched: nil, detectedFile: nil, filePath: nil, replacementsSource: nil, hasBackup: nil, error: nil),
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
struct DiagnosticReport: Codable, Equatable, Sendable {
    let connection: ConnectionStatus; let version: VersionStatus; let backup: BackupStatus; let patch: PatchStatus
}
