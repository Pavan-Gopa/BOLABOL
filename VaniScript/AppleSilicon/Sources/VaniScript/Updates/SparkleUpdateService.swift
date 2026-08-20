import Foundation
import Sparkle

/// Delegate implementing Sparkle updater delegation rules.
@MainActor
final class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private let feedURL: URL?

    init(feedURL: URL? = nil) {
        self.feedURL = feedURL
        super.init()
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feedURL?.absoluteString
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        // We configure automatic checks explicitly; do not show Sparkle's initial permission prompt.
        false
    }
}

/// Concrete Sparkle-backed update service.
/// Wraps SPUUpdater, enforces ADR-008 safety contracts (no automatic download or install),
/// and verifies EdDSA public key configuration.
@MainActor
public final class SparkleUpdateService: NSObject, UpdateServiceProtocol {
    private var updater: SPUUpdater?
    private let userDriver: SPUUserDriver
    private let updaterDelegate: SparkleUpdaterDelegate
    private let bundle: Bundle

    public private(set) var isConfigured: Bool = false
    public var feedURL: URL?

    public var isPublicKeyConfigured: Bool {
        guard let key = bundle.object(forInfoDictionaryKey: UpdateConfiguration.publicKeyInfoKey) as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    public var automaticallyChecksForUpdates: Bool {
        get {
            updater?.automaticallyChecksForUpdates ?? false
        }
        set {
            updater?.automaticallyChecksForUpdates = newValue
        }
    }

    public var updateCheckInterval: TimeInterval {
        get {
            updater?.updateCheckInterval ?? 86400
        }
        set {
            updater?.updateCheckInterval = newValue
        }
    }

    public init(
        userDriver: SPUUserDriver,
        bundle: Bundle = .main,
        feedURL: URL? = nil
    ) {
        self.userDriver = userDriver
        self.bundle = bundle
        let effectiveFeedURL = feedURL
            ?? (bundle.object(forInfoDictionaryKey: UpdateConfiguration.feedURLInfoKey) as? String).flatMap(URL.init(string:))
            ?? UpdateConfiguration.defaultFeedURL
        self.feedURL = effectiveFeedURL
        self.updaterDelegate = SparkleUpdaterDelegate(feedURL: effectiveFeedURL)
        super.init()
    }

    public func start() throws {
        guard !isConfigured else { return }

        guard isPublicKeyConfigured else {
            throw UpdateDiagnosticError.missingPublicKey
        }

        let updater = SPUUpdater(
            hostBundle: bundle,
            applicationBundle: bundle,
            userDriver: userDriver,
            delegate: updaterDelegate
        )

        // Safety policies:
        // Background checks are enabled, but automatic downloading/installing is strictly forbidden.
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = false

        do {
            try updater.start()
            self.updater = updater
            self.isConfigured = true
        } catch {
            throw UpdateDiagnosticError.map(from: error as NSError)
        }
    }

    public func checkForUpdates() {
        guard isConfigured, let updater = updater else { return }
        updater.checkForUpdates()
    }

    public func checkForUpdatesInBackground() {
        guard isConfigured, let updater = updater else { return }
        updater.checkForUpdatesInBackground()
    }
}
