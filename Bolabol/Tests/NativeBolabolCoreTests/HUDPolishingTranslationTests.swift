import Foundation
import NativeBolabolCore
import Testing

@Test
func hudPolishingTranslationIgnoresAutoAndBlankCodes() {
    #expect(
        HUDPolishingTranslation.targetLanguageCode(
            hudShowsForcedTarget: true,
            hudTargetLanguageCode: "auto"
        ) == nil
    )
    #expect(
        HUDPolishingTranslation.targetLanguageCode(
            hudShowsForcedTarget: true,
            hudTargetLanguageCode: "   "
        ) == nil
    )
    #expect(
        HUDPolishingTranslation.targetLanguageCode(
            hudShowsForcedTarget: false,
            hudTargetLanguageCode: "en"
        ) == nil
    )
}

@Test
func hudPolishingTranslationUsesHUDTargetForParakeetStyleSessions() {
    // Parakeet ASR plans never carry postASRTextTranslationTargetLanguageCode.
    // HUD E must still produce a concrete polishing target.
    #expect(
        HUDPolishingTranslation.targetLanguageCode(
            hudShowsForcedTarget: true,
            hudTargetLanguageCode: "en",
            sessionPostASRTargetLanguageCode: nil
        ) == "en"
    )
    #expect(
        HUDPolishingTranslation.targetLanguageCode(
            hudShowsForcedTarget: true,
            hudTargetLanguageCode: "es",
            sessionPostASRTargetLanguageCode: "auto"
        ) == "es"
    )
}

@Test
func hudPolishingTranslationPrefersConcreteSessionPostASRTarget() {
    #expect(
        HUDPolishingTranslation.targetLanguageCode(
            hudShowsForcedTarget: true,
            hudTargetLanguageCode: "en",
            sessionPostASRTargetLanguageCode: "fr"
        ) == "fr"
    )
}

@Test
func hudPolishingTranslationNormalizesEnglishAliases() {
    #expect(
        HUDPolishingTranslation.targetLanguageCode(
            hudShowsForcedTarget: true,
            hudTargetLanguageCode: "English"
        ) == "en"
    )
}

@Test
func hudPolishingTranslationResolvedTargetPrefersDistinctAdditionalLanguage() {
    let speech = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en")
    #expect(
        HUDPolishingTranslation.resolvedHUDTargetLanguageCode(speechLanguages: speech) == "en"
    )
}

@Test
func hudPolishingTranslationResolvedTargetFallsBackWhenPairIsTheSame() {
    let speech = UserSpeechLanguages(primaryLanguageCode: "en", additionalLanguageCode: "en")
    #expect(
        HUDPolishingTranslation.resolvedHUDTargetLanguageCode(speechLanguages: speech) == "ru"
    )
}
