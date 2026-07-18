import Foundation

public struct AudioEnergyWindow: Equatable, Sendable {
    public var posMs: Int
    public var dbfs: Double

    public init(posMs: Int, dbfs: Double) {
        self.posMs = posMs
        self.dbfs = dbfs
    }
}

public enum SmartSlicePlanner {
    public static let energyWindowMs = 20
    private static let searchRadiusFraction = 0.5
    private static let digitalSilenceDbfs = -119.0

    public static func computeEnergyProfile(
        pcm: [Int16],
        sampleRate: Int
    ) -> [AudioEnergyWindow] {
        guard sampleRate > 0 else { return [] }
        let windowSamples = max(1, Int((Double(energyWindowMs) / 1_000) * Double(sampleRate)))
        guard pcm.count >= windowSamples else { return [] }

        var profile: [AudioEnergyWindow] = []
        var index = 0
        while index + windowSamples <= pcm.count {
            var sumSquares = 0.0
            for sample in pcm[index..<(index + windowSamples)] {
                let value = Double(sample)
                sumSquares += value * value
            }

            let rms = sqrt(sumSquares / Double(windowSamples))
            let posMs = Int((Double(index) / Double(sampleRate)) * 1_000)
            profile.append(AudioEnergyWindow(posMs: posMs, dbfs: dbfsFromInt16RMS(rms)))
            index += windowSamples
        }
        return profile
    }

    public static func computeCutPoints(
        pcm: [Int16],
        sampleRate: Int,
        targetMs: Int,
        threshDb: Double,
        minSilenceMs: Int
    ) -> [Int] {
        guard sampleRate > 0 else { return [] }
        let totalMs = Int((Double(pcm.count) / Double(sampleRate)) * 1_000)
        return computeCutPoints(
            profile: computeEnergyProfile(pcm: pcm, sampleRate: sampleRate),
            totalDurationMs: totalMs,
            targetMs: targetMs,
            threshDb: threshDb,
            minSilenceMs: minSilenceMs
        )
    }

    public static func computeCutPoints(
        profile: [AudioEnergyWindow],
        totalDurationMs: Int,
        targetMs: Int,
        threshDb: Double,
        minSilenceMs: Int
    ) -> [Int] {
        guard totalDurationMs > targetMs, targetMs > 0, !profile.isEmpty else { return [] }

        let regions = findSilenceRegions(
            profile: profile,
            thresholdDb: threshDb,
            minSilenceMs: minSilenceMs
        )
        guard !regions.isEmpty else { return [] }

        let radius = Int(Double(targetMs) * searchRadiusFraction)
        var cuts: [Int] = []
        var cursor = 0

        while cursor + targetMs < totalDurationMs {
            let ideal = cursor + targetMs
            let lo = max(cursor + 1, ideal - radius)
            let hi = min(totalDurationMs - 1, ideal + radius)
            let remaining = regions.filter { $0.startMs > cursor }
            guard !remaining.isEmpty else { break }

            let nearby = remaining.filter { $0.startMs <= hi && $0.endMs >= lo }
            let pool = nearby.isEmpty ? remaining : nearby
            guard let best = pool.min(by: {
                distanceToRegion($0, targetMs: ideal) < distanceToRegion($1, targetMs: ideal)
            }) else { break }

            let cut = (best.startMs + best.endMs) / 2
            guard cut > cursor else { break }
            cuts.append(cut)
            cursor = cut

            if Double(totalDurationMs - cursor) < Double(targetMs) * 0.25 {
                break
            }
        }

        return cuts
    }

    public static func cutPointsToSeconds(_ cutPointsMs: [Int]) -> [Double] {
        cutPointsMs.map { Double($0) / 1_000 }
    }

    /// Silence intervals in the energy profile (milliseconds, same timeline as `posMs`).
    public static func silenceRegions(
        profile: [AudioEnergyWindow],
        thresholdDb: Double,
        minSilenceMs: Int
    ) -> [(startMs: Int, endMs: Int)] {
        findSilenceRegions(profile: profile, thresholdDb: thresholdDb, minSilenceMs: minSilenceMs)
            .map { (startMs: $0.startMs, endMs: $0.endMs) }
    }

    /// Speech intervals complementary to silence within `[0, totalDurationMs]`.
    public static func speechRegions(
        profile: [AudioEnergyWindow],
        totalDurationMs: Int,
        thresholdDb: Double,
        minSilenceMs: Int
    ) -> [(startMs: Int, endMs: Int)] {
        guard totalDurationMs > 0 else { return [] }
        let silence = findSilenceRegions(
            profile: profile,
            thresholdDb: thresholdDb,
            minSilenceMs: minSilenceMs
        ).sorted { $0.startMs < $1.startMs }

        var speech: [(startMs: Int, endMs: Int)] = []
        var cursor = 0
        for region in silence {
            let start = max(0, region.startMs)
            let end = min(totalDurationMs, region.endMs)
            if start > cursor {
                speech.append((startMs: cursor, endMs: start))
            }
            cursor = max(cursor, end)
        }
        if cursor < totalDurationMs {
            speech.append((startMs: cursor, endMs: totalDurationMs))
        }
        return speech.filter { $0.endMs > $0.startMs }
    }

    private struct SilenceRegion {
        var startMs: Int
        var endMs: Int
    }

    private static func dbfsFromInt16RMS(_ rms: Double) -> Double {
        guard rms > 0 else { return digitalSilenceDbfs }
        return 20 * log10(rms / 32_768)
    }

    private static func findSilenceRegions(
        profile: [AudioEnergyWindow],
        thresholdDb: Double,
        minSilenceMs: Int
    ) -> [SilenceRegion] {
        let minWindows = max(1, Int(ceil(Double(minSilenceMs) / Double(energyWindowMs))))
        var regions: [SilenceRegion] = []
        var runStart: Int?

        for index in profile.indices {
            let silent = profile[index].dbfs <= thresholdDb
            if silent, runStart == nil {
                runStart = index
                continue
            }
            if !silent, let start = runStart {
                let runLength = index - start
                if runLength >= minWindows {
                    regions.append(SilenceRegion(
                        startMs: profile[start].posMs,
                        endMs: profile[index - 1].posMs + energyWindowMs
                    ))
                }
                runStart = nil
            }
        }

        if let start = runStart {
            let runLength = profile.count - start
            if runLength >= minWindows {
                regions.append(SilenceRegion(
                    startMs: profile[start].posMs,
                    endMs: profile[profile.count - 1].posMs + energyWindowMs
                ))
            }
        }

        return regions
    }

    private static func distanceToRegion(_ region: SilenceRegion, targetMs: Int) -> Int {
        if targetMs >= region.startMs, targetMs <= region.endMs {
            return 0
        }
        return targetMs < region.startMs ? region.startMs - targetMs : targetMs - region.endMs
    }
}
