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
    private let sessionTimeout: TimeInterval
    private var lastTransitionAt: Date

    public init(
        phase: Phase = .idle,
        sessionTimeout: TimeInterval = 300,
        lastTransitionAt: Date = .distantPast
    ) {
        self.phase = phase
        self.sessionTimeout = sessionTimeout
        self.lastTransitionAt = lastTransitionAt
    }

    @discardableResult
    public func beginRecording(
        ownerID: UUID,
        now: Date = .now
    ) -> Bool {
        resetExpiredSessionIfNeeded(now: now)
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
        resetExpiredSessionIfNeeded(now: now)
        guard phase == .recording(ownerID) else { return false }
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

    private func resetExpiredSessionIfNeeded(now: Date) {
        guard case .idle = phase else {
            if now.timeIntervalSince(lastTransitionAt) > sessionTimeout {
                phase = .idle
                lastTransitionAt = now
            }
            return
        }
    }
}
