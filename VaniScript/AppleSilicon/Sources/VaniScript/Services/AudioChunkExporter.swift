import AVFoundation
import Foundation
import VaniScriptCore

enum AudioChunkExporter {
    static func exportChunks(sourceURL: URL, chunks: [ChunkData], projectId: String? = nil) async throws -> [Int: URL] {
        guard chunks.count > 1 || (chunks.first?.endSec ?? 0) > 0 else {
            return [0: sourceURL]
        }

        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw AudioChunkExportError.noAudioTrack
        }

        let outputDirectory = try makeOutputDirectory(projectId: projectId)
        var outputs: [Int: URL] = [:]

        for chunk in chunks {
            guard chunk.durationSec > 0 else {
                outputs[chunk.index] = sourceURL
                continue
            }

            let outputURL = outputDirectory
                .appendingPathComponent(String(format: "chunk_%04d", chunk.index + 1))
                .appendingPathExtension("m4a")

            try await exportAudioChunk(
                audioTrack: audioTrack,
                startSec: chunk.startSec,
                durationSec: chunk.durationSec,
                outputURL: outputURL
            )
            outputs[chunk.index] = outputURL
        }

        return outputs
    }

    private static func makeOutputDirectory(projectId: String?) throws -> URL {
        if let projectId, !projectId.isEmpty {
            let directory = AppStoragePaths.applicationSupportDirectory()
                .appendingPathComponent("Projects", isDirectory: true)
                .appendingPathComponent(projectId, isDirectory: true)
                .appendingPathComponent("chunks", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } else {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("VaniScriptChunks", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    private static func exportAudioChunk(
        audioTrack: AVAssetTrack,
        startSec: Double,
        durationSec: Double,
        outputURL: URL
    ) async throws {
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioChunkExportError.cannotCreateTrack
        }

        let start = CMTime(seconds: max(0, startSec), preferredTimescale: 600)
        let duration = CMTime(seconds: max(0.1, durationSec), preferredTimescale: 600)
        try compositionTrack.insertTimeRange(
            CMTimeRange(start: start, duration: duration),
            of: audioTrack,
            at: .zero
        )

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioChunkExportError.cannotCreateExporter
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        exporter.shouldOptimizeForNetworkUse = false

        let exportBox = ExportSessionBox(exporter)
        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exportBox.exporter.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exportBox.exporter.error ?? AudioChunkExportError.exportFailed)
                default:
                    continuation.resume(throwing: AudioChunkExportError.exportFailed)
                }
            }
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let exporter: AVAssetExportSession

    init(_ exporter: AVAssetExportSession) {
        self.exporter = exporter
    }
}

enum AudioChunkExportError: LocalizedError {
    case noAudioTrack
    case cannotCreateTrack
    case cannotCreateExporter
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            "The selected media does not contain an audio track."
        case .cannotCreateTrack:
            "Could not create a native audio composition track."
        case .cannotCreateExporter:
            "Could not create an AVFoundation export session."
        case .exportFailed:
            "AVFoundation could not export the audio chunk."
        }
    }
}
