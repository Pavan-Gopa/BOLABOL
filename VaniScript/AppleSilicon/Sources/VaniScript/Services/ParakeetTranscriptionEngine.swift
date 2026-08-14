import FluidAudio
import Foundation
import VaniScriptCore

/// Injectable model-session seam used by Parakeet and by tests without Core ML weights.
protocol ParakeetTranscriptionSession: Sendable {
    func transcribe(audioFileURL: URL, language: Language?) async throws -> ASRResult
    func unload() async
}

typealias ParakeetSessionLoader = @Sendable (URL) async throws -> any ParakeetTranscriptionSession

private actor FluidAudioParakeetSession: ParakeetTranscriptionSession {
    private var manager: AsrManager?

    init(manager: AsrManager) {
        self.manager = manager
    }

    func transcribe(audioFileURL: URL, language: Language?) async throws -> ASRResult {
        guard let manager else {
            throw LocalASREngineError.inferenceFailed("The Parakeet model is unloaded.")
        }

        let decoderLayers = await manager.decoderLayerCount
        var requestState: TdtDecoderState
        do {
            requestState = try TdtDecoderState(decoderLayers: decoderLayers)
        } catch {
            throw LocalASREngineError.decoderStateInitializationFailed(
                error.localizedDescription
            )
        }

        return try await manager.transcribe(
            audioFileURL,
            decoderState: &requestState,
            language: language
        )
    }

    func unload() {
        manager = nil
    }
}

private let defaultParakeetSessionLoader: ParakeetSessionLoader = { modelFolderURL in
    let models = try await AsrModels.load(
        from: modelFolderURL,
        version: .v3,
        encoderPrecision: .int8
    )
    let manager = AsrManager(config: .default)
    try await manager.loadModels(models)
    return FluidAudioParakeetSession(manager: manager)
}

/// FluidAudio v3/int8 local transcription with one resident model session.
///
/// The descriptor and model path are supplied by the catalog/download layer. This
/// engine validates that binding before loading and never invokes a downloader.
actor ParakeetTranscriptionEngine: LocalASREngine {
    nonisolated let descriptor: LocalASRModelDescriptor

    private let modelFolderURL: URL
    private let audioPreprocessor: LocalASRAudioPreprocessor
    private let fileManager: FileManager
    private let temporaryDirectory: URL
    private let sessionLoader: ParakeetSessionLoader
    private var session: (any ParakeetTranscriptionSession)?

    init(
        model: LocalASRModelDescriptor,
        modelFolderURL: URL,
        audioPreprocessor: LocalASRAudioPreprocessor = LocalASRAudioPreprocessor(),
        fileManager: FileManager = .default,
        temporaryDirectory: URL? = nil,
        sessionLoader: @escaping ParakeetSessionLoader = defaultParakeetSessionLoader
    ) {
        self.descriptor = model
        self.modelFolderURL = modelFolderURL
        self.audioPreprocessor = audioPreprocessor
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory ?? fileManager.temporaryDirectory
        self.sessionLoader = sessionLoader
    }

    func transcribe(_ request: LocalASRRequest) async throws -> LocalASRResult {
        try Task.checkCancellation()
        guard let sourceURL = request.audioFileURL else {
            throw LocalASREngineError.missingAudioFile
        }
        guard !request.translateToEnglish else {
            throw LocalASREngineError.translationUnsupported
        }
        try validateModelBinding()

        let normalizedAudioURL = temporaryDirectory.appendingPathComponent(
            "vaniscript-local-asr-\(UUID().uuidString).wav"
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
        let session = try await loadedSession()
        try Task.checkCancellation()

        let language = mappedLanguage(from: request.languageHint)
        let result: ASRResult
        do {
            result = try await session.transcribe(
                audioFileURL: normalizedAudioURL,
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
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw LocalASREngineError.emptyResult
        }

        let cues: [TranscriptCue]
        if let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty {
            cues = Self.timedCues(from: result)
        } else {
            guard result.duration.isFinite, result.duration > 0 else {
                throw LocalASREngineError.inferenceFailed("Could not bound transcript timing without valid duration.")
            }
            cues = Self.boundedCuesFromUntimedText(text, startSec: 0, endSec: result.duration)
            guard !cues.isEmpty else {
                throw LocalASREngineError.inferenceFailed("Could not segment transcript text into bounded cues.")
            }
        }

        return LocalASRResult(
            text: text,
            cues: cues
        )
    }

    /// Converts FluidAudio's real token timings into bounded word-bearing cues.
    /// Cue boundaries use observed gaps, punctuation, and fixed word/duration
    /// limits so long recordings cannot collapse into one review cue.
    nonisolated internal static func timedCues(from result: ASRResult) -> [TranscriptCue] {
        guard let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty else {
            return []
        }

        let wordTimings = buildWordTimings(from: tokenTimings)
        let fallbackDuration = wordTimings
            .map(\.endTime)
            .filter { $0.isFinite }
            .max() ?? 0
        let duration = result.duration.isFinite && result.duration > 0
            ? result.duration
            : fallbackDuration
        guard duration.isFinite, duration > 0 else { return [] }

        var words: [TranscriptWord] = []
        words.reserveCapacity(wordTimings.count)
        var previousEnd = 0.0
        for timing in wordTimings {
            let word = timing.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty,
                  timing.startTime.isFinite,
                  timing.endTime.isFinite
            else {
                continue
            }

            let start = min(duration, max(previousEnd, max(0, timing.startTime)))
            let end = min(duration, max(start, timing.endTime))
            guard end > start else { continue }
            words.append(TranscriptWord(startSec: start, endSec: end, text: word))
            previousEnd = end
        }
        guard !words.isEmpty else { return [] }

        let maximumCueDuration = 5.0
        let maximumCueWords = 10
        let silenceBreak = 0.8
        var cues: [TranscriptCue] = []
        var currentWords: [TranscriptWord] = []
        currentWords.reserveCapacity(maximumCueWords)

        func flush() {
            guard let first = currentWords.first,
                  let last = currentWords.last
            else {
                currentWords.removeAll(keepingCapacity: true)
                return
            }
            let text = currentWords.map(\.text).joined(separator: " ")
            guard !text.isEmpty, last.endSec > first.startSec else {
                currentWords.removeAll(keepingCapacity: true)
                return
            }
            cues.append(
                TranscriptCue(
                    startSec: first.startSec,
                    endSec: last.endSec,
                    text: text,
                    words: currentWords
                )
            )
            currentWords.removeAll(keepingCapacity: true)
        }

        for word in words {
            if let previous = currentWords.last {
                let gap = word.startSec - previous.endSec
                let sentenceBoundary = previous.text.last.map { ".!?".contains($0) } ?? false
                let durationExceeded = word.endSec - (currentWords.first?.startSec ?? word.startSec)
                    > maximumCueDuration
                if gap >= silenceBreak
                    || sentenceBoundary
                    || durationExceeded
                    || currentWords.count >= maximumCueWords
                {
                    flush()
                }
            }
            currentWords.append(word)
        }
        flush()
        return cues
    }
    /// Builds bounded word-bearing cues from untimed transcript text across a known duration.
    /// Uses sentence (.!?) and clause (,;:) boundaries, word limits, and max cue duration.
    nonisolated internal static func boundedCuesFromUntimedText(
        _ rawText: String,
        startSec: Double = 0,
        endSec: Double
    ) -> [TranscriptCue] {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, startSec.isFinite, endSec.isFinite, endSec > startSec else {
            return []
        }

        let totalDuration = endSec - startSec
        let words = text
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return [] }

        let maximumCueDuration = 5.0
        let maximumCueWords = 10

        var cueGroups: [[String]] = []
        var currentGroup: [String] = []

        for word in words {
            currentGroup.append(word)
            let isSentenceOrClauseEnd = word.last.map { ".!?,;:".contains($0) } ?? false
            if isSentenceOrClauseEnd || currentGroup.count >= maximumCueWords {
                cueGroups.append(currentGroup)
                currentGroup = []
            }
        }
        if !currentGroup.isEmpty {
            cueGroups.append(currentGroup)
        }

        let totalWordCount = Double(words.count)
        var cues: [TranscriptCue] = []
        var previousEnd = startSec

        for group in cueGroups {
            let groupText = group.joined(separator: " ")
            let groupWordCount = Double(group.count)

            let rawDuration = (groupWordCount / totalWordCount) * totalDuration
            let cueDuration = min(maximumCueDuration, rawDuration)

            let cueStart = previousEnd
            let cueEnd = min(endSec, cueStart + cueDuration)

            guard cueEnd > cueStart else { continue }

            let wordStep = (cueEnd - cueStart) / Double(group.count)
            let cueWords: [TranscriptWord] = group.enumerated().map { wordIndex, wordStr in
                let wStart = cueStart + Double(wordIndex) * wordStep
                let wEnd = wordIndex == group.count - 1 ? cueEnd : min(cueEnd, wStart + wordStep)
                return TranscriptWord(startSec: wStart, endSec: max(wStart + 0.01, wEnd), text: wordStr)
            }

            cues.append(
                TranscriptCue(
                    startSec: cueStart,
                    endSec: cueEnd,
                    text: groupText,
                    words: cueWords.isEmpty ? nil : cueWords
                )
            )
            previousEnd = cueEnd
        }

        return cues
    }

    func unload() async {
        guard let session else { return }
        self.session = nil
        await session.unload()
    }

    private func loadedSession() async throws -> any ParakeetTranscriptionSession {
        if let session {
            return session
        }

        try validateModelBinding()
        do {
            let loaded = try await sessionLoader(modelFolderURL)
            session = loaded
            return loaded
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LocalASREngineError {
            throw error
        } catch {
            throw LocalASREngineError.inferenceFailed(
                "Could not load the Parakeet model: \(error.localizedDescription)"
            )
        }
    }

    private func validateModelBinding() throws {
        guard descriptor.backend == .fluidAudioCoreML else {
            throw LocalASREngineError.unsupportedModel(
                "expected the FluidAudio Core ML backend"
            )
        }
        guard case let .fluidAudio(version, encoderPrecision) = descriptor.installSource,
              version == "v3",
              encoderPrecision.lowercased() == "int8"
        else {
            throw LocalASREngineError.unsupportedModel(
                "expected FluidAudio v3/int8 model metadata"
            )
        }
        guard NativeModelCatalog.isModelPresent(
            descriptor,
            at: modelFolderURL,
            fileManager: fileManager
        ) else {
            throw LocalASREngineError.modelUnavailable(modelFolderURL)
        }
    }

    /// FluidAudio's language hint is a script filter, not a forced recognizer
    /// language. Only a catalog-supported explicit code is passed through; auto,
    /// empty, malformed, and unsupported hints preserve model auto-detection.
    private func mappedLanguage(from hint: String?) -> Language? {
        guard let hint else { return nil }
        let normalized = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "auto" else { return nil }

        let supported = Set(
            descriptor.capabilities.supportedLanguageCodes.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )
        guard supported.contains(normalized) else { return nil }
        return Language(rawValue: normalized)
    }
}
