import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Subtitle speech alignment")
struct SubtitleSpeechAlignerTests {
    @Test("derives speech regions by inverting silence")
    func derivesSpeechRegions() {
        var samples = [Int16](repeating: 12_000, count: 1_000)
        for i in 200..<600 { samples[i] = 0 }

        let profile = SmartSlicePlanner.computeEnergyProfile(pcm: samples, sampleRate: 1_000)
        let speech = SubtitleSpeechAligner.speechRegions(
            profile: profile,
            clipDurationSec: 1.0,
            thresholdDb: -50,
            minSilenceMs: 80
        )

        #expect(speech.count >= 2)
        #expect(speech[0].startSec == 0)
        #expect(speech[0].endSec <= 0.25)
        #expect(speech.last!.endSec >= 0.95)
    }

    @Test("shrinks continuous segments so pauses stay caption-free")
    func shrinksContinuousSegments() {
        let speech = [
            SpeechTimeRegion(startSec: 0.0, endSec: 0.4),
            SpeechTimeRegion(startSec: 0.7, endSec: 1.0),
        ]
        let segments = [
            AlignedSubtitleSegment(id: "a", start: 0.0, end: 0.5, text: "hello"),
            AlignedSubtitleSegment(id: "b", start: 0.5, end: 1.0, text: "world"),
        ]

        let result = SubtitleSpeechAligner.snapSegmentsToSpeech(
            segments: segments,
            speechRegions: speech,
            clipDurationSec: 1.0,
            padSec: 0.0
        )

        #expect(result.segments.count == 2)
        #expect(result.preservedAllText)
        #expect(joinedText(result.segments) == "hello world")
        #expect(result.segments[0].end < result.segments[1].start)
    }

    @Test("splits one long cue but keeps every word")
    func splitsInternalPausePreservingWords() {
        let speech = [
            SpeechTimeRegion(startSec: 0.0, endSec: 0.4),
            SpeechTimeRegion(startSec: 0.7, endSec: 1.0),
        ]
        let segments = [
            AlignedSubtitleSegment(id: "long", start: 0.0, end: 1.0, text: "hello beautiful world today"),
        ]

        let result = SubtitleSpeechAligner.snapSegmentsToSpeech(
            segments: segments,
            speechRegions: speech,
            clipDurationSec: 1.0,
            padSec: 0.0,
            splitSilenceSec: 0.2
        )

        #expect(result.segments.count == 2)
        #expect(result.preservedAllText)
        #expect(joinedText(result.segments) == "hello beautiful world today")
        #expect(result.segments[0].end < result.segments[1].start)
        #expect(!result.segments.contains { $0.text == "…" })
    }

    @Test("never deletes a segment when no speech overlaps")
    func keepsSegmentWithoutSpeech() {
        let speech = [SpeechTimeRegion(startSec: 0.0, endSec: 0.2)]
        let segments = [
            AlignedSubtitleSegment(id: "quiet", start: 0.5, end: 0.9, text: "only silence here"),
        ]
        let result = SubtitleSpeechAligner.snapSegmentsToSpeech(
            segments: segments,
            speechRegions: speech,
            clipDurationSec: 1.0,
            padSec: 0.0
        )
        #expect(result.segments.count == 1)
        #expect(result.preservedAllText)
        #expect(result.segments[0].text == "only silence here")
        #expect(result.changes.first?.status == "kept_no_speech")
    }

    @Test("single-word cue is never split away into ellipsis")
    func singleWordNeverSplitToEllipsis() {
        let speech = [
            SpeechTimeRegion(startSec: 0.0, endSec: 0.3),
            SpeechTimeRegion(startSec: 0.6, endSec: 1.0),
        ]
        let segments = [
            AlignedSubtitleSegment(id: "one", start: 0.0, end: 1.0, text: "Om"),
        ]
        let result = SubtitleSpeechAligner.snapSegmentsToSpeech(
            segments: segments,
            speechRegions: speech,
            clipDurationSec: 1.0,
            padSec: 0.0,
            splitSilenceSec: 0.2
        )
        #expect(result.segments.count == 1)
        #expect(result.segments[0].text == "Om")
        #expect(result.preservedAllText)
    }

    @Test("dense overlapping snaps still keep all captions")
    func overlapResolutionNeverDrops() {
        let speech = [SpeechTimeRegion(startSec: 0.0, endSec: 1.0)]
        let segments = [
            AlignedSubtitleSegment(id: "a", start: 0.0, end: 0.5, text: "one two"),
            AlignedSubtitleSegment(id: "b", start: 0.1, end: 0.6, text: "three four"),
            AlignedSubtitleSegment(id: "c", start: 0.2, end: 0.7, text: "five six"),
        ]
        let result = SubtitleSpeechAligner.snapSegmentsToSpeech(
            segments: segments,
            speechRegions: speech,
            clipDurationSec: 1.0,
            padSec: 0.0
        )
        #expect(result.segments.count == 3)
        #expect(result.preservedAllText)
        #expect(joinedText(result.segments) == "one two three four five six")
    }

    private func joinedText(_ segments: [AlignedSubtitleSegment]) -> String {
        segments
            .map(\.text)
            .flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .joined(separator: " ")
    }
}
