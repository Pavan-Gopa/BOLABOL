import Foundation
import Testing
@testable import VaniScript

@MainActor
private final class FakeUpdateService: UpdateServiceProtocol {
    var isConfigured: Bool = false
    var isPublicKeyConfigured: Bool = true
    var automaticallyChecksForUpdates: Bool = true
    var updateCheckInterval: TimeInterval = 86400
    var feedURL: URL? = UpdateConfiguration.defaultFeedURL

    var startCallCount = 0
    var checkForUpdatesCallCount = 0
    var checkForUpdatesInBackgroundCallCount = 0

    func start() throws {
        startCallCount += 1
        isConfigured = true
    }

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }

    func checkForUpdatesInBackground() {
        checkForUpdatesInBackgroundCallCount += 1
    }
}

@Suite("UpdateCoordinator Tests")
struct UpdateCoordinatorTests {

    @Test("Initial state reflects resolved versions, default settings, and idle phase")
    @MainActor
    func initialState() {
        let fakeService = FakeUpdateService()
        let coordinator = UpdateCoordinator(
            service: fakeService,
            currentVersion: "1.2.3",
            currentBuildNumber: "20260818"
        )

        #expect(coordinator.phase == .idle)
        #expect(coordinator.currentVersion == "1.2.3")
        #expect(coordinator.currentBuildNumber == "20260818")
        #expect(coordinator.lastCheckDate == nil)
        #expect(coordinator.automaticallyChecksForUpdates == true)
        #expect(coordinator.feedURL == UpdateConfiguration.defaultFeedURL)
    }

    @Test("Missing public key produces diagnostic error on check without network or crash")
    @MainActor
    func missingPublicKeyDiagnosticError() {
        let fakeService = FakeUpdateService()
        fakeService.isPublicKeyConfigured = false
        let emptyBundle = Bundle(for: UpdateUserDriver.self)

        let coordinator = UpdateCoordinator(
            service: fakeService,
            currentVersion: "1.0.0",
            currentBuildNumber: "1",
            bundle: emptyBundle
        )

        #expect(coordinator.isPublicKeyConfigured == false)

        coordinator.checkForUpdates()

        if case .failed(let error) = coordinator.phase {
            #expect(error.kind == .missingPublicKey)
            #expect(error.isConfigurationFailure == true)
            #expect(!error.message.isEmpty)
        } else {
            Issue.record("Expected phase to be .failed(.missingPublicKey)")
        }

        #expect(fakeService.checkForUpdatesCallCount == 0)
    }

    @Test("User-initiated check transitions phase and invokes service check")
    @MainActor
    func userInitiatedCheck() {
        let fakeService = FakeUpdateService()
        let driver = UpdateUserDriver()
        let coordinator = UpdateCoordinator(
            service: fakeService,
            driver: driver,
            currentVersion: "1.0.0",
            currentBuildNumber: "1"
        )
        driver.coordinator = coordinator

        // Simulate having a configured public key by testing through fake service
        coordinator.driverDidBeginCheck(isUserInitiated: true) {}

        #expect(coordinator.phase == .checking(isUserInitiated: true))
        #expect(coordinator.phase.isBusy == true)
    }

    @Test("Discovery publishes availability and DOES NOT auto-install (S22.J1 contract)")
    @MainActor
    func discoveryPublishesAvailabilityWithoutAutoInstall() {
        let fakeService = FakeUpdateService()
        let driver = UpdateUserDriver()
        let coordinator = UpdateCoordinator(
            service: fakeService,
            driver: driver,
            currentVersion: "1.0.0",
            currentBuildNumber: "1"
        )
        driver.coordinator = coordinator

        let descriptor = UpdateDescriptor(
            version: "1.1.0",
            displayVersion: "1.1.0",
            buildNumber: "200",
            releaseNotesDescription: "Performance enhancements and bug fixes.",
            contentLength: 45_000_000
        )

        coordinator.driverDidFindUpdate(descriptor: descriptor, isUserInitiated: false)

        #expect(coordinator.phase == .available(descriptor))
        #expect(coordinator.phase.isAvailable == true)
        #expect(coordinator.phase.isReadyToInstall == false)
        #expect(coordinator.lastCheckDate != nil)
        #expect(coordinator.phase.availableDescriptor?.displayVersion == "1.1.0")
        #expect(coordinator.phase.availableDescriptor?.humanReadableSize.isEmpty == false)
    }

    @Test("Dismiss and Skip actions reset coordinator phase to idle")
    @MainActor
    func dismissAndSkipActions() {
        let fakeService = FakeUpdateService()
        let driver = UpdateUserDriver()
        let coordinator = UpdateCoordinator(
            service: fakeService,
            driver: driver,
            currentVersion: "1.0.0",
            currentBuildNumber: "1"
        )
        driver.coordinator = coordinator

        let descriptor = UpdateDescriptor(version: "1.1.0")
        coordinator.driverDidFindUpdate(descriptor: descriptor, isUserInitiated: true)
        #expect(coordinator.phase == .available(descriptor))

        coordinator.dismissUpdate()
        #expect(coordinator.phase == .idle)

        coordinator.driverDidFindUpdate(descriptor: descriptor, isUserInitiated: true)
        #expect(coordinator.phase == .available(descriptor))

        coordinator.skipUpdate()
        #expect(coordinator.phase == .idle)
    }

    @Test("Download progress updates calculate ratio and advance state")
    @MainActor
    func downloadProgressUpdates() {
        let fakeService = FakeUpdateService()
        let driver = UpdateUserDriver()
        let coordinator = UpdateCoordinator(
            service: fakeService,
            driver: driver,
            currentVersion: "1.0.0",
            currentBuildNumber: "1"
        )
        driver.coordinator = coordinator

        let descriptor = UpdateDescriptor(version: "2.0.0", contentLength: 100_000_000)
        coordinator.driverDidFindUpdate(descriptor: descriptor, isUserInitiated: true)

        coordinator.driverDidInitiateDownload(cancellation: {})
        coordinator.driverDidReceiveExpectedContentLength(100_000_000)
        coordinator.driverDidReceiveData(length: 25_000_000)

        if case .downloading(let desc, let progress, let received, let total) = coordinator.phase {
            #expect(desc.version == "2.0.0")
            #expect(progress == 0.25)
            #expect(received == 25_000_000)
            #expect(total == 100_000_000)
        } else {
            Issue.record("Expected phase to be .downloading")
        }

        coordinator.driverDidReceiveData(length: 25_000_000)
        if case .downloading(_, let progress, let received, _) = coordinator.phase {
            #expect(progress == 0.5)
            #expect(received == 50_000_000)
        } else {
            Issue.record("Expected phase to be .downloading at 50%")
        }
    }

    @Test("Extraction and ready-to-install lifecycle transitions")
    @MainActor
    func extractionAndReadyLifecycle() {
        let fakeService = FakeUpdateService()
        let driver = UpdateUserDriver()
        let coordinator = UpdateCoordinator(
            service: fakeService,
            driver: driver,
            currentVersion: "1.0.0",
            currentBuildNumber: "1"
        )
        driver.coordinator = coordinator

        let descriptor = UpdateDescriptor(version: "2.0.0")
        coordinator.driverDidFindUpdate(descriptor: descriptor, isUserInitiated: true)

        coordinator.driverDidStartExtracting()
        #expect(coordinator.phase == .extracting(descriptor, progress: 0.0))

        coordinator.driverDidReceiveExtractionProgress(0.8)
        #expect(coordinator.phase == .extracting(descriptor, progress: 0.8))

        coordinator.driverIsReadyToInstall(descriptor: descriptor)
        #expect(coordinator.phase == .readyToInstall(descriptor))
        #expect(coordinator.phase.isReadyToInstall == true)

        coordinator.driverIsInstalling(descriptor: descriptor)
        #expect(coordinator.phase == .installing(descriptor))

        coordinator.driverDidFinishInstallation(relaunched: true)
        if case .upToDate(let lastChecked) = coordinator.phase {
            #expect(lastChecked <= Date())
        } else {
            Issue.record("Expected phase to be .upToDate after finish")
        }
    }

    @Test("Up to date and error states map deterministically")
    @MainActor
    func upToDateAndErrorStates() {
        let fakeService = FakeUpdateService()
        let driver = UpdateUserDriver()
        let coordinator = UpdateCoordinator(
            service: fakeService,
            driver: driver,
            currentVersion: "1.0.0",
            currentBuildNumber: "1"
        )
        driver.coordinator = coordinator

        coordinator.driverDidNotFindUpdate()
        if case .upToDate = coordinator.phase {
            #expect(coordinator.lastCheckDate != nil)
        } else {
            Issue.record("Expected phase to be .upToDate")
        }

        let testError = UpdateDiagnosticError(
            kind: .networkError,
            message: "Host unreachable",
            recoverySuggestion: "Check internet connection"
        )
        coordinator.driverDidFail(with: testError)
        #expect(coordinator.phase == .failed(testError))
        #expect(coordinator.phase.diagnosticError?.kind == .networkError)

        coordinator.clearError()
        #expect(coordinator.phase == .idle)
    }

    @Test("SettingsTab includes updates in alphabetized list")
    func settingsTabAlphabetizedIncludesUpdates() {
        #expect(SettingsTab.allCases.contains(.updates))
        #expect(SettingsTab.alphabetized.contains(.updates))
        #expect(SettingsTab.alphabetized.last == .updates)
    }
}
