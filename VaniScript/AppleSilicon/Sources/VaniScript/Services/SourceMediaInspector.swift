@preconcurrency import AVFoundation
import CoreAudio
import CoreMedia
import Foundation
import VaniScriptCore

enum SourceMediaInspector {
    static func inspect(
        fileURL: URL,
        originalURL: String? = nil,
        title: String? = nil,
        durationSec providedDuration: Double? = nil,
        importedAt: Date = Date()
    ) async -> SourceMediaInfo {
        let path = fileURL.path(percentEncoded: false)
        let asset = AVURLAsset(url: fileURL)
        let duration = await resolvedDuration(asset: asset, fallback: providedDuration)
        let fileSize = fileSizeBytes(fileURL)
        let container = fileURL.pathExtension.isEmpty ? nil : fileURL.pathExtension.lowercased()

        var kind = MediaSource.kind(forPath: path)
        var width: Int?
        var height: Int?
        var frameRate: Double?
        var videoCodec: String?
        var audioCodec: String?
        var videoBitrateBps: Double?
        var audioBitrateBps: Double?
        var audioSampleRateHz: Double?
        var audioChannelCount: Int?
        let writingApplication = await writingApplication(for: asset)

        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            if let videoTrack = videoTracks.first {
                kind = .video
                let size = try await transformedSize(for: videoTrack)
                width = size.width
                height = size.height
                let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                if nominalFrameRate.isFinite, nominalFrameRate > 0 {
                    frameRate = Double(nominalFrameRate)
                }
                let descriptions = try await videoTrack.load(.formatDescriptions)
                videoCodec = descriptions.first.map(codecName)
                videoBitrateBps = try await estimatedDataRate(for: videoTrack)
            }
        } catch {
            // Keep partial metadata; AVFoundation can still fail for unusual streams.
        }

        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if kind == .unknown, !audioTracks.isEmpty {
                kind = .audio
            }
            if let audioTrack = audioTracks.first {
                let descriptions = try await audioTrack.load(.formatDescriptions)
                audioCodec = descriptions.first.map(codecName)
                audioBitrateBps = try await estimatedDataRate(for: audioTrack)
                if let audioDescription = descriptions.first {
                    let audioFormat = audioStreamBasicDescription(audioDescription)
                    audioSampleRateHz = audioFormat.sampleRate
                    audioChannelCount = audioFormat.channelCount
                }
            }
        } catch {
            // Keep partial metadata.
        }

        let overallBitrate = overallBitrateBps(fileSizeBytes: fileSize, durationSec: duration)

        return SourceMediaInfo(
            originalURL: normalizedOptional(originalURL),
            filePath: path,
            fileName: fileURL.lastPathComponent,
            title: normalizedOptional(title),
            kind: kind,
            durationSec: duration,
            fileSizeBytes: fileSize,
            width: width,
            height: height,
            frameRate: frameRate,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            container: container,
            writingApplication: writingApplication,
            overallBitrateBps: overallBitrate,
            videoBitrateBps: videoBitrateBps,
            audioBitrateBps: audioBitrateBps,
            audioSampleRateHz: audioSampleRateHz,
            audioChannelCount: audioChannelCount,
            importedAt: ISO8601DateFormatter().string(from: importedAt)
        )
    }

    private static func resolvedDuration(asset: AVURLAsset, fallback: Double?) async -> Double? {
        if let fallback, fallback.isFinite, fallback > 0 {
            return fallback
        }
        do {
            let duration = try await asset.load(.duration).seconds
            return duration.isFinite && duration > 0 ? duration : nil
        } catch {
            return nil
        }
    }

    private static func transformedSize(for track: AVAssetTrack) async throws -> (width: Int, height: Int) {
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = naturalSize.applying(transform)
        let resolvedWidth = abs(transformed.width) > 0 ? abs(transformed.width) : naturalSize.width
        let resolvedHeight = abs(transformed.height) > 0 ? abs(transformed.height) : naturalSize.height
        return (
            width: Int(max(0, resolvedWidth).rounded()),
            height: Int(max(0, resolvedHeight).rounded())
        )
    }

    private static func fileSizeBytes(_ fileURL: URL) -> Int64? {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return nil
        }
        return Int64(fileSize)
    }

    private static func estimatedDataRate(for track: AVAssetTrack) async throws -> Double? {
        let rate = try await track.load(.estimatedDataRate)
        guard rate.isFinite, rate > 0 else { return nil }
        return Double(rate)
    }

    private static func overallBitrateBps(fileSizeBytes: Int64?, durationSec: Double?) -> Double? {
        guard let fileSizeBytes,
              let durationSec,
              durationSec.isFinite,
              durationSec > 0 else {
            return nil
        }
        return Double(fileSizeBytes) * 8.0 / durationSec
    }

    private static func codecName(_ description: CMFormatDescription) -> String {
        fourCharacterCode(CMFormatDescriptionGetMediaSubType(description))
    }

    private static func audioStreamBasicDescription(_ description: CMFormatDescription) -> (sampleRate: Double?, channelCount: Int?) {
        guard let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            return (nil, nil)
        }
        let audioFormat = streamDescription.pointee
        let sampleRate = audioFormat.mSampleRate.isFinite && audioFormat.mSampleRate > 0 ? audioFormat.mSampleRate : nil
        let channelCount = audioFormat.mChannelsPerFrame > 0 ? Int(audioFormat.mChannelsPerFrame) : nil
        return (sampleRate, channelCount)
    }

    private static func writingApplication(for asset: AVURLAsset) async -> String? {
        if let value = await writingApplication(in: (try? await asset.load(.commonMetadata)) ?? []) {
            return value
        }
        return await writingApplication(in: (try? await asset.load(.metadata)) ?? [])
    }

    private static func writingApplication(in metadataItems: [AVMetadataItem]) async -> String? {
        for item in metadataItems {
            let identifier = item.identifier?.rawValue.lowercased() ?? ""
            let key = item.key.map { String(describing: $0).lowercased() } ?? ""
            guard identifier.contains("software") || identifier.contains("%a9too") || identifier.contains("too") || key.contains("too") else {
                continue
            }
            let value = (try? await item.load(.stringValue))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func fourCharacterCode(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        let scalars = bytes.map { byte -> UnicodeScalar in
            let printable = (32...126).contains(Int(byte)) ? byte : UInt8(ascii: "?")
            return UnicodeScalar(printable)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
