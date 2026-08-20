import Foundation
import Testing
@testable import VaniScript

/// Characterization tests for `UpdateCoordinator.start()` — the exact path the app runs at
/// launch (`VaniScriptApp` `.task { updateCoordinator.start() }`) — plus the background-check
/// and busy-guard branches. These pin the S22.O3 contract at the model level: a fresh build
/// without a configured EdDSA public key must never start the live Sparkle updater, so no
/// scheduled check, download, or install can begin without explicit user action.
@MainActor
private final class RecordingUpdateService: UpdateServiceProtocol {
    var isConfigured: Bool = false
    var isPublicKeyConfigured: Bool = true
    var automaticallyChecksForUpdates: Bool = true
    var updateCheckInterval: TimeInterval = 86400
    var feedURL: URL? = UpdateConfiguration.defaultFeedURL
    var startError: Error?

    var startCallCount = 0
    var checkForUpdatesCallCount = 0
    var checkForUpdatesInBackgroundCallCount = 0

    func start() throws {
        startCallCount += 1
        if let startError { throw startError }
        isConfigured = true
    }

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }

    func checkForUpdatesInBackground() {
        checkForUpdatesInBackgroundCallCount += 1
    }
}

/// Builds a throwaway on-disk bundle whose Info.plist does (or does not) carry SUPublicEDKey.
/// The key value is a clearly-fake placeholder, never a real credential.
private func makeTestBundle(withPublicKey: Bool) -> Bundle {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("UpdateCoordinatorStartTests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var info: [String: Any] = [
        "CFBundleShortVersionString": "9.9.9",
        "CFBundleVersion": "999",
    ]
    if withPublicKey {
        info["SUPublicEDKey"] = "FAKE-TEST-KEY-not-a-real-credential"
    }
    let data = try! PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try! data.write(to: dir.appendingPathComponent("Info.plist"))
    return Bundle(path: dir.path)!
}

@Suite("UpdateCoordinator Start Lifecycle Tests (S22.O3)")
struct UpdateCoordinatorStartTests {

    @Test("Fresh build without public key never starts the live updater at launch and stays idle")
    @MainActor
    func startWithoutPublicKeyNeverStartsUpdater() {
        let service = RecordingUpdateService()
        service.isPublicKeyConfigured = false
        let keylessBundle = Bundle(for: UpdateUserDriver.self)

        let coordinator = UpdateCoordinator(
            service: service,
            currentVersion: "1.0.0",
            currentBuildNumber: "1",
            bundle: keylessBundle
        )
        #expect(coordinator.isPublicKeyConfigured == false)

        coordinator.start()

        // The live updater service must never be started: no scheduled checks,
        // no background download, no install path can be armed.
        #expect(service.startCallCount == 0)
        #expect(service.isConfigured == false)
        #expect(coordinator.phase == .idle)

        // Background checks are equally gated off without a key.
        coordinator.checkForUpdatesInBackground()
        #expect(service.checkForUpdatesInBackgroundCallCount == 0)
        #expect(coordinator.phase == .idle)
    }

    @Test("Start with configured key starts the service exactly once; repeat start is guarded")
    @MainActor
    func startWithPublicKeyStartsServiceOnce() {
        let service = RecordingUpdateService()
        let keyedBundle = makeTestBundle(withPublicKey: true)

        let coordinator = UpdateCoordinator(
            service: service,
            currentVersion: "1.0.0",
            currentBuildNumber: "1",
            bundle: keyedBundle
        )
        #expect(coordinator.isPublicKeyConfigured == true)

        coordinator.start()
        #expect(service.startCallCount == 1)
        #expect(coordinator.phase == .idle)

        coordinator.start()
        #expect(service.startCallCount == 1)
    }

    @Test("Start failure thrown as UpdateDiagnosticError surfaces failed phase unchanged")
    @MainActor
    func startDiagnosticErrorSurfacesFailedPhase() {
        let service = RecordingUpdateService()
        let diagnostic = UpdateDiagnosticError(
            kind: .feedUnavailable,
            message: "Unable to parse the update feed.",
            recoverySuggestion: "Please check your network connection or try again later."
        )
        service.startError = diagnostic
        let keyedBundle = makeTestBundle(withPublicKey: true)

        let coordinator = UpdateCoordinator(
            service: service,
            currentVersion: "1.0.0",
            currentBuildNumber: "1",
            bundle: keyedBundle
        )

        coordinator.start()

        #expect(coordinator.phase == .failed(diagnostic))
        #expect(coordinator.phase.diagnosticError?.kind == .feedUnavailable)
        #expect(coordinator.phase.isBusy == false)
    }

    @Test("Start failure thrown as NSError is mapped into a diagnostic failed phase")
    @MainActor
    func startNSErrorMapsToDiagnosticPhase() {
        let service = RecordingUpdateService()
        service.startError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
        )
        let keyedBundle = makeTestBundle(withPublicKey: true)

        let coordinator = UpdateCoordinator(
            service: service,
            currentVersion: "1.0.0",
            currentBuildNumber: "1",
            bundle: keyedBundle
        )

        coordinator.start()

        #expect(coordinator.phase.diagnosticError?.kind == .networkError)
        #expect(coordinator.phase.isBusy == false)
    }

    @Test("Background check with configured key reports non-user-initiated checking and calls service")
    @MainActor
    func backgroundCheckTransitionsToNonUserInitiatedChecking() {
        let service = RecordingUpdateService()
        let keyedBundle = makeTestBundle(withPublicKey: true)

        let coordinator = UpdateCoordinator(
            service: service,
            currentVersion: "1.0.0",
            currentBuildNumber: "1",
            bundle: keyedBundle
        )

        coordinator.checkForUpdatesInBackground()

        #expect(coordinator.phase == .checking(isUserInitiated: false))
        #expect(coordinator.phase.isBusy == true)
        #expect(service.checkForUpdatesInBackgroundCallCount == 1)
        #expect(service.checkForUpdatesCallCount == 0)
    }

    @Test("Busy phase blocks duplicate user-initiated and background checks")
    @MainActor
    func busyPhaseBlocksDuplicateChecks() {
        let service = RecordingUpdateService()
        let keyedBundle = makeTestBundle(withPublicKey: true)

        let coordinator = UpdateCoordinator(
            service: service,
            currentVersion: "1.0.0",
            currentBuildNumber: "1",
            bundle: keyedBundle
        )

        coordinator.checkForUpdates()
        #expect(coordinator.phase == .checking(isUserInitiated: true))
        #expect(service.checkForUpdatesCallCount == 1)

        coordinator.checkForUpdates()
        #expect(service.checkForUpdatesCallCount == 1)

        coordinator.checkForUpdatesInBackground()
        #expect(service.checkForUpdatesInBackgroundCallCount == 0)
        #expect(coordinator.phase == .checking(isUserInitiated: true))
    }
}
