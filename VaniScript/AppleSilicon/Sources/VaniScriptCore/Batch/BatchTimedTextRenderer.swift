import Foundation

public enum BatchTimedTextRenderer {
    public static func validate(
        duration: Double,
        cues: [TranscriptCue]
    ) -> BatchCueValidationResult {
        var violations: [BatchCueViolation] = []
        guard duration.isFinite, duration >= 0 else {
            return BatchCueValidationResult(violations: [.invalidDuration])
        }

        var previousStart = -Double.infinity
        var previousEnd = -Double.infinity
        for (index, cue) in cues.enumerated() {
            if !cue.startSec.isFinite || !cue.endSec.isFinite {
                violations.append(.nonFiniteTime(cueIndex: index))
            } else {
                if cue.startSec < 0 || cue.startSec > cue.endSec {
                    violations.append(.invalidRange(cueIndex: index))
                }
                if cue.endSec > duration {
                    violations.append(.outsideDuration(cueIndex: index))
                }
                if cue.startSec < previousStart || cue.endSec < previousEnd {
                    violations.append(.nonMonotonic(cueIndex: index))
                }
                previousStart = cue.startSec
                previousEnd = cue.endSec
            }
            if cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                violations.append(.emptyText(cueIndex: index))
            }
        }
        return BatchCueValidationResult(violations: violations)
    }

    public static func render(
        duration: Double,
        cues: [TranscriptCue]
    ) throws -> String {
        let validation = validate(duration: duration, cues: cues)
        guard validation.isValid else {
            throw BatchTimedTextRendererError.invalidTranscript(validation.violations)
        }
        guard !cues.isEmpty else { return "" }

        return cues.map { cue in
            "[\(timestamp(cue.startSec)) - \(timestamp(cue.endSec))] \(cue.text)"
        }.joined(separator: "\n\n") + "\n"
    }

    private static func timestamp(_ seconds: Double) -> String {
        let milliseconds = Int64((seconds * 1_000).rounded())
        let hours = milliseconds / 3_600_000
        let minutes = milliseconds / 60_000 % 60
        let wholeSeconds = milliseconds / 1_000 % 60
        let remainder = milliseconds % 1_000
        return String(format: "%02lld:%02lld:%02lld.%03lld", hours, minutes, wholeSeconds, remainder)
    }
}
