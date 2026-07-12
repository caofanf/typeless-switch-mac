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

struct MasterDictionaryDiff: Equatable, Sendable {
    let added: [String]
    let removed: [String]
    let unchanged: [String]
}

struct PendingMasterReplacement: Identifiable, Equatable, Sendable {
    let terms: [String]
    let diff: MasterDictionaryDiff
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
    private(set) var accountDictionary: AccountDictionary?
    private(set) var accountDictionaryAccountID: String?
    var dictionarySearchText = ""
    private(set) var isRefreshingDictionary = false
    private(set) var isWritingDictionary = false
    private(set) var masterDictionary = MasterDictionary(words: [])
    var masterDictionarySearchText = ""
    private(set) var isRefreshingMasterDictionary = false
    private(set) var pendingMasterReplacement: PendingMasterReplacement?
    private(set) var isReplacingMasterDictionary = false
    private(set) var taskCancellationNotice: String?
    private var dictionaryTaskIDsByAccount: [String: String] = [:]

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
            upsertTask(task)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "无法开始同步。请稍后重试。"
        }
    }

    var filteredAccountDictionaryWords: [DictionaryWord] {
        let words = accountDictionary?.words ?? []
        let query = dictionarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return words }
        return words.filter { $0.term.localizedCaseInsensitiveContains(query) }
    }

    var filteredMasterDictionaryWords: [String] {
        let query = masterDictionarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return masterDictionary.words }
        return masterDictionary.words.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    func normalizedDictionaryTerms(from input: String) -> [String] {
        var seen = Set<String>()
        return input
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { term in
                guard !term.isEmpty else { return false }
                return seen.insert(term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted
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

    func refreshAccountDictionary(accountID: String) async {
        guard !isRefreshingDictionary else { return }
        isRefreshingDictionary = true
        defer { isRefreshingDictionary = false }
        do {
            accountDictionary = try await coreClient.accountDictionary(accountID: accountID)
            accountDictionaryAccountID = accountID
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "无法读取个人词库。请检查账号连接后重试。"
        }
    }

    func addDictionaryTerms(_ input: String, accountID: String) async {
        let terms = normalizedDictionaryTerms(from: input)
        guard !terms.isEmpty, !isWritingDictionary else { return }
        isWritingDictionary = true
        defer { isWritingDictionary = false }
        do {
            if terms.count == 1 {
                _ = try await coreClient.addWord(terms[0], accountID: accountID)
            } else {
                let outcome = try await coreClient.addWords(terms, accountID: accountID)
                if case let .task(task) = outcome { upsertTask(task) }
            }
            accountDictionary = try await coreClient.accountDictionary(accountID: accountID)
            accountDictionaryAccountID = accountID
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "无法添加词条。远端词库未更新，请重试。"
        }
    }

    func deleteDictionaryWord(_ term: String, accountID: String) async {
        guard !isWritingDictionary else { return }
        isWritingDictionary = true
        defer { isWritingDictionary = false }
        do {
            _ = try await coreClient.deleteWord(term, accountID: accountID)
            accountDictionary = try await coreClient.accountDictionary(accountID: accountID)
            accountDictionaryAccountID = accountID
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "无法删除词条。远端词库未更新，请重试。"
        }
    }

    func syncAccountDictionary(accountID: String) async {
        do {
            let task = try await coreClient.syncAccountDictionary(accountID: accountID)
            dictionaryTaskIDsByAccount[accountID] = task.id
            upsertTask(task)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "无法开始同步该账号的词库。"
        }
    }

    func dictionaryTask(for accountID: String) -> CoreTask? {
        guard let taskID = dictionaryTaskIDsByAccount[accountID] else { return nil }
        return activeTasks.first { $0.id == taskID }
    }

    func refreshMasterDictionary() async {
        guard !isRefreshingMasterDictionary else { return }
        isRefreshingMasterDictionary = true
        defer { isRefreshingMasterDictionary = false }
        do {
            masterDictionary = try await coreClient.masterDictionary()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "无法读取主词库。请稍后重试。"
        }
    }

    func prepareMasterReplacement(from input: String) async {
        let terms = normalizedDictionaryTerms(from: input)
        let existingKeys = Set(masterDictionary.words.map(dictionaryTermKey))
        let proposedKeys = Set(terms.map(dictionaryTermKey))
        let added = terms.filter { !existingKeys.contains(dictionaryTermKey($0)) }
        let removed = masterDictionary.words.filter { !proposedKeys.contains(dictionaryTermKey($0)) }
        let unchanged = terms.filter { existingKeys.contains(dictionaryTermKey($0)) }
        let diff = MasterDictionaryDiff(added: added, removed: removed, unchanged: unchanged)
        let params: JSONValue = .object(["terms": .array(terms.map(JSONValue.string))])
        let summary: JSONValue = .object([
            "title": .string("替换主词库"),
            "message": .string("新增 \(added.count) 条，移除 \(removed.count) 条，保留 \(unchanged.count) 条。"),
            "destructive": .bool(!removed.isEmpty),
        ])
        do {
            let confirmation = try await coreClient.prepareOperation(method: "master.replace", params: params, summary: summary)
            pendingMasterReplacement = .init(terms: terms, diff: diff, confirmation: confirmation)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "无法准备主词库替换。请稍后重试。"
        }
    }

    func confirmMasterReplacement() async {
        guard let pendingMasterReplacement, !isReplacingMasterDictionary else { return }
        isReplacingMasterDictionary = true
        defer { isReplacingMasterDictionary = false }
        do {
            masterDictionary = try await coreClient.replaceMasterDictionary(
                pendingMasterReplacement.terms,
                confirmationToken: pendingMasterReplacement.confirmation.token
            )
            self.pendingMasterReplacement = nil
            lastErrorMessage = nil
        } catch {
            self.pendingMasterReplacement = nil
            lastErrorMessage = "主词库替换未完成。确认可能已过期，请重试。"
        }
    }

    func cancelMasterReplacement() {
        pendingMasterReplacement = nil
    }

    func cancelTask(id: String) async {
        do {
            let result = try await coreClient.cancelTask(id: id)
            if result.cancelled { taskCancellationNotice = "将在当前账号同步结束后取消" }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "无法取消任务。任务可能已经结束。"
        }
    }

    private func dictionaryTermKey(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func upsertTask(_ task: CoreTask) {
        if let index = activeTasks.firstIndex(where: { $0.id == task.id }) {
            activeTasks[index] = task
        } else {
            activeTasks.append(task)
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
