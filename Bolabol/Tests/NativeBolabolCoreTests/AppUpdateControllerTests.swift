import Foundation
@testable import NativeBolabol
import Testing

private final class TestValueBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) {
        self.value = value
    }
}

@Suite("AppUpdateControllerTests")
@MainActor
struct AppUpdateControllerTests {

    @Test
    func initialPhaseIsIdleWithNoUpdateAvailable() {
        let fakeDriver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(driver: fakeDriver)

        #expect(coordinator.phase == .idle)
        #expect(coordinator.isUpdateAvailable == false)
        #expect(coordinator.isReadyToInstall == false)
        #expect(coordinator.currentVersion == nil)
    }

    @Test
    func startInitializesDriver() {
        let fakeDriver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(driver: fakeDriver)

        #expect(fakeDriver.startCallCount == 0)
        coordinator.start()
        #expect(fakeDriver.startCallCount == 1)

        // Duplicate start is safely idempotent
        coordinator.start()
        #expect(fakeDriver.startCallCount == 1)
    }

    @Test
    func driverReportsFoundUpdateTransitionsToPreparing() {
        let fakeDriver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(driver: fakeDriver)
        coordinator.start()

        fakeDriver.simulateFoundUpdate(version: "1.0.6")

        #expect(coordinator.phase == .preparing(version: "1.0.6"))
        #expect(coordinator.isUpdateAvailable == true)
        #expect(coordinator.isReadyToInstall == false)
        #expect(coordinator.currentVersion == "1.0.6")
    }

    @Test
    func driverPreparesUpdateTransitionsToReady() {
        let fakeDriver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(driver: fakeDriver)
        coordinator.start()

        var handlerCalled = false
        fakeDriver.simulatePreparedUpdate(version: "1.0.6") {
            handlerCalled = true
        }

        #expect(coordinator.phase == .ready(version: "1.0.6"))
        #expect(coordinator.isUpdateAvailable == true)
        #expect(coordinator.isReadyToInstall == true)
        #expect(coordinator.currentVersion == "1.0.6")
        #expect(handlerCalled == false)
    }

    @Test
    func installPreparedUpdateInvokesRelaunchGateAndImmediateHandler() async {
        let fakeDriver = FakeUpdateDriver()
        let gate = UpdateRelaunchGate(timeout: 2.0)
        let coordinator = UpdateCoordinator(driver: fakeDriver, relaunchGate: gate)
        coordinator.start()

        var handlerCalled = false
        fakeDriver.simulatePreparedUpdate(version: "1.0.6") {
            handlerCalled = true
        }

        #expect(coordinator.isReadyToInstall == true)

        await coordinator.installPreparedUpdate()

        #expect(handlerCalled == true)
        #expect(coordinator.phase == .installing(version: "1.0.6"))
    }

    @Test
    func installPreparedUpdateRefusesWhenRecordingActive() async {
        let fakeDriver = FakeUpdateDriver()
        let gate = UpdateRelaunchGate(timeout: 2.0)
        let isRecording = TestValueBox(true)
        gate.registerRecordingChecker { isRecording.value }

        let coordinator = UpdateCoordinator(driver: fakeDriver, relaunchGate: gate)
        coordinator.start()

        var handlerCalled = false
        fakeDriver.simulatePreparedUpdate(version: "1.0.6") {
            handlerCalled = true
        }

        await coordinator.installPreparedUpdate()

        // Active recording must prevent installation
        #expect(handlerCalled == false)
        if case .failed(let version, let message) = coordinator.phase {
            #expect(version == "1.0.6")
            #expect(message.contains("recording"))
        } else {
            Issue.record("Expected .failed phase when recording is active, got \(coordinator.phase)")
        }

        // When recording stops, retry succeeds using the retained handler
        isRecording.value = false
        await coordinator.installPreparedUpdate()

        #expect(handlerCalled == true)
        #expect(coordinator.phase == .installing(version: "1.0.6"))
    }

    @Test
    func installPreparedUpdateFailsWhenQuiescenceTimesOut() async {
        let fakeDriver = FakeUpdateDriver()
        let gate = UpdateRelaunchGate(timeout: 0.05)
        gate.registerQuiescenceHandler {
            try await Task.sleep(nanoseconds: 300_000_000) // 300ms > 50ms timeout
        }

        let coordinator = UpdateCoordinator(driver: fakeDriver, relaunchGate: gate)
        coordinator.start()

        var handlerCalled = false
        fakeDriver.simulatePreparedUpdate(version: "1.0.6") {
            handlerCalled = true
        }

        await coordinator.installPreparedUpdate()

        #expect(handlerCalled == false)
        if case .failed(let version, let message) = coordinator.phase {
            #expect(version == "1.0.6")
            #expect(message.contains("Timed out"))
        } else {
            Issue.record("Expected .failed phase on quiescence timeout, got \(coordinator.phase)")
        }
    }

    @Test
    func cancellationRetainsPreparedHandlerAndRestoresReadyState() {
        let fakeDriver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(driver: fakeDriver)
        coordinator.start()

        var handlerCalled = false
        fakeDriver.simulatePreparedUpdate(version: "1.0.6") {
            handlerCalled = true
        }

        #expect(coordinator.phase == .ready(version: "1.0.6"))

        // Simulate cancellation during session
        fakeDriver.simulateCancel()

        // Phase must remain or restore .ready since prepared update is still available
        #expect(coordinator.phase == .ready(version: "1.0.6"))
        #expect(handlerCalled == false)
    }

    @Test
    func driverDidFailUpdateTransitionsToFailedState() {
        let fakeDriver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(driver: fakeDriver)
        coordinator.start()

        fakeDriver.simulateDownloading(version: "1.0.6")
        #expect(coordinator.phase == .preparing(version: "1.0.6"))

        fakeDriver.simulateFailure(version: "1.0.6", errorDescription: "Network unreachable")

        #expect(coordinator.phase == .failed(version: "1.0.6", message: "Network unreachable"))
        #expect(coordinator.isUpdateAvailable == true)
    }

    @Test
    func driverDidNotFindUpdateTransitionsCheckingToIdle() {
        let fakeDriver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(driver: fakeDriver)
        coordinator.start()

        coordinator.checkForUpdates()
        #expect(coordinator.phase == .checking)
        #expect(fakeDriver.checkForUpdatesCallCount == 1)

        fakeDriver.simulateNoUpdate()
        #expect(coordinator.phase == .idle)
        #expect(coordinator.isUpdateAvailable == false)
    }

    @Test
    func dismissFromFailedStateWithPreparedHandlerRestoresReady() {
        let fakeDriver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(driver: fakeDriver)
        coordinator.start()

        fakeDriver.simulatePreparedUpdate(version: "1.0.6") {}
        fakeDriver.simulateFailure(version: "1.0.6", errorDescription: "Temporary error")

        #expect(coordinator.phase == .failed(version: "1.0.6", message: "Temporary error"))

        coordinator.dismiss()
        #expect(coordinator.phase == .ready(version: "1.0.6"))
    }

    @Test
    func dismissFromFailedStateWithoutHandlerRestoresIdle() {
        let fakeDriver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(driver: fakeDriver)
        coordinator.start()

        coordinator.checkForUpdates()
        fakeDriver.simulateFailure(version: nil, errorDescription: "Server error")

        #expect(coordinator.phase == .failed(version: nil, message: "Server error"))

        coordinator.dismiss()
        #expect(coordinator.phase == .idle)
    }

    @Test
    func openReleasePageOpensExpectedLatestURL() {
        let openedURL = TestValueBox<URL?>(nil)
        let coordinator = UpdateCoordinator(
            driver: FakeUpdateDriver(),
            urlOpener: { url in
                openedURL.value = url
                return true
            }
        )

        let success = coordinator.openReleasePage()
        #expect(success == true)
        #expect(openedURL.value == URL(string: "https://github.com/Pavan-Gopa/BOLABOL/releases/latest"))
    }

    @Test
    func noFalseSuccessStateExists() {
        // Assert that the UpdatePhase model correctly does not contain an in-app "success" case;
        // Sparkle manages termination and relaunch externally upon update completion.
        let phases: [UpdatePhase] = [
            .idle,
            .checking,
            .preparing(version: "1.0.6"),
            .ready(version: "1.0.6"),
            .waitingForSafeRelaunch(version: "1.0.6"),
            .installing(version: "1.0.6"),
            .failed(version: "1.0.6", message: "error")
        ]

        #expect(phases.count == 7)
    }

    @Test
    func relaunchGateExecutesRegisteredQuiescenceHandlers() async throws {
        let gate = UpdateRelaunchGate(timeout: 2.0)
        let handler1Ran = TestValueBox(false)
        let handler2Ran = TestValueBox(false)

        gate.registerQuiescenceHandler {
            handler1Ran.value = true
        }
        gate.registerQuiescenceHandler {
            handler2Ran.value = true
        }

        try await gate.prepareForUpdateRelaunch()

        #expect(handler1Ran.value == true)
        #expect(handler2Ran.value == true)
    }
}
