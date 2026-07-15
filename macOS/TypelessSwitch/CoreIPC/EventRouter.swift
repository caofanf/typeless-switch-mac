import Foundation

struct CoreEvent: Equatable, Sendable {
    enum Kind: String, Sendable {
        case taskStarted = "task.started"
        case taskProgress = "task.progress"
        case taskSucceeded = "task.succeeded"
        case taskFailed = "task.failed"
        case taskCancelled = "task.cancelled"
    }

    let kind: Kind
    let taskID: String
    let payload: JSONValue

    init?(notification: JSONRPCNotification) {
        guard let kind = Kind(rawValue: notification.method) else { return nil }
        let payload = notification.params ?? .object([:])
        guard let taskID = payload.objectValue?["task_id"]?.stringValue else { return nil }
        self.kind = kind
        self.taskID = taskID
        self.payload = payload
    }
}

final class EventRouter: @unchecked Sendable {
    let events: AsyncStream<CoreEvent>

    private let continuation: AsyncStream<CoreEvent>.Continuation
    private var routingTask: Task<Void, Never>?

    init(notifications: AsyncStream<JSONRPCNotification>) {
        let stream = AsyncStream<CoreEvent>.makeStream()
        self.events = stream.stream
        self.continuation = stream.continuation
        self.routingTask = Task { [continuation = stream.continuation] in
            for await notification in notifications {
                guard !Task.isCancelled else { break }
                if let event = CoreEvent(notification: notification) {
                    continuation.yield(event)
                }
            }
            continuation.finish()
        }
    }

    deinit {
        routingTask?.cancel()
        continuation.finish()
    }
}
