import AppKit
import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

/// Discrete phases of the background / user-driven update workflow.
public enum UpdatePhase: Equatable, Sendable {
    case idle
    case checking
    case preparing(version: String)
    case ready(version: String)
    case waitingForSafeRelaunch(version: String)
    case installing(version: String)
    case failed(version: String?, message: String)

    public var version: String? {
        switch self {
        case .idle, .checking:
            return nil
        case .preparing(let version),
             .ready(let version),
             .waitingForSafeRelaunch(let version),
             .installing(let version):
            return version
        case .failed(let version, _):
            return version
        }
    }
}

/// Delegation interface from an update driver to the observable coordinator.
@MainActor
public protocol UpdateDriverDelegate: AnyObject {
    func driverDidFindUpdate(version: String)
    func driverDidNotFindUpdate()
    func driverDidStartDownloadingUpdate(version: String)
    func driverDidPrepareUpdate(version: String, installHandler: @escaping () -> Void)
    func driverDidFailUpdate(version: String?, errorDescription: String)
    func driverDidCancelUpdate()
    func driverDidFinishUpdateSession()
}

/// Abstract updater driver seam allowing Sparkle in production and deterministic fakes in tests.
@MainActor
public protocol UpdateDriving: AnyObject {
    var canCheckForUpdates: Bool { get }
    func setDelegate(_ delegate: (any UpdateDriverDelegate)?)
    func start()
    func checkForUpdates()
}

#if canImport(Sparkle)
/// Production driver wrapping Sparkle 2's `SPUStandardUpdaterController`.
@MainActor
public final class SparkleUpdateDriver: NSObject, UpdateDriving {
    private var updaterController: SPUStandardUpdaterController?
    private weak var delegate: (any UpdateDriverDelegate)?

    public override init() {
        super.init()
    }

    public func setDelegate(_ delegate: (any UpdateDriverDelegate)?) {
        self.delegate = delegate
    }

    public func start() {
        guard updaterController == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        self.updaterController = controller
    }

    public var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }

    public func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}

extension SparkleUpdateDriver: @preconcurrency SPUStandardUserDriverDelegate {
    // MARK: - SPUStandardUserDriverDelegate (Gentle scheduled update reminders)

    public nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    public func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Suppress automatic modal popup on scheduled checks; surface in title bar instead.
        false
    }

    public func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        delegate?.driverDidFindUpdate(version: update.displayVersionString)
    }

    public func standardUserDriverWillFinishUpdateSession() {
        delegate?.driverDidFinishUpdateSession()
    }
}

extension SparkleUpdateDriver: SPUUpdaterDelegate {
    // MARK: - SPUUpdaterDelegate

    public func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        let version = item.displayVersionString
        delegate?.driverDidPrepareUpdate(version: version, installHandler: immediateInstallHandler)
        return true
    }

    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        delegate?.driverDidFindUpdate(version: item.displayVersionString)
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        delegate?.driverDidNotFindUpdate()
    }

    public func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        // SUSparkleErrorDomain error 2001 (SUNoUpdateError) represents up-to-date state.
        if nsError.domain == "SUSparkleErrorDomain" && nsError.code == 2001 {
            delegate?.driverDidNotFindUpdate()
            return
        }
        // SUSparkleErrorDomain error 4001 (SUInstallationCanceledError) represents user cancellation.
        if nsError.domain == "SUSparkleErrorDomain" && nsError.code == 4001 {
            delegate?.driverDidCancelUpdate()
            return
        }
        delegate?.driverDidFailUpdate(version: nil, errorDescription: error.localizedDescription)
    }

    public func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        delegate?.driverDidFailUpdate(version: item.displayVersionString, errorDescription: error.localizedDescription)
    }

    public func userDidCancelDownload(_ updater: SPUUpdater) {
        delegate?.driverDidCancelUpdate()
    }

    public func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        delegate?.driverDidStartDownloadingUpdate(version: item.displayVersionString)
    }
}
#endif

/// Fallback or test fake updater driver.
@MainActor
public final class FakeUpdateDriver: UpdateDriving {
    public var canCheckForUpdates: Bool = true
    public private(set) var checkForUpdatesCallCount = 0
    public private(set) var startCallCount = 0
    public weak var delegate: (any UpdateDriverDelegate)?

    public init() {}

    public func setDelegate(_ delegate: (any UpdateDriverDelegate)?) {
        self.delegate = delegate
    }

    public func start() {
        startCallCount += 1
    }

    public func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }

    // Test simulation helpers
    public func simulateFoundUpdate(version: String) {
        delegate?.driverDidFindUpdate(version: version)
    }

    public func simulateNoUpdate() {
        delegate?.driverDidNotFindUpdate()
    }

    public func simulateDownloading(version: String) {
        delegate?.driverDidStartDownloadingUpdate(version: version)
    }

    public func simulatePreparedUpdate(version: String, installHandler: @escaping () -> Void) {
        delegate?.driverDidPrepareUpdate(version: version, installHandler: installHandler)
    }

    public func simulateFailure(version: String?, errorDescription: String) {
        delegate?.driverDidFailUpdate(version: version, errorDescription: errorDescription)
    }

    public func simulateCancel() {
        delegate?.driverDidCancelUpdate()
    }

    public func simulateFinishSession() {
        delegate?.driverDidFinishUpdateSession()
    }
}

/// Observable coordinator managing app update status, prepared installation, and safe relaunch.
///
/// Invariants:
/// - Conforms to Sparkle 2.9.4 delegate contracts.
/// - Retains the prepared immediate installation block across canceled or rejected relaunches.
/// - Invokes `UpdateRelaunchGate` before triggering atomic installation and relaunch.
/// - Exposes discrete phases (.idle, .checking, .preparing, .ready, .waitingForSafeRelaunch, .installing, .failed).
@MainActor
public final class UpdateCoordinator: ObservableObject, UpdateDriverDelegate {
    public static let defaultReleasePageURL = URL(string: "https://github.com/Pavan-Gopa/BOLABOL/releases/latest")!

    @Published public private(set) var phase: UpdatePhase = .idle
    @Published public private(set) var lastKnownVersion: String?

    public let relaunchGate: UpdateRelaunchGate
    private let driver: any UpdateDriving
    private let urlOpener: @Sendable (URL) -> Bool
    private var isStarted = false
    private var preparedInstallHandler: (() -> Void)?
    private var preparedVersion: String?

    public init(
        driver: (any UpdateDriving)? = nil,
        relaunchGate: UpdateRelaunchGate = .shared,
        urlOpener: (@Sendable (URL) -> Bool)? = nil
    ) {
        #if canImport(Sparkle)
        let resolvedDriver = driver ?? SparkleUpdateDriver()
        #else
        let resolvedDriver = driver ?? FakeUpdateDriver()
        #endif
        self.driver = resolvedDriver
        self.relaunchGate = relaunchGate
        self.urlOpener = urlOpener ?? { url in
            NSWorkspace.shared.open(url)
        }
        self.driver.setDelegate(self)
    }

    public static func live(relaunchGate: UpdateRelaunchGate = .shared) -> UpdateCoordinator {
        let coordinator = UpdateCoordinator(relaunchGate: relaunchGate)
        coordinator.start()
        return coordinator
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        driver.start()
    }

    public var isUpdateAvailable: Bool {
        switch phase {
        case .ready, .waitingForSafeRelaunch, .installing, .preparing, .failed:
            return lastKnownVersion != nil
        case .idle, .checking:
            return false
        }
    }

    public var isReadyToInstall: Bool {
        if case .ready = phase {
            return true
        }
        return false
    }

    public var currentVersion: String? {
        lastKnownVersion
    }

    /// User-initiated check for updates.
    public func checkForUpdates() {
        switch phase {
        case .installing, .waitingForSafeRelaunch:
            return
        case .ready:
            // Already prepared and ready to install
            return
        case .idle, .checking, .preparing, .failed:
            phase = .checking
            driver.checkForUpdates()
        }
    }

    /// Attempts to install the prepared update after satisfying `UpdateRelaunchGate`.
    public func installPreparedUpdate() async {
        guard let handler = preparedInstallHandler, let version = preparedVersion else {
            checkForUpdates()
            return
        }

        phase = .waitingForSafeRelaunch(version: version)

        do {
            try await relaunchGate.prepareForUpdateRelaunch()
            phase = .installing(version: version)
            handler()
        } catch {
            // Keep preparedInstallHandler retained so user can retry after stopping recording or resolving issues
            phase = .failed(version: version, message: error.localizedDescription)
        }
    }

    /// Retries either prepared installation or update check based on current state.
    public func retry() {
        if preparedInstallHandler != nil && preparedVersion != nil {
            Task {
                await installPreparedUpdate()
            }
        } else {
            checkForUpdates()
        }
    }

    @discardableResult
    public func openReleasePage(url: URL = defaultReleasePageURL) -> Bool {
        urlOpener(url)
    }

    /// Dismisses error state and restores appropriate ready or idle state.
    public func dismiss() {
        if case .failed = phase {
            if let preparedVersion, preparedInstallHandler != nil {
                phase = .ready(version: preparedVersion)
            } else if let lastKnownVersion {
                phase = .preparing(version: lastKnownVersion)
            } else {
                phase = .idle
            }
        }
    }

    // MARK: - UpdateDriverDelegate

    public func driverDidFindUpdate(version: String) {
        lastKnownVersion = version
        if preparedInstallHandler == nil {
            phase = .preparing(version: version)
        }
    }

    public func driverDidNotFindUpdate() {
        if case .checking = phase {
            phase = .idle
        }
    }

    public func driverDidStartDownloadingUpdate(version: String) {
        lastKnownVersion = version
        if preparedInstallHandler == nil {
            phase = .preparing(version: version)
        }
    }

    public func driverDidPrepareUpdate(version: String, installHandler: @escaping () -> Void) {
        lastKnownVersion = version
        preparedVersion = version
        preparedInstallHandler = installHandler
        phase = .ready(version: version)
    }

    public func driverDidFailUpdate(version: String?, errorDescription: String) {
        let targetVersion = version ?? preparedVersion ?? lastKnownVersion
        phase = .failed(version: targetVersion, message: errorDescription)
    }

    public func driverDidCancelUpdate() {
        if let preparedVersion, preparedInstallHandler != nil {
            phase = .ready(version: preparedVersion)
        } else {
            phase = .idle
        }
    }

    public func driverDidFinishUpdateSession() {
        switch phase {
        case .checking:
            phase = .idle
        default:
            break
        }
    }
}
