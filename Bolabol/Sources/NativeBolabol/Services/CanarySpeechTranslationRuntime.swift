import Foundation
import NativeBolabolCore

/// Dedicated runtime for Canary speech translation.
///
/// The runtime owns a separate Canary engine instance and accepts only an
/// explicit source/target pair. It is deliberately not registered with
/// `TranscriptionEngineStore`, so selecting Canary here cannot change the
/// model, language, or session used by the main dictation path.
actor CanarySpeechTranslationRuntime: SpeechTranslationEngine {
    nonisolated let id: String
    nonisolated let displayName: String

    private let engine: CanaryCoreMLEngine

    init(model: TranscriptionModelDescriptor, modelFolderURL: URL) {
        self.id = "canary-speech-translation:\(model.id)"
        self.displayName = "Canary Speech Translation (\(model.displayName))"
        self.engine = CanaryCoreMLEngine(
            model: model,
            modelFolderURL: modelFolderURL
        )
    }

    func translate(_ request: SpeechTranslationRequest) async throws -> SpeechTranslationResult {
        let source = Self.normalizedLanguageCode(request.sourceLanguageCode)
        let target = Self.normalizedLanguageCode(request.targetLanguageCode)
        guard !source.isEmpty, !target.isEmpty else {
            throw CanarySpeechTranslationRuntimeError.emptyLanguagePair
        }

        let sourceResult = try await engine.transcribe(
            TranscriptionRequest(
                audioFileURL: request.audioFileURL,
                forcedLanguageCode: source,
                translateToEnglish: false,
                targetLanguageCode: source
            )
        )

        let translatedResult: TranscriptionResult
        if source == target {
            translatedResult = sourceResult
        } else {
            translatedResult = try await engine.transcribe(
                TranscriptionRequest(
                    audioFileURL: request.audioFileURL,
                    forcedLanguageCode: source,
                    translateToEnglish: target == "en",
                    targetLanguageCode: target
                )
            )
        }

        return SpeechTranslationResult(
            sourceText: sourceResult.text,
            translatedText: translatedResult.text,
            sourceDiagnostics: sourceResult.diagnostics,
            translationDiagnostics: translatedResult.diagnostics
        )
    }

    private static func normalizedLanguageCode(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum CanarySpeechTranslationRuntimeError: LocalizedError, Equatable {
    case emptyLanguagePair

    var errorDescription: String? {
        switch self {
        case .emptyLanguagePair:
            "Canary speech translation needs both a source and target language."
        }
    }
}

/// Main-actor cache for the translation-only runtimes. This cache is separate
/// from `TranscriptionEngineStore` and never changes the active dictation model.
@MainActor
final class CanarySpeechTranslationRuntimeStore {
    private var runtimes: [String: CanarySpeechTranslationRuntime] = [:]

    func runtime(for activeModel: ActiveTranscriptionModel) -> CanarySpeechTranslationRuntime {
        let key = [activeModel.model.id, activeModel.modelFolderURL.path].joined(separator: "|")
        if let runtime = runtimes[key] {
            return runtime
        }

        let runtime = CanarySpeechTranslationRuntime(
            model: activeModel.model,
            modelFolderURL: activeModel.modelFolderURL
        )
        runtimes[key] = runtime
        return runtime
    }
}
