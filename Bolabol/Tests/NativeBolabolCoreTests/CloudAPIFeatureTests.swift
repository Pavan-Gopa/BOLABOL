import Foundation
import NativeBolabolCore
import Testing

// MARK: - New cloud / API feature coverage (Bolabol)
// Covers multi-key rotation helpers, provider capability flags, CloudRemoteModel
// pricing labels, migration of missing OpenRouter/Qwen fields, and usage edge cases
// introduced with the redesigned API Providers surface.

// MARK: Provider capability contract

@Test
func apiProviderOpenAICompatibleFlagsMatchProductSurface() {
  #expect(APIProviderKind.openAI.isOpenAICompatible)
  #expect(APIProviderKind.qwen.isOpenAICompatible)
  #expect(APIProviderKind.openRouter.isOpenAICompatible)
  #expect(APIProviderKind.custom.isOpenAICompatible)
  #expect(!APIProviderKind.google.isOpenAICompatible)
  #expect(!APIProviderKind.anthropic.isOpenAICompatible)
}

@Test
func apiProviderBalanceAndPricingOnlyOpenRouter() {
  for kind in APIProviderKind.allCases {
    if kind == .openRouter {
      #expect(kind.supportsBalance)
      #expect(kind.supportsPricing)
    } else {
      #expect(!kind.supportsBalance)
      #expect(!kind.supportsPricing)
    }
  }
}

@Test
func apiProviderDefaultBaseURLsMatchTokenPlanAndOpenRouter() {
  #expect(
    APIProviderKind.qwen.defaultBaseURL
      == "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1")
  #expect(APIProviderKind.openRouter.defaultBaseURL == "https://openrouter.ai/api/v1")
  #expect(APIProviderKind.openAI.defaultBaseURL == "https://api.openai.com/v1")
  #expect(APIProviderKind.google.defaultBaseURL.isEmpty)
  #expect(APIProviderKind.anthropic.defaultBaseURL.isEmpty)
}

@Test
func apiProviderGetAPIKeyURLsPresentForKnownProviders() {
  for kind in APIProviderKind.polishingUICases where kind != .custom {
    #expect(kind.getAPIKeyURL != nil, "\(kind.rawValue) should expose Get API Key URL")
  }
  #expect(APIProviderKind.custom.getAPIKeyURL == nil)
}

@Test
func apiProviderAnthropicStillMapsEngineIDForMigration() {
  #expect(APIProviderKind.anthropic.polishingEngineID == "cloud-anthropic")
  #expect(APIProviderKind(polishingEngineID: "cloud-anthropic") == .anthropic)
  #expect(APIProviderKind(polishingEngineID: "unknown") == nil)
}

// MARK: Multi-key CRUD

@Test
func apiProviderConfigurationRemoveAndUpdateKeyPreserveDisabledState() {
  var config = APIProviderConfiguration(apiKeys: ["a", "b", "c"])
  config.toggleKeyDisabled(at: 1)
  #expect(config.isKeyDisabled(at: 1))

  config.updateKey("b-rotated", at: 1)
  #expect(config.isKeyDisabled(at: 1))
  #expect(config.cleanKey(at: 1) == "b-rotated")
  #expect(config.sanitizedAPIKeys == ["a", "c"])

  config.removeKey(at: 0)
  #expect(config.apiKeys.count == 2)
  #expect(config.cleanKey(at: 0) == "b-rotated")
  #expect(config.isKeyDisabled(at: 0))
}

@Test
func apiProviderConfigurationLegacySingleKeyJSONDecodesToArray() throws {
  let json = """
    {"apiKey":"sk-legacy","textModel":"gpt-4o-mini","baseURL":"","name":""}
    """.data(using: .utf8)!
  let config = try JSONDecoder().decode(APIProviderConfiguration.self, from: json)
  #expect(config.apiKeys == ["sk-legacy"])
  #expect(config.apiKey == "sk-legacy")
  #expect(config.hasAPIKey)
}

@Test
func apiProviderConfigurationEmptyKeysMeansUnavailable() {
  var config = APIProviderConfiguration()
  #expect(!config.hasAPIKey)
  #expect(config.sanitizedAPIKeys.isEmpty)
  #expect(config.configuredAPIKeyCount == 0)

  config.apiKey = "  "
  #expect(!config.hasAPIKey)
}

@Test
func apiProviderSettingsSetConfigurationRoundTripsPerKind() {
  var settings = APIProviderSettings()
  var qwen = settings.configuration(for: .qwen)
  qwen.apiKey = "sk-sp-test"
  qwen.textModel = "qwen3.7-max"
  settings.setConfiguration(qwen, for: .qwen)

  #expect(settings.qwen.apiKey == "sk-sp-test")
  #expect(settings.configuration(for: .qwen).textModel == "qwen3.7-max")
}

@Test
func apiProviderCustomRequiresBaseURLAndModelToBeAvailable() {
  var settings = APIProviderSettings()
  settings.custom.apiKey = "k"
  settings.custom.textModel = "m"
  // missing base URL
  #expect(!settings.availablePolishingProviders.contains(where: { $0.kind == .custom }))

  settings.custom.baseURL = "https://example.com/v1"
  #expect(settings.availablePolishingProviders.contains(where: { $0.kind == .custom }))
}

@Test
func apiProviderQwenAvailableWithKeyAndModelEvenWithoutCustomBase() {
  var settings = APIProviderSettings()
  settings.qwen.apiKey = "qwen-key"
  settings.qwen.textModel = "qwen3.7-plus"
  // default Token Plan base is already set
  #expect(settings.availablePolishingProviders.contains(where: { $0.kind == .qwen }))
  #expect(
    settings.availablePolishingProviders.first(where: { $0.kind == .qwen })?.modelName
      == "qwen3.7-plus")
}

@Test
func apiProviderSettingsDecodeMissingOpenRouterFillsDefaults() throws {
  let json = """
    {
      "google": {"apiKey":"","textModel":"gemini-3.5-flash","baseURL":"","name":""},
      "openAI": {"apiKey":"","textModel":"gpt-4o-mini","baseURL":"","name":""}
    }
    """.data(using: .utf8)!
  let settings = try JSONDecoder().decode(APIProviderSettings.self, from: json)
  #expect(settings.openRouter.textModel == "openai/gpt-4o-mini")
  #expect(settings.openRouter.baseURL == "https://openrouter.ai/api/v1")
  #expect(settings.qwen.textModel == "qwen3.7-plus")
  #expect(settings.qwen.baseURL.contains("token-plan"))
}

@Test
func apiProviderSettingsEncodeDecodePreservesMultiKeyDisabledPrefix() throws {
  var settings = APIProviderSettings()
  settings.openRouter.apiKeys = ["live-key", "\(APIProviderConfiguration.disabledPrefix)parked"]
  settings.openRouter.textModel = "anthropic/claude-3.5-sonnet"
  let data = try JSONEncoder().encode(settings)
  let decoded = try JSONDecoder().decode(APIProviderSettings.self, from: data)
  #expect(decoded.openRouter.sanitizedAPIKeys == ["live-key"])
  #expect(decoded.openRouter.configuredAPIKeyCount == 2)
  #expect(decoded.openRouter.isKeyDisabled(at: 1))
  #expect(decoded.openRouter.textModel == "anthropic/claude-3.5-sonnet")
}

// MARK: CloudRemoteModel (pricing UI labels)

@Test
func cloudRemoteModelLabelsFormatContextAndPrices() {
  let model = CloudRemoteModel(
    id: "openai/gpt-4o-mini",
    contextLength: 128_000,
    promptPricePer1M: 0.15,
    completionPricePer1M: 0.60
  )
  #expect(model.contextLabel == "128K")
  #expect(model.inputPriceLabel.contains("0.150"))
  #expect(model.outputPriceLabel.contains("0.600"))
  #expect(model.priceLabel != nil)

  let huge = CloudRemoteModel(id: "x", contextLength: 1_000_000)
  #expect(huge.contextLabel == "1.0M")
  #expect(huge.priceLabel == nil)
  #expect(huge.inputPriceLabel == "—")
}

@Test
func cloudRemoteModelEmptyContextShowsDash() {
  let model = CloudRemoteModel(id: "m")
  #expect(model.contextLabel == "—")
  #expect(model.contextLength == nil)
}

// MARK: Usage statistics (new multi-provider keys)

@Test
func usageStatisticsClampsNegativeTokensAndTracksLastTransaction() {
  var settings = UsageStatisticsSettings()
  settings.record(
    modelID: "cloud-qwen:qwen3.7-plus",
    modelName: "Qwen 3.7 Plus",
    promptTokens: -5,
    completionTokens: 10
  )
  #expect(settings.lastTransaction.promptTokens == 0)
  #expect(settings.lastTransaction.completionTokens == 10)
  #expect(settings.totals["cloud-qwen:qwen3.7-plus"]?.totalTokens == 10)
}

@Test
func usageStatisticsRoundTripsThroughCodable() throws {
  var settings = UsageStatisticsSettings()
  settings.record(
    modelID: "cloud-openrouter:openai/gpt-4o-mini",
    modelName: "OpenRouter GPT",
    promptTokens: 100,
    completionTokens: 50
  )
  let data = try JSONEncoder().encode(settings)
  let decoded = try JSONDecoder().decode(UsageStatisticsSettings.self, from: data)
  #expect(decoded.lastTransaction.totalTokens == 150)
  #expect(decoded.totals["cloud-openrouter:openai/gpt-4o-mini"]?.promptTokens == 100)
  #expect(decoded.modelNames["cloud-openrouter:openai/gpt-4o-mini"] == "OpenRouter GPT")
}

@Test
func usageStatisticsZeroTokenRecordStillUpdatesLastTransaction() {
  var settings = UsageStatisticsSettings()
  settings.record(modelID: "m", modelName: "M", promptTokens: 0, completionTokens: 0)
  #expect(settings.lastTransaction.totalTokens == 0)
  #expect(settings.totals["m"]?.totalTokens == 0)
  #expect(settings.modelNames["m"] == "M")
}

@Test
func usageTokenCountAddIsNonNegative() {
  var count = UsageTokenCount(promptTokens: 1, completionTokens: 2)
  count.add(promptTokens: -10, completionTokens: 3)
  #expect(count.promptTokens == 1)
  #expect(count.completionTokens == 5)
  #expect(count.totalTokens == 6)
}
