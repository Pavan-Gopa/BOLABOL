/// Builds the ordered provider list for the floating HUD quick switcher.
///
/// Contract (mirrors production ContentView):
/// 1. Always start with Local.AI (`localEngineID`).
/// 2. Append cloud providers from `APIProviderSettings.availablePolishingProviders`.
/// 3. De-duplicate by engine id only, so several named custom instances
///    (ADR-031) appear side by side even when they share a display name.
public enum HUDProviderListComposer {
  public static let defaultLocalEngineID = "mlx-swift-local-model"
  public static let defaultLocalDisplayName = "Local.AI"

  public static func providers(
    apiSettings: APIProviderSettings,
    localEngineID: String = defaultLocalEngineID,
    localDisplayName: String = defaultLocalDisplayName
  ) -> [ProviderQuickSwitcherModel.Provider] {
    var providers: [ProviderQuickSwitcherModel.Provider] = [
      .init(id: localEngineID, displayName: localDisplayName)
    ]

    let cloudProviders = apiSettings.availablePolishingProviders.map {
      ProviderQuickSwitcherModel.Provider(
        id: $0.engineID,
        displayName: $0.displayName
      )
    }

    for provider in cloudProviders {
      if !providers.contains(where: { $0.id == provider.id }) {
        providers.append(provider)
      }
    }

    return providers
  }
}
