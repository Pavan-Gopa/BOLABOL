import Foundation

public struct TranscriptionLanguageRoute: Equatable, Sendable {
    public var forcedLanguageCode: String?
    public var translateToEnglish: Bool
    public var autoTranslateTargetLanguageCode: String?

    public init(
        forcedLanguageCode: String?,
        translateToEnglish: Bool,
        autoTranslateTargetLanguageCode: String?
    ) {
        self.forcedLanguageCode = forcedLanguageCode
        self.translateToEnglish = translateToEnglish
        self.autoTranslateTargetLanguageCode = autoTranslateTargetLanguageCode
    }
}

public enum TranscriptionLanguageRouter {
    public static func route(
        resolvedLanguageCode: String,
        isMultilingualModel: Bool,
        forceTargetLanguage: Bool = false
    ) -> TranscriptionLanguageRoute {
        let languageCode = resolvedLanguageCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !languageCode.isEmpty, languageCode != "auto" else {
            return TranscriptionLanguageRoute(
                forcedLanguageCode: nil,
                translateToEnglish: false,
                autoTranslateTargetLanguageCode: nil
            )
        }

        if forceTargetLanguage {
            // Targeted Language Mode: Whisper transcribes using auto-detect,
            // and then we translate to the target language using LLM.
            return TranscriptionLanguageRoute(
                forcedLanguageCode: nil,
                translateToEnglish: false,
                autoTranslateTargetLanguageCode: languageCode
            )
        }

        guard isMultilingualModel else {
            return TranscriptionLanguageRoute(
                forcedLanguageCode: languageCode,
                translateToEnglish: false,
                autoTranslateTargetLanguageCode: nil
            )
        }

        return TranscriptionLanguageRoute(
            forcedLanguageCode: languageCode,
            translateToEnglish: false,
            autoTranslateTargetLanguageCode: nil
        )
    }
}
