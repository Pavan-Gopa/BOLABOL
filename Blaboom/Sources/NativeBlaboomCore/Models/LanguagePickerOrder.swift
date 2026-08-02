import Foundation

// B1 — Canonical language picker order (plan §5).
//
// Ordering principle (plan §5.2, §5.3): English first, then Europe sorted
// alphabetically by English name, then Asia & other sorted alphabetically.
// Display names are endonyms (Français, Deutsch, Русский, 中文…) per §5.2.
// The System UI-language sentinel lives apart from the speech list — it is
// never placed between `en` and `fr`.

/// A speech language shown in primary/additional pickers (plan §5.4).
public struct SpeechLanguage: Identifiable, Equatable, Sendable {
    public var code: String
    public var displayName: String

    public var id: String { code }

    public init(code: String, displayName: String) {
        self.code = code
        self.displayName = displayName
    }
}

public enum LanguagePickerOrder {
    public static let englishCode = "en"

    /// Europe, alphabetical by English name (plan §5.3).
    public static let europeCodes: [String] = [
        "fr", "de", "it", "pl", "pt", "ru", "es", "tr", "uk"
    ]

    /// Asia & other, alphabetical (plan §5.3).
    public static let asiaOtherCodes: [String] = [
        "ar", "zh", "hi", "ja", "ko"
    ]

    /// Canonical speech-list order: English → Europe → Asia & other.
    public static var orderedSpeechCodes: [String] {
        [englishCode] + europeCodes + asiaOtherCodes
    }

    /// English names for the canonical codes. UI display stays endonym
    /// (plan §5.2); English names are used to resolve legacy string values
    /// such as the old `translation.targetLanguage` preference.
    public static let englishNamesByCode: [String: String] = [
        "en": "English",
        "fr": "French",
        "de": "German",
        "it": "Italian",
        "pl": "Polish",
        "pt": "Portuguese",
        "ru": "Russian",
        "es": "Spanish",
        "tr": "Turkish",
        "uk": "Ukrainian",
        "ar": "Arabic",
        "zh": "Chinese",
        "hi": "Hindi",
        "ja": "Japanese",
        "ko": "Korean"
    ]

    /// Speech languages for primary/additional pickers (no System sentinel —
    /// the sentinel only belongs to UI-language lists).
    public static var speechLanguages: [SpeechLanguage] {
        orderedSpeechCodes.map { code in
            SpeechLanguage(code: code, displayName: displayName(for: code))
        }
    }

    /// UI-language picker list: System sentinel first, then the canonical
    /// speech order. The sentinel is never inserted between `en` and `fr`.
    public static var uiLanguages: [UILanguagePreference] {
        [.system] + orderedSpeechCodes.compactMap { UILanguagePreference(rawValue: $0) }
    }

    public static func isKnownSpeechCode(_ code: String) -> Bool {
        orderedSpeechCodes.contains(Self.normalized(code))
    }

    /// Resolves a picker value (code, English name, or endonym) to a canonical
    /// speech-language code, or nil when unknown.
    public static func speechCode(forNameOrCode value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if isKnownSpeechCode(lowered) {
            return Self.normalized(lowered)
        }
        if lowered == "english" {
            return englishCode
        }
        if let code = englishNamesByCode.first(where: { $0.value.lowercased() == lowered })?.key {
            return code
        }
        return speechLanguages.first { $0.displayName.lowercased() == lowered }?.code
    }

    /// Endonym display name for a known speech code (plan §5.2); falls back to
    /// the code itself when unknown.
    public static func displayName(for code: String) -> String {
        let normalized = Self.normalized(code)
        return UILanguagePreference(rawValue: normalized)?.displayName ?? normalized
    }

    private static func normalized(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
