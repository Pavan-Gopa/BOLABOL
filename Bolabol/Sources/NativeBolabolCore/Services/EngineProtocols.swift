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
    /// Variant 2 humor slider level (0...100); nil when the slider is off or
    /// the variant carries no humor control. Engines may use it to modulate
    /// local sampling parameters; cloud engines ignore it.
    public var humorLevel: Int?

    public init(
        rawText: String,
        variant: ProcessingVariant,
        template: PromptTemplate,
        humorLevel: Int? = nil
    ) {
        self.rawText = rawText
        self.variant = variant
        self.template = template
        self.humorLevel = humorLevel
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
    /// Optional auto-detect orientation hint used by script-aware engines
    /// (Parakeet/FluidAudio). It never replaces Whisper's `forcedLanguageCode`
    /// and is nil for fully unanchored sessions.
    public var languageHint: String?

    public init(
        audioFileURL: URL? = nil,
        forcedLanguageCode: String? = nil,
        translateToEnglish: Bool = false,
        languageHint: String? = nil
    ) {
        self.audioFileURL = audioFileURL
        self.forcedLanguageCode = forcedLanguageCode
        self.translateToEnglish = translateToEnglish
        self.languageHint = languageHint
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
