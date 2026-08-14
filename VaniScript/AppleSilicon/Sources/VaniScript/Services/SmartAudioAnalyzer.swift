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

    /// Energy windows for a media range. `posMs` is **relative to `startSec`** (clip-local).
    static func energyProfile(
        sourceURL: URL,
        startSec: Double,
        endSec: Double
    ) async throws -> [AudioEnergyWindow] {
        try await Task.detached(priority: .utility) {
            try readEnergyProfile(from: sourceURL, startSec: startSec, endSec: endSec)
        }.value
    }

    private static func readEnergyProfile(from sourceURL: URL) throws -> [AudioEnergyWindow] {
        try readEnergyProfile(from: sourceURL, startSec: 0, endSec: .greatestFiniteMagnitude)
    }

    private static func readEnergyProfile(
        from sourceURL: URL,
        startSec: Double,
        endSec: Double
    ) throws -> [AudioEnergyWindow] {
        let file = try AVAudioFile(forReading: sourceURL)
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0, sampleRate.isFinite else { return [] }

        let fileLength = file.length
        let fileDurationSec = Double(fileLength) / sampleRate
        let startFrame: AVAudioFramePosition = {
            let boundedStartSec: Double
            if startSec.isNaN || startSec < 0 {
                boundedStartSec = 0
            } else if startSec.isFinite {
                boundedStartSec = min(startSec, fileDurationSec)
            } else {
                boundedStartSec = fileDurationSec
            }
            let candidate = (boundedStartSec * sampleRate).rounded(.down)
            return boundedFramePosition(candidate, fileLength: fileLength)
        }()
        let endFrame: AVAudioFramePosition = {
            guard endSec.isFinite, endSec > 0 else {
                return fileLength
            }
            let boundedEndSec = min(endSec, fileDurationSec)
            let candidate = (boundedEndSec * sampleRate).rounded(.up)
            return boundedFramePosition(candidate, fileLength: fileLength)
        }()
        guard endFrame > startFrame else { return [] }

        file.framePosition = startFrame

        let windowFrames = max(1, Int((Double(SmartSlicePlanner.energyWindowMs) / 1_000) * sampleRate))
        let bufferFrameCapacity: AVAudioFrameCount = 8_192
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: bufferFrameCapacity
        ) else {
            return []
        }

        var profile: [AudioEnergyWindow] = []
        var absoluteFrame = startFrame
        var currentWindowStartFrame = startFrame
        var currentWindowCount = 0
        var currentWindowSumSquares = 0.0

        while file.framePosition < endFrame {
            let remaining = endFrame - file.framePosition
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
                        rangeStartFrame: startFrame,
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
                rangeStartFrame: startFrame,
                sampleRate: sampleRate,
                sumSquares: currentWindowSumSquares,
                sampleCount: currentWindowCount
            ))
        }

        return profile
    }

    private static func boundedFramePosition(
        _ candidate: Double,
        fileLength: AVAudioFramePosition
    ) -> AVAudioFramePosition {
        guard candidate.isFinite, candidate > 0 else { return 0 }
        let fileLengthDouble = Double(fileLength)
        guard candidate < fileLengthDouble else { return fileLength }
        return AVAudioFramePosition(candidate)
    }

    private static func makeWindow(
        startFrame: AVAudioFramePosition,
        rangeStartFrame: AVAudioFramePosition,
        sampleRate: Double,
        sumSquares: Double,
        sampleCount: Int
    ) -> AudioEnergyWindow {
        let rms = sqrt(sumSquares / Double(max(1, sampleCount)))
        let dbfs = rms > 0 ? 20 * log10(rms) : -119
        // Clip-local timeline: 0ms at range start.
        let posMs = Int((Double(startFrame - rangeStartFrame) / sampleRate) * 1_000)
        return AudioEnergyWindow(posMs: max(0, posMs), dbfs: dbfs)
    }
}
