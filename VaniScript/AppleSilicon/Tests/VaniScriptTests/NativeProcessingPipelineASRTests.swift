import AVFoundation
import Foundation
import Testing
import VaniScriptCore
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
            providerID: descriptor.id
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

private actor PipelineSpyLocalASREngine: LocalASREngine {
    nonisolated let descriptor: LocalASRModelDescriptor
    private let result: LocalASRResult
    private let log: PipelineASRRequestLog

    init(
        descriptor: LocalASRModelDescriptor,
        result: LocalASRResult,
        log: PipelineASRRequestLog
    ) {
        self.descriptor = descriptor
        self.result = result
        self.log = log
    }

    func transcribe(_ request: LocalASRRequest) async throws -> LocalASRResult {
        await log.record(request)
        return result
    }

    func unload() async {}
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
