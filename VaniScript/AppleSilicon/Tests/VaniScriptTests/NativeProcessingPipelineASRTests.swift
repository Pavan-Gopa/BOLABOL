import AVFoundation
import Foundation
import Testing
import VaniScriptCore
import VaniScriptRuntime
@testable import VaniScript

@Suite("Native processing local ASR", .serialized)
struct NativeProcessingPipelineASRTests {
    init() {
        LocalModelVerification.skipVerificationForTesting = true
    }

    @Test("shared pipeline route canonicalizes source language and preserves Whisper cues")
    func sharedRoutePreservesCues() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptPipelineASR-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let descriptor = try #require(NativeModelCatalog.descriptor(for: "whisper-small-multilingual"))
        var settings = AppSettings.defaults
        settings.localAsrModels[descriptor.id] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            path: root.path,
            runtime: descriptor.settingsRuntime
        )
        let audioURL = root.appendingPathComponent("chunk.wav")
        try Data([1]).write(to: audioURL)
        let cues = [TranscriptCue(startSec: 0.4, endSec: 1.1, text: "hello")]
        let log = PipelineASRRequestLog()
        let factories = LocalASREngineRouterFactories(
            whisperKit: { model in
                return PipelineSpyLocalASREngine(
                    descriptor: model.descriptor,
                    result: LocalASRResult(text: "hello", cues: cues),
                    log: log
                )
            },
            parakeet: { _ in
                throw LocalASREngineError.unsupportedModel("unexpected Parakeet factory call")
            },
            canary: { _ in
                throw LocalASREngineError.unsupportedModel("unexpected Canary factory call")
            }
        )
        let pipeline = NativeProcessingPipeline(
            localASRRouter: LocalASREngineRouter(factories: factories)
        )

        let result = try await pipeline.transcribeLocalASR(
            audioURL: audioURL,
            sourceLang: "English",
            settings: settings,
            providerID: descriptor.id,
            progress: { _ in }
        )

        #expect(result.text == "hello")
        #expect(result.cues == cues)
        let requests = await log.requests
        #expect(requests.count == 1)
        #expect(requests.first?.languageHint == "en")
        #expect(requests.first?.translateToEnglish == false)
    }

    @Test("maps relative timed cues to absolute chunk time once without fallback")
    func mapsTimedCuesToChunkOffsetOnce() throws {
        let chunk = ChunkData(
            index: 0,
            filePath: "",
            durationSec: 30,
            startSec: 120,
            endSec: 150,
            original: "",
            translated: "",
            status: .pending,
            approved: false
        )
        let timed = LocalASRResult(
            text: "first second",
            cues: [
                TranscriptCue(
                    startSec: 1,
                    endSec: 2,
                    text: "first",
                    words: [TranscriptWord(startSec: 1.2, endSec: 1.8, text: "first")]
                ),
                TranscriptCue(startSec: 4, endSec: 5, text: "second"),
            ]
        )

        let mapped = NativeProcessingPipeline.transcriptCues(
            from: timed,
            chunk: chunk,
            fallbackText: timed.text
        )
        #expect(mapped.map(\.text) == ["first", "second"])
        #expect(mapped.map(\.startSec) == [121, 124])
        #expect(mapped.map(\.endSec) == [122, 125])
        #expect(abs((mapped[0].words?.first?.startSec ?? -1) - 121.2) < 0.001)

        let emptyTimed = NativeProcessingPipeline.transcriptCues(
            from: LocalASRResult(text: "timed but empty", cues: []),
            chunk: chunk,
            fallbackText: "timed but empty"
        )
        #expect(emptyTimed.isEmpty)

        let textOnly = NativeProcessingPipeline.transcriptCues(
            from: LocalASRResult(text: "fallback"),
            chunk: chunk,
            fallbackText: "fallback"
        )
        #expect(textOnly.map(\.text) == ["fallback"])
        #expect(textOnly.allSatisfy { $0.startSec >= chunk.startSec && $0.endSec <= chunk.endSec && $0.startSec <= $0.endSec })
        #expect(textOnly.allSatisfy { $0.endSec - $0.startSec <= 5.0 })
        #expect(textOnly.last?.endSec ?? 0 < chunk.endSec)
        #expect(textOnly.first?.words?.first?.startSec == 120.0)
        #expect(textOnly.first?.words?.first?.endSec == 125.0)
    }

    @Test("source and target aliases control translation independently")
    func sourceTargetTranslationDecision() {
        #expect(!NativeLanguagePolicy.translationNeeded(sourceLang: "de-DE", targetLang: "German"))
        #expect(!NativeLanguagePolicy.translationNeeded(sourceLang: "English", targetLang: "same"))
        #expect(NativeLanguagePolicy.translationNeeded(sourceLang: "auto", targetLang: "English"))
    }

    @Test("recovers a late empty MLX cue batch without discarding prior translations")
    func recoversLateEmptyMLXCueBatch() async throws {
        let cues: [TranscriptCue] = (0..<6).map { index -> TranscriptCue in
            let startSec: Double = Double(index * 2 + 1)
            let endSec: Double = Double(index * 2 + 2)
            let prefix: String = "source\(index)-"
            let padding: String = String(repeating: "x", count: 692)
            let text: String = prefix + padding
            return TranscriptCue(startSec: startSec, endSec: endSec, text: text)
        }
        let log = MLXGenerationRequestLog()
        let engine = MLXTextGenerationEngine(generationOverride: { prompt, _, sourceLength, _ in
            let request = await log.record(prompt: prompt, sourceLength: sourceLength)
            switch request {
            case 1:
                return mlxCueBatchOutput(["batch-one-0", "batch-one-1"])
            case 2:
                return mlxCueBatchOutput(["batch-two-2", "batch-two-3"])
            case 3:
                return "<<<END>>>"
            case 4:
                return mlxCueBatchOutput(["recovered-4"])
            case 5:
                return mlxCueBatchOutput(["recovered-5"])
            default:
                return "unexpected request"
            }
        })
        let model = try #require(makeTestMLXModel())

        let translated: [TranscriptCue] = try await engine.translateCues(
            cues,
            targetLang: "Russian",
            metadata: .empty,
            glossary: [],
            model: model
        )

        let translatedTexts: [String] = translated.map { cue in cue.text }
        let expectedTexts: [String] = [
            "batch-one-0",
            "batch-one-1",
            "batch-two-2",
            "batch-two-3",
            "recovered-4",
            "recovered-5",
        ]
        #expect(translatedTexts == expectedTexts)

        let translatedStartTimes: [Double] = translated.map { cue in cue.startSec }
        let sourceStartTimes: [Double] = cues.map { cue in cue.startSec }
        #expect(translatedStartTimes == sourceStartTimes)

        let translatedEndTimes: [Double] = translated.map { cue in cue.endSec }
        let sourceEndTimes: [Double] = cues.map { cue in cue.endSec }
        #expect(translatedEndTimes == sourceEndTimes)

        #expect(translated.allSatisfy { cue in
            !cue.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        })
        #expect(await log.sourceLengths == [1_400, 1_400, 1_400, 700, 700])
    }

    @Test("recovers single cue XML failure through terminal strategy without losing prior batch results")
    func recoversSingleCueXMLFailureThroughTerminalStrategy() async throws {
        let cues: [TranscriptCue] = (0..<6).map { index -> TranscriptCue in
            let startSec: Double = Double(index * 2 + 1)
            let endSec: Double = Double(index * 2 + 2)
            let prefix: String = "source\(index)-"
            let padding: String = String(repeating: "x", count: 692)
            let text: String = prefix + padding
            return TranscriptCue(startSec: startSec, endSec: endSec, text: text)
        }
        let log = MLXGenerationRequestLog()
        let engine = MLXTextGenerationEngine(generationOverride: { prompt, _, sourceLength, _ in
            let requestIndex = await log.record(prompt: prompt, sourceLength: sourceLength)
            switch requestIndex {
            case 1:
                return mlxCueBatchOutput(["batch-one-0", "batch-one-1"])
            case 2:
                return mlxCueBatchOutput(["batch-two-2", "batch-two-3"])
            case 3:
                return "<<<END>>>"
            case 4:
                return mlxCueBatchOutput(["recovered-4"])
            case 5:
                return "<<<END>>>"
            case 6:
                return "<<END>>"
            case 7:
                return "<<<TRANSLATION>>>\nterminal-recovered-5\n<<<END>>>"
            default:
                return "unexpected request"
            }
        })
        let model = try #require(makeTestMLXModel())

        let translated: [TranscriptCue] = try await engine.translateCues(
            cues,
            targetLang: "Russian",
            metadata: .empty,
            glossary: [],
            model: model
        )

        let translatedTexts: [String] = translated.map { cue in cue.text }
        let expectedTexts: [String] = [
            "batch-one-0",
            "batch-one-1",
            "batch-two-2",
            "batch-two-3",
            "recovered-4",
            "terminal-recovered-5",
        ]
        #expect(translatedTexts == expectedTexts)

        let translatedStartTimes: [Double] = translated.map { cue in cue.startSec }
        let sourceStartTimes: [Double] = cues.map { cue in cue.startSec }
        #expect(translatedStartTimes == sourceStartTimes)

        let translatedEndTimes: [Double] = translated.map { cue in cue.endSec }
        let sourceEndTimes: [Double] = cues.map { cue in cue.endSec }
        #expect(translatedEndTimes == sourceEndTimes)

        #expect(translated.allSatisfy { cue in
            !cue.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        })

        let requests = await log.requests
        #expect(requests.count == 7)

        for i in 0..<5 {
            #expect(requests[i].prompt.contains("<cue id="))
        }

        #expect(requests[5].prompt.contains("single-cue"))
        #expect(!requests[5].prompt.contains("<cue id="))
        #expect(requests[5].prompt.contains("<<<TRANSLATION>>>"))
        #expect(requests[6].prompt.contains("single-cue"))
        #expect(!requests[6].prompt.contains("<cue id="))
        #expect(requests[6].prompt.contains("Recovery requirement"))
        #expect(requests[6].prompt.contains("<<<TRANSLATION>>>"))
    }

    @Test("keeps prior translations and adds a source fallback after empty terminal retry")
    func keepsPriorTranslationsAndAddsSourceFallbackAfterEmptyTerminalRetry() async throws {
        let cues: [TranscriptCue] = (0..<6).map { index -> TranscriptCue in
            let startSec: Double = Double(index * 2 + 1)
            let endSec: Double = Double(index * 2 + 2)
            let prefix: String = "source\(index)-"
            let padding: String = String(repeating: "x", count: 692)
            let text: String = prefix + padding
            return TranscriptCue(startSec: startSec, endSec: endSec, text: text)
        }
        let log = MLXGenerationRequestLog()
        let engine = MLXTextGenerationEngine(generationOverride: { prompt, _, sourceLength, _ in
            let requestIndex = await log.record(prompt: prompt, sourceLength: sourceLength)
            switch requestIndex {
            case 1:
                return mlxCueBatchOutput(["batch-one-0", "batch-one-1"])
            case 2:
                return mlxCueBatchOutput(["batch-two-2", "batch-two-3"])
            case 3:
                return "<<<END>>>"
            case 4:
                return mlxCueBatchOutput(["recovered-4"])
            case 5:
                return "<<<END>>>"
            case 6:
                return "<<END>>"
            case 7:
                return "<<END>>"
            default:
                return "unexpected request"
            }
        })
        let model = try #require(makeTestMLXModel())

        let translated: [TranscriptCue] = try await engine.translateCues(
            cues,
            targetLang: "Russian",
            metadata: .empty,
            glossary: [],
            model: model
        )

        #expect(translated.count == cues.count)
        #expect(Array(translated.dropLast()).map(\.text) == [
            "batch-one-0",
            "batch-one-1",
            "batch-two-2",
            "batch-two-3",
            "recovered-4",
        ])
        #expect(translated.last?.text == cues[5].text)
        #expect(translated.last?.startSec == cues[5].startSec)
        #expect(translated.last?.endSec == cues[5].endSec)
        #expect(!(translated.last?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))

        let requests = await log.requests
        #expect(requests.count == 7)
        for i in 0..<5 {
            #expect(requests[i].prompt.contains("<cue id="))
        }
        #expect(requests[5].prompt.contains("single-cue"))
        #expect(!requests[5].prompt.contains("<cue id="))
        #expect(requests[5].prompt.contains("<<<TRANSLATION>>>"))
        #expect(requests[6].prompt.contains("single-cue"))
        #expect(!requests[6].prompt.contains("<cue id="))
        #expect(requests[6].prompt.contains("Recovery requirement"))
        #expect(requests[6].prompt.contains("<<<TRANSLATION>>>"))
    }

    @Test("throws explicitly when a single MLX cue cannot be translated")
    func throwsForUnrecoverableSingleMLXCue() async throws {
        let log = MLXGenerationRequestLog()
        let engine = MLXTextGenerationEngine(generationOverride: { prompt, _, sourceLength, _ in
            _ = await log.record(prompt: prompt, sourceLength: sourceLength)
            return "<<<END>>>"
        })
        let model = try #require(makeTestMLXModel())

        await #expect(throws: CueBatchTranslationError.emptyOutput) {
            _ = try await engine.translateCues(
                [TranscriptCue(startSec: 4, endSec: 5, text: "single source cue")],
                targetLang: "Russian",
                metadata: .empty,
                glossary: [],
                model: model
            )
        }
        #expect(await log.sourceLengths == [17, 17, 17])
    }

    @Test("bounds MLX cue recovery to the finite binary split tree")
    func boundsMLXCueRecovery() async throws {
        let cues: [TranscriptCue] = [
            TranscriptCue(startSec: 0, endSec: 1, text: "one"),
            TranscriptCue(startSec: 1, endSec: 2, text: "two"),
            TranscriptCue(startSec: 2, endSec: 3, text: "three"),
            TranscriptCue(startSec: 3, endSec: 4, text: "four"),
        ]
        let log = MLXGenerationRequestLog()
        let engine = MLXTextGenerationEngine(generationOverride: { prompt, _, sourceLength, _ in
            let request = await log.record(prompt: prompt, sourceLength: sourceLength)
            switch request {
            case 3, 4, 6:
                return mlxCueBatchOutput(["leaf translation"])
            case 1, 2, 5, 7, 8, 9:
                return "<<<END>>>"
            default:
                return "unexpected request"
            }
        })
        let model = try #require(makeTestMLXModel())

        let translated: [TranscriptCue] = try await engine.translateCues(
            cues,
            targetLang: "Russian",
            metadata: .empty,
            glossary: [],
            model: model
        )
        #expect(translated.map(\.text) == ["leaf translation", "leaf translation", "leaf translation", "four"])
        #expect(translated.map(\.startSec) == cues.map(\.startSec))
        #expect(translated.map(\.endSec) == cues.map(\.endSec))
        #expect(await log.sourceLengths == [15, 6, 3, 3, 9, 5, 4, 4, 4])
    }
    @Test("throws when all terminal leaves remain empty without a successful sibling")
    func throwsWhenAllTerminalLeavesRemainEmptyWithoutSuccessfulSibling() async throws {
        let cues: [TranscriptCue] = [
            TranscriptCue(startSec: 0, endSec: 1, text: "first source cue"),
            TranscriptCue(startSec: 1, endSec: 2, text: "second source cue"),
        ]
        let log = MLXGenerationRequestLog()
        let engine = MLXTextGenerationEngine(generationOverride: { prompt, _, sourceLength, _ in
            _ = await log.record(prompt: prompt, sourceLength: sourceLength)
            return "<<<END>>>"
        })
        let model = try #require(makeTestMLXModel())

        await #expect(throws: CueBatchTranslationError.emptyOutput) {
            _ = try await engine.translateCues(
                cues,
                targetLang: "Russian",
                metadata: .empty,
                glossary: [],
                model: model
            )
        }

        let requests = await log.requests
        #expect(requests.count == 7)
        #expect(requests[2].prompt.contains("single-cue"))
        #expect(requests[3].prompt.contains("Recovery requirement"))
        #expect(requests[5].prompt.contains("single-cue"))
        #expect(requests[6].prompt.contains("Recovery requirement"))
    }
    @Test("propagates operational error immediately without split retries")
    func propagatesOperationalErrorImmediatelyWithoutSplitRetries() async throws {
        let cues: [TranscriptCue] = [
            TranscriptCue(startSec: 0, endSec: 1, text: "first cue"),
            TranscriptCue(startSec: 1, endSec: 2, text: "second cue"),
        ]
        let log = MLXGenerationRequestLog()
        let engine = MLXTextGenerationEngine(generationOverride: { prompt, _, sourceLength, _ in
            _ = await log.record(prompt: prompt, sourceLength: sourceLength)
            throw MLXTextGenerationError.generationTimedOut(seconds: 30)
        })
        let model = try #require(makeTestMLXModel())

        await #expect(throws: MLXTextGenerationError.self) {
            _ = try await engine.translateCues(
                cues,
                targetLang: "Russian",
                metadata: .empty,
                glossary: [],
                model: model
            )
        }

        let requests = await log.requests
        #expect(requests.count == 1)
    }

    @Test("marks chunk error and preserves original transcript on MLX translation failure")
    func marksChunkErrorAndPreservesOriginalOnMLXTranslationFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptASRMLXFail-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audioURL = root.appendingPathComponent("test.wav")
        try writeValidTestWAV(to: audioURL)

        let log = MLXGenerationRequestLog()
        let mlxEngine = MLXTextGenerationEngine(generationOverride: { prompt, _, sourceLength, _ in
            _ = await log.record(prompt: prompt, sourceLength: sourceLength)
            throw CueBatchTranslationError.emptyOutput
        })

        let asrDescriptor = try #require(NativeModelCatalog.descriptor(for: "whisper-small-multilingual"))
        let translationModelID = "qwen35-4b-4bit"

        var settings = AppSettings.defaults
        settings.defaultSourceLang = "en"
        settings.defaultTargetLang = "ru"
        settings.transcriptionProvider = asrDescriptor.id
        settings.translationProvider = translationModelID
        settings.localAsrModels[asrDescriptor.id] = LocalModelState(
            status: .downloaded,
            label: asrDescriptor.displayName,
            path: root.path,
            runtime: asrDescriptor.settingsRuntime
        )
        settings.localTranslationModels[translationModelID] = LocalModelState(
            status: .downloaded,
            label: settings.localTranslationModels[translationModelID]?.label ?? "Qwen 3.5 4B 4-bit",
            path: root.path,
            runtime: .mlx
        )

        let sourceCue = TranscriptCue(
            startSec: 0,
            endSec: 2,
            text: "Source speech",
            words: [TranscriptWord(startSec: 0, endSec: 2, text: "Source speech")]
        )
        let asrLog = PipelineASRRequestLog()
        let factories = LocalASREngineRouterFactories(
            whisperKit: { _ in
                PipelineSpyLocalASREngine(
                    descriptor: asrDescriptor,
                    result: LocalASRResult(text: "Source speech", cues: [sourceCue]),
                    log: asrLog
                )
            },
            parakeet: { _ in
                PipelineSpyLocalASREngine(
                    descriptor: asrDescriptor,
                    result: LocalASRResult(text: "Source speech", cues: [sourceCue]),
                    log: asrLog
                )
            },
            canary: { _ in
                PipelineSpyLocalASREngine(
                    descriptor: asrDescriptor,
                    result: LocalASRResult(text: "Source speech", cues: [sourceCue]),
                    log: asrLog
                )
            }
        )
        let localASRRouter = LocalASREngineRouter(factories: factories)
        let pipeline = NativeProcessingPipeline(
            localASRRouter: localASRRouter,
            mlxEngine: mlxEngine
        )

        let chunk = ChunkData(
            index: 0,
            filePath: audioURL.path,
            durationSec: 2.0,
            startSec: 0.0,
            endSec: 2.0,
            original: "Source speech",
            translated: "",
            originalCues: [sourceCue],
            status: .done,
            approved: false
        )

        let session = SessionState(
            sourceFile: audioURL.path,
            sourceFileName: "test.wav",
            durationSec: 2.0,
            metadata: .empty,
            sourceLang: "en",
            targetLang: "ru",
            transcriptionProvider: asrDescriptor.id,
            translationProvider: translationModelID,
            outputFormats: [.txt],
            chunks: [chunk],
            currentChunkIndex: 0
        )
        let progressLog = PipelineProgressLog()
        let result = await pipeline.processCurrentChunk(session: session, settings: &settings) { message, _ in
            await progressLog.record(message)
        }

        #expect(result.chunks[0].status == .error)
        #expect(result.chunks[0].original == "Source speech")
        #expect(result.chunks[0].originalCues == [sourceCue])
        #expect(!result.chunks[0].translated.isEmpty)
        #expect(result.chunks[0].translated.contains("MLX translation failed"))
        let requests = await log.requests
        #expect(requests.count > 0)
        let progressMessages = await progressLog.messages
        #expect(progressMessages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.contains("MLX translation failed") }))
        #expect(!progressMessages.contains(where: { $0.lowercased().contains("ready for review") }))
    }

    @Test("batch cloud route bypasses local ASR")
    func batchCloudBypassesLocalASR() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audioURL = root.appendingPathComponent("cloud.wav")
        try writeValidTestWAV(to: audioURL)
        var settings = AppSettings.defaults
        settings.geminiKey = "test-key"
        settings.geminiKeys = ["test-key"]
        let localLog = PipelineASRRequestLog()
        let cloud = PipelineSpyCloudTranscriber()
        let factories = LocalASREngineRouterFactories(
            whisperKit: { descriptor in PipelineSpyLocalASREngine(descriptor: descriptor.descriptor, result: .init(text: "local", cues: []), log: localLog) },
            parakeet: { _ in throw LocalASREngineError.unsupportedModel("unexpected local route") },
            canary: { _ in throw LocalASREngineError.unsupportedModel("unexpected local route") }
        )
        let pipeline = NativeProcessingPipeline(localASRRouter: LocalASREngineRouter(factories: factories), cloudTranscriptionEngine: cloud)
        let transcriber = pipeline.makeBatchAudioTranscriber(workspaceRoot: root.appendingPathComponent("work"), sourceLang: "en", settings: settings, providerID: "gemini-cloud")
        let result = try await transcriber.transcribe(sourceURL: audioURL, resumedCheckpoints: [], progress: { _ in }, checkpoint: { _ in })

        #expect(result.checkpoints.first?.text == "cloud")
        #expect(await cloud.callCount == 1)
        #expect(await cloud.sourceLanguages == [NativeLanguagePolicy.autoCode])
        #expect(await localLog.requests.isEmpty)
    }

    @Test("missing cloud readiness fails honestly without local ASR")
    func missingCloudReadinessFailsHonestly() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audioURL = root.appendingPathComponent("missing.wav")
        try writeValidTestWAV(to: audioURL)
        let localLog = PipelineASRRequestLog()
        let factories = LocalASREngineRouterFactories(
            whisperKit: { descriptor in PipelineSpyLocalASREngine(descriptor: descriptor.descriptor, result: .init(text: "local", cues: []), log: localLog) },
            parakeet: { _ in throw LocalASREngineError.unsupportedModel("unexpected local route") },
            canary: { _ in throw LocalASREngineError.unsupportedModel("unexpected local route") }
        )
        let settings = AppSettings.defaults
        let pipeline = NativeProcessingPipeline(localASRRouter: LocalASREngineRouter(factories: factories))
        let transcriber = pipeline.makeBatchAudioTranscriber(workspaceRoot: root.appendingPathComponent("work"), sourceLang: "en", settings: settings, providerID: "gemini-cloud")
        let expected = NativeProcessingReadiness.evaluate(settings: settings, sourceLang: "en", targetLang: "en", transcriptionProvider: "gemini-cloud", translationProvider: settings.translationProvider).transcriptionMessage

        do {
            _ = try await transcriber.transcribe(sourceURL: audioURL, resumedCheckpoints: [], progress: { _ in }, checkpoint: { _ in })
            Issue.record("Expected missing cloud readiness to fail")
        } catch {
            #expect(error.localizedDescription == expected)
        }
        #expect(await localLog.requests.isEmpty)
    }

    @Test("batch silence planning persists absolute checkpoints and resumes by index")
    func batchSilencePlanningAndResume() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptBatchSilence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audioURL = root.appendingPathComponent("silence.wav")
        try writeSilenceSplitWAV(to: audioURL)

        let descriptor = try #require(NativeModelCatalog.descriptor(for: "whisper-small-multilingual"))
        var settings = AppSettings.defaults
        settings.sliceMode = .silence
        settings.chunkDurationMin = 1
        settings.silenceThreshDb = -40
        settings.minSilenceMs = 1_000
        settings.localAsrModels[descriptor.id] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            path: root.path,
            runtime: descriptor.settingsRuntime
        )
        let requests = PipelineASRRequestLog()
        let factories = LocalASREngineRouterFactories(
            whisperKit: { model in
                PipelineSpyLocalASREngine(
                    descriptor: model.descriptor,
                    result: LocalASRResult(
                        text: "chunk",
                        cues: [
                            TranscriptCue(
                                startSec: 1,
                                endSec: 2,
                                text: "chunk",
                                words: [TranscriptWord(startSec: 1.25, endSec: 1.75, text: "chunk")]
                            )
                        ]
                    ),
                    log: requests
                )
            },
            parakeet: { _ in
                throw LocalASREngineError.unsupportedModel("unexpected Parakeet factory call")
            },
            canary: { _ in
                throw LocalASREngineError.unsupportedModel("unexpected Canary factory call")
            }
        )
        let pipeline = NativeProcessingPipeline(
            localASRRouter: LocalASREngineRouter(factories: factories)
        )
        let transcriber = pipeline.makeBatchAudioTranscriber(
            workspaceRoot: root.appendingPathComponent("work"),
            sourceLang: "English",
            settings: settings,
            providerID: descriptor.id
        )
        let firstProgress = PipelineBatchProgressLog()
        let firstCheckpointLog = PipelineBatchCheckpointLog()
        let first = try await transcriber.transcribe(
            sourceURL: audioURL,
            resumedCheckpoints: [],
            progress: { value in await firstProgress.record(value) },
            checkpoint: { value in await firstCheckpointLog.record(value) }
        )

        let firstIndexes = first.checkpoints.map(\.index)
        guard first.checkpoints.count >= 2 else {
            Issue.record("silence fixture must produce multiple chunks")
            return
        }
        #expect(firstIndexes == Array(firstIndexes.indices))
        #expect(await firstCheckpointLog.values.last == first.checkpoints)
        #expect(await requests.requests.count == first.checkpoints.count)
        #expect(first.checkpoints[0].cues.first?.startSec == 1)
        #expect(abs((first.checkpoints[1].cues.first?.startSec ?? 0) - 61.5) < 0.05)
        #expect(abs((first.checkpoints[1].cues.first?.words?.first?.startSec ?? 0) - 61.75) < 0.05)
        let firstProgressValues = await firstProgress.values
        #expect(!firstProgressValues.isEmpty)
        #expect(firstProgressValues.first?.detail.phase == .planning)
        #expect(firstProgressValues.first?.totalChunks == nil)
        #expect(firstProgressValues.first?.fraction == 0)
        #expect(firstProgressValues.last?.fraction == 1)
        let firstKnownTotal = firstProgressValues.first(where: { $0.totalChunks != nil })
        #expect(firstKnownTotal?.totalChunks == first.checkpoints.count)
        #expect(firstKnownTotal?.fraction == 0)
        #expect(firstProgressValues.allSatisfy { $0.totalChunks == nil || $0.totalChunks == first.checkpoints.count })
        #expect(!firstProgressValues.contains { $0.totalChunks == 0 || ($0.totalChunks == 1 && first.checkpoints.count > 1) })

        let resumed = try await transcriber.transcribe(
            sourceURL: audioURL,
            resumedCheckpoints: [first.checkpoints[0]],
            progress: { _ in },
            checkpoint: { _ in }
        )
        #expect(resumed.checkpoints == first.checkpoints)
        #expect(await requests.requests.count == first.checkpoints.count + first.checkpoints.count - 1)

        var fixedSettings = settings
        fixedSettings.sliceMode = .fixed
        let fixedRequests = PipelineASRRequestLog()
        let fixedFactories = LocalASREngineRouterFactories(
            whisperKit: { model in
                PipelineSpyLocalASREngine(
                    descriptor: model.descriptor,
                    result: LocalASRResult(text: "fixed", cues: []),
                    log: fixedRequests
                )
            },
            parakeet: { _ in
                throw LocalASREngineError.unsupportedModel("unexpected Parakeet factory call")
            },
            canary: { _ in
                throw LocalASREngineError.unsupportedModel("unexpected Canary factory call")
            }
        )
        let fixedPipeline = NativeProcessingPipeline(
            localASRRouter: LocalASREngineRouter(factories: fixedFactories)
        )
        let fixedTranscriber = fixedPipeline.makeBatchAudioTranscriber(
            workspaceRoot: root.appendingPathComponent("fixed-work"),
            sourceLang: "auto",
            settings: fixedSettings,
            providerID: descriptor.id
        )
        let fixed = try await fixedTranscriber.transcribe(
            sourceURL: audioURL,
            resumedCheckpoints: [],
            progress: { _ in },
            checkpoint: { _ in }
        )
        #expect(fixed.checkpoints.map(\.index) == [0, 1, 2])
        #expect(await fixedRequests.requests.count == 3)
    }

    @Test("batch fixed planning falls back to one short-file chunk")
    func batchFixedPlanningUsesFallbackForShortFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptBatchFixed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audioURL = root.appendingPathComponent("short.wav")
        try writeValidTestWAV(to: audioURL)

        let descriptor = try #require(NativeModelCatalog.descriptor(for: "whisper-small-multilingual"))
        var settings = AppSettings.defaults
        settings.sliceMode = .silence
        settings.chunkDurationMin = 1
        settings.localAsrModels[descriptor.id] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            path: root.path,
            runtime: descriptor.settingsRuntime
        )
        let requests = PipelineASRRequestLog()
        let factories = LocalASREngineRouterFactories(
            whisperKit: { model in
                PipelineSpyLocalASREngine(
                    descriptor: model.descriptor,
                    result: LocalASRResult(text: "fallback", cues: []),
                    log: requests
                )
            },
            parakeet: { _ in
                throw LocalASREngineError.unsupportedModel("unexpected Parakeet factory call")
            },
            canary: { _ in
                throw LocalASREngineError.unsupportedModel("unexpected Canary factory call")
            }
        )
        let pipeline = NativeProcessingPipeline(
            localASRRouter: LocalASREngineRouter(factories: factories)
        )
        let transcriber = pipeline.makeBatchAudioTranscriber(
            workspaceRoot: root.appendingPathComponent("work"),
            sourceLang: "auto",
            settings: settings,
            providerID: descriptor.id
        )
        let result = try await transcriber.transcribe(
            sourceURL: audioURL,
            resumedCheckpoints: [],
            progress: { _ in },
            checkpoint: { _ in }
        )

        #expect(result.checkpoints.map(\.index) == [0])
        #expect(await requests.requests.count == 1)
    }
    @Test("provider invalidation waits for active batch local ASR")
    func providerInvalidationWaitsForActiveBatchLocalASR() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptASRInvalidation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let audioURL = root.appendingPathComponent("blocked.wav")
        try writeValidTestWAV(to: audioURL)
        let descriptor = try #require(NativeModelCatalog.descriptor(for: "whisper-small-multilingual"))
        var settings = AppSettings.defaults
        settings.sliceMode = .fixed
        settings.chunkDurationMin = 1
        settings.localAsrModels[descriptor.id] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            path: root.path,
            runtime: descriptor.settingsRuntime
        )

        let lifecycle = PipelineASRLifecycleLog()
        let engine = PipelineBlockingLocalASREngine(
            descriptor: descriptor,
            result: LocalASRResult(text: "blocked", cues: []),
            lifecycle: lifecycle
        )
        let factories = LocalASREngineRouterFactories(
            whisperKit: { _ in engine },
            parakeet: { _ in
                throw LocalASREngineError.unsupportedModel("unexpected Parakeet factory call")
            },
            canary: { _ in
                throw LocalASREngineError.unsupportedModel("unexpected Canary factory call")
            }
        )
        let scheduler = TranscriptionScheduler()
        let pipeline = NativeProcessingPipeline(
            localASRRouter: LocalASREngineRouter(factories: factories),
            transcriptionScheduler: scheduler
        )
        let transcriber = pipeline.makeBatchAudioTranscriber(
            workspaceRoot: root.appendingPathComponent("work"),
            sourceLang: "en",
            settings: settings,
            providerID: descriptor.id
        )

        let batch = Task {
            try await transcriber.transcribe(
                sourceURL: audioURL,
                resumedCheckpoints: [],
                progress: { _ in },
                checkpoint: { _ in }
            )
        }
        await engine.waitUntilTranscriptionStarts()

        let invalidation = Task {
            await pipeline.invalidateASRBinding()
        }
        await Task.yield()
        #expect(await engine.unloadCount == 0)
        #expect(await engine.maximumOperationOverlap == 1)
        #expect(await lifecycle.events == [.transcribeStarted])

        await engine.releaseTranscription()
        let result = try await batch.value
        await invalidation.value

        #expect(result.checkpoints.map(\.index) == [0])
        #expect(await engine.unloadCount == 1)
        #expect(await engine.maximumOperationOverlap == 1)
        #expect(await lifecycle.events == [
            .transcribeStarted,
            .transcribeFinished,
            .unloadStarted,
            .unloadFinished
        ])
    }

    @Test("batch ordered progress bridge awaits updates and propagates errors")
    func batchOrderedProgressBridgeAndErrorPropagation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptASROrder-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audioURL = root.appendingPathComponent("split.wav")
        try writeSilenceSplitWAV(to: audioURL)

        let descriptor = try #require(NativeModelCatalog.descriptor(for: "whisper-small-multilingual"))
        var settings = AppSettings.defaults
        settings.sliceMode = .silence
        settings.chunkDurationMin = 1
        settings.localAsrModels[descriptor.id] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            path: root.path,
            runtime: descriptor.settingsRuntime
        )
        let requests = PipelineASRRequestLog()
        let factories = LocalASREngineRouterFactories(
            whisperKit: { model in
                PipelineSpyLocalASREngine(
                    descriptor: model.descriptor,
                    result: LocalASRResult(text: "ordered", cues: []),
                    log: requests
                )
            },
            parakeet: { _ in throw LocalASREngineError.unsupportedModel("unexpected") },
            canary: { _ in throw LocalASREngineError.unsupportedModel("unexpected") }
        )
        let pipeline = NativeProcessingPipeline(
            localASRRouter: LocalASREngineRouter(factories: factories)
        )
        let transcriber = pipeline.makeBatchAudioTranscriber(
            workspaceRoot: root.appendingPathComponent("work"),
            sourceLang: "English",
            settings: settings,
            providerID: descriptor.id
        )

        struct ProgressFault: Error, LocalizedError {
            var errorDescription: String? { "Progress persistence write failed" }
        }

        let progressCount = LockedValue<Int>(0)

        await #expect(throws: ProgressFault.self) {
            _ = try await transcriber.transcribe(
                sourceURL: audioURL,
                resumedCheckpoints: [],
                progress: { update in
                    let current = progressCount.get() + 1
                    progressCount.set(current)
                    if current == 2 {
                        throw ProgressFault()
                    }
                },
                checkpoint: { _ in }
            )
        }

        #expect(await requests.requests.count <= 1)
    }

    @Test("batch resumed chunk progress mapping correctly computes fractions for prefix and non-zero ordinals")
    func batchResumedChunkProgressMapping() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptASRResumedProgress-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audioURL = root.appendingPathComponent("split.wav")
        try writeSilenceSplitWAV(to: audioURL)

        let descriptor = try #require(NativeModelCatalog.descriptor(for: "whisper-small-multilingual"))
        var settings = AppSettings.defaults
        settings.sliceMode = .silence
        settings.chunkDurationMin = 1
        settings.localAsrModels[descriptor.id] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            path: root.path,
            runtime: descriptor.settingsRuntime
        )
        let requests = PipelineASRRequestLog()
        let factories = LocalASREngineRouterFactories(
            whisperKit: { model in
                PipelineSpyLocalASREngine(
                    descriptor: model.descriptor,
                    result: LocalASRResult(text: "chunk", cues: []),
                    log: requests
                )
            },
            parakeet: { _ in throw LocalASREngineError.unsupportedModel("unexpected") },
            canary: { _ in throw LocalASREngineError.unsupportedModel("unexpected") }
        )
        let pipeline = NativeProcessingPipeline(
            localASRRouter: LocalASREngineRouter(factories: factories)
        )
        let transcriber = pipeline.makeBatchAudioTranscriber(
            workspaceRoot: root.appendingPathComponent("work"),
            sourceLang: "English",
            settings: settings,
            providerID: descriptor.id
        )

        // First pass: get planned chunks
        let firstProgress = PipelineBatchProgressLog()
        let initialResult = try await transcriber.transcribe(
            sourceURL: audioURL,
            resumedCheckpoints: [],
            progress: { await firstProgress.record($0) },
            checkpoint: { _ in }
        )
        let totalCount = initialResult.checkpoints.count
        guard totalCount >= 3 else {
            Issue.record("Expected at least 3 chunks for prefix and non-prefix testing")
            return
        }

        let checkpoint0 = try #require(initialResult.checkpoints.first(where: { $0.index == 0 }))
        let checkpoint1 = try #require(initialResult.checkpoints.first(where: { $0.index == 1 }))

        // Case 1: Prefix case — resumed semantic index 0, pending ordinals 0 (index 1) and 1 (index 2)
        let prefixEventLog = PipelineBatchEventLog()
        let prefixRequests = PipelineASRRequestLog()
        let prefixFactories = LocalASREngineRouterFactories(
            whisperKit: { model in
                PipelineSpyLocalASREngine(
                    descriptor: model.descriptor,
                    result: LocalASRResult(text: "chunk", cues: []),
                    log: prefixRequests,
                    onTranscribe: { request in
                        await prefixEventLog.recordASR(request)
                    }
                )
            },
            parakeet: { _ in throw LocalASREngineError.unsupportedModel("unexpected") },
            canary: { _ in throw LocalASREngineError.unsupportedModel("unexpected") }
        )
        let prefixPipeline = NativeProcessingPipeline(
            localASRRouter: LocalASREngineRouter(factories: prefixFactories)
        )
        let prefixTranscriber = prefixPipeline.makeBatchAudioTranscriber(
            workspaceRoot: root.appendingPathComponent("work-prefix"),
            sourceLang: "English",
            settings: settings,
            providerID: descriptor.id
        )

        let prefixResumed = [checkpoint0]
        _ = try await prefixTranscriber.transcribe(
            sourceURL: audioURL,
            resumedCheckpoints: prefixResumed,
            progress: { await prefixEventLog.recordProgress($0) },
            checkpoint: { _ in }
        )

        let prefixUpdates = await prefixEventLog.progressValues
        #expect(!prefixUpdates.isEmpty)
        #expect(prefixUpdates.first?.detail.phase == .planning)
        #expect(prefixUpdates.first?.totalChunks == nil)
        #expect(prefixUpdates.first?.fraction == 0.0)
        #expect(prefixUpdates.allSatisfy { $0.totalChunks == nil || $0.totalChunks == totalCount })
        #expect(!prefixUpdates.contains { $0.totalChunks == 0 || ($0.totalChunks == 1 && totalCount > 1) })
        let expectedPrefixInitial = Double(prefixResumed.count) / Double(totalCount) // 1 / total
        let expectedPrefixSecondPending = Double(prefixResumed.count + 1) / Double(totalCount) // 2 / total
        let prefixFirstKnownTotal = prefixUpdates.first(where: { $0.totalChunks != nil })
        #expect(prefixFirstKnownTotal?.totalChunks == totalCount)
        #expect(abs((prefixFirstKnownTotal?.fraction ?? 0) - expectedPrefixInitial) < 0.001)
        #expect(prefixUpdates.last?.fraction == 1.0)

        let prefixPreASR0 = await prefixEventLog.latestProgressBeforeASRRequest(atOrdinal: 0)
        let prefixPreASR1 = await prefixEventLog.latestProgressBeforeASRRequest(atOrdinal: 1)
        let preASR0Fraction = try #require(prefixPreASR0?.fraction)
        let preASR1Fraction = try #require(prefixPreASR1?.fraction)
        #expect(abs(preASR0Fraction - expectedPrefixInitial) < 0.001)
        #expect(abs(preASR1Fraction - expectedPrefixSecondPending) < 0.001)

        // Case 2: Non-prefix case — resumed semantic index 1, pending ordinals 0 (index 0) and 1 (index 2)
        let nonPrefixEventLog = PipelineBatchEventLog()
        let nonPrefixRequests = PipelineASRRequestLog()
        let nonPrefixFactories = LocalASREngineRouterFactories(
            whisperKit: { model in
                PipelineSpyLocalASREngine(
                    descriptor: model.descriptor,
                    result: LocalASRResult(text: "chunk", cues: []),
                    log: nonPrefixRequests,
                    onTranscribe: { request in
                        await nonPrefixEventLog.recordASR(request)
                    }
                )
            },
            parakeet: { _ in throw LocalASREngineError.unsupportedModel("unexpected") },
            canary: { _ in throw LocalASREngineError.unsupportedModel("unexpected") }
        )
        let nonPrefixPipeline = NativeProcessingPipeline(
            localASRRouter: LocalASREngineRouter(factories: nonPrefixFactories)
        )
        let nonPrefixTranscriber = nonPrefixPipeline.makeBatchAudioTranscriber(
            workspaceRoot: root.appendingPathComponent("work-nonprefix"),
            sourceLang: "English",
            settings: settings,
            providerID: descriptor.id
        )

        let nonPrefixResumed = [checkpoint1]
        _ = try await nonPrefixTranscriber.transcribe(
            sourceURL: audioURL,
            resumedCheckpoints: nonPrefixResumed,
            progress: { await nonPrefixEventLog.recordProgress($0) },
            checkpoint: { _ in }
        )

        let nonPrefixUpdates = await nonPrefixEventLog.progressValues
        #expect(!nonPrefixUpdates.isEmpty)
        #expect(nonPrefixUpdates.first?.detail.phase == .planning)
        #expect(nonPrefixUpdates.first?.totalChunks == nil)
        #expect(nonPrefixUpdates.first?.fraction == 0.0)
        #expect(nonPrefixUpdates.allSatisfy { $0.totalChunks == nil || $0.totalChunks == totalCount })
        #expect(!nonPrefixUpdates.contains { $0.totalChunks == 0 || ($0.totalChunks == 1 && totalCount > 1) })
        let expectedNonPrefixInitial = Double(nonPrefixResumed.count) / Double(totalCount) // 1 / total
        let expectedNonPrefixSecondPending = Double(nonPrefixResumed.count + 1) / Double(totalCount) // 2 / total
        let nonPrefixFirstKnownTotal = nonPrefixUpdates.first(where: { $0.totalChunks != nil })
        #expect(nonPrefixFirstKnownTotal?.totalChunks == totalCount)
        #expect(abs((nonPrefixFirstKnownTotal?.fraction ?? 0) - expectedNonPrefixInitial) < 0.001)
        #expect(nonPrefixUpdates.last?.fraction == 1.0)

        let nonPrefixPreASR0 = await nonPrefixEventLog.latestProgressBeforeASRRequest(atOrdinal: 0)
        let nonPrefixPreASR1 = await nonPrefixEventLog.latestProgressBeforeASRRequest(atOrdinal: 1)
        let nonPrefixPreASR0Fraction = try #require(nonPrefixPreASR0?.fraction)
        let nonPrefixPreASR1Fraction = try #require(nonPrefixPreASR1?.fraction)
        #expect(abs(nonPrefixPreASR0Fraction - expectedNonPrefixInitial) < 0.001)
        #expect(abs(nonPrefixPreASR1Fraction - expectedNonPrefixSecondPending) < 0.001)
    }
    @Test("batch invalid chunk index progress mapping throws typed error")
    func batchInvalidChunkIndexProgressMappingThrows() {
        let pendingOrdinalByIndex = [0: 0, 2: 1]
        #expect(throws: InvalidProgressIndexError(index: 1)) {
            _ = try NativeProcessingPipeline.pendingOrdinal(for: 1, pendingOrdinalByIndex: pendingOrdinalByIndex)
        }
    }
    @Test("batch early total chunks reports planned count and alive fraction before processor runs")
    func batchEarlyTotalChunksReporting() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptASREarlyTotal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audioURL = root.appendingPathComponent("short.wav")
        try writeValidTestWAV(to: audioURL)

        let descriptor = try #require(NativeModelCatalog.descriptor(for: "whisper-small-multilingual"))
        var settings = AppSettings.defaults
        settings.sliceMode = .silence
        settings.chunkDurationMin = 1
        settings.localAsrModels[descriptor.id] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            path: root.path,
            runtime: descriptor.settingsRuntime
        )
        let pipeline = NativeProcessingPipeline(
            localASRRouter: LocalASREngineRouter(
                factories: LocalASREngineRouterFactories(
                    whisperKit: { model in
                        PipelineSpyLocalASREngine(
                            descriptor: model.descriptor,
                            result: LocalASRResult(text: "short", cues: []),
                            log: PipelineASRRequestLog()
                        )
                    },
                    parakeet: { _ in throw LocalASREngineError.unsupportedModel("unexpected") },
                    canary: { _ in throw LocalASREngineError.unsupportedModel("unexpected") }
                )
            )
        )
        let transcriber = pipeline.makeBatchAudioTranscriber(
            workspaceRoot: root.appendingPathComponent("work"),
            sourceLang: "auto",
            settings: settings,
            providerID: descriptor.id
        )

        let progressLog = PipelineBatchProgressLog()
        _ = try await transcriber.transcribe(
            sourceURL: audioURL,
            resumedCheckpoints: [],
            progress: { await progressLog.record($0) },
            checkpoint: { _ in }
        )

        let updates = await progressLog.values
        #expect(!updates.isEmpty)
        #expect(updates.first?.detail.phase == .planning)
        #expect(updates.first?.totalChunks == nil)
        #expect(updates.contains { $0.totalChunks == 1 && $0.detail.phase == .transcribing })
        #expect(updates.last?.fraction == 1.0)
    }

    @Test("batch truthful audio position coverage produces monotonic fraction across segment positions")
    func batchTruthfulAudioPositionCoverageAndMonotonicity() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptASRTruthful-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audioURL = root.appendingPathComponent("test.wav")
        try writeValidTestWAV(to: audioURL)

        let descriptor = try #require(NativeModelCatalog.descriptor(for: "whisper-small-multilingual"))
        var settings = AppSettings.defaults
        settings.sliceMode = .fixed
        settings.chunkDurationMin = 5
        settings.localAsrModels[descriptor.id] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            path: root.path,
            runtime: descriptor.settingsRuntime
        )

        actor ProgressScriptedEngine: LocalASREngine {
            nonisolated let descriptor: LocalASRModelDescriptor
            init(descriptor: LocalASRModelDescriptor) { self.descriptor = descriptor }
            func transcribe(_ request: LocalASRRequest, progress: @escaping LocalASRProgressObserver) async throws -> LocalASRResult {
                try await progress(.loadingModel)
                try await progress(.convertingAudio)
                try await progress(.transcribing(audioPositionSec: 0.0))
                try await progress(.transcribing(audioPositionSec: 1.0))
                try await progress(.transcribing(audioPositionSec: 2.0))
                return LocalASRResult(text: "truthful audio coverage", cues: [])
            }
            func unload() async {}
        }

        let pipeline = NativeProcessingPipeline(
            localASRRouter: LocalASREngineRouter(
                factories: LocalASREngineRouterFactories(
                    whisperKit: { model in ProgressScriptedEngine(descriptor: model.descriptor) },
                    parakeet: { _ in throw LocalASREngineError.unsupportedModel("unexpected") },
                    canary: { _ in throw LocalASREngineError.unsupportedModel("unexpected") }
                )
            )
        )
        let transcriber = pipeline.makeBatchAudioTranscriber(
            workspaceRoot: root.appendingPathComponent("work"),
            sourceLang: "auto",
            settings: settings,
            providerID: descriptor.id
        )

        let progressLog = PipelineBatchProgressLog()
        _ = try await transcriber.transcribe(
            sourceURL: audioURL,
            resumedCheckpoints: [],
            progress: { await progressLog.record($0) },
            checkpoint: { _ in }
        )

        let updates = await progressLog.values
        #expect(!updates.isEmpty)
        #expect(updates.first?.detail.phase == .planning)
        #expect(updates.first?.totalChunks == nil)

        let phases = updates.map(\.detail.phase)
        #expect(phases.contains(.planning))
        #expect(phases.contains(.loadingModel))
        #expect(phases.contains(.convertingAudio))
        #expect(phases.contains(.transcribing))

        var previousFraction: Double = 0.0
        for update in updates {
            #expect(update.fraction >= previousFraction)
            previousFraction = update.fraction
        }
        #expect(updates.last?.fraction == 1.0)

        let positioned = updates.compactMap { update -> (position: Double, fraction: Double)? in
            guard update.detail.phase == .transcribing,
                  let position = update.detail.currentChunkAudioPositionSec else { return nil }
            return (position, update.fraction)
        }
        #expect(positioned.contains { abs($0.position - 1.0) < 0.05 })
        #expect(positioned.contains { abs($0.position - 2.0) < 0.05 })
        var sawIntraChunkIncrease = false
        for (previous, current) in zip(positioned, positioned.dropFirst()) where current.position > previous.position + 0.25 {
            #expect(current.fraction > previous.fraction + 0.05)
            sawIntraChunkIncrease = true
        }
        #expect(sawIntraChunkIncrease)
        #expect(updates.contains { $0.detail.phase == .transcribing && $0.fraction > 0.2 && $0.fraction < 0.9 })
    }

    @Test("all-complete resumed multi-chunk batch with malformed checkpoint timelines performs zero cloud calls and recovers valid rendered output")
    func batchAllCompleteResumedRecoveryZeroCloudCalls() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptBatch11Recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let audioURL = root.appendingPathComponent("long_lecture.wav")
        try writeTestAudioWAV(to: audioURL, durationSec: 3300)

        var settings = AppSettings.defaults
        settings.sliceMode = .fixed
        settings.chunkDurationMin = 5
        settings.geminiKey = "test-cloud-key"
        settings.geminiKeys = ["test-cloud-key"]
        let providerID = "gemini-cloud"
        let spyCloud = PipelineSpyCloudTranscriber()
        let pipeline = NativeProcessingPipeline(cloudTranscriptionEngine: spyCloud)

        // 11 checkpoints matching real 55-minute lecture chunking (300s each).
        // Chunks 2, 6, 8 contain the observed real failure shapes (equal markers, relative timestamps in late chunk, reversed/oversized).
        let resumedCheckpoints: [BatchChunkCheckpoint] = [
            BatchChunkCheckpoint(
                index: 0,
                text: "Introductory lecture concepts.",
                cues: [
                    TranscriptCue(startSec: 0, endSec: 150, text: "Introductory"),
                    TranscriptCue(startSec: 150, endSec: 300, text: "lecture concepts.")
                ]
            ),
            BatchChunkCheckpoint(
                index: 1,
                text: "Second chapter discussion.",
                cues: [
                    TranscriptCue(startSec: 300, endSec: 450, text: "Second chapter"),
                    TranscriptCue(startSec: 450, endSec: 600, text: "discussion.")
                ]
            ),
            BatchChunkCheckpoint(
                index: 2,
                text: "Equal marker start bug. Second sentence here.",
                cues: [
                    // Malformed: cue 0 ends at 900, cue 1 ends at 750 (nonMonotonic violation)
                    TranscriptCue(startSec: 600, endSec: 900, text: "Equal marker start bug."),
                    TranscriptCue(startSec: 600, endSec: 750, text: "Second sentence here.")
                ]
            ),
            BatchChunkCheckpoint(
                index: 3,
                text: "Fourth chunk content here.",
                cues: [
                    TranscriptCue(startSec: 900, endSec: 1050, text: "Fourth chunk"),
                    TranscriptCue(startSec: 1050, endSec: 1200, text: "content here.")
                ]
            ),
            BatchChunkCheckpoint(
                index: 4,
                text: "Fifth chunk content here.",
                cues: [
                    TranscriptCue(startSec: 1200, endSec: 1350, text: "Fifth chunk"),
                    TranscriptCue(startSec: 1350, endSec: 1500, text: "content here.")
                ]
            ),
            BatchChunkCheckpoint(
                index: 5,
                text: "Sixth chunk content here.",
                cues: [
                    TranscriptCue(startSec: 1500, endSec: 1650, text: "Sixth chunk"),
                    TranscriptCue(startSec: 1650, endSec: 1800, text: "content here.")
                ]
            ),
            BatchChunkCheckpoint(
                index: 6,
                text: "Relative timestamp artifact in late chunk.",
                cues: [
                    // Malformed: retains relative timestamps 295..345 for chunk 1800..2100 (< 1800)
                    TranscriptCue(startSec: 295, endSec: 310, text: "Relative timestamp"),
                    TranscriptCue(startSec: 310, endSec: 345, text: "artifact in late chunk.")
                ]
            ),
            BatchChunkCheckpoint(
                index: 7,
                text: "Eighth chunk content here.",
                cues: [
                    TranscriptCue(startSec: 2100, endSec: 2250, text: "Eighth chunk"),
                    TranscriptCue(startSec: 2250, endSec: 2400, text: "content here.")
                ]
            ),
            BatchChunkCheckpoint(
                index: 8,
                text: "Oversized marker artifact in ninth chunk.",
                cues: [
                    // Malformed: reversed timestamps (2550 > 2500) and exceeds chunk end (2800 > 2700)
                    TranscriptCue(startSec: 2550, endSec: 2500, text: "Oversized marker"),
                    TranscriptCue(startSec: 2500, endSec: 2800, text: "artifact in ninth chunk.")
                ]
            ),
            BatchChunkCheckpoint(
                index: 9,
                text: "Tenth chunk content here.",
                cues: [
                    TranscriptCue(startSec: 2700, endSec: 2850, text: "Tenth chunk"),
                    TranscriptCue(startSec: 2850, endSec: 3000, text: "content here.")
                ]
            ),
            BatchChunkCheckpoint(
                index: 10,
                text: "Eleventh final summary.",
                cues: [
                    TranscriptCue(startSec: 3000, endSec: 3150, text: "Eleventh"),
                    TranscriptCue(startSec: 3150, endSec: 3300, text: "final summary.")
                ]
            )
        ]

        actor CallbackRecorder {
            private(set) var saved: [[BatchChunkCheckpoint]] = []
            func record(_ checkpoints: [BatchChunkCheckpoint]) {
                saved.append(checkpoints)
            }
        }
        let recorder = CallbackRecorder()

        let transcriber = pipeline.makeBatchAudioTranscriber(
            workspaceRoot: root,
            sourceLang: "en",
            settings: settings,
            providerID: providerID
        )

        let result = try await transcriber.transcribe(
            sourceURL: audioURL,
            resumedCheckpoints: resumedCheckpoints,
            progress: { _ in },
            checkpoint: { checkpoints in
                await recorder.record(checkpoints)
            }
        )

        // Acceptance assertion: zero cloud provider calls when all chunks are resumed.
        let cloudCalls = await spyCloud.callCount
        #expect(cloudCalls == 0)

        #expect(result.checkpoints.count == 11)
        #expect(result.duration >= 3300.0)

        // Valid checkpoints remain byte-for-value identical.
        #expect(result.checkpoints[0].cues == resumedCheckpoints[0].cues)
        #expect(result.checkpoints[1].cues == resumedCheckpoints[1].cues)
        #expect(result.checkpoints[3].cues == resumedCheckpoints[3].cues)
        #expect(result.checkpoints[4].cues == resumedCheckpoints[4].cues)
        #expect(result.checkpoints[5].cues == resumedCheckpoints[5].cues)
        #expect(result.checkpoints[7].cues == resumedCheckpoints[7].cues)
        #expect(result.checkpoints[9].cues == resumedCheckpoints[9].cues)
        #expect(result.checkpoints[10].cues == resumedCheckpoints[10].cues)

        // Malformed checkpoints are repaired.
        #expect(result.checkpoints[2].cues != resumedCheckpoints[2].cues)
        #expect(result.checkpoints[6].cues != resumedCheckpoints[6].cues)
        #expect(result.checkpoints[8].cues != resumedCheckpoints[8].cues)

        // Repaired checkpoints were persisted through the callback.
        let savedCalls = await recorder.saved
        #expect(!savedCalls.isEmpty)
        #expect(savedCalls.last == result.checkpoints)

        // Complete text and order preserved across entire file.
        let flattenedCues: [TranscriptCue] = result.checkpoints.flatMap { $0.cues }
        let allText: String = flattenedCues.map { $0.text }.joined(separator: " ")
        #expect(allText.contains("Introductory"))
        #expect(allText.contains("Second chapter"))
        #expect(allText.contains("Equal marker start bug"))
        #expect(allText.contains("Fourth chunk"))
        #expect(allText.contains("Fifth chunk"))
        #expect(allText.contains("Sixth chunk"))
        #expect(allText.contains("Relative timestamp"))
        #expect(allText.contains("Eighth chunk"))
        #expect(allText.contains("Oversized marker"))
        #expect(allText.contains("Tenth chunk"))
        #expect(allText.contains("Eleventh final summary"))

        // Full flattened timeline is strictly valid and renders.
        let validation = BatchTimedTextRenderer.validate(duration: result.duration, cues: flattenedCues)
        #expect(validation.isValid)
        let rendered = try BatchTimedTextRenderer.render(duration: result.duration, cues: flattenedCues)
        #expect(!rendered.isEmpty)
        #expect(rendered.contains("Introductory"))
        #expect(rendered.contains("final summary"))
    }
}
private struct MLXRequestRecord: Sendable {
    let prompt: String
    let sourceLength: Int
}

private actor MLXGenerationRequestLog {
    private(set) var requests: [MLXRequestRecord] = []

    func record(prompt: String, sourceLength: Int) -> Int {
        requests.append(MLXRequestRecord(prompt: prompt, sourceLength: sourceLength))
        return requests.count
    }

    var sourceLengths: [Int] {
        requests.map(\.sourceLength)
    }

    var prompts: [String] {
        requests.map(\.prompt)
    }
}

private actor PipelineProgressLog {
    private(set) var messages: [String] = []

    func record(_ message: String) {
        messages.append(message)
    }
}
private actor PipelineBatchProgressLog {
    private(set) var values: [BatchTranscriptionProgress] = []

    func record(_ value: BatchTranscriptionProgress) {
        values.append(value)
    }
}

private enum PipelineBatchTestEvent: Equatable, Sendable {
    case progress(BatchTranscriptionProgress)
    case asrRequest(LocalASRRequest)
}

private actor PipelineBatchEventLog {
    private(set) var events: [PipelineBatchTestEvent] = []

    func recordProgress(_ progress: BatchTranscriptionProgress) {
        events.append(.progress(progress))
    }

    func recordASR(_ request: LocalASRRequest) {
        events.append(.asrRequest(request))
    }

    var progressValues: [BatchTranscriptionProgress] {
        events.compactMap {
            if case .progress(let p) = $0 { return p }
            return nil
        }
    }

    func latestProgressBeforeASRRequest(atOrdinal ordinal: Int) -> BatchTranscriptionProgress? {
        var asrCount = 0
        for (index, event) in events.enumerated() {
            if case .asrRequest = event {
                if asrCount == ordinal {
                    return events[..<index].reversed().compactMap {
                        if case .progress(let p) = $0 { return p }
                        return nil
                    }.first
                }
                asrCount += 1
            }
        }
        return nil
    }
}

private final class LockedValue<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.withLock { value } }
    func set(_ newValue: T) { lock.withLock { value = newValue } }
}
private actor PipelineBatchCheckpointLog {
    private(set) var values: [[BatchChunkCheckpoint]] = []

    func record(_ checkpoints: [BatchChunkCheckpoint]) {
        values.append(checkpoints)
    }
}

private func writeSilenceSplitWAV(to url: URL) throws {
    let sampleRate = 16_000.0
    let totalFrames = Int(sampleRate * 125)
    let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: true
    ]
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    ),
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else {
        throw TestAudioCreationError.cannotCreateFormatOrBuffer
    }
    buffer.frameLength = AVAudioFrameCount(totalFrames)
    if let samples = buffer.floatChannelData?[0] {
        for frame in 0..<totalFrames {
            let second = Double(frame) / sampleRate
            let silent = (58..<63).contains(Int(second)) || (118..<123).contains(Int(second))
            samples[frame] = silent ? 0 : 0.2
        }
    }
    let file = try AVAudioFile(
        forWriting: url,
        settings: settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )
    try file.write(from: buffer)
}

private func mlxCueBatchOutput(_ texts: [String]) -> String {
    let cues = texts.enumerated()
        .map { index, text in
            let id = String(format: "%03d", index + 1)
            return #"<cue id="\#(id)">\#(text)</cue>"#
        }
        .joined(separator: "\n")
    return "<<<BEGIN>>>\n\(cues)\n<<<END>>>"
}

private func makeTestMLXModel() -> ActiveMLXModel? {
    var settings = AppSettings.defaults
    settings.localTranslationModels["qwen35-4b-4bit"]?.status = .downloaded
    settings.localTranslationModels["qwen35-4b-4bit"]?.path = "/unused"
    return NativeModelCatalog.activeMLXModel(settings: settings, providerID: "mlx-native")
}

private actor PipelineASRRequestLog {
    private(set) var requests: [LocalASRRequest] = []

    func record(_ request: LocalASRRequest) {
        requests.append(request)
    }
}

private actor PipelineSpyCloudTranscriber: NativeCloudAudioTranscribing {
    private(set) var callCount = 0
    private(set) var sourceLanguages: [String] = []

    func transcribe(audioURL: URL, sourceLang: String, metadata: AudioMetadata, glossary: [GlossaryEntry], provider: ActiveCloudTranscriptionProvider, promptPresets: [String: PromptPresetSettings], chunkStartSec: Double, chunkEndSec: Double) async throws -> CloudAudioTranscriptionResult {
        callCount += 1
        sourceLanguages.append(sourceLang)
        return CloudAudioTranscriptionResult(text: "cloud", cues: [TranscriptCue(startSec: chunkStartSec, endSec: chunkEndSec, text: "cloud")])
    }
}

private actor PipelineSpyLocalASREngine: LocalASREngine {
    nonisolated let descriptor: LocalASRModelDescriptor
    private let result: LocalASRResult
    private let log: PipelineASRRequestLog
    private let onTranscribe: (@Sendable (LocalASRRequest) async -> Void)?

    init(
        descriptor: LocalASRModelDescriptor,
        result: LocalASRResult,
        log: PipelineASRRequestLog,
        onTranscribe: (@Sendable (LocalASRRequest) async -> Void)? = nil
    ) {
        self.descriptor = descriptor
        self.result = result
        self.log = log
        self.onTranscribe = onTranscribe
    }

    func transcribe(
        _ request: LocalASRRequest,
        progress: @escaping LocalASRProgressObserver
    ) async throws -> LocalASRResult {
        await log.record(request)
        if let onTranscribe {
            await onTranscribe(request)
        }
        return result
    }

    func unload() async {}
}

private enum PipelineASREvent: Equatable, Sendable {
    case transcribeStarted
    case transcribeFinished
    case unloadStarted
    case unloadFinished
}

private actor PipelineASRLifecycleLog {
    private(set) var events: [PipelineASREvent] = []

    func record(_ event: PipelineASREvent) {
        events.append(event)
    }
}

private actor PipelineBlockingLocalASREngine: LocalASREngine {
    nonisolated let descriptor: LocalASRModelDescriptor
    private let result: LocalASRResult
    private let lifecycle: PipelineASRLifecycleLog
    private var transcriptionContinuation: CheckedContinuation<Void, Never>?
    private var transcriptionStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var activeOperations = 0
    private(set) var maximumOperationOverlap = 0
    private(set) var unloadCount = 0

    init(
        descriptor: LocalASRModelDescriptor,
        result: LocalASRResult,
        lifecycle: PipelineASRLifecycleLog
    ) {
        self.descriptor = descriptor
        self.result = result
        self.lifecycle = lifecycle
    }

    func transcribe(
        _ request: LocalASRRequest,
        progress: @escaping LocalASRProgressObserver
    ) async throws -> LocalASRResult {
        activeOperations += 1
        maximumOperationOverlap = max(maximumOperationOverlap, activeOperations)
        await lifecycle.record(.transcribeStarted)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            transcriptionContinuation = continuation
            transcriptionStarted = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        activeOperations -= 1
        await lifecycle.record(.transcribeFinished)
        return result
    }

    func unload() async {
        activeOperations += 1
        maximumOperationOverlap = max(maximumOperationOverlap, activeOperations)
        unloadCount += 1
        await lifecycle.record(.unloadStarted)
        activeOperations -= 1
        await lifecycle.record(.unloadFinished)
    }

    func waitUntilTranscriptionStarts() async {
        if transcriptionStarted {
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            startWaiters.append(continuation)
        }
    }

    func releaseTranscription() {
        guard let transcriptionContinuation else {
            return
        }
        self.transcriptionContinuation = nil
        transcriptionContinuation.resume()
    }
}

private enum TestAudioCreationError: Error {
    case cannotCreateFormatOrBuffer
}

private func writeValidTestWAV(to url: URL) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16_000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: true
    ]
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    ),
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000) else {
        throw TestAudioCreationError.cannotCreateFormatOrBuffer
    }
    buffer.frameLength = 32_000
    let file = try AVAudioFile(
        forWriting: url,
        settings: settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )
    try file.write(from: buffer)
}

private func writeTestAudioWAV(to url: URL, durationSec: Double, sampleRate: Double = 8_000) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: true
    ]
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    ) else {
        throw TestAudioCreationError.cannotCreateFormatOrBuffer
    }
    let oneSecondFrames = AVAudioFrameCount(sampleRate)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: oneSecondFrames) else {
        throw TestAudioCreationError.cannotCreateFormatOrBuffer
    }
    buffer.frameLength = oneSecondFrames
    let file = try AVAudioFile(
        forWriting: url,
        settings: settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )
    let wholeSeconds = Int(durationSec)
    for _ in 0..<wholeSeconds {
        try file.write(from: buffer)
    }
    let remainingSeconds = durationSec - Double(wholeSeconds)
    if remainingSeconds > 0 {
        let remainderFrames = AVAudioFrameCount(sampleRate * remainingSeconds)
        if let remainderBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: remainderFrames) {
            remainderBuffer.frameLength = remainderFrames
            try file.write(from: remainderBuffer)
        }
    }
}
