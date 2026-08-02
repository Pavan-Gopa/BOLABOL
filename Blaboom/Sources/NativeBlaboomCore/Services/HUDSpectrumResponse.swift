import Foundation

/// Maps the recorder's full spectrum into the compact classic HUD without losing
/// quiet speech that falls between its small number of visible bars.
public enum HUDSpectrumResponse {
    public static func classicListeningValues(
        bands: [Float],
        barCount: Int,
        noiseFloor: Float = 0.10
    ) -> [Float] {
        guard barCount > 0 else { return [] }

        let floor = min(1, max(0, noiseFloor))
        let sanitized = bands.map { value in
            value.isFinite ? min(1, max(0, value)) : 0
        }
        guard !sanitized.isEmpty else {
            return Array(repeating: floor, count: barCount)
        }

        let peak = sanitized.max() ?? 0
        guard peak >= 0.035 else {
            return idleValues(count: barCount, noiseFloor: floor)
        }

        // Separate each bar's response to its local frequency bucket.
        // Quiet sounds sit low (~0.15-0.35) while peaks reach high (0.8-1.0),
        // preventing all bars from inflating simultaneously to maximum height.
        let buckets = peakWeightedBuckets(sanitized, count: barCount)
        let globalInput = min(1, max(0, (peak - 0.020) / 0.25))
        let globalPresence = shaped(globalInput, exponent: 0.85)

        return buckets.enumerated().map { index, value in
            let progress = Float(index) / Float(max(1, barCount - 1))
            let highGain = 1.0 + 0.75 * progress
            let localInput = min(1, max(0, (value * highGain - 0.012) / 0.16))
            let localResponse = shaped(localInput, exponent: 0.92)
            let voicePresence = 0.28 * sin(progress * .pi)
            let combined = max(localResponse, globalPresence * voicePresence)
            let responsive = min(1, max(floor, combined))
            return responsive
        }
    }

    private static func idleValues(
        count: Int,
        noiseFloor: Float
    ) -> [Float] {
        (0..<count).map { index in
            let progress = Float(index) / Float(max(1, count - 1))
            return min(1, noiseFloor + 0.025 * (0.5 + 0.5 * sin(progress * .pi)))
        }
    }

    /// Each visible bar consumes a complete slice of the input spectrum.
    /// A peak/RMS blend keeps brief consonants visible without turning steady
    /// microphone noise into a permanently raised wall.
    private static func peakWeightedBuckets(
        _ bands: [Float],
        count: Int
    ) -> [Float] {
        (0..<count).map { index in
            let start = min(
                bands.count - 1,
                Int(floor(Double(index) * Double(bands.count) / Double(count)))
            )
            let exclusiveEnd = min(
                bands.count,
                max(
                    start + 1,
                    Int(ceil(Double(index + 1) * Double(bands.count) / Double(count)))
                )
            )
            let bucket = bands[start..<exclusiveEnd]
            let peak = bucket.max() ?? 0
            let squareMean =
                bucket.reduce(Float(0)) { partial, value in
                    partial + value * value
                }
                / Float(max(1, bucket.count))
            let rootMeanSquare = sqrt(squareMean)
            return min(1, peak * 0.72 + rootMeanSquare * 0.28)
        }
    }

    private static func shaped(
        _ value: Float,
        exponent: Float
    ) -> Float {
        Float(pow(Double(min(1, max(0, value))), Double(exponent)))
    }
}
