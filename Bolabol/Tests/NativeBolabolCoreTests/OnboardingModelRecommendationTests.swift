import NativeBolabolCore
import Testing

private enum RecommendationTestModelID {
    static let gigaAM = "gigaam-v3-rnnt-coreml"
    static let canaryFlash = "canary-180m-flash-coreml"
    static let canary1B = "canary-1b-v2-coreml"
    static let largeV3 = "whisperkit-large-v3-full"
    static let turbo = "whisperkit-large-v3-turbo"
    static let medium = "whisperkit-medium-multilingual"
    static let parakeet = "parakeet-tdt-06b-v3"
}

@Test
func russianPrimaryUsesRussianAndBilingualRecommendations() {
    let result = OnboardingModelRecommendation.topThree(
        primary: "ru",
        additional: "en",
        available: allRecommendationModels()
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.gigaAM,
        RecommendationTestModelID.parakeet,
        RecommendationTestModelID.canary1B
    ])
    #expect(!result.contains { $0.id == RecommendationTestModelID.canaryFlash })
}

@Test
func russianPrimaryDoesNotLetUnsupportedAdditionalLanguageHideBilingualModels() {
    let result = OnboardingModelRecommendation.topThree(
        primary: "ru",
        additional: "ko",
        available: allRecommendationModels()
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.gigaAM,
        RecommendationTestModelID.largeV3,
        RecommendationTestModelID.turbo
    ])
    #expect(!result.contains { $0.id == RecommendationTestModelID.canary1B })
    #expect(!result.contains { $0.id == RecommendationTestModelID.parakeet })
}

@Test
func primaryLanguageIsMandatoryEvenWhenAdditionalLanguageMatchesSpecialtyModel() {
    let result = OnboardingModelRecommendation.topThree(
        primary: "en",
        additional: "ru",
        available: allRecommendationModels()
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.parakeet,
        RecommendationTestModelID.canary1B,
        RecommendationTestModelID.largeV3
    ])
    #expect(!result.contains { $0.id == RecommendationTestModelID.gigaAM })
}

@Test
func compactLanguagePairPrefersCompactFlashThenBilingualFastModels() {
    let result = OnboardingModelRecommendation.topThree(
        primary: "en",
        additional: "de",
        available: allRecommendationModels()
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.canaryFlash,
        RecommendationTestModelID.parakeet,
        RecommendationTestModelID.canary1B
    ])
}

@Test
func koreanPrimaryOffersOnlyModelsWithKoreanCapability() {
    let result = OnboardingModelRecommendation.topThree(
        primary: "ko",
        additional: "en",
        available: allRecommendationModels()
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.largeV3,
        RecommendationTestModelID.turbo,
        RecommendationTestModelID.medium
    ])
    #expect(!result.contains { $0.id == RecommendationTestModelID.gigaAM })
    #expect(!result.contains { $0.id == RecommendationTestModelID.canaryFlash })
    #expect(!result.contains { $0.id == RecommendationTestModelID.canary1B })
}

@Test
func shippedCatalogRecommendationsFollowRealModelCapabilities() {
    let available = TranscriptionModelCatalog.nativeWhisperKit.models

    let russian = OnboardingModelRecommendation.topThree(
        primary: "ru",
        additional: "en",
        available: available
    )
    let korean = OnboardingModelRecommendation.topThree(
        primary: "ko",
        additional: "en",
        available: available
    )

    #expect(russian.map(\.id) == [
        RecommendationTestModelID.gigaAM,
        RecommendationTestModelID.parakeet,
        RecommendationTestModelID.canary1B
    ])
    #expect(korean.map(\.id) == [
        RecommendationTestModelID.largeV3,
        RecommendationTestModelID.turbo,
        RecommendationTestModelID.medium
    ])
}

@Test
func recommendationNormalizesNamesAndRegionalCodes() {
    let result = OnboardingModelRecommendation.topThree(
        primary: " Russian ",
        additional: "en-US",
        available: allRecommendationModels()
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.gigaAM,
        RecommendationTestModelID.parakeet,
        RecommendationTestModelID.canary1B
    ])
}

@Test
func unavailableModelsAreSkippedWithoutFillingPlaceholderSlots() {
    let available = allRecommendationModels().filter {
        $0.id != RecommendationTestModelID.gigaAM
            && $0.id != RecommendationTestModelID.canary1B
    }

    let result = OnboardingModelRecommendation.topThree(
        primary: "ru",
        additional: "en",
        available: available
    )

    #expect(result.map(\.id) == [
        RecommendationTestModelID.parakeet,
        RecommendationTestModelID.largeV3,
        RecommendationTestModelID.turbo
    ])
}

@Test
func duplicateModelsAreReturnedOnceAndResultIsCappedAtThree() {
    let models = allRecommendationModels()
    let result = OnboardingModelRecommendation.topThree(
        primary: "ru",
        additional: "en",
        available: models + [models[0]]
    )

    #expect(result.count == 3)
    #expect(result.map(\.id).count == Set(result.map(\.id)).count)
}

@Test
func emptyCatalogReturnsNoRecommendations() {
    #expect(OnboardingModelRecommendation.topThree(
        primary: "ru",
        additional: "en",
        available: []
    ).isEmpty)
}

private func allRecommendationModels() -> [TranscriptionModelDescriptor] {
    [
        makeRecommendationModel(id: RecommendationTestModelID.gigaAM),
        makeRecommendationModel(id: RecommendationTestModelID.canaryFlash),
        makeRecommendationModel(id: RecommendationTestModelID.canary1B),
        makeRecommendationModel(id: RecommendationTestModelID.largeV3),
        makeRecommendationModel(id: RecommendationTestModelID.turbo),
        makeRecommendationModel(id: RecommendationTestModelID.medium),
        makeRecommendationModel(id: RecommendationTestModelID.parakeet)
    ]
}

private func makeRecommendationModel(id: String) -> TranscriptionModelDescriptor {
    let backend: TranscriptionModelDescriptor.Backend
    let supportedLanguageCodes: [String]
    let supportsAutoLanguageDetect: Bool

    switch id {
    case RecommendationTestModelID.gigaAM:
        backend = .gigaAMCoreML
        supportedLanguageCodes = ["ru"]
        supportsAutoLanguageDetect = false
    case RecommendationTestModelID.canaryFlash:
        backend = .canaryCoreML
        supportedLanguageCodes = CanaryLanguageCatalog.flashLanguageCodes
        supportsAutoLanguageDetect = false
    case RecommendationTestModelID.canary1B:
        backend = .canaryCoreML
        supportedLanguageCodes = CanaryLanguageCatalog.oneBV2LanguageCodes
        supportsAutoLanguageDetect = false
    case RecommendationTestModelID.parakeet:
        backend = .fluidAudioCoreML
        supportedLanguageCodes = CanaryLanguageCatalog.oneBV2LanguageCodes
        supportsAutoLanguageDetect = true
    default:
        backend = .whisperKitCoreML
        supportedLanguageCodes = LanguagePickerOrder.orderedSpeechCodes
        supportsAutoLanguageDetect = true
    }

    return TranscriptionModelDescriptor(
        id: id,
        displayName: id,
        modelName: id,
        backend: backend,
        languageSupport: .multilingual,
        downloadSize: "1 MB",
        description: "Test model",
        accuracy: 3,
        speed: 3,
        capabilities: ASRModelCapabilities(
            supportsAutoLanguageDetect: supportsAutoLanguageDetect,
            supportedLanguageCodes: supportedLanguageCodes,
            maxChunkSeconds: 30,
            approxDownloadBytes: 1_000_000
        )
    )
}
