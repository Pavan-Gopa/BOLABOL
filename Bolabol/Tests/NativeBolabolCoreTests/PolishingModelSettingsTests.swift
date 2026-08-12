import Foundation
import NativeBolabolCore
import Testing

@Test
func polishingModelSettingsActivatesOnlyPreparedModels() {
    let catalog = PolishingModelCatalog.nativeMLX
    let modelID = "qwen35-4b-4bit"
    var settings = PolishingModelSettings()

    #expect(settings.activate(modelID: modelID, catalog: catalog) == false)
    #expect(settings.activeModelID == nil)

    settings.markDownloaded(
        modelID: modelID,
        localURL: URL(fileURLWithPath: "/tmp/qwen35-4b")
    )

    let didActivate = settings.activate(modelID: modelID, catalog: catalog)

    #expect(didActivate)
    #expect(settings.activeModelID == modelID)
}

@Test
func polishingModelSettingsClearsActiveModelWhenPreparationFails() {
    let catalog = PolishingModelCatalog.nativeMLX
    var settings = PolishingModelSettings()
    settings.markDownloaded(modelID: "qwen35-4b-4bit")
    _ = settings.activate(modelID: "qwen35-4b-4bit", catalog: catalog)

    settings.markFailed(
        modelID: "qwen35-4b-4bit",
        errorMessage: "Download failed"
    )

    #expect(settings.activeModelID == nil)
    #expect(settings.installationState(for: "qwen35-4b-4bit").status == .failed)
}

@Test
func polishingModelSettingsClearsActiveModelWhenRemoved() {
    let catalog = PolishingModelCatalog.nativeMLX
    var settings = PolishingModelSettings()
    settings.markDownloaded(modelID: "qwen35-4b-4bit")
    _ = settings.activate(modelID: "qwen35-4b-4bit", catalog: catalog)

    settings.remove(modelID: "qwen35-4b-4bit")

    #expect(settings.activeModelID == nil)
    #expect(settings.installationState(for: "qwen35-4b-4bit").status == .notDownloaded)
}

@Test
func polishingModelDownloadStateClampsProgressFraction() {
    let low = PolishingModelInstallationState.downloading(progressFraction: -1)
    let high = PolishingModelInstallationState.downloading(progressFraction: 2)

    #expect(low.progressFraction == 0)
    #expect(high.progressFraction == 1)
}

@Test
func polishingModelSettingsCanResetInterruptedDownloads() {
    var settings = PolishingModelSettings()
    settings.markDownloading(modelID: "qwen35-08b-4bit", progressFraction: 1)

    settings.resetInterruptedDownloads()

    #expect(settings.installationState(for: "qwen35-08b-4bit").status == .notDownloaded)
}
