import Testing
@testable import VaniScriptCore

@Suite("Universal smart silence slicer")
struct SmartSlicePlannerTests {
    @Test("computes energy profile in 20 millisecond windows")
    func computesEnergyProfile() {
        let sampleRate = 1_000
        let samples = Array(repeating: Int16(16_384), count: 20)
            + Array(repeating: Int16(0), count: 20)

        let profile = SmartSlicePlanner.computeEnergyProfile(
            pcm: samples,
            sampleRate: sampleRate
        )

        #expect(profile.count == 2)
        #expect(profile[0].posMs == 0)
        #expect(profile[0].dbfs > -7)
        #expect(profile[1].posMs == 20)
        #expect(profile[1].dbfs == -119)
    }

    @Test("chooses silence regions near target cut points")
    func choosesSilenceRegionsNearTargetCutPoints() {
        let sampleRate = 1_000
        var samples = Array(repeating: Int16(12_000), count: 3_000)
        for index in 940..<1_080 {
            samples[index] = 0
        }
        for index in 1_960..<2_120 {
            samples[index] = 0
        }

        let cutPoints = SmartSlicePlanner.computeCutPoints(
            pcm: samples,
            sampleRate: sampleRate,
            targetMs: 1_000,
            threshDb: -50,
            minSilenceMs: 80
        )

        #expect(cutPoints.count == 2)
        #expect(cutPoints[0] >= 980)
        #expect(cutPoints[0] <= 1_040)
        #expect(cutPoints[1] >= 2_000)
        #expect(cutPoints[1] <= 2_080)
    }
}
