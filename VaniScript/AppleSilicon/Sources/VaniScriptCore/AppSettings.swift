import Foundation
import Security

public enum Theme: String, Codable, CaseIterable, Equatable, Sendable {
    case dark
    case light
}

public enum FontSize: String, Codable, CaseIterable, Equatable, Sendable {
    case sm
    case md
    case lg
    case xl
}

public enum FontFamily: String, Codable, CaseIterable, Equatable, Sendable {
    case mono
    case sans
    case serif
}

public enum LogLevel: String, Codable, CaseIterable, Equatable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
}

public enum SliceMode: String, Codable, CaseIterable, Equatable, Sendable {
    case silence
    case fixed
}

public enum LocalModelStatus: String, Codable, Equatable, Sendable {
    case notDownloaded = "not_downloaded"
    case downloading
    case downloaded
    case failed
}

public enum LocalModelRuntime: String, Codable, Equatable, Sendable {
    case whisper
    case parakeet
    case canary
    case mlx
}

public struct LocalModelState: Codable, Equatable, Sendable {
    public var status: LocalModelStatus
    public var progress: Double?
    public var progressLabel: String?
    public var label: String
    public var path: String? {
        didSet {
            location = Self.location(for: path)
        }
    }
    public var location: SharedModelLocation?
    public var error: String?
    public var runtime: LocalModelRuntime

    private enum CodingKeys: String, CodingKey {
        case status
        case progress
        case progressLabel
        case label
        case path
        case location
        case error
        case runtime
    }

    public init(
        status: LocalModelStatus,
        progress: Double? = nil,
        progressLabel: String? = nil,
        label: String,
        path: String? = nil,
        error: String? = nil,
        runtime: LocalModelRuntime
    ) {
        self.status = status
        self.progress = progress
        self.progressLabel = progressLabel
        self.label = label
        self.path = path
        self.location = Self.location(for: path)
        self.error = error
        self.runtime = runtime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decode(LocalModelStatus.self, forKey: .status)
        self.progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        self.progressLabel = try container.decodeIfPresent(String.self, forKey: .progressLabel)
        self.label = try container.decode(String.self, forKey: .label)
        let decodedLocation = try container.decodeIfPresent(SharedModelLocation.self, forKey: .location)
        self.location = decodedLocation
        if let decodedLocation {
            self.path = SharedModelsRoot.modelURL(for: decodedLocation).path
        } else {
            self.path = try container.decodeIfPresent(String.self, forKey: .path)
            self.location = Self.location(for: path)
        }
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
        let decodedRuntime = try? container.decodeIfPresent(LocalModelRuntime.self, forKey: .runtime)
        self.runtime = decodedRuntime ?? Self.runtime(for: decodedLocation ?? self.location) ?? .whisper
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(progress, forKey: .progress)
        try container.encodeIfPresent(progressLabel, forKey: .progressLabel)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(location, forKey: .location)
        if location == nil {
            try container.encodeIfPresent(path, forKey: .path)
        }
        try container.encodeIfPresent(error, forKey: .error)
        try container.encode(runtime, forKey: .runtime)
    }

    private static func location(for path: String?) -> SharedModelLocation? {
        guard let path, !path.isEmpty else { return nil }
        return SharedModelsRoot.location(for: URL(fileURLWithPath: path))
    }

    private static func runtime(for location: SharedModelLocation?) -> LocalModelRuntime? {
        guard let location else { return nil }
        switch location.runtime {
        case .whisperkit:
            return .whisper
        case .parakeet:
            return .parakeet
        case .canary:
            return .canary
        case .mlx:
            return .mlx
        case .gguf, .ggml:
            return nil
        }
    }
}

public struct GlossaryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var variants: [String]
    public var source: String
    public var translation: String
    public var category: String?
    public var translations: [String: String]
    public var remember: Bool
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String,
        variants: [String],
        source: String,
        translation: String,
        category: String?,
        translations: [String: String],
        remember: Bool,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.variants = variants
        self.source = source
        self.translation = translation
        self.category = category
        self.translations = translations
        self.remember = remember
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ProviderUsage: Codable, Equatable, Sendable {
    public var sessions: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var audioMinutes: Double
    public var lastUsed: String
    public var lastInputTokens: Int?
    public var lastOutputTokens: Int?
    // A1 (§6.1): per-model statistics support. Optional + decodeIfPresent so old
    // settings files decode without migration (nil = never recorded).
    /// Model id of the last recorded transaction (for the "Last Transaction" badge).
    public var lastModel: String?
    /// ISO-8601 timestamp of the last transaction (used to sort the latest entry).
    public var lastTransactionAt: String?
    /// Purpose of last transaction: "transcription" or "translation".
    public var lastPurpose: String?
    /// Audio minutes processed in the last transaction (if applicable).
    public var lastAudioMinutes: Double?

    public init(
        sessions: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        audioMinutes: Double = 0,
        lastUsed: String = "",
        lastInputTokens: Int? = nil,
        lastOutputTokens: Int? = nil,
        lastModel: String? = nil,
        lastTransactionAt: String? = nil,
        lastPurpose: String? = nil,
        lastAudioMinutes: Double? = nil
    ) {
        self.sessions = sessions
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.audioMinutes = audioMinutes
        self.lastUsed = lastUsed
        self.lastInputTokens = lastInputTokens
        self.lastOutputTokens = lastOutputTokens
        self.lastModel = lastModel
        self.lastTransactionAt = lastTransactionAt
        self.lastPurpose = lastPurpose
        self.lastAudioMinutes = lastAudioMinutes
    }

    // Explicit decoder so new optional fields are migration-safe (decodeIfPresent).
    // The synthesized decoder would already tolerate missing optionals, but we make
    // the contract explicit per invariant §14.1 (old settings must keep decoding).
    private enum CodingKeys: String, CodingKey {
        case sessions, inputTokens, outputTokens, audioMinutes, lastUsed
        case lastInputTokens, lastOutputTokens
        case lastModel, lastTransactionAt, lastPurpose, lastAudioMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessions = try container.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
        self.inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        self.outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        self.audioMinutes = try container.decodeIfPresent(Double.self, forKey: .audioMinutes) ?? 0
        self.lastUsed = try container.decodeIfPresent(String.self, forKey: .lastUsed) ?? ""
        self.lastInputTokens = try container.decodeIfPresent(Int.self, forKey: .lastInputTokens)
        self.lastOutputTokens = try container.decodeIfPresent(Int.self, forKey: .lastOutputTokens)
        self.lastModel = try container.decodeIfPresent(String.self, forKey: .lastModel)
        self.lastTransactionAt = try container.decodeIfPresent(String.self, forKey: .lastTransactionAt)
        self.lastPurpose = try container.decodeIfPresent(String.self, forKey: .lastPurpose)
        self.lastAudioMinutes = try container.decodeIfPresent(Double.self, forKey: .lastAudioMinutes)
    }
}
public struct CustomCloudProvider: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var baseUrl: String
    public var apiKey: String
    public var modelName: String
    public var inputCostPerMillion: Double
    public var outputCostPerMillion: Double
    public var budgetLimitUsd: Double

    public init(
        id: String = UUID().uuidString,
        label: String,
        baseUrl: String,
        apiKey: String,
        modelName: String,
        inputCostPerMillion: Double,
        outputCostPerMillion: Double,
        budgetLimitUsd: Double = 0.0
    ) {
        self.id = id
        self.label = label
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.modelName = modelName
        self.inputCostPerMillion = inputCostPerMillion
        self.outputCostPerMillion = outputCostPerMillion
        self.budgetLimitUsd = budgetLimitUsd
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    /// Primary/legacy Gemini key. Kept in sync with the first enabled `geminiKeys` entry.
    public var geminiKey: String {
        didSet { syncGeminiBankFromPrimaryKeyIfNeeded() }
    }
    /// Multi-key Gemini bank (max 10). Entries may use `#DISABLED#` prefix.
    public var geminiKeys: [String] {
        didSet { syncGeminiPrimaryKeyFromBankIfNeeded() }
    }
    public var openaiKey: String
    public var anthropicKey: String
    public var geminiBudgetUsd: Double
    public var openaiBudgetUsd: Double
    // A1 (§6.3): selected text models for existing providers. Defaults mirror the
    // current engine hardcode so behavior is unchanged if the user never picks one.
    public var geminiTextModel: String
    public var openaiTextModel: String
    // A1 (§6.3): new cloud providers (Qwen / OpenRouter / Ollama Cloud). Keys + selected
    // model + budget. All optional-on-decode (decodeIfPresent) → migration-safe.
    public var qwenApiKey: String
    public var qwenCloudModel: String
    public var qwenBudgetUsd: Double
    public var qwenBaseUrl: String
    public var openrouterApiKey: String
    public var openrouterModel: String
    public var openrouterTranscriptionModel: String
    public var openrouterTranslationModel: String
    public var openrouterBudgetUsd: Double
    public var ollamaCloudApiKey: String
    public var ollamaCloudModel: String
    public var ollamaCloudBaseUrl: String
    public var theme: Theme
    public var fontSize: FontSize
    public var fontScale: Double
    public var fontFamily: FontFamily
    public var chunkDurationMin: Int
    public var sliceMode: SliceMode
    public var silenceThreshDb: Int
    public var minSilenceMs: Int
    public var defaultSourceLang: String
    public var transcriptionProvider: String
    public var translationProvider: String
    public var defaultTargetLang: String
    public var documentApprovalModeDefault: ApprovalMode
    public var localAsrModels: [String: LocalModelState]
    public var localTranslationModels: [String: LocalModelState]
    public var promptPresets: [String: PromptPresetSettings]
    public var usage: [String: ProviderUsage]
    public var glossary: [GlossaryEntry]
    public var customCloudProviders: [CustomCloudProvider]
    public var hasCompletedOnboarding: Bool
    public var completedOnboardingBuildID: String?
    public var mediaResolverEndpoint: String
    public var mediaResolverToken: String
    public var mcpServerEnabled: Bool
    public var mcpAllowMutatingTools: Bool
    public var mcpAllowProcessingTools: Bool
    public var mcpAllowFileTools: Bool
    public var mcpAllowNetworkTools: Bool
    public var mcpAllowDestructiveTools: Bool
    public var mcpAccessToken: String
    public var mcpPreferredAgentID: String
    public var codexChatModelID: String
    public var codexChatReasoningEffort: String
    public var grokChatModelID: String
    public var grokChatReasoningEffort: String
    public var qwenChatModelID: String // Q2: no reasoning-effort — Qwen CLI has no such flag
    public var logLevel: LogLevel
    public var requireCanonicalNames: Bool
    public var favoriteCloudModelIDs: [String]
    private enum CodingKeys: String, CodingKey {
        case geminiKey, geminiKeys, openaiKey, anthropicKey
        case geminiBudgetUsd, openaiBudgetUsd
        // A1 (§6.3): selected models for existing providers + new cloud providers.
        case geminiTextModel, openaiTextModel
        case qwenApiKey, qwenCloudModel, qwenBudgetUsd, qwenBaseUrl
        case openrouterApiKey, openrouterModel, openrouterTranscriptionModel, openrouterTranslationModel, openrouterBudgetUsd
        case ollamaCloudApiKey, ollamaCloudModel, ollamaCloudBaseUrl
        case theme, fontSize, fontScale, fontFamily
        case chunkDurationMin, sliceMode, silenceThreshDb, minSilenceMs
        case defaultSourceLang, transcriptionProvider, translationProvider, defaultTargetLang
        case documentApprovalModeDefault
        case localAsrModels, localTranslationModels, promptPresets, usage, glossary, customCloudProviders
        case hasCompletedOnboarding, completedOnboardingBuildID
        case mediaResolverEndpoint, mediaResolverToken
        case mcpServerEnabled, mcpAllowMutatingTools
        case mcpAllowProcessingTools, mcpAllowFileTools, mcpAllowNetworkTools, mcpAllowDestructiveTools
        case mcpAccessToken, mcpPreferredAgentID
        case codexChatModelID, codexChatReasoningEffort
        case grokChatModelID, grokChatReasoningEffort
        case qwenChatModelID
        case logLevel
        case requireCanonicalNames
        case favoriteCloudModelIDs
    }

    public init(
        geminiKey: String = "",
        geminiKeys: [String] = [],
        openaiKey: String,
        anthropicKey: String,
        geminiBudgetUsd: Double,
        openaiBudgetUsd: Double,
        geminiTextModel: String = "gemini-2.5-flash",
        openaiTextModel: String = "gpt-4o-mini",
        qwenApiKey: String = "",
        qwenCloudModel: String = "",
        qwenBudgetUsd: Double = 0,
        qwenBaseUrl: String = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
        openrouterApiKey: String = "",
        openrouterModel: String = "",
        openrouterTranscriptionModel: String = "",
        openrouterTranslationModel: String = "",
        openrouterBudgetUsd: Double = 0,
        ollamaCloudApiKey: String = "",
        ollamaCloudModel: String = "",
        ollamaCloudBaseUrl: String = "https://ollama.com",
        theme: Theme,
        fontSize: FontSize,
        fontScale: Double,
        fontFamily: FontFamily,
        chunkDurationMin: Int,
        sliceMode: SliceMode,
        silenceThreshDb: Int,
        minSilenceMs: Int,
        defaultSourceLang: String,
        transcriptionProvider: String,
        translationProvider: String,
        defaultTargetLang: String,
        documentApprovalModeDefault: ApprovalMode = .manual,
        localAsrModels: [String: LocalModelState],
        localTranslationModels: [String: LocalModelState],
        promptPresets: [String: PromptPresetSettings],
        usage: [String: ProviderUsage],
        glossary: [GlossaryEntry],
        customCloudProviders: [CustomCloudProvider] = [],
        hasCompletedOnboarding: Bool = false,
        completedOnboardingBuildID: String? = nil,
        mediaResolverEndpoint: String = "",
        mediaResolverToken: String = "",
        mcpServerEnabled: Bool = false,
        mcpAllowMutatingTools: Bool = false,
        mcpAllowProcessingTools: Bool = false,
        mcpAllowFileTools: Bool = false,
        mcpAllowNetworkTools: Bool = false,
        mcpAllowDestructiveTools: Bool = false,
        mcpAccessToken: String = "",
        mcpPreferredAgentID: String = McpAgentProfileCatalog.defaultProfileID,
        codexChatModelID: String = CodexChatModelCatalog.defaultModelID,
        codexChatReasoningEffort: String = "medium",
        grokChatModelID: String = GrokChatModelCatalog.defaultModelID,
        grokChatReasoningEffort: String = "medium",
        qwenChatModelID: String = QwenChatModelCatalog.defaultModelID,
        logLevel: LogLevel = .info,
        requireCanonicalNames: Bool = true,
        favoriteCloudModelIDs: [String] = []
    ) {
        let bank: GeminiAPIKeyBank
        if !geminiKeys.isEmpty {
            bank = GeminiAPIKeyBank(entries: geminiKeys)
        } else {
            bank = GeminiAPIKeyBank(primaryKey: geminiKey)
        }
        self.geminiKeys = bank.entries
        self.geminiKey = bank.primaryKey
        self.openaiKey = openaiKey
        self.anthropicKey = anthropicKey
        self.geminiBudgetUsd = geminiBudgetUsd
        self.openaiBudgetUsd = openaiBudgetUsd
        self.geminiTextModel = geminiTextModel
        self.openaiTextModel = openaiTextModel
        self.qwenApiKey = qwenApiKey
        self.qwenCloudModel = qwenCloudModel
        self.qwenBudgetUsd = qwenBudgetUsd
        self.qwenBaseUrl = qwenBaseUrl
        self.openrouterApiKey = openrouterApiKey
        self.openrouterModel = openrouterModel
        self.openrouterTranscriptionModel = openrouterTranscriptionModel
        self.openrouterTranslationModel = openrouterTranslationModel
        self.openrouterBudgetUsd = openrouterBudgetUsd
        self.ollamaCloudApiKey = ollamaCloudApiKey
        self.ollamaCloudModel = ollamaCloudModel
        self.ollamaCloudBaseUrl = ollamaCloudBaseUrl
        self.theme = theme
        self.fontSize = fontSize
        self.fontScale = fontScale
        self.fontFamily = fontFamily
        self.chunkDurationMin = chunkDurationMin
        self.sliceMode = sliceMode
        self.silenceThreshDb = silenceThreshDb
        self.minSilenceMs = minSilenceMs
        self.defaultSourceLang = defaultSourceLang
        self.transcriptionProvider = transcriptionProvider
        self.translationProvider = translationProvider
        self.defaultTargetLang = defaultTargetLang
        self.documentApprovalModeDefault = documentApprovalModeDefault
        self.localAsrModels = localAsrModels
        self.localTranslationModels = localTranslationModels
        self.promptPresets = promptPresets
        self.usage = usage
        self.glossary = glossary
        self.customCloudProviders = customCloudProviders
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.completedOnboardingBuildID = completedOnboardingBuildID
        self.mediaResolverEndpoint = mediaResolverEndpoint
        self.mediaResolverToken = mediaResolverToken
        self.mcpServerEnabled = mcpServerEnabled
        self.mcpAllowMutatingTools = mcpAllowMutatingTools
        self.mcpAllowProcessingTools = mcpAllowProcessingTools
        self.mcpAllowFileTools = mcpAllowFileTools
        self.mcpAllowNetworkTools = mcpAllowNetworkTools
        self.mcpAllowDestructiveTools = mcpAllowDestructiveTools
        self.mcpAccessToken = mcpAccessToken
        self.mcpPreferredAgentID = mcpPreferredAgentID
        self.codexChatModelID = codexChatModelID
        self.codexChatReasoningEffort = codexChatReasoningEffort
        self.grokChatModelID = grokChatModelID
        self.grokChatReasoningEffort = grokChatReasoningEffort
        self.qwenChatModelID = qwenChatModelID
        self.logLevel = logLevel
        self.requireCanonicalNames = requireCanonicalNames
        self.favoriteCloudModelIDs = favoriteCloudModelIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyGeminiKey = try container.decodeIfPresent(String.self, forKey: .geminiKey) ?? ""
        let decodedGeminiKeys = try container.decodeIfPresent([String].self, forKey: .geminiKeys) ?? []
        if !decodedGeminiKeys.isEmpty {
            let bank = GeminiAPIKeyBank(entries: decodedGeminiKeys)
            self.geminiKeys = bank.entries
            self.geminiKey = bank.primaryKey
        } else {
            let bank = GeminiAPIKeyBank(primaryKey: legacyGeminiKey)
            self.geminiKeys = bank.entries
            self.geminiKey = bank.primaryKey
        }
        self.openaiKey = try container.decodeIfPresent(String.self, forKey: .openaiKey) ?? ""
        self.anthropicKey = try container.decodeIfPresent(String.self, forKey: .anthropicKey) ?? ""
        self.geminiBudgetUsd = try container.decodeIfPresent(Double.self, forKey: .geminiBudgetUsd) ?? 0
        self.openaiBudgetUsd = try container.decodeIfPresent(Double.self, forKey: .openaiBudgetUsd) ?? 0
        // A1 (§6.3/§6.4): migration-safe decode of new cloud-provider fields. Old
        // settings without these keys fall back to defaults (existing hardcode for
        // gemini/openai text models; empty/zero for the new providers).
        self.geminiTextModel = try container.decodeIfPresent(String.self, forKey: .geminiTextModel) ?? "gemini-2.5-flash"
        self.openaiTextModel = try container.decodeIfPresent(String.self, forKey: .openaiTextModel) ?? "gpt-4o-mini"
        self.qwenApiKey = try container.decodeIfPresent(String.self, forKey: .qwenApiKey) ?? ""
        self.qwenCloudModel = try container.decodeIfPresent(String.self, forKey: .qwenCloudModel) ?? ""
        self.qwenBudgetUsd = try container.decodeIfPresent(Double.self, forKey: .qwenBudgetUsd) ?? 0
        self.qwenBaseUrl = try container.decodeIfPresent(String.self, forKey: .qwenBaseUrl) ?? "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        self.openrouterApiKey = try container.decodeIfPresent(String.self, forKey: .openrouterApiKey) ?? ""
        self.openrouterModel = try container.decodeIfPresent(String.self, forKey: .openrouterModel) ?? ""
        self.openrouterBudgetUsd = try container.decodeIfPresent(Double.self, forKey: .openrouterBudgetUsd) ?? 0
        self.ollamaCloudApiKey = try container.decodeIfPresent(String.self, forKey: .ollamaCloudApiKey) ?? ""
        self.ollamaCloudModel = try container.decodeIfPresent(String.self, forKey: .ollamaCloudModel) ?? ""
        self.ollamaCloudBaseUrl = try container.decodeIfPresent(String.self, forKey: .ollamaCloudBaseUrl) ?? "https://ollama.com"
        self.theme = try container.decodeIfPresent(Theme.self, forKey: .theme) ?? .dark
        self.fontSize = try container.decodeIfPresent(FontSize.self, forKey: .fontSize) ?? .md
        self.fontScale = try container.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1
        self.fontFamily = try container.decodeIfPresent(FontFamily.self, forKey: .fontFamily) ?? .mono
        self.chunkDurationMin = try container.decodeIfPresent(Int.self, forKey: .chunkDurationMin) ?? 10
        self.sliceMode = try container.decodeIfPresent(SliceMode.self, forKey: .sliceMode) ?? .silence
        self.silenceThreshDb = try container.decodeIfPresent(Int.self, forKey: .silenceThreshDb) ?? -16
        self.minSilenceMs = try container.decodeIfPresent(Int.self, forKey: .minSilenceMs) ?? 400
        self.defaultSourceLang = try container.decodeIfPresent(String.self, forKey: .defaultSourceLang) ?? "auto"
        self.transcriptionProvider = try container.decodeIfPresent(String.self, forKey: .transcriptionProvider) ?? "coreml-whisperkit"
        self.translationProvider = try container.decodeIfPresent(String.self, forKey: .translationProvider) ?? "mlx-native"
        self.defaultTargetLang = try container.decodeIfPresent(String.self, forKey: .defaultTargetLang) ?? "Russian"
        self.documentApprovalModeDefault = try container.decodeIfPresent(ApprovalMode.self, forKey: .documentApprovalModeDefault) ?? .manual
        let decodedLocalASRModels = try container.decodeIfPresent([String: LocalModelState].self, forKey: .localAsrModels) ?? [:]
        self.localAsrModels = Self.mergeLocalASRDefaults(decodedLocalASRModels)
        self.localTranslationModels = try container.decodeIfPresent([String: LocalModelState].self, forKey: .localTranslationModels) ?? AppSettings.defaults.localTranslationModels
        self.promptPresets = try container.decodeIfPresent([String: PromptPresetSettings].self, forKey: .promptPresets) ?? DefaultPrompts.defaultPresets
        self.usage = try container.decodeIfPresent([String: ProviderUsage].self, forKey: .usage) ?? [:]
        self.glossary = try container.decodeIfPresent([GlossaryEntry].self, forKey: .glossary) ?? StarterGlossary.entries
        self.customCloudProviders = try container.decodeIfPresent([CustomCloudProvider].self, forKey: .customCloudProviders) ?? []
        self.hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        self.completedOnboardingBuildID = try container.decodeIfPresent(String.self, forKey: .completedOnboardingBuildID)
        self.mediaResolverEndpoint = try container.decodeIfPresent(String.self, forKey: .mediaResolverEndpoint) ?? ""
        self.mediaResolverToken = try container.decodeIfPresent(String.self, forKey: .mediaResolverToken) ?? ""
        self.mcpServerEnabled = try container.decodeIfPresent(Bool.self, forKey: .mcpServerEnabled) ?? false
        self.mcpAllowMutatingTools = try container.decodeIfPresent(Bool.self, forKey: .mcpAllowMutatingTools) ?? false
        self.mcpAllowProcessingTools = try container.decodeIfPresent(Bool.self, forKey: .mcpAllowProcessingTools) ?? false
        self.mcpAllowFileTools = try container.decodeIfPresent(Bool.self, forKey: .mcpAllowFileTools) ?? false
        self.mcpAllowNetworkTools = try container.decodeIfPresent(Bool.self, forKey: .mcpAllowNetworkTools) ?? false
        self.mcpAllowDestructiveTools = try container.decodeIfPresent(Bool.self, forKey: .mcpAllowDestructiveTools) ?? false
        self.mcpAccessToken = try container.decodeIfPresent(String.self, forKey: .mcpAccessToken) ?? ""
        self.mcpPreferredAgentID = try container.decodeIfPresent(String.self, forKey: .mcpPreferredAgentID) ?? McpAgentProfileCatalog.defaultProfileID
        self.codexChatModelID = try container.decodeIfPresent(String.self, forKey: .codexChatModelID) ?? CodexChatModelCatalog.defaultModelID
        self.codexChatReasoningEffort = try container.decodeIfPresent(String.self, forKey: .codexChatReasoningEffort) ?? "medium"
        self.grokChatModelID = try container.decodeIfPresent(String.self, forKey: .grokChatModelID) ?? GrokChatModelCatalog.defaultModelID
        self.grokChatReasoningEffort = try container.decodeIfPresent(String.self, forKey: .grokChatReasoningEffort) ?? "medium"
        self.qwenChatModelID = try container.decodeIfPresent(String.self, forKey: .qwenChatModelID) ?? QwenChatModelCatalog.defaultModelID
        self.openrouterTranscriptionModel = try container.decodeIfPresent(String.self, forKey: .openrouterTranscriptionModel) ?? ""
        self.openrouterTranslationModel = try container.decodeIfPresent(String.self, forKey: .openrouterTranslationModel) ?? ""
        self.logLevel = try container.decodeIfPresent(LogLevel.self, forKey: .logLevel) ?? .info
        self.requireCanonicalNames = try container.decodeIfPresent(Bool.self, forKey: .requireCanonicalNames) ?? true
        self.favoriteCloudModelIDs = try container.decodeIfPresent([String].self, forKey: .favoriteCloudModelIDs) ?? []
    }

    public func transcriptionModel(for providerID: String) -> String {
        let trimmed = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == CloudProviderCatalog.openrouterID || trimmed == "openrouter" {
            let specific = openrouterTranscriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !specific.isEmpty { return specific }
            return openrouterModel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed == CloudProviderCatalog.qwenID {
            return qwenCloudModel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed == "gemini-cloud" {
            let m = geminiTextModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? "gemini-2.5-flash" : m
        }
        if trimmed == "gpt-cloud" {
            let m = openaiTextModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? "gpt-4o-mini" : m
        }
        return ""
    }

    public func translationModel(for providerID: String) -> String {
        let trimmed = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == CloudProviderCatalog.openrouterID || trimmed == "openrouter" {
            let specific = openrouterTranslationModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !specific.isEmpty { return specific }
            let base = openrouterModel.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowerBase = base.lowercased()
            let isDedicatedSTT = lowerBase.contains("whisper")
                || lowerBase.contains("stt")
                || lowerBase.contains("nova-3")
                || lowerBase.contains("parakeet")
                || lowerBase.contains("mai-transcribe")
                || lowerBase.contains("chirp")
                || lowerBase.contains("asr")
                || lowerBase.contains("voxtral-mini")
            return (base.isEmpty || isDedicatedSTT) ? "google/gemini-2.5-flash" : base
        }
        if trimmed == CloudProviderCatalog.qwenID {
            let m = qwenCloudModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? "qwen-max" : m
        }
        if trimmed == "gemini-cloud" {
            let m = geminiTextModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? "gemini-2.5-flash" : m
        }
        if trimmed == "gpt-cloud" {
            let m = openaiTextModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? "gpt-4o-mini" : m
        }
        return ""
    }
    public func isFavoriteModel(_ modelID: String) -> Bool {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return favoriteCloudModelIDs.contains(trimmed)
    }

    @discardableResult
    public mutating func toggleFavoriteModel(_ modelID: String) -> Set<String> {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Set(favoriteCloudModelIDs) }
        if let index = favoriteCloudModelIDs.firstIndex(of: trimmed) {
            favoriteCloudModelIDs.remove(at: index)
        } else {
            favoriteCloudModelIDs.append(trimmed)
        }
        return Set(favoriteCloudModelIDs)
    }

    public func sortedWithFavorites(_ models: [String]) -> [String] {
        let favs = Set(favoriteCloudModelIDs)
        return models.sorted { a, b in
            let aFav = favs.contains(a)
            let bFav = favs.contains(b)
            if aFav != bFav { return aFav }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    public func favoriteModels(for providerID: String) -> [String] {
        let trimmed = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "openrouter" || trimmed == CloudProviderCatalog.openrouterID {
            let current = transcriptionModel(for: "openrouter")
            let currentEffective = current.isEmpty ? "google/gemini-2.5-flash" : current
            var matching = favoriteCloudModelIDs.filter { $0.contains("/") }
            if matching.isEmpty {
                matching = ["google/gemini-2.5-flash", "openai/whisper-large-v3", "meta-llama/llama-3.3-70b-instruct"]
            }
            if !matching.contains(currentEffective) {
                matching.insert(currentEffective, at: 0)
            }
            return matching
        } else if trimmed == "gemini-cloud" || trimmed == CloudProviderCatalog.geminiID {
            let current = geminiTextModel.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentEffective = current.isEmpty ? "gemini-2.5-flash" : current
            var matching = favoriteCloudModelIDs.filter { $0.lowercased().contains("gemini") }
            if matching.isEmpty {
                matching = ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-1.5-flash", "gemini-1.5-pro"]
            }
            if !matching.contains(currentEffective) {
                matching.insert(currentEffective, at: 0)
            }
            return matching
        }
        return []
    }

    public func resolvedQwenBaseUrl(apiKey: String? = nil) -> String {
        let raw = qwenBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveKey = (apiKey ?? qwenApiKey).trimmingCharacters(in: .whitespacesAndNewlines)

        if !raw.isEmpty && raw != "https://dashscope-intl.aliyuncs.com/compatible-mode/v1" && raw != "https://dashscope-intl.aliyuncs.com/compatible-mode" {
            var clean = raw
            while clean.hasSuffix("/") { clean.removeLast() }
            return clean
        }

        if effectiveKey.hasPrefix("sk-sp-") || effectiveKey.hasPrefix("sk-ws-") {
            return "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
        }

        var clean = raw.isEmpty ? "https://dashscope-intl.aliyuncs.com/compatible-mode/v1" : raw
        while clean.hasSuffix("/") { clean.removeLast() }
        return clean
    }

    public var geminiKeyBank: GeminiAPIKeyBank {
        get {
            if geminiKeys.isEmpty && !geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return GeminiAPIKeyBank(primaryKey: geminiKey)
            }
            return GeminiAPIKeyBank(entries: geminiKeys)
        }
        set {
            geminiKeys = newValue.entries
            geminiKey = newValue.primaryKey
        }
    }

    public mutating func setGeminiKeyBank(_ bank: GeminiAPIKeyBank) {
        geminiKeyBank = bank
    }

    private mutating func syncGeminiPrimaryKeyFromBankIfNeeded() {
        let primary = GeminiAPIKeyBank(entries: geminiKeys).primaryKey
        if geminiKey != primary {
            geminiKey = primary
        }
    }

    private mutating func syncGeminiBankFromPrimaryKeyIfNeeded() {
        var bank = GeminiAPIKeyBank(entries: geminiKeys)
        if bank.primaryKey != geminiKey {
            bank.primaryKey = geminiKey
            if geminiKeys != bank.entries {
                geminiKeys = bank.entries
            }
        }
    }
    public static let defaults = AppSettings(
        geminiKey: "",
        openaiKey: "",
        anthropicKey: "",
        geminiBudgetUsd: 0,
        openaiBudgetUsd: 0,
        theme: .dark,
        fontSize: .md,
        fontScale: 1,
        fontFamily: .mono,
        chunkDurationMin: 10,
        sliceMode: .silence,
        silenceThreshDb: -16,
        minSilenceMs: 400,
        defaultSourceLang: "auto",
        transcriptionProvider: "coreml-whisperkit",
        translationProvider: "mlx-native",
        defaultTargetLang: "Russian",
        localAsrModels: [
            "whisper-small-en": LocalModelState(
                status: .notDownloaded,
                label: "Whisper Small English",
                runtime: .whisper
            ),
            "whisper-small-multilingual": LocalModelState(
                status: .notDownloaded,
                label: "Whisper Small Multilingual",
                runtime: .whisper
            ),
            "whisper-medium-en": LocalModelState(
                status: .notDownloaded,
                label: "Whisper Medium English",
                runtime: .whisper
            ),
            "whisper-medium-multilingual": LocalModelState(
                status: .notDownloaded,
                label: "Whisper Medium Multilingual",
                runtime: .whisper
            ),
            "whisper-large-v3-turbo": LocalModelState(
                status: .notDownloaded,
                label: "Whisper Large v3 Turbo",
                runtime: .whisper
            ),
            "whisper-large-v3": LocalModelState(
                status: .notDownloaded,
                label: "Whisper Large v3",
                runtime: .whisper
            ),
            "parakeet-tdt-06b-v3": LocalModelState(
                status: .notDownloaded,
                label: "Parakeet TDT 0.6B v3",
                runtime: .parakeet
            ),
            "canary-180m-flash-coreml": LocalModelState(
                status: .notDownloaded,
                label: "Canary Flash 180M",
                runtime: .canary
            ),
            "canary-1b-v2-coreml": LocalModelState(
                status: .notDownloaded,
                label: "Canary 1B v2",
                runtime: .canary
            ),
        ],
        localTranslationModels: [
            "qwen35-08b-4bit": LocalModelState(status: .notDownloaded, label: "Qwen 3.5 0.8B 4-bit", runtime: .mlx),
            "qwen35-2b-4bit": LocalModelState(status: .notDownloaded, label: "Qwen 3.5 2B 4-bit", runtime: .mlx),
            "qwen35-4b-4bit": LocalModelState(status: .notDownloaded, label: "Qwen 3.5 4B 4-bit", runtime: .mlx),
            "qwen35-9b-4bit": LocalModelState(status: .notDownloaded, label: "Qwen 3.5 9B 4-bit", runtime: .mlx),
            "nemotron3-nano-4b-4bit": LocalModelState(status: .notDownloaded, label: "NVIDIA Nemotron-3 Nano 4B", runtime: .mlx),
        ],
        promptPresets: DefaultPrompts.defaultPresets,
        usage: [:],
        glossary: StarterGlossary.entries,
        customCloudProviders: [],
        mediaResolverEndpoint: "",
        mediaResolverToken: "",
        mcpServerEnabled: false,
        mcpAllowMutatingTools: false,
        mcpAllowProcessingTools: false,
        mcpAllowFileTools: false,
        mcpAllowNetworkTools: false,
        mcpAllowDestructiveTools: false,
        mcpAccessToken: "",
        mcpPreferredAgentID: McpAgentProfileCatalog.defaultProfileID,
        codexChatModelID: CodexChatModelCatalog.defaultModelID,
        codexChatReasoningEffort: "medium",
        grokChatModelID: GrokChatModelCatalog.defaultModelID,
        grokChatReasoningEffort: "medium",
        qwenChatModelID: QwenChatModelCatalog.defaultModelID,
        favoriteCloudModelIDs: []
    )

    private static func mergeLocalASRDefaults(
        _ decodedModels: [String: LocalModelState]
    ) -> [String: LocalModelState] {
        mergeLocalModelMetadata(
            decodedModels,
            defaults: AppSettings.defaults.localAsrModels,
            overwriteMetadata: false
        )
    }

    private static func mergeLocalModelMetadata(
        _ decodedModels: [String: LocalModelState],
        defaults: [String: LocalModelState],
        overwriteMetadata: Bool
    ) -> [String: LocalModelState] {
        var merged = decodedModels
        for (id, defaultModel) in defaults {
            guard var model = merged[id] else {
                merged[id] = defaultModel
                continue
            }
            if overwriteMetadata {
                model.label = NativeModelCatalog.displayName(for: id) ?? defaultModel.label
                model.runtime = NativeModelCatalog.settingsRuntime(for: id) ?? defaultModel.runtime
                merged[id] = model
            }
        }
        return merged
    }
}

extension AppSettings {
    public static func generateMcpAccessToken(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: max(16, byteCount))
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return [UUID().uuidString, UUID().uuidString]
            .joined()
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }
    /// Reconciles persisted local-model metadata with the source catalog while
    /// retaining user-owned state such as status, progress, location and errors.
    public mutating func normalizeLocalModelMetadata() {
        localAsrModels = Self.mergeLocalModelMetadata(
            localAsrModels,
            defaults: AppSettings.defaults.localAsrModels,
            overwriteMetadata: true
        )
        localTranslationModels = Self.mergeLocalModelMetadata(
            localTranslationModels,
            defaults: AppSettings.defaults.localTranslationModels,
            overwriteMetadata: true
        )
    }


    public mutating func normalizeMcpSettings(generateToken: () -> String = { AppSettings.generateMcpAccessToken() }) {
        mcpAccessToken = mcpAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        mcpPreferredAgentID = McpAgentProfileCatalog.normalizedProfileID(mcpPreferredAgentID)
        codexChatModelID = CodexChatModelCatalog.normalizedModelID(codexChatModelID)
        codexChatReasoningEffort = CodexChatModelCatalog.normalizedReasoningEffort(
            modelID: codexChatModelID,
            effort: codexChatReasoningEffort
        )
        grokChatModelID = GrokChatModelCatalog.normalizedModelID(grokChatModelID)
        grokChatReasoningEffort = GrokChatModelCatalog.normalizedReasoningEffort(
            modelID: grokChatModelID,
            effort: grokChatReasoningEffort
        )
        qwenChatModelID = QwenChatModelCatalog.normalizedModelID(qwenChatModelID)
        if mcpServerEnabled, mcpAccessToken.isEmpty {
            mcpAccessToken = generateToken()
        }
        if !mcpServerEnabled {
            mcpAllowMutatingTools = false
            mcpAllowProcessingTools = false
            mcpAllowFileTools = false
            mcpAllowNetworkTools = false
            mcpAllowDestructiveTools = false
        }
    }

    public mutating func adaptGlossaryToTargetLanguage(targetLang: String) {
        let isRussian = targetLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "russian"
        for i in 0..<glossary.count {
            let entry = glossary[i]
            if let specificTranslation = entry.translations[targetLang], !specificTranslation.isEmpty {
                glossary[i].translation = specificTranslation
            } else if isRussian {
                glossary[i].translation = entry.translations["Russian"] ?? entry.translation
            } else {
                // Latin-based fallback: Sanskrit source with diacritics
                glossary[i].translation = entry.source
            }
        }
    }

    public func isDownloadedLocalASRModelActive(id: String) -> Bool {
        let candidateIDs: [String]
        if id == "coreml-whisperkit" {
            candidateIDs = NativeModelCatalog.whisperKitModelDescriptors.map(\.id)
        } else {
            candidateIDs = [id]
        }

        guard transcriptionProvider == id else { return false }

        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        for candidateID in candidateIDs {
            guard let model = localAsrModels[candidateID],
                  model.status == .downloaded,
                  let descriptor = NativeModelCatalog.descriptor(for: candidateID),
                  model.runtime == descriptor.settingsRuntime,
                  descriptor.capabilities.isAvailable(onMacOSMajor: osMajor),
                  let path = model.path,
                  !path.isEmpty
            else {
                continue
            }

            // UI/MainActor readiness is intentionally reference-only. The
            // actor-isolated router performs the authoritative package check.
            var isDirectory = ObjCBool(false)
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return true
            }
        }
        return false
    }

    public func isDownloadedLocalTranslationModelActive(id: String) -> Bool {
        translationProvider == id && localTranslationModels[id]?.status == .downloaded
    }

    public mutating func synchronizeLocalModelsWithDisk() {
        let supportedTranslationKeys = Set(AppSettings.defaults.localTranslationModels.keys)
        let supportedCloudTranslationKeys = Set(["gemini-cloud", "gpt-cloud"] + CloudProviderCatalog.providers.map(\.id) + customCloudProviders.map(\.id))
        localTranslationModels = localTranslationModels.filter { supportedTranslationKeys.contains($0.key) }
        if translationProvider != AppSettings.defaults.translationProvider,
           !supportedTranslationKeys.contains(translationProvider),
           !supportedCloudTranslationKeys.contains(translationProvider) {
            translationProvider = AppSettings.defaults.translationProvider
        }

        func resetToNotDownloaded(_ model: LocalModelState) -> LocalModelState {
            var updated = model
            updated.status = .notDownloaded
            updated.path = nil
            updated.progress = nil
            updated.progressLabel = nil
            updated.error = nil
            return updated
        }

        for (id, model) in localAsrModels {
            if model.status == .notDownloaded {
                localAsrModels[id] = resetToNotDownloaded(model)
                continue
            }

            guard let descriptor = NativeModelCatalog.descriptor(for: id),
                  model.runtime == descriptor.settingsRuntime
            else {
                continue
            }

            // An in-flight manager operation owns its staged directory. Do not
            // turn a progress update into a failed state before its atomic
            // replacement has completed.
            guard model.status != .downloading else { continue }

            let presentPath: String? = {
                guard let path = model.path, !path.isEmpty,
                      LocalASRPresencePolicy.isPresent(
                          descriptor,
                          at: URL(fileURLWithPath: path)
                      )
                else {
                    return nil
                }
                if descriptor.backend == .whisperKitCoreML {
                    return LocalModelVerification.canonicalWhisperKitModelPath(path) ?? path
                }
                return path
            }()

            if let presentPath {
                var ready = model
                ready.status = .downloaded
                ready.path = presentPath
                ready.progress = 1
                ready.progressLabel = ready.progressLabel ?? "Ready"
                ready.error = nil
                localAsrModels[id] = ready
            } else if model.status == .downloaded || model.status == .failed {
                // Preserve an external path/reference for migration, but never
                // leave an invalid or disappeared install in a Ready state.
                var failed = model
                failed.status = .failed
                failed.progress = nil
                failed.progressLabel = "Validation failed"
                failed.error = "Model files are incomplete or failed integrity validation."
                localAsrModels[id] = failed
            }
        }
        for (id, model) in localTranslationModels {
            if model.status == .notDownloaded {
                localTranslationModels[id] = resetToNotDownloaded(model)
            } else if model.status == .downloaded,
                      !LocalModelVerification.verifyTranslationModelPath(model.path, modelID: id) {
                localTranslationModels[id] = resetToNotDownloaded(model)
            }
        }
    }
}
