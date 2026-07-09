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
        self.location = try container.decodeIfPresent(SharedModelLocation.self, forKey: .location)
        if let location {
            self.path = SharedModelsRoot.modelURL(for: location).path
        } else {
            self.path = try container.decodeIfPresent(String.self, forKey: .path)
            self.location = Self.location(for: path)
        }
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
        self.runtime = try container.decode(LocalModelRuntime.self, forKey: .runtime)
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

    public init(
        sessions: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        audioMinutes: Double = 0,
        lastUsed: String = "",
        lastInputTokens: Int? = nil,
        lastOutputTokens: Int? = nil
    ) {
        self.sessions = sessions
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.audioMinutes = audioMinutes
        self.lastUsed = lastUsed
        self.lastInputTokens = lastInputTokens
        self.lastOutputTokens = lastOutputTokens
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
    public var geminiKey: String
    public var openaiKey: String
    public var anthropicKey: String
    public var geminiBudgetUsd: Double
    public var openaiBudgetUsd: Double
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
    public var mcpAccessToken: String
    public var mcpPreferredAgentID: String
    public var logLevel: LogLevel

    private enum CodingKeys: String, CodingKey {
        case geminiKey, openaiKey, anthropicKey
        case geminiBudgetUsd, openaiBudgetUsd
        case theme, fontSize, fontScale, fontFamily
        case chunkDurationMin, sliceMode, silenceThreshDb, minSilenceMs
        case defaultSourceLang, transcriptionProvider, translationProvider, defaultTargetLang
        case localAsrModels, localTranslationModels, promptPresets, usage, glossary, customCloudProviders
        case hasCompletedOnboarding, completedOnboardingBuildID
        case mediaResolverEndpoint, mediaResolverToken
        case mcpServerEnabled, mcpAllowMutatingTools, mcpAccessToken, mcpPreferredAgentID
        case logLevel
    }

    public init(
        geminiKey: String,
        openaiKey: String,
        anthropicKey: String,
        geminiBudgetUsd: Double,
        openaiBudgetUsd: Double,
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
        mcpAccessToken: String = "",
        mcpPreferredAgentID: String = McpAgentProfileCatalog.defaultProfileID,
        logLevel: LogLevel = .info
    ) {
        self.geminiKey = geminiKey
        self.openaiKey = openaiKey
        self.anthropicKey = anthropicKey
        self.geminiBudgetUsd = geminiBudgetUsd
        self.openaiBudgetUsd = openaiBudgetUsd
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
        self.mcpAccessToken = mcpAccessToken
        self.mcpPreferredAgentID = mcpPreferredAgentID
        self.logLevel = logLevel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.geminiKey = try container.decodeIfPresent(String.self, forKey: .geminiKey) ?? ""
        self.openaiKey = try container.decodeIfPresent(String.self, forKey: .openaiKey) ?? ""
        self.anthropicKey = try container.decodeIfPresent(String.self, forKey: .anthropicKey) ?? ""
        self.geminiBudgetUsd = try container.decodeIfPresent(Double.self, forKey: .geminiBudgetUsd) ?? 0
        self.openaiBudgetUsd = try container.decodeIfPresent(Double.self, forKey: .openaiBudgetUsd) ?? 0
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
        self.localAsrModels = try container.decodeIfPresent([String: LocalModelState].self, forKey: .localAsrModels) ?? AppSettings.defaults.localAsrModels
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
        self.mcpAccessToken = try container.decodeIfPresent(String.self, forKey: .mcpAccessToken) ?? ""
        self.mcpPreferredAgentID = try container.decodeIfPresent(String.self, forKey: .mcpPreferredAgentID) ?? McpAgentProfileCatalog.defaultProfileID
        self.logLevel = try container.decodeIfPresent(LogLevel.self, forKey: .logLevel) ?? .info
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
        ],
        localTranslationModels: [
            "qwen35-08b-4bit": LocalModelState(status: .notDownloaded, label: "Qwen 3.5 0.8B 4bit", runtime: .mlx),
            "qwen35-2b-4bit": LocalModelState(status: .notDownloaded, label: "Qwen 3.5 2B 4bit", runtime: .mlx),
            "qwen35-4b-4bit": LocalModelState(status: .notDownloaded, label: "Qwen 3.5 4B 4bit", runtime: .mlx),
            "qwen35-9b-4bit": LocalModelState(status: .notDownloaded, label: "Qwen 3.5 9B 4bit", runtime: .mlx),
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
        mcpAccessToken: "",
        mcpPreferredAgentID: McpAgentProfileCatalog.defaultProfileID
    )
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

    public mutating func normalizeMcpSettings(generateToken: () -> String = { AppSettings.generateMcpAccessToken() }) {
        mcpAccessToken = mcpAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        mcpPreferredAgentID = McpAgentProfileCatalog.normalizedProfileID(mcpPreferredAgentID)
        if mcpServerEnabled, mcpAccessToken.isEmpty {
            mcpAccessToken = generateToken()
        }
        if !mcpServerEnabled {
            mcpAllowMutatingTools = false
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
        transcriptionProvider == id && localAsrModels[id]?.status == .downloaded
    }

    public func isDownloadedLocalTranslationModelActive(id: String) -> Bool {
        translationProvider == id && localTranslationModels[id]?.status == .downloaded
    }

    public mutating func synchronizeLocalModelsWithDisk() {
        let supportedTranslationKeys = Set(AppSettings.defaults.localTranslationModels.keys)
        let supportedCloudTranslationKeys = Set(["gemini-cloud", "gpt-cloud"] + customCloudProviders.map(\.id))
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
            } else if model.status == .downloaded,
                      !LocalModelVerification.verifyModelPath(model.path, isWhisper: true) {
                localAsrModels[id] = resetToNotDownloaded(model)
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
