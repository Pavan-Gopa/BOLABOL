import Foundation

public enum ProjectAssetRole: String, Codable, CaseIterable, Equatable, Sendable {
    case originalSource
    case localizedDocument
    case mediaChunk
    case auxiliary
}

public struct ProjectAssetManifestEntry: Codable, Equatable, Sendable {
    public var key: String
    public var role: ProjectAssetRole
    public var language: String?
    public var format: String
    public var originalFileName: String
    public var sha256: String
    public var size: Int64
    /// Logical keys that resolve to this one physical asset after role+hash
    /// deduplication. The field is optional for compatibility with the PRD v4
    /// shape, which only requires the seven fields above.
    public var aliases: [String]?

    public init(
        key: String,
        role: ProjectAssetRole,
        language: String? = nil,
        format: String,
        originalFileName: String,
        sha256: String,
        size: Int64,
        aliases: [String]? = nil
    ) {
        self.key = key
        self.role = role
        self.language = language
        self.format = format
        self.originalFileName = originalFileName
        self.sha256 = sha256
        self.size = size
        self.aliases = aliases
    }

    private enum CodingKeys: String, CodingKey {
        case key, role, language, format, originalFileName, sha256, size, aliases
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try container.decode(String.self, forKey: .key)
        self.role = try container.decode(ProjectAssetRole.self, forKey: .role)
        self.language = try container.decodeIfPresent(String.self, forKey: .language)
        self.format = try container.decode(String.self, forKey: .format)
        self.originalFileName = try container.decode(String.self, forKey: .originalFileName)
        self.sha256 = try container.decodeIfPresent(String.self, forKey: .sha256) ?? ""
        self.size = try container.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        self.aliases = try container.decodeIfPresent([String].self, forKey: .aliases)
    }
}

public struct ProjectAssetManifest: Codable, Equatable, Sendable {
    public var entries: [ProjectAssetManifestEntry]

    public init(entries: [ProjectAssetManifestEntry] = []) {
        self.entries = entries
    }
    public init(assets: [ProjectAssetManifestEntry]) {
        self.entries = assets
    }

    public var assets: [ProjectAssetManifestEntry] {
        get { entries }
        set { entries = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case entries
        case assets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.entries = try container.decodeIfPresent([ProjectAssetManifestEntry].self, forKey: .entries)
            ?? (try container.decodeIfPresent([ProjectAssetManifestEntry].self, forKey: .assets))
            ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
    }
}
