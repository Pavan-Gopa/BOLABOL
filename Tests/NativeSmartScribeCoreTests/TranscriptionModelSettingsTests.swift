import Foundation
import NativeSmartScribeCore
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
        .appendingPathComponent("native-smartscribe-model-cache-\(UUID().uuidString)", isDirectory: true)
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
