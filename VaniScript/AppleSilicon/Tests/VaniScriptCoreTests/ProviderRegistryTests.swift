import Testing
@testable import VaniScriptCore

@Suite("Provider registry parity")
struct ProviderRegistryTests {
    init() {
        LocalModelVerification.skipVerificationForTesting = true
    }

    @Test("native providers are available without API keys")
    func nativeProvidersAreAvailableWithoutAPIKeys() {
        let settings = AppSettings.defaults

        #expect(ProviderRegistry.availableTranscriptionProviders(settings: settings).map(\.id).contains("coreml-whisperkit"))
        #expect(ProviderRegistry.availableTranslationProviders(settings: settings, targetLang: "Russian").providers.map(\.id).contains("mlx-native"))
    }

    @Test("cloud providers require API keys")
    func cloudProvidersRequireKeys() {
        let settings = AppSettings.defaults

        #expect(!ProviderRegistry.availableTranscriptionProviders(settings: settings).map(\.id).contains("gemini-cloud"))
        #expect(!ProviderRegistry.availableTranslationProviders(settings: settings, targetLang: "Russian").providers.map(\.id).contains("gemini-cloud"))
    }

    @Test("downloaded local models appear as providers")
    func downloadedLocalModelsAppear() {
        var settings = AppSettings.defaults
        settings.localAsrModels["whisper-large-v3"]?.status = .downloaded
        settings.localTranslationModels["qwen35-4b-4bit"]?.status = .downloaded

        #expect(ProviderRegistry.availableTranscriptionProviders(settings: settings).map(\.id).contains("whisper-large-v3"))
        #expect(ProviderRegistry.availableTranslationProviders(settings: settings, targetLang: "Russian").providers.map(\.id).contains("qwen35-4b-4bit"))
    }

    @Test("same language disables translation providers")
    func sameLanguageDisablesTranslation() {
        var settings = AppSettings.defaults
        settings.geminiKey = "key"

        let result = ProviderRegistry.availableTranslationProviders(settings: settings, targetLang: "same")

        #expect(result.enabled == false)
        #expect(!result.providers.isEmpty)
    }
}
