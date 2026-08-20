import Foundation

// MARK: - ProviderRegistry (+ CloudChatRouter, A5)
//
// Role: single source of truth for which transcription/translation providers are
// selectable in the workflow UI, given the current AppSettings (keys, downloaded
// local models). A5 extends it with the Qwen / OpenRouter / Ollama Cloud options
// and with `CloudChatRouter` — a pure, core-level request-routing helper that the
// app-target engines delegate to. Routing lives here (not in the engines) so it is
// unit-testable from VaniScriptCoreTests without network or real keys (§14).

public enum ProviderGroup: String, Codable, Equatable, Sendable {
    case cloud
    case local
}

public enum ProviderKind: String, Codable, Equatable, Sendable {
    case transcription
    case translation
}

public struct ProviderOption: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var group: ProviderGroup
    public var kind: ProviderKind
    public var requiresKey: String?
}

public struct TranslationProviderAvailability: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var providers: [ProviderOption]
}


public enum ProviderRegistry {
    public static func cloudProviderCatalogID(for providerID: String) -> String? {
        let trimmed = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "gemini-cloud", "gemini":
            return CloudProviderCatalog.geminiID
        case "gpt-cloud", "openai", "gpt":
            return CloudProviderCatalog.openaiID
        case "anthropic", "claude":
            return CloudProviderCatalog.anthropicID
        case "qwen":
            return CloudProviderCatalog.qwenID
        case "openrouter":
            return CloudProviderCatalog.openrouterID
        case "ollama-cloud", "ollama":
            return CloudProviderCatalog.ollamaCloudID
        case "custom":
            return CloudProviderCatalog.customID
        default:
            if CloudProviderCatalog.providers.contains(where: { $0.id == trimmed }) {
                return trimmed
            }
            return nil
        }
    }
    public static func availableTranscriptionProviders(settings: AppSettings) -> [ProviderOption] {
        var providers: [ProviderOption] = []
        if settings.geminiKeyBank.hasEnabledKey {
            providers.append(
                ProviderOption(
                    id: "gemini-cloud",
                    label: "Gemini Cloud",
                    group: .cloud,
                    kind: .transcription,
                    requiresKey: "gemini"
                )
            )
        }
        if !settings.openaiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            providers.append(
                ProviderOption(
                    id: "gpt-cloud",
                    label: "GPT Cloud",
                    group: .cloud,
                    kind: .transcription,
                    requiresKey: "openai"
                )
            )
        }
        // A5: honest capability gating — new cloud providers (Qwen/OpenRouter/
        // Ollama Cloud) only appear here when the catalog says the provider really
        // supports audio transcription. Today all three are `false` (no verified
        // audio endpoint), so this loop adds nothing — but the gate is data-driven:
        // flipping `supportsTranscription` in CloudProviderCatalog is enough.
        for descriptor in CloudProviderCatalog.providers
        where CloudChatRouter.chatProviderIDs.contains(descriptor.id)
            && CloudChatRouter.apiKey(for: descriptor.id, settings: settings) != nil {
            let model = CloudChatRouter.route(providerID: descriptor.id, settings: settings, purpose: .transcription)?.model
            if CloudProviderCatalog.supportsTranscription(providerID: descriptor.id, modelID: model) {
                providers.append(
                    ProviderOption(
                        id: descriptor.id,
                        label: descriptor.label,
                        group: .cloud,
                        kind: .transcription,
                        requiresKey: descriptor.id
                    )
                )
            }
        }

        return providers + downloadedLocalProviders(models: settings.localAsrModels, kind: .transcription)
    }

    public static func availableTranslationProviders(
        settings: AppSettings,
        targetLang: String
    ) -> TranslationProviderAvailability {
        let isSame = targetLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "same"

        var providers: [ProviderOption] = []
        if settings.geminiKeyBank.hasEnabledKey {
            providers.append(
                ProviderOption(
                    id: "gemini-cloud",
                    label: "Gemini Cloud",
                    group: .cloud,
                    kind: .translation,
                    requiresKey: "gemini"
                )
            )
        }
        if !settings.openaiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            providers.append(
                ProviderOption(
                    id: "gpt-cloud",
                    label: "GPT Cloud",
                    group: .cloud,
                    kind: .translation,
                    requiresKey: "openai"
                )
            )
        }
        // A5: Qwen / OpenRouter / Ollama Cloud translation options — same pattern as
        // gemini/gpt above (key present ⇒ option shown). The option ids intentionally
        // equal the CloudProviderCatalog ids (`qwen` / `openrouter` / `ollama-cloud`)
        // so WorkflowStore's usage recording (§8, `providerId:model` keys) needs no
        // legacy remapping like `gemini-cloud`→`gemini`.
        for descriptor in CloudProviderCatalog.providers
        where CloudChatRouter.chatProviderIDs.contains(descriptor.id)
            && descriptor.capabilities.supportsTranslation
            && CloudChatRouter.apiKey(for: descriptor.id, settings: settings) != nil {
            providers.append(
                ProviderOption(
                    id: descriptor.id,
                    label: descriptor.label,
                    group: .cloud,
                    kind: .translation,
                    requiresKey: descriptor.id
                )
            )
        }

        providers += downloadedLocalProviders(models: settings.localTranslationModels, kind: .translation)
        return TranslationProviderAvailability(enabled: !isSame, providers: providers)
    }

    private static func downloadedLocalProviders(
        models: [String: LocalModelState],
        kind: ProviderKind
    ) -> [ProviderOption] {
        models
            .filter { id, state in
                guard state.status == .downloaded else { return false }
                switch kind {
                case .transcription:
                    guard let descriptor = NativeModelCatalog.descriptor(for: id),
                          state.runtime == descriptor.settingsRuntime,
                          descriptor.capabilities.isAvailable(
                              onMacOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
                          )
                    else {
                        return false
                    }
                    // Synthetic fixtures intentionally bypass path checks in tests;
                    // production listing only checks the persisted model reference.
                    if descriptor.backend == .whisperKitCoreML,
                       LocalModelVerification.skipVerificationForTesting {
                        return true
                    }
                    // Detached reconciliation owns full package/layout/hash validation;
                    // listing only checks the persisted model directory reference.
                    guard let path = state.path, !path.isEmpty else { return false }
                    var isDirectory = ObjCBool(false)
                    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                        && isDirectory.boolValue
                case .translation:
                    return state.runtime == .mlx
                        && LocalModelVerification.verifyTranslationModelPath(state.path, modelID: id)
                }
            }
            .map { id, state in
                ProviderOption(
                    id: id,
                    label: state.label,
                    group: .local,
                    kind: kind,
                    requiresKey: nil
                )
            }
            .sorted { $0.label < $1.label }
    }

    /// Calculate total spent for a provider based on accumulated token usage and pricing.
    public static func providerSpent(providerID: String, settings: AppSettings) -> Double {
        let prefix = "\(providerID):"
        var total: Double = 0
        for (key, stats) in settings.usage {
            if key == providerID || key.hasPrefix(prefix) {
                let input = stats.inputTokens
                let output = stats.outputTokens
                let audio = stats.audioMinutes

                let modelID: String = {
                    if let m = stats.lastModel, !m.isEmpty { return m }
                    let parts = key.split(separator: ":", maxSplits: 1)
                    return parts.count == 2 ? String(parts[1]) : ""
                }()

                let pricing = CloudProviderCatalog.modelPricingDetails(providerID: providerID, modelID: modelID)
                let promptPrice: Double = {
                    let s = pricing.inputCost.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: " / 1M", with: "")
                    return (Double(s) ?? 0.15) / 1_000_000.0
                }()
                let completionPrice: Double = {
                    let s = pricing.outputCost.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: " / 1M", with: "")
                    return (Double(s) ?? 0.60) / 1_000_000.0
                }()

                total += (Double(input) * promptPrice) + (Double(output) * completionPrice) + (audio * 0.005)
            }
        }
        return total
    }

    /// Evaluates whether spending for a cloud provider has reached or exceeded its budget limit.
    public static func isBudgetExceeded(providerID: String, settings: AppSettings) -> Bool {
        let budget: Double = {
            switch providerID {
            case CloudProviderCatalog.geminiID, "gemini-cloud": return settings.geminiBudgetUsd
            case CloudProviderCatalog.openaiID, "gpt-cloud": return settings.openaiBudgetUsd
            case CloudProviderCatalog.qwenID: return settings.qwenBudgetUsd
            case CloudProviderCatalog.openrouterID: return settings.openrouterBudgetUsd
            default:
                if let custom = settings.customCloudProviders.first(where: { $0.id == providerID }) {
                    return custom.budgetLimitUsd
                }
                return 0
            }
        }()

        guard budget > 0 else { return false }
        let spent = providerSpent(providerID: providerID, settings: settings)
        return spent >= budget
    }
}

// MARK: - CloudChatRouter (A5)

/// A5: fully resolved routing info for one OpenAI-compatible chat/completions call.
/// Pure data — engines copy `endpoint`/`headers` into the URLRequest they build.
/// The API key only ever appears inside the `Authorization` header value; it is
/// never logged or persisted here (invariant §14.3).
public struct CloudChatRoute: Equatable, Sendable {
    /// Catalog provider id (`qwen` / `openrouter` / `ollama-cloud`) — also the usage key prefix (§8).
    public var providerID: String
    /// Human-facing label for error messages ("Qwen", "OpenRouter", "Ollama Cloud").
    public var label: String
    /// Effective model id (settings value, or catalog default when the user never picked one).
    public var model: String
    /// Trimmed API key (guaranteed non-empty by `route`).
    public var apiKey: String
    /// Full `POST` chat/completions URL.
    public var endpoint: URL
    /// HTTP headers to apply (Authorization Bearer; Content-Type is set by the engine).
    public var headers: [String: String]
}

public enum CloudChatRouter {
    /// Default Qwen (DashScope PAYG) OpenAI-compatible chat completions endpoint.
    /// Used when `AppSettings.resolvedQwenBaseUrl` resolves to the standard host.
    public static let qwenDefaultChatCompletionsURL =
        "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions"

    /// Provider ids handled by this router (subset of CloudProviderCatalog).
    public static let chatProviderIDs: [String] = [
        CloudProviderCatalog.qwenID,
        CloudProviderCatalog.openrouterID,
        CloudProviderCatalog.ollamaCloudID,
    ]

    /// Trimmed API key for a routed provider, or nil when missing/blank.
    /// Shared by ProviderRegistry (option gating) and `route` (request auth).
    public static func apiKey(for providerID: String, settings: AppSettings) -> String? {
        let raw: String
        switch providerID {
        case CloudProviderCatalog.qwenID:
            raw = settings.qwenApiKey
        case CloudProviderCatalog.openrouterID:
            raw = settings.openrouterApiKey
        case CloudProviderCatalog.ollamaCloudID:
            raw = settings.ollamaCloudApiKey
        default:
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public enum ModelPurpose: Sendable {
        case transcription
        case translation
    }

    /// Resolve a provider id into a ready-to-use chat route, or nil when the id is
    /// not handled here or no key is saved (mirrors ActiveCloud*Provider.resolve).
    public static func route(
        providerID: String,
        settings: AppSettings,
        purpose: ModelPurpose = .translation
    ) -> CloudChatRoute? {
        let id = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard chatProviderIDs.contains(id),
              let key = apiKey(for: id, settings: settings),
              let descriptor = CloudProviderCatalog.descriptor(for: id) else {
            return nil
        }

        // Budget enforcement: block routing if the user's budget limit is reached
        guard !ProviderRegistry.isBudgetExceeded(providerID: id, settings: settings) else {
            return nil
        }

        let endpointString: String
        var configuredModel: String
        switch id {
        case CloudProviderCatalog.qwenID:
            // Prefer resolved endpoint profile (Token Plan vs PAYG); fall back to default DashScope URL.
            let base = settings.resolvedQwenBaseUrl(apiKey: settings.qwenApiKey)
            if base == "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
                || base == "https://dashscope-intl.aliyuncs.com/compatible-mode" {
                endpointString = Self.qwenDefaultChatCompletionsURL
            } else {
                endpointString = base + (base.hasSuffix("/v1") ? "/chat/completions" : "/v1/chat/completions")
            }
            // Settings model field: qwenCloudModel (blank → catalog default below).
            configuredModel = settings.qwenCloudModel
        case CloudProviderCatalog.openrouterID:
            endpointString = "https://openrouter.ai/api/v1/chat/completions"
            // Role-specific models with fallback to openrouterModel (see AppSettings helpers).
            configuredModel = purpose == .transcription
                ? settings.transcriptionModel(for: id)
                : settings.translationModel(for: id)
            if configuredModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                configuredModel = settings.openrouterModel
            }
        case CloudProviderCatalog.ollamaCloudID:
            var base = settings.ollamaCloudBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            while base.hasSuffix("/") { base.removeLast() }
            if base.isEmpty { base = "https://ollama.com" }
            endpointString = base + "/v1/chat/completions"
            configuredModel = settings.ollamaCloudModel
        default:
            return nil
        }

        guard let endpoint = URL(string: endpointString) else { return nil }

        let trimmedModel = configuredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = trimmedModel.isEmpty ? descriptor.defaultTextModel : trimmedModel

        if purpose == .transcription {
            guard CloudProviderCatalog.supportsTranscription(providerID: id, modelID: model) else {
                return nil
            }
        }

        return CloudChatRoute(
            providerID: id,
            label: descriptor.label,
            model: model,
            apiKey: key,
            endpoint: endpoint,
            headers: ["Authorization": "Bearer \(key)"]
        )
    }
}
