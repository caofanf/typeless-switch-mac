import Foundation

enum CoreTaskState: String, Codable, Sendable {
    case queued, running, succeeded, failed, cancelled
}

struct CoreTaskProgress: Codable, Equatable, Sendable {
    var phase: String?
    var completed: Double?
    var total: Double?
    var message: String?

    var fractionCompleted: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return min(max(completed / total, 0), 1)
    }
}

struct CoreTask: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let type: String
    var state: CoreTaskState
    var cancellable: Bool
    var progress: CoreTaskProgress?
    var result: JSONValue?
    var error: JSONValue?

    enum CodingKeys: String, CodingKey {
        case id = "task_id"
        case type, state, cancellable, progress, result, error
    }
}

struct TaskCancellationResult: Codable, Equatable, Sendable { let cancelled: Bool }
