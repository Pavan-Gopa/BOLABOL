import Foundation
import NativeBolabolCore
import Testing

// MARK: - Cloud provider stabilization / redesigned API surface
//
// Covers edge cases introduced with multi-key rotation, Qwen Token Plan defaults,
// OpenRouter pricing labels, and capability flags that the HUD / Settings UIs rely on.

// MARK: Empty base URL migration

@Test
func apiProviderSettingsBackfillsEmptyQwenAndOpenRouterBaseURLsOnDecode() throws {
  let json = """
    {
      "google": {"apiKeys":[],"textModel":"gemini-3.5-flash","baseURL":"","name":""},
      "openAI": {"apiKeys":[],"textModel":"gpt-4o-mini","baseURL":"","name":""},
      "qwen": {"apiKeys":["sk-qwen"],"textModel":"qwen3.7-plus","baseURL":"","name":""},
      "openRouter": {"apiKeys":["sk-or"],"textModel":"openai/gpt-4o-mini","baseURL":"  ","name":""}
    }
    """.data(using: .utf8)!

  let settings = try JSONDecoder().decode(APIProviderSettings.self, from: json)
  #expect(settings.qwen.baseURL == APIProviderKind.qwen.defaultBaseURL)
  #expect(settings.openRouter.baseURL == APIProviderKind.openRouter.defaultBaseURL)
  #expect(settings.availablePolishingProviders.map(\.kind) == [.qwen, .openRouter])
}

@Test
func apiProviderSettingsPreservesCustomNonEmptyQwenBaseURL() throws {
  let customBase = "https://dashscope.aliyuncs.com/compatible-mode/v1"
  let json = """
    {
      "qwen": {"apiKeys":["k"],"textModel":"qwen-max","baseURL":"\(customBase)","name":""}
    }
    """.data(using: .utf8)!
  let settings = try JSONDecoder().decode(APIProviderSettings.self, from: json)
  #expect(settings.qwen.baseURL == customBase)
}

// MARK: Multi-key edge cases

@Test
func apiProviderConfigurationRejectsKeysBeyondTen() {
  var config = APIProviderConfiguration()
  for i in 0..<12 {
    config.addKey("key-\(i)")
  }
  #expect(config.apiKeys.count == 10)
  #expect(config.configuredAPIKeyCount == 10)
}

@Test
func apiProviderConfigurationLegacyDisabledColonPrefixIsTreatedAsInactive() {
  // sanitizedAPIKeys also filters the historical "disabled:" prefix.
  let config = APIProviderConfiguration(apiKeys: [
    "live",
    "disabled:parked",
    "\(APIProviderConfiguration.disabledPrefix)also-parked",
  ])
  #expect(config.sanitizedAPIKeys == ["live"])
  #expect(config.configuredAPIKeyCount == 3)
  #expect(config.hasAPIKey)
}

@Test
func apiProviderConfigurationPrimaryKeySetterPreservesDisabledState() {
  var config = APIProviderConfiguration(apiKeys: ["first", "second"])
  config.toggleKeyDisabled(at: 0)
  #expect(config.isKeyDisabled(at: 0))

  config.apiKey = "rotated-first"
  #expect(config.isKeyDisabled(at: 0))
  #expect(config.cleanKey(at: 0) == "rotated-first")
  #expect(config.sanitizedAPIKeys == ["second"])
}

@Test
func apiProviderConfigurationOutOfBoundsKeyOpsAreNoOps() {
  var config = APIProviderConfiguration(apiKeys: ["only"])
  config.removeKey(at: 5)
  config.updateKey("nope", at: 3)
  config.toggleKeyDisabled(at: -1)
  #expect(config.apiKeys == ["only"])
  #expect(config.cleanKey(at: 99) == "")
  #expect(!config.isKeyDisabled(at: 99))
}

@Test
func apiProviderGoogleUnavailableWithoutModelEvenWithKey() {
  var settings = APIProviderSettings()
  settings.google.apiKey = "g-key"
  settings.google.textModel = "   "
  #expect(settings.availablePolishingProviders.isEmpty)

  settings.google.textModel = "gemini-3.5-flash"
  #expect(settings.availablePolishingProviders.map(\.kind) == [.google])
}

@Test
func apiProviderOpenAIAvailableWithKeyAndModelWithoutBaseURL() {
  var settings = APIProviderSettings()
  settings.openAI.apiKey = "sk-test"
  settings.openAI.textModel = "gpt-4o-mini"
  settings.openAI.baseURL = ""
  #expect(settings.availablePolishingProviders.contains { $0.kind == .openAI })
}

// MARK: CloudRemoteModel labels

@Test
func cloudRemoteModelSmallContextShowsRawTokenCount() {
  let model = CloudRemoteModel(id: "tiny", contextLength: 512)
  #expect(model.contextLabel == "512")
}

@Test
func cloudRemoteModelZeroOrNegativeContextShowsDash() {
  #expect(CloudRemoteModel(id: "z", contextLength: 0).contextLabel == "—")
  #expect(CloudRemoteModel(id: "n", contextLength: -1).contextLabel == "—")
}

@Test
func cloudRemoteModelPartialPricingDoesNotEmitCombinedPriceLabel() {
  let inputOnly = CloudRemoteModel(id: "a", promptPricePer1M: 1.0)
  #expect(inputOnly.priceLabel == nil)
  #expect(inputOnly.inputPriceLabel.contains("1.000"))
  #expect(inputOnly.outputPriceLabel == "—")

  let outputOnly = CloudRemoteModel(id: "b", completionPricePer1M: 2.5)
  #expect(outputOnly.priceLabel == nil)
  #expect(outputOnly.inputPriceLabel == "—")
  #expect(outputOnly.outputPriceLabel.contains("2.500"))
}

@Test
func cloudRemoteModelCodableRoundTrip() throws {
  let model = CloudRemoteModel(
    id: "openai/gpt-4o",
    contextLength: 128_000,
    promptPricePer1M: 2.5,
    completionPricePer1M: 10
  )
  let data = try JSONEncoder().encode(model)
  let decoded = try JSONDecoder().decode(CloudRemoteModel.self, from: data)
  #expect(decoded == model)
  #expect(decoded.priceLabel != nil)
}

// MARK: Capability matrix for Settings UI

@Test
func apiProviderKindCapabilityMatrixIsStable() {
  // Settings cards gate Balance / Pricing UI on these flags.
  #expect(APIProviderKind.openRouter.supportsBalance && APIProviderKind.openRouter.supportsPricing)
  #expect(!APIProviderKind.qwen.supportsBalance && !APIProviderKind.qwen.supportsPricing)
  #expect(!APIProviderKind.google.supportsBalance)
  #expect(APIProviderKind.qwen.isOpenAICompatible)
  #expect(APIProviderKind.openRouter.isOpenAICompatible)
  #expect(!APIProviderKind.google.isOpenAICompatible)
}

@Test
func apiProviderDefaultModelsMatchCuratedCatalog() {
  #expect(APIProviderKind.google.defaultTextModel == "gemini-3.5-flash")
  #expect(APIProviderKind.openAI.defaultTextModel == "gpt-4o-mini")
  #expect(APIProviderKind.qwen.defaultTextModel == "qwen3.7-plus")
  #expect(APIProviderKind.openRouter.defaultTextModel == "openai/gpt-4o-mini")
  #expect(APIProviderKind.custom.defaultTextModel.isEmpty)
}

@Test
func polishingModelOptionsCuratedQwenListIncludesTokenPlanModels() {
  let provider = PolishingModelOptionsProvider(apiSettings: APIProviderSettings())
  let ids = provider.availableModels(for: .qwen).map(\.id)
  #expect(ids.contains("qwen3.7-plus"))
  #expect(ids.contains("qwen3.6-flash"))
  #expect(ids.contains("qwen3.8-max-preview"))
}

@Test
func polishingModelOptionsCuratedOpenRouterListUsesSlashedIDs() {
  let provider = PolishingModelOptionsProvider(apiSettings: APIProviderSettings())
  let ids = provider.availableModels(for: .openRouter).map(\.id)
  #expect(ids.allSatisfy { $0.contains("/") })
  #expect(ids.contains("openai/gpt-4o-mini"))
  #expect(ids.contains("google/gemini-3.5-flash"))
}

// MARK: Retry policy hardening (Google stall retries)

@Test
func cloudRequestRetryPolicyClampsTimeoutAndAttempts() {
  let policy = CloudRequestRetryPolicy(
    timeoutInterval: 0.5,
    maxAttempts: 0,
    retryDelayNanoseconds: 0
  )
  #expect(policy.timeoutInterval == 1)
  #expect(policy.maxAttempts == 1)
}

@Test
func cloudRequestRetryErrorDescriptionIsUserFacing() {
  let message = CloudRequestRetryError.emptySuccessfulResponse.errorDescription
  #expect(message != nil)
  #expect(message!.lowercased().contains("empty"))
}

// MARK: Usage statistics multi-provider keys

@Test
func usageStatisticsAccumulatesPerCloudEngineKeyIndependently() {
  var settings = UsageStatisticsSettings()
  settings.record(
    modelID: "cloud-qwen:qwen3.7-plus",
    modelName: "Qwen 3.7 Plus",
    promptTokens: 40,
    completionTokens: 10
  )
  settings.record(
    modelID: "cloud-openrouter:openai/gpt-4o-mini",
    modelName: "GPT-4o Mini",
    promptTokens: 100,
    completionTokens: 20
  )
  settings.record(
    modelID: "cloud-qwen:qwen3.7-plus",
    modelName: "Qwen 3.7 Plus",
    promptTokens: 5,
    completionTokens: 5
  )

  #expect(settings.totals["cloud-qwen:qwen3.7-plus"]?.totalTokens == 60)
  #expect(settings.totals["cloud-openrouter:openai/gpt-4o-mini"]?.totalTokens == 120)
  #expect(settings.lastTransaction.totalTokens == 10)
  #expect(settings.modelNames["cloud-qwen:qwen3.7-plus"] == "Qwen 3.7 Plus")
}

@Test
func usageStatisticsResetDoesNotClearModelNamesOrLastTransaction() {
  var settings = UsageStatisticsSettings()
  settings.record(modelID: "a", modelName: "Alpha", promptTokens: 10, completionTokens: 1)
  settings.reset(modelID: "a")

  #expect(settings.totals["a"]?.totalTokens == 0)
  #expect(settings.modelNames["a"] == "Alpha")
  #expect(settings.lastTransaction.totalTokens == 11)
}
