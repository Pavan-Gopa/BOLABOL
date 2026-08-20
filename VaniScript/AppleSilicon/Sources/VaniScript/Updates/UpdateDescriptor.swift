import Foundation

/// Describes an available software update package retrieved from the appcast feed.
public struct UpdateDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let version: String
    public let displayVersion: String
    public let buildNumber: String
    public let releaseNotesURL: URL?
    public let releaseNotesHTML: String?
    public let releaseNotesDescription: String?
    public let title: String?
    public let isCritical: Bool
    public let isInformationalOnly: Bool
    public let infoURL: URL?
    public let contentLength: UInt64
    public let publishDate: Date?

    public init(
        id: String? = nil,
        version: String,
        displayVersion: String? = nil,
        buildNumber: String? = nil,
        releaseNotesURL: URL? = nil,
        releaseNotesHTML: String? = nil,
        releaseNotesDescription: String? = nil,
        title: String? = nil,
        isCritical: Bool = false,
        isInformationalOnly: Bool = false,
        infoURL: URL? = nil,
        contentLength: UInt64 = 0,
        publishDate: Date? = nil
    ) {
        let resolvedDisplay = displayVersion ?? version
        let resolvedBuild = buildNumber ?? version
        self.id = id ?? "\(version)-\(resolvedBuild)"
        self.version = version
        self.displayVersion = resolvedDisplay
        self.buildNumber = resolvedBuild
        self.releaseNotesURL = releaseNotesURL
        self.releaseNotesHTML = releaseNotesHTML
        self.releaseNotesDescription = releaseNotesDescription
        self.title = title
        self.isCritical = isCritical
        self.isInformationalOnly = isInformationalOnly
        self.infoURL = infoURL
        self.contentLength = contentLength
        self.publishDate = publishDate
    }

    public var humanReadableSize: String {
        guard contentLength > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(contentLength))
    }
}
