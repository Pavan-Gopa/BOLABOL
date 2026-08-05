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

/// A speech-to-text translation request owned by a translation runtime.
///
/// This is intentionally separate from `TranscriptionRequest`: a translation
/// runtime has an explicit source/target pair and must not inherit the main
/// dictation session's language or model selection.
public struct SpeechTranslationRequest: Equatable, Sendable {
    public var audioFileURL: URL
    public var sourceLanguageCode: String
    public var targetLanguageCode: String

    public init(
        audioFileURL: URL,
        sourceLanguageCode: String,
        targetLanguageCode: String
    ) {
        self.audioFileURL = audioFileURL
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
    }
}

public struct SpeechTranslationResult: Equatable, Sendable {
    public var sourceText: String
    public var translatedText: String
    public var sourceDiagnostics: EngineDiagnostics
    public var translationDiagnostics: EngineDiagnostics

    public init(
        sourceText: String,
        translatedText: String,
        sourceDiagnostics: EngineDiagnostics,
        translationDiagnostics: EngineDiagnostics
    ) {
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceDiagnostics = sourceDiagnostics
        self.translationDiagnostics = translationDiagnostics
    }
}

public protocol SpeechTranslationEngine: Sendable {
    var id: String { get }
    var displayName: String { get }

    func translate(_ request: SpeechTranslationRequest) async throws -> SpeechTranslationResult
}

public struct TranscriptionRequest: Equatable, Sendable {
    public var audioFileURL: URL?
    public var forcedLanguageCode: String?
    /// When `true`, the engine should use Whisper's `translate` task to
    /// produce English output regardless of the spoken language.
    public var translateToEnglish: Bool
    /// Explicit speech-translation target for engines with directional AST
    /// capabilities, such as Canary. `nil` means ordinary ASR.
    public var targetLanguageCode: String?

    public init(
        audioFileURL: URL? = nil,
        forcedLanguageCode: String? = nil,
        translateToEnglish: Bool = false,
        targetLanguageCode: String? = nil
    ) {
        self.audioFileURL = audioFileURL
        self.forcedLanguageCode = forcedLanguageCode
        self.translateToEnglish = translateToEnglish
        self.targetLanguageCode = targetLanguageCode
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
