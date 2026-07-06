import NativeSmartScribeCore
import Testing

@Test
func apiProviderSettingsExposeDefaultProviderModels() {
    let settings = APIProviderSettings()

    #expect(settings.google.textModel == "gemini-2.5-flash")
    #expect(settings.openAI.textModel == "gpt-4o-mini")
    #expect(settings.anthropic.textModel == "claude-3-haiku-20240307")
}

@Test
func apiProviderSettingsRequireCredentialsBeforeProviderIsAvailable() {
    var settings = APIProviderSettings()

    #expect(settings.availablePolishingProviders.isEmpty)

    settings.google.apiKey = "google-key"
    settings.openAI.apiKey = "openai-key"
    settings.custom.name = "OpenRouter"
    settings.custom.apiKey = "custom-key"
    settings.custom.baseURL = "https://openrouter.ai/api/v1"
    settings.custom.textModel = "qwen/qwen3.5"

    #expect(settings.availablePolishingProviders.map(\.kind) == [.google, .openAI, .custom])
}

@Test
func apiProviderSettingsResolvePolishingEngineIDs() {
    #expect(APIProviderKind.google.polishingEngineID == "cloud-google")
    #expect(APIProviderKind.openAI.polishingEngineID == "cloud-openai")
    #expect(APIProviderKind.anthropic.polishingEngineID == "cloud-anthropic")
    #expect(APIProviderKind.custom.polishingEngineID == "cloud-custom")
    #expect(APIProviderKind(polishingEngineID: "cloud-openai") == .openAI)
}
