import Foundation
import NativeSmartScribeCore
import WhisperKit

// WhisperKit is held behind this actor and is only touched through actor-isolated
// methods, so access is serialized even though the upstream class is not Sendable.
extension WhisperKit: @unchecked @retroactive Sendable {}

actor WhisperKitTranscriptionEngine: TranscriptionEngine {
    nonisolated let id: String
    nonisolated let displayName: String
    nonisolated let model: TranscriptionModelDescriptor
    nonisolated let modelFolderURL: URL

    private var pipeline: WhisperKit?

    init(
        model: TranscriptionModelDescriptor,
        modelFolderURL: URL
    ) {
        self.id = "whisperkit-coreml-\(model.id)"
        self.displayName = "WhisperKit Core ML (\(model.displayName))"
        self.model = model
        self.modelFolderURL = modelFolderURL
    }

    func transcribe(
        _ request: NativeSmartScribeCore.TranscriptionRequest
    ) async throws -> NativeSmartScribeCore.TranscriptionResult {
        guard let audioFileURL = request.audioFileURL else {
            throw WhisperKitTranscriptionError.missingAudioFile
        }

        let startedAt = Date()
        let pipeline = try await loadedPipeline()
        let results = try await pipeline.transcribe(
            audioPath: audioFileURL.path,
            decodeOptions: decodeOptions(for: request)
        )
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokensPerSecond = results
            .map(\.timings.tokensPerSecond)
            .filter { $0.isFinite && $0 > 0 }
            .average

        guard !text.isEmpty else {
            throw WhisperKitTranscriptionError.emptyResult
        }

        return NativeSmartScribeCore.TranscriptionResult(
            text: text,
            diagnostics: NativeSmartScribeCore.EngineDiagnostics(
                backendName: displayName,
                loadTimeMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000),
                tokensPerSecond: tokensPerSecond
            )
        )
    }

    private func loadedPipeline() async throws -> WhisperKit {
        if let pipeline {
            return pipeline
        }

        let config = WhisperKitConfig(
            model: model.modelName,
            modelRepo: model.modelRepositoryID,
            modelFolder: modelFolderURL.path,
            verbose: false,
            prewarm: false,
            load: true,
            download: false
        )
        let pipeline = try await WhisperKit(config)
        self.pipeline = pipeline
        return pipeline
    }

    private func decodeOptions(
        for request: NativeSmartScribeCore.TranscriptionRequest
    ) -> DecodingOptions {
        // WhisperKit's `language` field means "language spoken in the audio" (source),
        // NOT the output/target language. When translating to English via `.translate`,
        // we must let Whisper auto-detect the source language — passing "en" would
        // incorrectly tell Whisper the audio is already in English.
        let normalizedLanguage: String?
        if request.translateToEnglish {
            // Auto-detect source language for translation
            normalizedLanguage = nil
        } else {
            normalizedLanguage = request.forcedLanguageCode?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        // Use Whisper's native translate task when English output is requested.
        // Whisper can translate from any supported language → English natively.
        let task: DecodingTask = request.translateToEnglish ? .translate : .transcribe

        return DecodingOptions(
            verbose: false,
            task: task,
            language: normalizedLanguage?.isEmpty == false ? normalizedLanguage : nil,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: normalizedLanguage?.isEmpty != false,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: false
        )
    }
}

private extension [Double] {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

private enum WhisperKitTranscriptionError: LocalizedError {
    case missingAudioFile
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            AppText.localized(.missingAudioFileForTranscription, language: .english)
        case .emptyResult:
            AppText.localized(.whisperReturnedEmptyTranscript, language: .english)
        }
    }
}
