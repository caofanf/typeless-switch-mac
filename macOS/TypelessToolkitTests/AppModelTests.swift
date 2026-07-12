import XCTest
@testable import TypelessToolkit

@MainActor
final class AppModelTests: XCTestCase {
    func testDefaultSelectionIsOverview() {
        let model = AppModel(coreClient: MockCoreClient())

        XCTAssertEqual(model.selection, .overview)
        XCTAssertEqual(model.connectionState, .disconnected)
    }

    func testRefreshOverviewUpdatesAllLightweightStatus() async {
        let client = MockCoreClient()
        client.overview = makeOverview()
        let model = AppModel(coreClient: client)

        await model.refreshOverview()

        XCTAssertEqual(model.overview.accountCount, 1)
        XCTAssertEqual(model.connectionState, .connected)
        XCTAssertEqual(model.overview.backup.status, .backedUp)
        XCTAssertEqual(model.overview.version.current, "1.2.3")
        XCTAssertEqual(model.activeTasks.map(\.id), ["task-1"])
        XCTAssertFalse(model.isStale)
        XCTAssertNil(model.lastErrorMessage)
    }

    func testEstablishConnectionRefreshesOverviewAfterConnecting() async {
        let client = MockCoreClient()
        client.connection = .init(state: .connected, port: 9222, cdpReachable: true)
        client.overview = makeOverview()
        let model = AppModel(coreClient: client)

        await model.establishConnection()

        XCTAssertEqual(client.establishConnectionCallCount, 1)
        XCTAssertEqual(model.connectionState, .connected)
        XCTAssertEqual(model.overview.accountCount, 1)
        XCTAssertNil(model.lastErrorMessage)
    }

    func testSyncAllAddsReturnedTaskToActivity() async {
        let client = MockCoreClient()
        client.syncTask = .init(
            id: "sync-1",
            type: "dictionaries.syncAll",
            state: .queued,
            cancellable: true,
            progress: nil,
            result: nil,
            error: nil
        )
        let model = AppModel(coreClient: client)

        await model.syncAllDictionaries()

        XCTAssertEqual(client.syncAllCallCount, 1)
        XCTAssertEqual(model.activeTasks.map(\.id), ["sync-1"])
        XCTAssertNil(model.lastErrorMessage)
    }

    func testRefreshOverviewFailureKeepsLastSnapshotAndMarksItStale() async {
        let client = MockCoreClient()
        client.overview = makeOverview()
        let model = AppModel(coreClient: client)
        await model.refreshOverview()
        let lastSnapshot = model.overview

        client.overviewError = CoreError.transport(message: "offline")
        await model.refreshOverview()

        XCTAssertEqual(model.overview, lastSnapshot)
        XCTAssertEqual(model.connectionState, .connected)
        XCTAssertEqual(model.activeTasks.map(\.id), ["task-1"])
        XCTAssertTrue(model.isStale)
        XCTAssertNotNil(model.lastErrorMessage)
    }

    func testAddAccountWorkflowMovesThroughExpectedPhasesAndKeepsCaptureSanitized() async throws {
        let client = MockCoreClient()
        client.connection = .init(state: .connected, port: 9222, cdpReachable: true)
        client.capture = AccountCapture(
            captureID: "capture-1",
            userID: "u2",
            nickname: "新账号",
            email: "new@example.com",
            role: "pro",
            capturedAt: nil
        )
        client.savedAccount = makeAccount(id: "u2", nickname: "新账号")
        let model = AppModel(coreClient: client)
        var phases: [AddAccountPhase] = []
        client.onEstablishConnection = { phases.append(model.addAccountPhase) }
        client.onCaptureCurrentAccount = { phases.append(model.addAccountPhase) }
        client.onSaveCapture = { phases.append(model.addAccountPhase) }

        await model.beginAddAccount()
        phases.append(model.addAccountPhase)
        XCTAssertEqual(model.pendingAccountCapture?.userID, "u2")

        let encodedCapture = try JSONEncoder().encode(model.pendingAccountCapture)
        let encodedText = String(decoding: encodedCapture, as: UTF8.self)
        XCTAssertFalse(encodedText.localizedCaseInsensitiveContains("token"))

        await model.savePendingAccount(nickname: "新账号", email: "new@example.com")
        phases.append(model.addAccountPhase)

        XCTAssertEqual(phases, [.establishingConnection, .capturing, .reviewing, .saving, .completed])
        XCTAssertEqual(client.savedCaptureID, "capture-1")
        XCTAssertEqual(model.accounts.map(\.id), ["u2"])
    }

    func testDeleteAccountIsPreparedBeforeExecution() async {
        let client = MockCoreClient()
        client.confirmation = makeConfirmation(summary: .object([
            "title": .string("删除账号"),
            "message": .string("同时删除本地快照")
        ]))
        client.accounts = [makeAccount(id: "u1", nickname: "待删除")]
        let model = AppModel(coreClient: client)

        await model.prepareDeleteAccount(accountID: "u1", deleteSnapshot: true)

        XCTAssertEqual(client.preparedMethods, ["accounts.delete"])
        XCTAssertEqual(client.deleteAccountCallCount, 0)
        XCTAssertEqual(model.pendingAccountOperation?.kind, .delete)

        await model.confirmPendingAccountOperation()

        XCTAssertEqual(client.deleteAccountCallCount, 1)
        XCTAssertEqual(client.deletedAccountID, "u1")
        XCTAssertEqual(client.usedConfirmationToken, "confirm-1")
        XCTAssertTrue(model.accounts.isEmpty)
    }

    func testSwitchAccountIsPreparedBeforeExecution() async {
        let client = MockCoreClient()
        client.confirmation = makeConfirmation(summary: .object([
            "title": .string("切换账号"),
            "message": .string("Typeless 将重新启动")
        ]))
        client.accounts = [makeAccount(id: "u1", nickname: "目标账号")]
        let model = AppModel(coreClient: client)

        await model.prepareSwitchAccount(accountID: "u1")

        XCTAssertEqual(client.preparedMethods, ["snapshots.switch"])
        XCTAssertEqual(client.switchSnapshotCallCount, 0)
        XCTAssertEqual(model.pendingAccountOperation?.kind, .switchSnapshot)

        await model.confirmPendingAccountOperation()

        XCTAssertEqual(client.switchSnapshotCallCount, 1)
        XCTAssertEqual(client.switchedAccountID, "u1")
        XCTAssertEqual(client.usedConfirmationToken, "confirm-1")
    }

    func testAccountDictionarySearchMatchesTermsCaseInsensitively() async {
        let client = MockCoreClient()
        client.accountDictionaryValue = .init(words: [
            .init(term: "SwiftUI", auto: false),
            .init(term: "Node.js", auto: true),
            .init(term: "苹果原生", auto: false),
        ])
        let model = AppModel(coreClient: client)

        await model.refreshAccountDictionary(accountID: "u1")
        model.dictionarySearchText = "swift"

        XCTAssertEqual(model.filteredAccountDictionaryWords.map(\.term), ["SwiftUI"])
    }

    func testDictionaryBulkInputTrimsDropsEmptyLinesAndDeduplicates() {
        let model = AppModel(coreClient: MockCoreClient())

        let terms = model.normalizedDictionaryTerms(from: "  SwiftUI  \n\nNode.js\nSwiftUI\n node.js \n苹果原生")

        XCTAssertEqual(terms, ["SwiftUI", "Node.js", "苹果原生"])
    }

    func testDeletingDictionaryWordWaitsForServerThenReloadsRemoteDictionary() async {
        let client = MockCoreClient()
        client.accountDictionaryValue = .init(words: [
            .init(term: "保留", auto: false),
            .init(term: "删除我", auto: false),
        ])
        let model = AppModel(coreClient: client)
        await model.refreshAccountDictionary(accountID: "u1")
        client.onDeleteWord = {
            XCTAssertEqual(model.accountDictionary?.words.map(\.term), ["保留", "删除我"])
            client.accountDictionaryValue = .init(words: [.init(term: "保留", auto: false)])
        }

        await model.deleteDictionaryWord("删除我", accountID: "u1")

        XCTAssertEqual(client.deletedDictionaryTerms, ["删除我"])
        XCTAssertEqual(client.accountDictionaryCallCount, 2)
        XCTAssertEqual(model.accountDictionary?.words.map(\.term), ["保留"])
    }

    func testMasterReplacementShowsDiffAndRequiresConfirmationBeforeWriting() async {
        let client = MockCoreClient()
        client.masterDictionaryValue = .init(words: ["保留", "移除"])
        client.confirmation = makeConfirmation(summary: .object(["title": .string("替换主词库")]))
        let model = AppModel(coreClient: client)
        await model.refreshMasterDictionary()

        await model.prepareMasterReplacement(from: "保留\n新增\n新增")

        XCTAssertEqual(model.pendingMasterReplacement?.diff.added, ["新增"])
        XCTAssertEqual(model.pendingMasterReplacement?.diff.removed, ["移除"])
        XCTAssertEqual(model.pendingMasterReplacement?.diff.unchanged, ["保留"])
        XCTAssertEqual(client.preparedMethods, ["master.replace"])
        XCTAssertEqual(client.replaceMasterCallCount, 0)

        client.masterDictionaryValue = .init(words: ["保留", "新增"])
        await model.confirmMasterReplacement()

        XCTAssertEqual(client.replaceMasterCallCount, 1)
        XCTAssertEqual(client.replacedMasterTerms, ["保留", "新增"])
        XCTAssertEqual(client.usedConfirmationToken, "confirm-1")
        XCTAssertEqual(model.masterDictionary.words, ["保留", "新增"])
    }

    func testMasterReplacementHandlesExistingTermsThatDifferOnlyByCase() async {
        let client = MockCoreClient()
        client.masterDictionaryValue = .init(words: ["Swift", "swift", "移除"])
        client.confirmation = makeConfirmation(summary: .object(["title": .string("替换主词库")]))
        let model = AppModel(coreClient: client)
        await model.refreshMasterDictionary()

        await model.prepareMasterReplacement(from: "SWIFT\n新增")

        XCTAssertEqual(model.pendingMasterReplacement?.diff.added, ["新增"])
        XCTAssertEqual(model.pendingMasterReplacement?.diff.removed, ["移除"])
        XCTAssertEqual(model.pendingMasterReplacement?.diff.unchanged, ["SWIFT"])
        XCTAssertEqual(client.preparedMethods, ["master.replace"])
    }

    func testSingleAccountSyncAppearsInGlobalTaskProgress() async {
        let client = MockCoreClient()
        client.accountSyncTask = .init(
            id: "sync-u1", type: "sync-account", state: .running, cancellable: true,
            progress: .init(phase: "syncing", completed: 0, total: 1, message: "正在同步"),
            result: nil, error: nil
        )
        let model = AppModel(coreClient: client)

        await model.syncAccountDictionary(accountID: "u1")

        XCTAssertEqual(client.syncedAccountIDs, ["u1"])
        XCTAssertEqual(model.activeTasks.map(\.id), ["sync-u1"])
        XCTAssertEqual(model.dictionaryTask(for: "u1")?.progress?.message, "正在同步")
    }

    func testCancellingSyncAllRequestsBoundaryCancellationWithoutOptimisticRemoval() async {
        let client = MockCoreClient()
        let task = CoreTask(
            id: "sync-all", type: "sync-all", state: .running, cancellable: true,
            progress: .init(phase: "syncing", completed: 1, total: 3, message: "正在同步 1/3"),
            result: nil, error: nil
        )
        client.overview = makeOverview(activeTasks: [task])
        let model = AppModel(coreClient: client)
        await model.refreshOverview()

        await model.cancelTask(id: "sync-all")

        XCTAssertEqual(client.cancelledTaskIDs, ["sync-all"])
        XCTAssertEqual(model.activeTasks.map(\.id), ["sync-all"])
        XCTAssertEqual(model.taskCancellationNotice, "将在当前账号同步结束后取消")
    }

    private func makeConfirmation(summary: JSONValue) -> Confirmation {
        Confirmation(token: "confirm-1", expiresAt: Date(timeIntervalSince1970: 4_000_000_000), summary: summary)
    }

    private func makeAccount(id: String, nickname: String) -> Account {
        let data = Data(#"{"user_id":"\#(id)","nickname":"\#(nickname)","has_snapshot":true}"#.utf8)
        return try! JSONDecoder().decode(Account.self, from: data)
    }

    private func makeOverview(activeTasks: [CoreTask]? = nil) -> SystemOverview {
        SystemOverview(
            connection: .init(state: .connected, port: 9222, cdpReachable: true),
            accounts: [makeAccount()],
            version: .init(current: "1.2.3", lastSeen: "1.2.3", drifted: false, recordedAt: nil),
            backup: .init(
                status: .backedUp,
                backedUp: true,
                hasData: true,
                sources: [],
                latestDataModifiedAt: nil,
                latestBackup: nil,
                backupDirectory: "/tmp/backups",
                backupPath: "/tmp/backups/latest"
            ),
            patch: .init(exists: true, patched: true, detectedFile: nil, filePath: nil, replacementsSource: nil, hasBackup: true, error: nil),
            activeTasks: activeTasks ?? [
                .init(id: "task-1", type: "dictionaries.syncAll", state: .running, cancellable: true, progress: nil, result: nil, error: nil)
            ]
        )
    }

    private func makeAccount() -> Account {
        let data = Data(#"{"user_id":"u1","nickname":"测试账号","has_snapshot":true}"#.utf8)
        return try! JSONDecoder().decode(Account.self, from: data)
    }
}
