import Foundation

public struct ShortsTranscriptDetail: Equatable, Sendable {
    public var source: String
    public var target: String
}

public enum ShortsTranscriptExtractor {
    private struct TimedTranscriptLine: Equatable, Sendable {
        var startSec: Double
        var endSec: Double
        var text: String
    }

    public static func planningTranscript(
        session: SessionState,
        mode: ShortsPlanLanguageMode
    ) -> String {
        switch mode {
        case .source:
            return singleSidePlanningTranscript(chunks: session.chunks, side: .source, targetLanguage: nil)
        case .target:
            return singleSidePlanningTranscript(
                chunks: session.chunks,
                side: .target,
                targetLanguage: session.selectedTranslationLanguage
            )
        case .bilingual:
            let sourceLines = collectPlanningLines(
                chunks: session.chunks,
                side: .source,
                targetLanguage: nil
            )
            let targetLines = collectPlanningLines(
                chunks: session.chunks,
                side: .target,
                targetLanguage: session.selectedTranslationLanguage
            )

            return sourceLines
                .map { sourceLine in
                    let targetLine = nearestLine(in: targetLines, to: sourceLine.startSec)
                    return [
                        "[\(ShortsPlanner.secondsToShortsTimestamp(sourceLine.startSec))]",
                        "Source: \(sourceLine.text)",
                        targetLine.map { "Target: \($0.text)" } ?? ""
                    ]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                }
                .joined(separator: "\n\n")
        }
    }

    public static func extract(
        plan: ShortsClipPlan,
        session: SessionState,
        targetLanguage: String?
    ) -> ShortsTranscriptDetail {
        let startSec = ShortsPlanner.parseTimestampToSeconds(plan.start)
        let endSec = ShortsPlanner.parseTimestampToSeconds(plan.end)
        guard endSec > startSec else {
            return ShortsTranscriptDetail(source: "", target: "")
        }

        let source = session.chunks
            .filter { overlaps(start: startSec, end: endSec, itemStart: $0.startSec, itemEnd: $0.endSec) }
            .flatMap { transcriptLines(for: $0, language: nil, rangeStart: startSec, rangeEnd: endSec) }
            .joined(separator: "\n")

        let target = session.chunks
            .filter { overlaps(start: startSec, end: endSec, itemStart: $0.startSec, itemEnd: $0.endSec) }
            .flatMap { transcriptLines(for: $0, language: targetLanguage, rangeStart: startSec, rangeEnd: endSec) }
            .joined(separator: "\n")

        return ShortsTranscriptDetail(source: source, target: target)
    }

    private enum TranscriptSide {
        case source
        case target
    }

    private static func singleSidePlanningTranscript(
        chunks: [ChunkData],
        side: TranscriptSide,
        targetLanguage: String?
    ) -> String {
        collectPlanningLines(chunks: chunks, side: side, targetLanguage: targetLanguage)
            .map { formatLine(timestamp: $0.startSec, text: $0.text) }
            .joined(separator: "\n\n")
    }

    private static func collectPlanningLines(
        chunks: [ChunkData],
        side: TranscriptSide,
        targetLanguage: String?
    ) -> [TimedTranscriptLine] {
        chunks
            .filter { $0.status == .done }
            .flatMap { planningLines(for: $0, side: side, targetLanguage: targetLanguage) }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.startSec < $1.startSec }
    }

    private static func planningLines(
        for chunk: ChunkData,
        side: TranscriptSide,
        targetLanguage: String?
    ) -> [TimedTranscriptLine] {
        switch side {
        case .source:
            if let cues = chunk.originalCues, !cues.isEmpty {
                return timedLines(from: cues, chunkStart: chunk.startSec)
            }
            let clean = chunk.original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return [] }
            return [TimedTranscriptLine(startSec: chunk.startSec, endSec: chunk.endSec, text: clean)]
        case .target:
            let cues = chunk.translationCues(for: targetLanguage)
            if !cues.isEmpty {
                return timedLines(from: cues, chunkStart: chunk.startSec)
            }
            guard
                let text = chunk.translationText(for: targetLanguage),
                TranslationArchive.isUsableTranslationText(text)
            else { return [] }
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return [] }
            return [TimedTranscriptLine(startSec: chunk.startSec, endSec: chunk.endSec, text: clean)]
        }
    }

    private static func timedLines(
        from cues: [TranscriptCue],
        chunkStart: Double
    ) -> [TimedTranscriptLine] {
        cues.map { cue in
            TimedTranscriptLine(
                startSec: absoluteCueTime(cue.startSec, chunkStart: chunkStart),
                endSec: absoluteCueTime(cue.endSec, chunkStart: chunkStart),
                text: cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func nearestLine(
        in lines: [TimedTranscriptLine],
        to startSec: Double
    ) -> TimedTranscriptLine? {
        lines.min {
            abs($0.startSec - startSec) < abs($1.startSec - startSec)
        }
    }

    private static func transcriptLines(
        for chunk: ChunkData,
        language: String?,
        rangeStart: Double,
        rangeEnd: Double
    ) -> [String] {
        if let language {
            let cues = chunk.translationCues(for: language)
            if !cues.isEmpty {
                return cueLines(cues, chunkStart: chunk.startSec, rangeStart: rangeStart, rangeEnd: rangeEnd)
            }
            if let text = chunk.translationText(for: language), TranslationArchive.isUsableTranslationText(text) {
                return [formatLine(timestamp: max(chunk.startSec, rangeStart), text: text)]
            }
            return []
        }

        if let cues = chunk.originalCues, !cues.isEmpty {
            return cueLines(cues, chunkStart: chunk.startSec, rangeStart: rangeStart, rangeEnd: rangeEnd)
        }
        let clean = chunk.original.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? [] : [formatLine(timestamp: max(chunk.startSec, rangeStart), text: clean)]
    }

    private static func cueLines(
        _ cues: [TranscriptCue],
        chunkStart: Double,
        rangeStart: Double,
        rangeEnd: Double
    ) -> [String] {
        cues.compactMap { cue in
            let absoluteStart = absoluteCueTime(cue.startSec, chunkStart: chunkStart)
            let absoluteEnd = absoluteCueTime(cue.endSec, chunkStart: chunkStart)
            guard overlaps(start: rangeStart, end: rangeEnd, itemStart: absoluteStart, itemEnd: absoluteEnd) else {
                return nil
            }
            return formatLine(timestamp: absoluteStart, text: cue.text)
        }
    }

    private static func absoluteCueTime(_ value: Double, chunkStart: Double) -> Double {
        value >= max(0, chunkStart - 0.5) ? value : chunkStart + value
    }

    private static func overlaps(start: Double, end: Double, itemStart: Double, itemEnd: Double) -> Bool {
        itemEnd > start && itemStart < end
    }

    private static func formatLine(timestamp: Double, text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "[\(ShortsPlanner.secondsToShortsTimestamp(timestamp))] \(clean)"
    }
}
