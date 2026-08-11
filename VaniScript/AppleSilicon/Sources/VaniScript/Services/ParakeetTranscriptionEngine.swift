import FluidAudio
import Foundation
import VaniScriptCore

/// Injectable model-session seam used by Parakeet and by tests without Core ML weights.
protocol ParakeetTranscriptionSession: Sendable {
    func transcribe(audioFileURL: URL, language: Language?) async throws -> String
    func unload() async
}

typealias ParakeetSessionLoader = @Sendable (URL) async throws -> any ParakeetTranscriptionSession

private actor FluidAudioParakeetSession: ParakeetTranscriptionSession {
    private var manager: AsrManager?

    init(manager: AsrManager) {
        self.manager = manager
    }

    func transcribe(audioFileURL: URL, language: Language?) async throws -> String {
        guard let manager else {
            throw LocalASREngineError.inferenceFailed("The Parakeet model is unloaded.")
        }

        let decoderLayers = await manager.decoderLayerCount
        var requestState: TdtDecoderState
        do {
            requestState = try TdtDecoderState(decoderLayers: decoderLayers)
        } catch {
            throw LocalASREngineError.decoderStateInitializationFailed(
                error.localizedDescription
            )
        }

        let result = try await manager.transcribe(
            audioFileURL,
            decoderState: &requestState,
            language: language
        )
        return result.text
    }

    func unload() {
        manager = nil
    }
}

private let defaultParakeetSessionLoader: ParakeetSessionLoader = { modelFolderURL in
    let models = try await AsrModels.load(
        from: modelFolderURL,
        version: .v3,
        encoderPrecision: .int8
    )
    let manager = AsrManager(config: .default)
    try await manager.loadModels(models)
    return FluidAudioParakeetSession(manager: manager)
}

/// FluidAudio v3/int8 local transcription with one resident model session.
///
/// The descriptor and model path are supplied by the catalog/download layer. This
/// engine validates that binding before loading and never invokes a downloader.
actor ParakeetTranscriptionEngine: LocalASREngine {
    nonisolated let descriptor: LocalASRModelDescriptor

    private let modelFolderURL: URL
    private let audioPreprocessor: LocalASRAudioPreprocessor
    private let fileManager: FileManager
    private let temporaryDirectory: URL
    private let sessionLoader: ParakeetSessionLoader
    private var session: (any ParakeetTranscriptionSession)?

    init(
        model: LocalASRModelDescriptor,
        modelFolderURL: URL,
        audioPreprocessor: LocalASRAudioPreprocessor = LocalASRAudioPreprocessor(),
        fileManager: FileManager = .default,
        temporaryDirectory: URL? = nil,
        sessionLoader: @escaping ParakeetSessionLoader = defaultParakeetSessionLoader
    ) {
        self.descriptor = model
        self.modelFolderURL = modelFolderURL
        self.audioPreprocessor = audioPreprocessor
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory ?? fileManager.temporaryDirectory
        self.sessionLoader = sessionLoader
    }

    func transcribe(_ request: LocalASRRequest) async throws -> LocalASRResult {
        try Task.checkCancellation()
        guard let sourceURL = request.audioFileURL else {
            throw LocalASREngineError.missingAudioFile
        }
        guard !request.translateToEnglish else {
            throw LocalASREngineError.translationUnsupported
        }
        try validateModelBinding()

        let normalizedAudioURL = temporaryDirectory.appendingPathComponent(
            "vaniscript-local-asr-\(UUID().uuidString).wav"
        )
        defer {
            try? fileManager.removeItem(at: normalizedAudioURL)
        }

        do {
            try audioPreprocessor.convertTo16kMonoWAV(
                source: sourceURL,
                destination: normalizedAudioURL
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LocalASREngineError.audioPreparationFailed(error.localizedDescription)
        }

        try Task.checkCancellation()
        let session = try await loadedSession()
        try Task.checkCancellation()

        let language = mappedLanguage(from: request.languageHint)
        let rawText: String
        do {
            rawText = try await session.transcribe(
                audioFileURL: normalizedAudioURL,
                language: language
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LocalASREngineError {
            throw error
        } catch {
            throw LocalASREngineError.inferenceFailed(error.localizedDescription)
        }

        try Task.checkCancellation()
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw LocalASREngineError.emptyResult
        }
        return LocalASRResult(text: text)
    }

    func unload() async {
        guard let session else { return }
        self.session = nil
        await session.unload()
    }

    private func loadedSession() async throws -> any ParakeetTranscriptionSession {
        if let session {
            return session
        }

        try validateModelBinding()
        do {
            let loaded = try await sessionLoader(modelFolderURL)
            session = loaded
            return loaded
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LocalASREngineError {
            throw error
        } catch {
            throw LocalASREngineError.inferenceFailed(
                "Could not load the Parakeet model: \(error.localizedDescription)"
            )
        }
    }

    private func validateModelBinding() throws {
        guard descriptor.backend == .fluidAudioCoreML else {
            throw LocalASREngineError.unsupportedModel(
                "expected the FluidAudio Core ML backend"
            )
        }
        guard case let .fluidAudio(version, encoderPrecision) = descriptor.installSource,
              version == "v3",
              encoderPrecision.lowercased() == "int8"
        else {
            throw LocalASREngineError.unsupportedModel(
                "expected FluidAudio v3/int8 model metadata"
            )
        }
        guard NativeModelCatalog.isModelPresent(
            descriptor,
            at: modelFolderURL,
            fileManager: fileManager
        ) else {
            throw LocalASREngineError.modelUnavailable(modelFolderURL)
        }
    }

    /// FluidAudio's language hint is a script filter, not a forced recognizer
    /// language. Only a catalog-supported explicit code is passed through; auto,
    /// empty, malformed, and unsupported hints preserve model auto-detection.
    private func mappedLanguage(from hint: String?) -> Language? {
        guard let hint else { return nil }
        let normalized = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "auto" else { return nil }

        let supported = Set(
            descriptor.capabilities.supportedLanguageCodes.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )
        guard supported.contains(normalized) else { return nil }
        return Language(rawValue: normalized)
    }
}
