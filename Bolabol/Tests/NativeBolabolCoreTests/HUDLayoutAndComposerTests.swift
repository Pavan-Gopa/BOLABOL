import Foundation
import NativeBolabolCore
import Testing

// Production HUD geometry + provider list composition (used by ContentView and
// ProviderQuickSwitcher AppKit/SwiftUI surfaces).

// MARK: Composer

@Test
func hudComposerDefaultLocalEngineConstants() {
  #expect(HUDProviderListComposer.defaultLocalEngineID == "mlx-swift-local-model")
  #expect(HUDProviderListComposer.defaultLocalDisplayName == "Local.AI")
  #expect(HUDQuickSwitcherLayout.localEngineID == "mlx-swift-local-model")
}

@Test
func hudComposerWithFullCloudSurface() {
  var settings = APIProviderSettings()
  settings.google.apiKey = "g"
  settings.openAI.apiKey = "o"
  settings.qwen.apiKey = "q"
  settings.openRouter.apiKey = "or"
  settings.custom.apiKey = "c"
  settings.custom.baseURL = "https://x.test/v1"
  settings.custom.textModel = "m"
  settings.custom.name = "Acme"

  let list = HUDProviderListComposer.providers(apiSettings: settings)
  #expect(list.first?.displayName == "Local.AI")
  #expect(list.map(\.id).contains("cloud-custom"))
  #expect(list.last?.displayName == "Acme")
  #expect(list.count == 6)
}

@Test
func hudComposerCustomLocalLabels() {
  let list = HUDProviderListComposer.providers(
    apiSettings: APIProviderSettings(),
    localEngineID: "custom-local",
    localDisplayName: "On Device"
  )
  #expect(list == [.init(id: "custom-local", displayName: "On Device")])
}

// MARK: Layout geometry

@Test
func hudLayoutEmptyProvidersHaveZeroHeight() {
  #expect(HUDQuickSwitcherLayout.contentHeight(providers: []) == 0)
  #expect(HUDQuickSwitcherLayout.rowIndex(forY: 10, providers: []) == nil)
}

@Test
func hudLayoutSingleLocalProviderHasNoDivider() {
  let providers = [
    ProviderQuickSwitcherModel.Provider(id: "mlx-swift-local-model", displayName: "Local.AI")
  ]
  #expect(!HUDQuickSwitcherLayout.hasDivider(providers: providers))
  let height = HUDQuickSwitcherLayout.contentHeight(providers: providers)
  let expected =
    HUDQuickSwitcherLayout.verticalPadding * 2 + HUDQuickSwitcherLayout.rowHeight
  #expect(height == expected)
}

@Test
func hudLayoutMultiProviderInsertsDividerAfterLocal() {
  let providers = [
    ProviderQuickSwitcherModel.Provider(id: "mlx-swift-local-model", displayName: "Local.AI"),
    ProviderQuickSwitcherModel.Provider(id: "cloud-google", displayName: "Google"),
  ]
  #expect(HUDQuickSwitcherLayout.hasDivider(providers: providers))
  let height = HUDQuickSwitcherLayout.contentHeight(providers: providers)
  let withoutDivider =
    HUDQuickSwitcherLayout.verticalPadding * 2
    + 2 * HUDQuickSwitcherLayout.rowHeight
    + HUDQuickSwitcherLayout.rowSpacing
  #expect(height == withoutDivider + HUDQuickSwitcherLayout.dividerHeight)
}

@Test
func hudLayoutNoDividerWhenFirstIsNotLocal() {
  let providers = [
    ProviderQuickSwitcherModel.Provider(id: "cloud-google", displayName: "Google"),
    ProviderQuickSwitcherModel.Provider(id: "cloud-openai", displayName: "OpenAI"),
  ]
  #expect(!HUDQuickSwitcherLayout.hasDivider(providers: providers))
}

@Test
func hudLayoutRowIndexHitsLocalThenCloudRows() {
  let providers = [
    ProviderQuickSwitcherModel.Provider(id: "mlx-swift-local-model", displayName: "Local.AI"),
    ProviderQuickSwitcherModel.Provider(id: "cloud-google", displayName: "Google"),
    ProviderQuickSwitcherModel.Provider(id: "cloud-openai", displayName: "OpenAI"),
  ]
  let height = HUDQuickSwitcherLayout.contentHeight(providers: providers)
  // Top row (Local) — y near top of panel.
  let topY = height - HUDQuickSwitcherLayout.verticalPadding - 1
  #expect(HUDQuickSwitcherLayout.rowIndex(forY: topY, providers: providers) == 0)

  // Bottom of panel should be last row.
  let bottomY = HUDQuickSwitcherLayout.verticalPadding + 1
  #expect(HUDQuickSwitcherLayout.rowIndex(forY: bottomY, providers: providers) == 2)
}

@Test
func hudLayoutRowIndexReturnsNilInDividerGap() {
  let providers = [
    ProviderQuickSwitcherModel.Provider(id: "mlx-swift-local-model", displayName: "Local.AI"),
    ProviderQuickSwitcherModel.Provider(id: "cloud-google", displayName: "Google"),
  ]
  let height = HUDQuickSwitcherLayout.contentHeight(providers: providers)
  // Just below row 0: divider zone.
  let yInDivider =
    height - HUDQuickSwitcherLayout.verticalPadding - HUDQuickSwitcherLayout.rowHeight
    - HUDQuickSwitcherLayout.dividerHeight / 2
  #expect(HUDQuickSwitcherLayout.rowIndex(forY: yInDivider, providers: providers) == nil)
}

@Test
func hudLayoutRowIndexNilAboveAndBelowContent() {
  let providers = [
    ProviderQuickSwitcherModel.Provider(id: "cloud-google", displayName: "Google")
  ]
  let height = HUDQuickSwitcherLayout.contentHeight(providers: providers)
  #expect(HUDQuickSwitcherLayout.rowIndex(forY: height + 10, providers: providers) == nil)
  #expect(HUDQuickSwitcherLayout.rowIndex(forY: -1, providers: providers) == nil)
}

@Test
func hudLayoutWidthAndPaddingConstants() {
  #expect(HUDQuickSwitcherLayout.width == 190)
  #expect(HUDQuickSwitcherLayout.rowHeight == 24)
  #expect(HUDQuickSwitcherLayout.rowSpacing == 2)
  #expect(HUDQuickSwitcherLayout.horizontalPadding == 10)
  #expect(HUDQuickSwitcherLayout.verticalPadding == 6)
  #expect(HUDQuickSwitcherLayout.dividerHeight == 7)
}

@Test
func hudHoverOnlyControlsMatchHitTestingAndVoiceOverVisibility() {
  #expect(!HUDInteractionPolicy.allowsHitTesting(isVisible: false))
  #expect(HUDInteractionPolicy.allowsHitTesting(isVisible: true))
  #expect(HUDInteractionPolicy.isAccessibilityHidden(isVisible: false))
  #expect(!HUDInteractionPolicy.isAccessibilityHidden(isVisible: true))
}

@Test
func hudAccessibilityMetadataContainsPromptStateAndSliderValue() {
  let selected = HUDAccessibilityMetadataPolicy.promptSlot(
    name: "Custom prompt 2",
    isSelected: true,
    selectedState: "Selected",
    unselectedState: "Not selected",
    switchHint: "Switch prompt"
  )
  #expect(selected.label == "Custom prompt 2")
  #expect(selected.value == "Selected")
  #expect(selected.hint == "Switch prompt")
  #expect(selected.isSelected)

  let unselected = HUDAccessibilityMetadataPolicy.promptSlot(
    name: "Custom prompt 3",
    isSelected: false,
    selectedState: "Selected",
    unselectedState: "Not selected",
    switchHint: "Switch prompt"
  )
  #expect(unselected.value == "Not selected")
  #expect(!unselected.isSelected)

  let slider = HUDAccessibilityMetadataPolicy.humorSlider(label: "Humor level", level: .comedic)
  #expect(slider.label == "Humor level")
  #expect(slider.value == "80%")
}

// MARK: HUD language menu policy

@Test
func hudLanguageMenuCanaryUsesFullVerifiedCatalogAndCompactCycleSeparately() {
  let options = HUDLanguageMenuPolicy.options(
    backend: .canaryCoreML,
    languages: UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en"),
    supportedSourceCodes: CanaryLanguageCatalog.oneBV2LanguageCodes,
    currentCode: "en",
    isAutomatic: false,
    uiLanguage: .english
  )

  #expect(options.map(\.code) == CanaryLanguageCatalog.oneBV2LanguageCodes)
  #expect(options[5].isCurrent)
  #expect(options[12].code == "it")
  #expect(options[12].hudLabel == "I")
  #expect(options.allSatisfy { !$0.displayName.isEmpty })
  #expect(options.allSatisfy { $0.isSelectable })
  #expect(HUDLanguageMenuPolicy.canarySourceCodes(
    primary: "ru",
    additional: "en",
    supportedCodes: CanaryLanguageCatalog.oneBV2LanguageCodes
  ) == ["ru", "en"])
  #expect(HUDLanguageMenuPolicy.nextCode(current: "ru", choices: ["ru", "en"]) == "en")
  #expect(HUDLanguageMenuPolicy.nextCode(current: "en", choices: ["ru", "en"]) == "ru")
  #expect(HUDLanguageMenuPolicy.nextCode(current: "it", choices: ["ru", "en"]) == "ru")
  #expect(HUDLanguageMenuPolicy.nextCode(current: "ru", choices: ["ru"]) == nil)
}

@Test
func hudLanguageMenuFiltersUnsupportedAdditionalAndDisablesGigaAMSource() {
  let compactCanary = HUDLanguageMenuPolicy.canarySourceCodes(
    primary: "ru",
    additional: "fr",
    supportedCodes: ["ru", "en"]
  )
  #expect(compactCanary == ["ru"])

  let gigaAM = HUDLanguageMenuPolicy.options(
    backend: .gigaAMCoreML,
    languages: UserSpeechLanguages(primaryLanguageCode: "en", additionalLanguageCode: "fr"),
    currentCode: "ru",
    isAutomatic: false,
    uiLanguage: .english
  )
  #expect(gigaAM.map(\.code) == ["ru"])
  #expect(gigaAM[0].hudLabel == "R")
  #expect(!gigaAM[0].isSelectable)
}

@Test
func hudLanguageMenuCanaryFlashUsesFullVerifiedCatalog() {
  let options = HUDLanguageMenuPolicy.options(
    backend: .canaryCoreML,
    languages: UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "en"),
    supportedSourceCodes: CanaryLanguageCatalog.flashLanguageCodes,
    currentCode: "en",
    isAutomatic: false,
    uiLanguage: .english
  )

  #expect(options.map(\.code) == ["en", "de", "fr", "es"])
  #expect(options.allSatisfy { $0.isSelectable && !$0.displayName.isEmpty })
}

@Test
func hudLanguageMenuWhisperAutoTargetShowsCompleteCatalogWithLocalizedNames() {
  let english = HUDLanguageMenuPolicy.options(
    backend: .whisperKitCoreML,
    languages: UserSpeechLanguages(primaryLanguageCode: "en", additionalLanguageCode: "ru"),
    currentCode: "ru",
    isAutomatic: false,
    uiLanguage: .english,
    purpose: .targetLanguageSelection
  )
  let russian = HUDLanguageMenuPolicy.options(
    backend: .whisperKitCoreML,
    languages: UserSpeechLanguages(primaryLanguageCode: "en", additionalLanguageCode: "ru"),
    currentCode: nil,
    isAutomatic: true,
    uiLanguage: .russian,
    purpose: .targetLanguageSelection
  )

  // Auto + the complete 25-language target catalog, never the configured pair.
  #expect(english.map(\.code) == ["auto"] + CanaryLanguageCatalog.oneBV2LanguageCodes)
  #expect(english.count == 26)
  #expect(english[0].hudLabel == "A")
  #expect(english[24].isCurrent)
  #expect(russian[0].isCurrent)
  #expect(russian[25].displayName != english[25].displayName)
}

// MARK: Vertical Pulse geometry

@Test
func verticalPulsePromptRowFitsWithoutShrinkingItsFiveHitTargets() {
  let promptWidth = HUDQuickSwitcherLayout.promptBarWidth(for: 1)
  let panelWidth = HUDQuickSwitcherLayout.verticalPulsePanelWidth(
    baseWidth: 52,
    scale: 1,
    showsPromptBar: true
  )

  #expect(HUDQuickSwitcherLayout.promptSlotCount == 5)
  #expect(promptWidth == 97)
  #expect(panelWidth == promptWidth + 2 * HUDQuickSwitcherLayout.overlayShadowPad)
  #expect(promptWidth <= panelWidth - 2 * HUDQuickSwitcherLayout.overlayShadowPad)
}

@Test
func verticalPulseMainCapsuleScreenFrameIsStableAcrossAccessoryStates() {
  let baseSize = HUDQuickSwitcherLayout.overlayPanelSize(
    for: 1,
    style: .vertical,
    isProcessing: false
  )
  let baseLocalFrame = HUDQuickSwitcherLayout.mainCapsuleFrame(
    panelSize: baseSize,
    scale: 1,
    style: .vertical,
    isProcessing: false,
    showsHumorSlider: false
  )
  let basePanel = HUDOverlayFrame(
    x: 200,
    y: 300,
    width: baseSize.width,
    height: baseSize.height
  )
  let initialScreenFrame = HUDQuickSwitcherLayout.screenCapsuleFrame(
    panelFrame: basePanel,
    localCapsuleFrame: baseLocalFrame
  )

  let states: [(prompt: Bool, humor: Bool)] = [
    (true, false),
    (true, true),
    (false, true),
    (false, false),
  ]
  var currentScreenFrame = initialScreenFrame
  for state in states {
    let nextSize = HUDQuickSwitcherLayout.overlayPanelSize(
      for: 1,
      style: .vertical,
      isProcessing: false,
      showsPromptBar: state.prompt,
      showsHumorSlider: state.humor
    )
    let nextLocalFrame = HUDQuickSwitcherLayout.mainCapsuleFrame(
      panelSize: nextSize,
      scale: 1,
      style: .vertical,
      isProcessing: false,
      showsHumorSlider: state.humor
    )
    let nextPanel = HUDQuickSwitcherLayout.anchoredPanelFrame(
      previousCapsuleScreenFrame: currentScreenFrame,
      newPanelSize: nextSize,
      newLocalCapsuleFrame: nextLocalFrame
    )
    currentScreenFrame = HUDQuickSwitcherLayout.screenCapsuleFrame(
      panelFrame: nextPanel,
      localCapsuleFrame: nextLocalFrame
    )

    #expect(abs(currentScreenFrame.x - initialScreenFrame.x) < 0.001)
    #expect(abs(currentScreenFrame.y - initialScreenFrame.y) < 0.001)
    #expect(abs(currentScreenFrame.width - initialScreenFrame.width) < 0.001)
    #expect(abs(currentScreenFrame.height - initialScreenFrame.height) < 0.001)
  }
}

@Test
func verticalPulseRapidTargetSequencesDoNotAccumulateFrameDrift() {
  let sequences: [[(prompt: Bool, humor: Bool)]] = [
    [(false, false), (true, false), (true, true), (false, false)],
    [(false, false), (true, true), (true, false), (false, false)],
  ]
  let scales = [0.8, 1.0, 1.35, 1.6]

  for scale in scales {
    let initialSize = HUDQuickSwitcherLayout.overlayPanelSize(
      for: scale,
      style: .vertical,
      isProcessing: false
    )
    let initialLocal = HUDQuickSwitcherLayout.mainCapsuleFrame(
      panelSize: initialSize,
      scale: scale,
      style: .vertical,
      isProcessing: false,
      showsHumorSlider: false
    )
    let initialScreen = HUDOverlayFrame(
      x: 400 + initialLocal.x,
      y: 240 + initialLocal.y,
      width: initialLocal.width,
      height: initialLocal.height
    )

    for sequence in sequences {
      var currentScreen = initialScreen
      for state in sequence.dropFirst() {
        let size = HUDQuickSwitcherLayout.overlayPanelSize(
          for: scale,
          style: .vertical,
          isProcessing: false,
          showsPromptBar: state.prompt,
          showsHumorSlider: state.humor
        )
        let local = HUDQuickSwitcherLayout.mainCapsuleFrame(
          panelSize: size,
          scale: scale,
          style: .vertical,
          isProcessing: false,
          showsHumorSlider: state.humor
        )
        let panel = HUDQuickSwitcherLayout.anchoredPanelFrame(
          previousCapsuleScreenFrame: currentScreen,
          newPanelSize: size,
          newLocalCapsuleFrame: local
        )
        currentScreen = HUDQuickSwitcherLayout.screenCapsuleFrame(
          panelFrame: panel,
          localCapsuleFrame: local
        )
      }

      #expect(abs(currentScreen.x - initialScreen.x) < 0.001)
      #expect(abs(currentScreen.y - initialScreen.y) < 0.001)
      #expect(abs(currentScreen.width - initialScreen.width) < 0.001)
      #expect(abs(currentScreen.height - initialScreen.height) < 0.001)
    }
  }
}

@Test
func verticalPulseHumorExpansionIsBelowCapsuleAndOtherStylesKeepGeometry() {
  let vertical = HUDQuickSwitcherLayout.overlayPanelSize(
    for: 1,
    style: .vertical,
    isProcessing: false
  )
  let withHumor = HUDQuickSwitcherLayout.overlayPanelSize(
    for: 1,
    style: .vertical,
    isProcessing: false,
    showsHumorSlider: true
  )
  #expect(withHumor.width == vertical.width)
  #expect(withHumor.height > vertical.height)

  let localWithoutHumor = HUDQuickSwitcherLayout.mainCapsuleFrame(
    panelSize: vertical,
    scale: 1,
    style: .vertical,
    isProcessing: false,
    showsHumorSlider: false
  )
  let localWithHumor = HUDQuickSwitcherLayout.mainCapsuleFrame(
    panelSize: withHumor,
    scale: 1,
    style: .vertical,
    isProcessing: false,
    showsHumorSlider: true
  )
  #expect(localWithHumor.x == localWithoutHumor.x)
  #expect(localWithHumor.width == localWithoutHumor.width)
  #expect(localWithHumor.y > localWithoutHumor.y)

  #expect(
    HUDQuickSwitcherLayout.overlayPanelSize(for: 1, style: .capsule, isProcessing: false)
      == HUDOverlaySize(width: 100, height: 44)
  )
  #expect(
    HUDQuickSwitcherLayout.overlayPanelSize(for: 1, style: .tech, isProcessing: false)
      == HUDOverlaySize(width: 118, height: 46)
  )
}

@Test
func verticalPulseMainCapsuleDoesNotUseAnimatedPanelFrameOrMoveTransitions() throws {
  let overlay = try String(
    contentsOfFile: "Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift",
    encoding: .utf8
  )

  #expect(!overlay.contains("animator().setFrame"))
  #expect(!overlay.contains(".transition(.move"))
  #expect(overlay.contains("HUDQuickSwitcherLayout.anchoredPanelFrame"))
  #expect(overlay.contains("HUDQuickSwitcherLayout.screenCapsuleFrame"))
  #expect(overlay.contains("updateTrackedCapsuleAfterExternalMove"))
  #expect(overlay.contains("laidOutCapsuleScreenFrame = nil"))
  #expect(overlay.contains("visibleFrame: visibleFrame"))
}
@Test
func verticalControlHitFrameMatchesVisibleCapsuleAndSupportsMultipleScales() {
  let scales: [Double] = [0.8, 1.0, 1.25, 1.5]
  for scale in scales {
    let panelSize = HUDQuickSwitcherLayout.overlayPanelSize(
      for: scale,
      style: .vertical,
      isProcessing: false
    )
    let visualScale = HUDQuickSwitcherLayout.overlayVisualScale(for: scale)
    let shadowInset = HUDQuickSwitcherLayout.overlayShadowPad * visualScale
    let visibleHeight = max(1, panelSize.height - 2 * shadowInset)
    let visibleWidth = max(1, panelSize.width - 2 * shadowInset)

    let langFrame = HUDQuickSwitcherLayout.verticalControlHitFrame(
      slot: .language,
      panelSize: panelSize,
      scale: scale,
      style: .vertical,
      isProcessing: false
    )
    let targetFrame = HUDQuickSwitcherLayout.verticalControlHitFrame(
      slot: .target,
      panelSize: panelSize,
      scale: scale,
      style: .vertical,
      isProcessing: false
    )

    let diameter = HUDQuickSwitcherLayout.controlDiameter(for: scale, style: .vertical)
    let margin = HUDQuickSwitcherLayout.controlHitMargin(for: scale)
    let pad = HUDQuickSwitcherLayout.capsuleContentPad(for: scale)

    let expectedLangCenterY = shadowInset + visibleHeight - pad - diameter / 2
    let actualLangCenterY = langFrame.y + langFrame.height / 2
    #expect(abs(actualLangCenterY - expectedLangCenterY) < 0.001)

    let expectedTargetCenterY = shadowInset + pad + diameter / 2
    let actualTargetCenterY = targetFrame.y + targetFrame.height / 2
    #expect(abs(actualTargetCenterY - expectedTargetCenterY) < 0.001)

    let expectedCenterX = shadowInset + visibleWidth / 2
    #expect(abs((langFrame.x + langFrame.width / 2) - expectedCenterX) < 0.001)
    #expect(abs((targetFrame.x + targetFrame.width / 2) - expectedCenterX) < 0.001)

    #expect(langFrame.y > targetFrame.y + targetFrame.height)
  }
}
