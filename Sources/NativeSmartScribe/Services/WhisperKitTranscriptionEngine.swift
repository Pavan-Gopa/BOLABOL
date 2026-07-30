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
        let options = await resolveDecodingOptions(for: request, pipeline: pipeline, audioPath: audioFileURL.path)
        let results = try await pipeline.transcribe(
            audioPath: audioFileURL.path,
            decodeOptions: options
        )
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokensPerSecond = results
            .map(\.timings.tokensPerSecond)
            .filter { $0.isFinite && $0 > 0 }
            .average
        let resultLanguages = results.map(\.language).joined(separator: ",")
        let preview = String(text.prefix(80))
        let hasCyrillic = text.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil
        NativeSmartScribeLog.transcription.info(
            "WhisperKit result translateToEnglish=\(request.translateToEnglish) task=\(String(describing: options.task), privacy: .public) languageOpt=\(options.language ?? "nil", privacy: .public) resultLang=\(resultLanguages, privacy: .public) hasCyrillic=\(hasCyrillic) len=\(text.count) preview=\(preview, privacy: .public)"
        )

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

    private func resolveDecodingOptions(
        for request: NativeSmartScribeCore.TranscriptionRequest,
        pipeline: WhisperKit,
        audioPath: String
    ) async -> DecodingOptions {
        if request.translateToEnglish {
            // WhisperKit's `language` is the *spoken* (source) language.
            // `task: .translate` forces X→English. Never pass "en" as source
            // when the user spoke another language.
            //
            // Critical: match WhisperKit CLI/unit-test defaults for translate:
            // - usePrefillPrompt: true  (injects <|lang|><|translate|> tokens)
            // - usePrefillCache: false  (CLI default; prefill KV cache on some
            //   Core ML large-v3 builds effectively ignores the translate token
            //   and keeps producing source-language text)
            // - temperatureFallbackCount: 0
            let detected = try? await pipeline.detectLanguage(audioPath: audioPath)
            let spokenLanguage = detected?.language
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                .lowercased()

            if let spokenLanguage, !spokenLanguage.isEmpty, spokenLanguage == "en" || spokenLanguage.hasPrefix("en") {
                NativeSmartScribeLog.transcription.info(
                    "Translation decoding options: task=transcribe sourceLanguage=en (already English)"
                )
                return DecodingOptions(
                    verbose: false,
                    task: .transcribe,
                    language: "en",
                    temperature: 0,
                    temperatureFallbackCount: 0,
                    usePrefillPrompt: true,
                    usePrefillCache: false,
                    detectLanguage: false,
                    skipSpecialTokens: true,
                    withoutTimestamps: true,
                    wordTimestamps: false
                )
            }

            let sourceLanguage: String?
            if let spokenLanguage, !spokenLanguage.isEmpty {
                sourceLanguage = spokenLanguage
            } else if let forced = request.forcedLanguageCode?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                !forced.isEmpty,
                forced != "en",
                !forced.hasPrefix("en") {
                sourceLanguage = forced
            } else {
                // Unknown source: Whisper detects language while translating.
                sourceLanguage = nil
            }

            NativeSmartScribeLog.transcription.info(
                "Translation decoding options: task=translate sourceLanguage=\(sourceLanguage ?? "auto", privacy: .public) usePrefillCache=false"
            )

            return DecodingOptions(
                verbose: false,
                task: .translate,
                language: sourceLanguage,
                temperature: 0,
                temperatureFallbackCount: 0,
                // Force prefill so <|ru|><|translate|> are always in the prompt.
                usePrefillPrompt: true,
                // IMPORTANT: false — see comment above. Prefill cache broke ER.
                usePrefillCache: false,
                detectLanguage: sourceLanguage == nil,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                wordTimestamps: false
            )
        }

        let normalizedLanguage = request.forcedLanguageCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: normalizedLanguage?.isEmpty == false ? normalizedLanguage : nil,
            temperature: 0,
            temperatureFallbackCount: 0,
            usePrefillPrompt: true,
            usePrefillCache: false,
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
