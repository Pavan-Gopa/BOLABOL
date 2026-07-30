import NativeSmartScribeCore
import Testing

@Test
func transcriptionLanguageRouterForcesEnglishLikeElectronOnMultilingualModels() {
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "en",
        isMultilingualModel: true
    )

    #expect(route.forcedLanguageCode == "en")
    #expect(!route.translateToEnglish)
    #expect(route.autoTranslateTargetLanguageCode == nil)
}

@Test
func transcriptionLanguageRouterKeepsAutoDetectAsPlainTranscription() {
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "auto",
        isMultilingualModel: true
    )

    #expect(route.forcedLanguageCode == nil)
    #expect(!route.translateToEnglish)
    #expect(route.autoTranslateTargetLanguageCode == nil)
}

@Test
func transcriptionLanguageRouterForcesNonEnglishTargetsLikeElectron() {
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "fr",
        isMultilingualModel: true
    )

    #expect(route.forcedLanguageCode == "fr")
    #expect(!route.translateToEnglish)
    #expect(route.autoTranslateTargetLanguageCode == nil)
}

@Test
func transcriptionLanguageRouterForcesLanguageOnNonMultilingualModels() {
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "en",
        isMultilingualModel: false
    )

    #expect(route.forcedLanguageCode == "en")
    #expect(!route.translateToEnglish)
    #expect(route.autoTranslateTargetLanguageCode == nil)
}

@Test
func transcriptionLanguageRouterTargetModeUsesLLMForNonEnglishTargets() {
    // Whisper can only translate natively to English. Non-English targets
    // always go through a post-transcription LLM translation pass.
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "fr",
        isMultilingualModel: true,
        forceTargetLanguage: true
    )

    #expect(route.forcedLanguageCode == nil)
    #expect(!route.translateToEnglish)
    #expect(route.autoTranslateTargetLanguageCode == "fr")
}

@Test
func transcriptionLanguageRouterTargetModeEnablesTranslateToEnglishForEnglishTarget() {
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "en",
        isMultilingualModel: true,
        forceTargetLanguage: true
    )

    #expect(route.forcedLanguageCode == nil)
    #expect(route.translateToEnglish)
    #expect(route.autoTranslateTargetLanguageCode == nil)
}

@Test
func transcriptionLanguageRouterTargetModeFallsBackToLLMOnNonMultilingualModels() {
    // Non-multilingual models can't translate; fall back to LLM translation.
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "fr",
        isMultilingualModel: false,
        forceTargetLanguage: true
    )

    #expect(route.forcedLanguageCode == nil)
    #expect(!route.translateToEnglish)
    #expect(route.autoTranslateTargetLanguageCode == "fr")
}

@Test
func transcriptionLanguageRouterTargetModeFallsBackToLLMForEnglishOnNonMultilingualModels() {
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "en",
        isMultilingualModel: false,
        forceTargetLanguage: true
    )

    #expect(route.forcedLanguageCode == nil)
    #expect(!route.translateToEnglish)
    #expect(route.autoTranslateTargetLanguageCode == "en")
}

@Test
func transcriptionLanguageRouterTargetModeKeepsAutoDetectWhenAutoSelected() {
    // Auto + force target defaults to English (Whisper native translate).
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "auto",
        isMultilingualModel: true,
        forceTargetLanguage: true
    )

    #expect(route.forcedLanguageCode == nil)
    #expect(route.translateToEnglish)
    #expect(route.autoTranslateTargetLanguageCode == nil)
}

@Test
func transcriptionLanguageRouterTargetModeNormalizesEnglishAliases() {
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "english",
        isMultilingualModel: true,
        forceTargetLanguage: true
    )

    #expect(route.forcedLanguageCode == nil)
    #expect(route.translateToEnglish)
    #expect(route.autoTranslateTargetLanguageCode == nil)
}
