import Foundation

@MainActor
public final class HotkeySessionCoordinator {
    public enum Phase: Equatable {
        case idle
        case recording(UUID)
        case processing(UUID)
    }

    public static let shared = HotkeySessionCoordinator()

    public private(set) var phase: Phase
    /// Timeout for stuck **processing** sessions only.
    /// Active recording never expires — users may dictate for many minutes.
    private let processingTimeout: TimeInterval
    private var lastTransitionAt: Date

    public init(
        phase: Phase = .idle,
        sessionTimeout: TimeInterval = 900,
        lastTransitionAt: Date = .distantPast
    ) {
        self.phase = phase
        // Keep the historical parameter name for call sites/tests, but apply it
        // only to stuck processing — never to live recording.
        self.processingTimeout = sessionTimeout
        self.lastTransitionAt = lastTransitionAt
    }

    @discardableResult
    public func beginRecording(
        ownerID: UUID,
        now: Date = .now
    ) -> Bool {
        resetExpiredProcessingIfNeeded(now: now)
        guard case .idle = phase else { return false }
        phase = .recording(ownerID)
        lastTransitionAt = now
        return true
    }

    @discardableResult
    public func beginProcessing(
        ownerID: UUID,
        now: Date = .now
    ) -> Bool {
        resetExpiredProcessingIfNeeded(now: now)
        guard phase == .recording(ownerID) else { return false }
        phase = .processing(ownerID)
        lastTransitionAt = now
        return true
    }

    /// Recovers when audio is still capturing but the session phase was lost
    /// (legacy timeout, crash recovery path, multi-window race). Only allowed
    /// from `.idle` so another owner's active session cannot be stolen.
    @discardableResult
    public func reclaimOrphanedRecordingForStop(
        ownerID: UUID,
        now: Date = .now
    ) -> Bool {
        guard case .idle = phase else { return false }
        phase = .processing(ownerID)
        lastTransitionAt = now
        return true
    }

    public func finish(
        ownerID: UUID,
        now: Date = .now
    ) {
        guard isOwned(by: ownerID) else { return }
        phase = .idle
        lastTransitionAt = now
    }

    public func reset(now: Date = .now) {
        phase = .idle
        lastTransitionAt = now
    }

    public func isOwned(by ownerID: UUID) -> Bool {
        switch phase {
        case .idle:
            false
        case .recording(let currentOwner), .processing(let currentOwner):
            currentOwner == ownerID
        }
    }

    private func resetExpiredProcessingIfNeeded(now: Date) {
        guard case .processing = phase else {
            // Never auto-expire live recording — long dictation is intentional.
            return
        }
        if now.timeIntervalSince(lastTransitionAt) > processingTimeout {
            phase = .idle
            lastTransitionAt = now
        }
    }
}
