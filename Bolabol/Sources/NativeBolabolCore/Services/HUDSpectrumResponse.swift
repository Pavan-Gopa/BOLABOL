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

    /// Maps the recorder's spectrum into the tech zigzag's listening trace.
    ///
    /// The response is deliberately brighter than the classic mapping: silence
    /// rests exactly on the idle floor (the view layers a subtle drift on top
    /// of the flat signal), while voiced bands rise steeply toward full
    /// deflection so speech reads as an unmistakable, strongly articulated
    /// zigzag instead of a faint ripple.
    public static func techListeningValues(
        bands: [Float],
        pointCount: Int,
        idleFloor: Float = 0.10
    ) -> [Float] {
        guard pointCount > 0 else { return [] }

        let floor = min(1, max(0, idleFloor))
        let sanitized = bands.map { value in
            value.isFinite ? min(1, max(0, value)) : 0
        }
        guard !sanitized.isEmpty else {
            return Array(repeating: floor, count: pointCount)
        }

        let peak = sanitized.max() ?? 0
        guard peak >= 0.045 else {
            return Array(repeating: floor, count: pointCount)
        }

        let buckets = peakWeightedBuckets(sanitized, count: pointCount)
        let pointTotal = max(1, pointCount - 1)
        let globalPresence = shaped(
            min(1, max(0, (peak - 0.040) / 0.22)),
            exponent: 0.62
        )

        return buckets.enumerated().map { index, value in
            let progress = Float(index) / Float(pointTotal)
            // Steep local rise with a lowered gate: moderate buckets already
            // produce a clearly visible deflection, strong ones saturate.
            let localInput = min(1, max(0, (value - 0.040) / 0.15))
            let localResponse = shaped(localInput, exponent: 0.55)
            // A center-weighted global breath keeps the trace connected on
            // voice without flattening per-point contrast.
            let voiceTaper = 0.30 + 0.70 * sin(progress * .pi)
            let combined = max(localResponse, globalPresence * 0.6 * voiceTaper)
            return min(1, max(floor, combined))
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

/// One frame of the tech-processing electric particle swarm, fully resolved
/// and ready to draw. Everything is derived deterministically from `phase`,
/// so identical phases always yield identical frames and the render loop can
/// stay a pure function of time.
public struct HUDElectricSwarmFrame: Equatable, Sendable {
    public let particles: [HUDSwarmParticle]
    public let arcs: [HUDSwarmArc]
    /// 0…1 charge tension driving arc density, contraction, and bloom.
    public let energy: Double
    /// 0…1 discharge flash inside the release window; peaks mid-burst.
    public let spark: Double
    /// 0…1 central bloom intensity for the about-to-burst core glow.
    public let bloom: Double
    /// Index of the current charge cycle; seeds the burst strike pair.
    public let cycle: Int

    public init(
        particles: [HUDSwarmParticle],
        arcs: [HUDSwarmArc],
        energy: Double,
        spark: Double,
        bloom: Double,
        cycle: Int
    ) {
        self.particles = particles
        self.arcs = arcs
        self.energy = energy
        self.spark = spark
        self.bloom = bloom
        self.cycle = cycle
    }
}

public struct HUDSwarmParticle: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let radius: Double
    /// 0…1 twinkle brightness; swarms blink actively even at rest.
    public let brightness: Double
    /// 0…1 heat; particles at arc ends glow white-hot above ~0.55.
    public let heat: Double

    public init(x: Double, y: Double, radius: Double, brightness: Double, heat: Double) {
        self.x = x
        self.y = y
        self.radius = radius
        self.brightness = brightness
        self.heat = heat
    }
}

public struct HUDSwarmArc: Equatable, Sendable {
    public let from: Int
    public let to: Int
    /// 0…1 discharge intensity between neighboring particles.
    public let intensity: Double
    /// Occasional brighter strike (charged bolt), rendered thicker and white.
    public let isStrike: Bool

    public init(from: Int, to: Int, intensity: Double, isStrike: Bool) {
        self.from = from
        self.to = to
        self.intensity = intensity
        self.isStrike = isStrike
    }
}

/// Deterministic motion/discharge model for the electric-swarm tech
/// processing visual. The widget's energy charges up over a cycle, the arc
/// web intensifies toward the burst, and a paired strike discharges during
/// the release window; no per-frame randomness exists anywhere in the model.
public enum HUDElectricSwarmPolicy {
    /// Seconds for one full charge → burst cycle.
    public static let chargeCycleSeconds: Double = 2.6

    /// Fraction of the cycle spent charging; the remainder releases.
    private static let chargeRampFraction: Double = 0.90

    /// Charge envelope for a given phase. `energy` ramps smoothly from 0 to
    /// 1 across the charge window and releases fully inside the tail so
    /// frames stay continuous across cycle boundaries; `spark` flashes only
    /// inside the release tail and returns to 0 at both of its edges.
    public static func chargeEnvelope(
        for phase: Double
    ) -> (energy: Double, spark: Double, cycle: Int) {
        guard phase.isFinite else { return (energy: 0, spark: 0, cycle: 0) }
        let wrapped = positiveRemainder(phase, chargeCycleSeconds)
        let progress = wrapped / chargeCycleSeconds
        let rawCycle = floor(phase / chargeCycleSeconds)
        let cycle: Int
        if rawCycle.isFinite {
            let normalized = rawCycle.truncatingRemainder(dividingBy: 1_000_000_000)
            cycle = Int(normalized)
        } else {
            cycle = 0
        }

        let ramp = min(1, progress / chargeRampFraction)
        let gather = smoothStep(ramp)
        let tail = max(0, (progress - chargeRampFraction) / (1 - chargeRampFraction))
        let tailProgress = min(1, tail)
        let release = tail > 0 ? smoothStep(tailProgress) : 0
        let spark = tail > 0 ? sin(tailProgress * .pi) : 0
        return (energy: gather * (1 - release), spark: spark, cycle: cycle)
    }

    /// Deterministic charged pair for the mid-cycle hot arc and the release
    /// bolt. Distinct indices guaranteed; varies from cycle to cycle.
    public static func strikePair(cycle: Int, particleCount: Int) -> (Int, Int)? {
        guard particleCount >= 2 else { return nil }
        let seed = UInt64(bitPattern: Int64(cycle))
        let first = Int(hashUnit(seed &+ 1) * Double(particleCount))
        var second = Int(hashUnit(seed &+ 2) * Double(particleCount))
        if second == first {
            second = (second + 1) % particleCount
        }
        return (min(first, second), max(first, second))
    }

    /// Resolves one complete draw frame at `phase` for a field of
    /// `width`×`height` points. Twinkle frequencies stay active at rest, arc
    /// density grows with `energy`, and particles gather toward the centroid
    /// as the charge tightens, then burst outward during the spark flash.
    public static func frame(
        for phase: Double,
        width: Double,
        height: Double,
        particleCount: Int
    ) -> HUDElectricSwarmFrame {
        let count = max(0, min(64, particleCount))
        guard phase.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0, count > 0 else {
            return HUDElectricSwarmFrame(
                particles: [], arcs: [], energy: 0, spark: 0, bloom: 0, cycle: 0
            )
        }
        let envelope = chargeEnvelope(for: phase)
        let energy = envelope.energy
        let spark = envelope.spark
        let centroid = (x: width / 2, y: height / 2)
        let boundedPhase = phase.truncatingRemainder(dividingBy: 1_000_000_000)

        // Raw orbital motion: constant per-particle angular speeds keep
        // positions continuous across cycle boundaries; only the orbit
        // amplitude breathes with energy.
        var base = [CGPointPair](repeating: CGPointPair(), count: count)
        for index in 0..<count {
            let speedHash = hashUnit(UInt64(index) &+ 11)
            let radiusHash = hashUnit(UInt64(index) &+ 23)
            let angle = boundedPhase * (0.9 + 2.6 * speedHash) + Double(index) * 2.399
            let orbit = CGPointPair(
                x: width * (0.10 + 0.34 * hashUnit(UInt64(index) &+ 5)) * (0.35 + 0.65 * energy),
                y: height * (0.12 + 0.36 * hashUnit(UInt64(index) &+ 7)) * (0.35 + 0.65 * energy)
            )
            let anchorX = width * hashUnit(UInt64(index) &+ 13)
            let anchorY = height * hashUnit(UInt64(index) &+ 17)
            base[index] = CGPointPair(
                x: anchorX + cos(angle) * orbit.x * (0.72 + 0.56 * radiusHash),
                y: anchorY + sin(angle) * orbit.y * (0.72 + 0.56 * radiusHash)
            )
        }

        // Charge gathers the swarm toward its centroid; the spark burst
        // pushes particles back out along their radial directions.
        var positions = [CGPointPair](repeating: CGPointPair(), count: count)
        for index in 0..<count {
            let gatheredX = base[index].x + (centroid.x - base[index].x) * (0.20 * energy)
            let gatheredY = base[index].y + (centroid.y - base[index].y) * (0.20 * energy)
            let dx = gatheredX - centroid.x
            let dy = gatheredY - centroid.y
            let length = max(0.001, (dx * dx + dy * dy).squareRoot())
            let burst = spark * (3.0 + 4.0 * hashUnit(UInt64(index) &+ 29))
            positions[index] = CGPointPair(
                x: gatheredX + dx / length * burst,
                y: gatheredY + dy / length * burst
            )
        }

        // Arc web: neighbours link when they drift inside the link radius,
        // which widens sharply as the charge intensifies.
        let linkRadius = mix(
            7.0,
            min(max(10.0, min(width, height) * 0.58), 26.0),
            energy
        )
        var arcs: [HUDSwarmArc] = []
        arcs.reserveCapacity(count)
        if count >= 2 {
            for first in 0..<(count - 1) {
                for second in (first + 1)..<count {
                    let dx = positions[first].x - positions[second].x
                    let dy = positions[first].y - positions[second].y
                    let distance = (dx * dx + dy * dy).squareRoot()
                    guard distance <= linkRadius else { continue }
                    let proximity = 1 - distance / max(linkRadius, 0.001)
                    let intensity = pow(proximity, 1.35) * mix(0.30, 1.0, energy)
                    guard intensity > 0.08 else { continue }
                    arcs.append(
                        HUDSwarmArc(from: first, to: second, intensity: min(1, intensity), isStrike: false)
                    )
                }
            }
        }

        // Occasional brighter strikes: one hot arc appears near peak charge,
        // and the release bolt fires its cycle's pair across the field.
        if count >= 2 {
            if energy > 0.75, let hot = strikePair(cycle: envelope.cycle &+ 7919, particleCount: count) {
                let hotIntensity = min(1, 0.85 * energy)
                if let existing = arcs.firstIndex(where: { arc in
                    (arc.from == hot.0 && arc.to == hot.1) || (arc.from == hot.1 && arc.to == hot.0)
                }) {
                    arcs[existing] = HUDSwarmArc(
                        from: arcs[existing].from,
                        to: arcs[existing].to,
                        intensity: max(arcs[existing].intensity, hotIntensity),
                        isStrike: true
                    )
                } else {
                    arcs.append(
                        HUDSwarmArc(from: hot.0, to: hot.1, intensity: hotIntensity, isStrike: true)
                    )
                }
            }
            if spark > 0.05, let bolt = strikePair(cycle: envelope.cycle, particleCount: count) {
                if let existing = arcs.firstIndex(where: { arc in
                    (arc.from == bolt.0 && arc.to == bolt.1) || (arc.from == bolt.1 && arc.to == bolt.0)
                }) {
                    arcs[existing] = HUDSwarmArc(
                        from: arcs[existing].from,
                        to: arcs[existing].to,
                        intensity: max(arcs[existing].intensity, 0.9),
                        isStrike: true
                    )
                } else {
                    arcs.append(
                        HUDSwarmArc(from: bolt.0, to: bolt.1, intensity: 1, isStrike: true)
                    )
                }
            }
        }

        var particles = [HUDSwarmParticle]()
        particles.reserveCapacity(count)
        var heats = [Double](repeating: 0, count: count)
        for arc in arcs {
            let glow = arc.isStrike ? 1 : arc.intensity
            heats[arc.from] = max(heats[arc.from], glow)
            heats[arc.to] = max(heats[arc.to], glow)
        }
        for index in 0..<count {
            let twinkleRate = 5.0 + 4.0 * hashUnit(UInt64(index) &+ 31) + 6.5 * energy
            let twinkle = 0.5 + 0.5 * sin(boundedPhase * twinkleRate + Double(index) * 2.13)
            let brightness = min(1, max(0, 0.25 + 0.65 * twinkle * (0.55 + 0.45 * energy)))
            let baseRadius = 0.9 + 0.9 * hashUnit(UInt64(index) &+ 37)
            let radius = baseRadius * (1 + 0.45 * heats[index])
            let pad = 2.5
            particles.append(
                HUDSwarmParticle(
                    x: min(max(pad, positions[index].x), max(pad, width - pad)),
                    y: min(max(pad, positions[index].y), max(pad, height - pad)),
                    radius: radius,
                    brightness: brightness,
                    heat: min(1, heats[index])
                )
            )
        }

        let bloom = min(1, max(0, 0.10 + 0.55 * energy + 0.35 * spark))
        return HUDElectricSwarmFrame(
            particles: particles,
            arcs: arcs,
            energy: energy,
            spark: spark,
            bloom: bloom,
            cycle: envelope.cycle
        )
    }

    private static func positiveRemainder(_ value: Double, _ divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder < 0 ? remainder + divisor : remainder
    }

    private static func smoothStep(_ value: Double) -> Double {
        let clamped = min(1, max(0, value))
        return clamped * clamped * (3 - 2 * clamped)
    }

    private static func mix(_ lower: Double, _ upper: Double, _ t: Double) -> Double {
        lower + (upper - lower) * min(1, max(0, t))
    }

    /// SplitMix64 step mapped to the unit interval; deterministic across
    /// platforms and free of the precision decay of large-angle `sin` seeds.
    private static func hashUnit(_ seed: UInt64) -> Double {
        var z = seed &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        let mantissa = z >> 11
        return Double(mantissa) / Double(1 << 53)
    }

    private struct CGPointPair: Equatable, Sendable {
        var x: Double = 0
        var y: Double = 0
    }
}
