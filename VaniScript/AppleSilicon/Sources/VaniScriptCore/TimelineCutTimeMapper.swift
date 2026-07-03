import Foundation

public enum TimelineCutTimeMapper {
    public static func activeOutputDuration(
        clipDuration: Double,
        trim: TimelineTrim,
        cuts: [TimelineCut]
    ) -> Double {
        let window = activeWindow(clipDuration: clipDuration, trim: trim)
        guard window.end > window.start else { return 0 }
        let removed = normalizedCuts(cuts, clipDuration: clipDuration, trim: trim)
            .reduce(0.0) { $0 + max(0, $1.endSec - $1.startSec) }
        return max(0, (window.end - window.start) - removed)
    }

    public static func virtualDuration(
        clipDuration: Double,
        trim: TimelineTrim,
        cuts: [TimelineCut],
        introDuration: Double,
        outroDuration: Double
    ) -> Double {
        let window = activeWindow(clipDuration: clipDuration, trim: trim)
        return window.start
            + max(0, introDuration)
            + activeOutputDuration(clipDuration: clipDuration, trim: trim, cuts: cuts)
            + max(0, outroDuration)
            + max(0, clipDuration - window.end)
    }

    public static func mapVirtualToPhysical(
        virtualSec: Double,
        clipDuration: Double,
        trim: TimelineTrim,
        cuts: [TimelineCut],
        introDuration: Double,
        outroDuration: Double
    ) -> Double {
        let window = activeWindow(clipDuration: clipDuration, trim: trim)
        let intro = max(0, introDuration)
        let activeDuration = activeOutputDuration(clipDuration: clipDuration, trim: trim, cuts: cuts)
        let activeStartVirtual = window.start + intro
        let activeEndWithTrimVirtual = activeStartVirtual + activeDuration
        let outroEndVirtual = activeEndWithTrimVirtual + max(0, outroDuration)
        let safeVirtual = clamp(virtualSec, min: 0, max: virtualDuration(
            clipDuration: clipDuration,
            trim: trim,
            cuts: cuts,
            introDuration: introDuration,
            outroDuration: outroDuration
        ))

        if safeVirtual < window.start {
            return safeVirtual
        }
        if safeVirtual < activeStartVirtual {
            return window.start
        }
        if safeVirtual >= activeEndWithTrimVirtual && safeVirtual < outroEndVirtual {
            return window.end
        }
        if safeVirtual >= outroEndVirtual {
            return clamp(window.end + (safeVirtual - outroEndVirtual), min: window.start, max: max(window.end, clipDuration))
        }

        let activeElapsed = safeVirtual - activeStartVirtual
        return physicalForOutputElapsed(
            activeElapsed,
            clipDuration: clipDuration,
            trim: trim,
            cuts: cuts
        )
    }

    public static func mapPhysicalToVirtual(
        physicalSec: Double,
        clipDuration: Double,
        trim: TimelineTrim,
        cuts: [TimelineCut],
        introDuration: Double,
        outroDuration: Double
    ) -> Double {
        let window = activeWindow(clipDuration: clipDuration, trim: trim)
        if physicalSec < window.start {
            return clamp(physicalSec, min: 0, max: window.start)
        }
        if physicalSec > window.end {
            let activeDuration = activeOutputDuration(clipDuration: clipDuration, trim: trim, cuts: cuts)
            let outroEndVirtual = window.start + max(0, introDuration) + activeDuration + max(0, outroDuration)
            return clamp(outroEndVirtual + (physicalSec - window.end), min: 0, max: virtualDuration(
                clipDuration: clipDuration,
                trim: trim,
                cuts: cuts,
                introDuration: introDuration,
                outroDuration: outroDuration
            ))
        }
        let physical = clamp(physicalSec, min: window.start, max: window.end)
        let activeElapsed = outputElapsedForPhysical(
            physical,
            clipDuration: clipDuration,
            trim: trim,
            cuts: cuts
        )
        let intro = window.start + max(0, introDuration)
        let duration = virtualDuration(
            clipDuration: clipDuration,
            trim: trim,
            cuts: cuts,
            introDuration: introDuration,
            outroDuration: outroDuration
        )
        return clamp(intro + activeElapsed, min: 0, max: duration)
    }

    public static func normalizedCuts(
        _ cuts: [TimelineCut],
        clipDuration: Double,
        trim: TimelineTrim
    ) -> [TimelineCut] {
        let window = activeWindow(clipDuration: clipDuration, trim: trim)
        guard window.end > window.start else { return [] }

        let sorted = cuts
            .map {
                TimelineCut(
                    startSec: clamp($0.startSec, min: window.start, max: window.end),
                    endSec: clamp($0.endSec, min: window.start, max: window.end)
                )
            }
            .filter { $0.endSec > $0.startSec + 0.01 }
            .sorted { $0.startSec < $1.startSec }

        var merged: [TimelineCut] = []
        for cut in sorted {
            if let last = merged.last, cut.startSec <= last.endSec + 0.01 {
                merged[merged.count - 1].endSec = max(last.endSec, cut.endSec)
            } else {
                merged.append(cut)
            }
        }
        return merged
    }

    public static func incrementalCutFragments(
        existingCuts: [TimelineCut],
        newCut: TimelineCut,
        clipDuration: Double
    ) -> [TimelineCut] {
        guard let cut = normalizedCuts([newCut], clipDuration: clipDuration, trim: .zero).first else {
            return []
        }

        let existing = normalizedCuts(existingCuts, clipDuration: clipDuration, trim: .zero)
        var fragments: [TimelineCut] = []
        var cursor = cut.startSec

        for covered in existing {
            guard covered.endSec > cursor else { continue }
            guard covered.startSec < cut.endSec else { break }

            let fragmentEnd = min(covered.startSec, cut.endSec)
            if fragmentEnd > cursor + 0.01 {
                fragments.append(TimelineCut(startSec: cursor, endSec: fragmentEnd))
            }

            cursor = max(cursor, covered.endSec)
            if cursor >= cut.endSec { break }
        }

        if cursor < cut.endSec - 0.01 {
            fragments.append(TimelineCut(startSec: cursor, endSec: cut.endSec))
        }

        return fragments
    }

    private static func physicalForOutputElapsed(
        _ elapsed: Double,
        clipDuration: Double,
        trim: TimelineTrim,
        cuts: [TimelineCut]
    ) -> Double {
        let window = activeWindow(clipDuration: clipDuration, trim: trim)
        var cursor = window.start
        var outputCursor = 0.0
        let target = max(0, elapsed)

        for cut in normalizedCuts(cuts, clipDuration: clipDuration, trim: trim) {
            let keptDuration = max(0, cut.startSec - cursor)
            if keptDuration > 0, target <= outputCursor + keptDuration {
                return clamp(cursor + (target - outputCursor), min: window.start, max: window.end)
            }
            outputCursor += keptDuration
            cursor = max(cursor, cut.endSec)
        }

        return clamp(cursor + (target - outputCursor), min: window.start, max: window.end)
    }

    private static func outputElapsedForPhysical(
        _ physicalSec: Double,
        clipDuration: Double,
        trim: TimelineTrim,
        cuts: [TimelineCut]
    ) -> Double {
        let window = activeWindow(clipDuration: clipDuration, trim: trim)
        let physical = clamp(physicalSec, min: window.start, max: window.end)
        var cursor = window.start
        var outputCursor = 0.0

        for cut in normalizedCuts(cuts, clipDuration: clipDuration, trim: trim) {
            if physical < cut.startSec {
                return outputCursor + max(0, physical - cursor)
            }
            outputCursor += max(0, cut.startSec - cursor)
            if physical <= cut.endSec {
                return outputCursor
            }
            cursor = max(cursor, cut.endSec)
        }

        return outputCursor + max(0, physical - cursor)
    }

    private static func activeWindow(clipDuration: Double, trim: TimelineTrim) -> (start: Double, end: Double) {
        let duration = max(0, clipDuration)
        let start = clamp(trim.trimStartSec, min: 0, max: duration)
        let trimEnd = clamp(trim.trimEndSec, min: 0, max: max(0, duration - start))
        return (start, max(start, duration - trimEnd))
    }

    private static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        guard value.isFinite else { return lower }
        return Swift.min(Swift.max(value, lower), upper)
    }
}
