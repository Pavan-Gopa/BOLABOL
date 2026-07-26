import Foundation

// MARK: - CloudProviderCatalog
//
// Role: single source of truth (VaniScriptCore layer) describing the cloud AI
// providers offered on the "API & Usage" tab. UI (SettingsView / ProviderCardView)
// and engines (Cloud*Engine) read from this catalog instead of hardcoding provider
// ids, labels, default models or "Get API Key" URLs.
//
// A1 scope: data only. This file owns the *fixed provider ordering* approved by
// Human (`API_USAGE_ARCHITECTURE.md` §7) and the per-provider descriptors. It must
// NOT perform network calls, key validation or model listing — those live in
// CloudKeyValidator / CloudModelCatalog (A4) and CloudBalanceService (A7).
//
// Invariants (§14): no keys/tokens in source; buildable each step; migration-safe.

/// How the models list is fetched for a provider (consumed by CloudModelCatalog at A4).
/// A1 only records the *shape*; no network code here.
public enum ModelsEndpoint: String, Codable, Equatable, Sendable {
    /// OpenAI-compatible `GET /v1/models` → `data[].id` (OpenAI, Qwen, OpenRouter).
    case openAICompatible
    /// Gemini `GET /v1beta/models` → `models[].name` (strip `models/`).
    case gemini
    /// Anthropic `GET /v1/models` → `data[].id`.
    case anthropic
    /// Ollama Cloud `GET /api/tags` → `models[].name`.
    case ollamaTags
    /// User-defined provider (CustomCloudProvider): no automatic listing.
    case custom
    /// No automatic model listing available for this provider.
    case none
}

/// Honest capability flags per provider (verified progressively; see §7 / A5).
public struct CloudProviderCapabilities: Codable, Equatable, Sendable {
    /// Provider can transcribe audio (speech-to-text).
    public var supportsTranscription: Bool
    /// Provider can translate / edit text.
    public var supportsTranslation: Bool
    /// Provider exposes a real balance/limit via API (drives §11 balance UI).
    public var supportsRealBalance: Bool

    public init(
        supportsTranscription: Bool,
        supportsTranslation: Bool,
        supportsRealBalance: Bool
    ) {
        self.supportsTranscription = supportsTranscription
        self.supportsTranslation = supportsTranslation
        self.supportsRealBalance = supportsRealBalance
    }
}

/// How a provider's balance is represented in the UI (§11).
/// `.estimated` = locally counted tokens only (with disclaimer); never fake "$".
public enum BalanceKind: String, Codable, Equatable, Sendable {
    /// No balance concept shown at all.
    case none
    /// Real USD credits/limit (OpenRouter `/api/v1/credits` + `/api/v1/key`).
    case openrouterCredits
    /// Plan-based limits (Ollama Cloud — GPU time, not USD).
    case ollamaPlan
    /// Only locally estimated spend (Gemini/OpenAI/Anthropic/Qwen).
    case estimated
}

/// Immutable description of one cloud provider (§7). Pure data — no behavior.
public struct CloudProviderDescriptor: Codable, Equatable, Sendable, Identifiable {
    /// Stable provider id used as key everywhere:
    /// `gemini | openai | anthropic | qwen | openrouter | ollama-cloud | custom`.
    public let id: String
    /// Human-facing label for the dropdown ("Google Gemini", ...).
    public let label: String
    /// URL for the "Get API Key" button.
    public let getApiKeyURL: String
    /// How to fetch the models list (A4).
    public let modelsEndpoint: ModelsEndpoint
    /// Honest capability flags.
    public let capabilities: CloudProviderCapabilities
    /// Fallback text model if auto-fetch is unavailable.
    public let defaultTextModel: String
    /// Fallback audio (transcription) model, when supported.
    public let defaultAudioModel: String?
    /// How balance is represented (§11).
    public let balanceKind: BalanceKind

    public init(
        id: String,
        label: String,
        getApiKeyURL: String,
        modelsEndpoint: ModelsEndpoint,
        capabilities: CloudProviderCapabilities,
        defaultTextModel: String,
        defaultAudioModel: String?,
        balanceKind: BalanceKind
    ) {
        self.id = id
        self.label = label
        self.getApiKeyURL = getApiKeyURL
        self.modelsEndpoint = modelsEndpoint
        self.capabilities = capabilities
        self.defaultTextModel = defaultTextModel
        self.defaultAudioModel = defaultAudioModel
        self.balanceKind = balanceKind
    }
}


/// Catalog of cloud providers — the single source of truth for ordering + metadata.
public enum CloudProviderCatalog {
    // Stable provider ids (avoid stringly-typed drift across the codebase).
    public static let geminiID = "gemini"
    public static let openaiID = "openai"
    public static let anthropicID = "anthropic"
    public static let qwenID = "qwen"
    public static let openrouterID = "openrouter"
    public static let ollamaCloudID = "ollama-cloud"
    public static let customID = "custom"

    /// Fixed dropdown order approved by Human (§7): must NOT be reordered.
    /// `gemini → openai → anthropic → qwen → openrouter → ollama-cloud → custom`.
    public static let providerOrder: [String] = [
        geminiID, openaiID, anthropicID, qwenID, openrouterID, ollamaCloudID, customID,
    ]

    /// Provider descriptors in the fixed dropdown order.
    public static let providers: [CloudProviderDescriptor] = [
        CloudProviderDescriptor(
            id: geminiID,
            label: "Google Gemini",
            getApiKeyURL: "https://aistudio.google.com/apikey",
            modelsEndpoint: .gemini,
            // Gemini: multimodal generateContent handles audio; no $ balance by key.
            capabilities: CloudProviderCapabilities(
                supportsTranscription: true,
                supportsTranslation: true,
                supportsRealBalance: false
            ),
            defaultTextModel: "gemini-2.5-flash", // current hardcode (do not change behavior)
            defaultAudioModel: "gemini-2.5-flash",
            balanceKind: .estimated
        ),
        CloudProviderDescriptor(
            id: openaiID,
            label: "OpenAI",
            getApiKeyURL: "https://platform.openai.com/api-keys",
            modelsEndpoint: .openAICompatible,
            // OpenAI: whisper transcription + chat translation; no $ balance by key.
            capabilities: CloudProviderCapabilities(
                supportsTranscription: true,
                supportsTranslation: true,
                supportsRealBalance: false
            ),
            defaultTextModel: "gpt-4o-mini", // current hardcode (do not change behavior)
            defaultAudioModel: "whisper-1",
            balanceKind: .estimated
        ),
        CloudProviderDescriptor(
            id: anthropicID,
            label: "Anthropic",
            getApiKeyURL: "https://console.anthropic.com/settings/keys",
            modelsEndpoint: .anthropic,
            // Anthropic: text-only (no transcription); no $ balance by key.
            capabilities: CloudProviderCapabilities(
                supportsTranscription: false,
                supportsTranslation: true,
                supportsRealBalance: false
            ),
            defaultTextModel: "claude-3-5-sonnet-latest",
            defaultAudioModel: nil,
            balanceKind: .estimated
        ),
        CloudProviderDescriptor(
            id: qwenID,
            label: "Qwen",
            getApiKeyURL: "https://bailian.console.alibabacloud.com/?apiKey=1",
            modelsEndpoint: .openAICompatible,
            // Qwen (DashScope, OpenAI-compatible): translation ok; audio format TBD (A5).
            capabilities: CloudProviderCapabilities(
                supportsTranscription: false,
                supportsTranslation: true,
                supportsRealBalance: false
            ),
            defaultTextModel: "qwen-plus",
            defaultAudioModel: nil,
            balanceKind: .estimated
        ),
        CloudProviderDescriptor(
            id: openrouterID,
            label: "OpenRouter",
            getApiKeyURL: "https://openrouter.ai/keys",
            modelsEndpoint: .openAICompatible,
            // OpenRouter: routes to many models; real USD balance via credits/key API.
            capabilities: CloudProviderCapabilities(
                supportsTranscription: false,
                supportsTranslation: true,
                supportsRealBalance: true
            ),
            defaultTextModel: "openai/gpt-4o-mini",
            defaultAudioModel: nil,
            balanceKind: .openrouterCredits
        ),
        CloudProviderDescriptor(
            id: ollamaCloudID,
            label: "Ollama Cloud",
            getApiKeyURL: "https://ollama.com/settings/keys",
            modelsEndpoint: .ollamaTags,
            // Ollama Cloud: plan-based limits (GPU time), not USD; audio depends on model.
            capabilities: CloudProviderCapabilities(
                supportsTranscription: false,
                supportsTranslation: true,
                supportsRealBalance: true
            ),
            defaultTextModel: "gpt-oss:120b",
            defaultAudioModel: nil,
            balanceKind: .ollamaPlan
        ),
        CloudProviderDescriptor(
            id: customID,
            label: "Custom",
            getApiKeyURL: "",
            modelsEndpoint: .custom,
            // Custom: fully user-defined via CustomCloudProvider (existing mechanism).
            capabilities: CloudProviderCapabilities(
                supportsTranscription: false,
                supportsTranslation: true,
                supportsRealBalance: false
            ),
            defaultTextModel: "",
            defaultAudioModel: nil,
            balanceKind: .estimated
        ),
    ]

    /// Descriptor lookup by id (nil if unknown).
    public static func descriptor(for id: String) -> CloudProviderDescriptor? {
        providers.first { $0.id == id }
    }

    /// Display name for a provider id; falls back to the raw id when unknown
    /// (so custom/legacy ids still render something sensible in the UI).
    public static func providerDisplayName(_ id: String) -> String {
        descriptor(for: id)?.label ?? id
    }
}
