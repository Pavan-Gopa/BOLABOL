import Foundation

/// Time interval in **clip-relative** seconds (0 = clip start).
public struct SpeechTimeRegion: Equatable, Sendable {
    public var startSec: Double
    public var endSec: Double

    public init(startSec: Double, endSec: Double) {
        self.startSec = startSec
        self.endSec = endSec
    }

    public var durationSec: Double { max(0, endSec - startSec) }
}

public struct SubtitleSpeechSnapChange: Equatable, Sendable {
    public var segmentId: String
    public var text: String
    public var oldStartSec: Double
    public var oldEndSec: Double
    public var newStartSec: Double
    public var newEndSec: Double
    public var status: String

    public init(
        segmentId: String,
        text: String,
        oldStartSec: Double,
        oldEndSec: Double,
        newStartSec: Double,
        newEndSec: Double,
        status: String
    ) {
        self.segmentId = segmentId
        self.text = text
        self.oldStartSec = oldStartSec
        self.oldEndSec = oldEndSec
        self.newStartSec = newStartSec
        self.newEndSec = newEndSec
        self.status = status
    }

    public var changed: Bool {
        abs(oldStartSec - newStartSec) > 0.001 || abs(oldEndSec - newEndSec) > 0.001
    }
}

public struct SubtitleSpeechSnapResult: Equatable, Sendable {
    public var segments: [AlignedSubtitleSegment]
    public var changes: [SubtitleSpeechSnapChange]
    public var speechRegions: [SpeechTimeRegion]

    public init(
        segments: [AlignedSubtitleSegment],
        changes: [SubtitleSpeechSnapChange],
        speechRegions: [SpeechTimeRegion]
    ) {
        self.segments = segments
        self.changes = changes
        self.speechRegions = speechRegions
    }
}

/// Shrinks (and splits) subtitle segment bounds to speech energy so pauses stay caption-free.
public enum SubtitleSpeechAligner {
    public static let defaultPadSec = 0.04
    public static let minSegmentDurationSec = 0.10
    /// Minimum internal silence (sec) that causes a segment to split into multiple cues.
    public static let defaultSplitSilenceSec = 0.25

    public static func speechRegions(
        profile: [AudioEnergyWindow],
        clipDurationSec: Double,
        thresholdDb: Double,
        minSilenceMs: Int
    ) -> [SpeechTimeRegion] {
        let totalMs = max(0, Int((clipDurationSec * 1_000).rounded()))
        return SmartSlicePlanner.speechRegions(
            profile: profile,
            totalDurationMs: totalMs,
            thresholdDb: thresholdDb,
            minSilenceMs: minSilenceMs
        ).map {
            SpeechTimeRegion(
                startSec: Double($0.startMs) / 1_000,
                endSec: Double($0.endMs) / 1_000
            )
        }
    }

    /// Align segments to speech:
    /// - shrink bounds to speech inside the original range;
    /// - **split** a segment when it covers multiple speech islands separated by silence
    ///   (so mid-cue pauses no longer show captions).
    public static func snapSegmentsToSpeech(
        segments: [AlignedSubtitleSegment],
        speechRegions: [SpeechTimeRegion],
        clipDurationSec: Double,
        padSec: Double = defaultPadSec,
        splitSilenceSec: Double = defaultSplitSilenceSec
    ) -> SubtitleSpeechSnapResult {
        let duration = max(0, clipDurationSec)
        let pad = max(0, padSec)
        let minSplitGap = max(0.08, splitSilenceSec)
        let speech = speechRegions
            .map { SpeechTimeRegion(startSec: max(0, $0.startSec), endSec: min(duration, $0.endSec)) }
            .filter { $0.endSec > $0.startSec }
            .sorted { $0.startSec < $1.startSec }

        var changes: [SubtitleSpeechSnapChange] = []
        var snapped: [AlignedSubtitleSegment] = []

        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let oldStart = max(0, min(duration, segment.start))
            let oldEnd = max(oldStart, min(duration, segment.end))
            let overlaps = speech
                .filter { $0.startSec < oldEnd && $0.endSec > oldStart }
                .map { island in
                    SpeechTimeRegion(
                        startSec: max(oldStart, island.startSec),
                        endSec: min(oldEnd, island.endSec)
                    )
                }
                .filter { $0.endSec - $0.startSec >= minSegmentDurationSec * 0.5 }

            guard !overlaps.isEmpty else {
                let unchanged = makeSegment(
                    id: segment.id,
                    start: oldStart,
                    end: max(oldStart + minSegmentDurationSec, oldEnd),
                    text: segment.text
                )
                snapped.append(unchanged)
                changes.append(
                    SubtitleSpeechSnapChange(
                        segmentId: segment.id,
                        text: segment.text,
                        oldStartSec: oldStart,
                        oldEndSec: oldEnd,
                        newStartSec: unchanged.start,
                        newEndSec: unchanged.end,
                        status: "no_speech_in_range"
                    )
                )
                continue
            }

            // Merge adjacent speech islands separated by tiny gaps (< splitSilenceSec).
            let islands = mergeCloseIslands(overlaps, maxGapSec: minSplitGap)
            let wordPieces = distributeText(segment.text, across: islands.count)

            for (index, island) in islands.enumerated() {
                var newStart = max(oldStart, island.startSec - pad)
                var newEnd = min(oldEnd, island.endSec + pad)
                if newEnd - newStart < minSegmentDurationSec {
                    let mid = (island.startSec + island.endSec) / 2
                    newStart = max(oldStart, mid - minSegmentDurationSec / 2)
                    newEnd = min(oldEnd, newStart + minSegmentDurationSec)
                }
                let pieceID = index == 0
                    ? segment.id
                    : "\(segment.id)_s\(index)_\(Int((newStart * 1000).rounded()))"
                let pieceText = wordPieces[index]
                let piece = makeSegment(id: pieceID, start: newStart, end: newEnd, text: pieceText)
                snapped.append(piece)

                let status: String
                if islands.count > 1 {
                    status = index == 0 ? "split_head" : "split_part"
                } else if abs(oldStart - newStart) > 0.001 || abs(oldEnd - newEnd) > 0.001 {
                    status = "snapped"
                } else {
                    status = "unchanged"
                }
                changes.append(
                    SubtitleSpeechSnapChange(
                        segmentId: pieceID,
                        text: pieceText,
                        oldStartSec: oldStart,
                        oldEndSec: oldEnd,
                        newStartSec: piece.start,
                        newEndSec: piece.end,
                        status: status
                    )
                )
            }
        }

        snapped = resolveOverlaps(snapped, clipDurationSec: duration)

        return SubtitleSpeechSnapResult(
            segments: snapped,
            changes: changes,
            speechRegions: speech
        )
    }

    private static func mergeCloseIslands(
        _ islands: [SpeechTimeRegion],
        maxGapSec: Double
    ) -> [SpeechTimeRegion] {
        guard var current = islands.first else { return [] }
        var result: [SpeechTimeRegion] = []
        for next in islands.dropFirst() {
            if next.startSec - current.endSec <= maxGapSec {
                current = SpeechTimeRegion(startSec: current.startSec, endSec: max(current.endSec, next.endSec))
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }

    private static func distributeText(_ text: String, across count: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard count > 1 else { return [trimmed] }
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= count else {
            // Not enough words to split cleanly — keep full text on first island, minimal on rest.
            return (0..<count).map { $0 == 0 ? trimmed : "…" }
        }
        let base = words.count / count
        let remainder = words.count % count
        var pieces: [String] = []
        var cursor = 0
        for index in 0..<count {
            let take = base + (index < remainder ? 1 : 0)
            let slice = words[cursor..<(cursor + take)]
            pieces.append(slice.joined(separator: " "))
            cursor += take
        }
        return pieces
    }

    private static func makeSegment(id: String, start: Double, end: Double, text: String) -> AlignedSubtitleSegment {
        let base = AlignedSubtitleSegment(id: id, start: start, end: end, text: text)
        return AlignedSubtitleSegment(
            id: base.id,
            start: base.start,
            end: base.end,
            text: base.text,
            words: ShortsVisualEditorStateBuilder.inferredWords(for: base)
        )
    }

    private static func resolveOverlaps(
        _ segments: [AlignedSubtitleSegment],
        clipDurationSec: Double
    ) -> [AlignedSubtitleSegment] {
        var result: [AlignedSubtitleSegment] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            var start = max(0, segment.start)
            let end = max(start, min(clipDurationSec, segment.end))
            if let previous = result.last, start < previous.end {
                start = previous.end
                if end - start < minSegmentDurationSec {
                    continue
                }
            }
            result.append(makeSegment(id: segment.id, start: start, end: end, text: segment.text))
        }
        return result
    }
}
