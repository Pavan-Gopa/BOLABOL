import Foundation

/// Protocol abstraction over the Sparkle updater service to enable deterministic testing
/// with mock/fake services that never touch the network or invoke live installers.
@MainActor
public protocol UpdateServiceProtocol: AnyObject {
    var isConfigured: Bool { get }
    var isPublicKeyConfigured: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var updateCheckInterval: TimeInterval { get set }
    var feedURL: URL? { get set }

    func start() throws
    func checkForUpdates()
    func checkForUpdatesInBackground()
}
