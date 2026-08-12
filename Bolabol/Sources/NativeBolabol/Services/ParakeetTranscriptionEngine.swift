import FluidAudio
import Foundation
import NativeBolabolCore

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

        // FluidAudio's file converter lets CoreAudio downmix multichannel input.
        // Bolabol recordings can contain four discrete microphone channels,
        // which can cancel to silence during that downmix. Reuse the app's robust
        // preparation path: select the loudest physical channel first, then
        // resample that mono signal to Parakeet's required 16 kHz input.
        let normalizedAudioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bolabol-parakeet-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: normalizedAudioURL) }
        do {
            try GeminiCloudDictationEngine.convertTo16kMonoWAV(
                source: audioFileURL,
                destination: normalizedAudioURL
            )
        } catch {
            throw ParakeetTranscriptionError.audioPreparationFailed(
                error.localizedDescription
            )
        }

        let manager = try await loadedManager()
        var decoderState = TdtDecoderState.make(
            decoderLayers: await manager.decoderLayerCount
        )

        // Parakeet v3 detects the spoken language itself. A stale Whisper language
        // preference acts only as a script filter in FluidAudio; for example, an
        // Italian hint can suppress every Cyrillic token in Russian speech.
        // Only the route's explicit `languageHint` (anchored auto-detect for the
        // configured primary language) is mapped to a FluidAudio script filter;
        // anything else stays fully unanchored auto-detect.
        let languageFilter: Language? = request.languageHint.flatMap(Language.init(rawValue:))
        let result = try await manager.transcribe(
            normalizedAudioURL,
            decoderState: &decoderState,
            language: languageFilter
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

    /// Resets the loaded FluidAudio ASR manager. Parakeet keeps a cached internal
    /// language state between sessions. If a previous session carried an English
    /// hint, the manager will keep filtering Russian speech to English tokens even
    /// when a later session explicitly asks for unanchored auto-detect. We must
    /// explicitly tear down the manager to force clean auto-detect on the next run.
    func resetAsrManager() async {
        self.manager = nil
    }
}

private enum ParakeetTranscriptionError: LocalizedError {
    case missingAudioFile
    case translationUnsupported
    case audioPreparationFailed(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            "Parakeet needs a recorded or imported audio file."
        case .translationUnsupported:
            "Parakeet transcribes the source language but cannot translate speech to English. Choose a Whisper model for that routing mode."
        case .audioPreparationFailed(let detail):
            "Could not prepare audio for Parakeet: \(detail)"
        case .emptyResult:
            "Parakeet returned an empty transcription."
        }
    }
}
