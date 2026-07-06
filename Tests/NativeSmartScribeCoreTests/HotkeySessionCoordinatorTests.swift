import Foundation
import NativeSmartScribeCore
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
func hotkeySessionCoordinatorExpiresStaleSession() {
    let start = Date(timeIntervalSince1970: 1_777_000_000)
    let coordinator = HotkeySessionCoordinator(sessionTimeout: 10)
    let firstOwner = UUID()
    let secondOwner = UUID()

    #expect(coordinator.beginRecording(ownerID: firstOwner, now: start))
    #expect(
        coordinator.beginRecording(
            ownerID: secondOwner,
            now: start.addingTimeInterval(11)
        )
    )
    #expect(coordinator.phase == .recording(secondOwner))
}
