import Foundation

// B1 — Canonical speech-language pair (plan §3.3, §3.4).
//
// Terminology (plan §3.1): `primary` is the language the user usually dictates
// in; `additional` is a second language they regularly use. `additional` is
// *not* an "always output in this language" target — never call it that in UI
// copy. The two codes may be equal (same-as-primary policy, plan §3.4).
public struct UserSpeechLanguages: Codable, Equatable, Sendable {
    public var primaryLanguageCode: String
    public var additionalLanguageCode: String

    public init(primaryLanguageCode: String, additionalLanguageCode: String) {
        self.primaryLanguageCode = Self.normalized(primaryLanguageCode)
        self.additionalLanguageCode = Self.normalized(additionalLanguageCode)
    }

    /// Fresh-install defaults (plan §3.4), matching `makeDefaults()` for the
    /// current system locale.
    public init() {
        self = .makeDefaults()
    }

    /// Fresh-install defaults (plan §3.4): primary maps the system locale when
    /// it is a known speech language, otherwise `en`; additional is `en` when
    /// primary differs, otherwise the same-as-primary value (`en`).
    public static func makeDefaults(systemLocale: Locale = .current) -> UserSpeechLanguages {
        let primary = Self.systemLocaleSpeechCode(systemLocale) ?? LanguagePickerOrder.englishCode
        // Plan §3.4: additional = "en" when primary != en; when primary is
        // already English the pair is trivially same-as-primary (also "en").
        let additional = LanguagePickerOrder.englishCode
        return UserSpeechLanguages(
            primaryLanguageCode: primary,
            additionalLanguageCode: additional
        )
    }

    /// Best-effort migration from legacy transcription / force-target prefs
    /// (plan §3.4 "Migration from old installs").
    ///
    /// - `legacyTranscriptionCode`: the explicit language the old
    ///   `TranscriptionModelSettings.languagePreference` carried (nil when the
    ///   old preference was auto-detection).
    /// - `legacyTargetLanguageName`: the old `translation.targetLanguage`
    ///   string (a name or code), historically the "force target" language.
    ///
    /// Migration is best-effort: unknown/empty legacy values fall back to the
    /// fresh-install defaults. The old auto-detect behavior itself is preserved
    /// (plan §4.1) — only the *pair* is seeded from legacy data.
    public static func migrating(
        legacyTranscriptionCode: String?,
        legacyTargetLanguageName: String?,
        systemLocale: Locale = .current
    ) -> UserSpeechLanguages {
        let primary: String
        if let code = legacyTranscriptionCode.map(Self.normalized),
           LanguagePickerOrder.isKnownSpeechCode(code) {
            primary = code
        } else {
            primary = Self.systemLocaleSpeechCode(systemLocale) ?? LanguagePickerOrder.englishCode
        }

        let additional: String
        if let name = legacyTargetLanguageName,
           let code = LanguagePickerOrder.speechCode(forNameOrCode: name),
           code != primary {
            additional = code
        } else {
            // Plan §3.4: "en if primary != en, else en (same)". English is the
            // most common second language; when primary is already English the
            // pair is trivially same-as-primary.
            additional = LanguagePickerOrder.englishCode
        }

        return UserSpeechLanguages(
            primaryLanguageCode: primary,
            additionalLanguageCode: additional
        )
    }

    public var usesSameAdditionalAsPrimary: Bool {
        additionalLanguageCode == primaryLanguageCode
    }

    /// Same-as-primary policy (plan §3.4, §7.1): user explicitly wants no
    /// second language, so additional mirrors primary.
    public func settingAdditionalSameAsPrimary() -> UserSpeechLanguages {
        UserSpeechLanguages(
            primaryLanguageCode: primaryLanguageCode,
            additionalLanguageCode: primaryLanguageCode
        )
    }

    /// Changes primary (B2 onboarding / B3 settings). When the pair currently
    /// uses the same-as-primary policy, additional follows the new primary so
    /// the mirror stays intact; otherwise the explicit additional is kept.
    public func settingPrimary(_ code: String) -> UserSpeechLanguages {
        let normalized = Self.normalized(code)
        let additional = usesSameAdditionalAsPrimary
            ? normalized
            : additionalLanguageCode
        return UserSpeechLanguages(
            primaryLanguageCode: normalized,
            additionalLanguageCode: additional
        )
    }

    /// Changes additional (B3 settings / B2 onboarding additional picker).
    /// Primary is untouched. When the new additional equals primary the pair
    /// is back in the same-as-primary state (plan §3.4, §7.1).
    public func settingAdditional(_ code: String) -> UserSpeechLanguages {
        UserSpeechLanguages(
            primaryLanguageCode: primaryLanguageCode,
            additionalLanguageCode: code
        )
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case primaryLanguageCode
        case additionalLanguageCode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let primary = try container.decodeIfPresent(String.self, forKey: .primaryLanguageCode)
            ?? LanguagePickerOrder.englishCode
        let additional = try container.decodeIfPresent(String.self, forKey: .additionalLanguageCode)
            ?? LanguagePickerOrder.englishCode
        self.init(primaryLanguageCode: primary, additionalLanguageCode: additional)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(primaryLanguageCode, forKey: .primaryLanguageCode)
        try container.encode(additionalLanguageCode, forKey: .additionalLanguageCode)
    }

    // MARK: - Helpers

    private static func normalized(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? LanguagePickerOrder.englishCode : trimmed
    }

    private static func systemLocaleSpeechCode(_ locale: Locale) -> String? {
        let identifier = locale.identifier.lowercased()
        for code in LanguagePickerOrder.orderedSpeechCodes where identifier.hasPrefix(code) {
            return code
        }
        return nil
    }
}
