import NativeBolabolCore
import Testing

@Test
func classicHUDRespondsToQuietSpeechAcrossUnsampledFrequencyBins() {
    var bands = Array(repeating: Float(0.02), count: 40)
    bands[7] = 0.055
    bands[24] = 0.046

    let values = HUDSpectrumResponse.classicListeningValues(
        bands: bands,
        barCount: 3
    )

    #expect(values.count == 3)
    #expect(values.max() ?? 0 > 0.20)
    #expect(values.allSatisfy { $0 >= 0.10 })
}

@Test
func classicHUDKeepsTrueSilenceNearItsRestingFloor() {
    let values = HUDSpectrumResponse.classicListeningValues(
        bands: Array(repeating: 0.02, count: 40),
        barCount: 3
    )

    #expect(values.count == 3)
    #expect(values.allSatisfy { $0 >= 0.10 && $0 <= 0.126 })
}

@Test
func classicHUDResponseGrowsWithVoiceLevelWithoutOverflowing() {
    var quietBands = Array(repeating: Float(0.02), count: 40)
    quietBands[18] = 0.05
    var normalBands = quietBands
    normalBands[18] = 0.22

    let quiet = HUDSpectrumResponse.classicListeningValues(
        bands: quietBands,
        barCount: 3
    )
    let normal = HUDSpectrumResponse.classicListeningValues(
        bands: normalBands,
        barCount: 3
    )

    #expect((normal.max() ?? 0) > (quiet.max() ?? 0))
    #expect(normal.allSatisfy { $0 >= 0 && $0 <= 1 })
}

@Test
func classicHUDDecouplesFrequencyBandsByPitch() {
    var lowEnergyBands = Array(repeating: Float(0.02), count: 40)
    lowEnergyBands[2] = 0.45
    let lowValues = HUDSpectrumResponse.classicListeningValues(
        bands: lowEnergyBands,
        barCount: 3
    )
    #expect(lowValues[0] > lowValues[2] + 0.15)

    var highEnergyBands = Array(repeating: Float(0.02), count: 40)
    highEnergyBands[37] = 0.45
    let highValues = HUDSpectrumResponse.classicListeningValues(
        bands: highEnergyBands,
        barCount: 3
    )
    #expect(highValues[2] > highValues[0] + 0.15)
}

