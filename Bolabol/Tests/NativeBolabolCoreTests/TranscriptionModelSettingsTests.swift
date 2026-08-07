import Foundation
import NativeBolabolCore
import Testing

@Test
func transcriptionModelSettingsActivatesOnlyDownloadedModels() {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let modelID = "whisperkit-small-en"
    var settings = TranscriptionModelSettings()

    #expect(settings.activate(modelID: modelID, catalog: catalog) == false)
    #expect(settings.activeModelID == nil)

    settings.markDownloaded(
        modelID: modelID,
        localURL: URL(fileURLWithPath: "/tmp/whisperkit-small-en")
    )

    let didActivate = settings.activate(modelID: modelID, catalog: catalog)

    #expect(didActivate)
    #expect(settings.activeModelID == modelID)
}

@Test
func transcriptionModelSettingsClearsActiveModelWhenRemoved() {
    var settings = TranscriptionModelSettings()
    settings.markDownloaded(modelID: "whisperkit-small-en")
    _ = settings.activate(
        modelID: "whisperkit-small-en",
        catalog: .nativeWhisperKit
    )

    settings.remove(modelID: "whisperkit-small-en")

    #expect(settings.activeModelID == nil)
    #expect(settings.installationState(for: "whisperkit-small-en").status == .notDownloaded)
}

@Test
func transcriptionModelSettingsResolvesLanguageFromActiveModelDefault() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    var settings = TranscriptionModelSettings()
    settings.markDownloaded(modelID: "whisperkit-large-v3-full")
    _ = settings.activate(
        modelID: "whisperkit-large-v3-full",
        catalog: catalog
    )

    #expect(settings.resolvedLanguageCode(catalog: catalog) == "auto")

    settings.languagePreference = .language("ru")
    #expect(settings.resolvedLanguageCode(catalog: catalog) == "ru")
}

@Test
func transcriptionModelDescriptorBuildsWhisperKitModelFolderName() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let model = try #require(catalog.model(withID: "whisperkit-small-en"))

    #expect(model.modelFolderName == "openai_whisper-small.en")
}

@Test
func transcriptionModelSettingsResolvesActiveDownloadedModelFolder() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let cacheRoot = uniqueModelCacheRoot()
    defer { try? FileManager.default.removeItem(at: cacheRoot) }
    let modelFolder = cacheRoot.appendingPathComponent("openai_whisper-small.en", isDirectory: true)
    try createCompleteWhisperKitFixture(at: modelFolder)
    var settings = TranscriptionModelSettings()
    settings.markDownloaded(
        modelID: "whisperkit-small-en",
        localURL: cacheRoot
    )
    _ = settings.activate(modelID: "whisperkit-small-en", catalog: catalog)

    let activeModel = try #require(settings.activeDownloadedModel(catalog: catalog))

    #expect(activeModel.model.id == "whisperkit-small-en")
    #expect(
        activeModel.modelFolderURL == cacheRoot.appendingPathComponent(
            "openai_whisper-small.en",
            isDirectory: true
        )
    )
}

@Test
func transcriptionModelSettingsKeepsExplicitModelFolderWhenAlreadyResolved() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit
    let cacheRoot = uniqueModelCacheRoot()
    defer { try? FileManager.default.removeItem(at: cacheRoot) }
    let modelFolder = cacheRoot.appendingPathComponent("openai_whisper-small.en", isDirectory: true)
    try createCompleteWhisperKitFixture(at: modelFolder)
    var settings = TranscriptionModelSettings()
    settings.markDownloaded(
        modelID: "whisperkit-small-en",
        localURL: modelFolder
    )
    _ = settings.activate(modelID: "whisperkit-small-en", catalog: catalog)

    let activeModel = try #require(settings.activeDownloadedModel(catalog: catalog))

    #expect(activeModel.modelFolderURL == modelFolder)
}

private func uniqueModelCacheRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("native-bolabol-model-cache-\(UUID().uuidString)", isDirectory: true)
}

private func createCompleteWhisperKitFixture(at modelFolder: URL) throws {
    let fileManager = FileManager.default
    try? fileManager.removeItem(at: modelFolder)
    try fileManager.createDirectory(
        at: modelFolder.appendingPathComponent("AudioEncoder.mlmodelc", isDirectory: true),
        withIntermediateDirectories: true
    )
    try "{}".write(
        to: modelFolder.appendingPathComponent("config.json"),
        atomically: true,
        encoding: .utf8
    )
}

@Test
func transcriptionModelSettingsCanResetInterruptedDownloads() {
    var settings = TranscriptionModelSettings()
    settings.markDownloading(modelID: "whisperkit-small-en", progressFraction: 0.41)
    #expect(settings.installationState(for: "whisperkit-small-en").status == .downloading)
    #expect(settings.installationState(for: "whisperkit-small-en").progressFraction == 0.41)
    
    settings.resetInterruptedDownloads()
    
    #expect(settings.installationState(for: "whisperkit-small-en").status == .notDownloaded)
    #expect(settings.installationState(for: "whisperkit-small-en").progressFraction == nil)
}

@Test
func S10PresentationPolicyDoesNotMutateSavedSettings() throws {
    let model = try #require(
        TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-1b-v2-coreml")
    )
    let settings = TranscriptionModelSettings(
        activeModelID: model.id,
        languagePreference: .language("ru"),
        installationStates: [model.id: .downloaded(localURL: URL(fileURLWithPath: "/tmp/canary-1b"))]
    )
    let speechLanguages = UserSpeechLanguages(
        primaryLanguageCode: "ru",
        additionalLanguageCode: "fr"
    )
    let originalSettings = settings
    let originalSpeechLanguages = speechLanguages

    let projection = model.sourceLanguageProjection(
        primary: speechLanguages.primaryLanguageCode,
        additional: speechLanguages.additionalLanguageCode
    )
    let belowMinimum = model.capabilities.isAvailable(
        on: ASRModelCapabilities.OSVersion(majorVersion: 14)
    )

    #expect(!projection.isHardBlocked)
    #expect(!belowMinimum)
    #expect(settings == originalSettings)
    #expect(speechLanguages == originalSpeechLanguages)
    #expect(settings.activeModelID == model.id)
    #expect(settings.languagePreference == .language("ru"))
    #expect(settings.installationState(for: model.id).status == .downloaded)
}

@Test
func S10ClampDeduplicatesWithoutChangingTheConfiguredPair() throws {
    let model = try #require(
        TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-180m-flash-coreml")
    )
    let speechLanguages = UserSpeechLanguages(
        primaryLanguageCode: "en",
        additionalLanguageCode: "en"
    )
    let before = speechLanguages

    let projection = model.sourceLanguageProjection(
        primary: speechLanguages.primaryLanguageCode,
        additional: speechLanguages.additionalLanguageCode
    )

    #expect(projection.effectiveChoices == ["en"])
    #expect(!projection.isClamped)
    #expect(speechLanguages == before)
}

@Test
func S11SessionRoutingDoesNotPersistPairOrLegacyLanguagePreference() throws {
    let model = try #require(
        TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-180m-flash-coreml")
    )
    let settings = TranscriptionModelSettings(
        activeModelID: model.id,
        languagePreference: .language("ru"),
        installationStates: [model.id: .downloaded(localURL: URL(fileURLWithPath: "/tmp/flash"))]
    )
    let pair = UserSpeechLanguages(primaryLanguageCode: "en", additionalLanguageCode: "de")
    let originalSettings = settings
    let originalPair = pair

    let resolution = TranscriptionSessionResolver.resolve(
        activeModel: model,
        modelFolderURL: URL(fileURLWithPath: "/tmp/flash"),
        engineIdentity: "flash-engine",
        currentOSVersion: ASRModelCapabilities.OSVersion(majorVersion: 15),
        hasCompleteModel: true,
        primaryLanguageCode: pair.primaryLanguageCode,
        additionalLanguageCode: pair.additionalLanguageCode,
        operation: .asr
    )
    guard case .available = resolution else {
        Issue.record("Expected an explicit Flash plan")
        return
    }

    #expect(settings == originalSettings)
    #expect(pair == originalPair)
    #expect(settings.languagePreference == .language("ru"))
    #expect(settings.activeModelID == model.id)
}
