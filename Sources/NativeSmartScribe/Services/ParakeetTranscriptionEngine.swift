import FluidAudio
import Foundation
import NativeSmartScribeCore

actor ParakeetTranscriptionEngine: TranscriptionEngine {
    nonisolated let id: String
    nonisolated let displayName: String

    private let model: TranscriptionModelDescriptor
    private let modelFolderURL: URL
    private var manager: AsrManager?

    init(
        model: TranscriptionModelDescriptor,
        modelFolderURL: URL
    ) {
        self.model = model
        self.modelFolderURL = modelFolderURL
        self.id = "parakeet-\(model.id)"
        self.displayName = "Parakeet Core ML/ANE (\(model.displayName))"
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        guard let audioFileURL = request.audioFileURL else {
            throw ParakeetTranscriptionError.missingAudioFile
        }
        guard !request.translateToEnglish else {
            throw ParakeetTranscriptionError.translationUnsupported
        }

        let manager = try await loadedManager()
        var decoderState = TdtDecoderState.make(
            decoderLayers: await manager.decoderLayerCount
        )
        let language = request.forcedLanguageCode
            .map { String($0.prefix(2)).lowercased() }
            .flatMap(Language.init(rawValue:))
        let result = try await manager.transcribe(
            audioFileURL,
            decoderState: &decoderState,
            language: language
        )
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ParakeetTranscriptionError.emptyResult
        }

        return TranscriptionResult(
            text: text,
            diagnostics: EngineDiagnostics(
                backendName: displayName,
                loadTimeMilliseconds: Int(result.processingTime * 1_000)
            )
        )
    }

    private func loadedManager() async throws -> AsrManager {
        if let manager {
            return manager
        }

        let models = try await AsrModels.load(
            from: modelFolderURL,
            version: .v3,
            encoderPrecision: .int8
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        return manager
    }
}

private enum ParakeetTranscriptionError: LocalizedError {
    case missingAudioFile
    case translationUnsupported
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            "Parakeet needs a recorded or imported audio file."
        case .translationUnsupported:
            "Parakeet transcribes the source language but cannot translate speech to English. Choose a Whisper model for that routing mode."
        case .emptyResult:
            "Parakeet returned an empty transcription."
        }
    }
}
