import Foundation
import VaniScriptCore

public struct FileTranscriptionChunk: Sendable, Equatable {
    public let index: Int
    public let startSec: Double
    public let endSec: Double

    public init(index: Int, startSec: Double, endSec: Double) {
        self.index = index
        self.startSec = startSec
        self.endSec = endSec
    }
}

public struct ChunkTranscription: Sendable, Equatable {
    public let index: Int
    public let text: String
    public let cues: [TranscriptCue]

    public init(index: Int, text: String, cues: [TranscriptCue]) {
        self.index = index
        self.text = text
        self.cues = cues
    }
}

public struct RelativeTranscription: Sendable, Equatable {
    public let text: String
    public let cues: [TranscriptCue]?

    public init(text: String, cues: [TranscriptCue]? = nil) {
        self.text = text
        self.cues = cues
    }
}
public enum AudioChunkProcessingError: Error, Equatable, Sendable {
    case missingModelCues
}


public struct AudioChunkProcessingService: Sendable {
    public typealias Export = @Sendable (URL, FileTranscriptionChunk, URL) async throws -> URL
    public typealias Transcribe = @Sendable (URL, FileTranscriptionChunk) async throws -> RelativeTranscription
    private let export: Export
    private let transcribe: Transcribe

    public init(export: @escaping Export, transcribe: @escaping Transcribe) {
        self.export = export
        self.transcribe = transcribe
    }

    public func process(
        sourceURL: URL,
        chunk: FileTranscriptionChunk,
        workspaceURL: URL
    ) async throws -> ChunkTranscription {
        try Task.checkCancellation()
        let audioURL = try await export(sourceURL, chunk, workspaceURL)
        let result = try await transcribe(audioURL, chunk)
        let cleanText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let timedCues = result.cues else {
            if cleanText.isEmpty {
                return ChunkTranscription(index: chunk.index, text: cleanText, cues: [])
            }
            throw AudioChunkProcessingError.missingModelCues
        }
        let cues = Self.absoluteCues(timedCues, chunk: chunk)
        return ChunkTranscription(index: chunk.index, text: cleanText, cues: cues)
    }

    public static func absoluteCues(
        _ timedCues: [TranscriptCue],
        chunk: FileTranscriptionChunk
    ) -> [TranscriptCue] {

        var mapped: [TranscriptCue] = []
        mapped.reserveCapacity(timedCues.count)
        var previousCueEnd = chunk.startSec
        for cue in timedCues {
            let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, cue.startSec.isFinite, cue.endSec.isFinite else { continue }
            let start = min(chunk.endSec, max(previousCueEnd, chunk.startSec + cue.startSec))
            let end = min(chunk.endSec, max(start, chunk.startSec + cue.endSec))
            guard end > start else { continue }

            var words: [TranscriptWord] = []
            words.reserveCapacity(cue.words?.count ?? 0)
            var previousWordEnd = start
            for word in cue.words ?? [] {
                let wordText = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !wordText.isEmpty, word.startSec.isFinite, word.endSec.isFinite else { continue }
                let wordStart = min(end, max(previousWordEnd, max(start, chunk.startSec + word.startSec)))
                let wordEnd = min(end, max(wordStart, chunk.startSec + word.endSec))
                guard wordEnd > wordStart else { continue }
                words.append(TranscriptWord(startSec: wordStart, endSec: wordEnd, text: wordText))
                previousWordEnd = wordEnd
            }
            mapped.append(TranscriptCue(startSec: start, endSec: end, text: text, words: words.isEmpty ? nil : words))
            previousCueEnd = end
        }
        return mapped
    }
}
