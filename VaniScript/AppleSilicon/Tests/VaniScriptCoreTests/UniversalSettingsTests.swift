import Testing
import Foundation
@testable import VaniScriptCore

@Suite("Universal settings parity")
struct UniversalSettingsTests {
    @Test("copies Universal default settings")
    func defaultSettings() {
        let settings = AppSettings.defaults

        #expect(settings.theme == .dark)
        #expect(settings.fontSize == .md)
        #expect(settings.fontScale == 1)
        #expect(settings.fontFamily == .mono)
        #expect(settings.chunkDurationMin == 10)
        #expect(settings.sliceMode == .silence)
        #expect(settings.silenceThreshDb == -16)
        #expect(settings.minSilenceMs == 400)
        #expect(settings.defaultSourceLang == "auto")
        #expect(settings.transcriptionProvider == "coreml-whisperkit")
        #expect(settings.translationProvider == "mlx-native")
        #expect(settings.defaultTargetLang == "Russian")
    }

    @Test("tracks Visual Editor as a first-class workspace screen")
    func workflowScreensIncludeVisualEditorWorkspace() {
        #expect(UniversalWorkflowScreen.allCases.contains(.visualEditor))
        #expect(UniversalWorkflowScreen.visualEditor.title == "Visual Editor")
    }

    @Test("copies Universal local model catalogs")
    func modelCatalogs() {
        let settings = AppSettings.defaults

        #expect(settings.localAsrModels["whisper-small-en"]?.runtime == .whisper)
        #expect(settings.localAsrModels["whisper-medium-en"]?.runtime == .whisper)
        #expect(settings.localAsrModels["whisper-medium-multilingual"]?.runtime == .whisper)
        #expect(settings.localAsrModels["whisper-large-v3"]?.runtime == .whisper)
        #expect(settings.localAsrModels["parakeet-tdt-06b-v3"]?.runtime == .parakeet)
        #expect(settings.localAsrModels["canary-180m-flash-coreml"]?.runtime == .canary)
        #expect(settings.localAsrModels["canary-1b-v2-coreml"]?.runtime == .canary)
        #expect(settings.localTranslationModels["qwen35-4b-4bit"]?.runtime == .mlx)
        #expect(settings.localTranslationModels["qwen35-9b-4bit"]?.status == .notDownloaded)
        #expect(settings.localTranslationModels["nemotron3-nano-4b-4bit"]?.status == .notDownloaded)
    }

    @Test("legacy settings gain new ASR defaults without resetting selection")
    func legacySettingsMergeNewASRDefaults() throws {
        var legacySettings = AppSettings.defaults
        legacySettings.transcriptionProvider = "whisper-large-v3"
        legacySettings.localAsrModels["whisper-large-v3"] = LocalModelState(
            status: .downloaded,
            label: "Whisper Large v3",
            path: "/legacy/whisper-large-v3",
            runtime: .whisper
        )
        legacySettings.localTranslationModels["qwen35-4b-4bit"] = LocalModelState(
            status: .downloaded,
            label: "Qwen 3.5 4B 4bit",
            path: "/legacy/qwen35-4b-4bit",
            runtime: .mlx
        )

        var object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(legacySettings)
            ) as? [String: Any]
        )
        var localASR = try #require(object["localAsrModels"] as? [String: Any])
        localASR.removeValue(forKey: "parakeet-tdt-06b-v3")
        localASR.removeValue(forKey: "canary-180m-flash-coreml")
        localASR.removeValue(forKey: "canary-1b-v2-coreml")
        object["localAsrModels"] = localASR

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyData)

        #expect(decoded.transcriptionProvider == "whisper-large-v3")
        #expect(decoded.localAsrModels["whisper-large-v3"]?.status == .downloaded)
        #expect(decoded.localAsrModels["whisper-large-v3"]?.path == "/legacy/whisper-large-v3")
        #expect(decoded.localTranslationModels["qwen35-4b-4bit"]?.status == .downloaded)
        #expect(decoded.localAsrModels["parakeet-tdt-06b-v3"]?.status == .notDownloaded)
        #expect(decoded.localAsrModels["canary-180m-flash-coreml"]?.runtime == .canary)
        #expect(decoded.localAsrModels["canary-1b-v2-coreml"]?.runtime == .canary)
    }

    @Test("disk synchronization validates new ASR runtimes with their own presence policy")
    func preservesNewASRRuntimeStateDuringSynchronization() {
        var settings = AppSettings.defaults
        settings.transcriptionProvider = "canary-1b-v2-coreml"
        settings.localAsrModels["parakeet-tdt-06b-v3"] = LocalModelState(
            status: .downloaded,
            label: "Parakeet TDT 0.6B v3",
            path: "/installed/parakeet-tdt-0.6b-v3",
            runtime: .parakeet
        )
        settings.localAsrModels["canary-1b-v2-coreml"] = LocalModelState(
            status: .downloaded,
            label: "Canary 1B v2",
            path: "/installed/canary-1b-v2",
            runtime: .canary
        )

        settings.synchronizeLocalModelsWithDisk()

        #expect(settings.transcriptionProvider == "canary-1b-v2-coreml")
        #expect(settings.localAsrModels["parakeet-tdt-06b-v3"]?.status == .failed)
        #expect(settings.localAsrModels["parakeet-tdt-06b-v3"]?.path == "/installed/parakeet-tdt-0.6b-v3")
        #expect(settings.localAsrModels["canary-1b-v2-coreml"]?.status == .failed)
        #expect(settings.localAsrModels["canary-1b-v2-coreml"]?.path == "/installed/canary-1b-v2")
    }

    @Test("active local model badge requires downloaded state")
    func activeLocalModelBadgeRequiresDownloadedState() {
        var settings = AppSettings.defaults

        settings.transcriptionProvider = "whisper-large-v3"
        settings.localAsrModels["whisper-large-v3"]?.status = .notDownloaded
        #expect(!settings.isDownloadedLocalASRModelActive(id: "whisper-large-v3"))

        settings.localAsrModels["whisper-large-v3"]?.status = .downloaded
        #expect(settings.isDownloadedLocalASRModelActive(id: "whisper-large-v3"))
        #expect(!settings.isDownloadedLocalASRModelActive(id: "whisper-medium-en"))

        settings.translationProvider = "qwen35-9b-4bit"
        settings.localTranslationModels["qwen35-9b-4bit"]?.status = .notDownloaded
        #expect(!settings.isDownloadedLocalTranslationModelActive(id: "qwen35-9b-4bit"))

        settings.localTranslationModels["qwen35-9b-4bit"]?.status = .downloaded
        #expect(settings.isDownloadedLocalTranslationModelActive(id: "qwen35-9b-4bit"))
        #expect(!settings.isDownloadedLocalTranslationModelActive(id: "qwen35-4b-4bit"))
    }

    @Test("removes unsupported local translation model ids during disk synchronization")
    func removesUnsupportedLocalTranslationModelIDs() {
        var settings = AppSettings.defaults
        settings.localTranslationModels["custom-deadbeef"] = LocalModelState(
            status: .notDownloaded,
            label: "main",
            runtime: .mlx
        )

        settings.synchronizeLocalModelsWithDisk()

        #expect(settings.localTranslationModels["custom-deadbeef"] == nil)
        #expect(Set(settings.localTranslationModels.keys) == Set(AppSettings.defaults.localTranslationModels.keys))
    }

    @Test("resets legacy incompatible translation provider and downloaded paths during disk synchronization")
    func resetsLegacyIncompatibleTranslationState() throws {
        let legacyFlavor = "Opt" + "iQ"
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptLegacySettings-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyPath = root
            .appendingPathComponent("Direct/models--mlx-community--Qwen3.5-0.8B-\(legacyFlavor)-4bit/snapshots/main", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyPath, withIntermediateDirectories: true)
        try #"{"model_type":"qwen2"}"#.write(to: legacyPath.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try #"{}"#.write(to: legacyPath.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)
        try Data([0, 1, 2, 3]).write(to: legacyPath.appendingPathComponent("model.safetensors"))

        var settings = AppSettings.defaults
        settings.translationProvider = "nemotron3-nano-4b-" + "opt" + "iq" + "-4bit"
        settings.localTranslationModels["qwen35-08b-4bit"] = LocalModelState(
            status: .downloaded,
            progress: 1,
            progressLabel: "Done (Scanned)",
            label: "Qwen 3.5 0.8B 4bit",
            path: legacyPath.path,
            runtime: .mlx
        )
        settings.localTranslationModels["qwen35-2b-4bit"] = LocalModelState(
            status: .notDownloaded,
            progress: 1,
            progressLabel: "Done (Scanned)",
            label: "Qwen 3.5 2B 4bit",
            path: legacyPath.path,
            error: "stale",
            runtime: .mlx
        )

        settings.synchronizeLocalModelsWithDisk()

        #expect(settings.translationProvider == "mlx-native")
        #expect(settings.localTranslationModels["qwen35-08b-4bit"]?.status == .notDownloaded)
        #expect(settings.localTranslationModels["qwen35-08b-4bit"]?.path == nil)
        #expect(settings.localTranslationModels["qwen35-08b-4bit"]?.progress == nil)
        #expect(settings.localTranslationModels["qwen35-08b-4bit"]?.progressLabel == nil)
        #expect(settings.localTranslationModels["qwen35-2b-4bit"]?.status == .notDownloaded)
        #expect(settings.localTranslationModels["qwen35-2b-4bit"]?.path == nil)
        #expect(settings.localTranslationModels["qwen35-2b-4bit"]?.progress == nil)
        #expect(settings.localTranslationModels["qwen35-2b-4bit"]?.progressLabel == nil)
        #expect(settings.localTranslationModels["qwen35-2b-4bit"]?.error == nil)
    }

    @Test("keeps cloud translation providers during disk synchronization")
    func keepsCloudTranslationProviderDuringDiskSynchronization() {
        var settings = AppSettings.defaults
        settings.geminiKey = "gemini-key"
        settings.translationProvider = "gemini-cloud"

        settings.synchronizeLocalModelsWithDisk()

        #expect(settings.translationProvider == "gemini-cloud")
    }

    @Test("adapts glossary to target languages (Russian & Czech)")
    func glossaryAdaptation() {
        var settings = AppSettings.defaults

        // Default target language is Russian, adapt to Russian
        settings.adaptGlossaryToTargetLanguage(targetLang: "Russian")
        let krishnaRU = settings.glossary.first { $0.source == "Kṛṣṇa" }
        #expect(krishnaRU?.translation == "Кришна") // Russian translation from StarterGlossary

        // If changed to Czech (Latin script fallback)
        settings.adaptGlossaryToTargetLanguage(targetLang: "Czech")
        let krishnaCZ = settings.glossary.first { $0.source == "Kṛṣṇa" }
        #expect(krishnaCZ?.translation == "Kṛṣṇa") // Fallback to Sanskrit source with diacritics

        // If changed to French (Latin script fallback)
        settings.adaptGlossaryToTargetLanguage(targetLang: "French")
        let prabhupadaFR = settings.glossary.first { $0.source == "Śrīla Prabhupāda" }
        #expect(prabhupadaFR?.translation == "Śrīla Prabhupāda") // Fallback to Sanskrit source with diacritics
    }

    @Test("manages custom cloud providers")
    func customCloudProviders() {
        var settings = AppSettings.defaults
        #expect(settings.customCloudProviders.isEmpty)

        let newProvider = CustomCloudProvider(
            label: "DeepSeek",
            baseUrl: "https://api.deepseek.com/v1",
            apiKey: "sk-test",
            modelName: "deepseek-chat",
            inputCostPerMillion: 0.14,
            outputCostPerMillion: 0.28,
            budgetLimitUsd: 10.0
        )
        settings.customCloudProviders.append(newProvider)

        #expect(settings.customCloudProviders.count == 1)
        #expect(settings.customCloudProviders[0].label == "DeepSeek")
        #expect(settings.customCloudProviders[0].inputCostPerMillion == 0.14)
        #expect(settings.customCloudProviders[0].budgetLimitUsd == 10.0)
    }

    @Test("persists media resolver settings for web link import")
    func mediaResolverSettingsPersist() throws {
        var settings = AppSettings.defaults
        #expect(settings.mediaResolverEndpoint == "")
        #expect(settings.mediaResolverToken == "")

        settings.mediaResolverEndpoint = "https://resolver.example/"
        settings.mediaResolverToken = "secret-token"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.mediaResolverEndpoint == "https://resolver.example/")
        #expect(decoded.mediaResolverToken == "secret-token")
    }

    @Test("persists first-run onboarding completion per build")
    func onboardingCompletionPersistsPerBuild() throws {
        var settings = AppSettings.defaults
        #expect(settings.hasCompletedOnboarding == false)
        #expect(settings.completedOnboardingBuildID == nil)
        #expect(OnboardingCompletionPolicy.needsOnboarding(settings: settings, currentBuildID: "build-a"))

        OnboardingCompletionPolicy.markCompleted(settings: &settings, currentBuildID: "build-a")

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.hasCompletedOnboarding == true)
        #expect(decoded.completedOnboardingBuildID == "build-a")
        #expect(!OnboardingCompletionPolicy.needsOnboarding(settings: decoded, currentBuildID: "build-a"))
        #expect(OnboardingCompletionPolicy.needsOnboarding(settings: decoded, currentBuildID: "build-b"))
    }
}
