import Foundation

struct CoreErrorDetails: Equatable, Sendable {
    var recoverable: Bool
    var suggestedAction: String?
    var context: JSONValue
}

enum CoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidRequest(message: String, details: CoreErrorDetails)
    case unsupportedProtocol(message: String, details: CoreErrorDetails)
    case coreProcessExited(message: String, details: CoreErrorDetails)
    case managementConnectionRequired(message: String, details: CoreErrorDetails)
    case currentAccountUnavailable(message: String, details: CoreErrorDetails)
    case captureExpired(message: String, details: CoreErrorDetails)
    case accountNotFound(message: String, details: CoreErrorDetails)
    case tokenExpired(message: String, details: CoreErrorDetails)
    case snapshotNotFound(message: String, details: CoreErrorDetails)
    case backupInvalid(message: String, details: CoreErrorDetails)
    case backupChanged(message: String, details: CoreErrorDetails)
    case restoreRecoveryRequired(message: String, details: CoreErrorDetails)
    case typelessNotInstalled(message: String, details: CoreErrorDetails)
    case typelessVersionDrifted(message: String, details: CoreErrorDetails)
    case patchFailedRolledBack(message: String, details: CoreErrorDetails)
    case patchRecoveryRequired(message: String, details: CoreErrorDetails)
    case confirmationRequired(message: String, details: CoreErrorDetails)
    case operationConflict(message: String, details: CoreErrorDetails)
    case permissionDenied(message: String, details: CoreErrorDetails)
    case networkUnavailable(message: String, details: CoreErrorDetails)
    case internalError(message: String, details: CoreErrorDetails)
    case transport(message: String)
    case decoding(message: String)
    case unknown(code: String, message: String, details: CoreErrorDetails)

    var errorDescription: String? {
        switch self {
        case let .transport(message), let .decoding(message): message
        case let .unknown(_, message, _): message
        default: messageAndDetails.message
        }
    }

    var details: CoreErrorDetails? {
        switch self {
        case .transport, .decoding: nil
        case let .unknown(_, _, details): details
        default: messageAndDetails.details
        }
    }

    static func from(_ payload: JSONRPCErrorPayload) -> CoreError {
        let details = CoreErrorDetails(json: payload.details)
        return switch payload.code {
        case "INVALID_REQUEST": .invalidRequest(message: payload.message, details: details)
        case "UNSUPPORTED_PROTOCOL": .unsupportedProtocol(message: payload.message, details: details)
        case "CORE_PROCESS_EXITED": .coreProcessExited(message: payload.message, details: details)
        case "MANAGEMENT_CONNECTION_REQUIRED": .managementConnectionRequired(message: payload.message, details: details)
        case "CURRENT_ACCOUNT_UNAVAILABLE": .currentAccountUnavailable(message: payload.message, details: details)
        case "CAPTURE_EXPIRED": .captureExpired(message: payload.message, details: details)
        case "ACCOUNT_NOT_FOUND": .accountNotFound(message: payload.message, details: details)
        case "TOKEN_EXPIRED": .tokenExpired(message: payload.message, details: details)
        case "SNAPSHOT_NOT_FOUND": .snapshotNotFound(message: payload.message, details: details)
        case "BACKUP_INVALID": .backupInvalid(message: payload.message, details: details)
        case "BACKUP_CHANGED": .backupChanged(message: payload.message, details: details)
        case "RESTORE_RECOVERY_REQUIRED": .restoreRecoveryRequired(message: payload.message, details: details)
        case "TYPELESS_NOT_INSTALLED": .typelessNotInstalled(message: payload.message, details: details)
        case "TYPELESS_VERSION_DRIFTED": .typelessVersionDrifted(message: payload.message, details: details)
        case "PATCH_FAILED_ROLLED_BACK": .patchFailedRolledBack(message: payload.message, details: details)
        case "PATCH_RECOVERY_REQUIRED": .patchRecoveryRequired(message: payload.message, details: details)
        case "CONFIRMATION_REQUIRED": .confirmationRequired(message: payload.message, details: details)
        case "OPERATION_CONFLICT": .operationConflict(message: payload.message, details: details)
        case "PERMISSION_DENIED": .permissionDenied(message: payload.message, details: details)
        case "NETWORK_UNAVAILABLE": .networkUnavailable(message: payload.message, details: details)
        case "INTERNAL_ERROR": .internalError(message: payload.message, details: details)
        default: .unknown(code: payload.code, message: payload.message, details: details)
        }
    }

    private var messageAndDetails: (message: String, details: CoreErrorDetails) {
        switch self {
        case let .invalidRequest(m, d), let .unsupportedProtocol(m, d), let .coreProcessExited(m, d),
             let .managementConnectionRequired(m, d), let .currentAccountUnavailable(m, d),
             let .captureExpired(m, d), let .accountNotFound(m, d), let .tokenExpired(m, d),
             let .snapshotNotFound(m, d), let .backupInvalid(m, d), let .backupChanged(m, d),
             let .restoreRecoveryRequired(m, d), let .typelessNotInstalled(m, d),
             let .typelessVersionDrifted(m, d), let .patchFailedRolledBack(m, d),
             let .patchRecoveryRequired(m, d), let .confirmationRequired(m, d),
             let .operationConflict(m, d), let .permissionDenied(m, d),
             let .networkUnavailable(m, d), let .internalError(m, d): (m, d)
        case let .unknown(_, m, d): (m, d)
        case let .transport(m), let .decoding(m): (m, .init(recoverable: false, suggestedAction: nil, context: .object([:])))
        }
    }
}

private extension CoreErrorDetails {
    init(json: JSONValue?) {
        let object = json?.objectValue ?? [:]
        self.init(
            recoverable: object["recoverable"] == .bool(true),
            suggestedAction: object["suggested_action"]?.stringValue,
            context: object["context"] ?? .object([:])
        )
    }
}
