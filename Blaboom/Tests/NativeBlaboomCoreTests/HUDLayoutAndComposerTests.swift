import Foundation
import NativeBlaboomCore
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
