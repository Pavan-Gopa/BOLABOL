import Foundation

/// Result of pre-termination preparation and readiness validation.
public enum TerminationPreparationResult: Equatable, Sendable {
    case readyToTerminate
    case blocked(reasons: [UpdateBlockingReason])
    case saveFailed(message: String)
    case backupFailed(message: String)

    public var isReady: Bool {
        if case .readyToTerminate = self { return true }
        return false
    }

    public var failureDescription: String? {
        switch self {
        case .readyToTerminate:
            return nil
        case .blocked(let reasons):
            return reasons.map(\.description).joined(separator: "; ")
        case .saveFailed(let message):
            return "Save failed before update: \(message)"
        case .backupFailed(let message):
            return "Metadata backup failed before update: \(message)"
        }
    }
}

/// Orchestrates pre-update save, metadata backup, editing freeze, and readiness re-check.
@MainActor
public final class UpdateTerminationCoordinator {
    public private(set) weak var readinessProvider: UpdateReadinessProviding?
    private let fileManager: FileManager
    private let backupDirectory: URL

    public init(
        readinessProvider: UpdateReadinessProviding? = nil,
        fileManager: FileManager = .default,
        backupDirectory: URL = AppStoragePaths.updateBackupDirectory()
    ) {
        self.readinessProvider = readinessProvider
        self.fileManager = fileManager
        self.backupDirectory = backupDirectory
    }

    public func setReadinessProvider(_ provider: UpdateReadinessProviding) {
        self.readinessProvider = provider
    }

    /// Complete pre-termination sequence:
    /// 1. Initial readiness check
    /// 2. Save pending state
    /// 3. Create metadata backup (projects.json, settings.json)
    /// 4. Freeze editing UI
    /// 5. Final readiness re-check
    public func prepareAndValidateTermination() -> TerminationPreparationResult {
        guard let provider = readinessProvider else {
            return .readyToTerminate
        }

        // 1. Initial readiness check
        let initialSnapshot = provider.updateReadinessSnapshot
        guard initialSnapshot.isReady else {
            return .blocked(reasons: initialSnapshot.blockingReasons)
        }

        // 2. Save pending state synchronously
        let saveSuccess = provider.prepareForUpdateTermination()
        guard saveSuccess else {
            let updatedSnapshot = provider.updateReadinessSnapshot
            if !updatedSnapshot.isReady {
                return .blocked(reasons: updatedSnapshot.blockingReasons)
            }
            return .saveFailed(message: "Failed to persist projects or settings to disk.")
        }

        // 3. Create metadata backup
        do {
            try createMetadataBackup()
        } catch {
            return .backupFailed(message: error.localizedDescription)
        }

        // 4. Freeze editing
        provider.freezeEditingForUpdate()

        // 5. Final readiness re-check
        let finalSnapshot = provider.updateReadinessSnapshot
        guard finalSnapshot.isReady else {
            return .blocked(reasons: finalSnapshot.blockingReasons)
        }

        return .readyToTerminate
    }

    /// Creates metadata backup of projects.json and settings.json in update backup directory.
    /// Does NOT touch recordings, imports, or local models directories.
    public func createMetadataBackup() throws {
        if !fileManager.fileExists(atPath: backupDirectory.path) {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        }

        let projectsURL = AppStoragePaths.projectsURL(fileManager: fileManager)
        let settingsURL = AppStoragePaths.settingsURL(fileManager: fileManager)

        let timestamp = Int(Date().timeIntervalSince1970)
        let backupSubdir = backupDirectory.appendingPathComponent("backup_\(timestamp)", isDirectory: true)
        try fileManager.createDirectory(at: backupSubdir, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: projectsURL.path) {
            let target = backupSubdir.appendingPathComponent("projects.json")
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: projectsURL, to: target)
        }

        if fileManager.fileExists(atPath: settingsURL.path) {
            let target = backupSubdir.appendingPathComponent("settings.json")
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: settingsURL, to: target)
        }
    }
}
