import Foundation
import NativeBlaboomCore
import Testing

// MARK: - Cross-cutting regressions for 1.0.1 product surface
// Hotkey HUD targets, thinking-suppression for new Qwen ladders, locales, output
// text resolution, and onboarding/help contracts that shipped with the HUD switcher.

// MARK: Hotkey HUD target cycle & display

@Test
func hotkeyTargetFullCycleReturnsToRaw() {
  var target = HotkeyTarget.raw
  target = target.next()
  #expect(target == .note)
  target = target.next()
  #expect(target == .x2)
  target = target.next()
  #expect(target == .raw)
  #expect([HotkeyTarget.raw, .note, .x2].map(\.hudLabel) == ["R", "1", "2"])
}

@Test
func hotkeySettingsNormalizesCyrillicLetterKeysToLatin() {
  // Russian layout Option+Ы must resolve to Option+S (primary dictation).
  #expect(HotkeySettings.normalizeMacModifiers("Option+Ы") == "Option+S")
  #expect(HotkeySettings.normalizeMacModifiers("⌥+ы") == "Option+S")
  #expect(HotkeySettings.normalizeMacModifiers("Alt+Й") == "Option+Q")
  #expect(HotkeySettings.displayString(for: "Option+Ы") == "⌥S")
}

@Test
func hotkeySettingsDecodesTertiaryAndSettingsHotkeysWithDefaults() throws {
  let json = """
    {
      "enabled": true,
      "target": "note",
      "mode": "typing",
      "hotkey": "Option+S"
    }
    """.data(using: .utf8)!
  let settings = try JSONDecoder().decode(HotkeySettings.self, from: json)
  #expect(settings.tertiaryHotkey == HotkeySettings.defaultTertiaryHotkey)
  #expect(settings.settingsHotkey == HotkeySettings.defaultSettingsHotkey)
  #expect(settings.secondaryHotkey == HotkeySettings.defaultSecondaryHotkey)
}

@Test
func hotkeySettingsRoundTripsAllFourHotkeySlots() throws {
  var settings = HotkeySettings(
    enabled: true,
    hotkey: "Command+Option+D",
    secondaryHotkey: "Option+1",
    tertiaryHotkey: "Option+2",
    settingsHotkey: "Option+~"
  )
  settings.holdToRecord = true
  let data = try JSONEncoder().encode(settings)
  let decoded = try JSONDecoder().decode(HotkeySettings.self, from: data)
  #expect(decoded.hotkey == "Command+Option+D")
  #expect(decoded.secondaryHotkey == "Option+1")
  #expect(decoded.tertiaryHotkey == "Option+2")
  #expect(decoded.settingsHotkey == "Option+~")
  #expect(decoded.holdToRecord)
  #expect(HotkeySettings.displayString(for: decoded.hotkey) == "⌘⌥D")
}

// MARK: Hotkey output text resolution

@Test
func hotkeyOutputTextResolverX2FallsBackToVariantOneBeforeRaw() {
  let note = BlaboomNote(
    title: "Test",
    rawText: "raw",
    polishedVariantOne: "variant one only",
    polishedVariantTwo: "  "
  )
  #expect(HotkeyOutputTextResolver.text(from: note, target: .x2) == "variant one only")
  #expect(HotkeyOutputTextResolver.text(from: note, target: .note) == "variant one only")
  #expect(HotkeyOutputTextResolver.text(from: note, target: .raw) == "raw")
}

@Test
func hotkeyOutputTextResolverKeepsWhitespaceOnlyVariantsAsEmpty() {
  let note = BlaboomNote(
    title: "Test",
    rawText: "raw text",
    polishedVariantOne: "\n\t  ",
    polishedVariantTwo: "   "
  )
  #expect(HotkeyOutputTextResolver.text(from: note, target: .note) == "raw text")
  #expect(HotkeyOutputTextResolver.text(from: note, target: .x2) == "raw text")
}

// MARK: PolishingModelPromptControl (Qwen 3.5 / 3.6 thinking)

private func polishModel(
  displayName: String,
  repositoryID: String = "owner/repo",
  description: String = ""
) -> PolishingModelDescriptor {
  PolishingModelDescriptor(
    id: displayName,
    displayName: displayName,
    repositoryID: repositoryID,
    backend: .mlxSwiftLLM,
    downloadSize: "1 GB",
    description: description,
    quality: 4,
    speed: 4
  )
}

@Test
func polishingPromptControlSuppressesThinkingOnQwen35And36Variants() {
  let cases = [
    polishModel(displayName: "Qwen3.5-4B-4bit", repositoryID: "mlx-community/Qwen3.5-4B-4bit"),
    polishModel(displayName: "Qwen 3.5 9B", repositoryID: "mlx-community/Qwen3.5-9B-4bit"),
    polishModel(displayName: "qwen-3.5-instruct"),
    polishModel(displayName: "Local", repositoryID: "org/qwen3_5-7b"),
    polishModel(displayName: "Qwen3.6-Flash"),
    polishModel(displayName: "Qwen 3.6", repositoryID: "mlx-community/Qwen3.6-4B"),
    polishModel(displayName: "qwen-3.6-preview"),
    polishModel(displayName: "Qwen-Think-7B", description: "thinking fine-tune"),
    polishModel(displayName: "Qwopus3.5-4B"),
  ]

  for model in cases {
    #expect(
      PolishingModelPromptControl.needsThinkingSuppression(model),
      "Expected thinking suppression for \(model.displayName)"
    )
    #expect(PolishingModelPromptControl.isQwenLike(model))
  }
}

@Test
func polishingPromptControlDoesNotSuppressPlainQwen25Instruct() {
  let model = polishModel(
    displayName: "Qwen2.5-3B-Instruct-mlx-4Bit",
    repositoryID: "mlx-community/Qwen2.5-3B-Instruct-4bit"
  )
  #expect(!PolishingModelPromptControl.needsThinkingSuppression(model))
  #expect(PolishingModelPromptControl.isQwenLike(model))
}

@Test
func polishingPromptControlIsNotQwenLikeForNemotronOrGemma() {
  let nemotron = polishModel(
    displayName: "Nemotron-3 Nano",
    repositoryID: "mlx-community/Nemotron-3-Nano"
  )
  let gemma = polishModel(displayName: "Gemma-2-9B", repositoryID: "google/gemma-2-9b")
  #expect(!PolishingModelPromptControl.isQwenLike(nemotron))
  #expect(!PolishingModelPromptControl.needsThinkingSuppression(nemotron))
  #expect(!PolishingModelPromptControl.isQwenLike(gemma))
}

// MARK: UI languages (uk / tr / pl expansion)

@Test
func uiLanguagePreferenceResolvesUkrainianTurkishPolishLocales() {
  #expect(
    UILanguagePreference.system.resolvedLocaleIdentifier(for: Locale(identifier: "uk_UA")) == "uk"
  )
  #expect(
    UILanguagePreference.system.resolvedLocaleIdentifier(for: Locale(identifier: "tr_TR")) == "tr"
  )
  #expect(
    UILanguagePreference.system.resolvedLocaleIdentifier(for: Locale(identifier: "pl_PL")) == "pl"
  )
  #expect(UILanguagePreference.ukrainian.displayName == "Українська")
  #expect(UILanguagePreference.turkish.displayName == "Türkçe")
  #expect(UILanguagePreference.polish.displayName == "Polski")
}

@Test
func appTextProvidesPrimaryStringsForUkrainianTurkishPolish() {
  let keys: [AppTextKey] = [.settingsGeneral, .record, .translate, .copy, .notes]
  for language in [UILanguagePreference.ukrainian, .turkish, .polish] {
    for key in keys {
      let value = AppText.localized(key, language: language)
      #expect(!value.isEmpty, "\(key.rawValue) empty for \(language.rawValue)")
      #expect(value != key.rawValue, "\(key.rawValue) fell back for \(language.rawValue)")
    }
  }
}

// MARK: Glossary selection helpers (shared by HUD / settings pickers)

@Test
func glossaryCategorySelectionMapsEmptyToNoneAndUnknownToCustom() {
  let categories = ["Tech", "Devotional"]
  #expect(GlossaryCategorySelection.selectionID(for: "", categories: categories)
    == GlossaryCategorySelection.noneID)
  #expect(GlossaryCategorySelection.selectionID(for: "tech", categories: categories) == "Tech")
  #expect(
    GlossaryCategorySelection.selectionID(for: "Brand new", categories: categories)
      == GlossaryCategorySelection.customID
  )

  #expect(
    GlossaryCategorySelection.categoryValue(
      for: GlossaryCategorySelection.noneID, categories: categories
    ).isEmpty
  )
  #expect(
    GlossaryCategorySelection.categoryValue(for: "Tech", categories: categories) == "Tech"
  )
  #expect(
    GlossaryCategorySelection.categoryValue(
      for: GlossaryCategorySelection.customID,
      currentCategory: "My Custom",
      categories: categories
    ) == "My Custom"
  )
}

@Test
func glossaryEntrySearchFiltersBySourceTranslationVariantAndCategory() {
  let entries = [
    GlossaryEntry(
      id: "prabhupada",
      variants: ["Srila"],
      source: "Prabhupada",
      translation: "Прабхупада",
      category: "Names",
      translations: [:],
      remember: true,
      createdAt: "",
      updatedAt: ""
    ),
    GlossaryEntry(
      id: "api-key",
      variants: [],
      source: "API key",
      translation: "ключ API",
      category: "Tech",
      translations: [:],
      remember: true,
      createdAt: "",
      updatedAt: ""
    ),
  ]
  #expect(GlossaryEntrySearch.filter(entries, query: "prabhu").count == 1)
  #expect(GlossaryEntrySearch.filter(entries, query: "ключ").count == 1)
  #expect(GlossaryEntrySearch.filter(entries, query: "Names").count == 1)
  #expect(GlossaryEntrySearch.filter(entries, query: "srila").count == 1)
  #expect(GlossaryEntrySearch.filter(entries, query: "  ").count == 2)
  #expect(GlossaryEntrySearch.filter(entries, query: "zzz").isEmpty)
}

// MARK: Engine registry + local AI for multi-provider HUD

@Test
func polishingEngineRegistryIncludesCloudAndLocalDescriptors() throws {
  let local = TestPolishEngine(id: "mlx-swift-local-model", displayName: "Local.AI")
  let google = TestPolishEngine(id: "cloud-google", displayName: "Google")
  let openRouter = TestPolishEngine(id: "cloud-openrouter", displayName: "OpenRouter")

  let registry = try PolishingEngineRegistry(
    engines: [local, google, openRouter],
    preferredEngineID: "cloud-google"
  )

  #expect(registry.activeEngineID == "cloud-google")
  #expect(registry.descriptors.count == 3)
  #expect(registry.descriptors.filter(\.isActive).count == 1)
  #expect(registry.descriptors.first { $0.id == "mlx-swift-local-model" }?.displayName == "Local.AI")
}

@Test
func polishingEngineRegistryRejectsEmptyEngineList() {
  #expect(throws: PolishingEngineRegistryError.noEnginesRegistered) {
    _ = try PolishingEngineRegistry(engines: [])
  }
}

private struct TestPolishEngine: PolishingEngine {
  let id: String
  let displayName: String

  func polish(_ request: PolishingRequest) async throws -> PolishingResult {
    PolishingResult(
      text: request.rawText,
      diagnostics: EngineDiagnostics(backendName: displayName)
    )
  }
}
