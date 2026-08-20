import Foundation
import Sparkle
import Testing
@testable import VaniScript

@MainActor
private final class MockUpdateUserDriverDelegate: UpdateUserDriverDelegate {
    var beganCheckCallCount = 0
    var isUserInitiatedCheck = false
    var foundDescriptor: UpdateDescriptor?
    var didFindUpdateCount = 0
    var releaseNotesHTML: String?
    var releaseNotesText: String?
    var notFoundCount = 0
    var reportedError: UpdateDiagnosticError?
    var downloadInitiatedCount = 0
    var expectedContentLength: UInt64 = 0
    var receivedDataLength: UInt64 = 0
    var didStartExtractingCount = 0
    var extractionProgress: Double = 0.0
    var readyToInstallDescriptor: UpdateDescriptor?
    var installingDescriptor: UpdateDescriptor?
    var didFinishInstallationCount = 0
    var didDismissInstallationCount = 0

    func driverDidBeginCheck(isUserInitiated: Bool, cancellation: @escaping () -> Void) {
        beganCheckCallCount += 1
        isUserInitiatedCheck = isUserInitiated
    }

    func driverDidFindUpdate(descriptor: UpdateDescriptor, isUserInitiated: Bool) {
        didFindUpdateCount += 1
        foundDescriptor = descriptor
    }

    func driverDidReceiveReleaseNotes(html: String?, text: String?) {
        releaseNotesHTML = html
        releaseNotesText = text
    }

    func driverDidNotFindUpdate() {
        notFoundCount += 1
    }

    func driverDidFail(with error: UpdateDiagnosticError) {
        reportedError = error
    }

    func driverDidInitiateDownload(cancellation: @escaping () -> Void) {
        downloadInitiatedCount += 1
    }

    func driverDidReceiveExpectedContentLength(_ expectedLength: UInt64) {
        expectedContentLength = expectedLength
    }

    func driverDidReceiveData(length: UInt64) {
        receivedDataLength += length
    }

    func driverDidStartExtracting() {
        didStartExtractingCount += 1
    }

    func driverDidReceiveExtractionProgress(_ progress: Double) {
        extractionProgress = progress
    }

    func driverIsReadyToInstall(descriptor: UpdateDescriptor) {
        readyToInstallDescriptor = descriptor
    }

    func driverIsInstalling(descriptor: UpdateDescriptor) {
        installingDescriptor = descriptor
    }

    func driverDidFinishInstallation(relaunched: Bool) {
        didFinishInstallationCount += 1
    }

    func driverDidDismissInstallation() {
        didDismissInstallationCount += 1
    }
}

/// Helper to instantiate an SPUUserUpdateState via NSSecureCoding.
private func makeUserUpdateState(stage: Int = 0, userInitiated: Bool = false) -> SPUUserUpdateState {
    let archiver = NSKeyedArchiver(requiringSecureCoding: false)
    archiver.encode(stage, forKey: "SPUUserUpdateStateStage")
    archiver.encode(userInitiated, forKey: "SPUUserUpdateStateUserInitiated")
    archiver.finishEncoding()
    let data = archiver.encodedData
    let unarchiver = try! NSKeyedUnarchiver(forReadingFrom: data)
    unarchiver.requiresSecureCoding = false
    return SPUUserUpdateState(coder: unarchiver)!
}

/// Helper to instantiate a valid SUAppcastItem for unit tests.
private func makeAppcastItem(version: String = "1.5.0", build: String = "150") -> SUAppcastItem {
    let appcastDict: [String: Any] = [
        "title": "VaniScript \(version)",
        "description": "Release notes for \(version).",
        "sparkle:version": build,
        "sparkle:shortVersionString": version,
        "enclosure": [
            "url": "https://github.com/Pavan-Gopa/VaniScript/releases/download/v\(version)/VaniScript-\(version).zip",
            "sparkle:version": build,
            "sparkle:shortVersionString": version,
            "length": "52428800"
        ]
    ]
    return SUAppcastItem(dictionary: appcastDict)!
}

@Suite("UpdateUserDriver Tests")
struct UpdateUserDriverTests {

    @Test("Permission request responds with automatic checks enabled and auto-download disabled")
    @MainActor
    func permissionRequestResponse() {
        let driver = UpdateUserDriver()
        let request = SPUUpdatePermissionRequest(systemProfile: [])

        var receivedResponse: SUUpdatePermissionResponse?
        driver.show(request) { response in
            receivedResponse = response
        }

        #expect(receivedResponse != nil)
        #expect(receivedResponse?.automaticUpdateChecks == true)
        #expect(receivedResponse?.automaticUpdateDownloading?.boolValue == false)
        #expect(receivedResponse?.sendSystemProfile == false)
    }

    @Test("User-initiated update check captures cancellation and notifies delegate")
    @MainActor
    func userInitiatedUpdateCheck() {
        let driver = UpdateUserDriver()
        let delegate = MockUpdateUserDriverDelegate()
        driver.delegate = delegate

        var cancelled = false
        driver.showUserInitiatedUpdateCheck {
            cancelled = true
        }

        #expect(delegate.beganCheckCallCount == 1)
        #expect(delegate.isUserInitiatedCheck == true)

        driver.cancelCheck()
        #expect(cancelled == true)
    }

    @Test("Update found HOLDS reply closure without auto-installing (ADR-008, S22.J1)")
    @MainActor
    func updateFoundHoldsReplyUntilUserAction() {
        let driver = UpdateUserDriver()
        let delegate = MockUpdateUserDriverDelegate()
        driver.delegate = delegate

        let appcastItem = makeAppcastItem(version: "1.5.0", build: "150")
        var receivedChoice: SPUUserUpdateChoice?

        #expect(appcastItem.displayVersionString == "1.5.0")
        #expect(appcastItem.versionString == "150")

        let userState = makeUserUpdateState(stage: 0, userInitiated: false)

        driver.showUpdateFound(with: appcastItem, state: userState) { choice in
            receivedChoice = choice
        }

        // CRITICAL CONTRACT CHECK: Reply must NOT have been called yet!
        #expect(receivedChoice == nil)
        #expect(delegate.didFindUpdateCount == 1)
        #expect(delegate.foundDescriptor?.displayVersion == "1.5.0")
        #expect(delegate.foundDescriptor?.buildNumber == "150")

        // Now simulate user clicking "Install Update"
        driver.installUpdate()
        #expect(receivedChoice == .install)
    }

    @Test("Dismiss update resumes held reply with .dismiss")
    @MainActor
    func dismissUpdateResumesHeldReplyWithDismiss() {
        let driver = UpdateUserDriver()
        let appcastItem = makeAppcastItem(version: "1.5.0", build: "150")
        let userState = makeUserUpdateState(stage: 0, userInitiated: false)

        var receivedChoice: SPUUserUpdateChoice?
        driver.showUpdateFound(with: appcastItem, state: userState) { choice in
            receivedChoice = choice
        }

        #expect(receivedChoice == nil)
        driver.dismissUpdate()
        #expect(receivedChoice == .dismiss)
    }

    @Test("Skip update resumes held reply with .skip")
    @MainActor
    func skipUpdateResumesHeldReplyWithSkip() {
        let driver = UpdateUserDriver()
        let appcastItem = makeAppcastItem(version: "1.5.0", build: "150")
        let userState = makeUserUpdateState(stage: 0, userInitiated: false)

        var receivedChoice: SPUUserUpdateChoice?
        driver.showUpdateFound(with: appcastItem, state: userState) { choice in
            receivedChoice = choice
        }

        #expect(receivedChoice == nil)
        driver.skipUpdate()
        #expect(receivedChoice == .skip)
    }

    @Test("Download, extraction, and installation lifecycle progress events")
    @MainActor
    func downloadAndExtractionLifecycle() {
        let driver = UpdateUserDriver()
        let delegate = MockUpdateUserDriverDelegate()
        driver.delegate = delegate

        var downloadCancelled = false
        driver.showDownloadInitiated {
            downloadCancelled = true
        }
        #expect(delegate.downloadInitiatedCount == 1)

        driver.cancelDownload()
        #expect(downloadCancelled == true)

        driver.showDownloadDidReceiveExpectedContentLength(80_000_000)
        #expect(delegate.expectedContentLength == 80_000_000)

        driver.showDownloadDidReceiveData(ofLength: 40_000_000)
        #expect(delegate.receivedDataLength == 40_000_000)

        driver.showDownloadDidStartExtractingUpdate()
        #expect(delegate.didStartExtractingCount == 1)

        driver.showExtractionReceivedProgress(0.9)
        #expect(delegate.extractionProgress == 0.9)

        var installChoice: SPUUserUpdateChoice?
        driver.showReady(toInstallAndRelaunch: { choice in
            installChoice = choice
        })
        #expect(installChoice == nil)

        driver.installUpdate()
        #expect(installChoice == .install)

        var acknowledged = false
        driver.showUpdateInstalledAndRelaunched(true) {
            acknowledged = true
        }
        #expect(acknowledged == true)
        #expect(delegate.didFinishInstallationCount == 1)
    }

    @Test("Update not found and error handling invoke acknowledgements")
    @MainActor
    func updateNotFoundAndErrorAcknowledgements() {
        let driver = UpdateUserDriver()
        let delegate = MockUpdateUserDriverDelegate()
        driver.delegate = delegate

        var notFoundAck = false
        let notFoundError = NSError(domain: "SUSparkleErrorDomain", code: 1001, userInfo: nil)
        driver.showUpdateNotFoundWithError(notFoundError) {
            notFoundAck = true
        }
        #expect(notFoundAck == true)
        #expect(delegate.notFoundCount == 1)

        var errorAck = false
        let sparkleError = NSError(
            domain: "SUSparkleErrorDomain",
            code: 3001, // SUSignatureError
            userInfo: [NSLocalizedDescriptionKey: "Signature check failed"]
        )
        driver.showUpdaterError(sparkleError) {
            errorAck = true
        }
        #expect(errorAck == true)
        #expect(delegate.reportedError?.kind == .signatureVerificationFailed)
    }

    @Test("Dismiss update installation cleans up held closures")
    @MainActor
    func dismissUpdateInstallationCleansUp() {
        let driver = UpdateUserDriver()
        let delegate = MockUpdateUserDriverDelegate()
        driver.delegate = delegate

        driver.dismissUpdateInstallation()
        #expect(delegate.didDismissInstallationCount == 1)
    }
}
