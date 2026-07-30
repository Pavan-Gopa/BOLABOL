import Foundation

public enum TranscriptionLanguagePreference: Codable, Equatable, Sendable {
    case auto
    case language(String)
    case custom(String)

    public func resolvedCode(defaultCode: String) -> String {
        switch self {
        case .auto:
            normalize(defaultCode, fallback: "auto")
        case .language(let code):
            normalize(code, fallback: defaultCode)
        case .custom(let code):
            normalize(code, fallback: defaultCode)
        }
    }

    private func normalize(_ code: String, fallback: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        return normalized
    }
}

public struct TranscriptionLanguageOption: Identifiable, Equatable, Sendable {
    public var id: String { code }
    public var code: String
    public var displayName: String

    public init(code: String, displayName: String) {
        self.code = code
        self.displayName = displayName
    }
}

public extension TranscriptionLanguageOption {
    static let builtIn: [TranscriptionLanguageOption] = [
        .init(code: "en", displayName: "English"),
        .init(code: "es", displayName: "Spanish"),
        .init(code: "fr", displayName: "French"),
        .init(code: "de", displayName: "German"),
        .init(code: "it", displayName: "Italian"),
        .init(code: "pt", displayName: "Portuguese"),
        .init(code: "ru", displayName: "Russian"),
        .init(code: "zh", displayName: "Chinese"),
        .init(code: "ja", displayName: "Japanese"),
        .init(code: "ko", displayName: "Korean"),
        .init(code: "ar", displayName: "Arabic"),
        .init(code: "hi", displayName: "Hindi")
    ]

    /// Returns the human-readable language name for a given code (e.g. "en" → "English").
    /// Falls back to the code itself when no match is found.
    static func displayName(for code: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "english" { return "English" }
        return builtIn.first {
            $0.code == normalized || $0.displayName.lowercased() == normalized
        }?.displayName ?? code
    }

    /// Compact single-character HUD label for the target language control
    /// (English → "E", Spanish → "S", French → "F", Chinese → "C", …).
    /// Prefer the first letter of the English display name so the badge stays
    /// Latin and readable on the overlay for every built-in language.
    static func hudLabel(for codeOrName: String) -> String {
        let trimmed = codeOrName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "E" }

        let name = displayName(for: trimmed)
        if let letter = name.first(where: \.isLetter) {
            return String(letter).uppercased()
        }
        if let letter = trimmed.first(where: \.isLetter) {
            return String(letter).uppercased()
        }
        return "E"
    }
}
