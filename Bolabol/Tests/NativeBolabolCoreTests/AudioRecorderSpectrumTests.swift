import AVFoundation
import Foundation
@testable import NativeBolabol
import Testing

// S1 crash regression: `frequencyBands(for:bandCount:)` trapped (SIGTRAP on
// RealtimeMessenger.mServiceQueue) for low microphone sample rates because the
// 196-bin magnitude cap left frequency-to-bin mapping that could produce
// inverted or out-of-bounds slices (e.g. 16 kHz mapped startBin 208 while the
// last valid index was 195).
//
// These tests drive the real production function through real
// `AVAudioPCMBuffer` fixtures and assert only the observable output contract:
// exact band counts, finite values bounded to `[0.02, 1]`, deterministic
// fallbacks, and no trapping. They deliberately never re-derive the internal
// bin math or assert source text.

@Suite("Audio Recorder Spectrum Regression Tests")
struct AudioRecorderSpectrumTests {

    // MARK: - Fixtures

    /// Builds a real mono, non-interleaved Float32 PCM buffer with controlled
    /// sample rate, frame length, and sample content.
    private func monoFloatBuffer(
        sampleRate: Double,
        frameLength: AVAudioFrameCount,
        sampleAt: (Int) -> Float
    ) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            ),
            "Float32 mono format must exist at \(sampleRate) Hz"
        )
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frameLength, 1)),
            "PCM buffer must allocate with capacity \(frameLength)"
        )
        buffer.frameLength = frameLength
        if let channelData = buffer.floatChannelData {
            let samples = channelData[0]
            for frame in 0..<Int(frameLength) {
                samples[frame] = sampleAt(frame)
            }
        }
        return buffer
    }

    /// Deterministic audible sine (440 Hz at amplitude 0.5) — comfortably
    /// inside the analysis range for every tested sample rate.
    private func sineSample(frame: Int, sampleRate: Double) -> Float {
        0.5 * Float(sin(2 * Double.pi * 440 * Double(frame) / sampleRate))
    }

    /// Observable default-output contract: exactly `expectedCount` values,
    /// every one finite and bounded to `[0.02, 1]`.
    private func assertBoundedSpectrum(
        _ bands: [Float],
        expectedCount: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(bands.count == expectedCount, sourceLocation: sourceLocation)
        #expect(
            bands.allSatisfy { $0.isFinite },
            "every band must be finite, got \(bands)",
            sourceLocation: sourceLocation
        )
        #expect(
            bands.allSatisfy { $0 >= 0.02 && $0 <= 1 },
            "every band must stay within [0.02, 1], got \(bands)",
            sourceLocation: sourceLocation
        )
    }

    // MARK: - Sample-rate matrix (the reported crash surface)

    @Test("Low microphone sample rates return a bounded 40-band spectrum without trapping")
    func lowSampleRateSpectrumMatrix() throws {
        // 8/16/24/32 kHz deterministically trapped the pre-fix implementation;
        // running the real function on real buffers at these rates is the
        // regression guard (a formula inspection would not have crashed).
        for sampleRate in [8_000.0, 16_000.0, 24_000.0, 32_000.0] {
            let buffer = try monoFloatBuffer(sampleRate: sampleRate, frameLength: 1024) { frame in
                sineSample(frame: frame, sampleRate: sampleRate)
            }

            let bands = frequencyBands(for: buffer)

            assertBoundedSpectrum(bands, expectedCount: 40)
            #expect(
                (bands.max() ?? 0) > 0.1,
                "\(sampleRate) Hz: an audible sine must light up at least one band well above the 0.02 floor"
            )
        }
    }

    @Test("Normal microphone sample rates keep the bounded 40-band spectrum contract")
    func normalSampleRateSpectrumMatrix() throws {
        for sampleRate in [44_100.0, 48_000.0, 96_000.0] {
            let buffer = try monoFloatBuffer(sampleRate: sampleRate, frameLength: 1024) { frame in
                sineSample(frame: frame, sampleRate: sampleRate)
            }

            let bands = frequencyBands(for: buffer)

            assertBoundedSpectrum(bands, expectedCount: 40)
            #expect(
                (bands.max() ?? 0) > 0.1,
                "\(sampleRate) Hz: an audible sine must light up at least one band well above the 0.02 floor"
            )
        }
    }

    // MARK: - Frame-length boundaries

    @Test("Empty and sub-64-frame buffers fall back to the deterministic 0.08 baseline")
    func emptyAndShortBuffersUseBaselineFallback() throws {
        for frameLength in [0, 63] as [AVAudioFrameCount] {
            let buffer = try monoFloatBuffer(sampleRate: 48_000, frameLength: frameLength) { _ in 0.5 }

            let bands = frequencyBands(for: buffer)

            #expect(
                bands == Array(repeating: 0.08, count: 40),
                "frameLength \(frameLength) must fall back to exactly 40 × 0.08"
            )
        }

        // The fallback must respect the requested band count, not just the default.
        let shortBuffer = try monoFloatBuffer(sampleRate: 48_000, frameLength: 63) { _ in 0.5 }
        #expect(frequencyBands(for: shortBuffer, bandCount: 3) == Array(repeating: 0.08, count: 3))
    }

    @Test("Usable frame lengths including the 768-frame analysis cap produce bounded spectra")
    func usableFrameLengthBoundaries() throws {
        // 64 is the minimum usable length; 768 is the internal analysis window;
        // 1024 proves longer buffers are safely capped instead of read out of
        // bounds.
        for frameLength in [64, 768, 1024] as [AVAudioFrameCount] {
            let buffer = try monoFloatBuffer(sampleRate: 48_000, frameLength: frameLength) { frame in
                sineSample(frame: frame, sampleRate: 48_000)
            }

            let bands = frequencyBands(for: buffer)

            assertBoundedSpectrum(bands, expectedCount: 40)
        }
    }

    @Test("Non-float PCM buffers fall back to the baseline without trapping")
    func nonFloatBufferFallsBackToBaseline() throws {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 48_000,
                channels: 1,
                interleaved: false
            ),
            "Int16 mono format must exist"
        )
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024

        #expect(buffer.floatChannelData == nil, "Int16 buffer must expose no float channel data")
        #expect(frequencyBands(for: buffer) == Array(repeating: 0.08, count: 40))
    }

    // MARK: - Band-count boundaries

    @Test("Non-positive band counts return an empty result without trapping")
    func nonPositiveBandCountsReturnEmpty() throws {
        let buffer = try monoFloatBuffer(sampleRate: 48_000, frameLength: 1024) { frame in
            sineSample(frame: frame, sampleRate: 48_000)
        }

        #expect(frequencyBands(for: buffer, bandCount: 0).isEmpty)
        #expect(frequencyBands(for: buffer, bandCount: -40).isEmpty)
    }

    @Test("Extreme positive band counts return exactly the requested bounded count")
    func extremeBandCountsReturnRequestedCount() throws {
        let buffer = try monoFloatBuffer(sampleRate: 48_000, frameLength: 1024) { frame in
            sineSample(frame: frame, sampleRate: 48_000)
        }

        for bandCount in [1, 80] {
            let bands = frequencyBands(for: buffer, bandCount: bandCount)
            assertBoundedSpectrum(bands, expectedCount: bandCount)
        }
    }

    // MARK: - Representative content

    @Test("Silence stays at the 0.02 floor")
    func silenceStaysAtFloor() throws {
        let buffer = try monoFloatBuffer(sampleRate: 48_000, frameLength: 1024) { _ in 0 }

        let bands = frequencyBands(for: buffer)

        assertBoundedSpectrum(bands, expectedCount: 40)
        // Deterministic contract: zero RMS closes the activity gate, so every
        // band is clamped to the exact floor.
        #expect(
            bands.allSatisfy { $0 == 0.02 },
            "silence must clamp every band to the 0.02 floor, got \(bands)"
        )
    }

    @Test("A DC offset is removed before analysis and stays at the floor")
    func dcOffsetRemovedBeforeAnalysis() throws {
        let buffer = try monoFloatBuffer(sampleRate: 48_000, frameLength: 1024) { _ in 0.4 }

        let bands = frequencyBands(for: buffer)

        assertBoundedSpectrum(bands, expectedCount: 40)
        // Deterministic contract: DC removal leaves no residual energy, the
        // activity gate closes, and every band clamps to the exact floor.
        #expect(
            bands.allSatisfy { $0 == 0.02 },
            "pure DC must be removed and clamp every band to the 0.02 floor, got \(bands)"
        )
    }

    @Test("An audible sine produces non-baseline activity in at least one band")
    func audibleSineShowsActivity() throws {
        let buffer = try monoFloatBuffer(sampleRate: 48_000, frameLength: 1024) { frame in
            sineSample(frame: frame, sampleRate: 48_000)
        }

        let bands = frequencyBands(for: buffer)

        assertBoundedSpectrum(bands, expectedCount: 40)
        #expect(
            (bands.max() ?? 0) > 0.1,
            "a strong audible sine must push at least one band well above the 0.02 floor, got \(bands)"
        )
    }

    @Test("NaN and infinite samples never leak non-finite or out-of-range bands")
    func nonFiniteSamplesStayFiniteAndBounded() throws {
        // A single pathological sample contaminates the whole analysis window;
        // the production contract is that the finiteness guards fold the
        // result to the floor instead of emitting NaN/infinity or trapping.
        for (label, poison) in [("NaN", Float.nan), ("+infinity", Float.infinity)] {
            let buffer = try monoFloatBuffer(sampleRate: 48_000, frameLength: 1024) { frame in
                frame == 100 ? poison : sineSample(frame: frame, sampleRate: 48_000)
            }

            let bands = frequencyBands(for: buffer)

            assertBoundedSpectrum(bands, expectedCount: 40)
            #expect(
                bands.allSatisfy { $0 == 0.02 },
                "\(label) content must deterministically fold every band to the 0.02 floor, got \(bands)"
            )
        }
    }
}
