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

/// Shrinks subtitle segment bounds to speech energy so pauses stay caption-free.
public enum SubtitleSpeechAligner {
    public static let defaultPadSec = 0.05
    public static let minSegmentDurationSec = 0.12

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

    /// Shrink each segment to the speech intervals that fall inside its original range.
    /// Does not invent new cues and does not expand beyond the original segment bounds.
    public static func snapSegmentsToSpeech(
        segments: [AlignedSubtitleSegment],
        speechRegions: [SpeechTimeRegion],
        clipDurationSec: Double,
        padSec: Double = defaultPadSec
    ) -> SubtitleSpeechSnapResult {
        let duration = max(0, clipDurationSec)
        let pad = max(0, padSec)
        let speech = speechRegions
            .map { SpeechTimeRegion(startSec: max(0, $0.startSec), endSec: min(duration, $0.endSec)) }
            .filter { $0.endSec > $0.startSec }
            .sorted { $0.startSec < $1.startSec }

        var changes: [SubtitleSpeechSnapChange] = []
        var snapped: [AlignedSubtitleSegment] = []

        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let oldStart = max(0, min(duration, segment.start))
            let oldEnd = max(oldStart, min(duration, segment.end))
            let overlaps = speech.filter { $0.startSec < oldEnd && $0.endSec > oldStart }

            guard let first = overlaps.first, let last = overlaps.last else {
                let unchanged = AlignedSubtitleSegment(
                    id: segment.id,
                    start: oldStart,
                    end: max(oldStart + minSegmentDurationSec, oldEnd),
                    text: segment.text,
                    words: segment.words
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

            var newStart = max(oldStart, first.startSec - pad)
            var newEnd = min(oldEnd, last.endSec + pad)
            if newEnd - newStart < minSegmentDurationSec {
                let mid = (first.startSec + last.endSec) / 2
                newStart = max(oldStart, mid - minSegmentDurationSec / 2)
                newEnd = min(oldEnd, newStart + minSegmentDurationSec)
                if newEnd - newStart < minSegmentDurationSec {
                    newStart = oldStart
                    newEnd = oldEnd
                }
            }

            let base = AlignedSubtitleSegment(
                id: segment.id,
                start: newStart,
                end: newEnd,
                text: segment.text
            )
            let withWords = AlignedSubtitleSegment(
                id: base.id,
                start: base.start,
                end: base.end,
                text: base.text,
                words: ShortsVisualEditorStateBuilder.inferredWords(for: base)
            )
            snapped.append(withWords)
            changes.append(
                SubtitleSpeechSnapChange(
                    segmentId: segment.id,
                    text: segment.text,
                    oldStartSec: oldStart,
                    oldEndSec: oldEnd,
                    newStartSec: withWords.start,
                    newEndSec: withWords.end,
                    status: (abs(oldStart - withWords.start) > 0.001 || abs(oldEnd - withWords.end) > 0.001)
                        ? "snapped"
                        : "unchanged"
                )
            )
        }

        // Resolve accidental overlaps after shrink (prefer earlier segment).
        snapped = resolveOverlaps(snapped, clipDurationSec: duration)

        return SubtitleSpeechSnapResult(
            segments: snapped,
            changes: changes,
            speechRegions: speech
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
                    // Drop zero-width collision rather than expanding into the next cue.
                    continue
                }
            }
            let base = AlignedSubtitleSegment(id: segment.id, start: start, end: end, text: segment.text)
            result.append(
                AlignedSubtitleSegment(
                    id: base.id,
                    start: base.start,
                    end: base.end,
                    text: base.text,
                    words: ShortsVisualEditorStateBuilder.inferredWords(for: base)
                )
            )
        }
        return result
    }
}
