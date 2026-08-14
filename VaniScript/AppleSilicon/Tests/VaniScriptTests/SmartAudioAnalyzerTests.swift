import AVFoundation
import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Smart audio analyzer", .serialized)
struct SmartAudioAnalyzerTests {
    @Test("full-file chunk planning treats the unbounded end range as the file length")
    func fullFilePlanningDoesNotConvertOverflowingEndFrame() async throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let sourceURL = try makeAudioFile(in: fixture, sampleCount: 16_000)

        var settings = AppSettings.defaults
        settings.sliceMode = .silence
        settings.chunkDurationMin = 1

        let chunks = try await SmartAudioAnalyzer.planChunks(
            sourceURL: sourceURL,
            sourcePath: sourceURL.path,
            durationSec: 1,
            settings: settings
        )

        // A one-second file cannot produce a one-minute silence cut, but the
        // analyzer still reads the complete AVAudioFile before returning nil.
        #expect(chunks == nil)
        let profile = try await SmartAudioAnalyzer.energyProfile(
            sourceURL: sourceURL,
            startSec: 0,
            endSec: .greatestFiniteMagnitude
        )
        #expect(!profile.isEmpty)
        #expect(profile.first?.posMs == 0)
    }

    private func makeAudioFile(in fixture: URL, sampleCount: Int) throws -> URL {
        let url = fixture.appendingPathComponent("source.caf")
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw FixtureError.audio
        }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else {
            throw FixtureError.audio
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<sampleCount {
                samples[index] = 0.2
            }
        }
        try file.write(from: buffer)
        return url
    }

    private func makeFixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("smart-audio-analyzer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private enum FixtureError: Error {
    case audio
}
