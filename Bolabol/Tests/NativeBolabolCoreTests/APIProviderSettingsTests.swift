import Foundation
import NativeBolabolCore
import Testing

@Test
func apiProviderSettingsExposeDefaultProviderModels() {
  let settings = APIProviderSettings()

  #expect(settings.google.textModel == "gemini-3.5-flash")
  #expect(settings.openAI.textModel == "gpt-4o-mini")
  #expect(settings.qwen.textModel == "qwen3.7-plus")
  #expect(settings.openRouter.textModel == "openai/gpt-4o-mini")
  #expect(settings.openRouter.baseURL == "https://openrouter.ai/api/v1")
}

@Test
func apiProviderSettingsUIOrderIsGoogleOpenAIQwenOpenRouterCustom() {
  #expect(
    APIProviderKind.polishingUICases == [
      .google, .openAI, .qwen, .openRouter, .custom,
    ])
  #expect(!APIProviderKind.polishingUICases.contains(.anthropic))
}

@Test
func apiProviderSettingsRequireCredentialsBeforeProviderIsAvailable() {
  var settings = APIProviderSettings()

  #expect(settings.availablePolishingProviders.isEmpty)

  settings.google.apiKey = "google-key"
  settings.openAI.apiKey = "openai-key"
  settings.qwen.apiKey = "qwen-key"
  settings.openRouter.apiKey = "or-key"
  settings.custom.name = "Private"
  settings.custom.apiKey = "custom-key"
  settings.custom.baseURL = "https://example.com/v1"
  settings.custom.textModel = "my-model"

  #expect(
    settings.availablePolishingProviders.map(\.kind) == [
      .google, .openAI, .qwen, .openRouter, .custom,
    ])
}

@Test
func apiProviderSettingsResolvePolishingEngineIDs() {
  #expect(APIProviderKind.google.polishingEngineID == "cloud-google")
  #expect(APIProviderKind.openAI.polishingEngineID == "cloud-openai")
  #expect(APIProviderKind.qwen.polishingEngineID == "cloud-qwen")
  #expect(APIProviderKind.openRouter.polishingEngineID == "cloud-openrouter")
  #expect(APIProviderKind.custom.polishingEngineID == "cloud-custom")
  #expect(APIProviderKind(polishingEngineID: "cloud-qwen") == .qwen)
}

@Test
func apiProviderSettingsDecodeWithoutQwenField() throws {
  let json = """
    {
      "google": {"apiKey":"","textModel":"gemini-2.5-flash","baseURL":"","name":""},
      "openAI": {"apiKey":"","textModel":"gpt-4o-mini","baseURL":"","name":""},
      "anthropic": {"apiKey":"","textModel":"claude-3-haiku-20240307","baseURL":"","name":""},
      "custom": {"apiKey":"","textModel":"","baseURL":"","name":""}
    }
    """.data(using: .utf8)!
  let settings = try JSONDecoder().decode(APIProviderSettings.self, from: json)
  #expect(settings.qwen.baseURL.contains("token-plan"))
  #expect(settings.qwen.textModel == "qwen3.7-plus")
  #expect(settings.openRouter.baseURL == "https://openrouter.ai/api/v1")
}

@Test
func apiProviderSettingsSupportsMultipleKeysAndBackwardsCompatibility() throws {
  var config = APIProviderConfiguration(apiKey: "key1")
  #expect(config.apiKeys == ["key1"])
  #expect(config.apiKey == "key1")

  config.addKey("key2")
  config.addKey("key3")
  #expect(config.apiKeys == ["key1", "key2", "key3"])
  #expect(config.sanitizedAPIKeys == ["key1", "key2", "key3"])
  #expect(config.apiKey == "key1")

  // Test max key limit (10)
  for i in 4...12 {
    config.addKey("key\(i)")
  }
  #expect(config.apiKeys.count == 10)

  // Test JSON encoding and decoding
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()
  let data = try encoder.encode(config)
  let decoded = try decoder.decode(APIProviderConfiguration.self, from: data)

  #expect(decoded.apiKeys == config.apiKeys)
  #expect(decoded.apiKey == "key1")
}

@Test
func apiProviderSettingsSupportsTogglingDisabledKeys() {
  var config = APIProviderConfiguration(apiKeys: ["key1", "key2", "key3"])
  #expect(config.sanitizedAPIKeys == ["key1", "key2", "key3"])
  #expect(config.configuredAPIKeyCount == 3)

  // Disable key2
  config.toggleKeyDisabled(at: 1)
  #expect(config.isKeyDisabled(at: 1) == true)
  #expect(config.cleanKey(at: 1) == "key2")
  #expect(config.sanitizedAPIKeys == ["key1", "key3"])
  #expect(config.configuredAPIKeyCount == 3)

  // Test disable all except key3
  config.disableAllKeysExcept(at: 2)
  #expect(config.isKeyDisabled(at: 0) == true)
  #expect(config.isKeyDisabled(at: 1) == true)
  #expect(config.isKeyDisabled(at: 2) == false)
  #expect(config.sanitizedAPIKeys == ["key3"])
  #expect(config.apiKey == "key3")

  // Enable all keys
  config.enableAllKeys()
  #expect(config.sanitizedAPIKeys == ["key1", "key2", "key3"])
}

@Test
func apiProviderConfiguredKeyCountIgnoresBlankEntries() {
  let config = APIProviderConfiguration(
    apiKeys: ["key1", "  ", "\(APIProviderConfiguration.disabledPrefix)key2"]
  )

  #expect(config.configuredAPIKeyCount == 2)
  #expect(config.sanitizedAPIKeys == ["key1"])
}

@Test
func apiProviderSettingsKeepsCustomInstancesSharingABuiltInDisplayName() {
  // ADR-031: availability de-duplicates by engine ID only, so a custom
  // endpoint named "Qwen" appears next to the built-in Qwen provider with
  // its own engine ID.
  var settings = APIProviderSettings()
  settings.qwen.apiKey = "qwen-key"
  settings.qwen.textModel = "qwen3.7-plus"

  // Custom provider with same display name as Qwen
  settings.custom.name = "Qwen"
  settings.custom.apiKey = "custom-key"
  settings.custom.baseURL = "https://example.com/v1"
  settings.custom.textModel = "custom-model"

  let available = settings.availablePolishingProviders
  let ids = available.map(\.engineID)
  #expect(ids.contains("cloud-qwen"))
  #expect(ids.contains("cloud-custom"))
  #expect(ids.count == Set(ids).count)
}

@Test
func customUsageBucketsMatchInstanceNamePlusSpaceWithLongerSiblingPriority() {
  // Buckets are keyed by backend name ("<DisplayName> <model>"). A migrated
  // blank name displays as "Custom", and the next default is "Custom 2":
  // resetting "Custom" must not reset "Custom 2" buckets, and "Custom 1"
  // must not reset "Custom 10" buckets.
  var settings = APIProviderSettings()
  settings.customProviders = [
    CustomAPIProviderInstance(
      id: "legacy", configuration: APIProviderConfiguration(name: "")),
    CustomAPIProviderInstance(
      id: "uuid-2", configuration: APIProviderConfiguration(name: "Custom 2")),
    CustomAPIProviderInstance(
      id: "uuid-1", configuration: APIProviderConfiguration(name: "Custom 1")),
    CustomAPIProviderInstance(
      id: "uuid-10", configuration: APIProviderConfiguration(name: "Custom 10")),
  ]

  #expect(settings.usageBucketMatchesCustomInstance(bucketKey: "Custom legacy-model", displayName: "Custom"))
  #expect(
    !settings.usageBucketMatchesCustomInstance(bucketKey: "Custom 2 gpt-4o-mini", displayName: "Custom"))
  #expect(settings.usageBucketMatchesCustomInstance(bucketKey: "Custom 2 gpt-4o-mini", displayName: "Custom 2"))
  #expect(
    !settings.usageBucketMatchesCustomInstance(bucketKey: "Custom legacy-model", displayName: "Custom 2"))
  #expect(
    !settings.usageBucketMatchesCustomInstance(bucketKey: "Custom 10 some-model", displayName: "Custom 1"))
  #expect(settings.usageBucketMatchesCustomInstance(bucketKey: "Custom 1 some-model", displayName: "Custom 1"))
  #expect(
    settings.usageBucketMatchesCustomInstance(bucketKey: "Custom 10 some-model", displayName: "Custom 10"))
  // Matching is case-insensitive and requires the trailing space.
  #expect(settings.usageBucketMatchesCustomInstance(bucketKey: "custom 2 GPT-4O-MINI", displayName: "Custom 2"))
  #expect(!settings.usageBucketMatchesCustomInstance(bucketKey: "Custom", displayName: "Custom"))
  #expect(!settings.usageBucketMatchesCustomInstance(bucketKey: "Other m", displayName: "Custom"))
  #expect(!settings.usageBucketMatchesCustomInstance(bucketKey: "Custom m", displayName: ""))
}
