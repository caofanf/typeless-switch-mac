import Foundation
import Observation

/// 原生界面的顶层导航目标。
enum SidebarDestination: String, CaseIterable, Identifiable, Sendable {
    case overview
    case accounts
    case masterDictionary
    case backupRestore
    case diagnostics
    case advancedTools
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "概览"
        case .accounts: "账号"
        case .masterDictionary: "主词库"
        case .backupRestore: "备份与恢复"
        case .diagnostics: "诊断"
        case .advancedTools: "高级工具"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .accounts: "person.2"
        case .masterDictionary: "text.book.closed"
        case .backupRestore: "externaldrive.badge.timemachine"
        case .diagnostics: "stethoscope"
        case .advancedTools: "wrench.and.screwdriver"
        case .settings: "gearshape"
        }
    }
}

enum ConnectionState: String, Codable, Sendable {
    case disconnected
    case connecting
    case connected
    case degraded
}

struct SystemOverview: Equatable, Sendable {
    var connectionState: ConnectionState
    var accountCount: Int
    var activeTaskCount: Int

    static let empty = SystemOverview(
        connectionState: .disconnected,
        accountCount: 0,
        activeTaskCount: 0
    )
}

struct ActiveTask: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var progress: Double?
}

@MainActor
protocol CoreClientProtocol: AnyObject {
    func getOverview() async throws -> SystemOverview
}

@MainActor
final class UnavailableCoreClient: CoreClientProtocol {
    func getOverview() async throws -> SystemOverview {
        .empty
    }
}

@Observable
@MainActor
final class AppModel {
    var selection: SidebarDestination = .overview
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var activeTasks: [ActiveTask] = []
    private(set) var overview: SystemOverview = .empty
    private(set) var isRefreshing = false
    private(set) var lastErrorMessage: String?

    private let coreClient: any CoreClientProtocol

    init(coreClient: any CoreClientProtocol) {
        self.coreClient = coreClient
    }

    func refreshOverview() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let latest = try await coreClient.getOverview()
            overview = latest
            connectionState = latest.connectionState
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "无法刷新状态。请稍后重试。"
        }
    }
}
