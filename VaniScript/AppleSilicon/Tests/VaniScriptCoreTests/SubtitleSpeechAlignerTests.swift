import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Subtitle speech alignment")
struct SubtitleSpeechAlignerTests {
    @Test("derives speech regions by inverting silence")
    func derivesSpeechRegions() {
        // 0-200ms speech, 200-600ms silence, 600-1000ms speech
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
        // Speech 0-0.4s and 0.7-1.0s; silence 0.4-0.7s
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
        #expect(result.segments[0].id == "a")
        #expect(result.segments[0].end <= 0.41)
        #expect(result.segments[1].start >= 0.69)
        #expect(result.changes.filter { $0.status == "snapped" }.count == 2)
        // Gap remains between cues across the pause.
        #expect(result.segments[0].end < result.segments[1].start)
    }

    @Test("keeps segment when no speech overlaps its range")
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
        #expect(result.changes.first?.status == "no_speech_in_range")
        #expect(abs(result.segments[0].start - 0.5) < 0.001)
    }
}
