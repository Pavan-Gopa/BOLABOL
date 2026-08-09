import Testing
@testable import VaniScriptCore

// A5: registry coverage for the new cloud providers (Qwen / OpenRouter / Ollama
// Cloud). No network, no real keys — settings are constructed in-memory (§14).
@Suite("Provider registry — A5 cloud providers")
struct ProviderRegistryCloudTests {
    init() {
        LocalModelVerification.skipVerificationForTesting = true
    }

    @Test("new cloud providers are hidden without keys")
    func hiddenWithoutKeys() {
        let settings = AppSettings.defaults
        let ids = ProviderRegistry
            .availableTranslationProviders(settings: settings, targetLang: "Russian")
            .providers.map(\.id)

        #expect(!ids.contains(CloudProviderCatalog.qwenID))
        #expect(!ids.contains(CloudProviderCatalog.openrouterID))
        #expect(!ids.contains(CloudProviderCatalog.ollamaCloudID))
    }

    @Test("saved key exposes the provider for translation")
    func keyExposesTranslationOption() {
        var settings = AppSettings.defaults
        settings.qwenApiKey = "test-qwen-key"
        settings.openrouterApiKey = "test-or-key"
        settings.ollamaCloudApiKey = "test-ollama-key"

        let providers = ProviderRegistry
            .availableTranslationProviders(settings: settings, targetLang: "Russian")
            .providers
        let ids = providers.map(\.id)

        #expect(ids.contains(CloudProviderCatalog.qwenID))
        #expect(ids.contains(CloudProviderCatalog.openrouterID))
        #expect(ids.contains(CloudProviderCatalog.ollamaCloudID))

        // Ids double as usage keys (§8) and requiresKey markers; labels from catalog.
        let qwen = providers.first { $0.id == CloudProviderCatalog.qwenID }
        #expect(qwen?.label == "Qwen")
        #expect(qwen?.group == .cloud)
        #expect(qwen?.requiresKey == CloudProviderCatalog.qwenID)
    }

    @Test("whitespace-only key does not expose the provider")
    func whitespaceKeyIgnored() {
        var settings = AppSettings.defaults
        settings.openrouterApiKey = "   \n"
        let ids = ProviderRegistry
            .availableTranslationProviders(settings: settings, targetLang: "Russian")
            .providers.map(\.id)
        #expect(!ids.contains(CloudProviderCatalog.openrouterID))
    }

    @Test("honest transcription gating: text-only model → no transcription option, audio model → transcription option enabled")
    func transcriptionOptionsDynamicGating() {
        var settings = AppSettings.defaults
        settings.qwenApiKey = "k"
        settings.openrouterApiKey = "k"
        settings.ollamaCloudApiKey = "k"

        // Default models (qwen-plus, openai/gpt-4o-mini, gpt-oss:120b) are text-only -> no transcription option.
        let idsTextOnly = ProviderRegistry.availableTranscriptionProviders(settings: settings).map(\.id)
        #expect(!idsTextOnly.contains(CloudProviderCatalog.qwenID))
        #expect(!idsTextOnly.contains(CloudProviderCatalog.openrouterID))
        #expect(!idsTextOnly.contains(CloudProviderCatalog.ollamaCloudID))

        // Qwen is text-only -> no transcription option.
        // When OpenRouter model is set to an audio model (e.g. whisper), transcription option is enabled.
        settings.openrouterModel = "openai/whisper-1"
        let idsWithAudio = ProviderRegistry.availableTranscriptionProviders(settings: settings).map(\.id)
        #expect(!idsWithAudio.contains(CloudProviderCatalog.qwenID))
        #expect(idsWithAudio.contains(CloudProviderCatalog.openrouterID))
    }

    @Test("legacy gemini/gpt behavior is untouched")
    func legacyProvidersUnchanged() {
        var settings = AppSettings.defaults
        settings.geminiKey = "g"
        settings.openaiKey = "o"
        settings.qwenApiKey = "q"

        let translation = ProviderRegistry
            .availableTranslationProviders(settings: settings, targetLang: "Russian")
            .providers.map(\.id)
        #expect(translation.contains("gemini-cloud"))
        #expect(translation.contains("gpt-cloud"))
        #expect(translation.contains("mlx-native"))

        let transcription = ProviderRegistry.availableTranscriptionProviders(settings: settings).map(\.id)
        #expect(transcription.contains("gemini-cloud"))
        #expect(transcription.contains("gpt-cloud"))
    }
}
