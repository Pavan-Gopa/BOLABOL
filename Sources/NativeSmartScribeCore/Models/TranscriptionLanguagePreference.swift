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
        return builtIn.first { $0.code == normalized }?.displayName ?? code
    }
}
