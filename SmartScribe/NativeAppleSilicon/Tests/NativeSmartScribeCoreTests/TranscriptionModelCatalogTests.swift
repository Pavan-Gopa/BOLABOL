import NativeSmartScribeCore
import Testing

@Test
func nativeTranscriptionCatalogUsesWhisperKitRecommendedModelByDefault() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let defaultModel = try #require(catalog.defaultModel)

    #expect(defaultModel.id == "whisperkit-large-v3-v20240930-626mb")
    #expect(defaultModel.backend == .whisperKitCoreML)
    #expect(defaultModel.modelName == "large-v3-v20240930_626MB")
    #expect(defaultModel.isRecommended)
}

@Test
func nativeTranscriptionCatalogUsesExpectedWhisperOrder() {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit

    #expect(catalog.models.map(\.id) == [
        "whisperkit-small-en",
        "whisperkit-small-multilingual",
        "whisperkit-medium-en",
        "whisperkit-medium-multilingual",
        "whisperkit-large-v3-turbo-v20240930-632mb",
        "whisperkit-large-v3-v20240930-626mb"
    ])
}

@Test
func nativeTranscriptionCatalogRejectsDuplicateModelIDs() {
    let model = TranscriptionModelDescriptor(
        id: "duplicate",
        displayName: "Duplicate",
        modelName: "tiny",
        backend: .whisperKitCoreML,
        languageSupport: .multilingual,
        downloadSize: "75 MB",
        badge: "Fast",
        description: "Duplicate test model.",
        accuracy: 2,
        speed: 5
    )

    #expect(throws: TranscriptionModelCatalogError.duplicateModelID("duplicate")) {
        try TranscriptionModelCatalog(models: [model, model])
    }
}

@Test
func transcriptionModelDownloadStateClampsProgressFraction() {
    let low = TranscriptionModelInstallationState.downloading(progressFraction: -1)
    let high = TranscriptionModelInstallationState.downloading(progressFraction: 2)

    #expect(low.progressFraction == 0)
    #expect(high.progressFraction == 1)
}

@Test
func transcriptionLanguagePreferenceResolvesAutoAndCustomCodes() {
    #expect(TranscriptionLanguagePreference.auto.resolvedCode(defaultCode: "en") == "en")
    #expect(TranscriptionLanguagePreference.language("ru").resolvedCode(defaultCode: "en") == "ru")
    #expect(TranscriptionLanguagePreference.custom(" PT-br ").resolvedCode(defaultCode: "en") == "pt-br")
    #expect(TranscriptionLanguagePreference.custom(" ").resolvedCode(defaultCode: "en") == "en")
}
