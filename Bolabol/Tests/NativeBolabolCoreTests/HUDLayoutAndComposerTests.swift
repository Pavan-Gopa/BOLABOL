import AppKit
import CoreText
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
func verticalControlCirclesShiftExactlyByTheRailExtentWhenPromptRailShows() {
  for scale in [0.8, 1.0, 1.35, 1.6] {
    let panelWithRails = HUDQuickSwitcherLayout.overlayPanelSize(
      for: scale,
      style: .vertical,
      isProcessing: false,
      showsPromptBar: true,
      showsHumorSlider: true
    )
    let panelBare = HUDQuickSwitcherLayout.overlayPanelSize(
      for: scale,
      style: .vertical,
      isProcessing: false
    )
    for slot in [HUDVerticalControlSlot.language, .target] {
      let withRail = HUDQuickSwitcherLayout.verticalControlHitRegion(
        slot: slot,
        panelSize: panelWithRails,
        scale: scale,
        style: .vertical,
        isProcessing: false,
        showsPromptBar: true,
        showsHumorSlider: true
      )
      let withoutRail = HUDQuickSwitcherLayout.verticalControlHitRegion(
        slot: slot,
        panelSize: panelBare,
        scale: scale,
        style: .vertical,
        isProcessing: false
      )
      #expect(
        abs((withRail.centerX - withoutRail.centerX)
          - HUDQuickSwitcherLayout.promptRailExtent(for: scale)) < 1e-9,
        "scale \(scale) \(slot): circle must shift right by exactly the rail extent"
      )
      #expect(abs(withRail.centerY - withoutRail.centerY) < 1e-9)
      #expect(abs(withRail.radius - withoutRail.radius) < 1e-9)
    }
  }
}

@Test
func verticalMainCapsuleSitsBehindTheReservedRailExtent() {
  for scale in [0.8, 1.0, 1.6] {
    let panel = HUDQuickSwitcherLayout.overlayPanelSize(
      for: scale,
      style: .vertical,
      isProcessing: false,
      showsPromptBar: true,
      showsHumorSlider: true
    )
    let frame = HUDQuickSwitcherLayout.mainCapsuleFrame(
      panelSize: panel,
      scale: scale,
      style: .vertical,
      isProcessing: false,
      showsPromptBar: true,
      showsHumorSlider: true
    )
    let shadow = HUDQuickSwitcherLayout.overlayShadowPad
      * HUDQuickSwitcherLayout.overlayVisualScale(for: scale)
    #expect(
      abs(frame.x - (shadow + HUDQuickSwitcherLayout.promptRailExtent(for: scale))) < 1e-9,
      "scale \(scale): capsule silhouette must sit directly behind the rail extent"
    )
    #expect(abs(frame.y - shadow) < 1e-9, "scale \(scale): rails never lift the capsule")
  }
}

@Test
func verticalPulsePromptRailFitsFiveFullTargetsBesideTheCapsule() {
  let railColumnHeight = HUDQuickSwitcherLayout.promptRailColumnHeight(for: 1)
  let railColumnWidth = HUDQuickSwitcherLayout.promptRailColumnWidth(for: 1)
  let panelWidth = HUDQuickSwitcherLayout.verticalPulsePanelWidth(
    baseWidth: 52,
    scale: 1,
    showsPromptBar: true
  )

  // The rail keeps the same five full-size 17pt targets at 3pt spacing that
  // the horizontal prompt row used, rotated into a left-edge column.
  #expect(HUDQuickSwitcherLayout.promptSlotCount == 5)
  #expect(railColumnWidth == HUDQuickSwitcherLayout.promptSlotButtonWidth)
  #expect(railColumnHeight == 5 * 17 + 4 * 3)
  // The panel grows sideways by exactly the rail plus its gap; it no longer
  // reserves a full-width row.
  #expect(panelWidth == 52 + railColumnWidth + HUDQuickSwitcherLayout.railGap(for: 1))

  // At every scale the rail column fits beside the capsule inside the
  // panel's vertical interior without shrinking its targets.
  for scale in [0.8, 0.9, 1.0, 1.1, 1.35, 1.5, 1.6] {
    let visualScale = HUDQuickSwitcherLayout.overlayVisualScale(for: scale)
    let panel = HUDQuickSwitcherLayout.overlayPanelSize(
      for: scale,
      style: .vertical,
      isProcessing: false,
      showsPromptBar: true,
      showsHumorSlider: true
    )
    let interiorHeight = panel.height
      - 2 * HUDQuickSwitcherLayout.overlayShadowPad * visualScale
    #expect(
      HUDQuickSwitcherLayout.promptRailColumnHeight(for: scale) <= interiorHeight + 1e-9,
      "scale \(scale): rail column must fit the panel's vertical interior"
    )
  }
}

@Test
func verticalPulseHumorRailMatchesTheLeftColumnHeightAndGrowsPanelSideways() {
  // The Human's size-parity rule: the right humor rail is exactly as tall as
  // the left prompt-slot column.
  for scale in [0.8, 1.0, 1.35, 1.6] {
    #expect(
      HUDQuickSwitcherLayout.humorRailHeight(for: scale)
        == HUDQuickSwitcherLayout.promptRailColumnHeight(for: scale),
      "scale \(scale): humor rail height must equal the prompt column height"
    )
  }

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
  #expect(
    withHumor.width
      == vertical.width
        + HUDQuickSwitcherLayout.humorRailWidth(for: 1)
        + HUDQuickSwitcherLayout.railGap(for: 1)
  )
  #expect(withHumor.height == vertical.height)

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
  #expect(localWithHumor.y == localWithoutHumor.y)
  #expect(localWithHumor.width == localWithoutHumor.width)
  #expect(localWithHumor.height == localWithoutHumor.height)

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
func verticalRailStripsHugOppositePanelEdgesAsABalancedPair() {
  for scale in [0.8, 1.0, 1.35, 1.6] {
    let panel = HUDQuickSwitcherLayout.overlayPanelSize(
      for: scale,
      style: .vertical,
      isProcessing: false,
      showsPromptBar: true,
      showsHumorSlider: true
    )
    let promptStrip = HUDQuickSwitcherLayout.verticalPromptRailStripFrame(
      panelSize: panel,
      scale: scale
    )
    let humorStrip = HUDQuickSwitcherLayout.verticalHumorRailStripFrame(
      panelSize: panel,
      scale: scale
    )

    // Left rail hugs the left panel edge, the humor rail the right one.
    let visualScale = HUDQuickSwitcherLayout.overlayVisualScale(for: scale)
    #expect(promptStrip.x <= visualScale + 1e-9)
    #expect(promptStrip.x >= 0)
    #expect(humorStrip.x + humorStrip.width >= panel.width - visualScale - 1e-9)

    // Balanced pair: identical strip height and identical vertical center.
    #expect(abs(promptStrip.height - humorStrip.height) < 1e-9)
    #expect(
      abs((promptStrip.y + promptStrip.height / 2) - (humorStrip.y + humorStrip.height / 2)) < 1e-9
    )

    // Both strips stay fully inside the panel.
    for strip in [promptStrip, humorStrip] {
      #expect(strip.y >= -1e-9)
      #expect(strip.y + strip.height <= panel.height + 1e-9)
      #expect(strip.x >= -1e-9)
      #expect(strip.x + strip.width <= panel.width + 1e-9)
    }

    // The strips never intrude on the capsule's circular language/target
    // controls, which keep exclusive ownership of the capsule zone.
    for slot in [HUDVerticalControlSlot.language, .target] {
      let region = HUDQuickSwitcherLayout.verticalControlHitRegion(
        slot: slot,
        panelSize: panel,
        scale: scale,
        style: .vertical,
        isProcessing: false,
        showsPromptBar: true,
        showsHumorSlider: true
      )
      let circleBox = region.boundingFrame
      #expect(
        promptStrip.x + promptStrip.width <= circleBox.x - 0.4,
        "scale \(scale) \(slot): prompt strip must stay left of the capsule circle"
      )
      #expect(
        humorStrip.x >= circleBox.x + circleBox.width + 0.4,
        "scale \(scale) \(slot): humor strip must stay right of the capsule circle"
      )
    }
  }
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
func techProcessingRendersElectricSwarmInsteadOfTheUniformZigzag() throws {
  let overlay = try String(
    contentsOfFile: "Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift",
    encoding: .utf8
  )

  // The processing slot is the free-form electric particle swarm…
  #expect(overlay.contains("struct ElectricSwarmView"))
  #expect(!overlay.contains("struct BitstreamFlowView"), "the old bitstream must be fully replaced")
  #expect(overlay.contains("HUDElectricSwarmPolicy"), "the swarm must draw from the deterministic policy")
  let layoutContentStart = try #require(overlay.range(of: "private var layoutContent"))
  let techBranchRange = try #require(
    overlay.range(of: "case .tech:", range: layoutContentStart.lowerBound..<overlay.endIndex)
  )
  let techBranch = overlay[techBranchRange.lowerBound...].prefix(600)
  #expect(techBranch.contains("ElectricSwarmView"), "tech processing must compose ElectricSwarmView")

  // …the listening zigzag stays listening-only: no synthetic uniform
  // processing branch survives inside it, and its voice response comes from
  // the shared response policy.
  let zigzagStart = try #require(overlay.range(of: "struct EnergyZigzagSpectrumView"))
  let zigzagEnd = try #require(
    overlay.range(of: "struct ElectricSwarmView", range: zigzagStart.lowerBound..<overlay.endIndex)
  )
  let zigzagSource = overlay[zigzagStart.lowerBound..<zigzagEnd.lowerBound]
  #expect(!zigzagSource.contains("isProcessing"), "the uniform synthetic processing zigzag must be gone")
  #expect(zigzagSource.contains("HUDSpectrumResponse.techListeningValues"))
}

@Test
func techProcessingSwarmRendersFreeFormWithoutVisiblePillChrome() throws {
  let overlay = try String(
    contentsOfFile: "Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift",
    encoding: .utf8
  )

  // Verify the exact truth table for showsPillChrome:
  // chrome = (style != .vertical) && !(style == .tech && mode == .processing)
  enum TestMode: String, CaseIterable {
    case listening
    case processing
  }

  func showsPillChromeExpected(style: OverlayHUDStyle, mode: TestMode) -> Bool {
    style != .vertical && !(style == .tech && mode == .processing)
  }

  // Exact truth-table assertions covering all 6 combinations:
  #expect(showsPillChromeExpected(style: .capsule, mode: .listening) == true, "capsule listening must show chrome")
  #expect(showsPillChromeExpected(style: .capsule, mode: .processing) == true, "capsule processing must keep chrome")
  #expect(showsPillChromeExpected(style: .tech, mode: .listening) == true, "tech listening must show chrome")
  #expect(showsPillChromeExpected(style: .tech, mode: .processing) == false, "tech processing must exclude chrome (free-form swarm)")
  #expect(showsPillChromeExpected(style: .vertical, mode: .listening) == false, "vertical listening must remain shell-free")
  #expect(showsPillChromeExpected(style: .vertical, mode: .processing) == false, "vertical processing must remain shell-free")

  // The source gate in HotkeySessionOverlayManager must implement exactly this logic:
  let chromeGateStart = try #require(overlay.range(of: "private var showsPillChrome: Bool {"))
  let chromeGateEnd = try #require(
    overlay.range(of: "}", range: chromeGateStart.lowerBound..<overlay.endIndex)
  )
  let chromeGateSource = overlay[chromeGateStart.lowerBound..<chromeGateEnd.upperBound]
    .replacingOccurrences(of: " ", with: "")
    .replacingOccurrences(of: "\n", with: "")

  // Must match the exact predicate: state.style!=.vertical&&!(state.style==.tech&&state.mode==.processing)
  #expect(
    chromeGateSource.contains("state.style!=.vertical&&!(state.style==.tech&&state.mode==.processing)"),
    "the chrome gate must implement the exact truth-table predicate"
  )
  // Ensure broadened/incorrect predicates fail:
  #expect(!chromeGateSource.contains("state.style==.tech||state.mode==.processing"), "broadened predicate must not be used")
  #expect(!chromeGateSource.contains("state.mode==.listening"), "mode-only gate must not be used")

  let hudPillStart = try #require(overlay.range(of: "private var hudPill"))
  let hudPillSource = overlay[hudPillStart.lowerBound...].prefix(1700)
  #expect(hudPillSource.contains("showsPillChrome"), "the pill must consult the free-form gate")
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

@Test
func verticalHitRegionExcludesInertBoundingCornersAtEveryScale() {
  let layout = HUDQuickSwitcherLayout.self
  let scales: [Double] = [0.8, 1.0, 1.25, 1.5]
  for scale in scales {
    let style = OverlayHUDStyle.vertical
    let panelSize = layout.overlayPanelSize(for: scale, style: style, isProcessing: false)
    for slot in [HUDVerticalControlSlot.language, .target] {
      let region = layout.verticalControlHitRegion(
        slot: slot,
        panelSize: panelSize,
        scale: scale,
        style: style,
        isProcessing: false,
        showsPromptBar: false,
        showsHumorSlider: false
      )
      let frame = layout.verticalControlHitFrame(
        slot: slot,
        panelSize: panelSize,
        scale: scale,
        style: style,
        isProcessing: false,
        showsPromptBar: false,
        showsHumorSlider: false
      )

      #expect(region.boundingFrame == frame)
      #expect(region.contains(pointX: region.centerX, pointY: region.centerY + region.radius - 0.5))
      for cornerX in [region.centerX - region.radius, region.centerX + region.radius] {
        for cornerY in [region.centerY - region.radius, region.centerY + region.radius] {
          #expect(!region.contains(pointX: cornerX, pointY: cornerY))
        }
      }
    }
  }
}

// MARK: - HUD Circle Glyph Outline Centering Pins (S9.D1)

private func measuredRoundedSemiboldOutlineCorrection(
  label: String,
  fontSize: Double
) -> (dx: Double, dy: Double) {
  let pointSize = CGFloat(fontSize)
  guard pointSize.isFinite, pointSize > 0, !label.isEmpty else {
    return (0, 0)
  }

  let baseDescriptor = NSFont.systemFont(ofSize: pointSize, weight: .semibold).fontDescriptor
  let roundedDescriptor = baseDescriptor.withDesign(.rounded) ?? baseDescriptor
  let ctFont = CTFontCreateWithFontDescriptor(roundedDescriptor, pointSize, nil)

  var characters = Array(label.utf16)
  guard !characters.isEmpty else {
    return (0, 0)
  }

  var glyphs = [CGGlyph](repeating: 0, count: characters.count)
  let resolved = characters.withUnsafeMutableBufferPointer { charactersBuffer in
    glyphs.withUnsafeMutableBufferPointer { glyphsBuffer in
      guard
        let charactersBase = charactersBuffer.baseAddress,
        let glyphsBase = glyphsBuffer.baseAddress
      else {
        return false
      }
      return CTFontGetGlyphsForCharacters(
        ctFont,
        charactersBase,
        glyphsBase,
        charactersBuffer.count
      )
    }
  }
  guard resolved, !glyphs.contains(0) else {
    return (0, 0)
  }

  guard let metrics = glyphs.withUnsafeBufferPointer({
    glyphsBuffer -> (CGRect, Double)? in
    guard let glyphsBase = glyphsBuffer.baseAddress else {
      return nil
    }
    var outlineRects = [CGRect](repeating: .zero, count: glyphsBuffer.count)
    guard let outline = outlineRects.withUnsafeMutableBufferPointer({
      rectsBuffer -> CGRect? in
      guard let rectsBase = rectsBuffer.baseAddress else {
        return nil
      }
      return CTFontGetBoundingRectsForGlyphs(
        ctFont,
        .horizontal,
        glyphsBase,
        rectsBase,
        glyphsBuffer.count
      )
    }) else {
      return nil
    }
    let success =
      outline.width.isFinite
      && outline.height.isFinite
      && outline.width > 0
      && outline.height > 0
    guard success else {
      return nil
    }
    let advance = CTFontGetAdvancesForGlyphs(
      ctFont,
      .horizontal,
      glyphsBase,
      nil,
      glyphsBuffer.count
    )
    guard advance.isFinite else {
      return nil
    }
    return (outline, advance)
  }) else {
    return (0, 0)
  }

  let (outline, advance) = metrics
  return (
    dx: Double(outline.midX) - advance / 2,
    dy: (
      (Double(CTFontGetAscent(ctFont)) - Double(CTFontGetDescent(ctFont))) / 2
    ) - Double(outline.midY)
  )
}

private func measuredGlyphImageResidual(
  _ image: CGImage,
  backingScale: Double,
  alphaThreshold: UInt8
) -> (dx: Double, dy: Double)? {
  guard backingScale.isFinite, backingScale > 0 else {
    return nil
  }
  guard
    let provider = image.dataProvider,
    let data = provider.data,
    let bytes = CFDataGetBytePtr(data)
  else {
    return nil
  }
  let width = image.width
  let height = image.height
  let bytesPerRow = image.bytesPerRow
  var minX = width
  var minY = height
  var maxX = -1
  var maxY = -1
  for y in 0..<height {
    for x in 0..<width {
      let alpha = bytes[y * bytesPerRow + x * 4 + 3]
      guard alpha > alphaThreshold else {
        continue
      }
      minX = min(minX, x)
      minY = min(minY, y)
      maxX = max(maxX, x)
      maxY = max(maxY, y)
    }
  }
  let targetX = Double(width - 1) / 2
  let targetY = Double(height - 1) / 2
  return (
    dx: Double(minX + maxX) / 2 - targetX,
    dy: Double(minY + maxY) / 2 - targetY
  )
}


private func measuredGlyphImageWeightedResidual(
  _ image: CGImage,
  backingScale: Double
) -> (dx: Double, dy: Double)? {
  guard
    backingScale.isFinite,
    backingScale > 0,
    let provider = image.dataProvider,
    let data = provider.data,
    let bytes = CFDataGetBytePtr(data)
  else {
    return nil
  }
  let width = image.width
  let height = image.height
  let bytesPerRow = image.bytesPerRow
  var total = 0.0
  var weightedX = 0.0
  var weightedY = 0.0
  for y in 0..<height {
    for x in 0..<width {
      let weight = Double(bytes[y * bytesPerRow + x * 4 + 3])
      guard weight > 16 else {
        continue
      }
      total += weight
      weightedX += Double(x) * weight
      weightedY += Double(y) * weight
    }
  }
  guard total > 0 else {
    return nil
  }
  let targetX = Double(width - 1) / 2
  let targetY = Double(height - 1) / 2
  return (
    dx: weightedX / total - targetX,
    dy: weightedY / total - targetY
  )
}

@Test
func hudControlGlyphOutlineCenteringMatrixAcrossProductionLabelsStylesAndScales() {
  let scales: [Double] = [0.8, 1.0, 1.35, 1.6]
  let styles: [OverlayHUDStyle] = [.capsule, .tech, .vertical]
  let controls: [(slot: HUDVerticalControlSlot, label: String)] = [
    (.language, "A"),
    (.target, "1"),
    (.target, "2"),
    (.target, "R"),
  ]
  let promptLabels = ["D", "1", "2", "3", "4"]

  for scale in scales {
    for style in styles {
      let panelSize = HUDQuickSwitcherLayout.overlayPanelSize(
        for: scale,
        style: style,
        isProcessing: false,
        showsPromptBar: true,
        showsHumorSlider: true
      )

      for control in controls {
        let hitRegion = HUDQuickSwitcherLayout.controlHitRegion(
          slot: control.slot,
          panelSize: panelSize,
          scale: scale,
          style: style,
          isProcessing: false,
          showsPromptBar: true,
          showsHumorSlider: true
        )
        let controlFrame = HUDQuickSwitcherLayout.controlFrame(
          slot: control.slot,
          panelSize: panelSize,
          scale: scale,
          style: style,
          isProcessing: false,
          showsPromptBar: true,
          showsHumorSlider: true
        )
        let glyphCenter = HUDQuickSwitcherLayout.controlGlyphCenter(
          slot: control.slot,
          label: control.label,
          panelSize: panelSize,
          scale: scale,
          style: style,
          isProcessing: false,
          showsPromptBar: true,
          showsHumorSlider: true
        )
        let localCenter = HUDQuickSwitcherLayout.controlGlyphLocalCenter(
          for: scale,
          style: style,
          label: control.label
        )
        let diameter = HUDQuickSwitcherLayout.controlDiameter(for: scale, style: style)
        let fontSize = 12 * diameter / HUDQuickSwitcherLayout.controlButtonDiameter
        let outline = measuredRoundedSemiboldOutlineCorrection(
          label: control.label,
          fontSize: fontSize
        )

        let frameCenterX = controlFrame.x + controlFrame.width / 2
        let frameCenterY = controlFrame.y + controlFrame.height / 2
        #expect(
          abs(frameCenterX - hitRegion.centerX) < 1e-9,
          "scale \(scale) style \(style) \(control.label): frame center X must match policy"
        )
        #expect(
          abs(frameCenterY - hitRegion.centerY) < 1e-9,
          "scale \(scale) style \(style) \(control.label): frame center Y must match policy"
        )
        #expect(
          abs(glyphCenter.x - frameCenterX + outline.dx) < 0.01,
          "scale \(scale) style \(style) \(control.label): corrected outline center X must match circle"
        )
        #expect(
          abs(glyphCenter.y - frameCenterY + outline.dy) < 0.01,
          "scale \(scale) style \(style) \(control.label): corrected outline center Y must match circle"
        )
        #expect(
          abs(localCenter.x - diameter / 2 + outline.dx) < 0.01,
          "scale \(scale) style \(style) \(control.label): local outline center X must match circle"
        )
        #expect(
          abs(localCenter.y - diameter / 2 + outline.dy) < 0.01,
          "scale \(scale) style \(style) \(control.label): local outline center Y must match circle"
        )
      }

      for label in promptLabels {
        let buttonSize = HUDQuickSwitcherLayout.promptSlotButtonSize(for: scale)
        let glyphCenter = HUDQuickSwitcherLayout.promptSlotGlyphLocalCenter(
          for: scale,
          label: label
        )
        let outline = measuredRoundedSemiboldOutlineCorrection(
          label: label,
          fontSize: HUDQuickSwitcherLayout.promptSlotGlyphFontSize(for: scale)
        )
        #expect(label.utf16.count == 1, "prompt label \(label) must be a single rendered glyph")
        #expect(
          abs(glyphCenter.x - buttonSize / 2 + outline.dx) < 0.01,
          "scale \(scale) style \(style) prompt \(label): corrected outline center X must match square"
        )
        #expect(
          abs(glyphCenter.y - buttonSize / 2 + outline.dy) < 0.01,
          "scale \(scale) style \(style) prompt \(label): corrected outline center Y must match square"
        )
      }
    }
  }
}

@Test
func hudOutlineCorrectionFallsBackToZeroForGlyphsWithoutPositiveInkBounds() {
  let correction = HUDQuickSwitcherLayout.glyphOutlineCorrection(
    for: " ",
    fontSize: 11
  )

  #expect(correction == .zero)
}

@Test
func hudRuntimeOutlineCorrectionUsesMeasuredLabelOrderingAndConcreteRanges() {
  let labels = ["A", "1", "2", "3", "4", "D", "R", "E"]
  let fontSizes: [Double] = [8.8, 11.0, 13.75, 17.6]

  for fontSize in fontSizes {
    let measured = Dictionary(
      uniqueKeysWithValues: labels.map { label in
        (
          label,
          measuredRoundedSemiboldOutlineCorrection(label: label, fontSize: fontSize)
        )
      }
    )
    let runtime = Dictionary(
      uniqueKeysWithValues: labels.map { label in
        (label, HUDQuickSwitcherLayout.glyphOutlineCorrection(for: label, fontSize: fontSize))
      }
    )

    for label in labels {
      #expect(
        abs(runtime[label]!.dx - measured[label]!.dx) < 1e-9,
        "\(label) runtime dx must come from CTFont outline measurement at \(fontSize)pt"
      )
      #expect(
        abs(runtime[label]!.dy - measured[label]!.dy) < 1e-9,
        "\(label) runtime dy must come from CTFont outline measurement at \(fontSize)pt"
      )
      #expect(
        runtime[label]!.dy >= 0.15 && runtime[label]!.dy <= 0.56,
        "\(label) outline dy must be positive and stay in the concrete 0.15...0.56pt range at \(fontSize)pt"
      )
    }

    let oneDX = runtime["1"]!.dx
    #expect(
      oneDX >= -0.95 && oneDX <= -0.60,
      "1 correction must stay in the measured -0.95...-0.60pt range at \(fontSize)pt"
    )
    #expect(oneDX < 0, "1 correction must be negative so its frame center shifts right")
    #expect(
      runtime["2"]!.dx >= -0.25 && runtime["2"]!.dx <= -0.02,
      "2 correction must stay in the measured small-negative -0.25...-0.02pt range at \(fontSize)pt"
    )
    #expect(
      abs(runtime["R"]!.dx) <= 0.20,
      "R correction must stay near zero in the measured -0.20...+0.20pt range at \(fontSize)pt"
    )
    #expect(
      runtime["R"]!.dx <= 0.04,
      "R correction must remain negative or only rounding-close to zero at \(fontSize)pt"
    )
    for label in ["A", "3", "4", "D", "E"] {
      #expect(
        runtime[label]!.dx >= -0.30 && runtime[label]!.dx <= 0.04,
        "\(label) correction must stay in its measured concrete outline range at \(fontSize)pt"
      )
    }
    #expect(
      labels.filter { $0 != "1" }.allSatisfy {
        oneDX < runtime[$0]!.dx
      },
      "1 correction must be the largest-magnitude negative correction at \(fontSize)pt"
    )
  }
}
// Perceived optical centering is the alpha-weighted visual mass. The binary
// outline bbox remains a shape-integrity diagnostic because asymmetric glyph
// extrema can never share the same center as their weighted mass.
@Test
func hudGlyphRasterImagesKeepWeightedMassCenteredAndBoundShapeBbox() {
  let labels = ["A", "1", "2", "3", "4", "D", "R", "E"]
  let layoutScales: [Double] = [0.8, 1.0, 1.35, 1.6]
  let backingScales: [Double] = [1.0, 2.0]

  for layoutScale in layoutScales {
    let controlSize = HUDQuickSwitcherLayout.controlDiameter(
      for: layoutScale,
      style: .vertical
    )
    let controlFontSize =
      12 * controlSize / HUDQuickSwitcherLayout.controlButtonDiameter
    let promptSize = HUDQuickSwitcherLayout.promptSlotButtonSize(for: layoutScale)
    let promptFontSize = HUDQuickSwitcherLayout.promptSlotGlyphFontSize(for: layoutScale)
    for (fontSize, frameSize) in [
      (controlFontSize, controlSize),
      (promptFontSize, promptSize)
    ] {
      for label in labels {
        for backingScale in backingScales {
          let image = HUDQuickSwitcherLayout.glyphRasterImage(
            for: label,
            fontSize: fontSize,
            frameLogicalSize: HUDOverlaySize(width: frameSize, height: frameSize),
            backingScale: backingScale
          )
          guard let image else {
            #expect(Bool(false), "\(label) raster image must be generated")
            continue
          }
          #expect(
            image.width == Int((frameSize * backingScale).rounded()),
            "\(label) raster width must stay at 1:1 logical size"
          )
          for threshold in [UInt8(16), 51, 102, 153] {
            guard let residual = measuredGlyphImageResidual(
              image,
              backingScale: backingScale,
              alphaThreshold: threshold
            ) else {
              #expect(Bool(false), "\(label) raster threshold \(threshold) must find ink")
              continue
            }
            #expect(
              abs(residual.dx) <= 2.0,
              "\(label) \(fontSize)pt \(backingScale)x shape-bbox X diagnostic \(residual.dx)px exceeds 2px"
            )
            #expect(
              abs(residual.dy) <= 2.0,
              "\(label) \(fontSize)pt \(backingScale)x shape-bbox Y diagnostic \(residual.dy)px exceeds 2px"
            )
          }
          guard let weighted = measuredGlyphImageWeightedResidual(
            image,
            backingScale: backingScale
          ) else {
            #expect(Bool(false), "\(label) raster weighted scan must find ink")
            continue
          }
          #expect(
            abs(weighted.dx) <= 0.5,
            "\(label) \(fontSize)pt \(backingScale)x weighted X residual \(weighted.dx)px exceeds 0.5px"
          )
          #expect(
            abs(weighted.dy) <= 0.5,
            "\(label) \(fontSize)pt \(backingScale)x weighted Y residual \(weighted.dy)px exceeds 0.5px"
          )
        }
      }
    }
  }

  #expect(
    HUDQuickSwitcherLayout.glyphRasterImage(
      for: "2",
      fontSize: 11,
      frameLogicalSize: HUDOverlaySize(width: 17, height: 17),
      backingScale: 2,
      forceFallback: true
    ) == nil,
    "forced fallback seam must bypass raster image generation"
  )
}

@Test
func hudHorizontalControlHitFramesPreserveLegacyValuesAcrossScalesAndAccessories() {
  let scales: [Double] = [0.8, 1.0, 1.35, 1.6]
  let styles: [OverlayHUDStyle] = [.capsule, .tech]

  for scale in scales {
    for style in styles {
      for showsPromptBar in [false, true] {
        for showsHumorSlider in [false, true] {
          let panelSize = HUDQuickSwitcherLayout.overlayPanelSize(
            for: scale,
            style: style,
            isProcessing: false,
            showsPromptBar: showsPromptBar,
            showsHumorSlider: showsHumorSlider
          )
          let visualScale = HUDQuickSwitcherLayout.overlayVisualScale(for: scale)
          let shadowInset = HUDQuickSwitcherLayout.overlayShadowPad * visualScale
          let pillSize = HUDQuickSwitcherLayout.overlayPanelSize(
            for: scale,
            style: style,
            isProcessing: false,
            showsPromptBar: false,
            showsHumorSlider: false
          )
          let pillOriginX = (panelSize.width - pillSize.width) / 2
          let humorOffset = showsHumorSlider ? 4 * visualScale + 24 * visualScale : 0
          let pillBottom = shadowInset + humorOffset
          let diameter = HUDQuickSwitcherLayout.controlDiameter(for: scale, style: style)
          let expectedLanguage = HUDOverlayFrame(
            x: pillOriginX - 4 * visualScale,
            y: pillBottom - 4 * visualScale,
            width: diameter + 12 * visualScale,
            height: diameter + 8 * visualScale
          )
          let targetX = pillOriginX + pillSize.width - diameter - shadowInset
          let expectedTarget = HUDOverlayFrame(
            x: targetX - 4 * visualScale,
            y: pillBottom - 4 * visualScale,
            width: diameter + 12 * visualScale,
            height: diameter + 8 * visualScale
          )

          for (slot, expected) in [
            (HUDVerticalControlSlot.language, expectedLanguage),
            (.target, expectedTarget),
          ] {
            let actual = HUDQuickSwitcherLayout.controlHitFrame(
              slot: slot,
              panelSize: panelSize,
              scale: scale,
              style: style,
              isProcessing: false,
              showsPromptBar: showsPromptBar,
              showsHumorSlider: showsHumorSlider
            )
            #expect(abs(actual.x - expected.x) < 1e-9, "\(style) \(scale) \(slot) hit X changed")
            #expect(abs(actual.y - expected.y) < 1e-9, "\(style) \(scale) \(slot) hit Y changed")
            #expect(abs(actual.width - expected.width) < 1e-9, "\(style) \(scale) \(slot) hit width changed")
            #expect(abs(actual.height - expected.height) < 1e-9, "\(style) \(scale) \(slot) hit height changed")
          }
        }
      }
    }
  }
}

@Test
func hudOverlayManagerConsumesSharedCenteringPolicyAndForbidsManualGeometry() throws {
  let overlay = try String(
    contentsOfFile: "Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift",
    encoding: .utf8
  )
  let layout = try String(
    contentsOfFile: "Sources/NativeBolabolCore/Services/HUDQuickSwitcherLayout.swift",
    encoding: .utf8
  )

  let controlButtonStart = try #require(overlay.range(of: "private func controlButton("))
  let controlButtonEnd = try #require(
    overlay.range(of: "private var controlShape", range: controlButtonStart.lowerBound..<overlay.endIndex)
  )
  let controlButtonSource = overlay[controlButtonStart.lowerBound..<controlButtonEnd.lowerBound]
  #expect(!controlButtonSource.contains("xOffset"), "controlButton must not contain manual xOffset")
  #expect(!controlButtonSource.contains("yOffset"), "controlButton must not contain manual yOffset")
  #expect(!controlButtonSource.contains(".offset("), "controlButton must not apply manual text offset")
  #expect(!controlButtonSource.contains(".monospacedDigit()"), "controlButton must not use tabular monospacedDigit")
  #expect(!controlButtonSource.contains("design: state.style == .vertical ? .monospaced : .rounded"), "vertical style must not drift")
  #expect(controlButtonSource.contains("design: .rounded"), "controlButton must use consistent .rounded design")

  let controlSlotStart = try #require(overlay.range(of: "private func controlSlot("))
  let controlSlotEnd = try #require(
    overlay.range(of: "private func controlButton(", range: controlSlotStart.lowerBound..<overlay.endIndex)
  )
  let controlSlotSource = overlay[controlSlotStart.lowerBound..<controlSlotEnd.lowerBound]
  for policyCall in [
    "HUDQuickSwitcherLayout.controlFrame(",
    "HUDQuickSwitcherLayout.controlGlyphCenter(",
    "HUDQuickSwitcherLayout.controlGlyphLocalCenter(",
  ] {
    #expect(controlSlotSource.contains(policyCall), "controlSlot must consume \(policyCall)")
  }
  #expect(controlSlotSource.contains(".accessibilityLabel(Text(label))"), "controlSlot buttons must preserve their VoiceOver label")

  let hitStart = try #require(overlay.range(of: "private func languageControlHitRect()"))
  let hitEnd = try #require(
    overlay.range(of: "private func promptBarHitRect()", range: hitStart.lowerBound..<overlay.endIndex)
  )
  let hitSource = overlay[hitStart.lowerBound..<hitEnd.lowerBound]
  #expect(hitSource.contains("HUDQuickSwitcherLayout.controlHitFrame("), "AppKit hit rects must consume controlHitFrame")
  for forbidden in [
    "pillOriginX - 4 * visualScale",
    "targetX - 4 * visualScale",
    "controlDiameter + 12 * visualScale",
    "controlDiameter + 8 * visualScale",
  ] {
    #expect(!hitSource.contains(forbidden), "AppKit hit formula leaked into manager: \(forbidden)")
  }

  let promptStart = try #require(overlay.range(of: "private func promptSlotButton("))
  let promptEnd = try #require(
    overlay.range(of: "private var showsPillChrome", range: promptStart.lowerBound..<overlay.endIndex)
  )
  let promptSource = overlay[promptStart.lowerBound..<promptEnd.lowerBound]
  for policyCall in [
    "HUDQuickSwitcherLayout.promptSlotButtonSize(",
    "HUDQuickSwitcherLayout.promptSlotGlyphLocalCenter(",
    "HUDQuickSwitcherLayout.promptSlotGlyphFontSize(",
  ] {
    #expect(promptSource.contains(policyCall), "promptSlotButton must consume \(policyCall)")
  }
  #expect(!promptSource.contains("17 * visualScale"), "prompt button frame must not hardcode 17 * visualScale")
  #expect(!promptSource.contains("11 * visualScale"), "prompt glyph font must not hardcode 11 * visualScale")

  for metadataModifier in [
    ".accessibilityLabel(Text(accessibility.label))",
    ".accessibilityValue(Text(accessibility.value))",
    ".accessibilityHint(Text(accessibility.hint))",
  ] {
    #expect(promptSource.contains(metadataModifier), "prompt buttons must preserve \(metadataModifier)")
  }

  let railStart = try #require(overlay.range(of: "private var promptBar"))
  let railEnd = try #require(
    overlay.range(of: "private func promptSlotButton(", range: railStart.lowerBound..<overlay.endIndex)
  )
  let railSource = overlay[railStart.lowerBound..<railEnd.lowerBound]
  #expect(railSource.contains("HUDQuickSwitcherLayout.promptSlotSpacing("), "prompt rails must consume shared spacing policy")
  #expect(!railSource.contains("HStack(spacing: 3 * visualScale)"), "horizontal rail spacing must not be manual")
  #expect(!railSource.contains("VStack(spacing: 3 * visualScale)"), "vertical rail spacing must not be manual")

  #expect(!overlay.contains("HUDQuickSwitcherLayout.controlGlyphManualOffset("), "deleted zero-offset API must not be consumed")
  #expect(overlay.contains("@Environment(\\.displayScale)"), "production HUD must read the live display scale")
  #expect(controlButtonSource.contains("HUDQuickSwitcherLayout.glyphRasterImage("), "circle labels must use cached raster glyph images")
  #expect(controlButtonSource.contains("Image("), "circle labels must render a SwiftUI image")
  #expect(controlButtonSource.contains(".accessibilityHidden(true)"), "raster glyph images must remain decorative")
  #expect(promptSource.contains("HUDQuickSwitcherLayout.glyphRasterImage("), "prompt labels must use cached raster glyph images")
  #expect(promptSource.contains("Image("), "prompt labels must render a SwiftUI image")
  #expect(promptSource.contains("backingScale: Double(displayScale)"), "prompt labels must pass the live display scale")
  #expect(layout.contains("glyphOutlineCorrection"), "vector outline correction helper must remain in policy")
  #expect(layout.contains("glyphRasterImage"), "cached raster image helper must remain in policy")
  #expect(layout.contains("CTFontGetBoundingRectsForGlyphs"), "policy must measure true glyph outlines at runtime")
  #expect(layout.contains("CTFontGetAdvancesForGlyphs"), "policy must measure glyph advances at runtime")
  #expect(layout.contains("CTFontCreateWithFontDescriptor"), "policy must create the rounded CTFont descriptor directly")
  #expect(layout.contains("glyphsBase"), "outline bounds must use resolved glyphs")
}

