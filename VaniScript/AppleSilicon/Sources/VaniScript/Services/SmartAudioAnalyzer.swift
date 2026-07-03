import AVFoundation
import Foundation
import VaniScriptCore

enum SmartAudioAnalyzer {
    static func planChunks(
        sourceURL: URL,
        sourcePath: String,
        durationSec: Double,
        settings: AppSettings
    ) async throws -> [ChunkData]? {
        guard settings.sliceMode == .silence, durationSec > 0 else { return nil }

        let targetMs = max(60_000, settings.chunkDurationMin * 60 * 1_000)
        let thresholdDb = Double(settings.silenceThreshDb)
        let minSilenceMs = settings.minSilenceMs

        let cutPointsMs = try await Task.detached(priority: .utility) {
            let profile = try readEnergyProfile(from: sourceURL)
            return SmartSlicePlanner.computeCutPoints(
                profile: profile,
                totalDurationMs: Int(durationSec * 1_000),
                targetMs: targetMs,
                threshDb: thresholdDb,
                minSilenceMs: minSilenceMs
            )
        }.value

        guard !cutPointsMs.isEmpty else { return nil }
        return ChunkPlanner.plan(
            sourcePath: sourcePath,
            durationSec: durationSec,
            cutPointsSec: SmartSlicePlanner.cutPointsToSeconds(cutPointsMs)
        )
    }

    private static func readEnergyProfile(from sourceURL: URL) throws -> [AudioEnergyWindow] {
        let file = try AVAudioFile(forReading: sourceURL)
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return [] }

        let windowFrames = max(1, Int((Double(SmartSlicePlanner.energyWindowMs) / 1_000) * sampleRate))
        let bufferFrameCapacity: AVAudioFrameCount = 8_192
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: bufferFrameCapacity
        ) else {
            return []
        }

        var profile: [AudioEnergyWindow] = []
        var absoluteFrame: AVAudioFramePosition = 0
        var currentWindowStartFrame: AVAudioFramePosition = 0
        var currentWindowCount = 0
        var currentWindowSumSquares = 0.0

        while file.framePosition < file.length {
            let remaining = file.length - file.framePosition
            let framesToRead = AVAudioFrameCount(min(Int64(bufferFrameCapacity), remaining))
            try file.read(into: buffer, frameCount: framesToRead)
            guard buffer.frameLength > 0 else { break }
            guard let channels = buffer.floatChannelData else { return [] }

            let channelCount = max(1, Int(buffer.format.channelCount))
            for frameIndex in 0..<Int(buffer.frameLength) {
                if currentWindowCount == 0 {
                    currentWindowStartFrame = absoluteFrame
                }

                var mixedSample = 0.0
                for channelIndex in 0..<channelCount {
                    mixedSample += Double(channels[channelIndex][frameIndex])
                }
                mixedSample /= Double(channelCount)
                currentWindowSumSquares += mixedSample * mixedSample
                currentWindowCount += 1
                absoluteFrame += 1

                if currentWindowCount >= windowFrames {
                    profile.append(makeWindow(
                        startFrame: currentWindowStartFrame,
                        sampleRate: sampleRate,
                        sumSquares: currentWindowSumSquares,
                        sampleCount: currentWindowCount
                    ))
                    currentWindowCount = 0
                    currentWindowSumSquares = 0
                }
            }
        }

        if currentWindowCount > 0 {
            profile.append(makeWindow(
                startFrame: currentWindowStartFrame,
                sampleRate: sampleRate,
                sumSquares: currentWindowSumSquares,
                sampleCount: currentWindowCount
            ))
        }

        return profile
    }

    private static func makeWindow(
        startFrame: AVAudioFramePosition,
        sampleRate: Double,
        sumSquares: Double,
        sampleCount: Int
    ) -> AudioEnergyWindow {
        let rms = sqrt(sumSquares / Double(max(1, sampleCount)))
        let dbfs = rms > 0 ? 20 * log10(rms) : -119
        let posMs = Int((Double(startFrame) / sampleRate) * 1_000)
        return AudioEnergyWindow(posMs: posMs, dbfs: dbfs)
    }
}
