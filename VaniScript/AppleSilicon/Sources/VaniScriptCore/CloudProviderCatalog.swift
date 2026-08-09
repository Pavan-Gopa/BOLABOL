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
            // Anthropic: text translation/editing (workflow route lands with OBS-005 / CPS).
            // No audio transcription endpoint; no real $ balance by key.
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

    /// Evaluates dynamically whether a provider + model combination supports audio transcription.
    /// Gemini and OpenAI native cloud providers support transcription.
    /// For routing providers (OpenRouter, Qwen, Ollama Cloud, Custom), the model ID is inspected for
    /// audio/speech-to-text indicators (e.g. `whisper`, `gemini`, `audio`, `speech`, `stt`, `asr`, `transcrib`, `voxtral`, `sensevoice`, `parakeet`).
    public static func supportsTranscription(providerID: String, modelID: String? = nil) -> Bool {
        let trimmedProvider = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedProvider == qwenID || trimmedProvider == "qwen" {
            return false
        }
        if trimmedProvider == geminiID || trimmedProvider == "gemini-cloud" ||
           trimmedProvider == openaiID || trimmedProvider == "gpt-cloud" {
            return true
        }

        if let desc = descriptor(for: trimmedProvider), desc.capabilities.supportsTranscription {
            return true
        }

        let modelToTest = (modelID?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? descriptor(for: trimmedProvider)?.defaultTextModel ?? ""

        let lower = modelToTest.lowercased()
        guard !lower.isEmpty else { return false }

        // OpenRouter supports dedicated audio transcription models (e.g. Grok STT, Deepgram Nova-3, Parakeet, Voxtral, MAI-Transcribe, Chirp 3, Qwen ASR, GPT Audio, Whisper).
        if trimmedProvider == openrouterID || trimmedProvider == "openrouter" {
            let openRouterAudioModels = [
                "gpt-audio", "gpt-4o-audio", "whisper", "stt", "deepgram", "transcribe", "parakeet", "voxtral", "mai-transcribe", "grok-stt", "sensevoice", "asr", "chirp"
            ]
            return openRouterAudioModels.contains { lower.contains($0) }
        }

        let audioKeywords = [
            "whisper", "gemini", "audio", "speech", "stt", "asr", "transcrib", "voxtral", "sensevoice", "parakeet", "fun-asr", "qwen-audio", "livetranslate", "omni"
        ]
        return audioKeywords.contains { lower.contains($0) }
    }

    /// Evaluates dynamically whether a provider + model combination supports text translation (chat completion).
    /// Dedicated audio-only STT models (e.g. `grok-stt`, `whisper`, `deepgram`, `parakeet`, `mai-transcribe`, `voxtral-mini`, `chirp`, `asr`)
    /// do NOT support text translation chat prompts.
    public static func supportsTranslation(providerID: String, modelID: String? = nil) -> Bool {
        let trimmedProvider = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelToTest = (modelID?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? descriptor(for: trimmedProvider)?.defaultTextModel ?? ""

        let lower = modelToTest.lowercased()
        guard !lower.isEmpty else { return true }

        let isDedicatedAudioSTT = lower.contains("whisper")
            || lower.contains("grok-stt")
            || lower.contains("deepgram")
            || lower.contains("parakeet")
            || lower.contains("mai-transcribe")
            || lower.contains("voxtral-mini")
            || lower.contains("chirp")
            || lower.contains("asr-flash")
            || lower.contains("fun-asr")
            || lower.contains("sensevoice")
            || lower.contains("livetranslate")
            || lower.contains("mini-transcribe")

        return !isDedicatedAudioSTT
    }

    /// Evaluates whether a model supports multimodal vision/video capabilities.
    public static func supportsVision(modelID: String) -> Bool {
        let lower = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        let visionKeywords = ["vision", "multimodal", "omni", "-vl", "claude-3", "gpt-4o", "gemini"]
        return visionKeywords.contains { lower.contains($0) }
    }

    public struct STTPricing: Equatable, Sendable {
        public let costPerMin: Double
        public let costPerHour: Double

        public init(costPerMin: Double, costPerHour: Double) {
            self.costPerMin = costPerMin
            self.costPerHour = costPerHour
        }

        public var formattedPerMin: String {
            if costPerMin < 0.0001 {
                return String(format: "$%.5f / min", costPerMin)
            } else if costPerMin < 0.01 {
                return String(format: "$%.4f / min", costPerMin)
            } else {
                return String(format: "$%.3f / min", costPerMin)
            }
        }

        public var formattedPerHour: String {
            return String(format: "$%.3f / hour", costPerHour)
        }
    }

    /// Evaluates per-minute and per-hour cost for dedicated audio STT models.
    public static func sttPricing(for modelID: String) -> STTPricing {
        let lower = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if lower.contains("grok-stt") {
            return STTPricing(costPerMin: 0.00167, costPerHour: 0.10)
        }
        if lower.contains("deepgram") || lower.contains("nova-3") {
            return STTPricing(costPerMin: 0.0043, costPerHour: 0.258)
        }
        if lower.contains("parakeet") {
            return STTPricing(costPerMin: 0.0010, costPerHour: 0.060)
        }
        if lower.contains("qwen3-asr") || lower.contains("qwen3-livetranslate") {
            return STTPricing(costPerMin: 0.0060, costPerHour: 0.360)
        }
        if lower.contains("fun-asr") || lower.contains("sensevoice") {
            return STTPricing(costPerMin: 0.0040, costPerHour: 0.240)
        }
        if lower.contains("qwen-audio") || lower.contains("qwen2-audio") {
            return STTPricing(costPerMin: 0.0050, costPerHour: 0.300)
        }
        if lower.contains("chirp") {
            return STTPricing(costPerMin: 0.0160, costPerHour: 0.0160 * 60.0)
        }
        if lower.contains("whisper-large-v3-turbo") {
            return STTPricing(costPerMin: 0.0010, costPerHour: 0.0010 * 60.0)
        }
        if lower.contains("whisper-large-v3") {
            return STTPricing(costPerMin: 0.0015, costPerHour: 0.0015 * 60.0)
        }
        if lower.contains("whisper") {
            return STTPricing(costPerMin: 0.0060, costPerHour: 0.0060 * 60.0)
        }
        if lower.contains("gpt-4o-mini-transcribe") {
            return STTPricing(costPerMin: 0.0050, costPerHour: 0.0050 * 60.0)
        }
        if lower.contains("gpt-4o-transcribe") {
            return STTPricing(costPerMin: 0.0100, costPerHour: 0.0100 * 60.0)
        }

        return STTPricing(costPerMin: 0.0030, costPerHour: 0.180)
    }

    /// Evaluates context window size and input/output pricing per 1M tokens for a model.
    public static func modelPricingDetails(
        providerID: String,
        modelID: String,
        loadedModel: CloudModel? = nil
    ) -> (context: String, inputCost: String, outputCost: String) {
        let trimmedModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)

        if let loaded = loadedModel {
            let ctxText: String = {
                if let ctx = loaded.contextLength { return formatTokens(ctx) }
                return defaultContext(for: trimmedModel)
            }()
            let inText: String = {
                if let p = loaded.promptPricePer1M { return String(format: "$%.3f / 1M", p) }
                return defaultInputCost(for: trimmedModel)
            }()
            let outText: String = {
                if let c = loaded.completionPricePer1M { return String(format: "$%.3f / 1M", c) }
                return defaultOutputCost(for: trimmedModel)
            }()
            return (ctxText, inText, outText)
        }

        return (
            defaultContext(for: trimmedModel),
            defaultInputCost(for: trimmedModel),
            defaultOutputCost(for: trimmedModel)
        )
    }

    private static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            let millions = Double(count) / 1_000_000.0
            return String(format: "%.1fM tokens", millions)
        } else if count >= 1_000 {
            let thousands = count / 1_000
            return "\(thousands)K tokens"
        }
        return "\(count) tokens"
    }

    private static func defaultContext(for model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("qwen3.8") || lower.contains("qwen3.7") || lower.contains("qwen3.6") || lower.contains("qwen-long") || lower.contains("qwen-turbo") {
            return "1.0M tokens"
        }
        if lower.contains("gemini-2.5") || lower.contains("gemini-3.5") || lower.contains("gemini-1.5") {
            return "1.0M tokens"
        }
        if lower.contains("claude-3") || lower.contains("sonnet") || lower.contains("opus") {
            return "200K tokens"
        }
        return "128K tokens"
    }

    private static func defaultInputCost(for model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("qwen3.8") || lower.contains("qwen3.7-max") || lower.contains("qwen-max") {
            return "$0.350 / 1M"
        }
        if lower.contains("qwen3.7-plus") || lower.contains("qwen-plus") {
            return "$0.110 / 1M"
        }
        if lower.contains("qwen3.6") || lower.contains("qwen-turbo") {
            return "$0.050 / 1M"
        }
        if lower.contains("deepseek") {
            return "$0.140 / 1M"
        }
        if lower.contains("glm") {
            return "$0.100 / 1M"
        }
        if lower.contains("gemini-2.5-pro") || lower.contains("gemini-1.5-pro") {
            return "$1.250 / 1M"
        }
        if lower.contains("gemini-2.5-flash") || lower.contains("gemini-1.5-flash") || lower.contains("gemini") {
            return "$0.075 / 1M"
        }
        if lower.contains("gpt-4o-mini") {
            return "$0.150 / 1M"
        }
        if lower.contains("gpt-4o") {
            return "$2.500 / 1M"
        }
        if lower.contains("claude-3-5-sonnet") || lower.contains("sonnet") {
            return "$3.000 / 1M"
        }
        return "$0.150 / 1M"
    }

    private static func defaultOutputCost(for model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("qwen3.8") || lower.contains("qwen3.7-max") || lower.contains("qwen-max") {
            return "$1.050 / 1M"
        }
        if lower.contains("qwen3.7-plus") || lower.contains("qwen-plus") {
            return "$0.330 / 1M"
        }
        if lower.contains("qwen3.6") || lower.contains("qwen-turbo") {
            return "$0.150 / 1M"
        }
        if lower.contains("deepseek") {
            return "$0.280 / 1M"
        }
        if lower.contains("glm") {
            return "$0.200 / 1M"
        }
        if lower.contains("gemini-2.5-pro") || lower.contains("gemini-1.5-pro") {
            return "$5.000 / 1M"
        }
        if lower.contains("gemini-2.5-flash") || lower.contains("gemini-1.5-flash") || lower.contains("gemini") {
            return "$0.300 / 1M"
        }
        if lower.contains("gpt-4o-mini") {
            return "$0.600 / 1M"
        }
        if lower.contains("gpt-4o") {
            return "$10.000 / 1M"
        }
        if lower.contains("claude-3-5-sonnet") || lower.contains("sonnet") {
            return "$15.000 / 1M"
        }
        return "$0.600 / 1M"
    }
}
