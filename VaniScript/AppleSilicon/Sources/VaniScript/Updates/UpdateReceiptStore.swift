import Foundation

/// Durable record of an in-app update installation and relaunch health state.
public struct UpdateReceipt: Codable, Equatable, Sendable {
    public let previousVersion: String
    public let previousBuild: String
    public let installedVersion: String
    public let installedBuild: String
    public let installedAt: Date
    public let status: HealthStatus

    public enum HealthStatus: String, Codable, Equatable, Sendable {
        case success
        case failed
    }

    public init(
        previousVersion: String,
        previousBuild: String,
        installedVersion: String,
        installedBuild: String,
        installedAt: Date = Date(),
        status: HealthStatus = .success
    ) {
        self.previousVersion = previousVersion
        self.previousBuild = previousBuild
        self.installedVersion = installedVersion
        self.installedBuild = installedBuild
        self.installedAt = installedAt
        self.status = status
    }
}

/// Disk store for persisting and retrieving update launch receipts.
public final class UpdateReceiptStore: @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL = AppStoragePaths.updateReceiptURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func recordUpdate(
        previousVersion: String,
        previousBuild: String,
        targetVersion: String,
        targetBuild: String,
        status: UpdateReceipt.HealthStatus = .success
    ) throws {
        let receipt = UpdateReceipt(
            previousVersion: previousVersion,
            previousBuild: previousBuild,
            installedVersion: targetVersion,
            installedBuild: targetBuild,
            installedAt: Date(),
            status: status
        )
        try saveReceipt(receipt)
    }

    public func saveReceipt(_ receipt: UpdateReceipt) throws {
        let parentDir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(receipt)
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadReceipt() -> UpdateReceipt? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(UpdateReceipt.self, from: data)
        } catch {
            return nil
        }
    }

    public func clearReceipt() {
        try? fileManager.removeItem(at: fileURL)
    }
}
