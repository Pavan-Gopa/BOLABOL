import Foundation

/// The model capabilities that affect document translation packing.
///
/// A document planner must receive these values from the selected provider/model;
/// it must not assume that every model has the same context window or output
/// contract. `recommended*` values are token targets for the literary profile,
/// not character limits. They keep a large-context model from making a whole
/// book into one request while the calculated capacity still enforces safety.
public struct TranslationModelCapabilities: Codable, Equatable, Sendable {
    public var modelID: String
    public var contextWindowTokens: Int
    public var maxOutputTokens: Int
    public var supportsStructuredOutput: Bool
    public var tokenizerAvailable: Bool
    public var fallbackCharactersPerToken: Double
    public var recommendedSoftSourceTokens: Int?
    public var recommendedHardSourceTokens: Int?

    public init(
        modelID: String = "cloud-default",
        contextWindowTokens: Int,
        maxOutputTokens: Int,
        supportsStructuredOutput: Bool = true,
        tokenizerAvailable: Bool = false,
        fallbackCharactersPerToken: Double = 4.0,
        recommendedSoftSourceTokens: Int? = nil,
        recommendedHardSourceTokens: Int? = nil
    ) {
        self.modelID = modelID
        self.contextWindowTokens = max(1, contextWindowTokens)
        self.maxOutputTokens = max(1, maxOutputTokens)
        self.supportsStructuredOutput = supportsStructuredOutput
        self.tokenizerAvailable = tokenizerAvailable
        self.fallbackCharactersPerToken = max(1.0, fallbackCharactersPerToken)
        self.recommendedSoftSourceTokens = recommendedSoftSourceTokens.map { max(1, $0) }
        self.recommendedHardSourceTokens = recommendedHardSourceTokens.map { max(1, $0) }
    }

    /// A conservative cloud profile for the first literary document slice.
    ///
    /// The source targets are deliberately expressed in tokens. They are
    /// bounded below the model's maximum context so prompt, glossary, rolling
    /// context, output expansion, and safety margin remain available.
    public static let cloudDefault = TranslationModelCapabilities(
        modelID: "cloud-default",
        contextWindowTokens: 32_768,
        maxOutputTokens: 8_192,
        supportsStructuredOutput: true,
        tokenizerAvailable: false,
        fallbackCharactersPerToken: 4.0,
        recommendedSoftSourceTokens: 1_950,
        recommendedHardSourceTokens: 2_650
    )

    public static let localDefault = TranslationModelCapabilities(
        modelID: "local-default",
        contextWindowTokens: 8_192,
        maxOutputTokens: 2_048,
        supportsStructuredOutput: true,
        tokenizerAvailable: false,
        fallbackCharactersPerToken: 4.0,
        recommendedSoftSourceTokens: 1_050,
        recommendedHardSourceTokens: 1_500
    )
}

/// Fixed prompt/context costs and target-language expansion used by a budget
/// calculation. All fields are explicit so tests and provider adapters can
/// account for their own prompt contract instead of sharing a global cap.
public struct TranslationBudgetConfiguration: Codable, Equatable, Sendable {
    public var promptTokens: Int
    public var glossaryTokens: Int
    public var rollingContextTokens: Int
    public var safetyMarginTokens: Int
    public var targetLanguageExpansion: Double

    public init(
        promptTokens: Int = 900,
        glossaryTokens: Int = 256,
        rollingContextTokens: Int = 384,
        safetyMarginTokens: Int = 512,
        targetLanguageExpansion: Double = 1.35
    ) {
        self.promptTokens = max(0, promptTokens)
        self.glossaryTokens = max(0, glossaryTokens)
        self.rollingContextTokens = max(0, rollingContextTokens)
        self.safetyMarginTokens = max(0, safetyMarginTokens)
        self.targetLanguageExpansion = max(1.0, targetLanguageExpansion.isFinite ? targetLanguageExpansion : 1.0)
    }

    public static let literaryDefault = TranslationBudgetConfiguration()
}

/// Arithmetic for one candidate source group.
public struct TranslationBudget: Equatable, Sendable {
    public let sourceTokenEstimate: Int
    public let reservedOutputTokens: Int
    public let promptTokens: Int
    public let glossaryTokens: Int
    public let rollingContextTokens: Int
    public let safetyMarginTokens: Int
    public let targetLanguageExpansion: Double
    public let usableContextTokens: Int
    public let hardSourceTokenLimit: Int
    public let softSourceTokenTarget: Int

    public var fixedInputTokens: Int {
        promptTokens + glossaryTokens + rollingContextTokens + safetyMarginTokens
    }

    public var totalReservedTokens: Int {
        fixedInputTokens + sourceTokenEstimate + reservedOutputTokens
    }

    public var fitsHardLimit: Bool {
        sourceTokenEstimate <= hardSourceTokenLimit && sourceTokenEstimate <= usableContextTokens
    }

    public init(
        sourceTokenEstimate: Int,
        reservedOutputTokens: Int,
        promptTokens: Int,
        glossaryTokens: Int,
        rollingContextTokens: Int,
        safetyMarginTokens: Int,
        targetLanguageExpansion: Double,
        usableContextTokens: Int,
        hardSourceTokenLimit: Int,
        softSourceTokenTarget: Int
    ) {
        self.sourceTokenEstimate = max(0, sourceTokenEstimate)
        self.reservedOutputTokens = max(0, reservedOutputTokens)
        self.promptTokens = max(0, promptTokens)
        self.glossaryTokens = max(0, glossaryTokens)
        self.rollingContextTokens = max(0, rollingContextTokens)
        self.safetyMarginTokens = max(0, safetyMarginTokens)
        self.targetLanguageExpansion = max(1.0, targetLanguageExpansion)
        self.usableContextTokens = max(0, usableContextTokens)
        self.hardSourceTokenLimit = max(1, hardSourceTokenLimit)
        self.softSourceTokenTarget = max(1, softSourceTokenTarget)
    }
}

/// The measured size of one fully rendered provider prompt.
///
/// Unlike the source-packing budget above, this value is calculated from the
/// actual serialized prompt text. It lets a provider adapter reject an
/// oversized request after optional context has been trimmed without imposing
/// a blind character cap on every document.
public struct TranslationPromptBudget: Equatable, Sendable {
    public let serializedPromptCharacters: Int
    public let estimatedPromptTokens: Int
    public let sourceTokenEstimate: Int
    public let reservedOutputTokens: Int
    public let safetyMarginTokens: Int
    public let totalEstimatedTokens: Int
    public let contextWindowTokens: Int
    public let maxOutputTokens: Int

    public var fits: Bool {
        totalEstimatedTokens <= contextWindowTokens
    }

    public init(
        serializedPromptCharacters: Int,
        estimatedPromptTokens: Int,
        sourceTokenEstimate: Int,
        reservedOutputTokens: Int,
        safetyMarginTokens: Int,
        contextWindowTokens: Int,
        maxOutputTokens: Int
    ) {
        self.serializedPromptCharacters = max(0, serializedPromptCharacters)
        self.estimatedPromptTokens = max(0, estimatedPromptTokens)
        self.sourceTokenEstimate = max(0, sourceTokenEstimate)
        self.reservedOutputTokens = max(0, reservedOutputTokens)
        self.safetyMarginTokens = max(0, safetyMarginTokens)
        self.totalEstimatedTokens = max(
            0,
            estimatedPromptTokens + reservedOutputTokens + safetyMarginTokens
        )
        self.contextWindowTokens = max(1, contextWindowTokens)
        self.maxOutputTokens = max(1, maxOutputTokens)
    }
}

/// Computes provider-aware source budgets and deterministic token estimates.
public struct TranslationBudgetPlanner: Sendable {
    public typealias Capabilities = TranslationModelCapabilities
    public typealias Configuration = TranslationBudgetConfiguration
    public typealias Tokenizer = @Sendable (String) -> Int

    public let capabilities: TranslationModelCapabilities
    public let configuration: TranslationBudgetConfiguration
    private let tokenizer: Tokenizer?

    public init(
        capabilities: TranslationModelCapabilities = .cloudDefault,
        configuration: TranslationBudgetConfiguration = .literaryDefault,
        tokenizer: Tokenizer? = nil
    ) {
        self.capabilities = capabilities
        self.configuration = configuration
        self.tokenizer = tokenizer
    }

    /// Estimate source tokens with a real tokenizer when one is available.
    ///
    /// The bounded fallback is intentionally conservative and documented: it
    /// uses Unicode scalar count divided by a configured character/token ratio,
    /// never returns zero for non-empty text, and clamps input length before
    /// integer conversion. It is an estimator only; hard packing decisions are
    /// still made from model token capacity and not from a global character cap.
    public func estimateTokens(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        if capabilities.tokenizerAvailable, let tokenizer {
            return max(1, tokenizer(trimmed))
        }

        let scalarCount = min(trimmed.unicodeScalars.count, 8_000_000)
        let characterEstimate = Int(ceil(Double(scalarCount) / capabilities.fallbackCharactersPerToken))
        let wordEstimate = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return max(1, min(4_000_000, max(characterEstimate, wordEstimate)))
    }

    /// Measures a rendered request against the selected model's context
    /// window. The serialized prompt is counted as-is; only the output
    /// reservation and configured safety margin are estimated.
    public func promptBudget(
        for prompt: String,
        sourceText: String
    ) -> TranslationPromptBudget {
        let sourceTokens = estimateTokens(sourceText)
        let reservedOutputTokens = sourceTokens == 0
            ? 0
            : min(
                capabilities.maxOutputTokens,
                max(1, Int(ceil(Double(sourceTokens) * configuration.targetLanguageExpansion)))
            )
        return TranslationPromptBudget(
            serializedPromptCharacters: prompt.count,
            estimatedPromptTokens: estimateTokens(prompt),
            sourceTokenEstimate: sourceTokens,
            reservedOutputTokens: reservedOutputTokens,
            safetyMarginTokens: configuration.safetyMarginTokens,
            contextWindowTokens: capabilities.contextWindowTokens,
            maxOutputTokens: capabilities.maxOutputTokens
        )
    }

    public func budget(forSourceTokenEstimate sourceTokenEstimate: Int) -> TranslationBudget {
        budget(for: TranslationBudgetRequest(
            sourceTokenEstimate: sourceTokenEstimate,
            configuration: configuration
        ))
    }

    public func budget(forSourceText text: String) -> TranslationBudget {
        budget(forSourceTokenEstimate: estimateTokens(text))
    }

    public func budget(for request: TranslationBudgetRequest) -> TranslationBudget {
        let source = max(0, request.sourceTokenEstimate)
        let expansion = max(1.0, request.targetLanguageExpansion.isFinite ? request.targetLanguageExpansion : 1.0)
        let prompt = max(0, request.promptTokens)
        let glossary = max(0, request.glossaryTokens)
        let rollingContext = max(0, request.rollingContextTokens)
        let safety = max(0, request.safetyMarginTokens)
        let fixed = prompt + glossary + rollingContext + safety
        let reservedOutput = source == 0
            ? 0
            : min(capabilities.maxOutputTokens, max(1, Int(ceil(Double(source) * expansion))))

        let usableContext = max(0, capabilities.contextWindowTokens - fixed - reservedOutput)
        let contextCapacity = max(1, Int(floor(Double(max(1, capabilities.contextWindowTokens - fixed)) / (1.0 + expansion))))
        let outputCapacity = max(1, Int(floor(Double(capabilities.maxOutputTokens) / expansion)))
        let calculatedHardLimit = min(contextCapacity, outputCapacity)
        let hardLimit = max(1, min(calculatedHardLimit, capabilities.recommendedHardSourceTokens ?? calculatedHardLimit))
        let defaultSoftTarget = max(1, Int(Double(hardLimit) * 0.74))
        let softTarget = max(1, min(hardLimit, capabilities.recommendedSoftSourceTokens ?? defaultSoftTarget))

        return TranslationBudget(
            sourceTokenEstimate: source,
            reservedOutputTokens: reservedOutput,
            promptTokens: prompt,
            glossaryTokens: glossary,
            rollingContextTokens: rollingContext,
            safetyMarginTokens: safety,
            targetLanguageExpansion: expansion,
            usableContextTokens: usableContext,
            hardSourceTokenLimit: hardLimit,
            softSourceTokenTarget: softTarget
        )
    }


    public static func estimateTokens(
        _ text: String,
        capabilities: TranslationModelCapabilities = .cloudDefault,
        tokenizer: Tokenizer? = nil
    ) -> Int {
        TranslationBudgetPlanner(
            capabilities: capabilities,
            tokenizer: tokenizer
        ).estimateTokens(text)
    }
    public static func budget(
        forSourceTokenEstimate sourceTokenEstimate: Int,
        capabilities: TranslationModelCapabilities = .cloudDefault,
        configuration: TranslationBudgetConfiguration = .literaryDefault
    ) -> TranslationBudget {
        TranslationBudgetPlanner(
            capabilities: capabilities,
            configuration: configuration
        ).budget(forSourceTokenEstimate: sourceTokenEstimate)
    }

    public static func estimateSourceTokens(
        _ text: String,
        capabilities: TranslationModelCapabilities = .cloudDefault,
        tokenizer: Tokenizer? = nil
    ) -> Int {
        estimateTokens(text, capabilities: capabilities, tokenizer: tokenizer)
    }
}

/// A request keeps the arithmetic inputs visible to provider adapters and tests.
public struct TranslationBudgetRequest: Equatable, Sendable {
    public var sourceTokenEstimate: Int
    public var promptTokens: Int
    public var glossaryTokens: Int
    public var rollingContextTokens: Int
    public var safetyMarginTokens: Int
    public var targetLanguageExpansion: Double

    public init(
        sourceTokenEstimate: Int,
        promptTokens: Int = 900,
        glossaryTokens: Int = 256,
        rollingContextTokens: Int = 384,
        safetyMarginTokens: Int = 512,
        targetLanguageExpansion: Double = 1.35
    ) {
        self.sourceTokenEstimate = max(0, sourceTokenEstimate)
        self.promptTokens = max(0, promptTokens)
        self.glossaryTokens = max(0, glossaryTokens)
        self.rollingContextTokens = max(0, rollingContextTokens)
        self.safetyMarginTokens = max(0, safetyMarginTokens)
        self.targetLanguageExpansion = max(1.0, targetLanguageExpansion.isFinite ? targetLanguageExpansion : 1.0)
    }

    public init(sourceTokenEstimate: Int, configuration: TranslationBudgetConfiguration) {
        self.init(
            sourceTokenEstimate: sourceTokenEstimate,
            promptTokens: configuration.promptTokens,
            glossaryTokens: configuration.glossaryTokens,
            rollingContextTokens: configuration.rollingContextTokens,
            safetyMarginTokens: configuration.safetyMarginTokens,
            targetLanguageExpansion: configuration.targetLanguageExpansion
        )
    }
}
