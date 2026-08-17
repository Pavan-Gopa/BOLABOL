import Foundation

/// Errors encountered when preparing the application for safe update and relaunch.
public enum UpdateRelaunchGateError: LocalizedError, Equatable, Sendable {
    case recordingActive
    case quiescenceTimeout
    case quiescenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .recordingActive:
            return "Cannot install update while audio recording is in progress. Please stop recording and try again."
        case .quiescenceTimeout:
            return "Timed out waiting for active tasks to safely finish before updating."
        case .quiescenceFailed(let reason):
            return "Failed to prepare application for update: \(reason)"
        }
    }
}

/// Coordinates safety checks, quiescence, and state preservation before an update relaunch.
///
/// Invariants:
/// - Refuses installation while audio recording is active.
/// - Runs all registered async quiescence / flush handlers within a bounded timeout.
/// - Never force-quits or deletes user data.
@MainActor
public final class UpdateRelaunchGate: ObservableObject {
    public static let shared = UpdateRelaunchGate()

    private var recordingCheckers: [UUID: @MainActor () -> Bool] = [:]
    private var quiescenceHandlers: [UUID: @Sendable () async throws -> Void] = [:]
    public let defaultTimeout: TimeInterval

    public init(timeout: TimeInterval = 5.0) {
        self.defaultTimeout = timeout
    }

    /// Registers a provider that reports whether audio recording is currently active.
    @discardableResult
    public func registerRecordingChecker(
        id: UUID = UUID(),
        _ checker: @escaping @MainActor () -> Bool
    ) -> UUID {
        recordingCheckers[id] = checker
        return id
    }

    /// Unregisters an active recording checker.
    public func unregisterRecordingChecker(_ id: UUID) {
        recordingCheckers.removeValue(forKey: id)
    }

    /// Registers an async quiescence / flush handler to be executed before update relaunch.
    @discardableResult
    public func registerQuiescenceHandler(
        id: UUID = UUID(),
        _ handler: @escaping @Sendable () async throws -> Void
    ) -> UUID {
        quiescenceHandlers[id] = handler
        return id
    }

    /// Unregisters a quiescence handler.
    public func unregisterQuiescenceHandler(_ id: UUID) {
        quiescenceHandlers.removeValue(forKey: id)
    }

    /// Returns true if any registered checker reports active recording.
    public var isRecordingActive: Bool {
        for checker in recordingCheckers.values {
            if checker() {
                return true
            }
        }
        return false
    }

    /// Prepares the application for update relaunch.
    ///
    /// Throws `UpdateRelaunchGateError.recordingActive` if audio recording is in progress.
    /// Executes all registered quiescence handlers concurrently with a bounded timeout.
    public func prepareForUpdateRelaunch(timeout: TimeInterval? = nil) async throws {
        if isRecordingActive {
            throw UpdateRelaunchGateError.recordingActive
        }

        let handlers = Array(quiescenceHandlers.values)
        guard !handlers.isEmpty else {
            return
        }

        let effectiveTimeout = timeout ?? defaultTimeout

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let nanoseconds = UInt64(max(0.01, effectiveTimeout) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw UpdateRelaunchGateError.quiescenceTimeout
            }

            group.addTask {
                for handler in handlers {
                    try await handler()
                }
            }

            // Await whichever finishes first: handlers completing or timeout throwing
            try await group.next()
            group.cancelAll()
        }
    }
}
