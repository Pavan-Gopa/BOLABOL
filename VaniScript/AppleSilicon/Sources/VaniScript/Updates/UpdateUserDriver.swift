import Foundation
import Sparkle

/// Delegate protocol for user driver state changes.
@MainActor
public protocol UpdateUserDriverDelegate: AnyObject {
    func driverDidBeginCheck(isUserInitiated: Bool, cancellation: @escaping () -> Void)
    func driverDidFindUpdate(descriptor: UpdateDescriptor, isUserInitiated: Bool)
    func driverDidReceiveReleaseNotes(html: String?, text: String?)
    func driverDidNotFindUpdate()
    func driverDidFail(with error: UpdateDiagnosticError)
    func driverDidInitiateDownload(cancellation: @escaping () -> Void)
    func driverDidReceiveExpectedContentLength(_ expectedLength: UInt64)
    func driverDidReceiveData(length: UInt64)
    func driverDidStartExtracting()
    func driverDidReceiveExtractionProgress(_ progress: Double)
    func driverIsReadyToInstall(descriptor: UpdateDescriptor)
    func driverIsInstalling(descriptor: UpdateDescriptor)
    func driverDidFinishInstallation(relaunched: Bool)
    func driverDidDismissInstallation()
}

/// Custom Sparkle SPUUserDriver that holds update choice replies until explicit user action,
/// never installs automatically, and reports granular progress to UpdateCoordinator.
@MainActor
public final class UpdateUserDriver: NSObject, SPUUserDriver {
    public weak var delegate: UpdateUserDriverDelegate?
    public weak var coordinator: UpdateCoordinator?

    private var heldUpdateChoiceReply: ((SPUUserUpdateChoice) -> Void)?
    private var heldInstallReply: ((SPUUserUpdateChoice) -> Void)?
    private var heldRetryTerminatingApplication: (() -> Void)?
    private var checkCancellation: (() -> Void)?
    private var downloadCancellation: (() -> Void)?
    private var currentAppcastItem: SUAppcastItem?

    public override init() {
        super.init()
    }

    // MARK: - SPUUserDriver: Permission Request

    public func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        // Automatic checks: true; Automatic downloading: false; Send profile: false
        let response = SUUpdatePermissionResponse(
            automaticUpdateChecks: true,
            automaticUpdateDownloading: NSNumber(value: false),
            sendSystemProfile: false
        )
        reply(response)
    }

    // MARK: - SPUUserDriver: Check Initiated

    public func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.checkCancellation = cancellation
        delegate?.driverDidBeginCheck(isUserInitiated: true, cancellation: cancellation)
        coordinator?.driverDidBeginCheck(isUserInitiated: true, cancellation: cancellation)
    }

    // MARK: - SPUUserDriver: Update Found

    public func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        self.currentAppcastItem = appcastItem
        // CRITICAL CONTRACT (ADR-008, S22.J1):
        // Hold the reply block. Do NOT invoke reply(.install) automatically.
        self.heldUpdateChoiceReply = reply

        let descriptor = UpdateDescriptor(
            id: "\(appcastItem.versionString)-\(appcastItem.displayVersionString)",
            version: appcastItem.displayVersionString,
            displayVersion: appcastItem.displayVersionString,
            buildNumber: appcastItem.versionString,
            releaseNotesURL: appcastItem.releaseNotesURL,
            releaseNotesDescription: appcastItem.itemDescription,
            title: appcastItem.title,
            isCritical: appcastItem.isCriticalUpdate,
            isInformationalOnly: appcastItem.isInformationOnlyUpdate,
            infoURL: appcastItem.infoURL,
            contentLength: appcastItem.contentLength,
            publishDate: appcastItem.date
        )

        delegate?.driverDidFindUpdate(descriptor: descriptor, isUserInitiated: state.userInitiated)
        coordinator?.driverDidFindUpdate(descriptor: descriptor, isUserInitiated: state.userInitiated)
    }

    // MARK: - SPUUserDriver: Release Notes

    public func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        let stringContent = String(data: downloadData.data, encoding: .utf8)
        let mimeType = downloadData.mimeType
        let isHTML = mimeType?.contains("html") == true || (stringContent?.contains("<html") == true)

        let html = isHTML ? stringContent : nil
        let text = isHTML ? nil : stringContent

        delegate?.driverDidReceiveReleaseNotes(html: html, text: text)
        coordinator?.driverDidReceiveReleaseNotes(html: html, text: text)
    }

    public func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        // Non-fatal: UI falls back to appcast item description or empty notes.
    }

    // MARK: - SPUUserDriver: Update Not Found

    public func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        delegate?.driverDidNotFindUpdate()
        coordinator?.driverDidNotFindUpdate()
    }

    // MARK: - SPUUserDriver: Error

    public func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        let diagnosticError = UpdateDiagnosticError.map(from: error as NSError)
        delegate?.driverDidFail(with: diagnosticError)
        coordinator?.driverDidFail(with: diagnosticError)
    }

    // MARK: - SPUUserDriver: Download Progress

    public func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.downloadCancellation = cancellation
        delegate?.driverDidInitiateDownload(cancellation: cancellation)
        coordinator?.driverDidInitiateDownload(cancellation: cancellation)
    }

    public func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        delegate?.driverDidReceiveExpectedContentLength(expectedContentLength)
        coordinator?.driverDidReceiveExpectedContentLength(expectedContentLength)
    }

    public func showDownloadDidReceiveData(ofLength length: UInt64) {
        delegate?.driverDidReceiveData(length: length)
        coordinator?.driverDidReceiveData(length: length)
    }

    // MARK: - SPUUserDriver: Extraction Progress

    public func showDownloadDidStartExtractingUpdate() {
        delegate?.driverDidStartExtracting()
        coordinator?.driverDidStartExtracting()
    }

    public func showExtractionReceivedProgress(_ progress: Double) {
        delegate?.driverDidReceiveExtractionProgress(progress)
        coordinator?.driverDidReceiveExtractionProgress(progress)
    }

    // MARK: - SPUUserDriver: Ready to Install

    public func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        self.heldInstallReply = reply
        if let descriptor = coordinator?.phase.availableDescriptor {
            delegate?.driverIsReadyToInstall(descriptor: descriptor)
            coordinator?.driverIsReadyToInstall(descriptor: descriptor)
        }
    }

    // MARK: - SPUUserDriver: Installing

    public func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        self.heldRetryTerminatingApplication = retryTerminatingApplication
        if let descriptor = coordinator?.phase.availableDescriptor {
            delegate?.driverIsInstalling(descriptor: descriptor)
            coordinator?.driverIsInstalling(descriptor: descriptor)
        }
    }

    public func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        delegate?.driverDidFinishInstallation(relaunched: relaunched)
        coordinator?.driverDidFinishInstallation(relaunched: relaunched)
    }

    // MARK: - SPUUserDriver: Dismiss

    public func dismissUpdateInstallation() {
        heldUpdateChoiceReply = nil
        heldInstallReply = nil
        checkCancellation = nil
        downloadCancellation = nil
        currentAppcastItem = nil
        heldRetryTerminatingApplication = nil
        delegate?.driverDidDismissInstallation()
        coordinator?.driverDidDismissInstallation()
    }

    public func showUpdateInFocus() {
        // Brings update UI into focus if needed
    }

    // MARK: - Explicit User Action Handlers

    public func installUpdate() {
        if let reply = heldInstallReply {
            heldInstallReply = nil
            reply(.install)
        } else if let reply = heldUpdateChoiceReply {
            heldUpdateChoiceReply = nil
            reply(.install)
        }
    }

    public func dismissUpdate() {
        if let reply = heldInstallReply {
            heldInstallReply = nil
            reply(.dismiss)
        } else if let reply = heldUpdateChoiceReply {
            heldUpdateChoiceReply = nil
            reply(.dismiss)
        }
    }

    public func skipUpdate() {
        if let reply = heldInstallReply {
            heldInstallReply = nil
            reply(.skip)
        } else if let reply = heldUpdateChoiceReply {
            heldUpdateChoiceReply = nil
            reply(.skip)
        }
    }

    public func cancelCheck() {
        if let cancel = checkCancellation {
            checkCancellation = nil
            cancel()
        }
    }

    public func cancelDownload() {
        if let cancel = downloadCancellation {
            downloadCancellation = nil
            cancel()
        }
    }
    public func retryTerminatingApplication() {
        guard let retry = heldRetryTerminatingApplication else { return }
        if let coordinator = coordinator {
            let result = coordinator.validateTerminationForRetry()
            if result.isReady {
                retry()
            }
        } else {
            retry()
        }
    }
}
