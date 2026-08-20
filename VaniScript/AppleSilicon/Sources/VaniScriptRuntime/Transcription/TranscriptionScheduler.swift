import Foundation

public enum TranscriptionPriority: Sendable {
    case manual
    case background
}

/// Serializes local inference while allowing queued manual work to pass queued background work.
public actor TranscriptionScheduler {
    private struct Waiter {
        let id: UUID
        let priority: TranscriptionPriority
        let continuation: CheckedContinuation<Void, Error>
    }

    private var active = false
    private var waiters: [Waiter] = []

    public init() {}

    public func run<T: Sendable>(
        priority: TranscriptionPriority,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let id = UUID()
        try await acquire(id: id, priority: priority)
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire(id: UUID, priority: TranscriptionPriority) async throws {
        if !active {
            active = true
            return
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let waiter = Waiter(id: id, priority: priority, continuation: continuation)
                switch priority {
                case .manual:
                    let insertion = waiters.firstIndex { $0.priority == .background } ?? waiters.endIndex
                    waiters.insert(waiter, at: insertion)
                case .background:
                    waiters.append(waiter)
                }
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    private func cancel(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func release() {
        while !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.continuation.resume()
            return
        }
        active = false
    }
}
