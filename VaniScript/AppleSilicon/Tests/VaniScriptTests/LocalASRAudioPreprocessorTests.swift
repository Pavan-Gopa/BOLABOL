import AVFoundation
import Foundation
import Testing
@testable import VaniScript

@Suite("Local ASR audio preprocessing", .serialized)
struct LocalASRAudioPreprocessorTests {
    @Test("keeps mono audio and writes canonical 16 kHz int16 WAV")
    func convertsMonoAudio() throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = fixture.appendingPathComponent("mono.caf")
        let destination = fixture.appendingPathComponent("normalized.wav")
        try writeFloatAudio(
            to: source,
            sampleRate: 48_000,
            channels: [[Float](repeating: 0.25, count: 24_000)]
        )

        _ = try LocalASRAudioPreprocessor().convertTo16kMonoWAV(
            source: source,
            destination: destination
        )

        let output = try AVAudioFile(forReading: destination)
        #expect(output.length == 8_000)
        #expect(abs(output.fileFormat.sampleRate - 16_000) < 0.5)
        #expect(output.fileFormat.channelCount == 1)
        #expect(output.fileFormat.commonFormat == .pcmFormatInt16)
        #expect(output.fileFormat.isInterleaved)
        #expect(try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber != nil)
    }

    @Test("selects the loudest physical channel instead of downmixing")
    func selectsLoudestMultichannelInput() throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = fixture.appendingPathComponent("multichannel.caf")
        let destination = fixture.appendingPathComponent("normalized.wav")
        let quiet = [Float](repeating: 0.03, count: 24_000)
        let loud = [Float](repeating: 0.8, count: 24_000)
        try writeFloatAudio(to: source, sampleRate: 48_000, channels: [quiet, loud])

        try LocalASRAudioPreprocessor().convertTo16kMonoWAV(
            source: source,
            destination: destination
        )

        let output = try AVAudioFile(forReading: destination)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: output.processingFormat,
            frameCapacity: AVAudioFrameCount(output.length)
        ) else {
            Issue.record("Could not allocate output buffer")
            return
        }
        try output.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else {
            Issue.record("Output did not expose a mono channel")
            return
        }
        let firstSample = abs(channel[Int(buffer.frameLength / 2)])
        #expect(firstSample > 0.6)
    }

    @Test("rejects empty audio and removes a partial destination")
    func rejectsEmptyAudio() throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = fixture.appendingPathComponent("empty.caf")
        let destination = fixture.appendingPathComponent("normalized.wav")
        try writeFloatAudio(to: source, sampleRate: 48_000, channels: [[]])

        do {
            _ = try LocalASRAudioPreprocessor().convertTo16kMonoWAV(
                source: source,
                destination: destination
            )
            Issue.record("Expected empty audio to fail")
        } catch is CancellationError {
            Issue.record("Empty audio unexpectedly cancelled")
        } catch is LocalASRAudioPreprocessorError {
            #expect(!FileManager.default.fileExists(atPath: destination.path))
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("rejects invalid source paths and matching destination")
    func rejectsInvalidSourceAndSameDestination() throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let destination = fixture.appendingPathComponent("normalized.wav")
        let missingSource = fixture.appendingPathComponent("nonexistent.caf")

        #expect(throws: LocalASRAudioPreprocessorError.destinationIsSource) {
            try LocalASRAudioPreprocessor().convertTo16kMonoWAV(
                source: destination,
                destination: destination
            )
        }

        #expect(throws: LocalASRAudioPreprocessorError.sourceUnavailable(missingSource)) {
            try LocalASRAudioPreprocessor().convertTo16kMonoWAV(
                source: missingSource,
                destination: destination
            )
        }
    }

    private func makeFixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScript-ASR-Audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeFloatAudio(
        to url: URL,
        sampleRate: Double,
        channels: [[Float]]
    ) throws {
        let frameCount = channels.map(\.count).min() ?? 0
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels.count),
            interleaved: false
        ) else {
            Issue.record("Could not create fixture format")
            return
        }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels.count,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true
        ]
        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            ) else {
                Issue.record("Could not allocate fixture buffer")
                return
            }
            buffer.frameLength = AVAudioFrameCount(frameCount)
            if let channelData = buffer.floatChannelData {
                for channel in channels.indices {
                    for frame in 0..<frameCount {
                        channelData[channel][frame] = channels[channel][frame]
                    }
                }
            }
            try file.write(from: buffer)
        }
    }
}
