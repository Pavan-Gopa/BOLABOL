import Foundation
import VaniScriptCore
import AVFoundation

protocol NativeLocalMLXEngine: Sendable {
    func translate(
        text: String,
        targetLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        model: ActiveMLXModel,
        promptPresets: [String: PromptPresetSettings]
    ) async throws -> String

    func translateCues(
        _ cues: [TranscriptCue],
        targetLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        model: ActiveMLXModel,
        promptPresets: [String: PromptPresetSettings]
    ) async throws -> [TranscriptCue]

    func polish(
        text: String,
        targetLang: String,
        model: ActiveMLXModel,
        lecturer: String,
        glossary: [GlossaryEntry],
        promptPresets: [String: PromptPresetSettings]
    ) async throws -> String

    func formatDocument(
        format: OutputFormat,
        targetLang: String,
        text: String,
        model: ActiveMLXModel
    ) async throws -> String

    func planShorts(
        transcript: String,
        count: Int,
        minDurationSec: Int,
        maxDurationSec: Int,
        outputLanguage: String,
        speakerName: String?,
        mode: ShortsPlanLanguageMode,
        existingClips: [ShortsClipPlan],
        model: ActiveMLXModel
    ) async throws -> [ShortsClipPlan]

    func translateShortsPlan(
        _ plan: ShortsClipPlan,
        targetLanguage: String,
        model: ActiveMLXModel
    ) async throws -> ShortsClipTranslation
}

extension MLXTextGenerationEngine: NativeLocalMLXEngine {}

actor NativeProcessingPipeline {
    private let mlxEngine: any NativeLocalMLXEngine
    private let cloudEngine = CloudTextTranslationEngine()
    private let cloudTranscriptionEngine = CloudAudioTranscriptionEngine()
    private let localASRRouter: LocalASREngineRouter

    init(
        localASRRouter: LocalASREngineRouter = LocalASREngineRouter(),
        mlxEngine: any NativeLocalMLXEngine = MLXTextGenerationEngine()
    ) {
        self.localASRRouter = localASRRouter
        self.mlxEngine = mlxEngine
    }

    func unloadModels() async {
        await localASRRouter.unload()
    }

    func releaseASRBeforeLocalMLX() async {
        await localASRRouter.unloadBeforeHeavyLocalModel()
    }

    func invalidateASRBinding() async {
        await localASRRouter.unload()
    }

    func transcribeLocalASR(
        audioURL: URL,
        sourceLang: String,
        settings: AppSettings,
        providerID: String
    ) async throws -> LocalASRResult {
        try await localASRRouter.transcribe(
            settings: settings,
            providerID: providerID,
            request: LocalASRRequest(
                audioFileURL: audioURL,
                languageHint: NativeLanguagePolicy.canonicalCode(sourceLang),
                translateToEnglish: false
            )
        )
    }

    func processCurrentChunk(
        session: SessionState,
        settings: inout AppSettings,
        projectId: String? = nil,
        progress: @Sendable @escaping (String, Double) async -> Void
    ) async -> SessionState {
        var next = session
        AppLogger.shared.info("Starting native processing for current segment of \(session.sourceFileName).", settings: settings)
        await progress("Checking native model readiness...", 0.08)

        let readiness = NativeProcessingReadiness.evaluate(
            settings: settings,
            sourceLang: session.sourceLang,
            targetLang: session.targetLang,
            transcriptionProvider: session.transcriptionProvider,
            translationProvider: session.translationProvider
        )

        guard readiness.canTranscribe else {
            AppLogger.shared.error("Readiness check failed: \(readiness.transcriptionMessage)", settings: settings)
            markCurrentChunk(&next, status: .error, original: readiness.transcriptionMessage, translated: "")
            await progress(readiness.transcriptionMessage, 1)
            return next
        }

        guard readiness.canTranslate else {
            AppLogger.shared.error("Readiness check failed: \(readiness.translationMessage)", settings: settings)
            markCurrentChunk(&next, status: .error, original: readiness.translationMessage, translated: "")
            await progress(readiness.translationMessage, 1)
            return next
        }

        guard let sourceFile = session.sourceFile, !sourceFile.isEmpty else {
            AppLogger.shared.error("Missing source audio file path.", settings: settings)
            markCurrentChunk(&next, status: .error, original: "Missing source audio file.", translated: "")
            await progress("Missing source audio file.", 1)
            return next
        }

        let sourceURL = URL(fileURLWithPath: sourceFile)


        do {
            let resolvedDuration = next.durationSec > 0
                ? next.durationSec
                : await MediaDurationReader.durationSeconds(for: sourceURL)
            if resolvedDuration > 0, next.chunks.isEmpty || abs(next.durationSec - resolvedDuration) > 0.5 {
                next.durationSec = resolvedDuration
                next.chunks = await planChunks(
                    sourceURL: sourceURL,
                    sourcePath: sourceFile,
                    durationSec: resolvedDuration,
                    settings: settings,
                    progress: progress
                )
                next.currentChunkIndex = min(next.currentChunkIndex, max(0, next.chunks.count - 1))
            }

            guard next.chunks.indices.contains(next.currentChunkIndex) else {
                AppLogger.shared.error("Current segment index is outside planned chunk range.", settings: settings)
                await progress("No segment is available to process.", 1)
                return next
            }

            let index = next.currentChunkIndex
            let chunkNumber = index + 1
            let total = next.chunks.count
            next.chunks[index].status = .processing
            next.chunks[index].original = next.chunks[index].original.trimmingCharacters(in: .whitespacesAndNewlines)

            await progress("Slicing segment \(chunkNumber) / \(total) with AVFoundation...", 0.26)
            let chunkURLs = try await AudioChunkExporter.exportChunks(
                sourceURL: sourceURL,
                chunks: [next.chunks[index]],
                projectId: projectId
            )

            let audioURL = chunkURLs[next.chunks[index].index] ?? sourceURL
            next.chunks[index].filePath = audioURL.path

            if let cloudProvider = ActiveCloudTranscriptionProvider.resolve(
                settings: settings,
                providerID: next.transcriptionProvider
            ) {
                await progress("Transcribing segment \(chunkNumber) / \(total) with \(cloudProvider.label)...", 0.38)
                try await transcribeCurrentChunkWithCloud(
                    &next,
                    index: index,
                    audioURL: audioURL,
                    provider: cloudProvider,
                    settings: &settings
                )
                guard next.chunks[index].status == .done else {
                    await progress(next.chunks[index].original, 1)
                    return next
                }
                await translateCurrentChunkIfNeeded(
                    &next,
                    index: index,
                    settings: &settings,
                    progress: progress
                )
                return await finishCurrentChunk(
                    session: next,
                    index: index,
                    chunkNumber: chunkNumber,
                    total: total,
                    settings: settings,
                    progress: progress
                )
            }

            guard let activeModel = NativeModelCatalog.activeLocalASRModel(
                settings: settings,
                providerID: next.transcriptionProvider
            ) else {
                AppLogger.shared.error("ASR model lookup failed.", settings: settings)
                markCurrentChunk(&next, status: .error, original: readiness.transcriptionMessage, translated: "")
                await progress(readiness.transcriptionMessage, 1)
                return next
            }

            await progress("Loading \(activeModel.label) local ASR...", 0.16)
            AppLogger.shared.info(
                "Loading local ASR model \(activeModel.label) (\(activeModel.id)) from \(activeModel.path)...",
                settings: settings
            )

            await progress("Transcribing segment \(chunkNumber) / \(total) with \(activeModel.label) local ASR...", 0.38)
            AppLogger.shared.info("Transcribing segment \(chunkNumber)/\(total) path: \(audioURL.path)", settings: settings)

            let result = try await transcribeLocalASR(
                audioURL: audioURL,
                sourceLang: next.sourceLang,
                settings: settings,
                providerID: next.transcriptionProvider
            )
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawOriginalCues = Self.transcriptCues(from: result, chunk: next.chunks[index], fallbackText: text)
            let glossaryOriginal = applySourceGlossary(text: text, cues: rawOriginalCues, settings: settings)
            let originalText = glossaryOriginal.text
            let originalCues = glossaryOriginal.cues

            guard !originalText.isEmpty else {
                AppLogger.shared.warn("Segment \(chunkNumber)/\(total) returned empty transcript.", settings: settings)
                next.chunks[index].status = .error
                next.chunks[index].original = "Local transcription returned no text."
                next.chunks[index].translated = ""
                await progress("Local transcription returned no text.", 1)
                return next
            }

            if glossaryOriginal.count > 0 {
                AppLogger.shared.info("Applied \(glossaryOriginal.count) glossary replacement(s) to source segment \(chunkNumber)/\(total).", settings: settings)
            }
            AppLogger.shared.info("Segment \(chunkNumber)/\(total) transcription complete (\(originalText.count) chars).", settings: settings)
            next.chunks[index].original = originalText
            next.chunks[index].originalCues = originalCues
            next.chunks[index].translated = ""
            next.chunks[index].status = .done



            await translateCurrentChunkIfNeeded(
                &next,
                index: index,
                settings: &settings,
                progress: progress
            )

            return await finishCurrentChunk(
                session: next,
                index: index,
                chunkNumber: chunkNumber,
                total: total,
                settings: settings,
                progress: progress
            )
        } catch {
            markCurrentChunk(&next, status: .error, original: "Native segment processing failed: \(error.localizedDescription)", translated: "")
            await progress("Native segment processing failed.", 1)
            return next
        }
    }

    private func finishCurrentChunk(
        session: SessionState,
        index: Int,
        chunkNumber: Int,
        total: Int,
        settings: AppSettings,
        progress: @Sendable @escaping (String, Double) async -> Void
    ) async -> SessionState {
        if session.chunks[index].status == .error {
            let rawFailure = session.chunks[index].translated.trimmingCharacters(in: .whitespacesAndNewlines)
            let failureMessage = rawFailure.isEmpty ? "Translation failed." : rawFailure
            await progress(failureMessage, 1)
            return session
        }
        AppLogger.shared.info("Segment \(chunkNumber)/\(total) is ready for review.", settings: settings)
        await progress("Segment \(chunkNumber) is ready for review.", 1)
        return session
    }

    func process(
        session: SessionState,
        settings: inout AppSettings,
        projectId: String? = nil,
        progress: @Sendable @escaping (String, Double) async -> Void
    ) async -> SessionState {
        var next = session
        AppLogger.shared.info("Starting native processing pipeline for \(session.sourceFileName).", settings: settings)
        await progress("Checking native model readiness...", 0.08)

        let readiness = NativeProcessingReadiness.evaluate(
            settings: settings,
            sourceLang: session.sourceLang,
            targetLang: session.targetLang,
            transcriptionProvider: session.transcriptionProvider,
            translationProvider: session.translationProvider
        )

        guard readiness.canTranscribe else {
            AppLogger.shared.error("Readiness check failed: \(readiness.transcriptionMessage)", settings: settings)
            markAllChunks(&next, status: .error, original: readiness.transcriptionMessage, translated: "")
            await progress(readiness.transcriptionMessage, 1)
            return next
        }

        guard readiness.canTranslate else {
            AppLogger.shared.error("Readiness check failed: \(readiness.translationMessage)", settings: settings)
            markAllChunks(&next, status: .error, original: readiness.translationMessage, translated: "")
            await progress(readiness.translationMessage, 1)
            return next
        }

        guard let sourceFile = session.sourceFile, !sourceFile.isEmpty else {
            AppLogger.shared.error("Missing source audio file path.", settings: settings)
            markAllChunks(&next, status: .error, original: "Missing source audio file.", translated: "")
            return next
        }

        let sourceURL = URL(fileURLWithPath: sourceFile)


        do {
            let resolvedDuration = next.durationSec > 0
                ? next.durationSec
                : await MediaDurationReader.durationSeconds(for: sourceURL)
            if resolvedDuration > 0 {
                next.durationSec = resolvedDuration
                AppLogger.shared.info("Audio duration resolved: \(resolvedDuration) seconds.", settings: settings)
                next.chunks = await planChunks(
                    sourceURL: sourceURL,
                    sourcePath: sourceFile,
                    durationSec: resolvedDuration,
                    settings: settings,
                    progress: progress
                )
            }

            if let cloudProvider = ActiveCloudTranscriptionProvider.resolve(
                settings: settings,
                providerID: next.transcriptionProvider
            ) {
                await progress("Slicing audio with AVFoundation...", 0.22)
                let chunkURLs = try await AudioChunkExporter.exportChunks(
                    sourceURL: sourceURL,
                    chunks: next.chunks,
                    projectId: projectId
                )
                AppLogger.shared.info("Audio sliced successfully into \(next.chunks.count) segments.", settings: settings)

                guard !next.chunks.isEmpty else {
                    AppLogger.shared.warn("Planned chunks array is empty. Exiting.", settings: settings)
                    return next
                }

                for index in next.chunks.indices {
                    let chunkNumber = index + 1
                    let total = next.chunks.count
                    next.chunks[index].status = .processing
                    let fraction = 0.28 + (Double(index) / Double(max(1, total))) * 0.50
                    await progress("Transcribing segment \(chunkNumber) / \(total) with \(cloudProvider.label)...", fraction)

                    let audioURL = chunkURLs[next.chunks[index].index] ?? sourceURL
                    next.chunks[index].filePath = audioURL.path
                    AppLogger.shared.debug("Cloud transcribing segment \(chunkNumber)/\(total) path: \(audioURL.path)", settings: settings)
                    try await transcribeCurrentChunkWithCloud(
                        &next,
                        index: index,
                        audioURL: audioURL,
                        provider: cloudProvider,
                        settings: &settings
                    )
                }

                AppLogger.shared.info("Cloud transcription complete successfully.", settings: settings)
                await translateChunksIfNeeded(
                    &next,
                    settings: &settings,
                    progress: progress
                )

                await progress("Native processing complete.", 1)
                return next
            }

            guard let activeModel = NativeModelCatalog.activeLocalASRModel(
                settings: settings,
                providerID: next.transcriptionProvider
            ) else {
                AppLogger.shared.error("ASR model lookup failed.", settings: settings)
                markAllChunks(&next, status: .error, original: readiness.transcriptionMessage, translated: "")
                return next
            }

            AppLogger.shared.info("Loading local ASR model \(activeModel.label) (\(activeModel.id)) from \(activeModel.path)...", settings: settings)
            await progress("Loading \(activeModel.label) local ASR...", 0.16)

            await progress("Slicing audio with AVFoundation...", 0.22)
            let chunkURLs = try await AudioChunkExporter.exportChunks(
                sourceURL: sourceURL,
                chunks: next.chunks,
                projectId: projectId
            )
            AppLogger.shared.info("Audio sliced successfully into \(next.chunks.count) segments.", settings: settings)

            guard !next.chunks.isEmpty else {
                AppLogger.shared.warn("Planned chunks array is empty. Exiting.", settings: settings)
                return next
            }

            for index in next.chunks.indices {
                let chunkNumber = index + 1
                let total = next.chunks.count
                next.chunks[index].status = .processing
                let fraction = 0.28 + (Double(index) / Double(max(1, total))) * 0.50

                await progress("Transcribing segment \(chunkNumber) / \(total) with \(activeModel.label) local ASR...", fraction)

                let audioURL = chunkURLs[next.chunks[index].index] ?? sourceURL
                AppLogger.shared.debug("Transcribing segment \(chunkNumber)/\(total) path: \(audioURL.path)", settings: settings)

                let result = try await transcribeLocalASR(
                    audioURL: audioURL,
                    sourceLang: next.sourceLang,
                    settings: settings,
                    providerID: next.transcriptionProvider
                )
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let rawOriginalCues = Self.transcriptCues(from: result, chunk: next.chunks[index], fallbackText: text)
                let glossaryOriginal = applySourceGlossary(text: text, cues: rawOriginalCues, settings: settings)
                let originalText = glossaryOriginal.text
                let originalCues = glossaryOriginal.cues

                if originalText.isEmpty {
                    AppLogger.shared.warn("Segment \(chunkNumber)/\(total) returned empty transcript.", settings: settings)
                    next.chunks[index].status = .error
                    next.chunks[index].original = "Local transcription returned no text."
                    next.chunks[index].translated = ""
                } else {
                    if glossaryOriginal.count > 0 {
                        AppLogger.shared.info("Applied \(glossaryOriginal.count) glossary replacement(s) to source segment \(chunkNumber)/\(total).", settings: settings)
                    }
                    AppLogger.shared.info("Segment \(chunkNumber)/\(total) transcript: \"\(originalText)\"", settings: settings)
                    next.chunks[index].filePath = audioURL.path
                    next.chunks[index].original = originalText
                    next.chunks[index].originalCues = originalCues
                    next.chunks[index].translated = ""
                    next.chunks[index].status = .done
                }
            }

            AppLogger.shared.info("Transcription complete successfully.", settings: settings)
        } catch {
            markAllChunks(&next, status: .error, original: "Transcription failed: \(error.localizedDescription)", translated: "")
            await progress("Transcription failed.", 1)
            return next
        }

        await translateChunksIfNeeded(
            &next,
            settings: &settings,
            progress: progress
        )

        await progress("Native processing complete.", 1)
        return next
    }

    private func transcribeCurrentChunkWithCloud(
        _ session: inout SessionState,
        index: Int,
        audioURL: URL,
        provider: ActiveCloudTranscriptionProvider,
        settings: inout AppSettings
    ) async throws {
        guard session.chunks.indices.contains(index) else { return }

        let chunkNumber = index + 1
        let total = session.chunks.count
        let chunk = session.chunks[index]
        let result = try await cloudTranscriptionEngine.transcribe(
            audioURL: audioURL,
            sourceLang: session.sourceLang,
            metadata: session.metadata,
            glossary: settings.glossary,
            provider: provider,
            promptPresets: settings.promptPresets,
            chunkStartSec: chunk.startSec,
            chunkEndSec: chunk.endSec
        )

        let audioMins = max(0, (chunk.endSec - chunk.startSec) / 60.0)
        UsageRecorder.record(
            into: &settings.usage,
            providerId: provider.id,
            model: provider.model,
            delta: result.usage,
            audioMinutes: audioMins,
            purpose: "transcription"
        )

        let glossaryOriginal = applySourceGlossary(text: result.text, cues: result.cues, settings: settings)
        let originalText = glossaryOriginal.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !originalText.isEmpty else {
            AppLogger.shared.warn("Segment \(chunkNumber)/\(total) returned empty cloud transcript.", settings: settings)
            session.chunks[index].status = .error
            session.chunks[index].original = "\(provider.label) returned an empty transcript."
            session.chunks[index].translated = ""
            return
        }

        if glossaryOriginal.count > 0 {
            AppLogger.shared.info("Applied \(glossaryOriginal.count) glossary replacement(s) to cloud source segment \(chunkNumber)/\(total).", settings: settings)
        }
        AppLogger.shared.info("Segment \(chunkNumber)/\(total) \(provider.label) transcription complete (\(originalText.count) chars).", settings: settings)
        session.chunks[index].original = originalText
        session.chunks[index].originalCues = glossaryOriginal.cues
        session.chunks[index].translated = ""
        session.chunks[index].status = .done
    }

    nonisolated internal static func transcriptCues(
        from result: LocalASRResult,
        chunk: ChunkData,
        fallbackText: String
    ) -> [TranscriptCue] {
        guard let timedCues = result.cues else {
            let clean = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, chunk.startSec.isFinite, chunk.endSec.isFinite, chunk.endSec > chunk.startSec else {
                return []
            }
            return ParakeetTranscriptionEngine.boundedCuesFromUntimedText(
                clean,
                startSec: chunk.startSec,
                endSec: chunk.endSec
            )
        }

        var mapped: [TranscriptCue] = []
        mapped.reserveCapacity(timedCues.count)
        var previousCueEnd = chunk.startSec

        for cue in timedCues {
            let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  cue.startSec.isFinite,
                  cue.endSec.isFinite
            else {
                continue
            }

            let rawStart = chunk.startSec + cue.startSec
            let rawEnd = chunk.startSec + cue.endSec
            guard rawStart.isFinite, rawEnd.isFinite else { continue }
            let boundedStart = min(
                chunk.endSec,
                max(previousCueEnd, max(chunk.startSec, rawStart))
            )
            let boundedEnd = min(
                chunk.endSec,
                max(boundedStart, rawEnd)
            )
            guard boundedEnd > boundedStart else { continue }

            var words: [TranscriptWord] = []
            words.reserveCapacity(cue.words?.count ?? 0)
            var previousWordEnd = boundedStart
            for word in cue.words ?? [] {
                let wordText = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !wordText.isEmpty,
                      word.startSec.isFinite,
                      word.endSec.isFinite
                else {
                    continue
                }
                let rawWordStart = chunk.startSec + word.startSec
                let rawWordEnd = chunk.startSec + word.endSec
                guard rawWordStart.isFinite, rawWordEnd.isFinite else { continue }
                let boundedWordStart = min(
                    boundedEnd,
                    max(previousWordEnd, max(boundedStart, rawWordStart))
                )
                let boundedWordEnd = min(
                    boundedEnd,
                    max(boundedWordStart, rawWordEnd)
                )
                guard boundedWordEnd > boundedWordStart else { continue }
                words.append(
                    TranscriptWord(
                        startSec: boundedWordStart,
                        endSec: boundedWordEnd,
                        text: wordText
                    )
                )
                previousWordEnd = boundedWordEnd
            }

            mapped.append(
                TranscriptCue(
                    startSec: boundedStart,
                    endSec: boundedEnd,
                    text: text,
                    words: words.isEmpty ? nil : words
                )
            )
            previousCueEnd = boundedEnd
        }

        // A non-nil timed result is authoritative, including an empty array.
        // Do not replace it with a whole-planned-chunk text cue.
        return mapped
    }

    private func planChunks(
        sourceURL: URL,
        sourcePath: String,
        durationSec: Double,
        settings: AppSettings,
        progress: @Sendable @escaping (String, Double) async -> Void
    ) async -> [ChunkData] {
        if settings.sliceMode == .silence {
            await progress("Analyzing audio for silence split points...", 0.14)
            if let smartChunks = try? await SmartAudioAnalyzer.planChunks(
                sourceURL: sourceURL,
                sourcePath: sourcePath,
                durationSec: durationSec,
                settings: settings
            ) {
                return smartChunks
            }
        }

        return ChunkPlanner.plan(
            sourcePath: sourcePath,
            durationSec: durationSec,
            chunkDurationMin: settings.chunkDurationMin
        )
    }

    private func translationSeed(for session: SessionState, settings: AppSettings) -> String {
        guard NativeLanguagePolicy.translationNeeded(
            sourceLang: session.sourceLang,
            targetLang: session.targetLang
        ) else {
            return ""
        }
        let translationOption = ProviderRegistry
            .availableTranslationProviders(settings: settings, targetLang: session.targetLang)
            .providers
            .first { $0.id == session.translationProvider }
        let cloudTranslationReady = translationOption?.group == .cloud
        let localTranslationReady = NativeModelCatalog.activeMLXModel(
            settings: settings,
            providerID: session.translationProvider
        ) != nil
        guard cloudTranslationReady || localTranslationReady else {
            return "MLX translation requires a downloaded or located local model."
        }
        return ""
    }

    private func translateChunksIfNeeded(
        _ session: inout SessionState,
        settings: inout AppSettings,
        progress: @Sendable @escaping (String, Double) async -> Void
    ) async {
        guard NativeLanguagePolicy.translationNeeded(
            sourceLang: session.sourceLang,
            targetLang: session.targetLang
        ) else {
            return
        }
        if let cloudProvider = ActiveCloudTranslationProvider.resolve(
            settings: settings,
            providerID: session.translationProvider
        ) {
            await translateChunksWithCloud(
                &session,
                settings: &settings,
                provider: cloudProvider,
                progress: progress
            )
            return
        }

        guard let model = NativeModelCatalog.activeMLXModel(
            settings: settings,
            providerID: session.translationProvider
        ) else {
            let seed = translationSeed(for: session, settings: settings)
            for index in session.chunks.indices where session.chunks[index].status == .done {
                session.chunks[index].translated = seed
                session.chunks[index].status = .error
                session.chunks[index].setTranslation(seed, language: session.targetLang)
            }
            session.registerTranslationLanguage(session.targetLang)
            await progress(seed, 1)
            return
        }

        let translatableIndices = session.chunks.indices.filter { session.chunks[$0].status == .done }
        guard !translatableIndices.isEmpty else { return }
        await releaseASRBeforeLocalMLX()

        var completedTranslations = 0
        for (offset, index) in translatableIndices.enumerated() {
            let chunkNumber = offset + 1
            let total = translatableIndices.count
            let fraction = 0.84 + (Double(offset) / Double(max(1, total))) * 0.14
            await progress("Translating segment \(chunkNumber) / \(total) with MLX...", min(0.98, fraction))

            do {
                let translatedCues = try await translateCuesIfAvailable(
                    session.chunks[index].originalCues ?? [],
                    targetLang: session.targetLang,
                    metadata: session.metadata,
                    glossary: settings.glossary,
                    model: model,
                    promptPresets: settings.promptPresets
                )
                let translated = translatedCues.isEmpty
                    ? try await mlxEngine.translate(
                        text: session.chunks[index].original,
                        targetLang: session.targetLang,
                        metadata: session.metadata,
                        glossary: settings.glossary,
                        model: model,
                        promptPresets: settings.promptPresets
                    )
                    : translatedCues.map(\.text).joined(separator: "\n")
                let glossaryTranslation = applyTranslationGlossary(text: translated, cues: translatedCues, settings: settings)
                session.chunks[index].translated = glossaryTranslation.text
                session.chunks[index].setTranslation(
                    glossaryTranslation.text,
                    language: session.targetLang,
                    provider: model.id,
                    cues: glossaryTranslation.cues.isEmpty ? nil : glossaryTranslation.cues
                )
                completedTranslations += 1
            } catch {
                AppLogger.shared.error("Segment \(index + 1)/\(session.chunks.count) MLX translation failed: \(error.localizedDescription)", settings: settings)
                let failureMessage = "MLX translation failed: \(error.localizedDescription)"
                session.chunks[index].translated = failureMessage
                session.chunks[index].setTranslation(failureMessage, language: session.targetLang)
                session.chunks[index].status = .error
            }
        }
        if completedTranslations > 0 {
            session.registerTranslationLanguage(session.targetLang)
        }
    }

    private func translateCurrentChunkIfNeeded(
        _ session: inout SessionState,
        index: Int,
        settings: inout AppSettings,
        progress: @Sendable @escaping (String, Double) async -> Void
    ) async {
        guard session.chunks.indices.contains(index) else { return }
        guard NativeLanguagePolicy.translationNeeded(
            sourceLang: session.sourceLang,
            targetLang: session.targetLang
        ) else {
            return
        }

        if let cloudProvider = ActiveCloudTranslationProvider.resolve(
            settings: settings,
            providerID: session.translationProvider
        ) {
            await translateCurrentChunkWithCloud(
                &session,
                index: index,
                settings: &settings,
                provider: cloudProvider,
                progress: progress
            )
            return
        }

        guard let model = NativeModelCatalog.activeMLXModel(
            settings: settings,
            providerID: session.translationProvider
        ) else {
            session.chunks[index].translated = translationSeed(for: session, settings: settings)
            session.chunks[index].status = .error
            session.chunks[index].setTranslation(session.chunks[index].translated, language: session.targetLang)
            session.registerTranslationLanguage(session.targetLang)
            await progress(session.chunks[index].translated, 1)
            return
        }
        await releaseASRBeforeLocalMLX()

        await progress("Translating segment \(index + 1) / \(session.chunks.count) with MLX...", 0.78)
        do {
            let sourceCues = session.chunks[index].originalCues ?? []
            let translatedCues = try await translateCuesIfAvailable(
                sourceCues,
                targetLang: session.targetLang,
                metadata: session.metadata,
                glossary: settings.glossary,
                model: model,
                promptPresets: settings.promptPresets
            )
            let translated = translatedCues.isEmpty
                ? try await mlxEngine.translate(
                    text: session.chunks[index].original,
                    targetLang: session.targetLang,
                    metadata: session.metadata,
                    glossary: settings.glossary,
                    model: model,
                    promptPresets: settings.promptPresets
                )
                : translatedCues.map(\.text).joined(separator: "\n")
            let glossaryTranslation = applyTranslationGlossary(text: translated, cues: translatedCues, settings: settings)
            session.chunks[index].translated = glossaryTranslation.text
            session.chunks[index].setTranslation(
                glossaryTranslation.text,
                language: session.targetLang,
                provider: model.id,
                cues: glossaryTranslation.cues.isEmpty ? nil : glossaryTranslation.cues
            )
            session.registerTranslationLanguage(session.targetLang)
            AppLogger.shared.info("Segment \(index + 1)/\(session.chunks.count) translation complete.", settings: settings)
        } catch {
            AppLogger.shared.error("Segment \(index + 1)/\(session.chunks.count) MLX translation failed: \(error.localizedDescription)", settings: settings)
            let failureMessage = "MLX translation failed: \(error.localizedDescription)"
            session.chunks[index].translated = failureMessage
            session.chunks[index].setTranslation(failureMessage, language: session.targetLang)
            session.chunks[index].status = .error
        }
    }

    private func translateChunksWithCloud(
        _ session: inout SessionState,
        settings: inout AppSettings,
        provider: ActiveCloudTranslationProvider,
        progress: @Sendable @escaping (String, Double) async -> Void
    ) async {
        let translatableIndices = session.chunks.indices.filter { session.chunks[$0].status == .done }
        guard !translatableIndices.isEmpty else { return }

        var completedTranslations = 0
        for (offset, index) in translatableIndices.enumerated() {
            let chunkNumber = offset + 1
            let total = translatableIndices.count
            let fraction = 0.84 + (Double(offset) / Double(max(1, total))) * 0.14
            await progress("Translating segment \(chunkNumber) / \(total) with \(provider.label)...", min(0.98, fraction))

            do {
                let sourceCues = session.chunks[index].originalCues ?? []
                let translatedCues = try await cloudEngine.translateCues(
                    sourceCues,
                    targetLang: session.targetLang,
                    metadata: session.metadata,
                    glossary: settings.glossary,
                    provider: provider,
                    promptPresets: settings.promptPresets
                )
                let translated = translatedCues.isEmpty
                    ? try await cloudEngine.translate(
                        text: session.chunks[index].original,
                        targetLang: session.targetLang,
                        metadata: session.metadata,
                        glossary: settings.glossary,
                        provider: provider,
                        promptPresets: settings.promptPresets
                    )
                    : translatedCues.map(\.text).joined(separator: "\n")
                let glossaryTranslation = applyTranslationGlossary(text: translated, cues: translatedCues, settings: settings)
                session.chunks[index].translated = glossaryTranslation.text
                session.chunks[index].setTranslation(
                    glossaryTranslation.text,
                    language: session.targetLang,
                    provider: provider.id,
                    cues: glossaryTranslation.cues.isEmpty ? nil : glossaryTranslation.cues
                )
                completedTranslations += 1

                let usageDelta = await cloudEngine.takeLastUsage()
                UsageRecorder.record(
                    into: &settings.usage,
                    providerId: provider.id,
                    model: provider.model,
                    delta: usageDelta,
                    audioMinutes: 0,
                    purpose: "translation"
                )
            } catch {
                AppLogger.shared.error("Segment \(index + 1)/\(session.chunks.count) \(provider.label) translation failed: \(error.localizedDescription)", settings: settings)
                let failureMessage = "\(provider.label) translation failed: \(error.localizedDescription)"
                session.chunks[index].translated = failureMessage
                session.chunks[index].setTranslation(failureMessage, language: session.targetLang)
                session.chunks[index].status = .error
            }
        }

        if completedTranslations > 0 {
            session.registerTranslationLanguage(session.targetLang)
        }
    }

    private func translateCurrentChunkWithCloud(
        _ session: inout SessionState,
        index: Int,
        settings: inout AppSettings,
        provider: ActiveCloudTranslationProvider,
        progress: @Sendable @escaping (String, Double) async -> Void
    ) async {
        await progress("Translating segment \(index + 1) / \(session.chunks.count) with \(provider.label)...", 0.78)
        do {
            let sourceCues = session.chunks[index].originalCues ?? []
            let translatedCues = try await cloudEngine.translateCues(
                sourceCues,
                targetLang: session.targetLang,
                metadata: session.metadata,
                glossary: settings.glossary,
                provider: provider,
                promptPresets: settings.promptPresets
            )
            let translated = translatedCues.isEmpty
                ? try await cloudEngine.translate(
                    text: session.chunks[index].original,
                    targetLang: session.targetLang,
                    metadata: session.metadata,
                    glossary: settings.glossary,
                    provider: provider,
                    promptPresets: settings.promptPresets
                )
                : translatedCues.map(\.text).joined(separator: "\n")
            let glossaryTranslation = applyTranslationGlossary(text: translated, cues: translatedCues, settings: settings)
            session.chunks[index].translated = glossaryTranslation.text
            session.chunks[index].setTranslation(
                glossaryTranslation.text,
                language: session.targetLang,
                provider: provider.id,
                cues: glossaryTranslation.cues.isEmpty ? nil : glossaryTranslation.cues
            )
            session.registerTranslationLanguage(session.targetLang)

            let usageDelta = await cloudEngine.takeLastUsage()
            UsageRecorder.record(
                into: &settings.usage,
                providerId: provider.id,
                model: provider.model,
                delta: usageDelta,
                audioMinutes: 0,
                purpose: "translation"
            )

            AppLogger.shared.info("Segment \(index + 1)/\(session.chunks.count) translation complete.", settings: settings)
        } catch {
            AppLogger.shared.error("Segment \(index + 1)/\(session.chunks.count) \(provider.label) translation failed: \(error.localizedDescription)", settings: settings)
            let failureMessage = "\(provider.label) translation failed: \(error.localizedDescription)"
            session.chunks[index].translated = failureMessage
            session.chunks[index].setTranslation(failureMessage, language: session.targetLang)
            session.chunks[index].status = .error
        }
    }

    private func translateCuesIfAvailable(
        _ cues: [TranscriptCue],
        targetLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        model: ActiveMLXModel,
        promptPresets: [String: PromptPresetSettings]
    ) async throws -> [TranscriptCue] {
        guard !cues.isEmpty else { return [] }
        return try await mlxEngine.translateCues(
            cues,
            targetLang: targetLang,
            metadata: metadata,
            glossary: glossary,
            model: model,
            promptPresets: promptPresets
        )
    }

    private func applySourceGlossary(
        text: String,
        cues: [TranscriptCue],
        settings: AppSettings
    ) -> (text: String, cues: [TranscriptCue], count: Int) {
        guard !settings.glossary.isEmpty else {
            return (text, cues, 0)
        }

        let textResult = GlossaryTextRewriter.apply(to: text, entries: settings.glossary, target: .source)
        let cueResult = GlossaryTextRewriter.apply(to: cues, entries: settings.glossary, target: .source)
        let rewrittenText = cueResult.1 > 0 && !cueResult.0.isEmpty
            ? cueResult.0.map(\.text).joined(separator: " ")
            : textResult.text
        return (rewrittenText, cueResult.0.isEmpty ? cues : cueResult.0, textResult.count + cueResult.1)
    }

    private func applyTranslationGlossary(
        text: String,
        cues: [TranscriptCue],
        settings: AppSettings
    ) -> (text: String, cues: [TranscriptCue], count: Int) {
        guard !settings.glossary.isEmpty else {
            return (text, cues, 0)
        }

        let cueResult = GlossaryTextRewriter.apply(to: cues, entries: settings.glossary, target: .translation)
        if cueResult.1 > 0 && !cueResult.0.isEmpty {
            return (cueResult.0.map(\.text).joined(separator: "\n"), cueResult.0, cueResult.1)
        }

        let textResult = GlossaryTextRewriter.apply(to: text, entries: settings.glossary, target: .translation)
        return (textResult.text, cues, textResult.count)
    }

    private func markAllChunks(
        _ session: inout SessionState,
        status: ChunkStatus,
        original: String,
        translated: String
    ) {
        for index in session.chunks.indices {
            session.chunks[index].status = status
            session.chunks[index].original = original
            session.chunks[index].translated = translated
        }
    }

    private func markCurrentChunk(
        _ session: inout SessionState,
        status: ChunkStatus,
        original: String,
        translated: String
    ) {
        guard session.chunks.indices.contains(session.currentChunkIndex) else { return }
        session.chunks[session.currentChunkIndex].status = status
        session.chunks[session.currentChunkIndex].original = original
        session.chunks[session.currentChunkIndex].translated = translated
    }
}
