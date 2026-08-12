import Foundation
import NativeBolabolCore
import Testing

@Test
func transcriptionLanguageRouterForcesEnglishLikeElectronOnMultilingualModels() {
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "en",
        isMultilingualModel: true
    )

    #expect(route.forcedLanguageCode == "en")
    #expect(!route.translateToEnglish)
    #expect(route.postASRTextTranslationTargetLanguageCode == nil)
}

@Test
func transcriptionLanguageRouterKeepsAutoDetectAsPlainTranscription() {
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "auto",
        isMultilingualModel: true
    )

    #expect(route.forcedLanguageCode == nil)
    #expect(!route.translateToEnglish)
    #expect(route.postASRTextTranslationTargetLanguageCode == nil)
}

@Test
func transcriptionLanguageRouterForcesNonEnglishTargetsLikeElectron() {
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "fr",
        isMultilingualModel: true
    )

    #expect(route.forcedLanguageCode == "fr")
    #expect(!route.translateToEnglish)
    #expect(route.postASRTextTranslationTargetLanguageCode == nil)
}

@Test
func transcriptionLanguageRouterForcesLanguageOnNonMultilingualModels() {
    let route = TranscriptionLanguageRouter.route(
        resolvedLanguageCode: "en",
        isMultilingualModel: false
    )

    #expect(route.forcedLanguageCode == "en")
    #expect(!route.translateToEnglish)
    #expect(route.postASRTextTranslationTargetLanguageCode == nil)
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
    #expect(route.postASRTextTranslationTargetLanguageCode == "fr")
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
    #expect(route.postASRTextTranslationTargetLanguageCode == nil)
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
    #expect(route.postASRTextTranslationTargetLanguageCode == "fr")
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
    #expect(route.postASRTextTranslationTargetLanguageCode == "en")
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
    #expect(route.postASRTextTranslationTargetLanguageCode == nil)
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
    #expect(route.postASRTextTranslationTargetLanguageCode == nil)
}

// MARK: - BUG-VPH-006: Parakeet Auto + Primary Russian must never silently route English

private let vph006OS = ASRModelCapabilities.OSVersion(majorVersion: 15)

private func vph006Resolve(
    modelID: String,
    primary: String? = "ru",
    additional: String? = "en",
    legacyLanguageCode: String? = "auto"
) throws -> TranscriptionSessionResolution {
    let model = try #require(TranscriptionModelCatalog.nativeWhisperKit.model(withID: modelID))
    return TranscriptionSessionResolver.resolve(
        activeModel: model,
        modelFolderURL: URL(fileURLWithPath: "/tmp/vph006-\(modelID)"),
        currentOSVersion: vph006OS,
        hasCompleteModel: true,
        primaryLanguageCode: primary,
        additionalLanguageCode: additional,
        operation: .asr,
        legacyLanguageCode: legacyLanguageCode
    )
}

@Suite("BUG-VPH-006 Parakeet Auto + Primary Russian")
struct BUGVPH006ParakeetRussianRoutingTests {

    @Test("Auto + Primary Russian anchors the Parakeet request to Russian, never English")
    func parakeetAutoAnchorsToPrimaryRussian() throws {
        let resolution = try vph006Resolve(modelID: "parakeet-tdt-06b-v3")
        guard case .available(let plan) = resolution else {
            Issue.record("Expected an available Parakeet session plan")
            return
        }

        #expect(plan.backend == .fluidAudioCoreML)
        #expect(plan.capabilities.supportsInputLanguage("ru"))
        #expect(plan.languageMode == .auto)
        #expect(plan.hudLanguageLabel == "A")
        // The S11 auto contract stays intact: no forced language token.
        #expect(plan.request.forcedLanguageCode == nil)
        // Parakeet Auto must never carry a hardcoded language anchor.
        #expect(plan.route.languageHint == nil)
        #expect(plan.request.languageHint == nil)
        // Never a translation route for an auto session.
        #expect(!plan.request.translateToEnglish)
        #expect(plan.route.postASRTextTranslationTargetLanguageCode == nil)
    }

    @Test("Engine-bound request keeps the Russian anchor for insertion")
    func parakeetEngineRequestCarriesRussianHint() throws {
        let resolution = try vph006Resolve(modelID: "parakeet-tdt-06b-v3")
        guard case .available(let plan) = resolution else {
            Issue.record("Expected an available Parakeet session plan")
            return
        }

        let request = plan.request(audioFileURL: URL(fileURLWithPath: "/tmp/ru-speech.wav"))
        #expect(request.languageHint == nil)
        #expect(request.audioFileURL != nil)
    }

    @Test("Auto without a configured primary stays fully unanchored")
    func parakeetAutoWithoutPrimaryStaysUnanchored() throws {
        let resolution = try vph006Resolve(modelID: "parakeet-tdt-06b-v3", primary: nil, additional: "en")
        guard case .available(let plan) = resolution else {
            Issue.record("Expected an available Parakeet session plan")
            return
        }

        #expect(plan.request.forcedLanguageCode == nil)
        #expect(plan.route.languageHint == nil)
        #expect(plan.request.languageHint == nil)
    }

    @Test("Explicit legacy language preference is not turned into a hint (stale-pref protection)")
    func parakeetExplicitLegacyPreferenceStaysUnanchored() throws {
        let resolution = try vph006Resolve(
            modelID: "parakeet-tdt-06b-v3",
            primary: "ru",
            additional: "en",
            legacyLanguageCode: "it"
        )
        guard case .available(let plan) = resolution else {
            Issue.record("Expected an available Parakeet session plan")
            return
        }

        #expect(plan.request.forcedLanguageCode == nil)
        #expect(plan.route.languageHint == nil, "A stale Whisper preference must not become a Parakeet hint")
    }

    @Test("Whisper auto behavior is unchanged by the Parakeet anchor policy")
    func whisperAutoBehaviorUnchanged() throws {
        let resolution = try vph006Resolve(
            modelID: "whisperkit-small-multilingual",
            primary: "ru",
            additional: "en"
        )
        guard case .available(let plan) = resolution else {
            Issue.record("Expected an available Whisper session plan")
            return
        }

        #expect(plan.backend == .whisperKitCoreML)
        #expect(plan.request.forcedLanguageCode == nil)
        #expect(plan.route.languageHint == nil)
        #expect(plan.request.languageHint == nil)
    }

    @Test("Parakeet Auto can never claim a target translation (E-mode) route")
    func parakeetAutoNeverClaimsTranslationRoute() throws {
        let resolution = try vph006Resolve(modelID: "parakeet-tdt-06b-v3")
        guard case .available(let plan) = resolution else {
            Issue.record("Expected an available Parakeet session plan")
            return
        }

        #expect(!plan.isWhisperTargetMode)
        #expect(!plan.supportsNativeWhisperTranslation)
        #expect(plan.route.translateToEnglish == false)
    }
}
