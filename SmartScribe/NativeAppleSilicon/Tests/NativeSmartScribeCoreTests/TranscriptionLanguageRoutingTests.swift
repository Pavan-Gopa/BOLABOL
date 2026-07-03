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
func transcriptionLanguageRouterTargetModeUsesAutoDetectForWhisperAndLLMForTargetLanguage() {
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
func transcriptionLanguageRouterTargetModeKeepsAutoDetectWhenAutoSelected() {
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "auto",
        isMultilingualModel: true,
        forceTargetLanguage: true
    )

    #expect(route.forcedLanguageCode == nil)
    #expect(!route.translateToEnglish)
    #expect(route.autoTranslateTargetLanguageCode == nil)
}
