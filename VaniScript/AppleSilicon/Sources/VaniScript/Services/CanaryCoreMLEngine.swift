/// Owns VaniScript's two catalog Canary Core ML ASR variants. The service must
/// not route pipelines, download models, or provide translation behavior.
import Accelerate
import CoreML
import Foundation
import VaniScriptCore

// MARK: - Session seam

/// Injectable inference surface for deterministic tests and one resident model
/// session in production. The engine owns validation, audio preparation, and
/// windowing; a session owns the variant-specific Core ML graph.
protocol CanaryCoreMLSession: Sendable {
    func transcribe(samples: [Float], language: String) async throws -> String
    func unload() async
}

typealias CanaryCoreMLSessionLoader = @Sendable (
    LocalASRModelDescriptor,
    URL
) async throws -> any CanaryCoreMLSession

typealias CanaryCoreMLURLSessionLoader = @Sendable (
    URL
) async throws -> any CanaryCoreMLSession

/// Internal lifecycle observation emitted only after a waiter is committed to
/// the actor's in-flight load state. Production leaves the observer unset.
enum CanaryCoreMLLoadEvent: Sendable {
    case waiterRegistered(generation: UInt64, waiterCount: Int)
}

typealias CanaryCoreMLLoadObserver = @Sendable (CanaryCoreMLLoadEvent) -> Void

enum CanaryVariant: Sendable {
    case flash
    case pathB
    case unknown
}

private struct CanaryAudioWindow: Sendable {
    let sampleOffset: Int
    let samples: [Float]
}

private let defaultCanaryCoreMLSessionLoader: CanaryCoreMLSessionLoader = { descriptor, root in
    switch descriptor.id {
    case "canary-180m-flash-coreml":
        return try FlashCoreMLSession.load(from: root)
    case "canary-1b-v2-coreml":
        guard #available(macOS 15.0, *) else {
            let current = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            throw LocalASREngineError.unsupportedOS(requiredMajor: 15, currentMajor: current)
        }
        return try PathBCoreMLSession.load(from: root)
    default:
        throw LocalASREngineError.unsupportedModel(
            "expected canary-180m-flash-coreml or canary-1b-v2-coreml"
        )
    }
}

/// Native Core ML/ANE execution for the two catalog Canary ASR variants.
///
/// This service deliberately has no router, downloader, UI, or translation
/// responsibilities. It validates the descriptor and local package, converts
/// audio through the shared LASR preprocessor, then keeps one injectable
/// variant session resident until `unload()` is called.
actor CanaryCoreMLEngine: LocalASREngine {
    nonisolated let descriptor: LocalASRModelDescriptor

    private let modelFolderURL: URL
    private let audioPreprocessor: LocalASRAudioPreprocessor
    private let fileManager: FileManager
    private let temporaryDirectory: URL
    private let sessionLoader: CanaryCoreMLSessionLoader
    private let loadObserver: CanaryCoreMLLoadObserver?
    private var session: (any CanaryCoreMLSession)?
    private var loadGeneration: UInt64 = 0
    private var inFlightLoad: InFlightSessionLoad?

    private struct InFlightSessionLoad {
        let generation: UInt64
        let task: Task<any CanaryCoreMLSession, Error>
        var waiters: Set<UUID>
        var pendingSession: (any CanaryCoreMLSession)?
        var invalidated = false
    }

    private enum SessionLoadRegistration {
        case active(InFlightSessionLoad)
        case invalidated(InFlightSessionLoad)
    }

    init(
        model: LocalASRModelDescriptor,
        modelFolderURL: URL,
        audioPreprocessor: LocalASRAudioPreprocessor = LocalASRAudioPreprocessor(),
        fileManager: FileManager = .default,
        temporaryDirectory: URL? = nil,
        sessionLoader: @escaping CanaryCoreMLSessionLoader = defaultCanaryCoreMLSessionLoader,
        loadObserver: CanaryCoreMLLoadObserver? = nil
    ) {
        self.descriptor = model
        self.modelFolderURL = modelFolderURL
        self.audioPreprocessor = audioPreprocessor
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory ?? fileManager.temporaryDirectory
        self.sessionLoader = sessionLoader
        self.loadObserver = loadObserver
    }

    /// Compatibility seam matching the existing local-ASR loaders that only
    /// need the validated model folder URL.
    init(
        model: LocalASRModelDescriptor,
        modelFolderURL: URL,
        audioPreprocessor: LocalASRAudioPreprocessor = LocalASRAudioPreprocessor(),
        fileManager: FileManager = .default,
        temporaryDirectory: URL? = nil,
        sessionLoader: @escaping CanaryCoreMLURLSessionLoader,
        loadObserver: CanaryCoreMLLoadObserver? = nil
    ) {
        self.init(
            model: model,
            modelFolderURL: modelFolderURL,
            audioPreprocessor: audioPreprocessor,
            fileManager: fileManager,
            temporaryDirectory: temporaryDirectory,
            sessionLoader: { _, modelFolderURL in
                try await sessionLoader(modelFolderURL)
            },
            loadObserver: loadObserver
        )
    }

    func transcribe(_ request: LocalASRRequest) async throws -> LocalASRResult {
        try Task.checkCancellation()
        try validateASROnlyRequest(request)
        try Self.validateModelBinding(
            descriptor: descriptor,
            modelFolderURL: modelFolderURL,
            fileManager: fileManager
        )
        try validateOSRequirement()

        guard let sourceURL = request.audioFileURL else {
            throw LocalASREngineError.missingAudioFile
        }
        let language = try resolveLanguage(request)

        let normalizedAudioURL = temporaryDirectory.appendingPathComponent(
            "vaniscript-canary-\(UUID().uuidString).wav"
        )
        defer {
            try? fileManager.removeItem(at: normalizedAudioURL)
        }

        do {
            try audioPreprocessor.convertTo16kMonoWAV(
                source: sourceURL,
                destination: normalizedAudioURL
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LocalASREngineError.audioPreparationFailed(error.localizedDescription)
        }

        try Task.checkCancellation()
        let samples: [Float]
        do {
            samples = try Self.readInt16MonoWAV(at: normalizedAudioURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LocalASREngineError.audioPreparationFailed(error.localizedDescription)
        }
        guard !samples.isEmpty else {
            throw LocalASREngineError.emptyResult
        }

        let maxChunkSamples = max(
            1,
            Int((descriptor.capabilities.maxEngineWindowSeconds * 16_000.0).rounded(.down))
        )
        let windows: [CanaryAudioWindow]
        switch Self.variant(for: descriptor.id) {
        case .flash:
            windows = Self.flashWindows(samples: samples, maxSamples: maxChunkSamples)
        case .pathB:
            windows = Self.chunkWindows(samples: samples, maxSamples: maxChunkSamples)
        case .unknown:
            throw LocalASREngineError.unsupportedModel(
                "expected canary-180m-flash-coreml or canary-1b-v2-coreml"
            )
        }
        guard !windows.isEmpty else {
            throw LocalASREngineError.emptyResult
        }

        let session = try await loadedSession()
        var textParts: [String] = []
        textParts.reserveCapacity(windows.count)
        var cues: [TranscriptCue] = []
        cues.reserveCapacity(windows.count)
        for window in windows {
            try Task.checkCancellation()
            let rawText: String
            do {
                rawText = try await session.transcribe(
                    samples: window.samples,
                    language: language
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as LocalASREngineError {
                throw error
            } catch {
                throw LocalASREngineError.inferenceFailed(error.localizedDescription)
            }
            try Task.checkCancellation()
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            textParts.append(text)
            let start = Double(window.sampleOffset) / 16_000.0
            let end = Double(window.sampleOffset + window.samples.count) / 16_000.0
            guard end > start else { continue }
            // Canary exposes no word timing. The exact bounded inference
            // window is the only honest relative cue boundary available.
            cues.append(TranscriptCue(startSec: start, endSec: end, text: text))
        }

        let text = textParts.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw LocalASREngineError.emptyResult
        }
        return LocalASRResult(text: text, cues: cues)
    }

    func unload() async {
        loadGeneration &+= 1

        let residentSession = session
        session = nil

        let pendingSession: (any CanaryCoreMLSession)?
        if var inFlightLoad {
            inFlightLoad.invalidated = true
            inFlightLoad.waiters.removeAll()
            pendingSession = inFlightLoad.pendingSession
            inFlightLoad.pendingSession = nil
            self.inFlightLoad = inFlightLoad
        } else {
            pendingSession = nil
        }

        if let residentSession {
            await residentSession.unload()
        }
        if let pendingSession {
            await pendingSession.unload()
        }
    }

    /// Actor-isolated binding seam used by callers that preflight a local
    /// package before submitting audio.
    internal func validateModelBinding() throws {
        try Self.validateModelBinding(
            descriptor: descriptor,
            modelFolderURL: modelFolderURL,
            fileManager: fileManager
        )
    }

    private struct SessionLoadInvalidated: Error {}

    private func loadedSession() async throws -> any CanaryCoreMLSession {
        if let session {
            return session
        }

        try Task.checkCancellation()
        while true {
            let waiterID = UUID()
            switch beginSessionLoad(waiterID: waiterID) {
            case .invalidated(let load):
                do {
                    _ = try await load.task.value
                } catch {
                    // An invalidated load is disposed by its own completion
                    // path. Its failure cannot become the next request's
                    // load error.
                }
                try Task.checkCancellation()
            case .active(let load):
                do {
                    return try await withTaskCancellationHandler(operation: {
                        do {
                            _ = try await load.task.value
                            return try await resolveSessionLoad(
                                generation: load.generation,
                                waiterID: waiterID,
                                cancelled: Task.isCancelled
                            )
                        } catch is CancellationError {
                            await abandonSessionLoadWaiter(
                                generation: load.generation,
                                waiterID: waiterID
                            )
                            throw CancellationError()
                        } catch is SessionLoadInvalidated {
                            await abandonSessionLoadWaiter(
                                generation: load.generation,
                                waiterID: waiterID
                            )
                            throw SessionLoadInvalidated()
                        } catch let error as LocalASREngineError {
                            await abandonSessionLoadWaiter(
                                generation: load.generation,
                                waiterID: waiterID
                            )
                            throw error
                        } catch {
                            await abandonSessionLoadWaiter(
                                generation: load.generation,
                                waiterID: waiterID
                            )
                            throw LocalASREngineError.inferenceFailed(
                                "Could not load the Canary model: \(error.localizedDescription)"
                            )
                        }
                    }, onCancel: {
                        Task {
                            await self.cancelSessionLoadWaiter(
                                generation: load.generation,
                                waiterID: waiterID
                            )
                        }
                    })
                } catch is SessionLoadInvalidated {
                    try Task.checkCancellation()
                    throw CancellationError()
                }
        }
    }

    }

    private func beginSessionLoad(waiterID: UUID) -> SessionLoadRegistration {
        if var inFlightLoad {
            if inFlightLoad.invalidated {
                return .invalidated(inFlightLoad)
            }
            inFlightLoad.waiters.insert(waiterID)
            self.inFlightLoad = inFlightLoad
            loadObserver?(.waiterRegistered(
                generation: inFlightLoad.generation,
                waiterCount: inFlightLoad.waiters.count
            ))
            return .active(inFlightLoad)
        }

        loadGeneration &+= 1
        let generation = loadGeneration
        let descriptor = descriptor
        let modelFolderURL = modelFolderURL
        let sessionLoader = sessionLoader
        let task = Task.detached { [self, descriptor, modelFolderURL, sessionLoader] in
            do {
                let loaded = try await sessionLoader(descriptor, modelFolderURL)
                await completeSessionLoad(generation: generation, session: loaded)
                await finishSessionLoadTask(generation: generation)
                return loaded
            } catch {
                await failSessionLoad(generation: generation)
                throw error
            }
        }
        let newLoad = InFlightSessionLoad(
            generation: generation,
            task: task,
            waiters: [waiterID],
            pendingSession: nil
        )
        inFlightLoad = newLoad
        loadObserver?(.waiterRegistered(
            generation: newLoad.generation,
            waiterCount: newLoad.waiters.count
        ))
        return .active(newLoad)
    }


    private func completeSessionLoad(
        generation: UInt64,
        session loaded: any CanaryCoreMLSession
    ) async {
        guard var inFlightLoad, inFlightLoad.generation == generation else {
            await loaded.unload()
            return
        }

        guard !inFlightLoad.invalidated else {
            self.inFlightLoad = inFlightLoad
            await loaded.unload()
            return
        }

        guard !inFlightLoad.waiters.isEmpty else {
            inFlightLoad.invalidated = true
            self.inFlightLoad = inFlightLoad
            await loaded.unload()
            return
        }

        inFlightLoad.pendingSession = loaded
        self.inFlightLoad = inFlightLoad
    }

    private func finishSessionLoadTask(generation: UInt64) {
        guard let inFlightLoad, inFlightLoad.generation == generation else { return }
        guard inFlightLoad.invalidated else { return }
        self.inFlightLoad = nil
    }

    private func failSessionLoad(generation: UInt64) {
        guard inFlightLoad?.generation == generation else { return }
        inFlightLoad = nil
    }

    private func resolveSessionLoad(
        generation: UInt64,
        waiterID: UUID,
        cancelled: Bool
    ) async throws -> any CanaryCoreMLSession {
        guard var inFlightLoad, inFlightLoad.generation == generation else {
            if cancelled {
                throw CancellationError()
            }
            if let session {
                return session
            }
            throw SessionLoadInvalidated()
        }

        guard !inFlightLoad.invalidated else {
            self.inFlightLoad = nil
            if cancelled {
                throw CancellationError()
            }
            throw SessionLoadInvalidated()
        }

        inFlightLoad.waiters.remove(waiterID)
        if cancelled {
            if inFlightLoad.waiters.isEmpty, let pendingSession = inFlightLoad.pendingSession {
                inFlightLoad.pendingSession = nil
                inFlightLoad.invalidated = true
                self.inFlightLoad = nil
                await pendingSession.unload()
            } else {
                self.inFlightLoad = inFlightLoad
            }
            throw CancellationError()
        }

        guard let pendingSession = inFlightLoad.pendingSession else {
            self.inFlightLoad = inFlightLoad
            throw SessionLoadInvalidated()
        }

        session = pendingSession
        inFlightLoad.pendingSession = nil
        self.inFlightLoad = nil
        return pendingSession
    }

    private func abandonSessionLoadWaiter(generation: UInt64, waiterID: UUID) async {
        guard var inFlightLoad, inFlightLoad.generation == generation else { return }
        inFlightLoad.waiters.remove(waiterID)
        if inFlightLoad.waiters.isEmpty, let pendingSession = inFlightLoad.pendingSession {
            inFlightLoad.pendingSession = nil
            inFlightLoad.invalidated = true
            self.inFlightLoad = inFlightLoad
            await pendingSession.unload()
        } else {
            self.inFlightLoad = inFlightLoad
        }
    }

    private func cancelSessionLoadWaiter(generation: UInt64, waiterID: UUID) async {
        await abandonSessionLoadWaiter(generation: generation, waiterID: waiterID)
    }

    private func validateOSRequirement() throws {
        let currentMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if descriptor.id == "canary-1b-v2-coreml", currentMajor < 15 {
            // Path B uses MLState and must not silently select a non-stateful
            // fallback on macOS 14, even if malformed metadata omits its gate.
            throw LocalASREngineError.unsupportedOS(requiredMajor: 15, currentMajor: currentMajor)
        }

        guard let minimumMajor = descriptor.capabilities.minimumMacOSMajor else { return }
        guard currentMajor >= minimumMajor else {
            throw LocalASREngineError.unsupportedOS(
                requiredMajor: minimumMajor,
                currentMajor: currentMajor
            )
        }
    }

    /// Keeps ASR-only defense ahead of model loading and temporary-file work.
    nonisolated internal func validateASROnlyRequest(_ request: LocalASRRequest) throws {
        guard !request.translateToEnglish else {
            throw LocalASREngineError.translationUnsupported
        }
    }

    /// Canary has no auto-detect route. The code must be present in the
    /// descriptor capabilities and is normalized only for comparison.
    nonisolated internal func resolveLanguage(_ request: LocalASRRequest) throws -> String {
        let supported = Set(
            descriptor.capabilities.supportedLanguageCodes.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )
        guard let hint = request.languageHint else {
            throw LocalASREngineError.unsupportedLanguage(
                "nil (explicit language required)"
            )
        }
        let normalized = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "auto", supported.contains(normalized) else {
            throw LocalASREngineError.unsupportedLanguage(normalized.isEmpty ? "empty" : normalized)
        }
        return normalized
    }

    // MARK: Pure seams

    nonisolated internal static func variant(for id: String) -> CanaryVariant {
        switch id {
        case "canary-180m-flash-coreml": return .flash
        case "canary-1b-v2-coreml": return .pathB
        default: return .unknown
        }
    }

    /// Validates the exact variant/layout contract without opening Core ML.
    nonisolated internal static func validateModelBinding(
        descriptor: LocalASRModelDescriptor,
        modelFolderURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let expected: [String]
        switch descriptor.id {
        case "canary-180m-flash-coreml":
            expected = [
                "CanaryEncoder.mlmodelc",
                "CanaryPrefill.mlmodelc",
                "CanaryDecoder.mlmodelc",
                "config.json",
                "vocab.json",
            ]
        case "canary-1b-v2-coreml":
            expected = [
                "canary_encoder.mlmodelc",
                "canary_cross_kv.mlmodelc",
                "canary_decoder_kv.mlmodelc",
                "canary_spe.model",
            ]
        default:
            throw LocalASREngineError.unsupportedModel(
                "expected canary-180m-flash-coreml or canary-1b-v2-coreml"
            )
        }

        guard descriptor.backend == .canaryCoreML else {
            throw LocalASREngineError.unsupportedModel(
                "Canary descriptors must use the canaryCoreML backend"
            )
        }

        let actual = descriptor.requiredLayout.requiredFiles
        guard Set(actual) == Set(expected), actual.count == expected.count else {
            throw LocalASREngineError.unsupportedModel(
                "descriptor required layout does not match the selected Canary variant"
            )
        }
        guard !descriptor.requiredLayout.isSDKManaged else {
            throw LocalASREngineError.unsupportedModel(
                "Canary descriptors require an explicit file layout"
            )
        }

        guard LocalASRPresencePolicy.requiredLayoutExists(
            descriptor.requiredLayout,
            at: modelFolderURL,
            fileManager: fileManager
        ) else {
            throw LocalASREngineError.modelUnavailable(modelFolderURL)
        }
    }

    /// Generic bounded windows used by Path B. Invalid bounds fail closed rather
    /// than risking an infinite loop in a caller-provided test seam.
    private nonisolated static func chunkWindows(
        samples: [Float],
        maxSamples: Int
    ) -> [CanaryAudioWindow] {
        guard maxSamples > 0 else { return [] }
        guard samples.count > maxSamples else {
            return samples.isEmpty
                ? []
                : [CanaryAudioWindow(sampleOffset: 0, samples: samples)]
        }

        var windows: [CanaryAudioWindow] = []
        windows.reserveCapacity((samples.count + maxSamples - 1) / maxSamples)
        var start = 0
        while start < samples.count {
            let end = min(start + maxSamples, samples.count)
            windows.append(
                CanaryAudioWindow(
                    sampleOffset: start,
                    samples: Array(samples[start..<end])
                )
            )
            start = end
        }
        return windows
    }

    nonisolated internal static func chunk(samples: [Float], maxSamples: Int) -> [[Float]] {
        guard maxSamples > 0 else { return [] }
        return samples.isEmpty
            ? [[]]
            : chunkWindows(samples: samples, maxSamples: maxSamples).map(\.samples)
    }

    /// Flash is an offline utterance model. Splitting at real pauses keeps a
    /// full ten-second EOS decision from discarding speech at the front of a
    /// long recording while retaining a hard model-window bound.
    private nonisolated static func flashWindows(
        samples: [Float],
        maxSamples: Int
    ) -> [CanaryAudioWindow] {
        guard !samples.isEmpty, maxSamples > 0 else { return [] }

        let frameSamples = 320 // 20 ms at 16 kHz
        let minimumSilenceSamples = 3_840 // 240 ms
        let paddingSamples = 1_920 // 120 ms on each speech boundary
        let minimumSpeechSamples = 4_800 // 300 ms
        let preferredChunkSamples = min(maxSamples, 96_000) // 6 seconds
        let frameCount = (samples.count + frameSamples - 1) / frameSamples

        var frameRMS = [Float](repeating: 0, count: frameCount)
        var peakRMS: Float = 0
        for frame in 0..<frameCount {
            let start = frame * frameSamples
            let end = min(start + frameSamples, samples.count)
            var sum: Float = 0
            for index in start..<end {
                let value = samples[index]
                sum += value * value
            }
            let rms = sqrt(sum / Float(max(1, end - start)))
            frameRMS[frame] = rms
            peakRMS = max(peakRMS, rms)
        }

        let speechThreshold = max(0.0025, peakRMS * 0.08)
        var speechRanges: [(start: Int, end: Int)] = []
        var rangeStart: Int?
        var silenceStart: Int?

        for frame in 0..<frameCount {
            let frameStart = frame * frameSamples
            let isSpeech = frameRMS[frame] >= speechThreshold
            if isSpeech {
                if rangeStart == nil {
                    rangeStart = max(0, frameStart - paddingSamples)
                }
                silenceStart = nil
                continue
            }

            guard let currentStart = rangeStart else { continue }
            if silenceStart == nil {
                silenceStart = frameStart
            }
            guard let currentSilenceStart = silenceStart,
                  frameStart - currentSilenceStart >= minimumSilenceSamples
            else {
                continue
            }

            let currentEnd = min(samples.count, currentSilenceStart + paddingSamples)
            if currentEnd - currentStart >= minimumSpeechSamples {
                speechRanges.append((currentStart, currentEnd))
            }
            rangeStart = nil
            silenceStart = nil
        }

        if let currentStart = rangeStart {
            let currentEnd = samples.count
            if currentEnd - currentStart >= minimumSpeechSamples {
                speechRanges.append((currentStart, currentEnd))
            }
        }

        guard !speechRanges.isEmpty else {
            return chunkWindows(samples: samples, maxSamples: maxSamples)
        }

        var windows: [CanaryAudioWindow] = []
        var currentStart = speechRanges[0].start
        var currentEnd = speechRanges[0].end

        func appendCurrent() {
            guard currentEnd > currentStart else { return }
            var start = currentStart
            while start < currentEnd {
                let end = min(start + maxSamples, currentEnd)
                windows.append(
                    CanaryAudioWindow(
                        sampleOffset: start,
                        samples: Array(samples[start..<end])
                    )
                )
                start = end
            }
        }

        for range in speechRanges.dropFirst() {
            let combinedEnd = range.end
            if combinedEnd - currentStart > preferredChunkSamples {
                appendCurrent()
                currentStart = range.start
            }
            currentEnd = combinedEnd
        }
        appendCurrent()

        return windows.isEmpty
            ? chunkWindows(samples: samples, maxSamples: maxSamples)
            : windows
    }

    nonisolated internal static func flashChunks(
        samples: [Float],
        maxSamples: Int
    ) -> [[Float]] {
        flashWindows(samples: samples, maxSamples: maxSamples).map(\.samples)
    }

    /// The Path B model consumes a causal mask with visible positions through
    /// the current token and a rank-one int32 position input.
    nonisolated internal static func pathBSelfMask(
        position: Int,
        capacity: Int = 238
    ) -> [Float] {
        guard capacity > 0 else { return [] }
        let clamped = min(max(position, 0), capacity - 1)
        var mask = [Float](repeating: -10_000, count: capacity)
        for index in 0...clamped {
            mask[index] = 0
        }
        return mask
    }

    nonisolated internal static func pathBDecoderPositionArray(position: Int) throws -> MLMultiArray {
        try makeI32Scalar(position)
    }

    nonisolated internal static func pathBDecoderPositionShape() -> [Int] {
        [1]
    }

    private static func readInt16MonoWAV(at url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)
        guard bytes.count >= 12,
              String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE"
        else {
            throw CanaryWAVError.invalid
        }

        var formatOffset: Int?
        var dataOffset: Int?
        var dataSize = 0
        var offset = 12
        while offset + 8 <= bytes.count {
            let chunkSize = Int(bytes[offset + 4])
                | (Int(bytes[offset + 5]) << 8)
                | (Int(bytes[offset + 6]) << 16)
                | (Int(bytes[offset + 7]) << 24)
            guard chunkSize >= 0, offset + 8 <= bytes.count else {
                throw CanaryWAVError.invalid
            }
            let payloadStart = offset + 8
            guard payloadStart <= bytes.count,
                  chunkSize <= bytes.count - payloadStart
            else {
                throw CanaryWAVError.invalid
            }
            let chunkID = String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii) ?? ""
            if chunkID == "fmt " { formatOffset = offset }
            if chunkID == "data" {
                dataOffset = payloadStart
                dataSize = chunkSize
            }
            let paddedSize = chunkSize + (chunkSize % 2)
            guard paddedSize <= bytes.count - payloadStart else {
                throw CanaryWAVError.invalid
            }
            offset = payloadStart + paddedSize
        }

        guard let formatOffset, let dataOffset,
              formatOffset + 24 <= bytes.count,
              dataOffset + dataSize <= bytes.count
        else {
            throw CanaryWAVError.invalid
        }

        let audioFormat = Int(bytes[formatOffset + 8])
            | (Int(bytes[formatOffset + 9]) << 8)
        let channels = Int(bytes[formatOffset + 10])
            | (Int(bytes[formatOffset + 11]) << 8)
        let sampleRate = Int(bytes[formatOffset + 12])
            | (Int(bytes[formatOffset + 13]) << 8)
            | (Int(bytes[formatOffset + 14]) << 16)
            | (Int(bytes[formatOffset + 15]) << 24)
        let bits = Int(bytes[formatOffset + 22])
            | (Int(bytes[formatOffset + 23]) << 8)

        guard audioFormat == 1, channels == 1, sampleRate == 16_000, bits == 16 else {
            throw CanaryWAVError.invalid
        }

        let raw = bytes[dataOffset..<(dataOffset + dataSize)]
        let frameBytes = channels * bits / 8
        guard frameBytes > 0, raw.count % frameBytes == 0 else {
            throw CanaryWAVError.invalid
        }
        var samples = [Float](repeating: 0, count: raw.count / frameBytes)
        for index in samples.indices {
            let byteIndex = raw.startIndex + index * 2
            let value = Int16(bitPattern: UInt16(raw[byteIndex]) | (UInt16(raw[byteIndex + 1]) << 8))
            samples[index] = Float(value) / 32_768.0
        }
        return samples
    }
}

private enum CanaryWAVError: LocalizedError {
    case invalid

    var errorDescription: String? {
        "The normalized audio is not a valid 16 kHz mono PCM WAV."
    }
}

// MARK: - Flash Core ML session
private actor FlashCoreMLSession: CanaryCoreMLSession {
    private var state: FlashState?

    init(state: FlashState) {
        self.state = state
    }

    static func load(from root: URL) throws -> FlashCoreMLSession {
        try FlashCoreMLSession(state: FlashState.load(from: root))
    }

    func transcribe(samples: [Float], language: String) async throws -> String {
        try Task.checkCancellation()
        guard let state else {
            throw LocalASREngineError.inferenceFailed("The Canary Flash model is unloaded.")
        }
        guard let languageID = state.languageTokenIDs[language] else {
            throw LocalASREngineError.unsupportedLanguage(language)
        }

        let (mel, frames) = try state.melFrontend.extract(samples)
        guard frames > 0 else { throw LocalASREngineError.emptyResult }
        let encoderOutput = try state.runEncoder(mel: mel, length: frames)
        guard let embeddings = encoderOutput.embeddings,
              let mask = encoderOutput.mask
        else {
            throw LocalASREngineError.inferenceFailed("Canary Flash encoder returned an incomplete output.")
        }

        var prompt = state.promptTemplate
        guard prompt.count >= 5 else {
            throw LocalASREngineError.inferenceFailed("Canary Flash prompt template is invalid.")
        }
        prompt[3] = languageID
        prompt[4] = languageID

        var output = try state.runPrefill(
            inputIDs: prompt,
            embeddings: embeddings,
            mask: mask
        )
        var tokens: [Int] = []
        tokens.reserveCapacity(64)
        for _ in 0..<256 {
            try Task.checkCancellation()
            guard let logits = output["logits"]?.multiArrayValue,
                  let cache = output["decoder_hidden_states"]?.multiArrayValue
            else { break }
            let token = Self.argmax(logits, vocabularySize: 5_248)
            if token == state.eosID { break }
            tokens.append(token)
            guard cache.shape.count > 2 else {
                throw LocalASREngineError.inferenceFailed("Canary Flash decoder cache has an invalid shape.")
            }
            let startPosition = cache.shape[2].intValue
            output = try state.runDecoderStep(
                token: token,
                cache: cache,
                embeddings: embeddings,
                mask: mask,
                startPosition: startPosition
            )
        }
        return state.decode(tokens: tokens)
    }

    func unload() {
        state = nil
    }

    private static func argmax(_ logits: MLMultiArray, vocabularySize: Int) -> Int {
        let count = logits.count
        guard count > 0 else { return 0 }
        let vocabulary = min(vocabularySize, count)
        let offset = count - vocabulary
        var best = 0
        var bestScore = -Float.infinity
        switch logits.dataType {
        case .float16:
            let pointer = logits.dataPointer.assumingMemoryBound(to: Float16.self)
            for index in 0..<vocabulary {
                let score = Float(pointer[offset + index])
                if score > bestScore { bestScore = score; best = index }
            }
        case .float32:
            let pointer = logits.dataPointer.assumingMemoryBound(to: Float.self)
            for index in 0..<vocabulary {
                let score = pointer[offset + index]
                if score > bestScore { bestScore = score; best = index }
            }
        default:
            for index in 0..<vocabulary {
                let score = logits[offset + index].floatValue
                if score > bestScore { bestScore = score; best = index }
            }
        }
        return best
    }
}

private final class FlashState: @unchecked Sendable {
    let encoder: MLModel
    let prefill: MLModel
    let decoder: MLModel
    let vocab: [Int: String]
    let languageTokenIDs: [String: Int]
    let promptTemplate: [Int]
    let eosID: Int
    let melFrontend: FlashMelFrontend

    init(
        encoder: MLModel,
        prefill: MLModel,
        decoder: MLModel,
        vocab: [Int: String],
        languageTokenIDs: [String: Int],
        promptTemplate: [Int],
        eosID: Int,
        melFrontend: FlashMelFrontend
    ) {
        self.encoder = encoder
        self.prefill = prefill
        self.decoder = decoder
        self.vocab = vocab
        self.languageTokenIDs = languageTokenIDs
        self.promptTemplate = promptTemplate
        self.eosID = eosID
        self.melFrontend = melFrontend
    }

    static func load(from root: URL) throws -> FlashState {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine

        func loadModel(_ name: String) throws -> MLModel {
            let url = root.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw LocalASREngineError.modelUnavailable(root)
            }
            do {
                return try MLModel(contentsOf: url, configuration: configuration)
            } catch {
                throw LocalASREngineError.inferenceFailed(
                    "Could not load \(name).mlmodelc: \(error.localizedDescription)"
                )
            }
        }

        let encoder = try loadModel("CanaryEncoder")
        let prefill = try loadModel("CanaryPrefill")
        let decoder = try loadModel("CanaryDecoder")

        let configURL = root.appendingPathComponent("config.json")
        guard let configData = try? Data(contentsOf: configURL),
              let config = try JSONSerialization.jsonObject(with: configData) as? [String: Any]
        else {
            throw LocalASREngineError.inferenceFailed("Canary Flash config.json is invalid.")
        }

        let languages = config["languageTokenIds"] as? [String: Int] ?? [:]
        let special = config["specialTokenIds"] as? [String: Int] ?? [:]
        let coreML = config["coreml"] as? [String: Any] ?? [:]
        let melFrames = (coreML["encoderMelFrames"] as? Int)
            ?? (coreML["encoderMelFrames"] as? Double).map(Int.init)
            ?? 1_000
        let prompt: [Int]
        if let prompts = config["promptIds"] as? [String: [Int]],
           let first = prompts.keys.sorted().first.flatMap({ prompts[$0] }) {
            prompt = first
        } else {
            prompt = [7, 4, 16, 0, 0, 5, 9, 11, 13]
        }
        guard let eosID = special["eos"] else {
            throw LocalASREngineError.inferenceFailed("Canary Flash config.json has no EOS token.")
        }

        let vocabURL = root.appendingPathComponent("vocab.json")
        guard let vocabData = try? Data(contentsOf: vocabURL),
              let vocabObject = try? JSONSerialization.jsonObject(with: vocabData),
              let vocabStrings = vocabObject as? [String: String]
        else {
            throw LocalASREngineError.inferenceFailed("Canary Flash vocab.json is invalid.")
        }
        var vocab: [Int: String] = [:]
        for (key, value) in vocabStrings {
            if let id = Int(key) { vocab[id] = value }
        }

        let frontend = try FlashMelFrontend(config: config, encoderMelFrames: melFrames)
        return FlashState(
            encoder: encoder,
            prefill: prefill,
            decoder: decoder,
            vocab: vocab,
            languageTokenIDs: languages,
            promptTemplate: prompt,
            eosID: eosID,
            melFrontend: frontend
        )
    }

    func runEncoder(mel: MLMultiArray, length: Int) throws -> (
        embeddings: MLMultiArray?,
        mask: MLMultiArray?
    ) {
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "audio_signal": MLFeatureValue(multiArray: mel),
            "length": MLFeatureValue(multiArray: try makeI32Scalar(length)),
        ])
        let output = try encoder.prediction(from: provider)
        return (
            output.featureValue(for: "encoder_embeddings")?.multiArrayValue,
            output.featureValue(for: "encoder_mask")?.multiArrayValue
        )
    }

    func runPrefill(
        inputIDs: [Int],
        embeddings: MLMultiArray,
        mask: MLMultiArray
    ) throws -> [String: MLFeatureValue] {
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: try makeI32(inputIDs)),
            "encoder_embeddings": MLFeatureValue(multiArray: embeddings),
            "encoder_mask": MLFeatureValue(multiArray: mask),
        ])
        let output = try prefill.prediction(from: provider)
        return outputFeatures(output)
    }

    func runDecoderStep(
        token: Int,
        cache: MLMultiArray,
        embeddings: MLMultiArray,
        mask: MLMultiArray,
        startPosition: Int
    ) throws -> [String: MLFeatureValue] {
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: try makeI32([token])),
            "decoder_mems": MLFeatureValue(multiArray: cache),
            "encoder_embeddings": MLFeatureValue(multiArray: embeddings),
            "encoder_mask": MLFeatureValue(multiArray: mask),
            "start_pos": MLFeatureValue(multiArray: try makeI32Scalar(startPosition)),
        ])
        let output = try decoder.prediction(from: provider)
        return outputFeatures(output)
    }

    func decode(tokens: [Int]) -> String {
        tokens.compactMap { vocab[$0] }
            .filter { !$0.hasPrefix("<|") }
            .joined()
            .replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func outputFeatures(_ provider: MLFeatureProvider) -> [String: MLFeatureValue] {
        var output: [String: MLFeatureValue] = [:]
        for name in provider.featureNames {
            if let value = provider.featureValue(for: name) { output[name] = value }
        }
        return output
    }
}

// MARK: - Canary 1B Path B session

@available(macOS 15.0, *)
private actor PathBCoreMLSession: CanaryCoreMLSession {
    private var state: PathBState?

    init(state: PathBState) {
        self.state = state
    }

    static func load(from root: URL) throws -> PathBCoreMLSession {
        try PathBCoreMLSession(state: PathBState.load(from: root))
    }

    func transcribe(samples: [Float], language: String) async throws -> String {
        try Task.checkCancellation()
        guard let state else {
            throw LocalASREngineError.inferenceFailed("The Canary 1B model is unloaded.")
        }
        guard let languageID = state.languageTokenIDs[language] else {
            throw LocalASREngineError.unsupportedLanguage(language)
        }

        let (mel, frames) = try state.melFrontend.extract(samples)
        guard frames > 0 else { throw LocalASREngineError.emptyResult }
        let encoderOutput = try state.runEncoder(mel: mel, length: frames)
        guard let encoderStates = encoderOutput.states,
              encoderOutput.length != nil
        else {
            throw LocalASREngineError.inferenceFailed("Canary 1B encoder returned an incomplete output.")
        }
        let crossOutput = try state.runCrossKV(states: encoderStates)
        guard let encoderK = crossOutput.k, let encoderV = crossOutput.v else {
            throw LocalASREngineError.inferenceFailed("Canary 1B cross-attention output is incomplete.")
        }

        let seed = [16053, 7, 4, 16, languageID, languageID, 5, 9, 11, 13]
        let decoderState: MLState
        do {
            decoderState = try state.makeState()
        } catch {
            throw LocalASREngineError.decoderStateInitializationFailed(error.localizedDescription)
        }

        var output: [String: MLFeatureValue] = [:]
        var position = 0
        for token in seed {
            try Task.checkCancellation()
            output = try state.runDecoderStep(
                state: decoderState,
                token: token,
                position: position,
                encoderK: encoderK,
                encoderV: encoderV
            )
            position += 1
        }

        var tokens: [Int] = []
        tokens.reserveCapacity(64)
        var repeatedCount = 0
        var previousToken: Int?
        for _ in 0..<256 {
            try Task.checkCancellation()
            guard let logits = output["log_probs"]?.multiArrayValue else { break }
            let token = Self.argmax(logits)
            if token == state.eosID { break }
            if token == previousToken {
                repeatedCount += 1
                if repeatedCount >= 4 { break }
            } else {
                repeatedCount = 0
            }
            previousToken = token
            tokens.append(token)
            output = try state.runDecoderStep(
                state: decoderState,
                token: token,
                position: position,
                encoderK: encoderK,
                encoderV: encoderV
            )
            position += 1
        }
        return state.decode(tokens: tokens)
    }

    func unload() {
        state = nil
    }

    private static func argmax(_ logits: MLMultiArray) -> Int {
        guard logits.count > 0 else { return 0 }
        var best = 0
        var bestScore = -Float.infinity
        for index in 0..<logits.count {
            let score = logits[index].floatValue
            if score > bestScore { bestScore = score; best = index }
        }
        return best
    }
}

@available(macOS 15.0, *)
private final class PathBState: @unchecked Sendable {
    let encoder: MLModel
    let crossKV: MLModel
    let decoderKV: MLModel
    let vocab: [Int: String]
    let languageTokenIDs: [String: Int]
    let eosID: Int
    let melFrontend: PathBMelFrontend

    init(
        encoder: MLModel,
        crossKV: MLModel,
        decoderKV: MLModel,
        vocab: [Int: String],
        languageTokenIDs: [String: Int],
        eosID: Int,
        melFrontend: PathBMelFrontend
    ) {
        self.encoder = encoder
        self.crossKV = crossKV
        self.decoderKV = decoderKV
        self.vocab = vocab
        self.languageTokenIDs = languageTokenIDs
        self.eosID = eosID
        self.melFrontend = melFrontend
    }

    static func load(from root: URL) throws -> PathBState {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine

        func loadModel(_ name: String) throws -> MLModel {
            let url = root.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw LocalASREngineError.modelUnavailable(root)
            }
            do {
                return try MLModel(contentsOf: url, configuration: configuration)
            } catch {
                throw LocalASREngineError.inferenceFailed(
                    "Could not load \(name).mlmodelc: \(error.localizedDescription)"
                )
            }
        }

        let encoder = try loadModel("canary_encoder")
        let crossKV = try loadModel("canary_cross_kv")
        let decoderKV = try loadModel("canary_decoder_kv")
        let sentencePieceURL = root.appendingPathComponent("canary_spe.model")
        guard FileManager.default.fileExists(atPath: sentencePieceURL.path) else {
            throw LocalASREngineError.modelUnavailable(root)
        }
        let pieces = try SentencePieceModel(url: sentencePieceURL).pieces
        let languageTokenIDs: [String: Int] = [
            "bg": 46, "hr": 58, "cs": 59, "da": 60, "nl": 62,
            "en": 64, "et": 66, "fi": 70, "fr": 71, "de": 78,
            "el": 79, "hu": 89, "it": 99, "lv": 117, "lt": 120,
            "mt": 127, "pl": 150, "pt": 151, "ro": 154, "ru": 157,
            "sk": 167, "sl": 168, "es": 171, "sv": 175, "uk": 192,
        ]
        return PathBState(
            encoder: encoder,
            crossKV: crossKV,
            decoderKV: decoderKV,
            vocab: Dictionary(uniqueKeysWithValues: pieces.enumerated().map { ($0.offset, $0.element) }),
            languageTokenIDs: languageTokenIDs,
            eosID: 3,
            melFrontend: try PathBMelFrontend()
        )
    }

    func makeState() throws -> MLState {
        decoderKV.makeState()
    }

    func runEncoder(mel: MLMultiArray, length: Int) throws -> (
        states: MLMultiArray?,
        length: MLMultiArray?
    ) {
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "mel": MLFeatureValue(multiArray: mel),
            "mel_length": MLFeatureValue(multiArray: try makeI32Scalar(length)),
        ])
        let output = try encoder.prediction(from: provider)
        return (
            output.featureValue(for: "enc_states")?.multiArrayValue,
            output.featureValue(for: "encoder_length")?.multiArrayValue
        )
    }

    func runCrossKV(states: MLMultiArray) throws -> (
        k: MLMultiArray?,
        v: MLMultiArray?
    ) {
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "enc_states": MLFeatureValue(multiArray: states),
        ])
        let output = try crossKV.prediction(from: provider)
        return (
            output.featureValue(for: "enc_k")?.multiArrayValue,
            output.featureValue(for: "enc_v")?.multiArrayValue
        )
    }

    func runDecoderStep(
        state: MLState,
        token: Int,
        position: Int,
        encoderK: MLMultiArray,
        encoderV: MLMultiArray
    ) throws -> [String: MLFeatureValue] {
        let mask = try makeFloatArray(
            CanaryCoreMLEngine.pathBSelfMask(position: position),
            shape: [1, 1, 1, 238]
        )
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "enc_k": MLFeatureValue(multiArray: encoderK),
            "enc_v": MLFeatureValue(multiArray: encoderV),
            // Path B's verified model contract is int32 [1], not [1, 1].
            "pos": MLFeatureValue(multiArray: try CanaryCoreMLEngine.pathBDecoderPositionArray(position: position)),
            "self_mask": MLFeatureValue(multiArray: mask),
            "token": MLFeatureValue(multiArray: try makeI32([token])),
        ])
        let output = try decoderKV.prediction(from: provider, using: state)
        var result: [String: MLFeatureValue] = [:]
        for name in output.featureNames {
            if let value = output.featureValue(for: name) { result[name] = value }
        }
        return result
    }

    func decode(tokens: [Int]) -> String {
        tokens.compactMap { vocab[$0] }
            .filter { !$0.hasPrefix("<|") }
            .joined()
            .replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

// MARK: - NeMo mel frontends

private final class FlashMelFrontend: @unchecked Sendable {
    let sampleRate: Int
    let numMelBins: Int
    let nFFT = 512
    let hopLength = 160
    let winLength = 400
    let preEmphasis = Float(0.97)
    let logGuard = Float(5.960464477539063e-08)
    let normEpsilon = Float(1e-5)
    let encoderMelFrames: Int

    private let log2FFT: vDSP_Length = 9
    private let nBins = 257
    private let centrePad = 256
    private let windowOffset = 56
    private let fftSetup: FFTSetup
    private let hannWindow: [Float]
    private let melFilterbank: [Float]

    init(config: [String: Any], encoderMelFrames: Int) throws {
        guard let sampleRate = config["sampleRate"] as? Int
                ?? (config["sampleRate"] as? Double).map(Int.init),
              let numMelBins = config["numMelBins"] as? Int
                ?? (config["numMelBins"] as? Double).map(Int.init),
              sampleRate > 0, numMelBins > 0, encoderMelFrames > 0
        else {
            throw LocalASREngineError.inferenceFailed("Canary Flash mel config is invalid.")
        }
        self.sampleRate = sampleRate
        self.numMelBins = numMelBins
        self.encoderMelFrames = encoderMelFrames
        guard let fftSetup = vDSP_create_fftsetup(log2FFT, FFTRadix(kFFTRadix2)) else {
            throw LocalASREngineError.inferenceFailed("Could not create the Canary Flash FFT setup.")
        }
        self.fftSetup = fftSetup
        let windowLength = 400
        self.hannWindow = (0..<windowLength).map {
            0.5 * (1.0 - cos(2.0 * Float.pi * Float($0) / Float(windowLength - 1)))
        }
        self.melFilterbank = Self.buildMelFilterbank(
            nMels: numMelBins,
            nBins: 257,
            sampleRate: sampleRate
        )
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func extract(_ audio: [Float]) throws -> (mel: MLMultiArray, frames: Int) {
        guard !audio.isEmpty else { throw LocalASREngineError.emptyResult }
        var emphasized = [Float](repeating: 0, count: audio.count)
        emphasized[0] = audio[0]
        if audio.count > 1 {
            for index in 1..<audio.count {
                emphasized[index] = audio[index] - preEmphasis * audio[index - 1]
            }
        }

        var padded = [Float](repeating: 0, count: centrePad + emphasized.count + centrePad)
        for index in emphasized.indices { padded[centrePad + index] = emphasized[index] }
        let stftFrames = max(0, (padded.count - nFFT) / hopLength + 1)
        let frames = min(stftFrames, audio.count / hopLength)
        guard frames > 0 else { throw LocalASREngineError.emptyResult }
        let usable = min(frames, encoderMelFrames)
        let mel = try MLMultiArray(
            shape: [1, NSNumber(value: numMelBins), NSNumber(value: encoderMelFrames)],
            dataType: .float32
        )
        let melPointer = mel.dataPointer.bindMemory(to: Float.self, capacity: mel.count)
        for index in 0..<(numMelBins * encoderMelFrames) { melPointer[index] = 0 }

        var frame = [Float](repeating: 0, count: nFFT)
        var real = [Float](repeating: 0, count: nFFT / 2)
        var imaginary = [Float](repeating: 0, count: nFFT / 2)
        var power = [Float](repeating: 0, count: nBins)
        var melFrame = [Float](repeating: 0, count: numMelBins)

        for time in 0..<usable {
            for index in 0..<nFFT { frame[index] = 0 }
            let start = time * hopLength
            for index in 0..<winLength {
                frame[windowOffset + index] = padded[start + windowOffset + index] * hannWindow[index]
            }
            computePowerSpectrum(
                frame: frame,
                real: &real,
                imaginary: &imaginary,
                power: &power,
                fftSetup: fftSetup,
                log2FFT: log2FFT
            )
            melFilterbank.withUnsafeBufferPointer { bank in
                power.withUnsafeBufferPointer { spectrum in
                    melFrame.withUnsafeMutableBufferPointer { output in
                        vDSP_mmul(
                            spectrum.baseAddress!, 1,
                            bank.baseAddress!, 1,
                            output.baseAddress!, 1,
                            1,
                            vDSP_Length(numMelBins),
                            vDSP_Length(nBins)
                        )
                    }
                }
            }
            for bin in 0..<numMelBins {
                melPointer[bin * encoderMelFrames + time] = log(melFrame[bin] + logGuard)
            }
        }
        normalize(melPointer, frames: usable)
        return (mel, frames)
    }

    private func normalize(_ mel: UnsafeMutablePointer<Float>, frames: Int) {
        guard frames > 1 else { return }
        for bin in 0..<numMelBins {
            let row = mel + bin * encoderMelFrames
            var sum: Float = 0
            for frame in 0..<frames { sum += row[frame] }
            let mean = sum / Float(frames)
            var squaredDeviation: Float = 0
            for frame in 0..<frames {
                let difference = row[frame] - mean
                squaredDeviation += difference * difference
            }
            let variance = squaredDeviation / Float(frames - 1)
            let scale = 1 / ((variance > 0 ? sqrt(variance) : 0) + normEpsilon)
            for frame in 0..<frames { row[frame] = (row[frame] - mean) * scale }
        }
    }

    private static func buildMelFilterbank(nMels: Int, nBins: Int, sampleRate: Int) -> [Float] {
        func hzToMel(_ hz: Double) -> Double {
            let fMin = 0.0
            let fSp = 200.0 / 3.0
            let minLogHz = 1_000.0
            let minLogMel = (minLogHz - fMin) / fSp
            let logStep = log(6.4) / 27.0
            return hz < minLogHz
                ? (hz - fMin) / fSp
                : minLogMel + log(hz / minLogHz) / logStep
        }
        func melToHz(_ mel: Double) -> Double {
            let fMin = 0.0
            let fSp = 200.0 / 3.0
            let minLogHz = 1_000.0
            let minLogMel = (minLogHz - fMin) / fSp
            let logStep = log(6.4) / 27.0
            return mel < minLogMel
                ? fMin + fSp * mel
                : minLogHz * exp(logStep * (mel - minLogMel))
        }
        let melMin = hzToMel(0)
        let melMax = hzToMel(Double(sampleRate) / 2)
        var edges = [Double](repeating: 0, count: nMels + 2)
        for index in 0...(nMels + 1) {
            edges[index] = melToHz(
                melMin + (melMax - melMin) * Double(index) / Double(nMels + 1)
            )
        }
        let binHz = Double(sampleRate) / 512.0
        var bank = [Float](repeating: 0, count: nBins * nMels)
        for mel in 0..<nMels {
            let left = edges[mel]
            let centre = edges[mel + 1]
            let right = edges[mel + 2]
            let normalization = right > left ? 2.0 / (right - left) : 0
            for bin in 0..<nBins {
                let hz = Double(bin) * binHz
                var weight = 0.0
                if hz >= left && hz <= centre, centre > left {
                    weight = (hz - left) / (centre - left)
                } else if hz > centre && hz <= right, right > centre {
                    weight = (right - hz) / (right - centre)
                }
                bank[bin * nMels + mel] = Float(weight * normalization)
            }
        }
        return bank
    }
}

@available(macOS 15.0, *)
private final class PathBMelFrontend: @unchecked Sendable {
    private let numMelBins = 128
    private let nFFT = 512
    private let hopLength = 160
    private let winLength = 400
    private let centrePad = 256
    private let windowOffset = 56
    private let maxFrames = 1_501
    private let preEmphasis = Float(0.97)
    private let logGuard = Float(5.960464477539063e-08)
    private let normEpsilon = Float(1e-5)
    private let fftSetup: FFTSetup
    private let hannWindow: [Float]
    private let melFilterbank: [Float]

    init() throws {
        guard let fftSetup = vDSP_create_fftsetup(9, FFTRadix(kFFTRadix2)) else {
            throw LocalASREngineError.inferenceFailed("Could not create the Canary 1B FFT setup.")
        }
        self.fftSetup = fftSetup
        let windowLength = 400
        self.hannWindow = (0..<windowLength).map {
            0.5 * (1.0 - cos(2.0 * Float.pi * Float($0) / Float(windowLength - 1)))
        }
        self.melFilterbank = Self.buildMelFilterbank(
            nMels: 128,
            nBins: 512 / 2 + 1,
            sampleRate: 16_000
        )
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func extract(_ source: [Float]) throws -> (mel: MLMultiArray, frames: Int) {
        let audio = Array(source.prefix(240_000))
        guard !audio.isEmpty else { throw LocalASREngineError.emptyResult }
        var emphasized = [Float](repeating: 0, count: audio.count)
        emphasized[0] = audio[0]
        if audio.count > 1 {
            for index in 1..<audio.count {
                emphasized[index] = audio[index] - preEmphasis * audio[index - 1]
            }
        }

        var padded = [Float](repeating: 0, count: audio.count + centrePad * 2)
        for index in audio.indices { padded[centrePad + index] = emphasized[index] }
        if audio.count > centrePad + 1 {
            for index in 0..<centrePad {
                padded[centrePad - 1 - index] = emphasized[index + 1]
                padded[centrePad + audio.count + index] = emphasized[audio.count - 2 - index]
            }
        }

        let stftFrames = max(0, (padded.count - nFFT) / hopLength + 1)
        let frames = min(stftFrames, maxFrames)
        guard frames > 0 else { throw LocalASREngineError.emptyResult }
        let mel = try MLMultiArray(
            shape: [1, NSNumber(value: numMelBins), NSNumber(value: maxFrames)],
            dataType: .float32
        )
        let pointer = mel.dataPointer.bindMemory(to: Float.self, capacity: mel.count)
        for index in 0..<mel.count { pointer[index] = 0 }

        var frame = [Float](repeating: 0, count: nFFT)
        var real = [Float](repeating: 0, count: nFFT / 2)
        var imaginary = [Float](repeating: 0, count: nFFT / 2)
        var power = [Float](repeating: 0, count: nFFT / 2 + 1)
        var melFrame = [Float](repeating: 0, count: numMelBins)

        for time in 0..<frames {
            for index in 0..<nFFT { frame[index] = 0 }
            let start = time * hopLength
            for index in 0..<winLength {
                frame[windowOffset + index] = padded[start + windowOffset + index] * hannWindow[index]
            }
            computePowerSpectrum(
                frame: frame,
                real: &real,
                imaginary: &imaginary,
                power: &power,
                fftSetup: fftSetup,
                log2FFT: 9
            )
            melFilterbank.withUnsafeBufferPointer { bank in
                power.withUnsafeBufferPointer { spectrum in
                    melFrame.withUnsafeMutableBufferPointer { output in
                        vDSP_mmul(
                            spectrum.baseAddress!, 1,
                            bank.baseAddress!, 1,
                            output.baseAddress!, 1,
                            1,
                            vDSP_Length(numMelBins),
                            vDSP_Length(nFFT / 2 + 1)
                        )
                    }
                }
            }
            for bin in 0..<numMelBins {
                pointer[bin * maxFrames + time] = log(melFrame[bin] + logGuard)
            }
        }
        normalize(pointer, frames: frames)
        return (mel, frames)
    }

    private func normalize(_ mel: UnsafeMutablePointer<Float>, frames: Int) {
        guard frames > 1 else { return }
        for bin in 0..<numMelBins {
            let row = mel + bin * maxFrames
            var mean: Float = 0
            for frame in 0..<frames { mean += row[frame] }
            mean /= Float(frames)
            var squaredDeviation: Float = 0
            for frame in 0..<frames {
                let difference = row[frame] - mean
                squaredDeviation += difference * difference
            }
            let variance = squaredDeviation / Float(frames - 1)
            let scale = 1 / ((variance > 0 ? sqrt(variance) : 0) + normEpsilon)
            for frame in 0..<frames { row[frame] = (row[frame] - mean) * scale }
        }
    }

    private static func buildMelFilterbank(nMels: Int, nBins: Int, sampleRate: Int) -> [Float] {
        func hzToMel(_ hz: Double) -> Double {
            let fMin = 0.0
            let fSp = 200.0 / 3.0
            let minLogHz = 1_000.0
            let minLogMel = (minLogHz - fMin) / fSp
            let logStep = log(6.4) / 27.0
            return hz < minLogHz
                ? (hz - fMin) / fSp
                : minLogMel + log(hz / minLogHz) / logStep
        }
        func melToHz(_ mel: Double) -> Double {
            let fMin = 0.0
            let fSp = 200.0 / 3.0
            let minLogHz = 1_000.0
            let minLogMel = (minLogHz - fMin) / fSp
            let logStep = log(6.4) / 27.0
            return mel < minLogMel
                ? fMin + fSp * mel
                : minLogHz * exp(logStep * (mel - minLogMel))
        }
        let melMin = hzToMel(0)
        let melMax = hzToMel(Double(sampleRate) / 2)
        var edges = [Double](repeating: 0, count: nMels + 2)
        for index in 0...(nMels + 1) {
            edges[index] = melToHz(
                melMin + (melMax - melMin) * Double(index) / Double(nMels + 1)
            )
        }
        let binHz = Double(sampleRate) / 512.0
        var bank = [Float](repeating: 0, count: nBins * nMels)
        for mel in 0..<nMels {
            let left = edges[mel]
            let centre = edges[mel + 1]
            let right = edges[mel + 2]
            let normalization = right > left ? 2.0 / (right - left) : 0
            for bin in 0..<nBins {
                let hz = Double(bin) * binHz
                var weight = 0.0
                if hz >= left && hz <= centre, centre > left {
                    weight = (hz - left) / (centre - left)
                } else if hz > centre && hz <= right, right > centre {
                    weight = (right - hz) / (right - centre)
                }
                bank[bin * nMels + mel] = Float(weight * normalization)
            }
        }
        return bank
    }
}

private func computePowerSpectrum(
    frame: [Float],
    real: inout [Float],
    imaginary: inout [Float],
    power: inout [Float],
    fftSetup: FFTSetup,
    log2FFT: vDSP_Length
) {
    real.withUnsafeMutableBufferPointer { realBuffer in
        imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
            var split = DSPSplitComplex(
                realp: realBuffer.baseAddress!,
                imagp: imaginaryBuffer.baseAddress!
            )
            frame.withUnsafeBufferPointer { source in
                source.baseAddress!.withMemoryRebound(
                    to: DSPComplex.self,
                    capacity: frame.count / 2
                ) { complex in
                    vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(frame.count / 2))
                }
            }
            vDSP_fft_zrip(fftSetup, &split, 1, log2FFT, FFTDirection(FFT_FORWARD))
            let dc = split.realp[0] * 0.5
            let nyquist = split.imagp[0] * 0.5
            split.imagp[0] = 0
            power[0] = dc * dc
            for bin in 1..<(frame.count / 2) {
                let re = split.realp[bin] * 0.5
                let im = split.imagp[bin] * 0.5
                power[bin] = re * re + im * im
            }
            power[frame.count / 2] = nyquist * nyquist
        }
    }
}

// MARK: - SentencePiece and Core ML helpers

private struct SentencePieceModel {
    let pieces: [String]

    init(url: URL) throws {
        self.pieces = Self.parsePieces(from: try Data(contentsOf: url))
    }

    private static func parsePieces(from data: Data) -> [String] {
        let bytes = [UInt8](data)
        var pieces: [String] = []
        var offset = 0
        while offset < bytes.count {
            let (tag, afterTag) = readVarint(bytes, offset)
            guard afterTag > offset else { break }
            offset = afterTag
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            if fieldNumber == 1 && wireType == 2 {
                let (length, afterLength) = readVarint(bytes, offset)
                offset = afterLength
                let end = offset + length
                guard end <= bytes.count else { break }
                var pieceOffset = offset
                var piece: String?
                while pieceOffset < end {
                    let (pieceTag, afterPieceTag) = readVarint(bytes, pieceOffset)
                    guard afterPieceTag > pieceOffset else { break }
                    pieceOffset = afterPieceTag
                    let pieceField = pieceTag >> 3
                    let pieceWire = pieceTag & 0x7
                    if pieceField == 1 && pieceWire == 2 {
                        let (stringLength, afterStringLength) = readVarint(bytes, pieceOffset)
                        pieceOffset = afterStringLength
                        guard pieceOffset + stringLength <= bytes.count else { break }
                        piece = String(
                            bytes: bytes[pieceOffset..<(pieceOffset + stringLength)],
                            encoding: .utf8
                        )
                        pieceOffset += stringLength
                    } else if pieceField == 2 && pieceWire == 5 {
                        pieceOffset += 4
                    } else if pieceField == 3 && pieceWire == 0 {
                        let (_, afterValue) = readVarint(bytes, pieceOffset)
                        pieceOffset = afterValue
                    } else {
                        break
                    }
                }
                pieces.append(piece ?? "")
                offset = end
            } else if wireType == 0 {
                let (_, afterValue) = readVarint(bytes, offset)
                offset = afterValue
            } else if wireType == 2 {
                let (length, afterLength) = readVarint(bytes, offset)
                offset = afterLength + length
            } else if wireType == 5 {
                offset += 4
            } else {
                break
            }
        }
        return pieces
    }

    private static func readVarint(_ bytes: [UInt8], _ offset: Int) -> (Int, Int) {
        var result = 0
        var shift = 0
        var current = offset
        while current < bytes.count {
            let byte = Int(bytes[current])
            current += 1
            result |= (byte & 0x7F) << shift
            if byte & 0x80 == 0 { return (result, current) }
            shift += 7
            if shift >= Int.bitWidth { break }
        }
        return (result, current)
    }
}

private func makeI32(_ values: [Int]) throws -> MLMultiArray {
    let array = try MLMultiArray(
        shape: [1, NSNumber(value: values.count)],
        dataType: .int32
    )
    for (index, value) in values.enumerated() {
        array[index] = NSNumber(value: value)
    }
    return array
}

private func makeI32Scalar(_ value: Int) throws -> MLMultiArray {
    let array = try MLMultiArray(shape: [1], dataType: .int32)
    array[0] = NSNumber(value: value)
    return array
}

private func makeFloatArray(_ values: [Float], shape: [Int]) throws -> MLMultiArray {
    let array = try MLMultiArray(
        shape: shape.map { NSNumber(value: $0) },
        dataType: .float32
    )
    precondition(values.count == array.count)
    _ = values.withUnsafeBufferPointer { buffer in
        memcpy(
            array.dataPointer,
            buffer.baseAddress!,
            values.count * MemoryLayout<Float>.stride
        )
    }
    return array
}
