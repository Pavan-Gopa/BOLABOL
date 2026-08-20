import Foundation

public enum BatchJobTransitionError: Error, Equatable, Sendable {
    case illegalTransition(from: BatchJobState, to: BatchJobState)
}

public enum BatchJobStateMachine {
    public static func canTransition(from: BatchJobState, to: BatchJobState) -> Bool {
        switch (from, to) {
        case (.pending, .processing),
             (.pending, .cancelled),
             (.processing, .completed),
             (.processing, .failed),
             (.processing, .cancelled),
             (.processing, .pending),
             (.processing, .blockedOutputCollision),
             (.failed, .pending),
             (.cancelled, .pending),
             (.blockedOutputCollision, .pending):
            true
        default:
            false
        }
    }

    public static func transition(_ job: inout BatchJob, to state: BatchJobState, at date: Date = Date()) throws {
        guard canTransition(from: job.state, to: state) else {
            throw BatchJobTransitionError.illegalTransition(from: job.state, to: state)
        }
        job.state = state
        job.updatedAt = date
    }
}
