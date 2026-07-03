import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Audio spectrum analyzer")
struct AudioSpectrumAnalyzerTests {
    @Test("silence resolves to the visual floor")
    func silenceResolvesToVisualFloor() {
        let levels = AudioSpectrumAnalyzer.frequencyBands(
            samples: Array(repeating: 0, count: 1_024),
            sampleRate: 48_000,
            bandCount: 36
        )

        #expect(levels.count == 36)
        #expect(levels.allSatisfy { abs($0 - AudioSpectrumAnalyzer.visualFloor) < 0.0001 })
    }

    @Test("single tone produces a non-flat frequency response")
    func singleToneProducesNonFlatFrequencyResponse() {
        let sampleRate = 48_000.0
        let frequency = 440.0
        let samples = (0..<2_048).map { index in
            Float(sin((Double(index) / sampleRate) * frequency * 2 * Double.pi))
        }

        let levels = AudioSpectrumAnalyzer.frequencyBands(
            samples: samples,
            sampleRate: sampleRate,
            bandCount: 36
        )

        let peak = levels.max() ?? 0
        let floor = levels.min() ?? 0
        let peakIndex = levels.firstIndex(of: peak) ?? 0

        #expect(levels.count == 36)
        #expect(peak > 0.70)
        #expect(floor < 0.20)
        #expect(peak - floor > 0.55)
        #expect(peakIndex > 4 && peakIndex < 18)
    }
}
