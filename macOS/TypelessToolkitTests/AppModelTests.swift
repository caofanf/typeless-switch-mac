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

    private func makeConfirmation(summary: JSONValue) -> Confirmation {
        Confirmation(token: "confirm-1", expiresAt: Date(timeIntervalSince1970: 4_000_000_000), summary: summary)
    }

    private func makeAccount(id: String, nickname: String) -> Account {
        let data = Data(#"{"user_id":"\#(id)","nickname":"\#(nickname)","has_snapshot":true}"#.utf8)
        return try! JSONDecoder().decode(Account.self, from: data)
    }

    private func makeOverview() -> SystemOverview {
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
            activeTasks: [
                .init(id: "task-1", type: "dictionaries.syncAll", state: .running, cancellable: true, progress: nil, result: nil, error: nil)
            ]
        )
    }

    private func makeAccount() -> Account {
        let data = Data(#"{"user_id":"u1","nickname":"测试账号","has_snapshot":true}"#.utf8)
        return try! JSONDecoder().decode(Account.self, from: data)
    }
}
