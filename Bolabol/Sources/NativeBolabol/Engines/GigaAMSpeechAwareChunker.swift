import Foundation

// MARK: - Strategy & Architecture
//
// ADR-023: Offline Speech-Aware GigaAM Audio Segmentation
//
// GigaAM v3 RNNT Core ML operates within a fixed 30-second window capacity (480,000 samples at 16 kHz).
// Mechanical fixed-offset slicing at arbitrary 30-second intervals risks bisecting active speech
// mid-utterance, causing token loss, repetition, or corruption across segment seams.
//
// To guarantee deterministic offline behavior without relying on runtime-downloaded VAD neural networks
// (such as FluidAudio's VadManager cache dependencies), Bolabol uses a pure, model-free speech-activity planner:
//   1. Single-pass 20 ms RMS frame analysis with energy prefix sums for O(1) interval queries.
//   2. Boundary selection hierarchy:
//      - Qualifying non-speech pause (>= 240 ms silence) nearest the 27-second target.
//      - Otherwise, reliable 200 ms low-energy window (<= max(0.003, 0.12 * peakRMS)).
//        Candidate ordering: preferred 25–28s band first, strictly lower RMS first within band,
//        proximity to 27s target for RMS ties, and earlier sample index for exact ties.
//      - Otherwise, hard capacity fallback with 500 ms leading overlap on the subsequent chunk.
//   3. Ownership ranges strictly partition the entire source audio [0..<sampleCount] without gaps or duplicates.
//   4. Inference ranges are bounded by [0..<sampleCount], never exceed 30 seconds, and end at owned upper bounds.
//   5. Tail rebalancing prevents microchunks by guaranteeing >= 5 seconds final inference where mathematically possible.
//   6. In-place token deduplication removes the longest matching 2–8 token suffix/prefix only on hard-overlap chunks.

// MARK: - GigaAMSpeechAwareChunker

/// Pure value-type segmentation planner for GigaAM Russian ASR.
internal enum GigaAMSpeechAwareChunker {

    // MARK: - Configuration

    /// Parameters controlling boundary search, energy thresholds, and overlap behavior.
    internal struct Configuration: Equatable, Sendable {
        internal var sampleRate: Double
        internal var targetChunkSeconds: Double
        internal var minChunkSeconds: Double
        internal var preferredBandEndSeconds: Double
        internal var maxChunkSeconds: Double
        internal var frameDurationSeconds: Double
        internal var hopDurationSeconds: Double
        internal var minSilenceSeconds: Double
        internal var lowEnergyWindowSeconds: Double
        internal var leadingOverlapSeconds: Double
        internal var minFinalInferenceSeconds: Double
        internal var nonSpeechFloorRMS: Float
        internal var nonSpeechPeakScale: Float
        internal var lowEnergyFloorRMS: Float
        internal var lowEnergyPeakScale: Float

        internal init(
            sampleRate: Double = 16_000.0,
            targetChunkSeconds: Double = 27.0,
            minChunkSeconds: Double = 25.0,
            preferredBandEndSeconds: Double = 28.0,
            maxChunkSeconds: Double = 30.0,
            frameDurationSeconds: Double = 0.020,
            hopDurationSeconds: Double = 0.020,
            minSilenceSeconds: Double = 0.240,
            lowEnergyWindowSeconds: Double = 0.200,
            leadingOverlapSeconds: Double = 0.500,
            minFinalInferenceSeconds: Double = 5.0,
            nonSpeechFloorRMS: Float = 0.0025,
            nonSpeechPeakScale: Float = 0.08,
            lowEnergyFloorRMS: Float = 0.003,
            lowEnergyPeakScale: Float = 0.12
        ) {
            self.sampleRate = sampleRate
            self.targetChunkSeconds = targetChunkSeconds
            self.minChunkSeconds = minChunkSeconds
            self.preferredBandEndSeconds = preferredBandEndSeconds
            self.maxChunkSeconds = maxChunkSeconds
            self.frameDurationSeconds = frameDurationSeconds
            self.hopDurationSeconds = hopDurationSeconds
            self.minSilenceSeconds = minSilenceSeconds
            self.lowEnergyWindowSeconds = lowEnergyWindowSeconds
            self.leadingOverlapSeconds = leadingOverlapSeconds
            self.minFinalInferenceSeconds = minFinalInferenceSeconds
            self.nonSpeechFloorRMS = nonSpeechFloorRMS
            self.nonSpeechPeakScale = nonSpeechPeakScale
            self.lowEnergyFloorRMS = lowEnergyFloorRMS
            self.lowEnergyPeakScale = lowEnergyPeakScale
        }

        /// Returns a fully normalized configuration where all rates and durations are finite,
        /// semantically ordered, bounded by the 30.0-second hard ceiling, and safe against arithmetic traps.
        internal func normalized() -> Configuration {
            // 1. Sample rate: positive, finite, reasonable upper ceiling.
            let normRate: Double
            if sampleRate.isFinite && sampleRate > 0 && sampleRate <= 1_000_000_000.0 {
                normRate = sampleRate
            } else {
                normRate = 16_000.0
            }

            // 2. Max chunk seconds: absolute hard maximum <= 30.0.
            let normMax: Double
            if maxChunkSeconds.isFinite && maxChunkSeconds > 0 {
                normMax = min(maxChunkSeconds, 30.0)
            } else {
                normMax = 30.0
            }

            // 3. Min chunk seconds: 0 < min <= max.
            let normMin: Double
            if minChunkSeconds.isFinite && minChunkSeconds > 0 {
                normMin = min(minChunkSeconds, normMax)
            } else {
                normMin = min(25.0, normMax)
            }

            // 4. Target chunk seconds: min <= target <= max.
            let normTarget: Double
            if targetChunkSeconds.isFinite && targetChunkSeconds > 0 {
                normTarget = min(max(normMin, targetChunkSeconds), normMax)
            } else {
                normTarget = min(max(normMin, 27.0), normMax)
            }

            // 5. Preferred band end seconds: target <= preferred <= max.
            let normPreferred: Double
            if preferredBandEndSeconds.isFinite && preferredBandEndSeconds > 0 {
                normPreferred = min(max(normTarget, preferredBandEndSeconds), normMax)
            } else {
                normPreferred = min(max(normTarget, 28.0), normMax)
            }

            // 6. Min final inference seconds: 0 < final <= min.
            let normFinal: Double
            if minFinalInferenceSeconds.isFinite && minFinalInferenceSeconds > 0 {
                normFinal = min(minFinalInferenceSeconds, normMin)
            } else {
                normFinal = min(5.0, normMin)
            }

            // 7. Leading overlap seconds: 0 <= overlap <= final.
            let normOverlap: Double
            if leadingOverlapSeconds.isFinite && leadingOverlapSeconds >= 0 {
                normOverlap = min(leadingOverlapSeconds, normFinal)
            } else {
                normOverlap = min(0.500, normFinal)
            }

            // 8. Frame and hop duration seconds: positive, finite, bounded.
            let normFrame: Double
            if frameDurationSeconds.isFinite && frameDurationSeconds > 0 {
                normFrame = min(frameDurationSeconds, normMax)
            } else {
                normFrame = min(0.020, normMax)
            }

            let normHop: Double
            if hopDurationSeconds.isFinite && hopDurationSeconds > 0 {
                normHop = min(hopDurationSeconds, normFrame)
            } else {
                normHop = min(0.020, normFrame)
            }

            // 9. Analysis window durations: non-negative, finite, bounded.
            let normSilence: Double
            if minSilenceSeconds.isFinite && minSilenceSeconds >= 0 {
                normSilence = min(minSilenceSeconds, normMax)
            } else {
                normSilence = min(0.240, normMax)
            }

            let normLowEnergyWin: Double
            if lowEnergyWindowSeconds.isFinite && lowEnergyWindowSeconds >= 0 {
                normLowEnergyWin = min(lowEnergyWindowSeconds, normMax)
            } else {
                normLowEnergyWin = min(0.200, normMax)
            }

            // 10. Energy thresholds & scales: non-negative, finite.
            let normNonSpeechFloor = (nonSpeechFloorRMS.isFinite && nonSpeechFloorRMS >= 0) ? nonSpeechFloorRMS : 0.0025
            let normNonSpeechScale = (nonSpeechPeakScale.isFinite && nonSpeechPeakScale >= 0) ? nonSpeechPeakScale : 0.08
            let normLowEnergyFloor = (lowEnergyFloorRMS.isFinite && lowEnergyFloorRMS >= 0) ? lowEnergyFloorRMS : 0.003
            let normLowEnergyScale = (lowEnergyPeakScale.isFinite && lowEnergyPeakScale >= 0) ? lowEnergyPeakScale : 0.12

            return Configuration(
                sampleRate: normRate,
                targetChunkSeconds: normTarget,
                minChunkSeconds: normMin,
                preferredBandEndSeconds: normPreferred,
                maxChunkSeconds: normMax,
                frameDurationSeconds: normFrame,
                hopDurationSeconds: normHop,
                minSilenceSeconds: normSilence,
                lowEnergyWindowSeconds: normLowEnergyWin,
                leadingOverlapSeconds: normOverlap,
                minFinalInferenceSeconds: normFinal,
                nonSpeechFloorRMS: normNonSpeechFloor,
                nonSpeechPeakScale: normNonSpeechScale,
                lowEnergyFloorRMS: normLowEnergyFloor,
                lowEnergyPeakScale: normLowEnergyScale
            )
        }
    }

    // MARK: - Chunk

    /// Audio segment containing distinct ownership and inference ranges.
    internal struct Chunk: Equatable, Sendable {
        /// Non-overlapping source range owned by this chunk.
        /// The sequence of owned ranges forms an exact partition of `0..<samples.count`.
        internal let ownedRange: Range<Int>

        /// Range of samples passed to inference / frontend.
        /// Always ends at `ownedRange.upperBound` and is bounded by `[0, samples.count]`.
        /// May extend earlier than `ownedRange.lowerBound` by at most leading overlap samples.
        internal let inferenceRange: Range<Int>

        /// Reason why this boundary was selected.
        internal let endReason: EndReason

        /// Derived flag indicating if this chunk has leading overlap from a previous hard fallback.
        internal var hasLeadingOverlap: Bool {
            inferenceRange.lowerBound < ownedRange.lowerBound
        }

        internal enum EndReason: String, Equatable, Sendable {
            case singleChunk
            case pause
            case lowEnergy
            case hardFallback
            case terminalRemaining
        }
    }

    // MARK: - Planning API

    /// Convenience planning entry point using sample rate and max chunk seconds.
    internal static func plan(
        samples: [Float],
        sampleRate: Double = 16_000.0,
        maxChunkSeconds: Double = 30.0
    ) -> [Chunk] {
        let config = Configuration(
            sampleRate: sampleRate,
            maxChunkSeconds: maxChunkSeconds
        )
        return plan(samples: samples, configuration: config)
    }

    /// Primary segmentation planner producing ordered, bounded chunks.
    internal static func plan(
        samples: [Float],
        configuration: Configuration
    ) -> [Chunk] {
        guard !samples.isEmpty else { return [] }

        let config = configuration.normalized()
        let rate = config.sampleRate
        let hardLimitSamples = safeFloorSampleCount(seconds: config.maxChunkSeconds, rate: rate)

        // Short path: audio fits entirely within one inference window.
        if samples.count <= hardLimitSamples {
            return [
                Chunk(
                    ownedRange: 0..<samples.count,
                    inferenceRange: 0..<samples.count,
                    endReason: .singleChunk
                )
            ]
        }

        // Long path: single-pass frame activity analysis.
        let analysis = FrameAnalysis(samples: samples, rate: rate, configuration: config)
        return planChunks(
            sampleCount: samples.count,
            rate: rate,
            hardLimitSamples: hardLimitSamples,
            configuration: config,
            analysis: analysis
        )
    }

    // MARK: - Safe Arithmetic Helpers

    internal static func safeFloorSampleCount(seconds: Double, rate: Double) -> Int {
        guard seconds.isFinite, rate.isFinite, seconds > 0, rate > 0 else { return 1 }
        let prod = seconds * rate
        guard prod.isFinite, prod >= 1.0, prod < Double(Int.max) else { return 1 }
        return max(1, Int(floor(prod)))
    }

    internal static func safeRoundSampleCount(seconds: Double, rate: Double, minBound: Int = 1) -> Int {
        guard seconds.isFinite, rate.isFinite, seconds > 0, rate > 0 else { return minBound }
        let prod = seconds * rate
        guard prod.isFinite, prod >= 0, prod < Double(Int.max) else { return minBound }
        return max(minBound, Int(round(prod)))
    }

    // MARK: - Frame Analysis

    private struct FrameAnalysis {
        let frameSamples: Int
        let hopSamples: Int
        let frameCount: Int
        let frameRMS: [Float]
        let energyPrefixSums: [Double]
        let peakFrameRMS: Float
        let isNonSpeech: [Bool]
        let nonSpeechRuns: [(startFrame: Int, endFrame: Int)]

        init(samples: [Float], rate: Double, configuration: Configuration) {
            let frameSamples = GigaAMSpeechAwareChunker.safeRoundSampleCount(
                seconds: configuration.frameDurationSeconds,
                rate: rate,
                minBound: 1
            )
            let hopSamples = GigaAMSpeechAwareChunker.safeRoundSampleCount(
                seconds: configuration.hopDurationSeconds,
                rate: rate,
                minBound: 1
            )
            let frameCount = max(1, (samples.count + hopSamples - 1) / hopSamples)

            var frameRMS = [Float](repeating: 0, count: frameCount)
            var energyPrefixSums = [Double](repeating: 0, count: frameCount + 1)
            var peakRMS: Float = 0

            var prefixAcc: Double = 0
            energyPrefixSums[0] = 0

            for f in 0..<frameCount {
                let start = f * hopSamples
                let end = min(start + frameSamples, samples.count)
                let count = end - start
                var sumSq: Double = 0
                if count > 0 {
                    for i in start..<end {
                        let v = samples[i]
                        if v.isFinite {
                            // Convert to Double before multiplication to prevent Float overflow on large finite samples.
                            let d = Double(v)
                            sumSq += d * d
                        }
                    }
                }
                let meanSq = count > 0 ? sumSq / Double(count) : 0
                let rms = Float(sqrt(max(0, meanSq)))
                let validRMS = rms.isFinite ? rms : 0
                frameRMS[f] = validRMS
                peakRMS = max(peakRMS, validRMS)

                prefixAcc += sumSq
                energyPrefixSums[f + 1] = prefixAcc
            }

            self.frameSamples = frameSamples
            self.hopSamples = hopSamples
            self.frameCount = frameCount
            self.frameRMS = frameRMS
            self.energyPrefixSums = energyPrefixSums
            self.peakFrameRMS = peakRMS

            let speechThreshold = max(
                configuration.nonSpeechFloorRMS,
                configuration.nonSpeechPeakScale * peakRMS
            )
            var isNonSpeech = [Bool](repeating: false, count: frameCount)
            for f in 0..<frameCount {
                isNonSpeech[f] = frameRMS[f] < speechThreshold
            }
            self.isNonSpeech = isNonSpeech

            let minSilenceFrames = max(
                1,
                Int(ceil(configuration.minSilenceSeconds / max(1e-6, configuration.frameDurationSeconds)))
            )
            var runs: [(startFrame: Int, endFrame: Int)] = []
            var runStart: Int?

            for f in 0..<frameCount {
                if isNonSpeech[f] {
                    if runStart == nil { runStart = f }
                } else {
                    if let start = runStart {
                        if f - start >= minSilenceFrames {
                            runs.append((startFrame: start, endFrame: f))
                        }
                        runStart = nil
                    }
                }
            }
            if let start = runStart, frameCount - start >= minSilenceFrames {
                runs.append((startFrame: start, endFrame: frameCount))
            }
            self.nonSpeechRuns = runs
        }

        func windowRMS(startFrame: Int, endFrame: Int, totalSamples: Int) -> Float {
            let sf = max(0, min(startFrame, frameCount))
            let ef = max(sf, min(endFrame, frameCount))
            if ef <= sf { return 0 }

            let sumSq = max(0, energyPrefixSums[ef] - energyPrefixSums[sf])
            let startSample = sf * hopSamples
            let endSample = min(ef * hopSamples, totalSamples)
            let sampleCount = max(1, endSample - startSample)
            let rms = Float(sqrt(sumSq / Double(sampleCount)))
            return rms.isFinite ? rms : 0
        }
    }

    // MARK: - Multi-Chunk Loop

    private static func planChunks(
        sampleCount: Int,
        rate: Double,
        hardLimitSamples: Int,
        configuration: Configuration,
        analysis: FrameAnalysis
    ) -> [Chunk] {
        var chunks: [Chunk] = []
        var currentOwnedStart = 0
        var hasLeadingOverlap = false

        let leadingOverlapSamples = safeRoundSampleCount(
            seconds: configuration.leadingOverlapSeconds,
            rate: rate,
            minBound: 0
        )
        let minFinalInferenceSamples = safeRoundSampleCount(
            seconds: configuration.minFinalInferenceSeconds,
            rate: rate,
            minBound: 1
        )
        let targetAdvanceSamples = safeRoundSampleCount(
            seconds: configuration.targetChunkSeconds,
            rate: rate,
            minBound: 1
        )
        let minAdvanceSamples = safeRoundSampleCount(
            seconds: configuration.minChunkSeconds,
            rate: rate,
            minBound: 1
        )
        let preferredBandEndAdvanceSamples = max(
            minAdvanceSamples,
            safeRoundSampleCount(
                seconds: configuration.preferredBandEndSeconds,
                rate: rate,
                minBound: minAdvanceSamples
            )
        )

        let lowEnergyWindowFrames = max(
            1,
            Int(round(configuration.lowEnergyWindowSeconds / max(1e-6, configuration.frameDurationSeconds)))
        )
        let halfWindow = lowEnergyWindowFrames / 2
        let lowEnergyThreshold = max(
            configuration.lowEnergyFloorRMS,
            configuration.lowEnergyPeakScale * analysis.peakFrameRMS
        )

        while currentOwnedStart < sampleCount {
            let overlapSamples = hasLeadingOverlap ? leadingOverlapSamples : 0
            let inferenceStart = max(0, currentOwnedStart - overlapSamples)

            let maxInferenceEnd = inferenceStart + hardLimitSamples
            let maxCapacityOwnedEnd = min(sampleCount, maxInferenceEnd)
            let remainingSamples = sampleCount - currentOwnedStart

            // If remaining audio fits entirely within the current chunk's inference capacity, finish.
            if remainingSamples <= (maxCapacityOwnedEnd - currentOwnedStart) {
                let chunk = Chunk(
                    ownedRange: currentOwnedStart..<sampleCount,
                    inferenceRange: inferenceStart..<sampleCount,
                    endReason: chunks.isEmpty ? .singleChunk : .terminalRemaining
                )
                chunks.append(chunk)
                break
            }

            // Tail protection: rebalance boundary if taking maxCapacity would leave < 5s tail.
            var maxAllowedOwnedEnd = maxCapacityOwnedEnd
            if sampleCount - maxAllowedOwnedEnd < minFinalInferenceSamples {
                let maxWithTail = sampleCount - minFinalInferenceSamples
                if maxWithTail > currentOwnedStart {
                    maxAllowedOwnedEnd = min(maxAllowedOwnedEnd, maxWithTail)
                }
            }

            let searchMaxOwnedEnd = max(currentOwnedStart + 1, maxAllowedOwnedEnd)
            let minAdvance = min(minAdvanceSamples, searchMaxOwnedEnd - currentOwnedStart)
            let searchMinOwnedEnd = max(currentOwnedStart + 1, min(searchMaxOwnedEnd, currentOwnedStart + minAdvance))

            let targetEnd = currentOwnedStart + targetAdvanceSamples
            let targetOwnedEnd = max(searchMinOwnedEnd, min(searchMaxOwnedEnd, targetEnd))

            let prefBandEnd = currentOwnedStart + preferredBandEndAdvanceSamples
            let preferredBandEnd = max(searchMinOwnedEnd, min(searchMaxOwnedEnd, prefBandEnd))

            var chosenOwnedEnd: Int?
            var chosenReason: Chunk.EndReason = .hardFallback

            // Tier 1: Non-speech pause interval (>= 240 ms).
            var bestPauseCandidate: Int?
            var bestPauseInBand = false
            var bestPauseDistance = Int.max

            for run in analysis.nonSpeechRuns {
                let runStartSample = run.startFrame * analysis.hopSamples
                let runEndSample = min(sampleCount, run.endFrame * analysis.hopSamples)

                let validStart = max(runStartSample, searchMinOwnedEnd)
                let validEnd = min(runEndSample, searchMaxOwnedEnd)
                guard validStart <= validEnd else { continue }

                let candidateSample = min(max(validStart, targetOwnedEnd), validEnd)
                let inBand = candidateSample <= preferredBandEnd
                let distance = abs(candidateSample - targetOwnedEnd)

                var isBetter = false
                if bestPauseCandidate == nil {
                    isBetter = true
                } else if inBand && !bestPauseInBand {
                    isBetter = true
                } else if inBand == bestPauseInBand {
                    if distance < bestPauseDistance {
                        isBetter = true
                    } else if distance == bestPauseDistance, let currentBest = bestPauseCandidate, candidateSample < currentBest {
                        isBetter = true
                    }
                }

                if isBetter {
                    bestPauseCandidate = candidateSample
                    bestPauseInBand = inBand
                    bestPauseDistance = distance
                }
            }

            if let pauseEnd = bestPauseCandidate {
                chosenOwnedEnd = pauseEnd
                chosenReason = .pause
            }

            // Tier 2: Reliable low-energy window (200 ms).
            // ADR-023 ranking: preferred 25-28s band first, strictly lower RMS first within band,
            // proximity to 27s target for RMS ties, and earlier sample index for exact ties.
            if chosenOwnedEnd == nil {
                var bestLowEnergyCandidate: Int?
                var bestLowEnergyInBand = false
                var bestLowEnergyRMS: Float = .infinity
                var bestLowEnergyDistance = Int.max

                let startFrame = searchMinOwnedEnd / analysis.hopSamples
                let endFrame = min(analysis.frameCount, (searchMaxOwnedEnd + analysis.hopSamples - 1) / analysis.hopSamples)

                if startFrame <= endFrame {
                    for f in startFrame...endFrame {
                        let sampleOffset = min(sampleCount, f * analysis.hopSamples)
                        guard sampleOffset >= searchMinOwnedEnd && sampleOffset <= searchMaxOwnedEnd else { continue }

                        let sf = max(0, f - halfWindow)
                        let ef = min(analysis.frameCount, f + halfWindow)
                        let winRMS = analysis.windowRMS(startFrame: sf, endFrame: ef, totalSamples: sampleCount)

                        guard winRMS <= lowEnergyThreshold else { continue }

                        let inBand = sampleOffset <= preferredBandEnd
                        let distance = abs(sampleOffset - targetOwnedEnd)

                        var isBetter = false
                        if bestLowEnergyCandidate == nil {
                            isBetter = true
                        } else if inBand && !bestLowEnergyInBand {
                            isBetter = true
                        } else if inBand == bestLowEnergyInBand {
                            if winRMS < bestLowEnergyRMS {
                                isBetter = true
                            } else if winRMS == bestLowEnergyRMS {
                                if distance < bestLowEnergyDistance {
                                    isBetter = true
                                } else if distance == bestLowEnergyDistance, let currentBest = bestLowEnergyCandidate, sampleOffset < currentBest {
                                    isBetter = true
                                }
                            }
                        }

                        if isBetter {
                            bestLowEnergyCandidate = sampleOffset
                            bestLowEnergyInBand = inBand
                            bestLowEnergyRMS = winRMS
                            bestLowEnergyDistance = distance
                        }
                    }
                }

                if let lowEnergyEnd = bestLowEnergyCandidate {
                    chosenOwnedEnd = lowEnergyEnd
                    chosenReason = .lowEnergy
                }
            }

            // Tier 3: Continuous-speech hard fallback.
            let finalOwnedEnd = chosenOwnedEnd ?? searchMaxOwnedEnd
            let finalReason = chosenOwnedEnd != nil ? chosenReason : .hardFallback

            let chunk = Chunk(
                ownedRange: currentOwnedStart..<finalOwnedEnd,
                inferenceRange: inferenceStart..<finalOwnedEnd,
                endReason: finalReason
            )
            chunks.append(chunk)

            hasLeadingOverlap = (finalReason == .hardFallback)
            currentOwnedStart = finalOwnedEnd
        }

        return chunks
    }
}

// MARK: - GigaAMTokenOverlapMerger

/// Pure token deduplication utility for hard-overlap GigaAM boundaries.
internal enum GigaAMTokenOverlapMerger {
    internal static let minMatchLength: Int = 2
    internal static let maxMatchLength: Int = 8

    /// Merges incoming chunk tokens into `accumulated` in place, deduplicating only when `hasLeadingOverlap` is true.
    ///
    /// Longest exact token match between accumulated suffix and incoming prefix (lengths 8 down to 2)
    /// is removed from incoming tokens before appending. Non-overlap chunks, negative cases,
    /// 1-token matches, and no-match cases append `incoming` directly without copying `accumulated`.
    internal static func merge(
        into accumulated: inout [Int],
        incoming: [Int],
        hasLeadingOverlap: Bool
    ) {
        guard !incoming.isEmpty else { return }

        guard hasLeadingOverlap, !accumulated.isEmpty else {
            accumulated.append(contentsOf: incoming)
            return
        }

        let maxK = min(maxMatchLength, accumulated.count, incoming.count)
        if maxK >= minMatchLength {
            for k in stride(from: maxK, through: minMatchLength, by: -1) {
                let suffix = accumulated[(accumulated.count - k)...]
                let prefix = incoming[..<k]
                if suffix.elementsEqual(prefix) {
                    accumulated.append(contentsOf: incoming.dropFirst(k))
                    return
                }
            }
        }

        accumulated.append(contentsOf: incoming)
    }
}
