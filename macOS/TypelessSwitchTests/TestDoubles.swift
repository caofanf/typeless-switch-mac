import Foundation
@testable import TypelessSwitch

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
    var captureError: Error?
    var savedAccount: Account?
    var accounts: [Account] = []
    var confirmation = Confirmation(token: "confirm", expiresAt: .distantFuture, summary: .object([:]))
    var accountDictionaryValue = AccountDictionary(words: [])
    var masterDictionaryValue = MasterDictionary(words: [])
    var accountSyncTask = CoreTask(id: "sync-account", type: "sync-account", state: .queued, cancellable: true, progress: nil, result: nil, error: nil)
    var backupInspection = BackupInspection(
        inspectionID: "inspection-1",
        expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
        summary: .init(type: "typeless-switch-macos-runtime-backup", version: 1, createdAt: nil, fileCount: 3, size: 1_024)
    )
    var restoreTask = CoreTask(id: "restore-1", type: "backup-restore", state: .succeeded, cancellable: false, progress: nil, result: nil, error: nil)
    var deviceResetTask = CoreTask(id: "reset-1", type: "device-reset", state: .queued, cancellable: true, progress: nil, result: nil, error: nil)
    var patchTask = CoreTask(id: "patch-1", type: "patch", state: .queued, cancellable: true, progress: nil, result: nil, error: nil)
    var backupStatusValue = SystemOverview.empty.backup
    var exportedPath = PathResult(path: "/tmp/export.json")
    var diagnosticReportValue: DiagnosticReport?
    var deviceStatusValue = DeviceStatus(connection: .disconnected, backup: SystemOverview.empty.backup)
    var patchStatusValue = SystemOverview.empty.patch
    var versionStatusValue = SystemOverview.empty.version
    var restoreError: Error?
    var onDeleteWord: (() -> Void)?
    var onEstablishConnection: (() -> Void)?
    var onCaptureCurrentAccount: (() -> Void)?
    var onSaveCapture: (() -> Void)?
    var onInspectBackup: (() -> Void)?
    var onPrepareOperation: ((String) -> Void)?
    var onRestoreBackup: (() -> Void)?
    private(set) var establishConnectionCallCount = 0
    private(set) var syncAllCallCount = 0
    private(set) var savedCaptureID: String?
    private(set) var preparedMethods: [String] = []
    private(set) var deleteAccountCallCount = 0
    private(set) var switchSnapshotCallCount = 0
    private(set) var deletedAccountID: String?
    private(set) var switchedAccountID: String?
    private(set) var usedConfirmationToken: String?
    private(set) var accountDictionaryCallCount = 0
    private(set) var deletedDictionaryTerms: [String] = []
    private(set) var syncedAccountIDs: [String] = []
    private(set) var replaceMasterCallCount = 0
    private(set) var replacedMasterTerms: [String] = []
    private(set) var cancelledTaskIDs: [String] = []
    private(set) var inspectedBackupPaths: [String] = []
    private(set) var restoredInspectionIDs: [String] = []
    private(set) var resetDeviceCallCount = 0
    private(set) var patchApplyActions: [String] = []
    private(set) var createBackupCallCount = 0
    private(set) var exportedBackupPaths: [String] = []
    private(set) var diagnosticsCallCount = 0
    private(set) var getOverviewCallCount = 0
    private(set) var acknowledgeVersionCallCount = 0

    func getOverview() async throws -> SystemOverview {
        getOverviewCallCount += 1
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
        if let captureError { throw captureError }
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
        onPrepareOperation?(method)
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

    func accountDictionary(accountID: String) async throws -> AccountDictionary {
        accountDictionaryCallCount += 1
        return accountDictionaryValue
    }

    func masterDictionary() async throws -> MasterDictionary { masterDictionaryValue }

    func deleteWord(_ term: String, accountID: String) async throws -> DeletedWordResult {
        deletedDictionaryTerms.append(term)
        onDeleteWord?()
        return .init(term: term, deleted: true)
    }

    func syncAccountDictionary(accountID: String) async throws -> CoreTask {
        syncedAccountIDs.append(accountID)
        return accountSyncTask
    }

    func replaceMasterDictionary(_ terms: [String], confirmationToken: String) async throws -> MasterDictionary {
        replaceMasterCallCount += 1
        replacedMasterTerms = terms
        usedConfirmationToken = confirmationToken
        return masterDictionaryValue
    }

    func backupStatus() async throws -> BackupStatus { backupStatusValue }

    func createBackup() async throws -> BackupStatus {
        createBackupCallCount += 1
        return backupStatusValue
    }

    func exportBackup(to path: String) async throws -> PathResult {
        exportedBackupPaths.append(path)
        return exportedPath
    }

    func diagnostics() async throws -> DiagnosticReport {
        diagnosticsCallCount += 1
        guard let diagnosticReportValue else { throw CoreError.transport(message: "missing diagnostics") }
        return diagnosticReportValue
    }

    func deviceStatus() async throws -> DeviceStatus { deviceStatusValue }
    func patchStatus() async throws -> PatchStatus { patchStatusValue }
    func versionStatus() async throws -> VersionStatus { versionStatusValue }

    func acknowledgeVersion() async throws -> VersionStatus {
        acknowledgeVersionCallCount += 1
        return versionStatusValue
    }

    func inspectBackup(at path: String) async throws -> BackupInspection {
        inspectedBackupPaths.append(path)
        onInspectBackup?()
        return backupInspection
    }

    func restoreBackup(inspectionID: String, confirmationToken: String) async throws -> CoreTask {
        restoredInspectionIDs.append(inspectionID)
        usedConfirmationToken = confirmationToken
        onRestoreBackup?()
        if let restoreError { throw restoreError }
        return restoreTask
    }

    func resetDevice(confirmationToken: String) async throws -> CoreTask {
        resetDeviceCallCount += 1
        usedConfirmationToken = confirmationToken
        return deviceResetTask
    }

    func applyPatch(action: String, confirmationToken: String) async throws -> CoreTask {
        patchApplyActions.append(action)
        usedConfirmationToken = confirmationToken
        return patchTask
    }

    func cancelTask(id: String) async throws -> TaskCancellationResult {
        cancelledTaskIDs.append(id)
        return .init(cancelled: true)
    }

    func syncAllDictionaries() async throws -> CoreTask {
        syncAllCallCount += 1
        return syncTask
    }
}

@MainActor
final class MockNotificationCenter: AppNotificationDelivering {
    struct Delivered: Equatable {
        let title: String
        let body: String?
    }

    private(set) var delivered: [Delivered] = []

    func deliver(title: String, body: String?) async {
        delivered.append(.init(title: title, body: body))
    }
}
