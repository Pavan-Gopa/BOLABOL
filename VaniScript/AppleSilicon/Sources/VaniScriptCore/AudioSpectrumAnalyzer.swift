import Foundation

public enum AudioSpectrumAnalyzer {
    public static let defaultBandCount = 36
    public static let visualFloor = 0.08
    public static let silenceLevels = Array(repeating: visualFloor, count: defaultBandCount)

    public static func frequencyBands(
        samples: [Float],
        sampleRate: Double,
        bandCount: Int = defaultBandCount
    ) -> [Double] {
        guard bandCount > 0 else { return [] }
        guard sampleRate.isFinite, sampleRate > 0 else {
            return Array(repeating: visualFloor, count: bandCount)
        }

        let finiteSamples = samples.filter { $0.isFinite }
        guard finiteSamples.count >= 64 else {
            return Array(repeating: visualFloor, count: bandCount)
        }

        let windowSize = min(2_048, finiteSamples.count)
        let window = Array(finiteSamples.suffix(windowSize))
        let rms = sqrt(window.reduce(0) { $0 + Double($1 * $1) } / Double(windowSize))
        guard rms > 0.000_01 else {
            return Array(repeating: visualFloor, count: bandCount)
        }

        let nyquist = sampleRate / 2
        let minFrequency = min(60.0, nyquist * 0.5)
        let maxFrequency = max(minFrequency * 1.5, min(12_000, nyquist * 0.92))
        let ratio = maxFrequency / minFrequency

        let magnitudes = (0..<bandCount).map { index in
            let position = bandCount == 1 ? 0 : Double(index) / Double(bandCount - 1)
            let center = minFrequency * pow(ratio, position)
            return goertzelMagnitude(samples: window, sampleRate: sampleRate, frequency: center)
        }

        guard let maxMagnitude = magnitudes.max(), maxMagnitude > 0.000_000_1 else {
            return Array(repeating: visualFloor, count: bandCount)
        }

        return magnitudes.map { magnitude in
            let relative = max(0, min(1, magnitude / maxMagnitude))
            let shaped = pow(relative, 0.72)
            let level = visualFloor + (1 - visualFloor) * shaped
            return max(visualFloor, min(1, level))
        }
    }

    private static func goertzelMagnitude(samples: [Float], sampleRate: Double, frequency: Double) -> Double {
        guard frequency > 0, frequency < sampleRate / 2 else { return 0 }

        let count = samples.count
        let omega = 2 * Double.pi * frequency / sampleRate
        let coefficient = 2 * cos(omega)
        var previous = 0.0
        var previous2 = 0.0

        for index in 0..<count {
            let sample = Double(samples[index]) * hannWindow(index: index, count: count)
            let current = sample + coefficient * previous - previous2
            previous2 = previous
            previous = current
        }

        let power = previous2 * previous2 + previous * previous - coefficient * previous * previous2
        return sqrt(max(0, power)) / Double(count)
    }

    private static func hannWindow(index: Int, count: Int) -> Double {
        guard count > 1 else { return 1 }
        return 0.5 - 0.5 * cos((2 * Double.pi * Double(index)) / Double(count - 1))
    }
}
