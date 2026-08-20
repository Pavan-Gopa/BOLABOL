import AVFoundation
import CoreML
import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Canary Core ML local ASR engine", .serialized)
struct CanaryCoreMLEngineTests {
    @Test("chunks are bounded and Flash splits at sustained silence")
    func chunksRespectWindowAndSilenceBoundaries() {
        let bounded = CanaryCoreMLEngine.chunk(
            samples: [Float](repeating: 0.2, count: 320_001),
            maxSamples: 160_000
        )
        #expect(bounded.map(\.count) == [160_000, 160_000, 1])

        var samples = [Float](repeating: 0, count: 240_000)
        for index in 8_000..<40_000 { samples[index] = 0.2 }
        for index in 160_000..<192_000 { samples[index] = 0.2 }
        let flash = CanaryCoreMLEngine.flashChunks(
            samples: samples,
            maxSamples: 160_000
        )
        #expect(flash.count == 2)
        #expect(flash.allSatisfy { $0.count <= 160_000 })
        #expect(flash.allSatisfy { !$0.isEmpty })
        #expect(flash[0].contains(where: { $0 == 0.2 }))
        #expect(flash[1].contains(where: { $0 == 0.2 }))
    }

    @Test("Path B mask and position seams preserve Core ML shapes")
    func pathBMaskAndPositionContracts() throws {
        let mask = CanaryCoreMLEngine.pathBSelfMask(position: 9, capacity: 12)
        #expect(mask == Array(repeating: Float(0), count: 10) + Array(repeating: Float(-10_000), count: 2))

        let clamped = CanaryCoreMLEngine.pathBSelfMask(position: 99, capacity: 12)
        #expect(clamped == Array(repeating: Float(0), count: 12))

        let position = try CanaryCoreMLEngine.pathBDecoderPositionArray(position: 9)
        #expect(position.dataType == .int32)
        #expect(position.shape.map(\.intValue) == [1])
        #expect(position[0].intValue == 9)
        #expect(CanaryCoreMLEngine.pathBDecoderPositionShape() == [1])
    }

    @Test("Canary accepts only explicit descriptor languages and ASR requests")
    func requestAndLanguageValidation() throws {
        let descriptor = try #require(
            NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")
        )
        let engine = CanaryCoreMLEngine(
            model: descriptor,
            modelFolderURL: URL(fileURLWithPath: "/tmp/canary-validation")
        )

        #expect(try engine.resolveLanguage(LocalASRRequest(languageHint: " EN ")) == "en")
        #expect(throws: LocalASREngineError.unsupportedLanguage("nil (explicit language required)")) {
            try engine.resolveLanguage(LocalASRRequest(languageHint: nil))
        }
        #expect(throws: LocalASREngineError.unsupportedLanguage("auto")) {
            try engine.resolveLanguage(LocalASRRequest(languageHint: "auto"))
        }
        #expect(throws: LocalASREngineError.unsupportedLanguage("ko")) {
            try engine.resolveLanguage(LocalASRRequest(languageHint: "ko"))
        }
        #expect(throws: LocalASREngineError.translationUnsupported) {
            try engine.validateASROnlyRequest(
                LocalASRRequest(languageHint: "en", translateToEnglish: true)
            )
        }
        try engine.validateASROnlyRequest(LocalASRRequest(languageHint: "en"))

        var unknown = descriptor
        unknown.id = "canary-unknown"
        #expect(throws: LocalASREngineError.unsupportedModel("expected canary-180m-flash-coreml or canary-1b-v2-coreml")) {
            try CanaryCoreMLEngine.validateModelBinding(
                descriptor: unknown,
                modelFolderURL: URL(fileURLWithPath: "/tmp/canary-validation")
            )
        }
    }

    @Test("model layout validation rejects missing and wrong variant files")
    func modelLayoutValidation() throws {
        let descriptor = try #require(
            NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")
        )
        let fixture = try makeFixtureDirectory(prefix: "VaniScript-Canary-layout")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)

        try CanaryCoreMLEngine.validateModelBinding(
            descriptor: descriptor,
            modelFolderURL: modelURL
        )

        try FileManager.default.removeItem(
            at: modelURL.appendingPathComponent("vocab.json")
        )
        #expect(throws: LocalASREngineError.modelUnavailable(modelURL)) {
            try CanaryCoreMLEngine.validateModelBinding(
                descriptor: descriptor,
                modelFolderURL: modelURL
            )
        }

        var wrongLayout = descriptor
        wrongLayout.requiredLayout = LocalASRRequiredLayout(
            requiredRelativePaths: ["CanaryEncoder.mlmodelc"]
        )
        #expect(throws: LocalASREngineError.unsupportedModel("descriptor required layout does not match the selected Canary variant")) {
            try CanaryCoreMLEngine.validateModelBinding(
                descriptor: wrongLayout,
                modelFolderURL: modelURL
            )
        }
    }

    @Test("resident session lifecycle, chunk calls, and temporary cleanup are deterministic")
    func residentSessionLifecycle() async throws {
        let descriptor = try #require(
            NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")
        )
        let fixture = try makeFixtureDirectory(prefix: "VaniScript-Canary-session")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)
        let source = try makeSourceAudio(in: fixture, sampleCount: 16_000)
        let temporaryDirectory = fixture.appendingPathComponent("temporary", isDirectory: true)
        let session = RecordingCanarySession(response: "  hello canary  ")
        let loadCount = Counter()
        let engine = CanaryCoreMLEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            temporaryDirectory: temporaryDirectory,
            sessionLoader: { _, _ in
                await loadCount.increment()
                return session
            }
        )

        let first = try await engine.transcribe(
            LocalASRRequest(audioFileURL: source, languageHint: " EN "),
            progress: { _ in }
        )
        let second = try await engine.transcribe(
            LocalASRRequest(audioFileURL: source, languageHint: "en"),
            progress: { _ in }
        )
        #expect(first.text == "hello canary")
        #expect(second.text == "hello canary")
        #expect(await loadCount.value == 1)
        let firstSnapshot = await session.snapshot()
        #expect(firstSnapshot.languages == ["en", "en"])
        #expect(firstSnapshot.sampleCounts.allSatisfy { $0 == 16_000 })
        #expect(temporaryFiles(in: temporaryDirectory).isEmpty)

        await engine.unload()
        #expect(await session.wasUnloaded())
        _ = try await engine.transcribe(
            LocalASRRequest(audioFileURL: source, languageHint: "en"),
            progress: { _ in }
        )
        #expect(await loadCount.value == 2)
        #expect(temporaryFiles(in: temporaryDirectory).isEmpty)
    }

    @Test("returns bounded relative cues for non-empty inference windows")
    func returnsTimedCuesForNonEmptyWindows() async throws {
        let descriptor = try #require(
            NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")
        )
        let fixture = try makeFixtureDirectory(prefix: "VaniScript-Canary-timed")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)
        let source = try makeSourceAudio(in: fixture, sampleCount: 400_000)
        let session = RecordingCanarySession(responses: ["first", "", "third"])
        let engine = CanaryCoreMLEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            temporaryDirectory: fixture.appendingPathComponent("temporary", isDirectory: true),
            sessionLoader: { _, _ in session }
        )

        let result = try await engine.transcribe(
            LocalASRRequest(audioFileURL: source, languageHint: "en"),
            progress: { _ in }
        )
        let cues = try #require(result.cues)

        #expect(result.text == "first third")
        #expect(cues.map(\.text) == ["first", "third"])
        #expect(cues.allSatisfy { $0.words == nil })
        #expect(abs(cues[0].startSec - 0) < 0.001)
        #expect(abs(cues[0].endSec - 10) < 0.001)
        #expect(abs(cues[1].startSec - 20) < 0.001)
        #expect(abs(cues[1].endSec - 25) < 0.001)
        #expect(cues[0].endSec <= cues[1].startSec)
    }

    @Test("concurrent transcriptions share one suspended resident session")
    func concurrentTranscriptionsShareOneLoad() async throws {
        let descriptor = try #require(
            NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")
        )
        let fixture = try makeFixtureDirectory(prefix: "VaniScript-Canary-concurrent")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)
        let source = try makeSourceAudio(in: fixture, sampleCount: 16_000)
        let session = RecordingCanarySession(response: "shared canary")
        let loader = SuspendedCanarySessionLoader(session: session)
        let secondWaiterRegistered = CanaryTestGate()
        let engine = CanaryCoreMLEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            temporaryDirectory: fixture.appendingPathComponent("temporary", isDirectory: true),
            sessionLoader: { descriptor, modelFolderURL in
                try await loader.load(descriptor, modelFolderURL)
            },
            loadObserver: { event in
                guard case let .waiterRegistered(_, waiterCount) = event,
                      waiterCount == 2 else { return }
                Task {
                    await secondWaiterRegistered.open()
                }
            }
        )

        let request = LocalASRRequest(audioFileURL: source, languageHint: "en")

        let first = Task {
            try await engine.transcribe(request, progress: { _ in })
        }
        await loader.waitUntilFirstLoadStarted()

        let second = Task {
            try await engine.transcribe(request, progress: { _ in })
        }

        await loader.releaseFirstLoad()
        let firstResult = try await first.value
        let secondResult = try await second.value

        #expect(firstResult.text == "shared canary")
        #expect(secondResult.text == "shared canary")
        #expect(await loader.loadCount == 1)
        let snapshot = await session.snapshot()
        #expect(snapshot.languages == ["en", "en"])
        #expect(snapshot.sampleCounts == [16_000, 16_000])

        await engine.unload()
        #expect(await session.unloadCount == 1)
    }

    @Test("unload invalidates a pending load and disposes its late session")
    func unloadDuringPendingLoadDisposesLateSession() async throws {
        let descriptor = try #require(
            NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")
        )
        let fixture = try makeFixtureDirectory(prefix: "VaniScript-Canary-unload-pending")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)
        let source = try makeSourceAudio(in: fixture, sampleCount: 16_000)
        let session = RecordingCanarySession(response: "late canary")
        let loader = SuspendedCanarySessionLoader(session: session)
        let engine = CanaryCoreMLEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            temporaryDirectory: fixture.appendingPathComponent("temporary", isDirectory: true),
            sessionLoader: { descriptor, modelFolderURL in
                try await loader.load(descriptor, modelFolderURL)
            }
        )
        let request = LocalASRRequest(audioFileURL: source, languageHint: "en")
        let transcription = Task {
            try await engine.transcribe(request, progress: { _ in })
        }
        await loader.waitUntilFirstLoadStarted()

        await engine.unload()
        await loader.releaseFirstLoad()

        do {
            _ = try await transcription.value
            Issue.record("Expected the invalidated transcription to fail")
        } catch is CancellationError {
            // Expected: unload invalidates the waiter without installing a session.
        }
        #expect(await loader.loadCount == 1)
        #expect(await session.unloadCount == 1)

        await engine.unload()
        #expect(await session.unloadCount == 1)
    }

    @Test("translation and macOS gate reject before a session loads")
    func earlyRequestFailures() async throws {
        let descriptor = try #require(
            NativeModelCatalog.localASRModel(for: "canary-1b-v2-coreml")
        )
        let fixture = try makeFixtureDirectory(prefix: "VaniScript-Canary-gate")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)
        let source = try makeSourceAudio(in: fixture, sampleCount: 16_000)
        let loadCount = Counter()

        let translationEngine = CanaryCoreMLEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            sessionLoader: { _, _ in
                await loadCount.increment()
                return RecordingCanarySession(response: "unreachable")
            }
        )
        do {
            _ = try await translationEngine.transcribe(
                LocalASRRequest(
                    audioFileURL: source,
                    languageHint: "en",
                    translateToEnglish: true
                ),
                progress: { _ in }
            )
            Issue.record("Expected Canary translation request to fail")
        } catch let error as LocalASREngineError {
            #expect(error == .translationUnsupported)
        }
        #expect(await loadCount.value == 0)

        var gated = descriptor
        gated.capabilities.minimumMacOSMajor = 99
        let gatedEngine = CanaryCoreMLEngine(
            model: gated,
            modelFolderURL: modelURL,
            sessionLoader: { _, _ in
                await loadCount.increment()
                return RecordingCanarySession(response: "unreachable")
            }
        )
        let currentMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        do {
            _ = try await gatedEngine.transcribe(
                LocalASRRequest(audioFileURL: source, languageHint: "en"),
                progress: { _ in }
            )
            Issue.record("Expected the macOS gate to fail")
        } catch let error as LocalASREngineError {
            #expect(error == .unsupportedOS(requiredMajor: 99, currentMajor: currentMajor))
        }
        #expect(await loadCount.value == 0)
    }

    @Test("pre-cancelled requests do not create temporary audio")
    func cancellationCleansTemporaryAudio() async throws {
        let descriptor = try #require(
            NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")
        )
        let fixture = try makeFixtureDirectory(prefix: "VaniScript-Canary-cancel")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let modelURL = try makeModelDirectory(in: fixture, descriptor: descriptor)
        let source = try makeSourceAudio(in: fixture, sampleCount: 16_000)
        let temporaryDirectory = fixture.appendingPathComponent("temporary", isDirectory: true)
        let engine = CanaryCoreMLEngine(
            model: descriptor,
            modelFolderURL: modelURL,
            temporaryDirectory: temporaryDirectory,
            sessionLoader: { _, _ in
                RecordingCanarySession(response: "unreachable")
            }
        )

        let task = Task {
            try await engine.transcribe(
                LocalASRRequest(audioFileURL: source, languageHint: "en"),
                progress: { _ in }
            )
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation to propagate")
        } catch is CancellationError {
            // Expected.
        }
        #expect(temporaryFiles(in: temporaryDirectory).isEmpty)
    }

    private func makeModelDirectory(
        in fixture: URL,
        descriptor: LocalASRModelDescriptor
    ) throws -> URL {
        let modelURL = fixture.appendingPathComponent("model", isDirectory: true)
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        for relativePath in descriptor.requiredLayout.requiredFiles {
            let itemURL = modelURL.appendingPathComponent(relativePath)
            if relativePath.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: itemURL, withIntermediateDirectories: true)
            } else {
                try Data("fixture".utf8).write(to: itemURL)
            }
        }
        return modelURL
    }

    private func makeSourceAudio(in fixture: URL, sampleCount: Int) throws -> URL {
        let url = fixture.appendingPathComponent("source.caf")
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw TestError.audioFixture
        }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true,
        ]
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
            throw TestError.audioFixture
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<sampleCount { samples[index] = 0.2 }
        }
        try file.write(from: buffer)
        return url
    }

    private func makeFixtureDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
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

private actor RecordingCanarySession: CanaryCoreMLSession {
    private let responses: [String]
    private var responseIndex = 0
    private var languages: [String] = []
    private var sampleCounts: [Int] = []
    private var unloaded = false
    private(set) var unloadCount = 0

    init(response: String) {
        self.responses = [response]
    }

    init(responses: [String]) {
        self.responses = responses
    }

    func transcribe(samples: [Float], language: String) async throws -> String {
        languages.append(language)
        sampleCounts.append(samples.count)
        let response = responses[min(responseIndex, responses.count - 1)]
        responseIndex += 1
        return response
    }

    func unload() {
        unloaded = true
        unloadCount += 1
    }

    func snapshot() -> (languages: [String], sampleCounts: [Int]) {
        (languages, sampleCounts)
    }

    func wasUnloaded() -> Bool {
        unloaded
    }
}

private actor SuspendedCanarySessionLoader {
    private let session: RecordingCanarySession
    private var firstLoadContinuation: CheckedContinuation<any CanaryCoreMLSession, Never>?
    private var firstLoadStarted = false
    private var firstLoadWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var loadCount = 0

    init(session: RecordingCanarySession) {
        self.session = session
    }

    func load(
        _ descriptor: LocalASRModelDescriptor,
        _ modelFolderURL: URL
    ) async throws -> any CanaryCoreMLSession {
        loadCount += 1
        guard loadCount == 1 else { return session }

        return await withCheckedContinuation { continuation in
            firstLoadContinuation = continuation
            firstLoadStarted = true
            let waiters = firstLoadWaiters
            firstLoadWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitUntilFirstLoadStarted() async {
        guard !firstLoadStarted else { return }
        await withCheckedContinuation { continuation in
            firstLoadWaiters.append(continuation)
        }
    }

    func releaseFirstLoad() {
        guard let continuation = firstLoadContinuation else { return }
        firstLoadContinuation = nil
        continuation.resume(returning: session)
    }
}

private actor CanaryTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private enum TestError: Error {
    case audioFixture
}
