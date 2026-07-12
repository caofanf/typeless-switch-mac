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

@Observable
@MainActor
final class AppModel {
    var selection: SidebarDestination = .overview
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var activeTasks: [CoreTask] = []
    private(set) var overview: SystemOverview = .empty
    private(set) var isRefreshing = false
    private(set) var isStale = false
    private(set) var lastErrorMessage: String?

    private let coreClient: any CoreClientProtocol

    init(coreClient: any CoreClientProtocol) {
        self.coreClient = coreClient
    }

    func establishConnection() async {
        guard connectionState != .connecting else { return }
        connectionState = .connecting
        lastErrorMessage = nil

        do {
            connectionState = try await coreClient.establishConnection().state
            await refreshOverview()
        } catch {
            connectionState = .degraded
            lastErrorMessage = "无法建立管理连接。请确认 Typeless 正在运行。"
        }
    }

    func syncAllDictionaries() async {
        do {
            let task = try await coreClient.syncAllDictionaries()
            if !activeTasks.contains(where: { $0.id == task.id }) {
                activeTasks.append(task)
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "无法开始同步。请稍后重试。"
        }
    }

    func refreshOverview() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let latest = try await coreClient.getOverview()
            overview = latest
            connectionState = latest.connectionState
            activeTasks = latest.activeTasks
            isStale = false
            lastErrorMessage = nil
        } catch {
            isStale = true
            lastErrorMessage = "无法刷新状态。请稍后重试。"
        }
    }
}
