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

enum AddAccountPhase: Equatable, Sendable {
    case idle
    case establishingConnection
    case capturing
    case reviewing
    case saving
    case completed
    case failed
}

enum AccountOperationKind: Equatable, Sendable {
    case delete
    case switchSnapshot
}

struct PendingAccountOperation: Identifiable, Equatable, Sendable {
    let kind: AccountOperationKind
    let accountID: String
    let deleteSnapshot: Bool
    let confirmation: Confirmation

    var id: String { confirmation.token }
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
    private(set) var accounts: [Account] = []
    var selectedAccountID: String?
    var accountSearchText = ""
    private(set) var addAccountPhase: AddAccountPhase = .idle
    private(set) var pendingAccountCapture: AccountCapture?
    private(set) var pendingAccountOperation: PendingAccountOperation?
    private(set) var isPerformingAccountOperation = false

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

    var filteredAccounts: [Account] {
        let query = accountSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return accounts }
        return accounts.filter { account in
            account.nickname.localizedCaseInsensitiveContains(query)
                || account.email.localizedCaseInsensitiveContains(query)
                || account.id.localizedCaseInsensitiveContains(query)
        }
    }

    func refreshAccounts() async {
        do {
            accounts = try await coreClient.listAccounts()
            if let selectedAccountID, !accounts.contains(where: { $0.id == selectedAccountID }) {
                self.selectedAccountID = nil
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "无法刷新账号列表。请稍后重试。"
        }
    }

    func beginAddAccount() async {
        guard addAccountPhase == .idle || addAccountPhase == .completed || addAccountPhase == .failed else { return }
        pendingAccountCapture = nil
        lastErrorMessage = nil
        addAccountPhase = .establishingConnection

        do {
            connectionState = try await coreClient.establishConnection().state
            addAccountPhase = .capturing
            pendingAccountCapture = try await coreClient.captureCurrentAccount()
            addAccountPhase = .reviewing
        } catch {
            addAccountPhase = .failed
            lastErrorMessage = "无法抓取当前账号。请确认 Typeless 已登录并保持运行。"
        }
    }

    func savePendingAccount(nickname: String, email: String) async {
        guard addAccountPhase == .reviewing,
              let captureID = pendingAccountCapture?.captureID else { return }
        addAccountPhase = .saving
        lastErrorMessage = nil

        do {
            let saved = try await coreClient.saveCapture(id: captureID, nickname: nickname, email: email)
            upsertAccount(saved)
            selectedAccountID = saved.id
            pendingAccountCapture = nil
            addAccountPhase = .completed
        } catch {
            addAccountPhase = .reviewing
            lastErrorMessage = "无法保存账号。抓取信息可能已过期，请重试。"
        }
    }

    func dismissAddAccount() {
        pendingAccountCapture = nil
        addAccountPhase = .idle
    }

    func saveSnapshot(accountID: String) async {
        do {
            let result = try await coreClient.saveSnapshot(accountID: accountID)
            if let index = accounts.firstIndex(where: { $0.id == result.userID }) {
                accounts[index].hasSnapshot = result.hasSnapshot ?? true
                accounts[index].snapshotModifiedAt = Date()
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "无法保存账号快照。请稍后重试。"
        }
    }

    func prepareDeleteAccount(accountID: String, deleteSnapshot: Bool) async {
        let nickname = accounts.first(where: { $0.id == accountID })?.nickname ?? accountID
        let params: JSONValue = .object([
            "user_id": .string(accountID),
            "delete_snapshot": .bool(deleteSnapshot),
        ])
        let summary: JSONValue = .object([
            "title": .string("删除账号“\(nickname)”"),
            "message": .string(deleteSnapshot ? "账号记录和本地登录快照将被删除。" : "账号记录将被删除，本地登录快照会保留。"),
            "destructive": .bool(true),
        ])
        await prepareAccountOperation(kind: .delete, accountID: accountID, deleteSnapshot: deleteSnapshot, method: "accounts.delete", params: params, summary: summary)
    }

    func prepareSwitchAccount(accountID: String) async {
        let nickname = accounts.first(where: { $0.id == accountID })?.nickname ?? accountID
        let params: JSONValue = .object(["user_id": .string(accountID)])
        let summary: JSONValue = .object([
            "title": .string("切换到“\(nickname)”"),
            "message": .string("将恢复该账号的本地快照并重新启动 Typeless。"),
            "destructive": .bool(false),
        ])
        await prepareAccountOperation(kind: .switchSnapshot, accountID: accountID, deleteSnapshot: false, method: "snapshots.switch", params: params, summary: summary)
    }

    func confirmPendingAccountOperation() async {
        guard let operation = pendingAccountOperation, !isPerformingAccountOperation else { return }
        isPerformingAccountOperation = true
        defer { isPerformingAccountOperation = false }
        lastErrorMessage = nil

        do {
            switch operation.kind {
            case .delete:
                _ = try await coreClient.deleteAccount(
                    id: operation.accountID,
                    deleteSnapshot: operation.deleteSnapshot,
                    confirmationToken: operation.confirmation.token
                )
                accounts.removeAll { $0.id == operation.accountID }
                if selectedAccountID == operation.accountID { selectedAccountID = nil }
            case .switchSnapshot:
                _ = try await coreClient.switchSnapshot(
                    accountID: operation.accountID,
                    confirmationToken: operation.confirmation.token
                )
            }
            pendingAccountOperation = nil
        } catch {
            pendingAccountOperation = nil
            lastErrorMessage = "操作未完成。确认可能已过期，请重新尝试。"
        }
    }

    func cancelPendingAccountOperation() {
        pendingAccountOperation = nil
    }

    private func prepareAccountOperation(
        kind: AccountOperationKind,
        accountID: String,
        deleteSnapshot: Bool,
        method: String,
        params: JSONValue,
        summary: JSONValue
    ) async {
        lastErrorMessage = nil
        do {
            let confirmation = try await coreClient.prepareOperation(method: method, params: params, summary: summary)
            pendingAccountOperation = .init(
                kind: kind,
                accountID: accountID,
                deleteSnapshot: deleteSnapshot,
                confirmation: confirmation
            )
        } catch {
            lastErrorMessage = "无法准备操作。请刷新状态后重试。"
        }
    }

    private func upsertAccount(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
    }

    func refreshOverview() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let latest = try await coreClient.getOverview()
            overview = latest
            accounts = latest.accounts
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
