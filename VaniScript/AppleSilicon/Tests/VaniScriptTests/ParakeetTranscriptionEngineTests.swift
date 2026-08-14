import AVFoundation
import FluidAudio
import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Parakeet local ASR engine", .serialized)
struct ParakeetTranscriptionEngineTests {
    @Test("maps supported language hints and cleans temporary WAVs")
    func mapsLanguageAndCleansTemporaryAudio() async throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let descriptor = try parakeetDescriptor()
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)
        let temporaryDirectory = fixture.appendingPathComponent("temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let source = try makeSourceAudio(in: fixture)
        let session = RecordingSession(response: "  hello world  ")
        let engine = ParakeetTranscriptionEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            temporaryDirectory: temporaryDirectory,
            sessionLoader: { _ in session }
        )

        let first = try await engine.transcribe(
            LocalASRRequest(audioFileURL: source, languageHint: " EN ")
        )
        let second = try await engine.transcribe(
            LocalASRRequest(audioFileURL: source, languageHint: "auto")
        )
        let third = try await engine.transcribe(
            LocalASRRequest(audioFileURL: source, languageHint: "   ")
        )
        let fourth = try await engine.transcribe(
            LocalASRRequest(audioFileURL: source, languageHint: "unsupported_lang")
        )
        let snapshot = await session.snapshot()

        #expect(first.text == "hello world")
        #expect(second.text == "hello world")
        #expect(third.text == "hello world")
        #expect(fourth.text == "hello world")
        #expect(snapshot.languages == [.english, nil, nil, nil])
        #expect(snapshot.audioFilesExistedDuringTranscription == [true, true, true, true])
        #expect(temporaryFiles(in: temporaryDirectory).isEmpty)
    }

    @Test("preserves FluidAudio token timings as bounded word-bearing cues")
    func preservesTokenTimingsAsReviewCues() async throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let descriptor = try parakeetDescriptor()
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)
        let source = try makeSourceAudio(in: fixture)
        let timings = [
            TokenTiming(token: "▁hello", tokenId: 1, startTime: 0.2, endTime: 0.7, confidence: 0.9),
            TokenTiming(token: "▁world", tokenId: 2, startTime: 0.9, endTime: 1.4, confidence: 0.9),
            TokenTiming(token: "▁again", tokenId: 3, startTime: 2.5, endTime: 3.0, confidence: 0.9),
        ]
        let session = RecordingSession(
            result: ASRResult(
                text: "hello world again",
                confidence: 0.9,
                duration: 4,
                processingTime: 0.1,
                tokenTimings: timings
            )
        )
        let engine = ParakeetTranscriptionEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            temporaryDirectory: fixture.appendingPathComponent("temporary", isDirectory: true),
            sessionLoader: { _ in session }
        )

        let result = try await engine.transcribe(LocalASRRequest(audioFileURL: source))
        let cues = try #require(result.cues)

        #expect(result.text == "hello world again")
        #expect(cues.map(\.text) == ["hello world", "again"])
        #expect(cues.allSatisfy { $0.startSec >= 0 && $0.endSec <= 4 && $0.endSec > $0.startSec })
        #expect(cues[0].words?.map(\.text) == ["hello", "world"])
        #expect(cues[1].words?.map(\.text) == ["again"])
        #expect(cues[0].endSec <= cues[1].startSec)
    }
    @Test("segments missing token timings into bounded cues for short and long text")
    func segmentsMissingTokenTimingsIntoBoundedCues() async throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let descriptor = try parakeetDescriptor()
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)
        let source = try makeSourceAudio(in: fixture)

        let longText = "First sentence is here. Second sentence is also here. Third sentence is long and has many words to test splitting. Fourth sentence is final."
        let session = RecordingSession(
            result: ASRResult(
                text: longText,
                confidence: 0.9,
                duration: 20,
                processingTime: 0.1,
                tokenTimings: nil
            )
        )
        let engine = ParakeetTranscriptionEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            temporaryDirectory: fixture.appendingPathComponent("temporary", isDirectory: true),
            sessionLoader: { _ in session }
        )

        let result = try await engine.transcribe(LocalASRRequest(audioFileURL: source))
        let cues = try #require(result.cues)

        #expect(result.text == longText)
        #expect(cues.count > 1)
        #expect(cues.allSatisfy { $0.startSec >= 0 && $0.endSec <= 20 && $0.endSec > $0.startSec })
        #expect(cues.allSatisfy { $0.endSec - $0.startSec <= 5.0 })
        #expect(cues.allSatisfy { $0.endSec - $0.startSec < 20.0 })
        #expect(cues.allSatisfy { $0.words != nil && !$0.words!.isEmpty })
        #expect(cues.map(\.text).joined(separator: " ") == longText)

        let allExtractedWords = cues.compactMap(\.words).flatMap { $0 }.map(\.text)
        let expectedWords = longText.split(whereSeparator: \.isWhitespace).map(String.init)
        #expect(allExtractedWords == expectedWords)
    }

    @Test("bounds sparse text cues over a long duration without full-chunk stretching")
    func boundsSparseTextCuesOverLongDuration() {
        let rawText = "Sparse words here."
        let cues = ParakeetTranscriptionEngine.boundedCuesFromUntimedText(rawText, startSec: 0, endSec: 60)

        #expect(cues.count == 1)
        #expect(cues[0].startSec == 0.0)
        #expect(cues[0].endSec <= 5.0)
        #expect(cues[0].endSec - cues[0].startSec <= 5.0)
        #expect(cues[0].endSec - cues[0].startSec < 60.0)
        #expect(cues[0].text == rawText)
    }

    @Test("bounds residual-window untimed cues so the final cue does not exceed 5 seconds")
    func boundsResidualWindowCues() {
        let rawText = "Sentence one. Sentence two is longer and reaches near the end. Sentence three."
        let cues = ParakeetTranscriptionEngine.boundedCuesFromUntimedText(rawText, startSec: 0, endSec: 18)

        #expect(cues.count > 1)
        #expect(cues.allSatisfy { $0.endSec - $0.startSec <= 5.0 })
        #expect(cues.allSatisfy { $0.endSec - $0.startSec < 18.0 })
        #expect(cues.map(\.text).joined(separator: " ") == rawText)

        let allExtractedWords = cues.compactMap(\.words).flatMap { $0 }.map(\.text)
        let expectedWords = rawText.split(whereSeparator: \.isWhitespace).map(String.init)
        #expect(allExtractedWords == expectedWords)
    }

    @Test("fails explicitly when missing token timings have invalid duration")
    func failsExplicitlyWhenMissingTokenTimingsHaveInvalidDuration() async throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let descriptor = try parakeetDescriptor()
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)
        let source = try makeSourceAudio(in: fixture)

        let session = RecordingSession(
            result: ASRResult(
                text: "Text without duration",
                confidence: 0.9,
                duration: 0,
                processingTime: 0.1,
                tokenTimings: nil
            )
        )
        let engine = ParakeetTranscriptionEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            temporaryDirectory: fixture.appendingPathComponent("temporary", isDirectory: true),
            sessionLoader: { _ in session }
        )

        do {
            _ = try await engine.transcribe(LocalASRRequest(audioFileURL: source))
            Issue.record("Expected invalid duration to fail")
        } catch let error as LocalASREngineError {
            guard case .inferenceFailed(let detail) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(detail.contains("valid duration"))
        }
    }

    @Test("rejects translation requests before loading a model")
    func rejectsTranslation() async throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let descriptor = try parakeetDescriptor()
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)
        let source = try makeSourceAudio(in: fixture)
        let session = RecordingSession(response: "not reached")
        let loadCount = LoadCount()
        let engine = ParakeetTranscriptionEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            temporaryDirectory: fixture.appendingPathComponent("temporary", isDirectory: true),
            sessionLoader: { _ in
                await loadCount.increment()
                return session
            }
        )

        do {
            _ = try await engine.transcribe(
                LocalASRRequest(
                    audioFileURL: source,
                    languageHint: "en",
                    translateToEnglish: true
                )
            )
            Issue.record("Expected translation to be rejected")
        } catch let error as LocalASREngineError {
            #expect(error == .translationUnsupported)
        }
        #expect(await loadCount.value == 0)
        #expect((try? FileManager.default.contentsOfDirectory(
            at: fixture.appendingPathComponent("temporary", isDirectory: true),
            includingPropertiesForKeys: nil
        ))?.isEmpty != false)
    }

    @Test("rejects empty output and maps inference failures while cleaning")
    func rejectsEmptyAndInferenceFailures() async throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let descriptor = try parakeetDescriptor()
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)
        let source = try makeSourceAudio(in: fixture)

        let emptySession = RecordingSession(response: " \n\t")
        let emptyTemporaryDirectory = fixture.appendingPathComponent("empty-temporary", isDirectory: true)
        let emptyEngine = ParakeetTranscriptionEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            temporaryDirectory: emptyTemporaryDirectory,
            sessionLoader: { _ in emptySession }
        )
        do {
            _ = try await emptyEngine.transcribe(LocalASRRequest(audioFileURL: source))
            Issue.record("Expected empty output to fail")
        } catch let error as LocalASREngineError {
            #expect(error == .emptyResult)
        }
        #expect(temporaryFiles(in: emptyTemporaryDirectory).isEmpty)

        let failingSession = RecordingSession(response: "unused", failure: .fixtureFailure)
        let failingTemporaryDirectory = fixture.appendingPathComponent("failing-temporary", isDirectory: true)
        let failingEngine = ParakeetTranscriptionEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            temporaryDirectory: failingTemporaryDirectory,
            sessionLoader: { _ in failingSession }
        )
        do {
            _ = try await failingEngine.transcribe(LocalASRRequest(audioFileURL: source))
            Issue.record("Expected inference failure")
        } catch let error as LocalASREngineError {
            guard case .inferenceFailed(let detail) = error else {
                Issue.record("Unexpected local ASR error: \(error)")
                return
            }
            #expect(detail.contains("fixture inference failure"))
        }
        #expect(temporaryFiles(in: failingTemporaryDirectory).isEmpty)
    }

    @Test("caches one session and unloads it explicitly")
    func cachesAndUnloadsSession() async throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let descriptor = try parakeetDescriptor()
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)
        let source = try makeSourceAudio(in: fixture)
        let session = RecordingSession(response: "cached")
        let loadCount = LoadCount()
        let engine = ParakeetTranscriptionEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            temporaryDirectory: fixture.appendingPathComponent("temporary", isDirectory: true),
            sessionLoader: { _ in
                await loadCount.increment()
                return session
            }
        )

        _ = try await engine.transcribe(LocalASRRequest(audioFileURL: source))
        _ = try await engine.transcribe(LocalASRRequest(audioFileURL: source))
        #expect(await loadCount.value == 1)

        await engine.unload()
        #expect(await session.wasUnloaded())

        _ = try await engine.transcribe(LocalASRRequest(audioFileURL: source))
        #expect(await loadCount.value == 2)
    }

    @Test("rejects missing audio files and unavailable model bindings")
    func rejectsMissingAudioAndUnavailableModel() async throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let descriptor = try parakeetDescriptor()
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)
        let source = try makeSourceAudio(in: fixture)
        let engine = ParakeetTranscriptionEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            temporaryDirectory: fixture.appendingPathComponent("temporary", isDirectory: true),
            sessionLoader: { _ in RecordingSession(response: "unused") }
        )

        do {
            _ = try await engine.transcribe(LocalASRRequest(audioFileURL: nil))
            Issue.record("Expected missing audio file request to fail")
        } catch let error as LocalASREngineError {
            #expect(error == .missingAudioFile)
        }

        let missingModelURL = fixture.appendingPathComponent("missing-model", isDirectory: true)
        let unavailableEngine = ParakeetTranscriptionEngine(
            model: descriptor,
            modelFolderURL: missingModelURL,
            temporaryDirectory: fixture.appendingPathComponent("temporary", isDirectory: true),
            sessionLoader: { _ in RecordingSession(response: "unused") }
        )

        do {
            _ = try await unavailableEngine.transcribe(LocalASRRequest(audioFileURL: source))
            Issue.record("Expected missing model directory to fail")
        } catch let error as LocalASREngineError {
            #expect(error == .modelUnavailable(missingModelURL))
        }
    }

    private func parakeetDescriptor() throws -> LocalASRModelDescriptor {
        try #require(NativeModelCatalog.localASRModel(for: "parakeet-tdt-06b-v3"))
    }

    private func makeModelDirectory(
        in fixture: URL,
        descriptor: LocalASRModelDescriptor
    ) throws -> URL {
        let modelURL = fixture.appendingPathComponent("parakeet-model", isDirectory: true)
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        for relativePath in descriptor.requiredLayout.requiredFiles {
            let item = modelURL.appendingPathComponent(relativePath)
            if relativePath.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true)
            } else {
                try Data("fixture".utf8).write(to: item)
            }
        }
        return modelURL
    }

    private func makeSourceAudio(in fixture: URL) throws -> URL {
        let url = fixture.appendingPathComponent("source.caf")
        let sampleCount = 24_000
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ) else {
            Issue.record("Could not create source format")
            return url
        }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 48_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true
        ]
        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleCount)
            ) else {
                Issue.record("Could not create source buffer")
                return url
            }
            buffer.frameLength = AVAudioFrameCount(sampleCount)
            if let samples = buffer.floatChannelData?[0] {
                for index in 0..<sampleCount {
                    samples[index] = 0.2
                }
            }
            try file.write(from: buffer)
        }
        return url
    }

    private func makeFixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScript-Parakeet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func temporaryFiles(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
    }
}

private actor RecordingSession: ParakeetTranscriptionSession {
    private let result: ASRResult
    private let failure: RecordingSessionError?
    private var languages: [Language?] = []
    private var audioFilesExistedDuringTranscription: [Bool] = []
    private var unloaded = false

    init(response: String, failure: RecordingSessionError? = nil) {
        self.result = ASRResult(
            text: response,
            confidence: 1,
            duration: 1,
            processingTime: 0.1
        )
        self.failure = failure
    }

    init(result: ASRResult, failure: RecordingSessionError? = nil) {
        self.result = result
        self.failure = failure
    }

    func transcribe(audioFileURL: URL, language: Language?) async throws -> ASRResult {
        languages.append(language)
        audioFilesExistedDuringTranscription.append(
            FileManager.default.fileExists(atPath: audioFileURL.path)
        )
        if let failure {
            throw failure
        }
        return result
    }

    func unload() {
        unloaded = true
    }

    func snapshot() -> (languages: [Language?], audioFilesExistedDuringTranscription: [Bool]) {
        (languages, audioFilesExistedDuringTranscription)
    }

    func wasUnloaded() -> Bool {
        unloaded
    }
}

private enum RecordingSessionError: LocalizedError, Sendable {
    case fixtureFailure

    var errorDescription: String? {
        switch self {
        case .fixtureFailure:
            return "fixture inference failure"
        }
    }
}

private actor LoadCount {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
