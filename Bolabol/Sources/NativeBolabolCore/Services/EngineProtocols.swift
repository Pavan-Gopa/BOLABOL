import Foundation

public struct EngineDiagnostics: Equatable, Sendable {
    public var backendName: String
    public var loadTimeMilliseconds: Int?
    public var tokensPerSecond: Double?
    public var memoryFootprintMB: Int?
    public var promptTokens: Int?
    public var completionTokens: Int?

    public init(
        backendName: String,
        loadTimeMilliseconds: Int? = nil,
        tokensPerSecond: Double? = nil,
        memoryFootprintMB: Int? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil
    ) {
        self.backendName = backendName
        self.loadTimeMilliseconds = loadTimeMilliseconds
        self.tokensPerSecond = tokensPerSecond
        self.memoryFootprintMB = memoryFootprintMB
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

public struct PolishingRequest: Equatable, Sendable {
    public var rawText: String
    public var variant: ProcessingVariant
    public var template: PromptTemplate

    public init(rawText: String, variant: ProcessingVariant, template: PromptTemplate) {
        self.rawText = rawText
        self.variant = variant
        self.template = template
    }
}

public struct PolishingResult: Equatable, Sendable {
    public var text: String
    public var diagnostics: EngineDiagnostics

    public init(text: String, diagnostics: EngineDiagnostics) {
        self.text = text
        self.diagnostics = diagnostics
    }
}

public protocol PolishingEngine: Sendable {
    var id: String { get }
    var displayName: String { get }

    func polish(_ request: PolishingRequest) async throws -> PolishingResult
}

public protocol ModelPreparingPolishingEngine: PolishingEngine {
    var preparationModelDirectory: URL { get }

    func preparationSnapshot() async -> ModelPreparationSnapshot
    func prepareModel(
        progress: @Sendable @escaping (ModelPreparationSnapshot) -> Void
    ) async -> ModelPreparationSnapshot
}

public struct TranscriptionRequest: Equatable, Sendable {
    public var audioFileURL: URL?
    public var forcedLanguageCode: String?
    /// Whisper-only native X-to-English task. Other engines reject this flag.
    public var translateToEnglish: Bool

    public init(
        audioFileURL: URL? = nil,
        forcedLanguageCode: String? = nil,
        translateToEnglish: Bool = false
    ) {
        self.audioFileURL = audioFileURL
        self.forcedLanguageCode = forcedLanguageCode
        self.translateToEnglish = translateToEnglish
    }
}

public struct TranscriptionResult: Equatable, Sendable {
    public var text: String
    public var diagnostics: EngineDiagnostics

    public init(text: String, diagnostics: EngineDiagnostics) {
        self.text = text
        self.diagnostics = diagnostics
    }
}

public protocol TranscriptionEngine: Sendable {
    var id: String { get }
    var displayName: String { get }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult
}
