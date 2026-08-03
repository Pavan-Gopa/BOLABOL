import Foundation

/// Builds the ordered provider list for the floating HUD quick switcher.
///
/// Contract (mirrors production ContentView):
/// 1. Always start with Local.AI (`localEngineID`).
/// 2. Append cloud providers from `APIProviderSettings.availablePolishingProviders`.
/// 3. De-duplicate by engine id **or** display name (prevents e.g. two "Qwen" rows).
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
        id: $0.kind.polishingEngineID,
        displayName: $0.displayName
      )
    }

    for provider in cloudProviders {
      if !providers.contains(where: {
        $0.id == provider.id || $0.displayName == provider.displayName
      }) {
        providers.append(provider)
      }
    }

    return providers
  }
}
