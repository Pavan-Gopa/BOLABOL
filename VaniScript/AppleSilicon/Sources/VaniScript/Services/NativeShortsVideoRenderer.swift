@preconcurrency import AVFoundation
import Foundation
import VaniScriptCore

struct NativeShortsExportOptions: Sendable {
    var format: String
    var resolutionPreset: String
    var frameRatePreset: String
    var language: ShortsIdeaDisplayLanguage
}

struct NativeShortsVideoRenderJob: Sendable {
    var planIndex: Int
    var plan: ShortsClipPlan
    var language: ShortsIdeaDisplayLanguage
}

enum NativeShortsVideoRendererError: LocalizedError {
    case missingVideoTrack
    case cannotCreateCompositionTrack
    case cannotCreateExporter
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            return "The source media does not contain a readable video track."
        case .cannotCreateCompositionTrack:
            return "AVFoundation could not create a native render track."
        case .cannotCreateExporter:
            return "AVFoundation could not create a native Shorts/Reels exporter."
        case .exportFailed:
            return "Native Shorts/Reels export did not complete."
        }
    }
}

enum NativeShortsVideoRenderer {
    static func export(
        sourceURL: URL,
        plans: [ShortsClipPlan],
        directory: URL,
        options: NativeShortsExportOptions,
        progressCallback: (@Sendable (_ progress: Double, _ stage: String, _ phaseTag: String) -> Void)? = nil
    ) async throws -> [URL] {
        try await export(
            sourceURL: sourceURL,
            jobs: plans.enumerated().map {
                NativeShortsVideoRenderJob(planIndex: $0.offset, plan: $0.element, language: options.language)
            },
            directory: directory,
            options: options,
            progressCallback: progressCallback
        )
    }

    static func export(
        sourceURL: URL,
        jobs: [NativeShortsVideoRenderJob],
        directory: URL,
        options: NativeShortsExportOptions,
        progressCallback: (@Sendable (_ progress: Double, _ stage: String, _ phaseTag: String) -> Void)? = nil
    ) async throws -> [URL] {
        let sourceAsset = AVURLAsset(url: sourceURL)
        guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
            throw NativeShortsVideoRendererError.missingVideoTrack
        }
        let sourceSize = orientedSize(for: sourceVideoTrack)
        let sourceFPS = sourceVideoTrack.nominalFrameRate > 0 ? Double(sourceVideoTrack.nominalFrameRate) : 30
        let outputSize = verticalResolution(for: options.resolutionPreset, sourceSize: sourceSize)
        let fps = frameRate(for: options.frameRatePreset, sourceFPS: sourceFPS)
        let fileExtension = options.format.lowercased() == "mov" ? "mov" : "mp4"
        let outputType: AVFileType = fileExtension == "mov" ? .mov : .mp4

        var exported: [URL] = []
        let totalJobs = max(1.0, Double(jobs.count))
        for (position, job) in jobs.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            let progressOffset = Double(position) / totalJobs
            progressCallback?(progressOffset, "Preparing render job for Clip \(job.planIndex + 1) \(job.language.rawValue)", "prepare")

            let renderPlan = NativeShortsRenderPlanBuilder.build(
                id: "\(sourceURL.lastPathComponent)-\(job.planIndex)-\(job.language.rawValue)",
                plan: job.plan,
                language: job.language,
                outputWidth: Int(outputSize.width),
                outputHeight: Int(outputSize.height),
                fps: fps
            )
            let outputURL = directory
                .appendingPathComponent(String(format: "%02d_%@_%@", job.planIndex + 1, job.language.rawValue, safeFilePart(renderPlan.title)))
                .appendingPathExtension(fileExtension)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            progressCallback?(progressOffset + (0.01 / totalJobs), "Prepared native media tracks", "prepare")

            try await exportSingle(
                sourceAsset: sourceAsset,
                sourceVideoTrack: sourceVideoTrack,
                sourceSize: sourceSize,
                renderPlan: renderPlan,
                outputURL: outputURL,
                outputType: outputType,
                progressCallback: { clipProgress in
                    let overallProgress = progressOffset + (clipProgress / totalJobs)
                    let stage: String
                    let phaseTag: String
                    if clipProgress < 0.05 {
                        stage = "Prepared native media tracks"
                        phaseTag = "prepare"
                    } else if clipProgress < 0.75 {
                        stage = "Rendering video frames through native Metal GPU compositor"
                        phaseTag = "render"
                    } else if clipProgress < 0.95 {
                        stage = "Mixing multi-channel audio tracks"
                        phaseTag = "audio"
                    } else {
                        stage = "Writing final video container"
                        phaseTag = "write"
                    }
                    progressCallback?(overallProgress, stage, phaseTag)
                }
            )
            exported.append(outputURL)
        }
        return exported
    }

    private static func exportSingle(
        sourceAsset: AVURLAsset,
        sourceVideoTrack: AVAssetTrack,
        sourceSize: CGSize,
        renderPlan: NativeShortsRenderPlan,
        outputURL: URL,
        outputType: AVFileType,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NativeShortsVideoRendererError.cannotCreateCompositionTrack
        }
        compositionVideoTrack.preferredTransform = sourceVideoTrack.preferredTransform

        var audioMixParameters: [AVAudioMixInputParameters] = []
        let sourceAudioTrack = sourceAsset.tracks(withMediaType: .audio).first
        let compositionAudioTrack = sourceAudioTrack.flatMap { _ in
            composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }

        let videoSegments = videoMediaSegments(for: renderPlan)
        let audioMediaSegments = renderPlan.mediaSegments

        for segment in videoSegments {
            let sourceStart = CMTime(seconds: segment.sourceStartSec, preferredTimescale: 600)
            let duration = CMTime(seconds: max(0, segment.sourceEndSec - segment.sourceStartSec), preferredTimescale: 600)
            let outputStart = CMTime(seconds: segment.outputStartSec, preferredTimescale: 600)
            let range = CMTimeRange(start: sourceStart, duration: duration)
            try compositionVideoTrack.insertTimeRange(range, of: sourceVideoTrack, at: outputStart)
        }

        for segment in audioMediaSegments {
            let sourceStart = CMTime(seconds: segment.sourceStartSec, preferredTimescale: 600)
            let duration = CMTime(seconds: max(0, segment.sourceEndSec - segment.sourceStartSec), preferredTimescale: 600)
            let outputStart = CMTime(seconds: segment.outputStartSec, preferredTimescale: 600)
            let range = CMTimeRange(start: sourceStart, duration: duration)
            if let sourceAudioTrack, let compositionAudioTrack {
                try? compositionAudioTrack.insertTimeRange(range, of: sourceAudioTrack, at: outputStart)
            }
        }

        for track in renderPlan.audioTracks where track.muted != true {
            guard let url = mediaURL(from: track.src) else { continue }
            let audioAsset = AVURLAsset(url: url)
            guard let audioTrack = audioAsset.tracks(withMediaType: .audio).first,
                  let targetTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }

            let assetDuration = max(0, audioAsset.duration.seconds)
            let sourceStart = min(max(0, track.trimStartSec), assetDuration)
            let sourceEnd = max(sourceStart, assetDuration - max(0, track.trimEndSec))
            let outputStart = min(max(0, track.startSec), renderPlan.durationSec)
            let outputDuration = min(sourceEnd - sourceStart, max(0, renderPlan.durationSec - outputStart))
            guard outputDuration > 0.05 else { continue }

            try? targetTrack.insertTimeRange(
                CMTimeRange(
                    start: CMTime(seconds: sourceStart, preferredTimescale: 600),
                    duration: CMTime(seconds: outputDuration, preferredTimescale: 600)
                ),
                of: audioTrack,
                at: CMTime(seconds: outputStart, preferredTimescale: 600)
            )

            let params = AVMutableAudioMixInputParameters(track: targetTrack)
            params.setVolume(Float(track.volume), at: CMTime(seconds: outputStart, preferredTimescale: 600))
            if track.fadeInSec > 0 {
                params.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: Float(track.volume),
                    timeRange: CMTimeRange(
                        start: CMTime(seconds: outputStart, preferredTimescale: 600),
                        duration: CMTime(seconds: min(track.fadeInSec, outputDuration), preferredTimescale: 600)
                    )
                )
            }
            if track.fadeOutSec > 0 {
                let fadeDuration = min(track.fadeOutSec, outputDuration)
                params.setVolumeRamp(
                    fromStartVolume: Float(track.volume),
                    toEndVolume: 0,
                    timeRange: CMTimeRange(
                        start: CMTime(seconds: outputStart + outputDuration - fadeDuration, preferredTimescale: 600),
                        duration: CMTime(seconds: fadeDuration, preferredTimescale: 600)
                    )
                )
            }
            audioMixParameters.append(params)
        }

        let videoComposition = makeVideoComposition(
            compositionTrack: compositionVideoTrack,
            sourceSize: sourceSize,
            renderPlan: renderPlan
        )
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioMixParameters

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NativeShortsVideoRendererError.cannotCreateExporter
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = outputType
        exporter.videoComposition = videoComposition
        if !audioMixParameters.isEmpty {
            exporter.audioMix = audioMix
        }
        exporter.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: renderPlan.durationSec, preferredTimescale: 600)
        )
        exporter.shouldOptimizeForNetworkUse = true
        try await runExport(exporter, progressCallback: progressCallback)
    }

    private static func videoMediaSegments(for renderPlan: NativeShortsRenderPlan) -> [NativeRenderMediaSegment] {
        guard renderPlan.backgroundSettings.blurEnabled else {
            return renderPlan.mediaSegments
        }

        var segments = renderPlan.mediaSegments
        if let intro = introBackgroundMediaSegment(for: renderPlan) {
            segments.append(intro)
        }
        if let outro = outroBackgroundMediaSegment(for: renderPlan) {
            segments.append(outro)
        }
        return segments.sorted { lhs, rhs in
            if lhs.outputStartSec == rhs.outputStartSec {
                return lhs.outputEndSec < rhs.outputEndSec
            }
            return lhs.outputStartSec < rhs.outputStartSec
        }
    }

    private static func introBackgroundMediaSegment(for renderPlan: NativeShortsRenderPlan) -> NativeRenderMediaSegment? {
        let introDuration = renderPlan.intro?.hidden == true ? 0 : renderPlan.intro?.duration ?? 0
        guard introDuration > 0.01 else { return nil }
        let window = sourceWindow(for: renderPlan)
        let sourceStart = window.start
        let sourceEnd = min(window.end, sourceStart + introDuration)
        guard sourceEnd > sourceStart + 0.01 else { return nil }
        return NativeRenderMediaSegment(
            sourceStartSec: sourceStart,
            sourceEndSec: sourceEnd,
            outputStartSec: 0,
            outputEndSec: sourceEnd - sourceStart
        )
    }

    private static func outroBackgroundMediaSegment(for renderPlan: NativeShortsRenderPlan) -> NativeRenderMediaSegment? {
        let outroDuration = renderPlan.outro?.hidden == true ? 0 : renderPlan.outro?.duration ?? 0
        guard outroDuration > 0.01 else { return nil }
        let window = sourceWindow(for: renderPlan)
        let sourceEnd = window.end
        let sourceStart = max(window.start, sourceEnd - outroDuration)
        guard sourceEnd > sourceStart + 0.01 else { return nil }
        let outputStart = max(0, renderPlan.durationSec - (sourceEnd - sourceStart))
        return NativeRenderMediaSegment(
            sourceStartSec: sourceStart,
            sourceEndSec: sourceEnd,
            outputStartSec: outputStart,
            outputEndSec: outputStart + (sourceEnd - sourceStart)
        )
    }

    private static func sourceWindow(for renderPlan: NativeShortsRenderPlan) -> (start: Double, end: Double) {
        let clipDuration = max(0, renderPlan.clipEndSec - renderPlan.clipStartSec)
        let windowStartOffset = min(max(0, renderPlan.timelineTrim.trimStartSec), clipDuration)
        let windowEndOffset = min(max(windowStartOffset, clipDuration - renderPlan.timelineTrim.trimEndSec), clipDuration)
        return (
            start: renderPlan.clipStartSec + windowStartOffset,
            end: renderPlan.clipStartSec + windowEndOffset
        )
    }

    private static func makeVideoComposition(
        compositionTrack: AVCompositionTrack,
        sourceSize: CGSize,
        renderPlan: NativeShortsRenderPlan
    ) -> AVMutableVideoComposition {
        let renderSize = CGSize(width: renderPlan.width, height: renderPlan.height)
        let instruction = NativeMetalVideoCompositionInstruction(
            sourceTrackID: compositionTrack.trackID,
            sourceSize: sourceSize,
            renderPlan: renderPlan
        )
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = NativeMetalVideoCompositor.self
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, renderPlan.fps)))
        return videoComposition
    }

    private static func orientedSize(for track: AVAssetTrack) -> CGSize {
        let transformed = track.naturalSize.applying(track.preferredTransform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    private static func verticalResolution(for preset: String, sourceSize: CGSize) -> CGSize {
        if preset.contains("4K") { return CGSize(width: 2160, height: 3840) }
        if preset.contains("2K") { return CGSize(width: 1440, height: 2560) }
        if preset.contains("1080") || preset.contains("Full HD") { return CGSize(width: 1080, height: 1920) }
        if preset.contains("720") || preset.contains("HD") { return CGSize(width: 720, height: 1280) }
        if preset.contains("Source-based") {
            return CGSize(width: max(1, sourceSize.width.rounded()), height: max(1, sourceSize.height.rounded()))
        }
        return CGSize(width: 1080, height: 1920)
    }

    private static func frameRate(for preset: String, sourceFPS: Double) -> Int {
        if preset.contains("24") { return 24 }
        if preset.contains("25") { return 25 }
        if preset.contains("50") { return 50 }
        if preset.contains("60") { return 60 }
        if preset.contains("30") { return 30 }
        if preset.contains("Source-based") { return max(1, Int(sourceFPS.rounded())) }
        return min(60, max(1, Int(sourceFPS.rounded())))
    }

    private static func mediaURL(from source: String) -> URL? {
        if source.hasPrefix("file://") {
            return URL(string: source)
        }
        return URL(fileURLWithPath: source)
    }

    private static func safeFilePart(_ value: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = value
            .components(separatedBy: disallowed)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "clip" : String(cleaned.prefix(72))
    }

    private static func runExport(
        _ exporter: AVAssetExportSession,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        exporter.exportAsynchronously {}

        while true {
            if Task.isCancelled {
                exporter.cancelExport()
                throw CancellationError()
            }

            let status = exporter.status
            let progress = Double(exporter.progress)
            progressCallback?(progress)

            if status == .completed {
                break
            } else if status == .failed {
                throw exporter.error ?? NativeShortsVideoRendererError.exportFailed
            } else if status == .cancelled {
                throw CancellationError()
            }

            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }
}
