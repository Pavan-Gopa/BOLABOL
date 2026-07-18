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
    /// Concatenated original texts vs output — must match (whitespace-normalized).
    public var preservedAllText: Bool

    public init(
        segments: [AlignedSubtitleSegment],
        changes: [SubtitleSpeechSnapChange],
        speechRegions: [SpeechTimeRegion],
        preservedAllText: Bool
    ) {
        self.segments = segments
        self.changes = changes
        self.speechRegions = speechRegions
        self.preservedAllText = preservedAllText
    }
}

/// Adjusts subtitle timings to speech energy **without deleting caption text**.
///
/// Guarantees:
/// 1. Every input segment produces ≥1 output segment.
/// 2. All words from every input segment appear in the output (no dropped lines).
/// 3. Overlap resolution never discards a segment — only shifts bounds.
public enum SubtitleSpeechAligner {
    public static let defaultPadSec = 0.04
    public static let minSegmentDurationSec = 0.10
    /// Minimum internal silence (sec) that may split a cue into multiple pieces.
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

        let inputNormalized = normalizeWhitespace(
            segments.map(\.text).joined(separator: " ")
        )

        var changes: [SubtitleSpeechSnapChange] = []
        var snapped: [AlignedSubtitleSegment] = []

        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let oldStart = max(0, min(duration, segment.start))
            let oldEnd = max(oldStart + minSegmentDurationSec * 0.5, min(duration, segment.end))
            let originalText = segment.text

            let overlaps = speech
                .filter { $0.startSec < oldEnd && $0.endSec > oldStart }
                .map { island in
                    SpeechTimeRegion(
                        startSec: max(oldStart, island.startSec),
                        endSec: min(oldEnd, island.endSec)
                    )
                }
                .filter { $0.endSec > $0.startSec }

            // No usable speech → keep original text and original (or minimally valid) timing.
            guard !overlaps.isEmpty else {
                let kept = makeSegment(
                    id: segment.id,
                    start: oldStart,
                    end: max(oldStart + minSegmentDurationSec, oldEnd),
                    text: originalText
                )
                snapped.append(kept)
                changes.append(
                    SubtitleSpeechSnapChange(
                        segmentId: segment.id,
                        text: originalText,
                        oldStartSec: oldStart,
                        oldEndSec: oldEnd,
                        newStartSec: kept.start,
                        newEndSec: kept.end,
                        status: "kept_no_speech"
                    )
                )
                continue
            }

            var islands = mergeCloseIslands(overlaps, maxGapSec: minSplitGap)

            // Never create more pieces than we have words — otherwise text would be lost/duplicated.
            let words = tokenizeWords(originalText)
            if words.count > 0, islands.count > words.count {
                islands = mergeToCount(islands, targetCount: words.count)
            }
            // Single-word (or empty) cues: never split — only shrink to first…last speech span.
            if words.count <= 1 {
                islands = [
                    SpeechTimeRegion(
                        startSec: islands.first!.startSec,
                        endSec: islands.last!.endSec
                    )
                ]
            }

            let wordPieces = distributeTextPreservingAllWords(originalText, across: islands.count)
            guard wordPieces.count == islands.count,
                  normalizeWhitespace(wordPieces.joined(separator: " "))
                    == normalizeWhitespace(originalText)
                    || originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                // Fall back: keep full text, shrink timing only for this cue.
                if let first = islands.first, let last = islands.last {
                    var newStart = max(oldStart, first.startSec - pad)
                    var newEnd = min(oldEnd, last.endSec + pad)
                    if newEnd - newStart < minSegmentDurationSec {
                        newStart = oldStart
                        newEnd = oldEnd
                    }
                    let kept = makeSegment(id: segment.id, start: newStart, end: newEnd, text: originalText)
                    snapped.append(kept)
                    changes.append(
                        SubtitleSpeechSnapChange(
                            segmentId: segment.id,
                            text: originalText,
                            oldStartSec: oldStart,
                            oldEndSec: oldEnd,
                            newStartSec: kept.start,
                            newEndSec: kept.end,
                            status: "snapped_safe"
                        )
                    )
                }
                continue
            }

            for (index, island) in islands.enumerated() {
                var newStart = max(oldStart, island.startSec - pad)
                var newEnd = min(oldEnd, island.endSec + pad)
                if newEnd - newStart < minSegmentDurationSec {
                    let mid = (island.startSec + island.endSec) / 2
                    newStart = max(0, mid - minSegmentDurationSec / 2)
                    newEnd = min(duration, newStart + minSegmentDurationSec)
                    if newEnd <= newStart {
                        newStart = oldStart
                        newEnd = max(oldStart + minSegmentDurationSec, oldEnd)
                    }
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

        // Never drop segments when resolving overlaps.
        snapped = resolveOverlapsPreservingAll(snapped, clipDurationSec: duration)

        let outputNormalized = normalizeWhitespace(
            snapped.map(\.text).joined(separator: " ")
        )
        let preserved = outputNormalized == inputNormalized
            || inputNormalized.isEmpty

        // Safety net: if anything went wrong with text, fall back to timing-only shrink
        // without splits so every original cue (full text) is restored.
        if !preserved {
            return snapTimingOnly(
                segments: segments,
                speech: speech,
                clipDurationSec: duration,
                padSec: pad
            )
        }

        return SubtitleSpeechSnapResult(
            segments: snapped,
            changes: changes,
            speechRegions: speech,
            preservedAllText: true
        )
    }

    /// Timing-only path: one output per input, full original text always kept.
    private static func snapTimingOnly(
        segments: [AlignedSubtitleSegment],
        speech: [SpeechTimeRegion],
        clipDurationSec: Double,
        padSec: Double
    ) -> SubtitleSpeechSnapResult {
        var changes: [SubtitleSpeechSnapChange] = []
        var snapped: [AlignedSubtitleSegment] = []

        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let oldStart = max(0, min(clipDurationSec, segment.start))
            let oldEnd = max(oldStart, min(clipDurationSec, segment.end))
            let overlaps = speech.filter { $0.startSec < oldEnd && $0.endSec > oldStart }

            var newStart = oldStart
            var newEnd = oldEnd
            if let first = overlaps.first, let last = overlaps.last {
                newStart = max(oldStart, first.startSec - padSec)
                newEnd = min(oldEnd, last.endSec + padSec)
                if newEnd - newStart < minSegmentDurationSec {
                    newStart = oldStart
                    newEnd = oldEnd
                }
            }

            let kept = makeSegment(id: segment.id, start: newStart, end: newEnd, text: segment.text)
            snapped.append(kept)
            changes.append(
                SubtitleSpeechSnapChange(
                    segmentId: segment.id,
                    text: segment.text,
                    oldStartSec: oldStart,
                    oldEndSec: oldEnd,
                    newStartSec: kept.start,
                    newEndSec: kept.end,
                    status: overlaps.isEmpty ? "kept_no_speech" : (kept.changed(from: oldStart, oldEnd) ? "snapped" : "unchanged")
                )
            )
        }

        snapped = resolveOverlapsPreservingAll(snapped, clipDurationSec: clipDurationSec)

        return SubtitleSpeechSnapResult(
            segments: snapped,
            changes: changes,
            speechRegions: speech,
            preservedAllText: true
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

    /// Merge neighboring islands until count ≤ targetCount (preserves total coverage).
    private static func mergeToCount(
        _ islands: [SpeechTimeRegion],
        targetCount: Int
    ) -> [SpeechTimeRegion] {
        guard targetCount > 0, islands.count > targetCount else { return islands }
        var current = islands
        while current.count > targetCount {
            // Merge the pair with the smallest gap.
            var bestIndex = 0
            var bestGap = Double.greatestFiniteMagnitude
            for i in 0..<(current.count - 1) {
                let gap = current[i + 1].startSec - current[i].endSec
                if gap < bestGap {
                    bestGap = gap
                    bestIndex = i
                }
            }
            let merged = SpeechTimeRegion(
                startSec: current[bestIndex].startSec,
                endSec: current[bestIndex + 1].endSec
            )
            current.replaceSubrange(bestIndex...(bestIndex + 1), with: [merged])
        }
        return current
    }

    private static func tokenizeWords(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        tokenizeWords(text).joined(separator: " ")
    }

    /// Splits words across pieces; **every word appears exactly once** in order.
    private static func distributeTextPreservingAllWords(_ text: String, across count: Int) -> [String] {
        let words = tokenizeWords(text)
        guard count > 1 else { return [words.joined(separator: " ")] }
        guard !words.isEmpty else { return Array(repeating: "", count: count) }

        let pieceCount = min(count, words.count)
        // If caller asked for more pieces than words, they should have merged islands already.
        // Still safe: put one word per first N pieces.
        let base = words.count / pieceCount
        let remainder = words.count % pieceCount
        var pieces: [String] = []
        var cursor = 0
        for index in 0..<pieceCount {
            let take = base + (index < remainder ? 1 : 0)
            let slice = words[cursor..<(cursor + take)]
            pieces.append(slice.joined(separator: " "))
            cursor += take
        }
        // Pad if count > pieceCount (should not happen after mergeToCount).
        while pieces.count < count {
            pieces.append("")
        }
        return pieces
    }

    private static func makeSegment(id: String, start: Double, end: Double, text: String) -> AlignedSubtitleSegment {
        let safeEnd = max(start + 0.05, end)
        let base = AlignedSubtitleSegment(id: id, start: start, end: safeEnd, text: text)
        return AlignedSubtitleSegment(
            id: base.id,
            start: base.start,
            end: base.end,
            text: base.text,
            words: ShortsVisualEditorStateBuilder.inferredWords(for: base)
        )
    }

    /// Resolves overlaps **without dropping any segment**.
    private static func resolveOverlapsPreservingAll(
        _ segments: [AlignedSubtitleSegment],
        clipDurationSec: Double
    ) -> [AlignedSubtitleSegment] {
        let ordered = segments.sorted { $0.start < $1.start }
        guard !ordered.isEmpty else { return [] }

        var starts = ordered.map { max(0, min(clipDurationSec, $0.start)) }
        var ends = ordered.map { max(0, min(clipDurationSec, $0.end)) }

        for i in 0..<ordered.count {
            if ends[i] <= starts[i] {
                ends[i] = min(clipDurationSec, starts[i] + minSegmentDurationSec)
            }
        }

        for i in 1..<ordered.count {
            if starts[i] < ends[i - 1] {
                // Prefer a small gap rather than deleting either cue.
                let gapPoint = (ends[i - 1] + starts[i]) / 2
                ends[i - 1] = max(starts[i - 1] + 0.05, gapPoint - 0.02)
                starts[i] = min(ends[i] - 0.05, gapPoint + 0.02)
                if starts[i] >= ends[i] {
                    ends[i] = min(clipDurationSec, starts[i] + minSegmentDurationSec)
                }
                if ends[i - 1] <= starts[i - 1] {
                    ends[i - 1] = starts[i - 1] + 0.05
                }
            }
        }

        return ordered.indices.map { i in
            makeSegment(id: ordered[i].id, start: starts[i], end: ends[i], text: ordered[i].text)
        }
    }
}

private extension AlignedSubtitleSegment {
    func changed(from oldStart: Double, _ oldEnd: Double) -> Bool {
        abs(start - oldStart) > 0.001 || abs(end - oldEnd) > 0.001
    }
}
