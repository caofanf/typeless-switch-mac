import Foundation

enum DictionaryWriteOutcome: Equatable, Sendable {
    case completed(BulkImportResult)
    case task(CoreTask)
}

protocol CoreClientProtocol: Sendable {
    func getOverview() async throws -> SystemOverview
    func connectionStatus() async throws -> ConnectionStatus
    func establishConnection() async throws -> ConnectionStatus
    func versionStatus() async throws -> VersionStatus
    func acknowledgeVersion() async throws -> VersionStatus
    func listAccounts() async throws -> [Account]
    func detectCurrentAccount() async throws -> AccountCapture
    func captureCurrentAccount() async throws -> AccountCapture
    func saveCapture(id: String, nickname: String, email: String) async throws -> Account
    func deleteAccount(id: String, deleteSnapshot: Bool, confirmationToken: String) async throws -> AccountDeletionResult
    func saveSnapshot(accountID: String) async throws -> SnapshotResult
    func switchSnapshot(accountID: String) async throws -> SnapshotResult
    func accountDictionary(accountID: String) async throws -> AccountDictionary
    func masterDictionary() async throws -> MasterDictionary
    func addWord(_ term: String, accountID: String) async throws -> AddedWordResult
    func addWords(_ terms: [String], accountID: String) async throws -> DictionaryWriteOutcome
    func deleteWord(_ term: String, accountID: String) async throws -> DeletedWordResult
    func syncAccountDictionary(accountID: String) async throws -> CoreTask
    func syncAllDictionaries() async throws -> CoreTask
    func importMasterDictionary(accountID: String) async throws -> CoreTask
    func copyDictionary(from sourceID: String, to targetID: String) async throws -> CoreTask
    func replaceMasterDictionary(_ terms: [String], confirmationToken: String) async throws -> MasterDictionary
    func activeTasks() async throws -> [CoreTask]
    func cancelTask(id: String) async throws -> TaskCancellationResult
    func backupStatus() async throws -> BackupStatus
    func createBackup() async throws -> BackupStatus
    func inspectBackup(at path: String) async throws -> BackupInspection
    func exportBackup(to path: String) async throws -> PathResult
    func restoreBackup(inspectionID: String, confirmationToken: String) async throws -> CoreTask
    func diagnostics() async throws -> DiagnosticReport
    func deviceStatus() async throws -> DeviceStatus
    func resetDevice(confirmationToken: String) async throws -> CoreTask
    func patchStatus() async throws -> PatchStatus
    func applyPatch(action: String, confirmationToken: String) async throws -> CoreTask
    func prepareOperation(method: String, params: JSONValue, summary: JSONValue) async throws -> Confirmation
    func close() async
}

extension CoreClientProtocol {
    private func unavailable<T>() throws -> T { throw CoreError.transport(message: "Core client unavailable") }
    func connectionStatus() async throws -> ConnectionStatus { try unavailable() }
    func establishConnection() async throws -> ConnectionStatus { try unavailable() }
    func versionStatus() async throws -> VersionStatus { try unavailable() }
    func acknowledgeVersion() async throws -> VersionStatus { try unavailable() }
    func listAccounts() async throws -> [Account] { try unavailable() }
    func detectCurrentAccount() async throws -> AccountCapture { try unavailable() }
    func captureCurrentAccount() async throws -> AccountCapture { try unavailable() }
    func saveCapture(id: String, nickname: String, email: String) async throws -> Account { try unavailable() }
    func deleteAccount(id: String, deleteSnapshot: Bool, confirmationToken: String) async throws -> AccountDeletionResult { try unavailable() }
    func saveSnapshot(accountID: String) async throws -> SnapshotResult { try unavailable() }
    func switchSnapshot(accountID: String) async throws -> SnapshotResult { try unavailable() }
    func accountDictionary(accountID: String) async throws -> AccountDictionary { try unavailable() }
    func masterDictionary() async throws -> MasterDictionary { try unavailable() }
    func addWord(_ term: String, accountID: String) async throws -> AddedWordResult { try unavailable() }
    func addWords(_ terms: [String], accountID: String) async throws -> DictionaryWriteOutcome { try unavailable() }
    func deleteWord(_ term: String, accountID: String) async throws -> DeletedWordResult { try unavailable() }
    func syncAccountDictionary(accountID: String) async throws -> CoreTask { try unavailable() }
    func syncAllDictionaries() async throws -> CoreTask { try unavailable() }
    func importMasterDictionary(accountID: String) async throws -> CoreTask { try unavailable() }
    func copyDictionary(from sourceID: String, to targetID: String) async throws -> CoreTask { try unavailable() }
    func replaceMasterDictionary(_ terms: [String], confirmationToken: String) async throws -> MasterDictionary { try unavailable() }
    func activeTasks() async throws -> [CoreTask] { try unavailable() }
    func cancelTask(id: String) async throws -> TaskCancellationResult { try unavailable() }
    func backupStatus() async throws -> BackupStatus { try unavailable() }
    func createBackup() async throws -> BackupStatus { try unavailable() }
    func inspectBackup(at path: String) async throws -> BackupInspection { try unavailable() }
    func exportBackup(to path: String) async throws -> PathResult { try unavailable() }
    func restoreBackup(inspectionID: String, confirmationToken: String) async throws -> CoreTask { try unavailable() }
    func diagnostics() async throws -> DiagnosticReport { try unavailable() }
    func deviceStatus() async throws -> DeviceStatus { try unavailable() }
    func resetDevice(confirmationToken: String) async throws -> CoreTask { try unavailable() }
    func patchStatus() async throws -> PatchStatus { try unavailable() }
    func applyPatch(action: String, confirmationToken: String) async throws -> CoreTask { try unavailable() }
    func prepareOperation(method: String, params: JSONValue, summary: JSONValue) async throws -> Confirmation { try unavailable() }
    func close() async {}
}

struct UnavailableCoreClient: CoreClientProtocol, Sendable {
    func getOverview() async throws -> SystemOverview { .empty }
}

struct LiveCoreClient: CoreClientProtocol, Sendable {
    private let transport: any RPCTransportProtocol

    init(transport: any RPCTransportProtocol) { self.transport = transport }

    func getOverview() async throws -> SystemOverview { try await call("system.getOverview") }
    func connectionStatus() async throws -> ConnectionStatus { try await call("connection.status") }
    func establishConnection() async throws -> ConnectionStatus { try await call("connection.establish") }
    func versionStatus() async throws -> VersionStatus { try await call("version.status") }
    func acknowledgeVersion() async throws -> VersionStatus { try await call("version.acknowledge") }
    func listAccounts() async throws -> [Account] { try await call("accounts.list", as: AccountList.self).accounts }
    func detectCurrentAccount() async throws -> AccountCapture { try await call("accounts.detectCurrent") }
    func captureCurrentAccount() async throws -> AccountCapture { try await call("accounts.captureCurrent") }

    func saveCapture(id: String, nickname: String, email: String) async throws -> Account {
        try await call("accounts.saveCapture", params: object("capture_id", id, "nickname", nickname, "email", email))
    }

    func deleteAccount(id: String, deleteSnapshot: Bool, confirmationToken: String) async throws -> AccountDeletionResult {
        try await call("accounts.delete", params: .object([
            "user_id": .string(id), "delete_snapshot": .bool(deleteSnapshot), "confirmation_token": .string(confirmationToken)
        ]))
    }

    func saveSnapshot(accountID: String) async throws -> SnapshotResult {
        try await call("snapshots.save", params: object("user_id", accountID))
    }

    func switchSnapshot(accountID: String) async throws -> SnapshotResult {
        try await call("snapshots.switch", params: object("user_id", accountID))
    }

    func accountDictionary(accountID: String) async throws -> AccountDictionary {
        try await call("dictionaries.getAccount", params: object("user_id", accountID))
    }

    func masterDictionary() async throws -> MasterDictionary { try await call("master.get") }

    func addWord(_ term: String, accountID: String) async throws -> AddedWordResult {
        try await call("dictionaries.addWord", params: object("user_id", accountID, "term", term))
    }

    func addWords(_ terms: [String], accountID: String) async throws -> DictionaryWriteOutcome {
        let value = try await rawCall("dictionaries.addWords", params: .object([
            "user_id": .string(accountID), "terms": .array(terms.map(JSONValue.string))
        ]))
        if value.objectValue?["task_id"] != nil { return .task(try decode(CoreTask.self, from: value)) }
        return .completed(try decode(BulkImportResult.self, from: value))
    }

    func deleteWord(_ term: String, accountID: String) async throws -> DeletedWordResult {
        try await call("dictionaries.deleteWord", params: object("user_id", accountID, "term", term))
    }

    func syncAccountDictionary(accountID: String) async throws -> CoreTask {
        try await call("dictionaries.syncAccount", params: object("user_id", accountID))
    }

    func syncAllDictionaries() async throws -> CoreTask { try await call("dictionaries.syncAll") }
    func importMasterDictionary(accountID: String) async throws -> CoreTask { try await call("dictionaries.importMasterToAccount", params: object("user_id", accountID)) }
    func copyDictionary(from sourceID: String, to targetID: String) async throws -> CoreTask {
        try await call("dictionaries.copyBetweenAccounts", params: object("source_user_id", sourceID, "target_user_id", targetID))
    }

    func replaceMasterDictionary(_ terms: [String], confirmationToken: String) async throws -> MasterDictionary {
        try await call("master.replace", params: .object([
            "terms": .array(terms.map(JSONValue.string)), "confirmation_token": .string(confirmationToken)
        ]))
    }

    func activeTasks() async throws -> [CoreTask] { try await call("tasks.listActive", as: ActiveTaskList.self).tasks }
    func cancelTask(id: String) async throws -> TaskCancellationResult { try await call("tasks.cancel", params: object("task_id", id)) }
    func backupStatus() async throws -> BackupStatus { try await call("backup.status") }
    func createBackup() async throws -> BackupStatus { try await call("backup.create") }
    func inspectBackup(at path: String) async throws -> BackupInspection { try await call("backup.inspect", params: object("path", path)) }
    func exportBackup(to path: String) async throws -> PathResult { try await call("backup.export", params: object("path", path)) }
    func restoreBackup(inspectionID: String, confirmationToken: String) async throws -> CoreTask {
        try await call("backup.restore", params: object("inspection_id", inspectionID, "confirmation_token", confirmationToken))
    }
    func diagnostics() async throws -> DiagnosticReport { try await call("diagnostics.run") }
    func deviceStatus() async throws -> DeviceStatus { try await call("device.status") }
    func resetDevice(confirmationToken: String) async throws -> CoreTask { try await call("device.reset", params: object("confirmation_token", confirmationToken)) }
    func patchStatus() async throws -> PatchStatus { try await call("patch.status") }
    func applyPatch(action: String, confirmationToken: String) async throws -> CoreTask {
        try await call("patch.apply", params: object("action", action, "confirmation_token", confirmationToken))
    }
    func prepareOperation(method: String, params: JSONValue, summary: JSONValue) async throws -> Confirmation {
        try await call("operations.prepare", params: .object(["method": .string(method), "params": params, "summary": summary]))
    }
    func close() async { await transport.close() }

    private func call<T: Decodable>(_ method: String, params: JSONValue = .object([:]), as type: T.Type = T.self) async throws -> T {
        try decode(type, from: await rawCall(method, params: params))
    }

    private func rawCall(_ method: String, params: JSONValue = .object([:])) async throws -> JSONValue {
        do { return try await transport.call(method: method, params: params) }
        catch let IPCTransportError.remote(payload) { throw CoreError.from(payload) }
        catch let error as CoreError { throw error }
        catch { throw CoreError.transport(message: error.localizedDescription) }
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        do {
            let data = try JSONEncoder().encode(value)
            return try Self.decoder.decode(type, from: data)
        } catch let error as CoreError { throw error }
        catch { throw CoreError.decoding(message: "无法解析核心响应：\(error.localizedDescription)") }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            if let milliseconds = try? value.decode(Double.self) {
                return Date(timeIntervalSince1970: milliseconds / 1_000)
            }
            let text = try value.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid ISO 8601 date")
        }
        return decoder
    }

    private func object(_ pairs: String...) -> JSONValue {
        precondition(pairs.count.isMultiple(of: 2))
        var result: [String: JSONValue] = [:]
        for index in stride(from: 0, to: pairs.count, by: 2) { result[pairs[index]] = .string(pairs[index + 1]) }
        return .object(result)
    }
}
