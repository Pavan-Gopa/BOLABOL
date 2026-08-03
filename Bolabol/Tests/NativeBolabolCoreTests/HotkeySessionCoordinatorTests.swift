import Foundation
import NativeBolabolCore
import Testing

@MainActor
@Test
func hotkeySessionCoordinatorAllowsSingleOwnerToStartAndStopSession() {
    let coordinator = HotkeySessionCoordinator()
    let owner = UUID()

    #expect(coordinator.beginRecording(ownerID: owner))
    #expect(coordinator.phase == .recording(owner))
    #expect(coordinator.beginProcessing(ownerID: owner))
    #expect(coordinator.phase == .processing(owner))

    coordinator.finish(ownerID: owner)

    #expect(coordinator.phase == .idle)
}

@MainActor
@Test
func hotkeySessionCoordinatorRejectsDifferentOwnerWhileSessionIsActive() {
    let coordinator = HotkeySessionCoordinator()
    let firstOwner = UUID()
    let secondOwner = UUID()

    #expect(coordinator.beginRecording(ownerID: firstOwner))
    #expect(!coordinator.beginRecording(ownerID: secondOwner))
    #expect(!coordinator.beginProcessing(ownerID: secondOwner))
    #expect(coordinator.phase == .recording(firstOwner))
}

@MainActor
@Test
func hotkeySessionCoordinatorNeverExpiresLiveRecording() {
    let start = Date(timeIntervalSince1970: 1_777_000_000)
    // Even with a short timeout, live recording must stay owned so long
    // dictation (6–20+ minutes) can still be stopped with the hotkey.
    let coordinator = HotkeySessionCoordinator(sessionTimeout: 10)
    let firstOwner = UUID()
    let secondOwner = UUID()

    #expect(coordinator.beginRecording(ownerID: firstOwner, now: start))
    #expect(
        !coordinator.beginRecording(
            ownerID: secondOwner,
            now: start.addingTimeInterval(11)
        )
    )
    #expect(coordinator.phase == .recording(firstOwner))
    #expect(coordinator.beginProcessing(ownerID: firstOwner, now: start.addingTimeInterval(600)))
    #expect(coordinator.phase == .processing(firstOwner))
}

@MainActor
@Test
func hotkeySessionCoordinatorExpiresStuckProcessing() {
    let start = Date(timeIntervalSince1970: 1_777_000_000)
    let coordinator = HotkeySessionCoordinator(sessionTimeout: 10)
    let firstOwner = UUID()
    let secondOwner = UUID()

    #expect(coordinator.beginRecording(ownerID: firstOwner, now: start))
    #expect(coordinator.beginProcessing(ownerID: firstOwner, now: start.addingTimeInterval(1)))
    #expect(
        coordinator.beginRecording(
            ownerID: secondOwner,
            now: start.addingTimeInterval(12)
        )
    )
    #expect(coordinator.phase == .recording(secondOwner))
}

@MainActor
@Test
func hotkeySessionCoordinatorReclaimsOrphanedIdleSessionForStop() {
    let coordinator = HotkeySessionCoordinator()
    let owner = UUID()

    #expect(coordinator.reclaimOrphanedRecordingForStop(ownerID: owner))
    #expect(coordinator.phase == .processing(owner))

    // Cannot reclaim while another owner is active.
    let other = UUID()
    #expect(!coordinator.reclaimOrphanedRecordingForStop(ownerID: other))
    #expect(coordinator.phase == .processing(owner))
}
