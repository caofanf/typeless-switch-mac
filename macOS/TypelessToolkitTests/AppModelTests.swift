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
