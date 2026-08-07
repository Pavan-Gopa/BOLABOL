import NativeBolabolCore
import Testing

private struct TranscriptionDescriptorSurface: Equatable {
    let id: String
    let displayName: String
    let modelName: String
    let modelRepositoryID: String
    let snapshotGlob: String
    let backend: TranscriptionModelDescriptor.Backend
    let languageSupport: TranscriptionModelDescriptor.LanguageSupport
    let downloadSize: String
    let badge: String?
    let description: String
    let accuracy: Int
    let speed: Int
    let isRecommended: Bool

    init(_ model: TranscriptionModelDescriptor) {
        id = model.id
        displayName = model.displayName
        modelName = model.modelName
        modelRepositoryID = model.modelRepositoryID
        snapshotGlob = model.snapshotGlob
        backend = model.backend
        languageSupport = model.languageSupport
        downloadSize = model.downloadSize
        badge = model.badge
        description = model.description
        accuracy = model.accuracy
        speed = model.speed
        isRecommended = model.isRecommended
    }

    init(
        id: String,
        displayName: String,
        modelName: String,
        modelRepositoryID: String,
        snapshotGlob: String,
        backend: TranscriptionModelDescriptor.Backend,
        languageSupport: TranscriptionModelDescriptor.LanguageSupport,
        downloadSize: String,
        badge: String?,
        description: String,
        accuracy: Int,
        speed: Int,
        isRecommended: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.modelName = modelName
        self.modelRepositoryID = modelRepositoryID
        self.snapshotGlob = snapshotGlob
        self.backend = backend
        self.languageSupport = languageSupport
        self.downloadSize = downloadSize
        self.badge = badge
        self.description = description
        self.accuracy = accuracy
        self.speed = speed
        self.isRecommended = isRecommended
    }
}

@Test
func nativeTranscriptionCatalogUsesWhisperKitRecommendedModelByDefault() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let defaultModel = try #require(catalog.defaultModel)

    #expect(defaultModel.id == "whisperkit-large-v3-full")
    #expect(defaultModel.backend == .whisperKitCoreML)
    #expect(defaultModel.modelName == "large-v3")
    #expect(defaultModel.isRecommended)
}

@Test
func nativeTranscriptionCatalogUsesExpectedModelOrder() {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit

    #expect(catalog.models.map(\.id) == [
        "parakeet-tdt-06b-v3",
        "whisperkit-small-en",
        "whisperkit-small-multilingual",
        "whisperkit-medium-en",
        "whisperkit-medium-multilingual",
        "whisperkit-large-v3-turbo",
        "whisperkit-large-v3-full",
        "canary-180m-flash-coreml",
        "canary-1b-v2-coreml",
        "gigaam-v3-rnnt-coreml"
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

@Test
func transcriptionLanguageHudLabelUsesFirstLetterOfDisplayName() {
    #expect(TranscriptionLanguageOption.hudLabel(for: "en") == "E")
    #expect(TranscriptionLanguageOption.hudLabel(for: "english") == "E")
    #expect(TranscriptionLanguageOption.hudLabel(for: "es") == "S")
    #expect(TranscriptionLanguageOption.hudLabel(for: "Spanish") == "S")
    #expect(TranscriptionLanguageOption.hudLabel(for: "fr") == "F")
    #expect(TranscriptionLanguageOption.hudLabel(for: "de") == "G")
    #expect(TranscriptionLanguageOption.hudLabel(for: "zh") == "C")
    #expect(TranscriptionLanguageOption.hudLabel(for: "ja") == "J")
    #expect(TranscriptionLanguageOption.hudLabel(for: "ru") == "R")
    #expect(TranscriptionLanguageOption.hudLabel(for: "ar") == "A")
    #expect(TranscriptionLanguageOption.hudLabel(for: "") == "E")
}

@Test
func nativeTranscriptionCatalogContainsAdr018GoModelsWithHonestCapabilities() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit

    let flash = try #require(catalog.model(withID: "canary-180m-flash-coreml"))
    #expect(flash.backend == .canaryCoreML)
    #expect(!flash.capabilities.supportsAutoLanguageDetect)
    #expect(!flash.capabilities.supportsSpeechTranslation)
    #expect(flash.capabilities.isRecommendedForEnDeFrEs)
    #expect(flash.capabilities.supportedLanguageCodes == ["en", "de", "fr", "es"])

    let canary1B = try #require(catalog.model(withID: "canary-1b-v2-coreml"))
    #expect(canary1B.backend == .canaryCoreML)
    #expect(canary1B.modelRepositoryID == "bolabol-canary-1b-v2-coreml-r1")
    #expect(!canary1B.capabilities.supportsAutoLanguageDetect)
    #expect(!canary1B.capabilities.supportsSpeechTranslation)
    #expect(canary1B.capabilities.minOSVersion?.majorVersion == 15)

    let gigaAM = try #require(catalog.model(withID: "gigaam-v3-rnnt-coreml"))
    #expect(gigaAM.backend == .gigaAMCoreML)
    #expect(!gigaAM.capabilities.supportsAutoLanguageDetect)
    #expect(!gigaAM.capabilities.supportsSpeechTranslation)
    #expect(gigaAM.capabilities.isRecommendedForPrimaryRU)
    #expect(gigaAM.capabilities.supportedLanguageCodes == ["ru"])

    #expect(!canary1B.modelRepositoryID.contains("FluidInference"))
    #expect(!canary1B.modelRepositoryID.contains("alexwengg"))
}

@Test
func nativeTranscriptionBackendsExposeStableRuntimeBadges() {
    #expect(TranscriptionModelDescriptor.Backend.whisperKitCoreML.runtimeBadge == "WhisperKit \u{00B7} Core ML")
    #expect(TranscriptionModelDescriptor.Backend.fluidAudioCoreML.runtimeBadge == "FluidAudio \u{00B7} Core ML/ANE")
    #expect(TranscriptionModelDescriptor.Backend.canaryCoreML.runtimeBadge == "Canary \u{00B7} Core ML/ANE")
    #expect(TranscriptionModelDescriptor.Backend.gigaAMCoreML.runtimeBadge == "GigaAM \u{00B7} Core ML/ANE")
}

@Test
func nativeTranscriptionCatalogUsesAdr018ChunkAndDownloadCapabilities() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let flash = try #require(catalog.model(withID: "canary-180m-flash-coreml"))
    let canary1B = try #require(catalog.model(withID: "canary-1b-v2-coreml"))
    let gigaAM = try #require(catalog.model(withID: "gigaam-v3-rnnt-coreml"))

    #expect(flash.capabilities.maxChunkSeconds == 10.0)
    #expect(flash.capabilities.approxDownloadBytes == 180_000_000)
    #expect(flash.capabilities.supportedLanguageCodes == ["en", "de", "fr", "es"])
    #expect(flash.capabilities.minOSVersion == nil)

    #expect(canary1B.capabilities.maxChunkSeconds == 15.0)
    #expect(canary1B.capabilities.approxDownloadBytes == 1_884_267_035)
    #expect(canary1B.capabilities.supportedLanguageCodes == CanaryLanguageCatalog.oneBV2LanguageCodes)
    #expect(canary1B.capabilities.minOSVersion == .init(majorVersion: 15))

    #expect(gigaAM.capabilities.maxChunkSeconds == 30.0)
    #expect(gigaAM.capabilities.approxDownloadBytes == 450_000_000)
    #expect(gigaAM.capabilities.supportedLanguageCodes == ["ru"])
    #expect(gigaAM.capabilities.minOSVersion == nil)
}

@Test
func nativeTranscriptionCatalogKeepsNoGoCanarySourcesOutOfGoEntries() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let goIDs = [
        "canary-180m-flash-coreml",
        "canary-1b-v2-coreml",
        "gigaam-v3-rnnt-coreml"
    ]

    for id in goIDs {
        let model = try #require(catalog.model(withID: id))
        let repositoryID = model.modelRepositoryID.lowercased()

        // The existing Parakeet descriptor legitimately uses FluidInference;
        // this guard applies to the newly admitted GO entries only.
        #expect(!repositoryID.contains("fluidinference"), "GO model \(id) must not install from FluidInference")
        #expect(!repositoryID.contains("alexwengg"), "GO model \(id) must not install from alexwengg")
    }
}

@Test
func nativeTranscriptionCatalogMapsExplicitInstallSourcesAndStoragePaths() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit

    let flash = try #require(catalog.model(withID: "canary-180m-flash-coreml"))
    #expect(flash.installSource == .huggingFace(repositoryID: "aufklarer/Canary-180M-Flash-CoreML"))
    #expect(flash.relativeStorageSubpath == "canary/180m-flash")

    let gigaAM = try #require(catalog.model(withID: "gigaam-v3-rnnt-coreml"))
    #expect(gigaAM.installSource == .huggingFace(repositoryID: "huggingfinger0/gigaam-v3-coreml"))
    #expect(gigaAM.relativeStorageSubpath == "gigaam/v3-rnnt")

    let canary1B = try #require(catalog.model(withID: "canary-1b-v2-coreml"))
    #expect(canary1B.installSource == .bolabolCDN(
        packageID: "bolabol-canary-1b-v2-coreml-r1",
        baseURL: TranscriptionModelDescriptor.defaultBolabolCDNBaseURL
    ))
    #expect(canary1B.relativeStorageSubpath == "canary/1b-v2")
}

@Test
func nativeTranscriptionCatalogPreservesExistingWhisperKitAndFluidAudioDescriptors() {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let goIDs = Set([
        "canary-180m-flash-coreml",
        "canary-1b-v2-coreml",
        "gigaam-v3-rnnt-coreml"
    ])
    let existing = catalog.models.filter { !goIDs.contains($0.id) }

    let expected = [
        TranscriptionDescriptorSurface(
            id: "parakeet-tdt-06b-v3",
            displayName: "Parakeet TDT 0.6B v3",
            modelName: "parakeet-tdt-0.6b-v3",
            modelRepositoryID: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
            snapshotGlob: "**",
            backend: .fluidAudioCoreML,
            languageSupport: .multilingual,
            downloadSize: "~482 MB",
            badge: "Fastest",
            description: "High-throughput Parakeet v3 for 25 European languages, including English, Dutch, Russian, and Ukrainian. Runs locally through Core ML on Apple Neural Engine.",
            accuracy: 4,
            speed: 5,
            isRecommended: false
        ),
        TranscriptionDescriptorSurface(
            id: "whisperkit-small-en",
            displayName: "Whisper Small English",
            modelName: "small.en",
            modelRepositoryID: "argmaxinc/whisperkit-coreml",
            snapshotGlob: "openai_whisper-small.en/**",
            backend: .whisperKitCoreML,
            languageSupport: .english,
            downloadSize: "~487 MB",
            badge: "Fast",
            description: "Compact English-only Whisper model for quick local transcription on Apple Silicon.",
            accuracy: 3,
            speed: 5,
            isRecommended: false
        ),
        TranscriptionDescriptorSurface(
            id: "whisperkit-small-multilingual",
            displayName: "Whisper Small Multi",
            modelName: "small",
            modelRepositoryID: "argmaxinc/whisperkit-coreml",
            snapshotGlob: "openai_whisper-small/**",
            backend: .whisperKitCoreML,
            languageSupport: .multilingual,
            downloadSize: "~486 MB",
            badge: "Fast",
            description: "Compact multilingual Whisper model for lightweight local transcription across languages.",
            accuracy: 3,
            speed: 5,
            isRecommended: false
        ),
        TranscriptionDescriptorSurface(
            id: "whisperkit-medium-en",
            displayName: "Whisper Medium English",
            modelName: "medium.en",
            modelRepositoryID: "argmaxinc/whisperkit-coreml",
            snapshotGlob: "openai_whisper-medium.en/**",
            backend: .whisperKitCoreML,
            languageSupport: .english,
            downloadSize: "~1.53 GB",
            badge: "Balanced",
            description: "Higher-accuracy English-only Whisper model with a strong quality-to-speed balance.",
            accuracy: 4,
            speed: 4,
            isRecommended: false
        ),
        TranscriptionDescriptorSurface(
            id: "whisperkit-medium-multilingual",
            displayName: "Whisper Medium Multi",
            modelName: "medium",
            modelRepositoryID: "argmaxinc/whisperkit-coreml",
            snapshotGlob: "openai_whisper-medium/**",
            backend: .whisperKitCoreML,
            languageSupport: .multilingual,
            downloadSize: "~1.53 GB",
            badge: "Balanced",
            description: "Higher-accuracy multilingual Whisper model for broad language coverage on-device.",
            accuracy: 4,
            speed: 4,
            isRecommended: false
        ),
        TranscriptionDescriptorSurface(
            id: "whisperkit-large-v3-turbo",
            displayName: "Whisper Large v3 Turbo",
            modelName: "large-v3-v20240930_turbo",
            modelRepositoryID: "argmaxinc/whisperkit-coreml",
            snapshotGlob: "openai_whisper-large-v3-v20240930_turbo/**",
            backend: .whisperKitCoreML,
            languageSupport: .multilingual,
            downloadSize: "~1.6 GB",
            badge: "Fast large",
            description: "OpenAI Large v3 Turbo (~809M parameters). Faster than full Large v3 with strong multilingual quality on Apple Silicon.",
            accuracy: 4,
            speed: 5,
            isRecommended: false
        ),
        TranscriptionDescriptorSurface(
            id: "whisperkit-large-v3-full",
            displayName: "Whisper Large v3 Full",
            modelName: "large-v3",
            modelRepositoryID: "argmaxinc/whisperkit-coreml",
            snapshotGlob: "openai_whisper-large-v3/**",
            backend: .whisperKitCoreML,
            languageSupport: .multilingual,
            downloadSize: "~3 GB",
            badge: "Best quality",
            description: "Complete Whisper Large v3 Core ML model. Highest accuracy and the most complete multilingual capabilities on-device.",
            accuracy: 5,
            speed: 2,
            isRecommended: true
        )
    ]

    #expect(existing.map { TranscriptionDescriptorSurface($0) } == expected)
}
