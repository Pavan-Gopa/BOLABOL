import Foundation
import NativeBolabolCore
import Testing

// MARK: - HUD provider quick switcher (v1.0.1)
//
// Production builds the HUD list as: Local.AI (mlx-swift-local-model) first,
// then available cloud polishing providers, de-duplicated by engine id / display
// name. These tests pin that composition contract and the pure switcher model
// behaviour that drives scroll + live provider activation.

private let localAIEngineID = HUDProviderListComposer.defaultLocalEngineID

private func hudProviderList(
  apiSettings: APIProviderSettings,
  localDisplayName: String = HUDProviderListComposer.defaultLocalDisplayName
) -> [ProviderQuickSwitcherModel.Provider] {
  HUDProviderListComposer.providers(
    apiSettings: apiSettings,
    localEngineID: localAIEngineID,
    localDisplayName: localDisplayName
  )
}

@Test
func hudProviderListAlwaysStartsWithLocalAI() {
  let settings = APIProviderSettings()
  let list = hudProviderList(apiSettings: settings)

  #expect(list.count == 1)
  #expect(list[0].id == localAIEngineID)
  #expect(list[0].displayName == "Local.AI")
}

@Test
func hudProviderListAppendsConfiguredCloudProvidersInUIOrder() {
  var settings = APIProviderSettings()
  settings.google.apiKey = "g-key"
  settings.openAI.apiKey = "o-key"
  settings.qwen.apiKey = "q-key"
  settings.openRouter.apiKey = "or-key"
  settings.custom.apiKey = "c-key"
  settings.custom.baseURL = "https://example.com/v1"
  settings.custom.textModel = "my-model"
  settings.custom.name = "Private"

  let list = hudProviderList(apiSettings: settings)

  #expect(list.map(\.id) == [
    localAIEngineID,
    "cloud-google",
    "cloud-openai",
    "cloud-qwen",
    "cloud-openrouter",
    "cloud-custom",
  ])
  #expect(list.map(\.displayName) == [
    "Local.AI", "Google", "OpenAI", "Qwen", "OpenRouter", "Private",
  ])
}

@Test
func hudProviderListDeduplicatesCustomNamedLikeQwen() {
  // Regression: HUD previously showed "Qwen" twice when a custom endpoint was
  // also named "Qwen". Display-name dedupe keeps the list unique.
  var settings = APIProviderSettings()
  settings.qwen.apiKey = "qwen-key"
  settings.qwen.textModel = "qwen3.7-plus"
  settings.custom.name = "Qwen"
  settings.custom.apiKey = "custom-key"
  settings.custom.baseURL = "https://example.com/v1"
  settings.custom.textModel = "custom-model"

  let list = hudProviderList(apiSettings: settings)
  let names = list.map(\.displayName)

  #expect(names.contains("Local.AI"))
  #expect(names.contains("Qwen"))
  #expect(names.filter { $0 == "Qwen" }.count == 1)
  #expect(Set(names).count == names.count)
}

@Test
func hudProviderListOmitsCloudProvidersMissingCredentialsOrModel() {
  var settings = APIProviderSettings()
  settings.google.apiKey = "g"
  settings.google.textModel = ""  // model required
  settings.openAI.apiKey = ""
  settings.openAI.textModel = "gpt-4o-mini"
  settings.qwen.apiKey = "q"
  settings.qwen.textModel = "qwen3.7-plus"

  let list = hudProviderList(apiSettings: settings)
  #expect(list.map(\.id) == [localAIEngineID, "cloud-qwen"])
}

@Test
func hudSwitcherCanCycleOnlyWithLocalPlusAtLeastOneCloud() {
  var settings = APIProviderSettings()
  // Local alone — cycling disabled (need ≥2 providers for the switcher).
  var alone = ProviderQuickSwitcherModel(
    providers: hudProviderList(apiSettings: settings),
    activeID: localAIEngineID
  )
  #expect(!alone.canCycle)
  #expect(alone.applyScroll(deltaY: -100, now: 1) == nil)

  settings.google.apiKey = "g-key"
  var multi = ProviderQuickSwitcherModel(
    providers: hudProviderList(apiSettings: settings),
    activeID: localAIEngineID
  )
  #expect(multi.canCycle)
  #expect(multi.providers.count == 2)

  let stepped = multi.applyScroll(deltaY: -ProviderQuickSwitcherModel.defaultStepThreshold, now: 1)
  #expect(stepped?.id == "cloud-google")
  #expect(multi.activeProvider?.displayName == "Google")
}

@Test
func hudSwitcherScrollFromLocalToCloudAndBackWraps() {
  var settings = APIProviderSettings()
  settings.google.apiKey = "g"
  settings.openAI.apiKey = "o"
  let providers = hudProviderList(apiSettings: settings)
  var model = ProviderQuickSwitcherModel(providers: providers, activeID: localAIEngineID)

  // Negative scroll = next (toward end of list)
  let next1 = model.applyScroll(deltaY: -30, now: 0)
  #expect(next1?.id == "cloud-google")
  let next2 = model.applyScroll(deltaY: -30, now: 1)
  #expect(next2?.id == "cloud-openai")
  let wrap = model.applyScroll(deltaY: -30, now: 2)
  #expect(wrap?.id == localAIEngineID)

  // Positive scroll = previous
  let prev = model.applyScroll(deltaY: 30, now: 3)
  #expect(prev?.id == "cloud-openai")
}

@Test
func hudSwitcherSelectByIDActivatesCloudEngineWithoutStealingIndexOnUnknown() {
  var settings = APIProviderSettings()
  settings.openRouter.apiKey = "or"
  var model = ProviderQuickSwitcherModel(
    providers: hudProviderList(apiSettings: settings),
    activeID: localAIEngineID
  )

  #expect(model.select(id: "cloud-openrouter")?.displayName == "OpenRouter")
  #expect(model.activeProvider?.id == "cloud-openrouter")

  let before = model.activeIndex
  #expect(model.select(id: "missing-engine") == nil)
  #expect(model.activeIndex == before)
}

@Test
func hudSwitcherResolvesActiveFromPolishingEngineIDs() {
  // Engine id reverse-mapping used when right-click / scroll applies a provider.
  #expect(APIProviderKind(polishingEngineID: "cloud-google") == .google)
  #expect(APIProviderKind(polishingEngineID: "cloud-openai") == .openAI)
  #expect(APIProviderKind(polishingEngineID: "cloud-qwen") == .qwen)
  #expect(APIProviderKind(polishingEngineID: "cloud-openrouter") == .openRouter)
  #expect(APIProviderKind(polishingEngineID: "cloud-custom") == .custom)
  #expect(APIProviderKind(polishingEngineID: localAIEngineID) == nil)
}

@Test
func hudRightClickModelMenuUsesSharedOptionsProvider() {
  // Right-click model menu on HUD shares PolishingModelOptionsProvider with
  // note/translation surfaces so favorites + current model stay consistent.
  var settings = APIProviderSettings()
  settings.openRouter.textModel = "openai/gpt-4o-mini"
  let provider = PolishingModelOptionsProvider(apiSettings: settings)

  let favorites: Set<String> = ["anthropic/claude-3.5-haiku", "google/gemini-3.5-flash"]
  let options = provider.providerModelOptions(for: .openRouter, favorites: favorites)

  #expect(options.map(\.id).contains("openai/gpt-4o-mini"))
  #expect(options.map(\.id).contains("anthropic/claude-3.5-haiku"))
  #expect(options.map(\.id).contains("google/gemini-3.5-flash"))
  // Display names strip vendor prefix for the menu.
  #expect(options.contains { $0.displayName == "gpt-4o-mini" || $0.displayName == "GPT-4o Mini" })
}

@Test
func helpCopyDocumentsHUDProviderScrollAndModelMenu() {
  let hotkeyBody = AppText.localized(.helpModeHotkeyBody, language: .english).lowercased()
  #expect(hotkeyBody.contains("scroll"))
  #expect(hotkeyBody.contains("provider"))
  #expect(hotkeyBody.contains("right-click") || hotkeyBody.contains("model"))

  let providers = AppText.localized(.helpCloudProviders, language: .english)
  #expect(providers.contains("Qwen"))
  #expect(providers.contains("OpenRouter"))
}

@Test
func hudProviderSwitcherInitializerUsesTheNamedThreshold() {
  let model = ProviderQuickSwitcherModel(
    providers: [
      .init(id: "one", displayName: "One"),
      .init(id: "two", displayName: "Two")
    ],
    activeID: "one"
  )
  #expect(model.stepThreshold == ProviderQuickSwitcherModel.defaultStepThreshold)
}

@Test
func hudProviderSwitcherPreciseScrollHonorsBelowAndExactThreshold() {
  let providers = [
    ProviderQuickSwitcherModel.Provider(id: "one", displayName: "One"),
    ProviderQuickSwitcherModel.Provider(id: "two", displayName: "Two")
  ]
  var model = ProviderQuickSwitcherModel(
    providers: providers,
    activeID: "one",
    stepCooldown: 0
  )

  #expect(model.applyScroll(
    deltaY: ProviderQuickSwitcherModel.defaultStepThreshold - 0.01,
    now: 1
  ) == nil)
  #expect(model.activeProvider?.id == "one")
  model = ProviderQuickSwitcherModel(
    providers: providers,
    activeID: "one",
    stepCooldown: 0
  )
  #expect(model.applyScroll(
    deltaY: -ProviderQuickSwitcherModel.defaultStepThreshold,
    now: 2
  )?.id == "two")
}

@Test
func hudProviderSwitcherAccumulationReversalAndBoundarySelectionAreDeterministic() {
  let providers = [
    ProviderQuickSwitcherModel.Provider(id: "one", displayName: "One"),
    ProviderQuickSwitcherModel.Provider(id: "two", displayName: "Two"),
    ProviderQuickSwitcherModel.Provider(id: "three", displayName: "Three")
  ]
  let threshold = ProviderQuickSwitcherModel.defaultStepThreshold
  var model = ProviderQuickSwitcherModel(
    providers: providers,
    activeID: "one",
    stepCooldown: 0
  )

  #expect(model.applyScroll(deltaY: -threshold / 2, now: 1) == nil)
  #expect(model.applyScroll(deltaY: -threshold / 2, now: 2)?.id == "two")
  #expect(model.applyScroll(deltaY: threshold / 2, now: 3) == nil)
  #expect(model.applyScroll(deltaY: threshold / 2, now: 4)?.id == "one")
  #expect(model.applyScroll(deltaY: threshold, now: 5)?.id == "three")
  #expect(model.applyScroll(deltaY: -threshold, now: 6)?.id == "one")
}

@Test
func hudProviderSwitcherNonPreciseDeltaUsesTheSameNamedThreshold() {
  let threshold = ProviderQuickSwitcherModel.defaultStepThreshold
  #expect(ProviderQuickSwitcherModel.nonPreciseHUDScrollDelta(1) == threshold)
  #expect(ProviderQuickSwitcherModel.nonPreciseHUDScrollDelta(-2) == -2 * threshold)
}

@Test
func hudProviderSwitcherIgnoresNonFiniteScrollWithoutPoisoningLaterInput() {
  let providers = [
    ProviderQuickSwitcherModel.Provider(id: "one", displayName: "One"),
    ProviderQuickSwitcherModel.Provider(id: "two", displayName: "Two")
  ]
  let threshold = ProviderQuickSwitcherModel.defaultStepThreshold

  for invalidDelta in [CGFloat.nan, CGFloat.infinity, -CGFloat.infinity] {
    var model = ProviderQuickSwitcherModel(
      providers: providers,
      activeID: "one",
      stepCooldown: 0
    )
    #expect(model.applyScroll(deltaY: invalidDelta, now: 1) == nil)
    #expect(model.activeProvider?.id == "one")
    #expect(model.applyScroll(deltaY: -threshold, now: 2)?.id == "two")
  }
}
