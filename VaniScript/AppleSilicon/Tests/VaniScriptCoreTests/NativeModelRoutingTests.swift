import Testing
import Foundation
@testable import VaniScriptCore

@Suite("Native model routing")
struct NativeModelRoutingTests {
    @Test("routes transcription to Core ML")
    func transcriptionUsesCoreML() {
        #expect(NativeModelRouting.backend(for: .transcription) == .coreML)
    }

    @Test("routes LLM text tasks to MLX")
    func llmTextTasksUseMLX() {
        for task in NativeTask.llmTextTasks {
            #expect(NativeModelRouting.backend(for: task) == .mlx)
        }
    }

    @Test("does not route native tasks through llama cpp")
    func nativeTasksDoNotUseLlamaCpp() {
        for task in NativeTask.allCases {
            #expect(NativeModelRouting.backend(for: task) != .llamaCpp)
        }
    }

    @Test("active native ASR lookup requires the same exact presence policy")
    func activeNativeASRRequiresExactPresence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptRouting-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let descriptor = try #require(
            NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")
        )
        let path = root.appendingPathComponent("canary-flash", isDirectory: true)
        for relativePath in descriptor.requiredLayout.requiredFiles {
            let url = path.appendingPathComponent(relativePath, isDirectory: relativePath.hasSuffix(".mlmodelc"))
            if relativePath.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data([1]).write(to: url)
            }
        }

        var settings = AppSettings.defaults
        settings.localAsrModels[descriptor.id]?.status = .downloaded
        settings.localAsrModels[descriptor.id]?.path = path.path
        #expect(
            NativeModelCatalog.activeLocalASRModel(
                settings: settings,
                providerID: descriptor.id,
                onMacOSMajor: 14
            )?.id == descriptor.id
        )

        try FileManager.default.removeItem(at: path.appendingPathComponent("vocab.json"))
        #expect(
            NativeModelCatalog.activeLocalASRModel(
                settings: settings,
                providerID: descriptor.id,
                onMacOSMajor: 14
        ) == nil
        )
    }

    @Test("provider lookup consumes reconciled native ASR presence state")
    func providerLookupUsesReconciledNativeASRState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptProvider-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let flash = try #require(
            NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")
        )
        let canaryOneB = try #require(
            NativeModelCatalog.localASRModel(for: "canary-1b-v2-coreml")
        )
        let mismatchedPath = root.appendingPathComponent("flash", isDirectory: true)
        for relativePath in flash.requiredLayout.requiredFiles {
            let url = mismatchedPath.appendingPathComponent(
                relativePath,
                isDirectory: relativePath.hasSuffix(".mlmodelc")
            )
            if relativePath.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data([1]).write(to: url)
            }
        }

        var settings = AppSettings.defaults
        settings.localAsrModels[canaryOneB.id] = LocalModelState(
            status: .downloaded,
            label: canaryOneB.displayName,
            path: mismatchedPath.path,
            runtime: canaryOneB.settingsRuntime
        )

        let staleProviders = ProviderRegistry.availableTranscriptionProviders(settings: settings)
        #expect(staleProviders.contains { $0.id == canaryOneB.id })

        settings.synchronizeLocalModelsWithDisk()

        #expect(settings.localAsrModels[canaryOneB.id]?.status == .failed)
        let reconciledProviders = ProviderRegistry.availableTranscriptionProviders(settings: settings)
        #expect(!reconciledProviders.contains { $0.id == canaryOneB.id })
    }

    @Test("reconciles a missing external ASR path and clears its active badge")
    func missingExternalASRPathIsNotReady() throws {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptMissingExternal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: missingPath) }

        let id = "canary-180m-flash-coreml"
        var settings = AppSettings.defaults
        settings.transcriptionProvider = id
        settings.localAsrModels[id] = LocalModelState(
            status: .downloaded,
            label: "Canary Flash 180M",
            path: missingPath.path,
            runtime: .canary
        )

        #expect(!settings.isDownloadedLocalASRModelActive(id: id))

        settings.synchronizeLocalModelsWithDisk()

        #expect(settings.localAsrModels[id]?.status == .failed)
        #expect(settings.localAsrModels[id]?.path == missingPath.path)
        #expect(!settings.isDownloadedLocalASRModelActive(id: id))
    }

    @Test("pathless downloaded ASR state is inactive before and after reconciliation")
    func pathlessDownloadedASRStateIsNotReady() {
        let id = "canary-180m-flash-coreml"
        var settings = AppSettings.defaults
        settings.transcriptionProvider = id
        settings.localAsrModels[id] = LocalModelState(
            status: .downloaded,
            label: "Canary Flash 180M",
            runtime: .canary
        )

        #expect(!settings.isDownloadedLocalASRModelActive(id: id))

        settings.synchronizeLocalModelsWithDisk()

        #expect(settings.localAsrModels[id]?.status == .failed)
        #expect(!settings.isDownloadedLocalASRModelActive(id: id))
    }
    @Test("favoriteCloudModelIDs persist, toggle, and sort favorites first")
    func favoritesPersistToggleAndSort() throws {
        var settings = AppSettings.defaults
        #expect(settings.favoriteCloudModelIDs.isEmpty)
        #expect(!settings.isFavoriteModel("gemini-2.5-pro"))

        settings.toggleFavoriteModel("gemini-2.5-pro")
        #expect(settings.isFavoriteModel("gemini-2.5-pro"))
        #expect(settings.favoriteCloudModelIDs == ["gemini-2.5-pro"])

        settings.toggleFavoriteModel("google/gemini-2.5-flash")
        #expect(settings.isFavoriteModel("google/gemini-2.5-flash"))
        #expect(settings.favoriteCloudModelIDs == ["gemini-2.5-pro", "google/gemini-2.5-flash"])

        // Round-trip encoding and decoding
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        #expect(decoded.favoriteCloudModelIDs == ["gemini-2.5-pro", "google/gemini-2.5-flash"])
        #expect(decoded.isFavoriteModel("gemini-2.5-pro"))
        #expect(decoded.isFavoriteModel("google/gemini-2.5-flash"))

        // Untoggle
        settings.toggleFavoriteModel("gemini-2.5-pro")
        #expect(!settings.isFavoriteModel("gemini-2.5-pro"))
        #expect(settings.favoriteCloudModelIDs == ["google/gemini-2.5-flash"])

        // Sorting: favorites appear first, then alphabetical
        let rawList = ["zebra-model", "google/gemini-2.5-flash", "alpha-model", "beta-model"]
        let sorted = settings.sortedWithFavorites(rawList)
        #expect(sorted == ["google/gemini-2.5-flash", "alpha-model", "beta-model", "zebra-model"])
    }

    @Test("available transcription providers list has no coreml-whisperkit synthetic stub")
    func availableTranscriptionProvidersHasNoCoreMLWhisperKitStub() {
        let providers = ProviderRegistry.availableTranscriptionProviders(settings: .defaults)
        #expect(!providers.map(\.id).contains("coreml-whisperkit"))
        #expect(!providers.map(\.label).contains("WhisperKit Core ML"))
    }

    @Test("available translation providers list has no mlx-native synthetic stub")
    func availableTranslationProvidersHasNoMLXNativeStub() {
        let availability = ProviderRegistry.availableTranslationProviders(settings: .defaults, targetLang: "Russian")
        #expect(!availability.providers.map(\.id).contains("mlx-native"))
        #expect(!availability.providers.map(\.label).contains("MLX Swift Local"))
    }

    @Test("Settings catalog id maps from gemini-cloud, gpt-cloud, openrouter, qwen, and ollama-cloud")
    func settingsCatalogIDMapping() {
        #expect(ProviderRegistry.cloudProviderCatalogID(for: "gemini-cloud") == CloudProviderCatalog.geminiID)
        #expect(ProviderRegistry.cloudProviderCatalogID(for: "gemini") == CloudProviderCatalog.geminiID)
        #expect(ProviderRegistry.cloudProviderCatalogID(for: "gpt-cloud") == CloudProviderCatalog.openaiID)
        #expect(ProviderRegistry.cloudProviderCatalogID(for: "openai") == CloudProviderCatalog.openaiID)
        #expect(ProviderRegistry.cloudProviderCatalogID(for: "openrouter") == CloudProviderCatalog.openrouterID)
        #expect(ProviderRegistry.cloudProviderCatalogID(for: "qwen") == CloudProviderCatalog.qwenID)
        #expect(ProviderRegistry.cloudProviderCatalogID(for: "ollama-cloud") == CloudProviderCatalog.ollamaCloudID)
        #expect(ProviderRegistry.cloudProviderCatalogID(for: "custom") == CloudProviderCatalog.customID)
        #expect(ProviderRegistry.cloudProviderCatalogID(for: "unknown-local-model") == nil)
    }

    @Test("batch favorite models include starred ids and current selection")
    func batchFavoriteModelsIncludesStarredAndCurrent() {
        var settings = AppSettings.defaults
        settings.geminiTextModel = "gemini-custom-active"
        settings.favoriteCloudModelIDs = ["gemini-2.5-pro", "gemini-1.5-flash", "openai/whisper-large-v3"]

        let geminiModels = settings.favoriteModels(for: "gemini-cloud")
        #expect(geminiModels.contains("gemini-2.5-pro"))
        #expect(geminiModels.contains("gemini-1.5-flash"))
        #expect(geminiModels.contains("gemini-custom-active"))
        #expect(!geminiModels.contains("openai/whisper-large-v3"))

        settings.openrouterTranscriptionModel = "meta-llama/llama-3.3-70b-instruct"
        let openrouterModels = settings.favoriteModels(for: "openrouter")
        #expect(openrouterModels.contains("openai/whisper-large-v3"))
        #expect(openrouterModels.contains("meta-llama/llama-3.3-70b-instruct"))
        #expect(!openrouterModels.contains("gemini-2.5-pro"))
    }

}
