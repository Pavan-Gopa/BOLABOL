import Foundation

/// Resolves the concrete language the polishing/LLM pass must emit after ASR.
///
/// HUD "E" (or S/F/…) is a post-ASR text target. Parakeet, Canary, and GigaAM
/// sessions are always `.asr` and do not store that target on the speech route,
/// so the HUD flag plus the configured target code are the source of truth.
public enum HUDPolishingTranslation {
    public static let forceTargetLanguageDefaultsKey = "hud.forceTargetLanguage"

    public static func hudShowsForcedTarget(userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: forceTargetLanguageDefaultsKey)
    }

    /// Concrete BCP-47-like code for the polishing translation pass, or `nil`
    /// when the HUD is in Auto and the session has no post-ASR target.
    /// `"auto"` is never a translation target.
    public static func targetLanguageCode(
        hudShowsForcedTarget: Bool,
        hudTargetLanguageCode: String,
        sessionPostASRTargetLanguageCode: String? = nil
    ) -> String? {
        if let sessionCode = concreteLanguageCode(sessionPostASRTargetLanguageCode) {
            return sessionCode
        }
        guard hudShowsForcedTarget else { return nil }
        return concreteLanguageCode(hudTargetLanguageCode)
    }

    /// Language the HUD letter represents (E → English, etc.).
    public static func resolvedHUDTargetLanguageCode(
        override: String? = nil,
        speechLanguages: UserSpeechLanguages,
        glossaryAutoLanguage: String? = nil
    ) -> String {
        let primary = normalizeLanguageCode(speechLanguages.primaryLanguageCode)
        let additional = normalizeLanguageCode(speechLanguages.additionalLanguageCode)

        if let override {
            let code = override.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !code.isEmpty,
               code != "auto",
               speechLanguages.orderedDistinctCodes.contains(code)
                || LanguagePickerOrder.isKnownSpeechCode(code) {
                return code
            }
        }

        if !speechLanguages.usesSameAdditionalAsPrimary,
           !speechLanguages.additionalLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           additional != "auto" {
            return additional
        }

        if let glossaryAutoLanguage {
            let rawGlossary = glossaryAutoLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
            let glossaryAuto = normalizeLanguageCode(glossaryAutoLanguage)
            if !rawGlossary.isEmpty, glossaryAuto != primary, glossaryAuto != "auto" {
                return glossaryAuto
            }
        }

        return primary == "en" ? "ru" : "en"
    }

    public static func concreteLanguageCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        if lowered == "auto" { return nil }
        if lowered == "english" || lowered.hasPrefix("en-") {
            return "en"
        }
        if let option = TranscriptionLanguageOption.builtIn.first(where: {
            $0.code == lowered || $0.displayName.lowercased() == lowered
        }) {
            return option.code
        }
        return lowered
    }

    private static func normalizeLanguageCode(_ value: String) -> String {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if code.isEmpty || code == "auto" {
            return "en"
        }
        if code.hasPrefix("en") || code == "english" {
            return "en"
        }
        if let option = TranscriptionLanguageOption.builtIn.first(where: {
            $0.displayName.lowercased() == code || $0.code == code
        }) {
            return option.code
        }
        return code
    }
}
