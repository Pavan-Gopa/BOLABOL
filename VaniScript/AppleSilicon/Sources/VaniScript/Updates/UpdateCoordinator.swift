import Foundation
import SwiftUI

/// Single @MainActor ObservableObject UX state owner for all in-app update operations.
/// Bridges Sparkle's low-level updater / driver lifecycle into high-level reactive SwiftUI state.
@MainActor
public final class UpdateCoordinator: ObservableObject {
    @Published public private(set) var phase: UpdatePhase = .idle
    @Published public private(set) var lastCheckDate: Date?
    @Published public private(set) var isPublicKeyConfigured: Bool
    @Published public private(set) var currentVersion: String
    @Published public private(set) var currentBuildNumber: String
    @Published public var automaticallyChecksForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyChecksForUpdates, forKey: UpdateConfiguration.automaticChecksPreferenceKey)
            service.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    public var feedURL: URL? {
        service.feedURL
    }

    private let service: UpdateServiceProtocol
    private let driver: UpdateUserDriver?
    private var isStarted = false
    public private(set) weak var readinessProvider: UpdateReadinessProviding?
    public let terminationCoordinator: UpdateTerminationCoordinator
    public let receiptStore: UpdateReceiptStore


    private var totalDownloadBytes: UInt64 = 0
    private var receivedDownloadBytes: UInt64 = 0
    private var currentDescriptor: UpdateDescriptor?

    public init(
        service: UpdateServiceProtocol? = nil,
        driver: UpdateUserDriver? = nil,
        readinessProvider: UpdateReadinessProviding? = nil,
        terminationCoordinator: UpdateTerminationCoordinator? = nil,
        receiptStore: UpdateReceiptStore = UpdateReceiptStore(),
        currentVersion: String? = nil,
        currentBuildNumber: String? = nil,
        bundle: Bundle = .main
    ) {
        self.readinessProvider = readinessProvider
        self.receiptStore = receiptStore
        let termCoord = terminationCoordinator ?? UpdateTerminationCoordinator(readinessProvider: readinessProvider)
        self.terminationCoordinator = termCoord
        let resolvedVersion = currentVersion
            ?? bundle.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "1.0.0"
        let resolvedBuild = currentBuildNumber
            ?? bundle.infoDictionary?["CFBundleVersion"] as? String
            ?? "1"

        self.currentVersion = resolvedVersion
        self.currentBuildNumber = resolvedBuild

        let hasPublicKey: Bool
        if let key = bundle.object(forInfoDictionaryKey: UpdateConfiguration.publicKeyInfoKey) as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasPublicKey = true
        } else {
            hasPublicKey = false
        }
        self.isPublicKeyConfigured = hasPublicKey

        let savedAutoCheck = UserDefaults.standard.object(forKey: UpdateConfiguration.automaticChecksPreferenceKey) as? Bool ?? true
        self.automaticallyChecksForUpdates = savedAutoCheck

        if let service = service {
            self.service = service
            self.driver = driver
        } else {
            let userDriver = UpdateUserDriver()
            let sparkleService = SparkleUpdateService(userDriver: userDriver, bundle: bundle)
            self.driver = userDriver
            self.service = sparkleService
            userDriver.coordinator = self
        }
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        guard isPublicKeyConfigured else {
            // Diagnostic notice: do not attempt to start live updater without valid key.
            return
        }

        do {
            try service.start()
        } catch let error as UpdateDiagnosticError {
            phase = .failed(error)
        } catch {
            phase = .failed(UpdateDiagnosticError.map(from: error as NSError))
        }
    }

    // MARK: - User Commands

    public func checkForUpdates() {
        guard isPublicKeyConfigured else {
            phase = .failed(.missingPublicKey)
            return
        }

        guard !phase.isBusy else { return }

        phase = .checking(isUserInitiated: true)
        service.checkForUpdates()
    }

    public func checkForUpdatesInBackground() {
        guard isPublicKeyConfigured else { return }
        guard !phase.isBusy else { return }

        phase = .checking(isUserInitiated: false)
        service.checkForUpdatesInBackground()
    }

    public func setReadinessProvider(_ provider: UpdateReadinessProviding) {
        self.readinessProvider = provider
        self.terminationCoordinator.setReadinessProvider(provider)
    }

    public func installUpdate() {
        let prepResult = terminationCoordinator.prepareAndValidateTermination()
        guard prepResult.isReady else {
            let message = prepResult.failureDescription ?? "Update blocked by active operations or unsaved state."
            phase = .failed(UpdateDiagnosticError(kind: .installationFailed, message: message, recoverySuggestion: "Resolve active operations or unsaved state before updating."))
            return
        }

        if let descriptor = currentDescriptor {
            try? receiptStore.recordUpdate(
                previousVersion: currentVersion,
                previousBuild: currentBuildNumber,
                targetVersion: descriptor.displayVersion,
                targetBuild: descriptor.buildNumber
            )
        }

        driver?.installUpdate()
    }

    @discardableResult
    public func validateTerminationForRetry() -> TerminationPreparationResult {
        let prepResult = terminationCoordinator.prepareAndValidateTermination()
        if !prepResult.isReady {
            let message = prepResult.failureDescription ?? "Termination blocked by active operations or unsaved state."
            phase = .failed(UpdateDiagnosticError(kind: .installationFailed, message: message, recoverySuggestion: "Resolve active operations or unsaved state before updating."))
        }
        return prepResult
    }

    public func checkAndSurfacePostRelaunchReceipt(workflowStore: WorkflowStore? = nil) {
        guard let receipt = receiptStore.loadReceipt() else { return }
        if receipt.status == .success {
            let message = "VaniScript was successfully updated to version \(receipt.installedVersion)."
            if let store = workflowStore {
                store.statusMessage = message
            }
        }
        receiptStore.clearReceipt()
    }

    public func dismissUpdate() {
        driver?.dismissUpdate()
        currentDescriptor = nil
        totalDownloadBytes = 0
        receivedDownloadBytes = 0
        phase = .idle
    }

    public func skipUpdate() {
        driver?.skipUpdate()
        currentDescriptor = nil
        totalDownloadBytes = 0
        receivedDownloadBytes = 0
        phase = .idle
    }

    public func cancelActiveOperation() {
        driver?.cancelCheck()
        driver?.cancelDownload()
        totalDownloadBytes = 0
        receivedDownloadBytes = 0
        phase = .idle
    }

    public func retryLastAction() {
        checkForUpdates()
    }

    public func clearError() {
        if case .failed = phase {
            phase = .idle
        }
    }

    // MARK: - Driver Event Callbacks

    public func driverDidBeginCheck(isUserInitiated: Bool, cancellation: @escaping () -> Void) {
        phase = .checking(isUserInitiated: isUserInitiated)
    }

    public func driverDidFindUpdate(descriptor: UpdateDescriptor, isUserInitiated: Bool) {
        self.currentDescriptor = descriptor
        self.lastCheckDate = Date()
        self.phase = .available(descriptor)
    }

    public func driverDidReceiveReleaseNotes(html: String?, text: String?) {
        guard var desc = currentDescriptor else { return }
        desc = UpdateDescriptor(
            id: desc.id,
            version: desc.version,
            displayVersion: desc.displayVersion,
            buildNumber: desc.buildNumber,
            releaseNotesURL: desc.releaseNotesURL,
            releaseNotesHTML: html ?? desc.releaseNotesHTML,
            releaseNotesDescription: text ?? desc.releaseNotesDescription,
            title: desc.title,
            isCritical: desc.isCritical,
            isInformationalOnly: desc.isInformationalOnly,
            infoURL: desc.infoURL,
            contentLength: desc.contentLength,
            publishDate: desc.publishDate
        )
        self.currentDescriptor = desc
        if case .available = phase {
            self.phase = .available(desc)
        }
    }

    public func driverDidNotFindUpdate() {
        let now = Date()
        self.lastCheckDate = now
        self.phase = .upToDate(lastChecked: now)
    }

    public func driverDidFail(with error: UpdateDiagnosticError) {
        self.phase = .failed(error)
    }

    public func driverDidInitiateDownload(cancellation: @escaping () -> Void) {
        self.receivedDownloadBytes = 0
        if let desc = currentDescriptor {
            self.phase = .downloading(
                desc,
                progress: 0.0,
                bytesReceived: 0,
                totalBytes: totalDownloadBytes
            )
        }
    }

    public func driverDidReceiveExpectedContentLength(_ expectedLength: UInt64) {
        self.totalDownloadBytes = expectedLength
        if let desc = currentDescriptor {
            let progress = totalDownloadBytes > 0
                ? Double(receivedDownloadBytes) / Double(totalDownloadBytes)
                : 0.0
            self.phase = .downloading(
                desc,
                progress: progress,
                bytesReceived: receivedDownloadBytes,
                totalBytes: totalDownloadBytes
            )
        }
    }

    public func driverDidReceiveData(length: UInt64) {
        self.receivedDownloadBytes += length
        let progress = totalDownloadBytes > 0
            ? min(1.0, Double(receivedDownloadBytes) / Double(totalDownloadBytes))
            : 0.0
        if let desc = currentDescriptor {
            self.phase = .downloading(
                desc,
                progress: progress,
                bytesReceived: receivedDownloadBytes,
                totalBytes: totalDownloadBytes
            )
        }
    }

    public func driverDidStartExtracting() {
        if let desc = currentDescriptor {
            self.phase = .extracting(desc, progress: 0.0)
        }
    }

    public func driverDidReceiveExtractionProgress(_ progress: Double) {
        if let desc = currentDescriptor {
            self.phase = .extracting(desc, progress: progress)
        }
    }

    public func driverIsReadyToInstall(descriptor: UpdateDescriptor) {
        self.currentDescriptor = descriptor
        self.phase = .readyToInstall(descriptor)
    }

    public func driverIsInstalling(descriptor: UpdateDescriptor) {
        self.phase = .installing(descriptor)
    }

    public func driverDidFinishInstallation(relaunched: Bool) {
        let now = Date()
        self.lastCheckDate = now
        self.phase = .upToDate(lastChecked: now)
    }

    public func driverDidDismissInstallation() {
        self.currentDescriptor = nil
        self.totalDownloadBytes = 0
        self.receivedDownloadBytes = 0
        self.phase = .idle
    }
}
