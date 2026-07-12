import Foundation
@testable import TypelessToolkit

@MainActor
final class MockCoreClient: CoreClientProtocol {
    var overview = SystemOverview.empty
    var overviewError: Error?
    var connection = ConnectionStatus.disconnected
    var syncTask = CoreTask(
        id: "sync", type: "dictionaries.syncAll", state: .queued,
        cancellable: true, progress: nil, result: nil, error: nil
    )
    private(set) var establishConnectionCallCount = 0
    private(set) var syncAllCallCount = 0

    func getOverview() async throws -> SystemOverview {
        if let overviewError { throw overviewError }
        return overview
    }

    func establishConnection() async throws -> ConnectionStatus {
        establishConnectionCallCount += 1
        return connection
    }

    func syncAllDictionaries() async throws -> CoreTask {
        syncAllCallCount += 1
        return syncTask
    }
}
