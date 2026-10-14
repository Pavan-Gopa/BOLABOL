/// A lightweight, UI-agnostic description of a selectable polishing model.
///
/// Shared between the note detail view, the HUD provider/model quick switcher
/// and unit tests so that all surfaces present identical model choices.
public struct PolishingModelOption: Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  public let displayName: String

  public init(id: String, displayName: String) {
    self.id = id
    self.displayName = displayName
  }
}

/// Builds the list of selectable polishing models for a cloud provider.
///
/// The logic is pure (no `UserDefaults`, no UI, no localization) so it can be
/// shared and unit tested. Favorite model identifiers are supplied by the
/// caller (for example from `FavoriteModelsStore.loadFavorites(engineID:defaults:)`),
/// keeping persistence concerns out of this type.
public struct PolishingModelOptionsProvider: Sendable {
  public var apiSettings: APIProviderSettings

  public init(apiSettings: APIProviderSettings) {
    self.apiSettings = apiSettings
  }

  /// Instance-aware variant of `providerModelOptions(for:favorites:)` keyed
  /// by engine ID (ADR-031). Custom engine IDs resolve to their own
  /// configuration; anything else behaves exactly like the kind-based path.
  /// Returns [] when the engine ID is unknown or its instance is gone.
  public func providerModelOptions(
    forEngineID engineID: String,
    favorites: Set<String>
  ) -> [PolishingModelOption] {
    guard let (kind, config) = configurationForEngineID(engineID) else { return [] }
    return providerModelOptions(
      for: kind, favorites: favorites, configuration: config)
  }

  /// The ordered, de-duplicated model options to present for `kind`.
  ///
  /// Behavior (mirrors the historical note/translation UIs):
  /// 1. Start from the provider's built-in `availableModels` that are favorited.
  /// 2. Append any other favorite ids that heuristically belong to `kind`.
  /// 3. If nothing is favorited for `kind`, fall back to the full built-in list.
  /// 4. Ensure the provider's currently configured model is present (inserted
  ///    first when missing).
  /// 5. De-duplicate by cleaned, lower-cased display name.
  public func providerModelOptions(
    for kind: APIProviderKind,
    favorites: Set<String>
  ) -> [PolishingModelOption] {
    providerModelOptions(
      for: kind, favorites: favorites, configuration: apiSettings.configuration(for: kind))
  }

  private func providerModelOptions(
    for kind: APIProviderKind,
    favorites: Set<String>,
    configuration: APIProviderConfiguration
  ) -> [PolishingModelOption] {
    let baseOptions = availableModels(for: kind, configuration: configuration)
    var result = baseOptions.filter { favorites.contains($0.id) }

    for id in favorites {
      if !result.contains(where: { $0.id == id }) && matchesProvider(modelID: id, kind: kind) {
        result.append(PolishingModelOption(id: id, displayName: modelDisplayName(id: id, kind: kind)))
      }
    }

    if result.isEmpty {
      result = baseOptions
    }

    let currentID = configuration.textModel
    if !currentID.isEmpty
      && !result.contains(where: { $0.id == currentID })
      && matchesProvider(modelID: currentID, kind: kind) {
      result.insert(
        PolishingModelOption(id: currentID, displayName: modelDisplayName(id: currentID, kind: kind)),
        at: 0)
    }

    var seenKeys = Set<String>()
    var deduplicated: [PolishingModelOption] = []
    for option in result {
      let cleanName = cleanModelDisplayName(option.displayName)
      let key = cleanName.lowercased()
      if !seenKeys.contains(key) {
        seenKeys.insert(key)
        deduplicated.append(PolishingModelOption(id: option.id, displayName: cleanName))
      }
    }
    return deduplicated
  }

  /// Built-in, curated model suggestions per provider, parameterized by the
  /// live configuration so custom engine IDs use their own model.
  private func availableModels(
    for kind: APIProviderKind,
    configuration: APIProviderConfiguration
  ) -> [PolishingModelOption] {
    if kind == .custom {
      return [
        PolishingModelOption(
          id: configuration.textModel,
          displayName: cleanModelDisplayName(configuration.textModel))
      ]
    }
    return availableModels(for: kind)
  }

  /// Built-in, curated model suggestions per provider.
  public func availableModels(for kind: APIProviderKind) -> [PolishingModelOption] {
    switch kind {
    case .google:
      return [
        PolishingModelOption(id: "gemini-3.5-flash", displayName: "Gemini 3.5 Flash"),
        PolishingModelOption(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash"),
        PolishingModelOption(id: "gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash Lite"),
        PolishingModelOption(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro"),
        PolishingModelOption(id: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash")
      ]
    case .openAI:
      return [
        PolishingModelOption(id: "gpt-4o-mini", displayName: "GPT-4o Mini"),
        PolishingModelOption(id: "gpt-4o", displayName: "GPT-4o"),
        PolishingModelOption(id: "o3-mini", displayName: "o3-mini"),
        PolishingModelOption(id: "gpt-4-turbo", displayName: "GPT-4 Turbo")
      ]
    case .qwen:
      return [
        PolishingModelOption(id: "qwen3.6-flash", displayName: "Qwen 3.6 Flash"),
        PolishingModelOption(id: "qwen3.7-plus", displayName: "Qwen 3.7 Plus"),
        PolishingModelOption(id: "qwen3.8-max-preview", displayName: "Qwen 3.8 Max"),
        PolishingModelOption(id: "qwen-turbo", displayName: "Qwen Turbo"),
        PolishingModelOption(id: "qwen-max", displayName: "Qwen Max")
      ]
    case .openRouter:
      return [
        PolishingModelOption(id: "google/gemini-3.5-flash", displayName: "Gemini 3.5 Flash"),
        PolishingModelOption(id: "deepseek/deepseek-v4-flash", displayName: "DeepSeek V4 Flash"),
        PolishingModelOption(id: "qwen/qwen3.6-flash", displayName: "Qwen 3.6 Flash"),
        PolishingModelOption(id: "openai/gpt-4o-mini", displayName: "GPT-4o Mini"),
        PolishingModelOption(id: "anthropic/claude-3.5-haiku", displayName: "Claude 3.5 Haiku"),
        PolishingModelOption(id: "google/gemini-2.5-flash", displayName: "Gemini 2.5 Flash"),
        PolishingModelOption(id: "deepseek/deepseek-chat", displayName: "DeepSeek V3")
      ]
    case .custom:
      let current = apiSettings.configuration(for: .custom).textModel
      return [PolishingModelOption(id: current, displayName: cleanModelDisplayName(current))]
    case .anthropic:
      return [
        PolishingModelOption(id: "claude-3-5-haiku-latest", displayName: "Claude 3.5 Haiku"),
        PolishingModelOption(id: "claude-3-5-sonnet-latest", displayName: "Claude 3.5 Sonnet")
      ]
    }
  }
  /// Instance-aware variant of `availableModels(for:)` keyed by engine ID
  /// (ADR-031). Custom engine IDs resolve to their own configured model.
  /// Returns [] when the engine ID is unknown or its instance is gone.
  public func availableModels(forEngineID engineID: String) -> [PolishingModelOption] {
    guard let (kind, config) = configurationForEngineID(engineID) else { return [] }
    if kind == .custom {
      return [
        PolishingModelOption(
          id: config.textModel, displayName: cleanModelDisplayName(config.textModel))
      ]
    }
    return availableModels(for: kind)
  }


  /// Heuristic mapping of a raw model identifier to a provider kind. Used to
  /// decide whether a globally-stored favorite belongs to a given provider.
  public func matchesProvider(modelID: String, kind: APIProviderKind) -> Bool {
    let lower = modelID.lowercased()
    if kind != .openRouter && kind != .custom && lower.contains("/") {
      return false
    }
    switch kind {
    case .google:
      return lower.contains("gemini") || lower.contains("gemma") || lower.contains("google")
        || lower.contains("lyra")
    case .openAI:
      return lower.contains("gpt") || lower.contains("o3") || lower.contains("o1")
        || lower.contains("openai")
    case .qwen:
      return lower.contains("qwen") || lower.contains("deepseek") || lower.contains("glm")
    case .openRouter:
      return lower.contains("/")
    case .anthropic:
      return lower.contains("claude") || lower.contains("anthropic")
    case .custom:
      return true
    }
  }

  /// Display name for a model id within a provider. Returns an empty string
  /// when `id` is empty so callers can apply their own localized fallback.
  public func modelDisplayName(id: String, kind: APIProviderKind) -> String {
    let available = availableModels(for: kind)
    if let match = available.first(where: { $0.id == id }) {
      return cleanModelDisplayName(match.displayName)
    }
    return cleanModelDisplayName(id)
  }
  /// Instance-aware variant of `modelDisplayName(id:kind:)` keyed by engine
  /// ID (ADR-031).
  public func modelDisplayName(id: String, engineID: String) -> String {
    let available = availableModels(forEngineID: engineID)
    if let match = available.first(where: { $0.id == id }) {
      return cleanModelDisplayName(match.displayName)
    }
    return cleanModelDisplayName(id)
  }


  /// Strips a leading `vendor/` prefix (e.g. `google/gemini-2.5-flash` →
  /// `gemini-2.5-flash`).
  public func cleanModelDisplayName(_ raw: String) -> String {
    var name = raw
    if let slashIndex = name.firstIndex(of: "/") {
      name = String(name[name.index(after: slashIndex)...])
    }
    return name
  }
  /// Resolves an engine ID to its kind and live configuration for the model
  /// menus. Nil when the engine ID is unknown or its custom instance is gone.
  public func configurationForEngineID(_ engineID: String) -> (
    kind: APIProviderKind, configuration: APIProviderConfiguration
  )? {
    guard let resolved = apiSettings.resolve(engineID: engineID) else { return nil }
    guard let config = apiSettings.configuration(forEngineID: engineID) else { return nil }
    return (resolved.kind, config)
  }
}
