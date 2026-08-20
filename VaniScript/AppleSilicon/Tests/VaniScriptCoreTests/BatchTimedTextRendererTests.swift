import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Batch timed TXT renderer")
struct BatchTimedTextRendererTests {
    @Test("renders deterministic millisecond blocks and one final newline")
    func deterministicRendering() throws {
        let cues = [
            TranscriptCue(startSec: 0, endSec: 1.2344, text: "First"),
            TranscriptCue(startSec: 3_661.9996, endSec: 3_662, text: "Second")
        ]

        let rendered = try BatchTimedTextRenderer.render(duration: 4_000, cues: cues)

        #expect(rendered == "[00:00:00.000 - 00:00:01.234] First\n\n[01:01:02.000 - 01:01:02.000] Second\n")
        #expect(rendered.hasSuffix("\n"))
        #expect(!rendered.hasSuffix("\n\n"))
    }

    @Test("accepts zero-length cues at duration boundaries")
    func boundaryCues() throws {
        let cues = [
            TranscriptCue(startSec: 0, endSec: 0, text: "Start"),
            TranscriptCue(startSec: 10, endSec: 10, text: "End")
        ]
        #expect(BatchTimedTextRenderer.validate(duration: 10, cues: cues).isValid)
        #expect(try BatchTimedTextRenderer.render(duration: 10, cues: cues).contains("[00:00:10.000 - 00:00:10.000] End"))
    }

    @Test("empty cue collection renders an empty file")
    func emptyTranscript() throws {
        #expect(try BatchTimedTextRenderer.render(duration: 0, cues: []) == "")
    }

    @Test("rejects non-finite and negative duration", arguments: [Double.nan, .infinity, -.infinity, -0.001])
    func invalidDuration(duration: Double) {
        let result = BatchTimedTextRenderer.validate(duration: duration, cues: [])
        #expect(result.violations == [.invalidDuration])
    }

    @Test("rejects non-finite cue times")
    func nonFiniteCue() {
        let cues = [TranscriptCue(startSec: .nan, endSec: 1, text: "Text")]
        #expect(BatchTimedTextRenderer.validate(duration: 2, cues: cues).violations == [.nonFiniteTime(cueIndex: 0)])
    }

    @Test("rejects negative and reversed ranges")
    func invalidRanges() {
        let cues = [
            TranscriptCue(startSec: -1, endSec: 0, text: "Negative"),
            TranscriptCue(startSec: 2, endSec: 1, text: "Reversed")
        ]
        let violations = BatchTimedTextRenderer.validate(duration: 3, cues: cues).violations
        #expect(violations.contains(.invalidRange(cueIndex: 0)))
        #expect(violations.contains(.invalidRange(cueIndex: 1)))
    }

    @Test("rejects cue end beyond duration")
    func outsideDuration() {
        let cues = [TranscriptCue(startSec: 0, endSec: 1.001, text: "Late")]
        #expect(BatchTimedTextRenderer.validate(duration: 1, cues: cues).violations == [.outsideDuration(cueIndex: 0)])
    }

    @Test("rejects non-monotonic cue ordering")
    func nonMonotonic() {
        let cues = [
            TranscriptCue(startSec: 2, endSec: 4, text: "Later"),
            TranscriptCue(startSec: 1, endSec: 3, text: "Earlier")
        ]
        #expect(BatchTimedTextRenderer.validate(duration: 5, cues: cues).violations.contains(.nonMonotonic(cueIndex: 1)))
    }

    @Test("rejects whitespace-only cue text")
    func emptyText() {
        let cues = [TranscriptCue(startSec: 0, endSec: 1, text: " \n\t")]
        #expect(BatchTimedTextRenderer.validate(duration: 1, cues: cues).violations == [.emptyText(cueIndex: 0)])
    }

    @Test("render throws all typed validation violations")
    func renderFailure() {
        let cues = [TranscriptCue(startSec: -1, endSec: 2, text: "")]
        #expect(throws: BatchTimedTextRendererError.invalidTranscript([
            .invalidRange(cueIndex: 0),
            .outsideDuration(cueIndex: 0),
            .emptyText(cueIndex: 0)
        ])) {
            try BatchTimedTextRenderer.render(duration: 1, cues: cues)
        }
    }
}
