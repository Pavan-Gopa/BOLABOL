import Foundation
@testable import NativeBolabol
import Testing

// MARK: - S2 / ADR-023 speech-aware segmentation regression coverage
//
// Every test below exercises the real production planning API
// `GigaAMSpeechAwareChunker.plan(samples:configuration:)` and the in-place
// `GigaAMTokenOverlapMerger.merge(into:incoming:hasLeadingOverlap:)` against
// deterministic synthetic waveforms. No model, network, file system, sleep, or
// FluidAudio state is involved, and the planner algorithm is intentionally not
// reimplemented here: assertions state the observable ADR-023 contract
// (exact ownership partition, bounded inference, pause > low-energy > hard
// hierarchy, 500 ms hard-overlap-only leading overlap, >= 5 s final inference,
// conservative 2-8 token dedup).

private typealias Chunker = GigaAMSpeechAwareChunker
private typealias ChunkerConfig = GigaAMSpeechAwareChunker.Configuration
private typealias ChunkerChunk = GigaAMSpeechAwareChunker.Chunk

private let s2Rate: Double = 16_000
private let s2Speech: Float = 0.4
private let s2Silence: Float = 0.0
private let s2HardLimit16k = 480_000 // floor(30 s * 16 kHz)
private let s2LeadingOverlap16k = 8_000 // 0.5 s * 16 kHz
private let s2MinFinalInference16k = 80_000 // 5 s * 16 kHz

private func s2Samples(seconds: Double, amplitude: Float, sampleRate: Double = s2Rate) -> [Float] {
    [Float](repeating: amplitude, count: Int((seconds * sampleRate).rounded()))
}

private func s2Waveform(_ parts: [(seconds: Double, amplitude: Float)], sampleRate: Double = s2Rate) -> [Float] {
    var samples: [Float] = []
    for part in parts {
        samples.append(contentsOf: s2Samples(seconds: part.seconds, amplitude: part.amplitude, sampleRate: sampleRate))
    }
    return samples
}

/// Shared ADR-023 structural invariants: exact ordered ownership partition of
/// `0..<sampleCount`, non-empty in-bounds inference ranges ending at owned
/// ends, inference never exceeding the hard sample limit, overlap only after a
/// hard fallback and bounded by the configured leading overlap, and a
/// consistent `hasLeadingOverlap` flag.
private func expectValidPlan(
    _ chunks: [ChunkerChunk],
    sampleCount: Int,
    hardLimitSamples: Int,
    leadingOverlapSamples: Int,
    maxChunkCount: Int? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    if sampleCount == 0 {
        #expect(chunks.isEmpty, "empty input must produce no chunks", sourceLocation: sourceLocation)
        return
    }

    #expect(!chunks.isEmpty, "non-empty input must produce at least one chunk", sourceLocation: sourceLocation)
    if let maxChunkCount {
        #expect(
            chunks.count <= maxChunkCount,
            "chunk count \(chunks.count) exceeds the finite bound \(maxChunkCount) (possible loop)",
            sourceLocation: sourceLocation
        )
    }

    var previousUpper = 0
    for (index, chunk) in chunks.enumerated() {
        #expect(!chunk.ownedRange.isEmpty, "chunk \(index) owns an empty range", sourceLocation: sourceLocation)
        #expect(
            chunk.ownedRange.lowerBound == previousUpper,
            "ownership must be contiguous: chunk \(index) starts at \(chunk.ownedRange.lowerBound), expected \(previousUpper)",
            sourceLocation: sourceLocation
        )
        #expect(
            chunk.ownedRange.upperBound <= sampleCount,
            "chunk \(index) ownership leaves source bounds",
            sourceLocation: sourceLocation
        )

        #expect(!chunk.inferenceRange.isEmpty, "chunk \(index) inference range is empty", sourceLocation: sourceLocation)
        #expect(chunk.inferenceRange.lowerBound >= 0, "chunk \(index) inference starts before the source", sourceLocation: sourceLocation)
        #expect(
            chunk.inferenceRange.upperBound == chunk.ownedRange.upperBound,
            "chunk \(index) inference must end at its owned end",
            sourceLocation: sourceLocation
        )
        #expect(
            chunk.inferenceRange.count <= hardLimitSamples,
            "chunk \(index) inference \(chunk.inferenceRange.count) exceeds the hard limit \(hardLimitSamples)",
            sourceLocation: sourceLocation
        )
        #expect(
            chunk.inferenceRange.lowerBound <= chunk.ownedRange.lowerBound,
            "chunk \(index) inference must not start after its ownership",
            sourceLocation: sourceLocation
        )

        let overlap = chunk.ownedRange.lowerBound - chunk.inferenceRange.lowerBound
        if index == 0 {
            #expect(chunk.inferenceRange.lowerBound == 0, "the first chunk must start at sample 0", sourceLocation: sourceLocation)
        } else if chunks[index - 1].endReason == .hardFallback {
            #expect(
                overlap >= 0 && overlap <= leadingOverlapSamples,
                "chunk \(index) overlap \(overlap) must stay within 0...\(leadingOverlapSamples) after a hard fallback",
                sourceLocation: sourceLocation
            )
        } else {
            #expect(
                overlap == 0,
                "chunk \(index) overlaps by \(overlap) but only hard fallbacks may create overlap",
                sourceLocation: sourceLocation
            )
        }
        #expect(
            chunk.hasLeadingOverlap == (overlap > 0),
            "chunk \(index) hasLeadingOverlap flag is inconsistent with its ranges",
            sourceLocation: sourceLocation
        )

        previousUpper = chunk.ownedRange.upperBound
    }
    #expect(
        previousUpper == sampleCount,
        "ownership must cover every source sample exactly once; ended at \(previousUpper) of \(sampleCount)",
        sourceLocation: sourceLocation
    )
}

struct GigaAMSpeechAwareChunkerTests {

    // MARK: Short input

    @Test
    func emptyInputProducesNoChunks() {
        let chunks = Chunker.plan(samples: [], configuration: ChunkerConfig())
        #expect(chunks.isEmpty)
    }

    @Test
    func shortInputsProduceOneExactOwnedInferenceChunk() {
        for count in [1, 100, 160_000] { // 1 sample, very short, 10 s
            let samples = [Float](repeating: s2Speech, count: count)
            let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())

            #expect(chunks.count == 1, "count \(count) must plan to exactly one chunk")
            guard let chunk = chunks.first else { continue }
            #expect(chunk.ownedRange == 0..<count)
            #expect(chunk.inferenceRange == 0..<count)
            #expect(chunk.endReason == .singleChunk)
            #expect(!chunk.hasLeadingOverlap)
        }
    }

    // MARK: Pause before the boundary

    @Test
    func qualifyingPauseBeforeBoundaryCutsInsideSilenceNearTarget() {
        // Speech through 26 s, a 2 s qualifying pause, speech to 35 s.
        let samples = s2Waveform([
            (seconds: 26, amplitude: s2Speech),
            (seconds: 2, amplitude: s2Silence),
            (seconds: 7, amplitude: s2Speech),
        ])
        #expect(samples.count == 560_000)

        let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())
        expectValidPlan(
            chunks,
            sampleCount: samples.count,
            hardLimitSamples: s2HardLimit16k,
            leadingOverlapSamples: s2LeadingOverlap16k,
            maxChunkCount: 3
        )

        #expect(chunks.count == 2)
        let first = chunks[0]
        #expect(first.endReason == .pause)
        // The cut lands strictly inside the [26 s, 28 s) silence at the 27 s
        // target — never at the 30 s hard edge.
        #expect(first.ownedRange.upperBound == 432_000)
        #expect(first.ownedRange.upperBound > 416_000)
        #expect(first.ownedRange.upperBound < 448_000)
        #expect(first.ownedRange.upperBound != s2HardLimit16k)
        #expect(!first.hasLeadingOverlap)

        #expect(chunks[1].ownedRange == 432_000..<560_000)
        #expect(chunks[1].inferenceRange == 432_000..<560_000)
        #expect(chunks[1].endReason == .terminalRemaining)
    }

    @Test
    func subMinimumSilenceDipDoesNotQualifyAsPause() {
        // A 200 ms dip is below the 240 ms minimum silence, so it must not be
        // chosen as a pause boundary (it remains visible as low energy only).
        let samples = s2Waveform([
            (seconds: 26, amplitude: s2Speech),
            (seconds: 0.2, amplitude: s2Silence),
            (seconds: 8.8, amplitude: s2Speech),
        ])
        #expect(samples.count == 560_000)

        let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())
        expectValidPlan(
            chunks,
            sampleCount: samples.count,
            hardLimitSamples: s2HardLimit16k,
            leadingOverlapSamples: s2LeadingOverlap16k,
            maxChunkCount: 3
        )

        #expect(chunks.count == 2)
        let first = chunks[0]
        #expect(first.endReason != .pause)
        #expect(first.endReason == .lowEnergy)
        #expect(first.ownedRange.upperBound == 417_600) // centered inside the 200 ms dip
        #expect(first.ownedRange.upperBound >= 416_000)
        #expect(first.ownedRange.upperBound <= 419_200)
        #expect(first.ownedRange.upperBound != s2HardLimit16k)
    }

    // MARK: Speech crossing the 30 s capacity

    @Test
    func earlierPauseIsChosenWhenActiveSpeechCrossesThirtySeconds() {
        // Speech through 26 s, a 0.5 s qualifying pause, then uninterrupted
        // speech from 26.5 s to 40 s — actively speaking at the 30 s mark.
        let samples = s2Waveform([
            (seconds: 26, amplitude: s2Speech),
            (seconds: 0.5, amplitude: s2Silence),
            (seconds: 13.5, amplitude: s2Speech),
        ])
        #expect(samples.count == 640_000)

        let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())
        expectValidPlan(
            chunks,
            sampleCount: samples.count,
            hardLimitSamples: s2HardLimit16k,
            leadingOverlapSamples: s2LeadingOverlap16k,
            maxChunkCount: 3
        )

        #expect(chunks.count == 2)
        #expect(chunks[0].endReason == .pause)
        #expect(chunks[0].ownedRange.upperBound == 424_000) // end of the 26.0-26.5 s pause
        #expect(chunks[0].ownedRange.upperBound < s2HardLimit16k)
        // The active region crossing 30 s stays inside one chunk and is not
        // cut at the hard capacity.
        #expect(chunks[1].ownedRange == 424_000..<640_000)
        #expect(chunks[1].ownedRange.contains(s2HardLimit16k))
        #expect(chunks.allSatisfy { $0.endReason != .hardFallback })
        #expect(chunks.allSatisfy { !$0.hasLeadingOverlap })
    }

    // MARK: Continuous speech

    @Test
    func continuousSpeechFallsBackToHardCapacityWithBoundedOverlap() {
        // Constant-energy speech offers no pause and no reliable low-energy
        // window: every non-final boundary must be the hard fallback, followed
        // by exactly 500 ms of leading overlap, with a >= 5 s final inference.
        let cases: [(count: Int, expectedChunks: Int, firstOwnedUpper: Int, lastInferenceCount: Int)] = [
            (640_000, 2, 480_000, 168_000), // 40 s
            (480_001, 2, 400_001, 88_000), // 30 s + 1 sample
            (952_000, 2, 480_000, 480_000), // 59.5 s
            (953_600, 3, 480_000, 88_000), // 59.6 s
            (960_000, 3, 480_000, 88_000), // 60 s
            (1_024_000, 3, 480_000, 88_000), // 64 s
        ]

        for testCase in cases {
            let samples = [Float](repeating: s2Speech, count: testCase.count)
            let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())

            expectValidPlan(
                chunks,
                sampleCount: testCase.count,
                hardLimitSamples: s2HardLimit16k,
                leadingOverlapSamples: s2LeadingOverlap16k,
                maxChunkCount: testCase.count / 400_000 + 2
            )

            #expect(
                chunks.count == testCase.expectedChunks,
                "\(testCase.count) samples must plan to \(testCase.expectedChunks) chunks, got \(chunks.count)"
            )
            guard chunks.count == testCase.expectedChunks else { continue }

            #expect(chunks.dropLast().allSatisfy { $0.endReason == .hardFallback })
            #expect(chunks.last?.endReason == .terminalRemaining)
            #expect(chunks[0].ownedRange.upperBound == testCase.firstOwnedUpper)
            #expect(chunks.dropFirst().allSatisfy { $0.hasLeadingOverlap })
            for chunk in chunks.dropFirst() {
                #expect(
                    chunk.ownedRange.lowerBound - chunk.inferenceRange.lowerBound == s2LeadingOverlap16k,
                    "hard-fallback overlap must be exactly 500 ms (8000 samples)"
                )
            }
            // Tail rebalance keeps the final inference >= 5 s and every
            // inference within the 30 s window.
            #expect(chunks.last!.inferenceRange.count == testCase.lastInferenceCount)
            #expect(chunks.last!.inferenceRange.count >= s2MinFinalInference16k)
            #expect(chunks.allSatisfy { $0.inferenceRange.count <= s2HardLimit16k })
        }
    }

    // MARK: Several minutes

    @Test
    func severalMinutesOfAlternatingSpeechAndSilenceKeepFullTimeline() {
        // 180 s: six 26 s speech + 1 s silence cycles, then 18 s of speech.
        var parts: [(seconds: Double, amplitude: Float)] = []
        for _ in 0..<6 {
            parts.append((seconds: 26, amplitude: s2Speech))
            parts.append((seconds: 1, amplitude: s2Silence))
        }
        parts.append((seconds: 18, amplitude: s2Speech))
        let samples = s2Waveform(parts)
        #expect(samples.count == 2_880_000)

        let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())
        expectValidPlan(
            chunks,
            sampleCount: samples.count,
            hardLimitSamples: s2HardLimit16k,
            leadingOverlapSamples: s2LeadingOverlap16k,
            maxChunkCount: 9
        )

        #expect(chunks.count == 7)
        #expect(chunks.dropLast().allSatisfy { $0.endReason == .pause })
        #expect(chunks.last?.endReason == .terminalRemaining)
        #expect(chunks.allSatisfy { !$0.hasLeadingOverlap })
        // Pauses near the 27 s target keep every advance inside 25-30 s.
        for chunk in chunks.dropLast() {
            #expect(chunk.ownedRange.count >= 400_000 && chunk.ownedRange.count <= 480_000)
        }
    }

    @Test
    func severalMinutesOfContinuousSpeechRemainBounded() {
        let samples = [Float](repeating: s2Speech, count: 2_400_000) // 150 s
        let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())
        expectValidPlan(
            chunks,
            sampleCount: samples.count,
            hardLimitSamples: s2HardLimit16k,
            leadingOverlapSamples: s2LeadingOverlap16k,
            maxChunkCount: 7
        )

        #expect(chunks.count == 6)
        #expect(chunks.dropLast().allSatisfy { $0.endReason == .hardFallback })
        #expect(chunks.last?.endReason == .terminalRemaining)
        #expect(chunks.first?.ownedRange.upperBound == s2HardLimit16k)
        #expect(chunks.dropFirst().allSatisfy { $0.hasLeadingOverlap })
        for chunk in chunks.dropFirst() {
            #expect(chunk.ownedRange.lowerBound - chunk.inferenceRange.lowerBound == s2LeadingOverlap16k)
        }
        // The penultimate boundary is rebalanced so the tail keeps >= 5 s.
        #expect(chunks[4].ownedRange.upperBound == samples.count - s2MinFinalInference16k)
        #expect(chunks.last!.inferenceRange.count >= s2MinFinalInference16k)
    }

    // MARK: Silence

    @Test
    func fullySilentInputPrefersNonSpeechBoundariesAndOwnsEverySample() {
        let samples = [Float](repeating: s2Silence, count: 720_000) // 45 s
        let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())
        expectValidPlan(
            chunks,
            sampleCount: samples.count,
            hardLimitSamples: s2HardLimit16k,
            leadingOverlapSamples: s2LeadingOverlap16k,
            maxChunkCount: 3
        )

        #expect(chunks.count == 2)
        #expect(chunks.allSatisfy { $0.endReason != .hardFallback })
        #expect(chunks[0].endReason == .pause)
        #expect(chunks[0].ownedRange.upperBound == 432_000)
        #expect(chunks.allSatisfy { !$0.hasLeadingOverlap })
    }

    @Test
    func speechFollowedByLongSilencePreservesCompleteTimeline() {
        let samples = s2Waveform([
            (seconds: 10, amplitude: s2Speech),
            (seconds: 50, amplitude: s2Silence),
        ])
        #expect(samples.count == 960_000)

        let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())
        expectValidPlan(
            chunks,
            sampleCount: samples.count,
            hardLimitSamples: s2HardLimit16k,
            leadingOverlapSamples: s2LeadingOverlap16k,
            maxChunkCount: 4
        )

        #expect(chunks.count == 3)
        #expect(chunks[0].endReason == .pause)
        #expect(chunks[0].ownedRange.upperBound == 432_000)
        #expect(chunks[1].endReason == .pause)
        #expect(chunks[1].ownedRange.upperBound == 864_000)
        #expect(chunks[2].endReason == .terminalRemaining)
        #expect(chunks[2].ownedRange.upperBound == 960_000)
        #expect(chunks.allSatisfy { !$0.hasLeadingOverlap })
    }

    // MARK: Exact boundary and sample-rate scaling

    @Test
    func exactThirtySecondsIsOneFullChunkWithoutMicrochunk() {
        let samples = [Float](repeating: s2Speech, count: 480_000)
        let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())

        #expect(chunks.count == 1)
        guard let chunk = chunks.first else { return }
        #expect(chunk.ownedRange == 0..<480_000)
        #expect(chunk.inferenceRange == 0..<480_000)
        #expect(chunk.endReason == .singleChunk)
        #expect(!chunk.hasLeadingOverlap)
    }

    @Test
    func justUnderThirtySecondsRemainsOneChunk() {
        let samples = [Float](repeating: s2Speech, count: 479_984) // 29.999 s at 16 kHz
        let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())

        #expect(chunks.count == 1)
        guard let chunk = chunks.first else { return }
        #expect(chunk.ownedRange == 0..<479_984)
        #expect(chunk.inferenceRange == 0..<479_984)
        #expect(chunk.endReason == .singleChunk)
    }

    @Test
    func hardLimitScalesWithActualSampleRate() {
        for rate in [8_000.0, 24_000.0, 44_100.0, 48_000.0, 96_000.0] {
            let hardLimit = Int((30.0 * rate).rounded(.down))
            let samples = [Float](repeating: s2Speech, count: hardLimit)
            let chunks = Chunker.plan(samples: samples, sampleRate: rate)

            #expect(chunks.count == 1, "exactly 30 s at \(rate) Hz must be one chunk")
            guard let chunk = chunks.first else { continue }
            #expect(chunk.ownedRange == 0..<hardLimit)
            #expect(chunk.inferenceRange == 0..<hardLimit)
            #expect(chunk.endReason == .singleChunk)
        }
    }

    @Test
    func overLimitAudioAtEightKilohertzScalesOverlapAndTail() {
        let rate = 8_000.0
        let samples = [Float](repeating: s2Speech, count: 248_000) // 31 s at 8 kHz
        let chunks = Chunker.plan(samples: samples, sampleRate: rate)

        let hardLimit = 240_000 // floor(30 s * 8 kHz)
        let overlap = 4_000 // 0.5 s * 8 kHz
        let minFinal = 40_000 // 5 s * 8 kHz

        expectValidPlan(
            chunks,
            sampleCount: samples.count,
            hardLimitSamples: hardLimit,
            leadingOverlapSamples: overlap,
            maxChunkCount: 3
        )
        #expect(chunks.count == 2)
        guard chunks.count == 2 else { return }
        #expect(chunks[0].endReason == .hardFallback)
        // Tail rebalance pulls the hard boundary back so the tail keeps >= 5 s.
        #expect(chunks[0].ownedRange.upperBound == samples.count - minFinal)
        #expect(chunks[1].inferenceRange == 204_000..<248_000)
        #expect(chunks[1].inferenceRange.count >= minFinal)
    }

    // MARK: Low-energy fallback and ordering

    @Test
    func reliableLowEnergyDipBeatsHardFallback() {
        // Dip amplitude 0.04 stays above the non-speech threshold
        // max(0.0025, 0.08 * 0.4) = 0.032 (so no pause qualifies) but its
        // centered 200 ms windows reach 0.04 <= max(0.003, 0.12 * 0.4) = 0.048,
        // so the reliable low-energy boundary must beat the hard fallback.
        let samples = s2Waveform([
            (seconds: 26, amplitude: s2Speech),
            (seconds: 1, amplitude: 0.04),
            (seconds: 13, amplitude: s2Speech),
        ])
        #expect(samples.count == 640_000)

        let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())
        expectValidPlan(
            chunks,
            sampleCount: samples.count,
            hardLimitSamples: s2HardLimit16k,
            leadingOverlapSamples: s2LeadingOverlap16k,
            maxChunkCount: 3
        )

        #expect(chunks.count == 2)
        #expect(chunks[0].endReason == .lowEnergy)
        #expect(chunks[0].ownedRange.upperBound == 430_400) // lowest-RMS window nearest the 27 s target
        #expect(chunks[0].ownedRange.upperBound >= 416_000)
        #expect(chunks[0].ownedRange.upperBound <= 432_000)
        #expect(chunks[0].ownedRange.upperBound != s2HardLimit16k)
        #expect(!chunks[0].hasLeadingOverlap)
    }

    @Test
    func saferLowerRMSDipBeatsTargetCloserHigherRMSDip() {
        // Dip A (25.5-26.5 s, RMS 0.035) is safer but farther from the 27 s
        // target; dip B (26.8-27.8 s, RMS 0.045) is closer to the target but
        // higher energy. ADR-023 orders strictly lower RMS before proximity.
        let samples = s2Waveform([
            (seconds: 25.5, amplitude: s2Speech),
            (seconds: 1, amplitude: 0.035),
            (seconds: 0.3, amplitude: s2Speech),
            (seconds: 1, amplitude: 0.045),
            (seconds: 12.2, amplitude: s2Speech),
        ])
        #expect(samples.count == 640_000)

        let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())
        expectValidPlan(
            chunks,
            sampleCount: samples.count,
            hardLimitSamples: s2HardLimit16k,
            leadingOverlapSamples: s2LeadingOverlap16k,
            maxChunkCount: 3
        )

        #expect(chunks[0].endReason == .lowEnergy)
        #expect(chunks[0].ownedRange.upperBound == 422_400) // inside dip A
        #expect(chunks[0].ownedRange.upperBound >= 408_000)
        #expect(chunks[0].ownedRange.upperBound <= 424_000)
        #expect(chunks[0].ownedRange.upperBound < 428_800) // dip B must lose despite target proximity
    }

    @Test
    func pauseBeatsLowEnergyWhenBothExist() {
        // Both a reliable low-energy dip and a qualifying >= 240 ms pause sit
        // inside the search window; the pause tier must win.
        let samples = s2Waveform([
            (seconds: 25.5, amplitude: s2Speech),
            (seconds: 1, amplitude: 0.035),
            (seconds: 0.5, amplitude: s2Speech),
            (seconds: 0.5, amplitude: s2Silence),
            (seconds: 12.5, amplitude: s2Speech),
        ])
        #expect(samples.count == 640_000)

        let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())
        expectValidPlan(
            chunks,
            sampleCount: samples.count,
            hardLimitSamples: s2HardLimit16k,
            leadingOverlapSamples: s2LeadingOverlap16k,
            maxChunkCount: 3
        )

        #expect(chunks[0].endReason == .pause)
        #expect(chunks[0].ownedRange.upperBound == 432_000) // inside the silence, not the dip
        #expect(chunks[0].ownedRange.upperBound >= 432_000)
        #expect(chunks[0].ownedRange.upperBound <= 440_000)
        #expect(!chunks[0].hasLeadingOverlap)
    }

    @Test
    func dipJustAboveReliabilityThresholdReachesHardFallback() {
        // Dip amplitude 0.05 exceeds the low-energy acceptance threshold
        // max(0.003, 0.12 * 0.4) = 0.048 and the non-speech threshold, so no
        // boundary qualifies and the hard fallback must be used.
        let samples = s2Waveform([
            (seconds: 26, amplitude: s2Speech),
            (seconds: 1, amplitude: 0.05),
            (seconds: 13, amplitude: s2Speech),
        ])
        #expect(samples.count == 640_000)

        let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig())
        expectValidPlan(
            chunks,
            sampleCount: samples.count,
            hardLimitSamples: s2HardLimit16k,
            leadingOverlapSamples: s2LeadingOverlap16k,
            maxChunkCount: 3
        )

        #expect(chunks.count == 2)
        #expect(chunks[0].endReason == .hardFallback)
        #expect(chunks[0].ownedRange.upperBound == s2HardLimit16k)
        #expect(chunks[1].hasLeadingOverlap)
    }

    // MARK: Invalid and extreme configuration

    @Test
    func invalidConfigurationsCannotTrapOrExceedNormalizedThirtySeconds() {
        // 40 s of constant speech at 100 Hz keeps allocations tiny while still
        // exceeding the normalized 30 s cap (3000 samples).
        let rate = 100.0
        let samples = [Float](repeating: s2Speech, count: 4_000)
        let hardLimit = 3_000 // floor(30 s * 100 Hz)
        let overlap = 50 // 0.5 s * 100 Hz
        let minFinal = 500 // 5 s * 100 Hz

        let configurations: [ChunkerConfig] = [
            ChunkerConfig(sampleRate: rate, maxChunkSeconds: .nan),
            ChunkerConfig(sampleRate: rate, maxChunkSeconds: .infinity),
            ChunkerConfig(sampleRate: rate, maxChunkSeconds: -.infinity),
            ChunkerConfig(sampleRate: rate, maxChunkSeconds: 0),
            ChunkerConfig(sampleRate: rate, maxChunkSeconds: -5),
            ChunkerConfig(sampleRate: rate, maxChunkSeconds: 31),
            ChunkerConfig(sampleRate: rate, maxChunkSeconds: 1_000),
            ChunkerConfig(sampleRate: rate, targetChunkSeconds: .nan),
            ChunkerConfig(sampleRate: rate, targetChunkSeconds: -1),
            ChunkerConfig(sampleRate: rate, targetChunkSeconds: .infinity),
            ChunkerConfig(sampleRate: rate, minChunkSeconds: .nan),
            ChunkerConfig(sampleRate: rate, minChunkSeconds: 0),
            ChunkerConfig(sampleRate: rate, minChunkSeconds: -3),
            ChunkerConfig(sampleRate: rate, preferredBandEndSeconds: .nan),
            ChunkerConfig(sampleRate: rate, preferredBandEndSeconds: -2),
            ChunkerConfig(sampleRate: rate, frameDurationSeconds: .nan),
            ChunkerConfig(sampleRate: rate, frameDurationSeconds: 0),
            ChunkerConfig(sampleRate: rate, frameDurationSeconds: -0.5),
            ChunkerConfig(sampleRate: rate, frameDurationSeconds: .infinity),
            ChunkerConfig(sampleRate: rate, hopDurationSeconds: .nan),
            ChunkerConfig(sampleRate: rate, hopDurationSeconds: 0),
            ChunkerConfig(sampleRate: rate, hopDurationSeconds: -1),
            ChunkerConfig(sampleRate: rate, minSilenceSeconds: .nan),
            ChunkerConfig(sampleRate: rate, minSilenceSeconds: -0.1),
            ChunkerConfig(sampleRate: rate, lowEnergyWindowSeconds: .nan),
            ChunkerConfig(sampleRate: rate, lowEnergyWindowSeconds: -0.2),
            ChunkerConfig(sampleRate: rate, leadingOverlapSeconds: .nan),
            ChunkerConfig(sampleRate: rate, leadingOverlapSeconds: -0.5),
            ChunkerConfig(sampleRate: rate, leadingOverlapSeconds: .infinity),
            ChunkerConfig(sampleRate: rate, minFinalInferenceSeconds: .nan),
            ChunkerConfig(sampleRate: rate, minFinalInferenceSeconds: 0),
            ChunkerConfig(sampleRate: rate, minFinalInferenceSeconds: -5),
            ChunkerConfig(sampleRate: rate, nonSpeechFloorRMS: .nan),
            ChunkerConfig(sampleRate: rate, nonSpeechFloorRMS: -1),
            ChunkerConfig(sampleRate: rate, nonSpeechPeakScale: .infinity),
            ChunkerConfig(sampleRate: rate, nonSpeechPeakScale: -0.5),
            ChunkerConfig(sampleRate: rate, lowEnergyFloorRMS: .nan),
            ChunkerConfig(sampleRate: rate, lowEnergyPeakScale: -2),
        ]

        for (index, configuration) in configurations.enumerated() {
            let chunks = Chunker.plan(samples: samples, configuration: configuration)
            expectValidPlan(
                chunks,
                sampleCount: samples.count,
                hardLimitSamples: hardLimit,
                leadingOverlapSamples: overlap,
                maxChunkCount: 4
            )
            #expect(
                chunks.count >= 2,
                "configuration \(index) must still split 40 s of audio at the normalized 30 s cap"
            )
            #expect(
                chunks.allSatisfy { $0.inferenceRange.count <= hardLimit },
                "configuration \(index) exceeded the normalized 30 s inference cap"
            )
            if let last = chunks.last {
                #expect(
                    last.inferenceRange.count >= minFinal,
                    "configuration \(index) lost the 5 s final-inference guarantee"
                )
            }
        }
    }

    @Test
    func extremeSampleRatesNormalizeSafely() {
        // A huge-but-accepted finite rate must not explode allocations: the
        // short input simply fits in one chunk.
        let tiny = [Float](repeating: s2Speech, count: 1_000)
        let hugeChunks = Chunker.plan(samples: tiny, configuration: ChunkerConfig(sampleRate: 1_000_000_000))
        #expect(hugeChunks.count == 1)
        #expect(hugeChunks.first?.ownedRange == 0..<1_000)
        #expect(hugeChunks.first?.inferenceRange == 0..<1_000)

        // Rates beyond the ceiling, non-positive, or non-finite normalize to
        // 16 kHz, where 31 s of speech plans exactly like the 16 kHz contract.
        for badRate in [1.0e12, 0.0, -16_000.0, Double.nan, Double.infinity] {
            let samples = [Float](repeating: s2Speech, count: 496_000) // 31 s at 16 kHz
            let chunks = Chunker.plan(samples: samples, configuration: ChunkerConfig(sampleRate: badRate))
            expectValidPlan(
                chunks,
                sampleCount: samples.count,
                hardLimitSamples: s2HardLimit16k,
                leadingOverlapSamples: s2LeadingOverlap16k,
                maxChunkCount: 3
            )
            #expect(chunks.count == 2, "rate \(badRate) must normalize and split 31 s into two chunks")
            guard chunks.count == 2 else { continue }
            #expect(chunks[0].endReason == .hardFallback)
            #expect(chunks[0].ownedRange.upperBound == 416_000) // tail rebalance keeps >= 5 s
            #expect(chunks[1].inferenceRange == 408_000..<496_000)
        }

        // The convenience entry point also caps maxChunkSeconds at 30.
        let convenienceChunks = Chunker.plan(
            samples: [Float](repeating: s2Speech, count: 496_000),
            sampleRate: 16_000,
            maxChunkSeconds: 1_000
        )
        expectValidPlan(
            convenienceChunks,
            sampleCount: 496_000,
            hardLimitSamples: s2HardLimit16k,
            leadingOverlapSamples: s2LeadingOverlap16k,
            maxChunkCount: 3
        )
        #expect(convenienceChunks.count == 2)
        #expect(convenienceChunks.allSatisfy { $0.inferenceRange.count <= s2HardLimit16k })
    }

    // MARK: Token overlap merge (hard-fallback dedup)

    @Test
    func tokenMergeRemovesExactTwoFiveEightMatches() {
        var two = [1, 2, 3, 4]
        GigaAMTokenOverlapMerger.merge(into: &two, incoming: [3, 4, 5, 6], hasLeadingOverlap: true)
        #expect(two == [1, 2, 3, 4, 5, 6])

        var five = [1, 2, 3, 4, 5, 6, 7]
        GigaAMTokenOverlapMerger.merge(into: &five, incoming: [3, 4, 5, 6, 7, 8, 9], hasLeadingOverlap: true)
        #expect(five == [1, 2, 3, 4, 5, 6, 7, 8, 9])

        var eight = [1, 2, 3, 4, 5, 6, 7, 8]
        GigaAMTokenOverlapMerger.merge(into: &eight, incoming: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], hasLeadingOverlap: true)
        #expect(eight == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    }

    @Test
    func tokenMergeNeverRemovesMoreThanEightTokens() {
        // An exact 9-token suffix/prefix match exceeds the 8-token cap, so the
        // merger must conservatively remove nothing.
        var nine = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        GigaAMTokenOverlapMerger.merge(into: &nine, incoming: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], hasLeadingOverlap: true)
        #expect(nine == [1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])

        // An exact 8-token match still removes exactly eight.
        var eight = [0, 1, 2, 3, 4, 5, 6, 7, 8]
        GigaAMTokenOverlapMerger.merge(into: &eight, incoming: [1, 2, 3, 4, 5, 6, 7, 8, 9], hasLeadingOverlap: true)
        #expect(eight == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
    }

    @Test
    func tokenMergeLongestMatchWins() {
        // Both a 2-token and a 4-token suffix/prefix match exist; the longest
        // exact match must be the one removed.
        var accumulated = [9, 1, 2, 1, 2]
        GigaAMTokenOverlapMerger.merge(into: &accumulated, incoming: [1, 2, 1, 2, 7], hasLeadingOverlap: true)
        #expect(accumulated == [9, 1, 2, 1, 2, 7])
    }

    @Test
    func tokenMergeNegativeCasesPreserveIncomingTokens() {
        // A 1-token match is below the 2-token minimum.
        var one = [1, 2, 3]
        GigaAMTokenOverlapMerger.merge(into: &one, incoming: [3, 4], hasLeadingOverlap: true)
        #expect(one == [1, 2, 3, 3, 4])

        // Interior-only repetition is not a suffix/prefix match.
        var interior = [1, 2, 3, 4]
        GigaAMTokenOverlapMerger.merge(into: &interior, incoming: [5, 2, 3, 6], hasLeadingOverlap: true)
        #expect(interior == [1, 2, 3, 4, 5, 2, 3, 6])

        // Reversed order is not a match.
        var reversed = [1, 2, 3, 4]
        GigaAMTokenOverlapMerger.merge(into: &reversed, incoming: [4, 3, 2, 1], hasLeadingOverlap: true)
        #expect(reversed == [1, 2, 3, 4, 4, 3, 2, 1])

        // Plain mismatch appends everything.
        var mismatch = [1, 2, 3]
        GigaAMTokenOverlapMerger.merge(into: &mismatch, incoming: [7, 8, 9], hasLeadingOverlap: true)
        #expect(mismatch == [1, 2, 3, 7, 8, 9])

        // An exact match without leading overlap must not deduplicate.
        var noOverlap = [1, 2, 3, 4]
        GigaAMTokenOverlapMerger.merge(into: &noOverlap, incoming: [3, 4, 5], hasLeadingOverlap: false)
        #expect(noOverlap == [1, 2, 3, 4, 3, 4, 5])
    }

    @Test
    func tokenMergeEmptySidesAreNoOps() {
        var emptyIncoming = [1, 2, 3]
        GigaAMTokenOverlapMerger.merge(into: &emptyIncoming, incoming: [], hasLeadingOverlap: true)
        #expect(emptyIncoming == [1, 2, 3])

        var emptyAccumulated: [Int] = []
        GigaAMTokenOverlapMerger.merge(into: &emptyAccumulated, incoming: [1, 2, 3], hasLeadingOverlap: true)
        #expect(emptyAccumulated == [1, 2, 3])
    }
}
