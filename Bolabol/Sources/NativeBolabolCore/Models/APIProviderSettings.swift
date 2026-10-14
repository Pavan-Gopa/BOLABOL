import Foundation

public enum APIProviderKind: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
  case google
  case openAI
  case anthropic  // kept for migration of stored settings; hidden in UI
  case qwen
  case openRouter
  case custom

  public var id: String { rawValue }

  /// Providers shown in Settings > API Providers (fixed order).
  /// Google → OpenAI → Qwen → OpenRouter → Custom.
  public static let polishingUICases: [APIProviderKind] = [.google, .openAI, .qwen, .openRouter, .custom]

  public var displayName: String {
    switch self {
    case .google: "Google"
    case .openAI: "OpenAI"
    case .anthropic: "Anthropic"
    case .qwen: "Qwen"
    case .openRouter: "OpenRouter"
    case .custom: "Custom"
    }
  }

  public var polishingEngineID: String {
    switch self {
    case .google: "cloud-google"
    case .openAI: "cloud-openai"
    case .anthropic: "cloud-anthropic"
    case .qwen: "cloud-qwen"
    case .openRouter: "cloud-openrouter"
    case .custom: "cloud-custom"
    }
  }

  public var getAPIKeyURL: URL? {
    switch self {
    case .google: URL(string: "https://aistudio.google.com/app/apikey")
    case .openAI: URL(string: "https://platform.openai.com/api-keys")
    case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
    case .qwen: URL(string: "https://modelstudio.console.alibabacloud.com/")
    case .openRouter: URL(string: "https://openrouter.ai/keys")
    case .custom: nil
    }
  }

  public var defaultTextModel: String {
    switch self {
    case .google: "gemini-3.5-flash"
    case .openAI: "gpt-4o-mini"
    case .anthropic: "claude-3-haiku-20240307"
    case .qwen: "qwen3.7-plus"
    case .openRouter: "openai/gpt-4o-mini"
    case .custom: ""
    }
  }

  public var defaultBaseURL: String {
    switch self {
    case .openAI: "https://api.openai.com/v1"
    case .qwen: "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
    case .openRouter: "https://openrouter.ai/api/v1"
    case .custom: ""
    case .google, .anthropic: ""
    }
  }

  public var supportsBalance: Bool {
    self == .openRouter
  }

  public var supportsPricing: Bool {
    self == .openRouter
  }

  /// OpenAI-compatible chat providers that use baseURL + Bearer auth.
  public var isOpenAICompatible: Bool {
    switch self {
    case .openAI, .qwen, .openRouter, .custom: true
    case .google, .anthropic: false
    }
  }

  public init?(polishingEngineID: String) {
    guard let kind = Self.allCases.first(where: { $0.polishingEngineID == polishingEngineID })
    else {
      return nil
    }
    self = kind
  }
}

public struct APIProviderConfiguration: Codable, Equatable, Sendable {
  public static let disabledPrefix = "#DISABLED#"

  public var apiKeys: [String]
  public var textModel: String
  public var baseURL: String
  public var name: String

  public init(
    apiKeys: [String] = [],
    apiKey: String = "",
    textModel: String = "",
    baseURL: String = "",
    name: String = ""
  ) {
    if !apiKeys.isEmpty {
      self.apiKeys = apiKeys
    } else if !apiKey.isEmpty {
      self.apiKeys = [apiKey]
    } else {
      self.apiKeys = []
    }
    self.textModel = textModel
    self.baseURL = baseURL
    self.name = name
  }

  /// Backwards-compatible primary key getter/setter.
  public var apiKey: String {
    get {
      sanitizedAPIKeys.first ?? cleanKey(apiKeys.first ?? "")
    }
    set {
      let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
      if apiKeys.isEmpty {
        if !trimmed.isEmpty {
          apiKeys = [newValue]
        }
      } else {
        let disabled = isKeyDisabled(at: 0)
        let clean = cleanKey(trimmed)
        apiKeys[0] = disabled ? "\(Self.disabledPrefix)\(clean)" : clean
      }
    }
  }

  /// Helper to get clean key value without #DISABLED# prefix
  public func cleanKey(at index: Int) -> String {
    guard apiKeys.indices.contains(index) else { return "" }
    return cleanKey(apiKeys[index])
  }

  public func cleanKey(_ raw: String) -> String {
    var key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if key.hasPrefix(Self.disabledPrefix) {
      key = String(key.dropFirst(Self.disabledPrefix.count))
    }
    return key
  }

  /// Check if key at index is disabled
  public func isKeyDisabled(at index: Int) -> Bool {
    guard apiKeys.indices.contains(index) else { return false }
    return apiKeys[index].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(
      Self.disabledPrefix)
  }

  /// Toggle disabled state of key at index
  public mutating func toggleKeyDisabled(at index: Int) {
    guard apiKeys.indices.contains(index) else { return }
    let current = apiKeys[index].trimmingCharacters(in: .whitespacesAndNewlines)
    if current.hasPrefix(Self.disabledPrefix) {
      apiKeys[index] = String(current.dropFirst(Self.disabledPrefix.count))
    } else {
      apiKeys[index] = "\(Self.disabledPrefix)\(current)"
    }
  }

  /// Enable all keys
  public mutating func enableAllKeys() {
    apiKeys = apiKeys.map { cleanKey($0) }
  }

  /// Disable all keys except at specific index
  public mutating func disableAllKeysExcept(at targetIndex: Int) {
    for i in apiKeys.indices {
      let clean = cleanKey(apiKeys[i])
      if i == targetIndex {
        apiKeys[i] = clean
      } else {
        apiKeys[i] = "\(Self.disabledPrefix)\(clean)"
      }
    }
  }

  /// All trimmed, non-empty, ENABLED ASCII valid API keys.
  public var sanitizedAPIKeys: [String] {
    apiKeys
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && !$0.hasPrefix(Self.disabledPrefix) && !$0.hasPrefix("disabled:") }
  }

  public var hasAPIKey: Bool {
    !sanitizedAPIKeys.isEmpty
  }

  /// Number of non-empty keys already stored for this provider, including
  /// temporarily disabled keys. Useful for setup UI that should not ask the
  /// user to configure credentials they have already added.
  public var configuredAPIKeyCount: Int {
    apiKeys
      .map(cleanKey)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .count
  }

  public mutating func addKey(_ key: String = "") {
    guard apiKeys.count < 10 else { return }
    apiKeys.append(key)
  }

  public mutating func removeKey(at index: Int) {
    guard apiKeys.indices.contains(index) else { return }
    apiKeys.remove(at: index)
  }

  public mutating func updateKey(_ key: String, at index: Int) {
    guard apiKeys.indices.contains(index) else { return }
    let disabled = isKeyDisabled(at: index)
    let clean = cleanKey(key)
    apiKeys[index] = disabled ? "\(Self.disabledPrefix)\(clean)" : clean
  }

  private enum CodingKeys: String, CodingKey {
    case apiKeys, apiKey, textModel, baseURL, name
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    textModel = try container.decodeIfPresent(String.self, forKey: .textModel) ?? ""
    baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""

    if let keys = try container.decodeIfPresent([String].self, forKey: .apiKeys), !keys.isEmpty {
      apiKeys = keys
    } else if let singleKey = try container.decodeIfPresent(String.self, forKey: .apiKey),
      !singleKey.isEmpty
    {
      apiKeys = [singleKey]
    } else {
      apiKeys = []
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(apiKeys, forKey: .apiKeys)
    try container.encode(apiKey, forKey: .apiKey)
    try container.encode(textModel, forKey: .textModel)
    try container.encode(baseURL, forKey: .baseURL)
    try container.encode(name, forKey: .name)
  }
}

public struct AvailableAPIProvider: Codable, Equatable, Sendable {
  public var kind: APIProviderKind
  public var displayName: String
  public var modelName: String
  /// Stable engine identity. Built-ins use `kind.polishingEngineID`; each
  /// custom instance uses its own `cloud-custom` / `cloud-custom-<id>`
  /// (ADR-031), so several instances can appear side by side.
  public var engineID: String

  public init(
    kind: APIProviderKind,
    displayName: String,
    modelName: String,
    engineID: String? = nil
  ) {
    self.kind = kind
    self.displayName = displayName
    self.modelName = modelName
    self.engineID = engineID ?? kind.polishingEngineID
  }

  private enum CodingKeys: String, CodingKey {
    case kind, displayName, modelName, engineID
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    kind = try container.decode(APIProviderKind.self, forKey: .kind)
    displayName = try container.decode(String.self, forKey: .displayName)
    modelName = try container.decode(String.self, forKey: .modelName)
    engineID =
      try container.decodeIfPresent(String.self, forKey: .engineID) ?? kind.polishingEngineID
  }
}

/// One named OpenAI-compatible custom provider instance (ADR-031).
///
/// `APIProviderKind.custom` stays the behaviour kind (request policy, model
/// catalog, URL building); this type carries the per-instance identity: a
/// stable string id, the configuration (whose `name` is the display name),
/// the engine ID and the keychain account. The migrated legacy provider keeps
/// engine ID `cloud-custom` and account `api-provider.custom.keys`; new
/// instances use `cloud-custom-<uuid>` and `api-provider.custom.<uuid>.keys`.
public struct CustomAPIProviderInstance: Codable, Equatable, Sendable, Identifiable {
  public static let legacyInstanceID = "legacy"
  public static let legacyEngineID = "cloud-custom"
  private static let engineIDPrefix = "cloud-custom-"

  public var id: String
  public var configuration: APIProviderConfiguration

  public init(
    id: String = legacyInstanceID,
    configuration: APIProviderConfiguration = APIProviderConfiguration()
  ) {
    self.id = id
    self.configuration = configuration
  }

  public static func engineID(forInstanceID id: String) -> String {
    id == legacyInstanceID ? legacyEngineID : "\(engineIDPrefix)\(id)"
  }

  public static func keychainAccount(forInstanceID id: String) -> String {
    id == legacyInstanceID ? "api-provider.custom.keys" : "api-provider.custom.\(id).keys"
  }

  /// Maps an engine ID back to a custom instance id (`nil` when not a custom
  /// engine ID). Structural only — the instance may not exist (anymore).
  public static func instanceID(forEngineID engineID: String) -> String? {
    if engineID == legacyEngineID { return legacyInstanceID }
    guard engineID.hasPrefix(engineIDPrefix) else { return nil }
    let suffix = String(engineID.dropFirst(engineIDPrefix.count))
    return suffix.isEmpty ? nil : suffix
  }

  public var engineID: String { Self.engineID(forInstanceID: id) }
  public var keychainAccount: String { Self.keychainAccount(forInstanceID: id) }

  public var displayName: String {
    let trimmed = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? APIProviderKind.custom.displayName : trimmed
  }
}

/// Structural resolution of a stored engine ID (ADR-031): the behaviour kind
/// plus, for custom providers, the instance id. Availability (keys, model,
/// base URL) is checked separately against the resolved configuration.
public struct ResolvedAPIProvider: Equatable, Sendable {
  public var kind: APIProviderKind
  public var customInstanceID: String?

  public init(kind: APIProviderKind, customInstanceID: String? = nil) {
    self.kind = kind
    self.customInstanceID = customInstanceID
  }
}

/// One remote model offered by a provider (with optional OpenRouter-style pricing).
public struct CloudRemoteModel: Codable, Equatable, Sendable, Identifiable, Hashable {
  public var id: String
  /// Context window size in tokens, when known.
  public var contextLength: Int?
  /// USD per 1M prompt tokens, when known.
  public var promptPricePer1M: Double?
  /// USD per 1M completion tokens, when known.
  public var completionPricePer1M: Double?

  public init(
    id: String,
    contextLength: Int? = nil,
    promptPricePer1M: Double? = nil,
    completionPricePer1M: Double? = nil
  ) {
    self.id = id
    self.contextLength = contextLength
    self.promptPricePer1M = promptPricePer1M
    self.completionPricePer1M = completionPricePer1M
  }

  public var priceLabel: String? {
    guard let prompt = promptPricePer1M, let completion = completionPricePer1M else {
      return nil
    }
    return String(format: "$%.2f / $%.2f per 1M", prompt, completion)
  }

  public var inputPriceLabel: String {
    guard let prompt = promptPricePer1M else { return "—" }
    return String(format: "$%.3f / 1M", prompt)
  }

  public var outputPriceLabel: String {
    guard let completion = completionPricePer1M else { return "—" }
    return String(format: "$%.3f / 1M", completion)
  }

  public var contextLabel: String {
    guard let contextLength, contextLength > 0 else { return "—" }
    if contextLength >= 1_000_000 {
      let m = Double(contextLength) / 1_000_000
      return String(format: "%.1fM", m)
    }
    if contextLength >= 1_000 {
      return "\(contextLength / 1_000)K"
    }
    return "\(contextLength)"
  }
}

public struct APIProviderSettings: Codable, Equatable, Sendable {
  public var google: APIProviderConfiguration
  public var openAI: APIProviderConfiguration
  public var anthropic: APIProviderConfiguration
  public var qwen: APIProviderConfiguration
  public var openRouter: APIProviderConfiguration
  /// Named custom provider instances (ADR-031). The first entry is the
  /// migrated legacy provider (`cloud-custom`).
  public var customProviders: [CustomAPIProviderInstance]

  /// Backwards-compatible alias for the first (migrated legacy) custom
  /// instance, so existing single-custom call sites keep working.
  public var custom: APIProviderConfiguration {
    get { customProviders.first?.configuration ?? APIProviderConfiguration() }
    set {
      if customProviders.isEmpty {
        customProviders = [CustomAPIProviderInstance(configuration: newValue)]
      } else {
        customProviders[0].configuration = newValue
      }
    }
  }

  public init(
    google: APIProviderConfiguration = APIProviderConfiguration(textModel: "gemini-3.5-flash"),
    openAI: APIProviderConfiguration = APIProviderConfiguration(textModel: "gpt-4o-mini"),
    anthropic: APIProviderConfiguration = APIProviderConfiguration(
      textModel: "claude-3-haiku-20240307"),
    qwen: APIProviderConfiguration = APIProviderConfiguration(
      textModel: "qwen3.7-plus",
      baseURL: "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
    ),
    openRouter: APIProviderConfiguration = APIProviderConfiguration(
      textModel: "openai/gpt-4o-mini",
      baseURL: "https://openrouter.ai/api/v1"
    ),
    custom: APIProviderConfiguration = APIProviderConfiguration(),
    customProviders: [CustomAPIProviderInstance]? = nil
  ) {
    self.google = google
    self.openAI = openAI
    self.anthropic = anthropic
    self.qwen = qwen
    self.openRouter = openRouter
    if let customProviders {
      self.customProviders = customProviders
    } else {
      self.customProviders = [CustomAPIProviderInstance(configuration: custom)]
    }
  }

  private enum CodingKeys: String, CodingKey {
    case google, openAI, anthropic, qwen, openRouter, custom, customProviders
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    google =
      try container.decodeIfPresent(APIProviderConfiguration.self, forKey: .google)
      ?? APIProviderConfiguration(textModel: "gemini-3.5-flash")
    openAI =
      try container.decodeIfPresent(APIProviderConfiguration.self, forKey: .openAI)
      ?? APIProviderConfiguration(textModel: "gpt-4o-mini")
    anthropic =
      try container.decodeIfPresent(APIProviderConfiguration.self, forKey: .anthropic)
      ?? APIProviderConfiguration(textModel: "claude-3-haiku-20240307")
    qwen =
      try container.decodeIfPresent(APIProviderConfiguration.self, forKey: .qwen)
      ?? APIProviderConfiguration(
        textModel: "qwen3.7-plus",
        baseURL: "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
      )
    openRouter =
      try container.decodeIfPresent(APIProviderConfiguration.self, forKey: .openRouter)
      ?? APIProviderConfiguration(
        textModel: "openai/gpt-4o-mini", baseURL: "https://openrouter.ai/api/v1")
    if let instances = try container.decodeIfPresent(
      [CustomAPIProviderInstance].self, forKey: .customProviders)
    {
      customProviders = instances
    } else {
      // Migration: legacy `custom` JSON becomes the first instance, keeping
      // base URL, model, name and keys.
      let legacy =
        try container.decodeIfPresent(APIProviderConfiguration.self, forKey: .custom)
        ?? APIProviderConfiguration()
      customProviders = [CustomAPIProviderInstance(configuration: legacy)]
    }

    if qwen.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      qwen.baseURL = APIProviderKind.qwen.defaultBaseURL
    }
    if openRouter.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      openRouter.baseURL = APIProviderKind.openRouter.defaultBaseURL
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(google, forKey: .google)
    try container.encode(openAI, forKey: .openAI)
    try container.encode(anthropic, forKey: .anthropic)
    try container.encode(qwen, forKey: .qwen)
    try container.encode(openRouter, forKey: .openRouter)
    // Downgrade: an older build decodes only `custom`, so it still sees one
    // custom provider (the first instance).
    try container.encode(custom, forKey: .custom)
    try container.encode(customProviders, forKey: .customProviders)
  }

  public var availablePolishingProviders: [AvailableAPIProvider] {
    var result: [AvailableAPIProvider] = []
    for kind in APIProviderKind.polishingUICases where kind != .custom {
      let config = configuration(for: kind)
      guard config.hasAPIKey else { continue }
      let model = config.textModel.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !model.isEmpty else { continue }
      result.append(
        AvailableAPIProvider(kind: kind, displayName: kind.displayName, modelName: model))
    }
    for instance in customProviders {
      let config = instance.configuration
      guard config.hasAPIKey else { continue }
      let model = config.textModel.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !model.isEmpty else { continue }
      let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !base.isEmpty else { continue }
      let entry = AvailableAPIProvider(
        kind: .custom,
        displayName: instance.displayName,
        modelName: model,
        engineID: instance.engineID
      )
      // De-duplicate by engine ID only, so several custom instances appear
      // side by side even when they share a display name.
      if !result.contains(where: { $0.engineID == entry.engineID }) {
        result.append(entry)
      }
    }
    return result
  }

  public func configuration(for kind: APIProviderKind) -> APIProviderConfiguration {
    switch kind {
    case .google: google
    case .openAI: openAI
    case .anthropic: anthropic
    case .qwen: qwen
    case .openRouter: openRouter
    case .custom: custom
    }
  }

  public mutating func setConfiguration(
    _ configuration: APIProviderConfiguration, for kind: APIProviderKind
  ) {
    switch kind {
    case .google: google = configuration
    case .openAI: openAI = configuration
    case .anthropic: anthropic = configuration
    case .qwen: qwen = configuration
    case .openRouter: openRouter = configuration
    case .custom: custom = configuration
    }
  }

  // MARK: - Custom instances (ADR-031)

  public func customInstance(id: String) -> CustomAPIProviderInstance? {
    customProviders.first(where: { $0.id == id })
  }

  public func customInstance(engineID: String) -> CustomAPIProviderInstance? {
    guard let id = CustomAPIProviderInstance.instanceID(forEngineID: engineID) else {
      return nil
    }
    return customInstance(id: id)
  }

  public func configuration(forCustomInstanceID id: String) -> APIProviderConfiguration? {
    customInstance(id: id)?.configuration
  }

  @discardableResult
  public mutating func setConfiguration(
    _ configuration: APIProviderConfiguration, forCustomInstanceID id: String
  ) -> Bool {
    guard let index = customProviders.firstIndex(where: { $0.id == id }) else { return false }
    customProviders[index].configuration = configuration
    return true
  }

  /// The single resolver from a stored engine ID to (kind, custom instance).
  /// `APIProviderKind(polishingEngineID:)` stays exact-match; this method
  /// additionally maps `cloud-custom-<id>` to (`.custom`, id). The resolution
  /// is structural — the instance may be missing (deleted), in which case
  /// configuration lookups return nil and availability checks fail.
  public func resolve(engineID: String) -> ResolvedAPIProvider? {
    if let kind = APIProviderKind(polishingEngineID: engineID) {
      if kind == .custom {
        return ResolvedAPIProvider(
          kind: .custom,
          customInstanceID: CustomAPIProviderInstance.legacyInstanceID)
      }
      return ResolvedAPIProvider(kind: kind)
    }
    if let instanceID = CustomAPIProviderInstance.instanceID(forEngineID: engineID) {
      return ResolvedAPIProvider(kind: .custom, customInstanceID: instanceID)
    }
    return nil
  }

  public func configuration(forEngineID engineID: String) -> APIProviderConfiguration? {
    guard let resolved = resolve(engineID: engineID) else { return nil }
    if resolved.kind == .custom {
      return resolved.customInstanceID.flatMap { configuration(forCustomInstanceID: $0) }
    }
    return configuration(for: resolved.kind)
  }

  @discardableResult
  public mutating func setConfiguration(
    _ configuration: APIProviderConfiguration, forEngineID engineID: String
  ) -> Bool {
    guard let resolved = resolve(engineID: engineID) else { return false }
    if resolved.kind == .custom {
      guard let id = resolved.customInstanceID else { return false }
      return setConfiguration(configuration, forCustomInstanceID: id)
    }
    setConfiguration(configuration, for: resolved.kind)
    return true
  }

  /// Display name for an engine ID: the instance name for custom providers,
  /// the kind name for built-ins, nil when the engine ID is unknown.
  public func displayName(forEngineID engineID: String) -> String? {
    guard let resolved = resolve(engineID: engineID) else { return nil }
    if resolved.kind == .custom {
      return resolved.customInstanceID.flatMap { customInstance(id: $0)?.displayName }
    }
    return resolved.kind.displayName
  }

  /// Whether a usage bucket key belongs to the custom instance named
  /// `displayName`. Buckets are keyed by backend name ("<DisplayName>
  /// <model>"), so the bucket must start with the display name plus a
  /// trailing space. When sibling instance names share a prefix ("Custom"
  /// vs "Custom 2"), a longer sibling name that is also a prefix of the
  /// bucket wins, so resetting one instance never resets a sibling's
  /// buckets.
  public func usageBucketMatchesCustomInstance(bucketKey: String, displayName: String) -> Bool {
    let bucket = bucketKey.lowercased()
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !name.isEmpty, bucket.hasPrefix(name + " ") else { return false }
    return !customProviders.contains {
      let other = $0.displayName.lowercased()
      return other.count > name.count && bucket.hasPrefix(other + " ")
    }
  }

  /// Names are required, trimmed and unique case-insensitively.
  public func isCustomNameTaken(_ name: String, excludingID: String? = nil) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    return customProviders.contains {
      $0.id != excludingID
        && $0.displayName.compare(trimmed, options: .caseInsensitive) == .orderedSame
    }
  }

  /// Default name for a new instance: localized "Custom N" with the smallest
  /// free N.
  public func defaultCustomName(language: UILanguagePreference) -> String {
    let format = AppText.localized(.customProviderDefaultName, language: language)
    var index = customProviders.count + 1
    // ponytail: linear probe; upgrade when custom instance counts grow large.
    while index < customProviders.count + 1000 {
      let candidate = String(format: format, index)
      if !isCustomNameTaken(candidate) { return candidate }
      index += 1
    }
    return String(format: format, customProviders.count + 1)
  }

  /// Appends a new instance with a fresh UUID id. An empty or taken name
  /// falls back to the default name, so this always succeeds.
  @discardableResult
  public mutating func addCustomProvider(
    name: String? = nil,
    language: UILanguagePreference = .english
  ) -> CustomAPIProviderInstance {
    let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let finalName = (!trimmed.isEmpty && !isCustomNameTaken(trimmed))
      ? trimmed : defaultCustomName(language: language)
    let instance = CustomAPIProviderInstance(
      id: UUID().uuidString,
      configuration: APIProviderConfiguration(name: finalName)
    )
    customProviders.append(instance)
    return instance
  }

  /// Removes the instance, returning it so the caller can delete its keychain
  /// item and repair selections pointing at its engine ID.
  @discardableResult
  public mutating func removeCustomProvider(id: String) -> CustomAPIProviderInstance? {
    guard let index = customProviders.firstIndex(where: { $0.id == id }) else { return nil }
    return customProviders.remove(at: index)
  }

  /// Renames the instance. Returns false (and changes nothing) when the name
  /// is blank or taken case-insensitively.
  @discardableResult
  public mutating func renameCustomProvider(id: String, name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isCustomNameTaken(trimmed, excludingID: id),
      let index = customProviders.firstIndex(where: { $0.id == id })
    else { return false }
    customProviders[index].configuration.name = trimmed
    return true
  }
}
