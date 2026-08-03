import Foundation

public struct GlossaryLanguageOption: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

public enum GlossaryLanguageCatalog {
    public static let defaultAuthorTranscriptionLanguage = "English"
    public static let defaultAutoTranslationLanguage = "Russian"

    public static let builtIn: [GlossaryLanguageOption] = [
        .init(name: "English"),
        .init(name: "Russian"),
        .init(name: "Dutch"),
        .init(name: "German"),
        .init(name: "Spanish"),
        .init(name: "French"),
        .init(name: "Italian"),
        .init(name: "Portuguese"),
        .init(name: "Chinese"),
        .init(name: "Japanese"),
        .init(name: "Korean"),
        .init(name: "Hindi"),
        .init(name: "Arabic")
    ]

    public static func normalizedName(_ value: String, fallback: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackClean = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = clean.isEmpty ? fallbackClean : clean
        guard !candidate.isEmpty else {
            return defaultAuthorTranscriptionLanguage
        }

        return builtIn.first {
            $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame
        }?.name ?? candidate
    }

    public static func displayName(for language: String) -> String {
        normalizedName(language, fallback: defaultAuthorTranscriptionLanguage)
    }

    public static func defaultAutoTranslationLanguage(for authorLanguage: String) -> String {
        let author = normalizedName(
            authorLanguage,
            fallback: defaultAuthorTranscriptionLanguage
        )
        if author.localizedCaseInsensitiveCompare("English") == .orderedSame {
            return "Russian"
        }
        return "English"
    }
}

public struct GlossarySettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var enabled: Bool
    public var authorTranscriptionLanguage: String
    public var autoTranslationLanguage: String
    public var entries: [GlossaryEntry]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        enabled: Bool = true,
        authorTranscriptionLanguage: String = GlossaryLanguageCatalog.defaultAuthorTranscriptionLanguage,
        autoTranslationLanguage: String = GlossaryLanguageCatalog.defaultAutoTranslationLanguage,
        entries: [GlossaryEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.enabled = enabled
        self.authorTranscriptionLanguage = GlossaryLanguageCatalog.normalizedName(
            authorTranscriptionLanguage,
            fallback: GlossaryLanguageCatalog.defaultAuthorTranscriptionLanguage
        )
        self.autoTranslationLanguage = GlossaryLanguageCatalog.normalizedName(
            autoTranslationLanguage,
            fallback: GlossaryLanguageCatalog.defaultAutoTranslationLanguage
        )
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case enabled
        case authorTranscriptionLanguage
        case autoTranslationLanguage
        case basicLanguage
        case entries
    }

    private enum LegacyBasicLanguage: String, Codable {
        case english
        case russian

        var authorLanguage: String {
            switch self {
            case .english:
                "English"
            case .russian:
                "Russian"
            }
        }

        var autoTranslationLanguage: String {
            switch self {
            case .english:
                "Russian"
            case .russian:
                "English"
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        schemaVersion = max(decodedSchemaVersion, Self.currentSchemaVersion)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true

        let legacyLanguage = try container.decodeIfPresent(LegacyBasicLanguage.self, forKey: .basicLanguage)
        let decodedAuthorLanguage = try container.decodeIfPresent(
            String.self,
            forKey: .authorTranscriptionLanguage
        )
        let decodedAutoLanguage = try container.decodeIfPresent(
            String.self,
            forKey: .autoTranslationLanguage
        )

        let fallbackAuthorLanguage = legacyLanguage?.authorLanguage
            ?? GlossaryLanguageCatalog.defaultAuthorTranscriptionLanguage
        let fallbackAutoLanguage = legacyLanguage?.autoTranslationLanguage
            ?? GlossaryLanguageCatalog.defaultAutoTranslationLanguage(for: fallbackAuthorLanguage)

        authorTranscriptionLanguage = GlossaryLanguageCatalog.normalizedName(
            decodedAuthorLanguage ?? fallbackAuthorLanguage,
            fallback: fallbackAuthorLanguage
        )
        autoTranslationLanguage = GlossaryLanguageCatalog.normalizedName(
            decodedAutoLanguage ?? fallbackAutoLanguage,
            fallback: fallbackAutoLanguage
        )
        entries = try container.decodeIfPresent([GlossaryEntry].self, forKey: .entries) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(authorTranscriptionLanguage, forKey: .authorTranscriptionLanguage)
        try container.encode(autoTranslationLanguage, forKey: .autoTranslationLanguage)
        try container.encode(entries, forKey: .entries)
    }
}
