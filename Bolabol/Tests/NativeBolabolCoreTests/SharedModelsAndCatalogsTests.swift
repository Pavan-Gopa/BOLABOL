import Foundation
import NativeBolabolCore
import Testing

// Shared models root, catalogs, accessibility prompt, prompt template settings edges.

@Test
func accessibilityPermissionPromptStateResetClearsFlag() {
  var state = AccessibilityPermissionPromptState(didRequestPrompt: true)
  state.reset()
  #expect(!state.didRequestPrompt)
  let requested = state.shouldRequestPrompt(isTrusted: false)
  #expect(requested)
}

@Test
func polishingModelCatalogDefaultIsQwen35FourB() {
  let catalog = PolishingModelCatalog.nativeMLX
  #expect(catalog.defaultModel?.id == "qwen35-4b-4bit")
  #expect(!catalog.models.isEmpty)
}

@Test
func transcriptionModelCatalogIsNonEmpty() {
  let catalog = TranscriptionModelCatalog.nativeWhisperKit
  #expect(!catalog.models.isEmpty)
}

@Test
func promptTemplateSettingsDefaultVariantsExist() {
  let settings = PromptTemplateSettings()
  #expect(!settings.template(for: .variantOne).body.isEmpty)
  #expect(!settings.template(for: .variantTwo).body.isEmpty)
  let body = settings.template(for: .variantOne).body
  #expect(body.contains(PromptTemplate.transcriptionPlaceholder) || body.lowercased().contains("transcription"))
}

@Test
func apiProviderKindAllCasesHaveEngineIDs() {
  for kind in APIProviderKind.allCases {
    #expect(!kind.polishingEngineID.isEmpty)
    #expect(kind.polishingEngineID.hasPrefix("cloud-"))
    #expect(APIProviderKind(polishingEngineID: kind.polishingEngineID) == kind)
  }
}

@Test
func apiProviderPolishingUICasesExcludeAnthropic() {
  #expect(!APIProviderKind.polishingUICases.contains(.anthropic))
  #expect(APIProviderKind.polishingUICases.count == 5)
}

@Test
func availableAPIProviderEquatable() {
  let a = AvailableAPIProvider(kind: .google, displayName: "Google", modelName: "g")
  let b = AvailableAPIProvider(kind: .google, displayName: "Google", modelName: "g")
  #expect(a == b)
}

@Test
func sharedModelsRootResolveReturnsUsableDirectory() {
  let root = SharedModelsRoot.resolve()
  #expect(root.isFileURL)
  #expect(!root.path.isEmpty)
}

@Test
func sharedModelsRootModelsDirectoryPerRuntime() throws {
  let tempRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("bolabol-models-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: tempRoot) }

  for runtime in SharedModelRuntime.allCases {
    let dir = try SharedModelsRoot.modelsDirectory(
      for: runtime,
      configuredRoot: tempRoot,
      defaultRoot: tempRoot
    )
    #expect(dir.lastPathComponent == runtime.rawValue)
    #expect(FileManager.default.fileExists(atPath: dir.path))
  }
}

@Test
func modelPresenceVerificationRejectsMissingDirectory() {
  let missing = URL(fileURLWithPath: "/tmp/bolabol-definitely-missing-\(UUID().uuidString)")
  #expect(!LocalModelPresence.isCompleteMLXModel(at: missing))
  #expect(!LocalModelPresence.isCompleteWhisperKitModel(at: missing))
}

@Test
func hotkeySettingsDefaultChordsAreDocumented() {
  #expect(HotkeySettings.defaultPrimaryHotkey == "Option+S")
  #expect(HotkeySettings.defaultSecondaryHotkey == "Option+1")
  #expect(HotkeySettings.defaultTertiaryHotkey == "Option+2")
  #expect(HotkeySettings.defaultSettingsHotkey == "Option+~")
  #expect(HotkeySettings.optionSymbol == "⌥")
}

@Test
func hotkeySettingsNormalizesCommandControlShiftGlyphs() {
  #expect(HotkeySettings.normalizeMacModifiers("⌘+⇧+S") == "Command+Shift+S")
  #expect(HotkeySettings.normalizeMacModifiers("Ctrl+Alt+A") == "Control+Option+A")
  #expect(HotkeySettings.displayString(for: "Control+Option+A") == "⌃⌥A")
  #expect(HotkeySettings.displayString(for: "Shift+X") == "⇧X")
}

@Test
func usageStatisticsEmptyDefaults() {
  let settings = UsageStatisticsSettings()
  #expect(settings.totals.isEmpty)
  #expect(settings.modelNames.isEmpty)
  #expect(settings.lastTransaction.totalTokens == 0)
}

@Test
func usageTokenCountTotalIsSum() {
  let count = UsageTokenCount(promptTokens: 3, completionTokens: 7)
  #expect(count.totalTokens == 10)
}

@Test
func promptSlotsHaveTitles() {
  for slot in PromptSlot.allCases {
    #expect(!slot.title.isEmpty)
    #expect(!slot.shortTitle.isEmpty)
  }
}
