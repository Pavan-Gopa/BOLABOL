import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
import VaniScriptCore

extension ChatSession: @unchecked @retroactive Sendable {}

actor MLXTextGenerationEngine {
    typealias GenerationOverride = @Sendable (
        _ prompt: String,
        _ model: ActiveMLXModel,
        _ sourceLength: Int,
        _ maxTokens: Int
    ) async throws -> String

    private var cachedModelID: String?
    private var cachedContainer: ModelContainer?
    private let generationTimeoutSeconds: TimeInterval = 180
    private let generationOverride: GenerationOverride?

    init(generationOverride: GenerationOverride? = nil) {
        self.generationOverride = generationOverride
    }

    func translate(
        text: String,
        targetLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        model: ActiveMLXModel,
        promptPresets: [String: PromptPresetSettings] = [:]
    ) async throws -> String {
        let prompt = NativeLLMPromptBuilder.translationPrompt(
            text: text,
            targetLang: targetLang,
            metadata: metadata,
            glossary: glossary,
            promptPresets: promptPresets
        )
        return try await generate(
            prompt: prompt,
            model: model,
            sourceLength: text.count,
            maxTokens: translationTokenLimit(for: text.count)
        )
    }

    /// Runs the strict document contract without transcript sanitization. The
    /// document engine owns JSON parsing and validation, so model output must
    /// remain byte-for-byte available to that gate.
    func generateDocumentTranslation(
        prompt: String,
        model: ActiveMLXModel,
        sourceLength: Int,
        maxTokens: Int? = nil
    ) async throws -> String {
        let raw = try await generate(
            prompt: prompt,
            model: model,
            sourceLength: max(1, sourceLength),
            maxTokens: maxTokens ?? min(max(sourceLength * 4 + 1_024, 2_048), 8_192),
            sanitizeOutput: false
        )
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MLXTextGenerationError.emptyDocumentOutput
        }
        return raw
    }

    func translateCues(
        _ cues: [TranscriptCue],
        targetLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        model: ActiveMLXModel,
        promptPresets: [String: PromptPresetSettings] = [:]
    ) async throws -> [TranscriptCue] {
        guard !cues.isEmpty else { return [] }

        var translated: [TranscriptCue] = []
        let batches = NativeLLMPromptBuilder.cueTranslationBatches(cues, maxSourceCharacters: 1_400)
        for batch in batches {
            let recovered = try await translateCueBatchWithRecovery(
                batch,
                targetLang: targetLang,
                metadata: metadata,
                glossary: glossary,
                model: model,
                promptPresets: promptPresets,
                allowsSourceFallback: cues.count > 1
            )
            translated.append(contentsOf: recovered)
        }

        guard Self.isReviewableCueTranslation(translated, sourceCues: cues),
              Self.containsRealCueTranslation(translated, sourceCues: cues)
        else {
            throw CueBatchTranslationError.emptyOutput
        }
        return translated
    }

    private func translateCueBatchWithRecovery(
        _ cues: [TranscriptCue],
        targetLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        model: ActiveMLXModel,
        promptPresets: [String: PromptPresetSettings],
        allowsSourceFallback: Bool
    ) async throws -> [TranscriptCue] {
        do {
            let prompt = NativeLLMPromptBuilder.cueBatchTranslationPrompt(
                cues: cues,
                targetLang: targetLang,
                metadata: metadata,
                glossary: glossary,
                promptPresets: promptPresets
            )
            let sourceLength = cues.reduce(0) { $0 + $1.text.count }
            let raw = try await generate(
                prompt: prompt,
                model: model,
                sourceLength: sourceLength,
                maxTokens: translationTokenLimit(for: sourceLength)
            )
            let translated = try NativeLLMPromptBuilder.parseCueBatchTranslationOutput(
                raw,
                sourceCues: cues
            )
            guard Self.isCompleteCueTranslation(translated, sourceCues: cues) else {
                throw CueBatchTranslationError.emptyOutput
            }
            return translated
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CueBatchTranslationError {
            if cues.count == 1, let singleCue = cues.first {
                return try await translateSingleCueTerminalWithRecovery(
                    singleCue,
                    targetLang: targetLang,
                    metadata: metadata,
                    glossary: glossary,
                    model: model,
                    promptPresets: promptPresets,
                    allowsSourceFallback: allowsSourceFallback
                )
            }

            guard cues.count > 1 else { throw error }

            // Each retry strictly halves the failed input; binary splitting visits
            // at most 2n - 1 batches, so a bad model response cannot loop forever.
            let splitIndex = cues.count / 2
            let left = try await translateCueBatchWithRecovery(
                Array(cues[..<splitIndex]),
                targetLang: targetLang,
                metadata: metadata,
                glossary: glossary,
                model: model,
                promptPresets: promptPresets,
                allowsSourceFallback: allowsSourceFallback
            )
            let right = try await translateCueBatchWithRecovery(
                Array(cues[splitIndex...]),
                targetLang: targetLang,
                metadata: metadata,
                glossary: glossary,
                model: model,
                promptPresets: promptPresets,
                allowsSourceFallback: allowsSourceFallback
            )
            return left + right
        } catch {
            throw error
        }
    }

    private func translateSingleCueTerminalWithRecovery(
        _ cue: TranscriptCue,
        targetLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        model: ActiveMLXModel,
        promptPresets: [String: PromptPresetSettings],
        allowsSourceFallback: Bool
    ) async throws -> [TranscriptCue] {
        let prompt = NativeLLMPromptBuilder.singleCueTerminalTranslationPrompt(
            cue: cue,
            targetLang: targetLang,
            metadata: metadata,
            glossary: glossary,
            promptPresets: promptPresets
        )
        let sourceLength = cue.text.count
        let maxTokens = translationTokenLimit(for: sourceLength)
        let raw = try await generate(
            prompt: prompt,
            model: model,
            sourceLength: sourceLength,
            maxTokens: maxTokens,
            sanitizeOutput: false
        )

        do {
            let translatedCue = try NativeLLMPromptBuilder.parseSingleCueTerminalTranslationOutput(
                raw,
                sourceCue: cue,
                targetLang: targetLang
            )
            guard Self.isCompleteCueTranslation([translatedCue], sourceCues: [cue]) else {
                throw CueBatchTranslationError.emptyOutput
            }
            return [translatedCue]
        } catch let error as CueBatchTranslationError {
            guard case .emptyOutput = error else { throw error }
        }

        let retryPrompt = Self.terminalRetryPrompt(from: prompt, targetLang: targetLang)
        let retryRaw = try await generate(
            prompt: retryPrompt,
            model: model,
            sourceLength: sourceLength,
            maxTokens: maxTokens,
            sanitizeOutput: false
        )

        do {
            let translatedCue = try NativeLLMPromptBuilder.parseSingleCueTerminalTranslationOutput(
                retryRaw,
                sourceCue: cue,
                targetLang: targetLang
            )
            guard Self.isCompleteCueTranslation([translatedCue], sourceCues: [cue]) else {
                throw CueBatchTranslationError.emptyOutput
            }
            return [translatedCue]
        } catch let error as CueBatchTranslationError {
            guard case .emptyOutput = error else { throw error }
            guard allowsSourceFallback else { throw CueBatchTranslationError.emptyOutput }

            // Preserve the failed source leaf for review while the caller retains
            // any real translations recovered from its sibling leaves.
            return [Self.sourcePreservingFallbackCue(for: cue)]
        }
    }

    private nonisolated static func sourcePreservingFallbackText(for cue: TranscriptCue) -> String {
        guard !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "[Untranslated source cue]"
        }
        return cue.text
    }

    private nonisolated static func sourcePreservingFallbackCue(for cue: TranscriptCue) -> TranscriptCue {
        TranscriptCue(
            startSec: cue.startSec,
            endSec: cue.endSec,
            text: sourcePreservingFallbackText(for: cue),
            words: cue.words
        )
    }


    private nonisolated static func terminalRetryPrompt(from prompt: String, targetLang: String) -> String {
        let marker = "<<<TRANSLATION>>>"
        let retryInstructions = """
        Recovery requirement: the previous terminal response was empty.
        Do not return <<<END>>> or <<END>> by itself.
        Return one nonempty translation in \(targetLang) between <<<TRANSLATION>>> and <<<END>>>.
        Do not answer with a marker, explanation, or empty body.
        """

        guard let markerRange = prompt.range(of: marker, options: .backwards) else {
            return "\(prompt)\n\n\(retryInstructions)\n\(marker)\n"
        }

        var retryPrompt = prompt
        retryPrompt.replaceSubrange(markerRange, with: "\(retryInstructions)\n\(marker)")
        return retryPrompt
    }

    private nonisolated static func isReviewableCueTranslation(
        _ translated: [TranscriptCue],
        sourceCues: [TranscriptCue]
    ) -> Bool {
        guard translated.count == sourceCues.count else { return false }
        return zip(translated, sourceCues).allSatisfy { translated, source in
            let translatedText = translated.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translatedText.isEmpty,
                  translated.startSec == source.startSec,
                  translated.endSec == source.endSec
            else {
                return false
            }

            if translated.text == sourcePreservingFallbackText(for: source) {
                return true
            }
            return isCompleteCueTranslation([translated], sourceCues: [source])
        }
    }

    private nonisolated static func containsRealCueTranslation(
        _ translated: [TranscriptCue],
        sourceCues: [TranscriptCue]
    ) -> Bool {
        zip(translated, sourceCues).contains { translated, source in
            translated.text != sourcePreservingFallbackText(for: source)
                && isCompleteCueTranslation([translated], sourceCues: [source])
        }
    }

    private nonisolated static func isCompleteCueTranslation(
        _ translated: [TranscriptCue],
        sourceCues: [TranscriptCue]
    ) -> Bool {
        guard translated.count == sourceCues.count else { return false }
        return zip(translated, sourceCues).allSatisfy { translated, source in
            let translatedText = translated.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translatedText.isEmpty,
                  translated.startSec == source.startSec,
                  translated.endSec == source.endSec
            else {
                return false
            }
            let normalizedTranslated = translatedText
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            let normalizedSource = source.text
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            return normalizedTranslated != normalizedSource
        }
    }

    func polish(
        text: String,
        targetLang: String,
        model: ActiveMLXModel,
        lecturer: String = "",
        glossary: [GlossaryEntry] = [],
        promptPresets: [String: PromptPresetSettings] = [:]
    ) async throws -> String {
        let prompt = NativeLLMPromptBuilder.literaryPolishPrompt(
            text: text,
            targetLang: targetLang,
            lecturer: lecturer,
            glossary: glossary,
            promptPresets: promptPresets
        )
        return try await generate(prompt: prompt, model: model, sourceLength: text.count)
    }

    func formatDocument(
        format: OutputFormat,
        targetLang: String,
        text: String,
        model: ActiveMLXModel
    ) async throws -> String {
        guard format != .txt else { return text }

        let sourceText = format == .markdown
            ? DocumentExportFormatter.stripMarkdownDocumentShell(text)
            : text
        let batches = DocumentExportFormatter.splitDocumentExportInput(
            sourceText,
            format: format,
            maxChars: DocumentExportFormatter.localDocumentBatchLimit(format: format)
        )
        guard !batches.isEmpty else { return text }

        var formattedParts: [String] = []
        for (index, batch) in batches.enumerated() {
            let prompt = format == .markdown
                ? DocumentExportFormatter.buildLocalMarkdownPartPrompt(
                    text: batch,
                    targetLang: targetLang,
                    partIndex: index,
                    totalParts: batches.count
                )
                : DocumentExportFormatter.buildDocumentExportPrompt(
                    format: format,
                    targetLang: targetLang,
                    text: batch
                )
            let raw = try await generate(
                prompt: prompt,
                model: model,
                sourceLength: batch.count,
                maxTokens: max(1_024, min(5_000, Int(Double(batch.count) * 1.4)))
            )
            let cleaned = format == .markdown
                ? DocumentExportFormatter.sanitizeLocalMarkdownBodyPart(raw)
                : DocumentExportFormatter.sanitizeDocumentExportOutput(raw)
            if !cleaned.isEmpty {
                formattedParts.append(cleaned)
            }
        }

        if format == .markdown {
            return DocumentExportFormatter.combineLocalMarkdownParts(
                parts: formattedParts,
                sourceDocument: text,
                targetLang: targetLang
            )
        }

        return DocumentExportFormatter.combineDocumentExportParts(formattedParts, format: format)
    }

    func planShorts(
        transcript: String,
        count: Int,
        minDurationSec: Int,
        maxDurationSec: Int,
        outputLanguage: String,
        speakerName: String?,
        mode: ShortsPlanLanguageMode,
        existingClips: [ShortsClipPlan] = [],
        model: ActiveMLXModel
    ) async throws -> [ShortsClipPlan] {
        let prompt = ShortsPlanner.buildPrompt(
            transcript: transcript,
            count: count,
            minDurationSec: minDurationSec,
            maxDurationSec: maxDurationSec,
            outputLanguage: outputLanguage,
            speakerName: speakerName,
            mode: mode,
            existingClips: existingClips
        )
        let raw = try await generate(
            prompt: prompt,
            model: model,
            sourceLength: transcript.count,
            maxTokens: 3_500
        )
        return try ShortsPlanner.parsePlanResponse(raw)
    }

    func translateShortsPlan(
        _ plan: ShortsClipPlan,
        targetLanguage: String,
        model: ActiveMLXModel
    ) async throws -> ShortsClipTranslation {
        let prompt = ShortsPlanner.buildTranslationPrompt(plan: plan, targetLanguage: targetLanguage)
        let raw = try await generate(
            prompt: prompt,
            model: model,
            sourceLength: prompt.count,
            maxTokens: 1_500
        )
        return try ShortsPlanner.parseTranslationResponse(raw, language: targetLanguage, provider: model.id)
    }

    private func generate(
        prompt: String,
        model: ActiveMLXModel,
        sourceLength: Int,
        maxTokens: Int? = nil,
        sanitizeOutput: Bool = true
    ) async throws -> String {
        let resolvedMaxTokens = maxTokens ?? generationTokenLimit(for: sourceLength)
        AppLogger.shared.info("MLX LLM generating with model \(model.id), prompt length: \(prompt.count), maxTokens: \(resolvedMaxTokens)")

        if let generationOverride {
            let raw = try await generationOverride(prompt, model, sourceLength, resolvedMaxTokens)
            AppLogger.shared.info("MLX LLM raw generated output length: \(raw.count)")
            if sanitizeOutput {
                let sanitized = ModelOutputSanitizer.sanitize(raw)
                AppLogger.shared.info("MLX LLM sanitized output length: \(sanitized.count)")
                return sanitized
            } else {
                return raw
            }
        }

        let container = try await modelContainer(for: model)

        let systemInstructions = """
        You are VaniScript's local translation engine.
        Follow the user formatting prompt exactly.
        Return only the requested final document content.
        Do not output reasoning, analysis, notes, or hidden thinking.
        """
        let generateParameters = GenerateParameters(
            maxTokens: resolvedMaxTokens,
            temperature: 0.0,
            topP: 0.9,
            repetitionPenalty: 1.12,
            repetitionContextSize: 64
        )
        let bypassForcedThinkingTemplate = Self.usesForcedThinkingTemplate(modelPath: model.path)
        let session = bypassForcedThinkingTemplate
            ? nil
            : ChatSession(
                container,
                instructions: systemInstructions,
                generateParameters: generateParameters,
                additionalContext: ["enable_thinking": false]
            )

        let promptToSend = bypassForcedThinkingTemplate
            ? NativeLLMPromptBuilder.qwenNoThinkChatPrompt(
                userPrompt: prompt,
                systemInstructions: systemInstructions
            )
            : prompt
        if bypassForcedThinkingTemplate {
            AppLogger.shared.info("MLX LLM using raw no-think chat prompt for model \(model.id)")
        }

        let timeoutSeconds = generationTimeoutSeconds
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var output = ""
                let startedAt = Date()
                if let session {
                    for try await chunk in session.streamResponse(to: promptToSend) {
                        try Task.checkCancellation()
                        output += chunk
                        if Self.shouldStopGeneration(output) {
                            break
                        }
                        if Date().timeIntervalSince(startedAt) > timeoutSeconds {
                            throw MLXTextGenerationError.generationTimedOut(seconds: timeoutSeconds)
                        }
                    }
                } else {
                    output = try await Self.generateRawPrompt(
                        prompt: promptToSend,
                        container: container,
                        parameters: generateParameters,
                        timeoutSeconds: timeoutSeconds,
                        startedAt: startedAt
                    )
                }

                AppLogger.shared.info("MLX LLM raw generated output length: \(output.count)")
                if sanitizeOutput {
                    let sanitized = ModelOutputSanitizer.sanitize(output)
                    AppLogger.shared.info("MLX LLM sanitized output length: \(sanitized.count)")
                    return sanitized
                } else {
                    return output
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw MLXTextGenerationError.generationTimedOut(seconds: timeoutSeconds)
            }

            guard let output = try await group.next() else {
                throw MLXTextGenerationError.generationTimedOut(seconds: timeoutSeconds)
            }
            group.cancelAll()
            return output
        }
    }

    private nonisolated static func usesForcedThinkingTemplate(modelPath: String) -> Bool {
        return false
    }

    private nonisolated static func shouldStopGeneration(_ output: String) -> Bool {
        output.contains("<<<END>>>")
            || output.contains("<|im_end|>")
            || output.contains("</s>")
    }

    private nonisolated static func generateRawPrompt(
        prompt: String,
        container: ModelContainer,
        parameters: GenerateParameters,
        timeoutSeconds: TimeInterval,
        startedAt: Date
    ) async throws -> String {
        try await container.perform { context in
            let tokens = context.tokenizer.encode(text: prompt, addSpecialTokens: false)
            let input = LMInput(tokens: MLXArray(tokens))
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: context
            )

            var output = ""
            for await item in stream {
                try Task.checkCancellation()
                if let chunk = item.chunk {
                    output += chunk
                    if shouldStopGeneration(output) {
                        break
                    }
                }
                if Date().timeIntervalSince(startedAt) > timeoutSeconds {
                    throw MLXTextGenerationError.generationTimedOut(seconds: timeoutSeconds)
                }
            }
            return output
        }
    }

    private func modelContainer(for model: ActiveMLXModel) async throws -> ModelContainer {
        if cachedModelID == model.id, let cachedContainer {
            return cachedContainer
        }

        let modelDirectory = URL(fileURLWithPath: model.path, isDirectory: true)
        let configuration = ModelConfiguration(directory: modelDirectory)
        let hubCache = HubCache(cacheDirectory: modelDirectory.deletingLastPathComponent())
        let hubClient = HubClient(cache: hubCache)
        let container = try await MLXLMCommon.loadModelContainer(
            from: #hubDownloader(hubClient),
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration
        )
        cachedModelID = model.id
        cachedContainer = container
        return container
    }

    private func generationTokenLimit(for sourceLength: Int) -> Int {
        min(max(sourceLength / 2 + 256, 384), 1_800)
    }

    private func translationTokenLimit(for sourceLength: Int) -> Int {
        min(max(sourceLength * 2 + 512, 1_024), 2_048)
    }
}

enum MLXTextGenerationError: LocalizedError {
    case generationTimedOut(seconds: TimeInterval)
    case emptyDocumentOutput

    var errorDescription: String? {
        switch self {
        case let .generationTimedOut(seconds):
            "MLX generation exceeded \(Int(seconds)) seconds."
        case .emptyDocumentOutput:
            "MLX returned no usable document translation output."
        }
    }
}
