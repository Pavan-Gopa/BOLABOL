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
    public static func availableTranscriptionProviders(settings: AppSettings) -> [ProviderOption] {
        var providers: [ProviderOption] = [
            ProviderOption(
                id: "coreml-whisperkit",
                label: "WhisperKit Core ML",
                group: .local,
                kind: .transcription,
                requiresKey: nil
            )
        ]
        if !settings.geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            && descriptor.capabilities.supportsTranscription
            && CloudChatRouter.apiKey(for: descriptor.id, settings: settings) != nil {
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
        return providers + downloadedLocalProviders(models: settings.localAsrModels, kind: .transcription)
    }

    public static func availableTranslationProviders(
        settings: AppSettings,
        targetLang: String
    ) -> TranslationProviderAvailability {
        guard targetLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "same" else {
            return TranslationProviderAvailability(enabled: false, providers: [])
        }

        var providers: [ProviderOption] = []
        if !settings.geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        providers.append(
            ProviderOption(
                id: "mlx-native",
                label: "MLX Swift Local",
                group: .local,
                kind: .translation,
                requiresKey: nil
            )
        )
        providers += downloadedLocalProviders(models: settings.localTranslationModels, kind: .translation)
        return TranslationProviderAvailability(enabled: true, providers: providers)
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
                    return LocalModelVerification.verifyModelPath(state.path, isWhisper: true)
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

/// A5: builds `CloudChatRoute`s for the providers that speak the OpenAI-compatible
/// chat protocol. Endpoints follow the A1/A5 discovery (see DECISIONS.md ADR A5):
///   - Qwen: DashScope *compatible-mode* (`/compatible-mode/v1/chat/completions`).
///   - OpenRouter: `/api/v1/chat/completions`.
///   - Ollama Cloud: OpenAI-compatible `/v1/chat/completions` on the user's base URL
///     (default `https://ollama.com`). Chosen over native `/api/chat` so the engines
///     reuse one request/response/usage parser for all three providers.
public enum CloudChatRouter {
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

    /// Resolve a provider id into a ready-to-use chat route, or nil when the id is
    /// not handled here or no key is saved (mirrors ActiveCloud*Provider.resolve).
    public static func route(providerID: String, settings: AppSettings) -> CloudChatRoute? {
        let id = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard chatProviderIDs.contains(id),
              let key = apiKey(for: id, settings: settings),
              let descriptor = CloudProviderCatalog.descriptor(for: id) else {
            return nil
        }

        let endpointString: String
        let configuredModel: String
        switch id {
        case CloudProviderCatalog.qwenID:
            // DashScope international endpoint, OpenAI compatible-mode (A1 verified:
            // 401 without Bearer ⇒ endpoint live). Same base as CloudModelCatalog.
            endpointString = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions"
            configuredModel = settings.qwenCloudModel
        case CloudProviderCatalog.openrouterID:
            endpointString = "https://openrouter.ai/api/v1/chat/completions"
            configuredModel = settings.openrouterModel
        case CloudProviderCatalog.ollamaCloudID:
            // User-configurable base URL (self-host escape hatch); trailing slashes
            // stripped so "https://ollama.com/" doesn't produce "//v1/...".
            var base = settings.ollamaCloudBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            while base.hasSuffix("/") { base.removeLast() }
            if base.isEmpty { base = "https://ollama.com" }
            endpointString = base + "/v1/chat/completions"
            configuredModel = settings.ollamaCloudModel
        default:
            return nil
        }

        guard let endpoint = URL(string: endpointString) else { return nil }

        // Model precedence matches A4 (§9.2): user-selected settings model first,
        // catalog default as migration-safe fallback (empty settings ⇒ old behavior).
        let trimmedModel = configuredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = trimmedModel.isEmpty ? descriptor.defaultTextModel : trimmedModel

        return CloudChatRoute(
            providerID: id,
            label: descriptor.label,
            model: model,
            apiKey: key,
            endpoint: endpoint,
            // All three providers authenticate with a plain Bearer token.
            headers: ["Authorization": "Bearer \(key)"]
        )
    }
}
