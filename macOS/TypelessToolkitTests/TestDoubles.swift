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
    var capture = AccountCapture(captureID: "capture", userID: "u1", nickname: "", email: "", role: "", capturedAt: nil)
    var savedAccount: Account?
    var accounts: [Account] = []
    var confirmation = Confirmation(token: "confirm", expiresAt: .distantFuture, summary: .object([:]))
    var onEstablishConnection: (() -> Void)?
    var onCaptureCurrentAccount: (() -> Void)?
    var onSaveCapture: (() -> Void)?
    private(set) var establishConnectionCallCount = 0
    private(set) var syncAllCallCount = 0
    private(set) var savedCaptureID: String?
    private(set) var preparedMethods: [String] = []
    private(set) var deleteAccountCallCount = 0
    private(set) var switchSnapshotCallCount = 0
    private(set) var deletedAccountID: String?
    private(set) var switchedAccountID: String?
    private(set) var usedConfirmationToken: String?

    func getOverview() async throws -> SystemOverview {
        if let overviewError { throw overviewError }
        return overview
    }

    func establishConnection() async throws -> ConnectionStatus {
        establishConnectionCallCount += 1
        onEstablishConnection?()
        return connection
    }

    func listAccounts() async throws -> [Account] { accounts }

    func captureCurrentAccount() async throws -> AccountCapture {
        onCaptureCurrentAccount?()
        return capture
    }

    func saveCapture(id: String, nickname: String, email: String) async throws -> Account {
        savedCaptureID = id
        onSaveCapture?()
        guard let savedAccount else { throw CoreError.transport(message: "missing saved account") }
        accounts = [savedAccount]
        return savedAccount
    }

    func prepareOperation(method: String, params: JSONValue, summary: JSONValue) async throws -> Confirmation {
        preparedMethods.append(method)
        return confirmation
    }

    func deleteAccount(id: String, deleteSnapshot: Bool, confirmationToken: String) async throws -> AccountDeletionResult {
        deleteAccountCallCount += 1
        deletedAccountID = id
        usedConfirmationToken = confirmationToken
        accounts.removeAll { $0.id == id }
        return .init(deleted: true, userID: id)
    }

    func switchSnapshot(accountID: String, confirmationToken: String) async throws -> SnapshotResult {
        switchSnapshotCallCount += 1
        switchedAccountID = accountID
        usedConfirmationToken = confirmationToken
        return .init(userID: accountID, hasSnapshot: nil, switched: true)
    }

    func syncAllDictionaries() async throws -> CoreTask {
        syncAllCallCount += 1
        return syncTask
    }
}
