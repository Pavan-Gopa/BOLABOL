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

        if forceTargetLanguage {
            let targetCode = normalizedTargetCode(languageCode)
            // Whisper can natively translate only to English (`task: .translate`).
            // For any other target language we always need a post-transcription
            // LLM pass — the language token is a *source* language constraint,
            // not an output-language selector.
            if isEnglishTarget(targetCode) {
                if isMultilingualModel {
                    return TranscriptionLanguageRoute(
                        forcedLanguageCode: nil,
                        translateToEnglish: true,
                        autoTranslateTargetLanguageCode: nil
                    )
                }
                // English-only Whisper models cannot translate; fall back to LLM.
                return TranscriptionLanguageRoute(
                    forcedLanguageCode: nil,
                    translateToEnglish: false,
                    autoTranslateTargetLanguageCode: targetCode
                )
            }

            return TranscriptionLanguageRoute(
                forcedLanguageCode: nil,
                translateToEnglish: false,
                autoTranslateTargetLanguageCode: targetCode
            )
        }

        guard !languageCode.isEmpty, languageCode != "auto" else {
            return TranscriptionLanguageRoute(
                forcedLanguageCode: nil,
                translateToEnglish: false,
                autoTranslateTargetLanguageCode: nil
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

    private static func normalizedTargetCode(_ languageCode: String) -> String {
        if languageCode.isEmpty || languageCode == "auto" {
            return "en"
        }
        if languageCode == "english" {
            return "en"
        }
        return languageCode
    }

    private static func isEnglishTarget(_ targetCode: String) -> Bool {
        targetCode == "en" || targetCode.hasPrefix("en-") || targetCode == "english"
    }
}
