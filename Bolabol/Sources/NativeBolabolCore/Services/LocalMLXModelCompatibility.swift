public struct LocalMLXModelMetadata: Equatable, Sendable {
    public var directoryName: String
    public var repositoryID: String?
    public var architectures: [String]
    public var modelType: String?
    public var modelName: String?
    public var nameOrPath: String?
    public var hasTextConfig: Bool
    public var hasVisionConfig: Bool
    public var processorClass: String?
    public var tokenizerClass: String?
    public var eosToken: String?
    public var padToken: String?
    public var hasChatTemplate: Bool
    public var chatTemplateStartsThinking: Bool
    public var quantizationGroupSize: Int?

    public init(
        directoryName: String,
        repositoryID: String?,
        architectures: [String],
        modelType: String?,
        modelName: String?,
        nameOrPath: String?,
        hasTextConfig: Bool,
        hasVisionConfig: Bool,
        processorClass: String?,
        tokenizerClass: String?,
        eosToken: String?,
        padToken: String?,
        hasChatTemplate: Bool,
        chatTemplateStartsThinking: Bool,
        quantizationGroupSize: Int? = nil
    ) {
        self.directoryName = directoryName
        self.repositoryID = repositoryID
        self.architectures = architectures
        self.modelType = modelType
        self.modelName = modelName
        self.nameOrPath = nameOrPath
        self.hasTextConfig = hasTextConfig
        self.hasVisionConfig = hasVisionConfig
        self.processorClass = processorClass
        self.tokenizerClass = tokenizerClass
        self.eosToken = eosToken
        self.padToken = padToken
        self.hasChatTemplate = hasChatTemplate
        self.chatTemplateStartsThinking = chatTemplateStartsThinking
        self.quantizationGroupSize = quantizationGroupSize
    }
}

public struct LocalMLXModelCompatibilityResult: Equatable, Sendable {
    public var isSupported: Bool
    public var profile: LocalMLXModelCompatibilityProfile?
    public var reason: String?

    public init(
        isSupported: Bool,
        profile: LocalMLXModelCompatibilityProfile? = nil,
        reason: String? = nil
    ) {
        self.isSupported = isSupported
        self.profile = profile
        self.reason = reason
    }

    public static func supported(
        _ profile: LocalMLXModelCompatibilityProfile
    ) -> LocalMLXModelCompatibilityResult {
        LocalMLXModelCompatibilityResult(isSupported: true, profile: profile)
    }

    public static func unsupported(_ reason: String) -> LocalMLXModelCompatibilityResult {
        LocalMLXModelCompatibilityResult(isSupported: false, reason: reason)
    }
}

public enum LocalMLXModelCompatibilityProfile: String, Equatable, Sendable {
    case standardTextGeneration
    case standardChatTemplate
    case reasoningChatTemplate
    case customChatTemplate
}

public enum LocalMLXModelCompatibility {
    public static func evaluate(
        _ metadata: LocalMLXModelMetadata
    ) -> LocalMLXModelCompatibilityResult {
        // Enforce quantization group size limits for Metal backend
        if let groupSize = metadata.quantizationGroupSize {
            let supportedSizes = [32, 64, 128]
            if !supportedSizes.contains(groupSize) {
                return .unsupported("Metal only supports quantization group sizes of 32, 64, and 128 (found \(groupSize)).")
            }
        }

        let searchableName = [
            metadata.directoryName,
            metadata.repositoryID,
            metadata.modelName,
            metadata.nameOrPath
        ]
            .compactMap(\.self)
            .joined(separator: " ")
            .lowercased()

        let architectures = metadata.architectures.map { $0.lowercased() }
        let modelType = metadata.modelType?.lowercased() ?? ""

        // Explicitly support any Gemma model variant (Gemma, Gemma 2, Gemma 3, Gemma 4, etc.)
        if modelType.contains("gemma") || architectures.contains(where: { $0.contains("gemma") }) {
            if isReasoningModel(metadata, searchableName: searchableName) {
                return .supported(.reasoningChatTemplate)
            }
            return metadata.hasChatTemplate
                ? .supported(.standardChatTemplate)
                : .supported(.standardTextGeneration)
        }

        if architectures.contains(where: { $0.contains("forcausallm") }) {
            if isReasoningModel(metadata, searchableName: searchableName) {
                return .supported(.reasoningChatTemplate)
            }
            return metadata.hasChatTemplate
                ? .supported(.standardChatTemplate)
                : .supported(.standardTextGeneration)
        }

        if architectures.contains(where: { $0.contains("forconditionalgeneration") }),
           modelType.contains("qwen3_5") || modelType.contains("qwen3.5") {
            if isReasoningModel(metadata, searchableName: searchableName) {
                return .supported(.reasoningChatTemplate)
            }
            return metadata.hasChatTemplate
                ? .supported(.customChatTemplate)
                : .supported(.standardChatTemplate)
        }

        if architectures.contains(where: { $0.contains("forconditionalgeneration") }) {
            if metadata.hasChatTemplate {
                return .supported(.customChatTemplate)
            }
            return .unsupported("Conditional-generation models need a chat template for local text polishing.")
        }

        return .unsupported("Only text-generation MLX models are supported for local polishing.")
    }

    private static func isReasoningModel(
        _ metadata: LocalMLXModelMetadata,
        searchableName: String
    ) -> Bool {
        metadata.chatTemplateStartsThinking
            || searchableName.contains("qwopus")
            || searchableName.contains("gemopus")
            || searchableName.contains("reasoning")
            || searchableName.contains("opus")
    }
}
