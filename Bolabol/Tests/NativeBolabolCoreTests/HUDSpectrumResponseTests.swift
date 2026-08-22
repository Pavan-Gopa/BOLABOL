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


// MARK: Tech zigzag voice response (S7)

@Test
func techHUDRestsExactlyOnItsIdleFloorInSilence() {
    let values = HUDSpectrumResponse.techListeningValues(
        bands: Array(repeating: Float(0.02), count: 40),
        pointCount: 9
    )

    #expect(values.count == 9)
    #expect(values.allSatisfy { $0 == 0.10 })
}

@Test
func techHUDAnswersQuietSpeechBrightlyInsteadOfIdling() {
    var bands = Array(repeating: Float(0.02), count: 40)
    bands[18] = 0.12

    let values = HUDSpectrumResponse.techListeningValues(
        bands: bands,
        pointCount: 9
    )

    #expect(values.count == 9)
    // Quiet speech (peak 0.12) must already deflect clearly: the old mapping
    // left a 0.12 band essentially at the resting floor.
    #expect(values.max() ?? 0 >= 0.45)
    #expect(values.allSatisfy { $0 >= 0.10 && $0 <= 1 })
}

@Test
func techHUDSaturatesStrongVoiceNearFullDeflection() {
    var bands = Array(repeating: Float(0.02), count: 40)
    bands[7] = 0.30

    let values = HUDSpectrumResponse.techListeningValues(
        bands: bands,
        pointCount: 9
    )

    #expect((values.max() ?? 0) >= 0.95)
    #expect(values.allSatisfy { $0 <= 1 })
}

@Test
func techHUDKeepsPerPointContrastForLocalizedEnergy() {
    var bands = Array(repeating: Float(0.02), count: 40)
    bands[7] = 0.30

    let values = HUDSpectrumResponse.techListeningValues(
        bands: bands,
        pointCount: 9
    )
    let localized = values[1]
    let remote = values[7]

    // A localized spike must read as a local peak on the trace, not a uniform
    // wall: the point covering the spike strongly outruns a remote one.
    #expect(localized >= 0.85)
    #expect(remote <= localized - 0.20)
}

@Test
func techHUDResponseGrowsMonotonicallyWithVoiceLevel() {
    var silence = Array(repeating: Float(0.02), count: 40)
    silence[20] = 0.02
    var quiet = silence
    quiet[20] = 0.10
    var normal = silence
    normal[20] = 0.25
    var loud = silence
    loud[20] = 0.55

    let silenceMax = HUDSpectrumResponse.techListeningValues(bands: silence, pointCount: 9).max() ?? 0
    let quietMax = HUDSpectrumResponse.techListeningValues(bands: quiet, pointCount: 9).max() ?? 0
    let normalMax = HUDSpectrumResponse.techListeningValues(bands: normal, pointCount: 9).max() ?? 0
    let loudMax = HUDSpectrumResponse.techListeningValues(bands: loud, pointCount: 9).max() ?? 0

    #expect(quietMax > silenceMax)
    #expect(normalMax > quietMax)
    #expect(loudMax >= normalMax)
}

@Test
func techHUDSanitizesDegenerateInput() {
    #expect(HUDSpectrumResponse.techListeningValues(bands: [], pointCount: 9).allSatisfy { $0 == 0.10 })
    #expect(HUDSpectrumResponse.techListeningValues(bands: [0.5], pointCount: 0).isEmpty)

    var dirty = Array(repeating: Float(0.02), count: 40)
    dirty[3] = .nan
    dirty[11] = .infinity
    dirty[19] = -0.7
    dirty[27] = 0.42
    let values = HUDSpectrumResponse.techListeningValues(bands: dirty, pointCount: 9)
    #expect(values.count == 9)
    #expect(values.allSatisfy { $0.isFinite && $0 >= 0.10 && $0 <= 1 })
}

// MARK: Electric swarm processing visual (S7 round 2)

@Test
func swarmChargeEnvelopeRampsThenReleasesAndNeverSnapsAtWrap() {
    let cycle = HUDElectricSwarmPolicy.chargeCycleSeconds
    // The ramp zone charges monotonically toward full tension.
    var previous = -1.0
    var sample = 0.02
    while sample <= 0.86 {
        let envelope = HUDElectricSwarmPolicy.chargeEnvelope(for: 8 * cycle + sample * cycle)
        #expect(envelope.energy >= previous)
        #expect(envelope.energy >= 0 && envelope.energy <= 1)
        #expect(envelope.spark == 0)
        previous = envelope.energy
        sample += 0.06
    }
    // The release window flashes, then lets the energy go so the next cycle
    // restarts from rest without a visible position snap.
    let peak = HUDElectricSwarmPolicy.chargeEnvelope(for: 8 * cycle + 0.95 * cycle)
    #expect(peak.spark == 1)
    #expect(peak.energy > 0 && peak.energy < 1)
    let wrap = HUDElectricSwarmPolicy.chargeEnvelope(for: 8 * cycle + 0.999 * cycle)
    #expect(wrap.energy < 0.02)
    #expect(wrap.spark < 0.04)
    let start = HUDElectricSwarmPolicy.chargeEnvelope(for: 8 * cycle)
    #expect(start.energy == 0)
    #expect(start.spark == 0)
}

@Test
func swarmChargeEnvelopeIsPeriodicInWholeCycles() {
    let cycle = HUDElectricSwarmPolicy.chargeCycleSeconds
    for fraction in [0.0, 0.35, 0.88, 0.92, 0.99] {
        let first = HUDElectricSwarmPolicy.chargeEnvelope(for: fraction * cycle)
        let later = HUDElectricSwarmPolicy.chargeEnvelope(for: 5 * cycle + fraction * cycle)
        #expect(abs(first.energy - later.energy) < 1e-12)
        #expect(abs(first.spark - later.spark) < 1e-12)
        #expect(later.cycle == first.cycle + 5)
    }
}

@Test
func swarmFrameIsDeterministicFromPhase() {
    let first = HUDElectricSwarmPolicy.frame(for: 812_345.29, width: 42, height: 38, particleCount: 16)
    let second = HUDElectricSwarmPolicy.frame(for: 812_345.29, width: 42, height: 38, particleCount: 16)
    #expect(first == second)
    let drift = HUDElectricSwarmPolicy.frame(for: 812_345.29 + 0.04, width: 42, height: 38, particleCount: 16)
    #expect(first != drift)
}

@Test
func swarmArcWebIntensifiesWithCharge() {
    let cycle = HUDElectricSwarmPolicy.chargeCycleSeconds
    let resting = HUDElectricSwarmPolicy.frame(for: 3 * cycle + 0.02 * cycle, width: 42, height: 38, particleCount: 16)
    let charged = HUDElectricSwarmPolicy.frame(for: 3 * cycle + 0.88 * cycle, width: 42, height: 38, particleCount: 16)
    #expect(resting.energy < 0.05)
    #expect(charged.energy > 0.95)
    #expect(charged.arcs.count > resting.arcs.count)
    #expect(charged.arcs.count >= 8)
    #expect(charged.bloom > resting.bloom)
    // Near peak charge a hotter strike joins the ordinary web.
    #expect(charged.arcs.contains { $0.isStrike })
    // The release window fires its bolt: a strike intensity near one.
    let burst = HUDElectricSwarmPolicy.frame(for: 3 * cycle + 0.95 * cycle, width: 42, height: 38, particleCount: 16)
    #expect(burst.spark == 1)
    #expect(burst.arcs.contains(where: { $0.isStrike && $0.intensity >= 0.85 }))
}

@Test
func swarmParticlesStayInsideTheFieldAndEveryValueIsSanitized() {
    let cycle = HUDElectricSwarmPolicy.chargeCycleSeconds
    var stridePhase = 0.0
    while stridePhase < 4 * cycle {
        let frame = HUDElectricSwarmPolicy.frame(for: stridePhase, width: 42, height: 38, particleCount: 16)
        #expect(frame.particles.count == 16)
        #expect(frame.bloom >= 0 && frame.bloom <= 1)
        for particle in frame.particles {
            #expect(particle.x >= 2.5 && particle.x <= 42 - 2.5)
            #expect(particle.y >= 2.5 && particle.y <= 38 - 2.5)
            #expect(particle.radius > 0)
            #expect(particle.brightness >= 0 && particle.brightness <= 1)
            #expect(particle.heat >= 0 && particle.heat <= 1)
        }
        for arc in frame.arcs {
            #expect(arc.from >= 0 && arc.from < 16)
            #expect(arc.to >= 0 && arc.to < 16)
            #expect(arc.from != arc.to)
            #expect(arc.intensity > 0 && arc.intensity <= 1)
        }
        stridePhase += 0.17
    }
}

@Test
func swarmStrikePairIsDeterministicDistinctAndVariesPerCycle() throws {
    var pairs = [(Int, Int)]()
    for cycle in 0..<12 {
        let pair = try #require(HUDElectricSwarmPolicy.strikePair(cycle: cycle, particleCount: 16))
        #expect(pair.0 != pair.1)
        let repeated = try #require(HUDElectricSwarmPolicy.strikePair(cycle: cycle, particleCount: 16))
        #expect(repeated == pair)
        pairs.append(pair)
    }
    #expect(Set(pairs.map { "\($0.0)-\($0.1)" }).count >= 4)
    #expect(HUDElectricSwarmPolicy.strikePair(cycle: 0, particleCount: 1) == nil)
}

@Test
func swarmFrameSanitizesDegenerateInputs() {
    let empty = HUDElectricSwarmPolicy.frame(for: 12.5, width: 0, height: 38, particleCount: 16)
    #expect(empty.particles.isEmpty)
    #expect(empty.arcs.isEmpty)
    let emptyCount = HUDElectricSwarmPolicy.frame(for: 12.5, width: 42, height: 38, particleCount: 0)
    #expect(emptyCount.particles.isEmpty)
    let dirty = HUDElectricSwarmPolicy.frame(for: .nan, width: 42, height: 38, particleCount: 16)
    #expect(dirty.particles.isEmpty)
    // A single particle draws alone without crashing the arc pass.
    let solo = HUDElectricSwarmPolicy.frame(for: 3.0, width: 42, height: 38, particleCount: 1)
    #expect(solo.particles.count == 1)
    #expect(solo.arcs.isEmpty)
}

@Test
func swarmRobustnessUnderExtremeFinitePhases() {
    let testPhases: [Double] = [
        .greatestFiniteMagnitude,
        -.greatestFiniteMagnitude,
        1e300,
        -1e300,
        1e-300,
        .leastNonzeroMagnitude,
        .leastNormalMagnitude,
        0.0,
        -0.0
    ]

    for phase in testPhases {
        let envelope = HUDElectricSwarmPolicy.chargeEnvelope(for: phase)
        #expect(envelope.energy.isFinite, "energy must be finite for phase \(phase)")
        #expect(envelope.energy >= 0 && envelope.energy <= 1)
        #expect(envelope.spark.isFinite, "spark must be finite for phase \(phase)")
        #expect(envelope.spark >= 0 && envelope.spark <= 1)

        let frame = HUDElectricSwarmPolicy.frame(for: phase, width: 42, height: 38, particleCount: 16)
        #expect(frame.particles.count == 16)
        #expect(frame.energy.isFinite && frame.energy >= 0 && frame.energy <= 1)
        #expect(frame.spark.isFinite && frame.spark >= 0 && frame.spark <= 1)
        #expect(frame.bloom.isFinite && frame.bloom >= 0 && frame.bloom <= 1)

        for particle in frame.particles {
            #expect(particle.x.isFinite, "particle.x must be finite for phase \(phase)")
            #expect(particle.x >= 2.5 && particle.x <= 42 - 2.5)
            #expect(particle.y.isFinite, "particle.y must be finite for phase \(phase)")
            #expect(particle.y >= 2.5 && particle.y <= 38 - 2.5)
            #expect(particle.radius.isFinite && particle.radius > 0)
            #expect(particle.brightness.isFinite && particle.brightness >= 0 && particle.brightness <= 1)
            #expect(particle.heat.isFinite && particle.heat >= 0 && particle.heat <= 1)
        }

        for arc in frame.arcs {
            #expect(arc.from >= 0 && arc.from < 16)
            #expect(arc.to >= 0 && arc.to < 16)
            #expect(arc.from != arc.to)
            #expect(arc.intensity.isFinite && arc.intensity >= 0 && arc.intensity <= 1)
        }
    }
}
