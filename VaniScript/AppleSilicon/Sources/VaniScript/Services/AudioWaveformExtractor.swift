import Foundation
import AVFoundation
import CoreMedia

public enum AudioWaveformExtractor {
    public static func extractPeaks(from url: URL, count: Int, startSec: Double = 0.0, durationSec: Double? = nil) async -> [Double] {
        return await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)

            guard let reader = try? AVAssetReader(asset: asset) else {
                return []
            }

            let loadedTracks = try? await asset.loadTracks(withMediaType: .audio)
            guard let audioTrack = loadedTracks?.first else {
                return []
            }

            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 1
            ]

            let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
            reader.add(readerOutput)

            var targetDuration = durationSec ?? 0.0
            if targetDuration <= 0.0 {
                var dur: Double = 0.0
                if #available(macOS 13.0, *), let assetDur = try? await asset.load(.duration) {
                    dur = assetDur.seconds
                }
                if dur <= 0.0 {
                    dur = asset.duration.seconds
                }
                targetDuration = max(0.1, dur - startSec)
            }

            let startCM = CMTime(seconds: startSec, preferredTimescale: 600)
            let durationCM = CMTime(seconds: targetDuration, preferredTimescale: 600)
            reader.timeRange = CMTimeRange(start: startCM, duration: durationCM)

            guard reader.startReading() else {
                return []
            }

            var sampleRate: Double = 44100.0
            var formats: [CMFormatDescription]? = nil
            if #available(macOS 13.0, *) {
                formats = try? await audioTrack.load(.formatDescriptions)
            }
            if formats == nil {
                formats = audioTrack.formatDescriptions as? [CMFormatDescription]
            }
            if let formats, let formatDesc = formats.first {
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                    sampleRate = asbd.pointee.mSampleRate
                }
            }

            let totalSamplesEstimate = Int(targetDuration * sampleRate)
            let samplesPerPeak = max(1, totalSamplesEstimate / count)

            var peaks = [Double](repeating: 0.0, count: count)
            var currentSampleIndex = 0
            var currentPeakIndex = 0
            var currentPeakMax: Double = 0.0
            var nextBoundary = samplesPerPeak

            while reader.status == .reading {
                guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                    break
                }
                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                    continue
                }

                var length = 0
                var totalLength = 0
                var dataPointer: UnsafeMutablePointer<CChar>? = nil
                let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

                if status == noErr, let rawPointer = dataPointer, length == totalLength {
                    let sampleCount = totalLength / 2
                    if sampleCount > 0 {
                        rawPointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { ptr in
                            for i in 0..<sampleCount {
                                let sample = ptr[i]
                                let val = abs(Double(sample)) / 32768.0
                                if val > currentPeakMax {
                                    currentPeakMax = val
                                }

                                currentSampleIndex += 1
                                if currentSampleIndex >= nextBoundary {
                                    if currentPeakIndex < count {
                                        peaks[currentPeakIndex] = currentPeakMax
                                    }
                                    currentPeakIndex += 1
                                    currentPeakMax = 0.0
                                    nextBoundary += samplesPerPeak
                                }
                            }
                        }
                    }
                } else {
                    let totalLength = CMBlockBufferGetDataLength(blockBuffer)
                    let sampleCount = totalLength / 2
                    if sampleCount > 0 {
                        var buffer = [Int16](repeating: 0, count: sampleCount)
                        let copyStatus = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: totalLength, destination: &buffer)
                        if copyStatus == noErr {
                            for sample in buffer {
                                let val = abs(Double(sample)) / 32768.0
                                if val > currentPeakMax {
                                    currentPeakMax = val
                                }

                                currentSampleIndex += 1
                                if currentSampleIndex >= nextBoundary {
                                    if currentPeakIndex < count {
                                        peaks[currentPeakIndex] = currentPeakMax
                                    }
                                    currentPeakIndex += 1
                                    currentPeakMax = 0.0
                                    nextBoundary += samplesPerPeak
                                }
                            }
                        }
                    }
                }
            }

            if currentPeakIndex < count && currentPeakMax > 0.0 {
                peaks[currentPeakIndex] = currentPeakMax
            }

            reader.cancelReading()

            let maxPeak = peaks.max() ?? 1.0
            if maxPeak > 0 {
                peaks = peaks.map { $0 / maxPeak }
            }

            return peaks
        }.value
    }
}
