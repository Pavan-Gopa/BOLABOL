import Foundation

public struct NativeRenderSubtitleCue: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var startSec: Double
    public var endSec: Double
    public var text: String

    public init(id: String, startSec: Double, endSec: Double, text: String) {
        self.id = id
        self.startSec = startSec
        self.endSec = endSec
        self.text = text
    }
}

public struct NativeRenderMediaSegment: Codable, Equatable, Sendable {
    public var sourceStartSec: Double
    public var sourceEndSec: Double
    public var outputStartSec: Double
    public var outputEndSec: Double

    public init(sourceStartSec: Double, sourceEndSec: Double, outputStartSec: Double, outputEndSec: Double) {
        self.sourceStartSec = sourceStartSec
        self.sourceEndSec = sourceEndSec
        self.outputStartSec = outputStartSec
        self.outputEndSec = outputEndSec
    }
}

public struct NativeShortsRenderPlan: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var width: Int
    public var height: Int
    public var fps: Int
    public var clipStartSec: Double
    public var clipEndSec: Double
    public var durationSec: Double
    public var subtitles: [NativeRenderSubtitleCue]
    public var captionStyle: ShortsSubtitleStyle
    public var subtitleBottomMargin: Double
    public var frameKeyframes: [FrameKeyframe]
    public var mediaSegments: [NativeRenderMediaSegment]
    public var timelineCuts: [TimelineCut]
    public var timelineTrim: TimelineTrim
    public var backgroundSettings: ShortsBackgroundSettings
    public var logo: LogoOverlaySettings?
    public var textTracks: [TextOverlayTrack]
    public var audioTracks: [ExtraAudioTrack]
    public var intro: IntroOutroOverlaySettings?
    public var outro: IntroOutroOverlaySettings?
}

public enum NativeShortsRenderPlanBuilder {
    public static func build(
        id: String,
        plan: ShortsClipPlan,
        language: ShortsIdeaDisplayLanguage,
        outputWidth: Int,
        outputHeight: Int,
        fps: Int,
        subtitleBottomMargin: Double = 450
    ) -> NativeShortsRenderPlan {
        let clipStart = ShortsPlanner.parseTimestampToSeconds(plan.start)
        let clipEnd = ShortsPlanner.parseTimestampToSeconds(plan.end)
        let clipDuration = max(0, clipEnd - clipStart)
        let trim = normalizeTrim(plan.timelineTrim, clipDuration: clipDuration)
        let cuts = normalizeCuts(plan.timelineCuts, clipDuration: clipDuration, trim: trim)
        let intro = overlay(for: language, source: plan.sourceIntro, target: plan.targetIntro, fallback: plan.intro)
        let outro = overlay(for: language, source: plan.sourceOutro, target: plan.targetOutro, fallback: plan.outro)
        let introDuration = intro?.hidden == true ? 0 : intro?.duration ?? 0
        let outroDuration = outro?.hidden == true ? 0 : outro?.duration ?? 0
        let mediaSegments = buildMediaSegments(
            clipStartSec: clipStart,
            clipEndSec: clipEnd,
            cuts: cuts,
            trim: trim,
            introDuration: introDuration
        )
        let activeDuration = max(0, clipDuration - trim.trimStartSec - trim.trimEndSec)
        let baseDuration = mediaSegments.last?.outputEndSec ?? (cuts.isEmpty ? activeDuration : introDuration)
        let duration = max(0.05, baseDuration + outroDuration)

        // 1. Get raw physical elements
        var rawSubtitles = segments(for: plan, language: language)
        var rawKeyframes = keyframes(for: plan, language: language)
        var rawTextTracks = tracks(for: plan, language: language)
        var rawAudioTracks = audioTracks(for: plan, language: language)

        // 2. Apply cuts in raw physical coordinate space sequentially
        var accumulatedCutDuration = 0.0
        for cut in cuts {
            let retimeCut = TimelineCut(
                startSec: cut.startSec - accumulatedCutDuration,
                endSec: cut.endSec - accumulatedCutDuration
            )
            rawSubtitles = retimeSubtitlesAfterCut(rawSubtitles, cut: retimeCut)
            rawKeyframes = retimeKeyframesAfterCut(rawKeyframes, cut: retimeCut)
            rawTextTracks = retimeTextTracksAfterCut(rawTextTracks, cut: retimeCut)
            rawAudioTracks = retimeAudioTracksAfterCut(rawAudioTracks, cut: retimeCut, clipDuration: clipDuration)
            accumulatedCutDuration += (cut.endSec - cut.startSec)
        }

        // 3. Shift elements for output timeline (subtract trimStartSec and add introDuration)
        let subtitles = normalizeSubtitles(
            shiftSubtitles(rawSubtitles, trimStartSec: trim.trimStartSec, introDuration: introDuration),
            duration: duration,
            introDuration: introDuration,
            outroDuration: outroDuration
        )
        let frameKeyframes = shiftKeyframes(
            rawKeyframes,
            trimStartSec: trim.trimStartSec,
            duration: duration,
            introDuration: introDuration
        )
        let textTracks = shiftTextTracks(
            rawTextTracks,
            trimStartSec: trim.trimStartSec,
            introDuration: introDuration
        )
        let audioTracks = shiftAudioTracks(
            rawAudioTracks,
            trimStartSec: trim.trimStartSec,
            introDuration: introDuration
        )

        return NativeShortsRenderPlan(
            id: id,
            title: title(for: plan, language: language),
            width: max(1, outputWidth),
            height: max(1, outputHeight),
            fps: max(1, fps),
            clipStartSec: clipStart,
            clipEndSec: clipEnd,
            durationSec: duration,
            subtitles: subtitles,
            captionStyle: plan.subtitleStyle ?? .orangeImpact,
            subtitleBottomMargin: plan.subtitleStyle?.subtitleBottomMargin ?? subtitleBottomMargin,
            frameKeyframes: frameKeyframes,
            mediaSegments: mediaSegments,
            timelineCuts: cuts,
            timelineTrim: trim,
            backgroundSettings: plan.backgroundSettings ?? .universalDefault,
            logo: overlay(for: language, source: plan.sourceLogo, target: plan.targetLogo, fallback: plan.logo),
            textTracks: textTracks,
            audioTracks: audioTracks,
            intro: intro,
            outro: outro
        )
    }

    public static func buildMediaSegments(
        clipStartSec: Double,
        clipEndSec: Double,
        cuts: [TimelineCut],
        trim: TimelineTrim,
        introDuration: Double = 0
    ) -> [NativeRenderMediaSegment] {
        let clipDuration = max(0, clipEndSec - clipStartSec)
        let windowStart = clamp(trim.trimStartSec, min: 0, max: clipDuration)
        let windowEnd = clamp(clipDuration - trim.trimEndSec, min: windowStart, max: clipDuration)
        var segments: [NativeRenderMediaSegment] = []
        var cursor = windowStart
        var outputCursor = max(0, introDuration)

        func pushSegment(start: Double, end: Double) {
            guard end > start + 0.01 else { return }
            let duration = end - start
            segments.append(NativeRenderMediaSegment(
                sourceStartSec: clipStartSec + start,
                sourceEndSec: clipStartSec + end,
                outputStartSec: outputCursor,
                outputEndSec: outputCursor + duration
            ))
            outputCursor += duration
        }

        for cut in cuts {
            pushSegment(start: cursor, end: cut.startSec)
            cursor = max(cursor, cut.endSec)
        }
        pushSegment(start: cursor, end: windowEnd)

        if segments.isEmpty, cuts.isEmpty {
            return [
                NativeRenderMediaSegment(
                    sourceStartSec: clipStartSec + windowStart,
                    sourceEndSec: clipStartSec + windowEnd,
                    outputStartSec: outputCursor,
                    outputEndSec: outputCursor + max(0, windowEnd - windowStart)
                )
            ]
        }
        return segments
    }

    public static func normalizeTrim(_ trim: TimelineTrim?, clipDuration: Double) -> TimelineTrim {
        let start = clamp(trim?.trimStartSec ?? 0, min: 0, max: max(0, clipDuration))
        let end = clamp(trim?.trimEndSec ?? 0, min: 0, max: max(0, clipDuration - start))
        return TimelineTrim(trimStartSec: start, trimEndSec: end)
    }

    public static func normalizeCuts(_ cuts: [TimelineCut]?, clipDuration: Double, trim: TimelineTrim) -> [TimelineCut] {
        let trimStart = trim.trimStartSec
        let trimEnd = max(trimStart, clipDuration - trim.trimEndSec)
        guard trimEnd > trimStart else { return [] }
        let sorted = (cuts ?? [])
            .map {
                TimelineCut(
                    startSec: clamp($0.startSec, min: trimStart, max: trimEnd),
                    endSec: clamp($0.endSec, min: trimStart, max: trimEnd)
                )
            }
            .filter { $0.endSec > $0.startSec + 0.01 }
            .sorted { $0.startSec < $1.startSec }

        var merged: [TimelineCut] = []
        for cut in sorted {
            if let last = merged.last, cut.startSec <= last.endSec + 0.01 {
                merged[merged.count - 1].endSec = max(last.endSec, cut.endSec)
            } else {
                merged.append(cut)
            }
        }
        return merged
    }

    private static func normalizeSubtitles(_ segments: [AlignedSubtitleSegment], duration: Double, introDuration: Double, outroDuration: Double) -> [NativeRenderSubtitleCue] {
        let activeStart = introDuration
        let activeEnd = max(activeStart, duration - outroDuration)
        return segments.enumerated().compactMap { index, segment in
            let start = max(activeStart, segment.start)
            let end = min(activeEnd, segment.end)
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, end > start + 0.01 else { return nil }
            return NativeRenderSubtitleCue(id: "cue_\(index)_\(segment.id)", startSec: start, endSec: end, text: text)
        }
    }

    private static func shiftSubtitles(_ segments: [AlignedSubtitleSegment], trimStartSec: Double, introDuration: Double) -> [AlignedSubtitleSegment] {
        segments.map {
            AlignedSubtitleSegment(
                id: $0.id,
                start: $0.start - trimStartSec + introDuration,
                end: $0.end - trimStartSec + introDuration,
                text: $0.text,
                words: $0.words.map { word in
                    AlignedWord(
                        id: word.id,
                        text: word.text,
                        start: word.start - trimStartSec + introDuration,
                        end: word.end - trimStartSec + introDuration
                    )
                }
            )
        }
    }

    private static func shiftKeyframes(
        _ keyframes: [FrameKeyframe],
        trimStartSec: Double,
        duration: Double,
        introDuration: Double
    ) -> [FrameKeyframe] {
        let source = keyframes.isEmpty ? [FrameKeyframe(id: "frame_default", time: 0, x: 0, y: 0, zoom: 1, backgroundColor: "#000000")] : keyframes
        let base = interpolateFrameState(source, timeSec: trimStartSec)
        var shifted: [FrameKeyframe] = []
        if introDuration > 0 {
            shifted.append(FrameKeyframe(id: "frame_intro_start", time: 0, x: base.x, y: base.y, zoom: base.zoom, backgroundColor: base.backgroundColor))
        }
        shifted.append(FrameKeyframe(id: "frame_trim_start", time: introDuration, x: base.x, y: base.y, zoom: base.zoom, backgroundColor: base.backgroundColor))
        shifted += source.compactMap { point in
            let time = point.time - trimStartSec + introDuration
            guard time > introDuration + 0.01, time <= duration + 0.01 else { return nil }
            return FrameKeyframe(id: point.id, time: time, x: point.x, y: point.y, zoom: point.zoom, backgroundColor: point.backgroundColor)
        }
        return shifted.sorted { $0.time < $1.time }
    }

    public static func interpolateFrameState(_ keyframes: [FrameKeyframe], timeSec: Double) -> FrameKeyframe {
        let sorted = keyframes
            .map {
                FrameKeyframe(
                    id: $0.id,
                    time: max(0, $0.time),
                    x: clamp($0.x, min: -100, max: 100),
                    y: clamp($0.y, min: -100, max: 100),
                    zoom: clamp($0.zoom, min: 0.5, max: 3),
                    backgroundColor: $0.backgroundColor ?? "#000000"
                )
            }
            .sorted { $0.time < $1.time }
        guard let first = sorted.first else {
            return FrameKeyframe(id: "frame_default", time: timeSec, x: 0, y: 0, zoom: 1, backgroundColor: "#000000")
        }
        guard sorted.count > 1, timeSec > first.time else { return first }
        guard let last = sorted.last, timeSec < last.time else { return sorted.last ?? first }
        guard let nextIndex = sorted.firstIndex(where: { $0.time >= timeSec }), nextIndex > 0 else { return first }
        let from = sorted[nextIndex - 1]
        let to = sorted[nextIndex]
        let progress = smoothstep((timeSec - from.time) / max(0.001, to.time - from.time))
        return FrameKeyframe(
            id: "frame_interpolated",
            time: timeSec,
            x: from.x + ((to.x - from.x) * progress),
            y: from.y + ((to.y - from.y) * progress),
            zoom: from.zoom + ((to.zoom - from.zoom) * progress),
            backgroundColor: from.backgroundColor ?? to.backgroundColor ?? "#000000"
        )
    }

    private static func shiftTextTracks(_ tracks: [TextOverlayTrack], trimStartSec: Double, introDuration: Double) -> [TextOverlayTrack] {
        tracks.map { track in
            var updated = track
            updated.blocks = track.blocks.map { block in
                TextOverlayBlock(
                    id: block.id,
                    startSec: block.startSec - trimStartSec + introDuration,
                    endSec: block.endSec - trimStartSec + introDuration,
                    text: block.text,
                    hidden: block.hidden
                )
            }
            return updated
        }
    }

    private static func shiftAudioTracks(_ tracks: [ExtraAudioTrack], trimStartSec: Double, introDuration: Double) -> [ExtraAudioTrack] {
        tracks.map { track in
            ExtraAudioTrack(
                id: track.id,
                name: track.name,
                src: track.src,
                previewSrc: track.previewSrc,
                startSec: track.startSec - trimStartSec + introDuration,
                trimStartSec: track.trimStartSec,
                trimEndSec: track.trimEndSec,
                volume: track.volume,
                fadeInSec: track.fadeInSec,
                fadeOutSec: track.fadeOutSec,
                muted: track.muted,
                assetDuration: track.assetDuration
            )
        }
    }

    private static func segments(for plan: ShortsClipPlan, language: ShortsIdeaDisplayLanguage) -> [AlignedSubtitleSegment] {
        ShortsVisualEditorStateBuilder.segments(for: plan, language: language)
    }

    private static func keyframes(for plan: ShortsClipPlan, language: ShortsIdeaDisplayLanguage) -> [FrameKeyframe] {
        switch language {
        case .source:
            return plan.sourceFrameKeyframes ?? plan.targetFrameKeyframes ?? []
        case .target:
            return plan.targetFrameKeyframes ?? plan.sourceFrameKeyframes ?? []
        }
    }

    private static func title(for plan: ShortsClipPlan, language: ShortsIdeaDisplayLanguage) -> String {
        switch language {
        case .source:
            return plan.sourceTitle ?? plan.title
        case .target:
            return plan.targetTitle ?? plan.translationsByLanguage?.values.first?.title ?? plan.title
        }
    }

    private static func tracks(for plan: ShortsClipPlan, language: ShortsIdeaDisplayLanguage) -> [TextOverlayTrack] {
        switch language {
        case .source:
            return plan.sourceTextTracks ?? plan.textTracks ?? []
        case .target:
            return plan.targetTextTracks ?? plan.textTracks ?? []
        }
    }

    private static func audioTracks(for plan: ShortsClipPlan, language: ShortsIdeaDisplayLanguage) -> [ExtraAudioTrack] {
        switch language {
        case .source:
            return plan.sourceAudioTracks ?? plan.audioTracks ?? []
        case .target:
            return plan.targetAudioTracks ?? plan.audioTracks ?? []
        }
    }

    private static func overlay<T>(for language: ShortsIdeaDisplayLanguage, source: T?, target: T?, fallback: T?) -> T? {
        switch language {
        case .source:
            return source ?? fallback
        case .target:
            return target ?? fallback
        }
    }

    private static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(Swift.max(value, lower), upper)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let t = clamp(value, min: 0, max: 1)
        return t * t * (3 - (2 * t))
    }

    // MARK: - Export Retiming Helpers

    private static func detectOverlap(start: Double, end: Double, cut: TimelineCut) -> String {
        if end <= cut.startSec || start >= cut.endSec { return "none" }
        if start >= cut.startSec && end <= cut.endSec { return "inside" }
        if start < cut.startSec && end > cut.endSec { return "split" }
        if start < cut.startSec { return "overlap-end" }
        return "overlap-start"
    }

    private static func retimeSubtitlesAfterCut(_ segments: [AlignedSubtitleSegment], cut: TimelineCut) -> [AlignedSubtitleSegment] {
        let cutDuration = cut.endSec - cut.startSec
        if cutDuration <= 0 { return segments }

        var result: [AlignedSubtitleSegment] = []
        for seg in segments {
            let overlap = detectOverlap(start: seg.start, end: seg.end, cut: cut)
            switch overlap {
            case "none":
                if seg.start >= cut.endSec {
                    var movedSeg = seg
                    movedSeg.start = seg.start - cutDuration
                    movedSeg.end = seg.end - cutDuration
                    movedSeg.words = seg.words.map { w in
                        var movedW = w
                        movedW.start = w.start - cutDuration
                        movedW.end = w.end - cutDuration
                        return movedW
                    }
                    result.append(movedSeg)
                } else {
                    result.append(seg)
                }
            case "inside":
                break // Delete entirely
            case "overlap-start":
                let newStart = cut.endSec - cutDuration
                var trimmedSeg = seg
                trimmedSeg.start = newStart
                trimmedSeg.end = seg.end - cutDuration
                trimmedSeg.words = seg.words.filter { $0.end > cut.endSec }.map { w in
                    var movedW = w
                    movedW.start = max(newStart, w.start - cutDuration)
                    movedW.end = w.end - cutDuration
                    return movedW
                }
                result.append(trimmedSeg)
            case "overlap-end":
                var trimmedSeg = seg
                trimmedSeg.end = cut.startSec
                trimmedSeg.words = seg.words.filter { $0.start < cut.startSec }.map { w in
                    var movedW = w
                    movedW.end = min(cut.startSec, w.end)
                    return movedW
                }
                result.append(trimmedSeg)
            case "split":
                // Part before cut
                var part1 = seg
                part1.end = cut.startSec
                part1.words = seg.words.filter { $0.start < cut.startSec }.map { w in
                    var movedW = w
                    movedW.end = min(cut.startSec, w.end)
                    return movedW
                }
                result.append(part1)

                // Part after cut
                let afterStart = cut.endSec - cutDuration
                var part2 = seg
                part2.id = "\(seg.id)_split"
                part2.start = afterStart
                part2.end = seg.end - cutDuration
                part2.words = seg.words.filter { $0.end > cut.endSec }.map { w in
                    var movedW = w
                    movedW.start = max(afterStart, w.start - cutDuration)
                    movedW.end = w.end - cutDuration
                    return movedW
                }
                result.append(part2)
            default:
                result.append(seg)
            }
        }
        return result
            .filter { $0.end > $0.start + 0.01 }
            .sorted { $0.start < $1.start }
    }

    private static func retimeKeyframesAfterCut(_ keyframes: [FrameKeyframe], cut: TimelineCut) -> [FrameKeyframe] {
        let cutDuration = cut.endSec - cut.startSec
        if cutDuration <= 0 { return keyframes }
        return keyframes
            .filter { $0.time < cut.startSec || $0.time >= cut.endSec }
            .map { kf in
                var movedKf = kf
                if kf.time >= cut.endSec {
                    movedKf.time = kf.time - cutDuration
                }
                return movedKf
            }
    }

    private static func retimeTextTracksAfterCut(_ tracks: [TextOverlayTrack], cut: TimelineCut) -> [TextOverlayTrack] {
        let cutDuration = cut.endSec - cut.startSec
        if cutDuration <= 0 { return tracks }

        return tracks.map { track in
            var updatedTrack = track
            var updatedBlocks: [TextOverlayBlock] = []
            for block in track.blocks {
                let overlap = detectOverlap(start: block.startSec, end: block.endSec, cut: cut)
                switch overlap {
                case "none":
                    if block.startSec >= cut.endSec {
                        var moved = block
                        moved.startSec = block.startSec - cutDuration
                        moved.endSec = block.endSec - cutDuration
                        updatedBlocks.append(moved)
                    } else {
                        updatedBlocks.append(block)
                    }
                case "inside":
                    break // Delete entirely
                case "overlap-start":
                    let newStart = cut.endSec - cutDuration
                    var trimmed = block
                    trimmed.startSec = newStart
                    trimmed.endSec = block.endSec - cutDuration
                    updatedBlocks.append(trimmed)
                case "overlap-end":
                    var trimmed = block
                    trimmed.endSec = cut.startSec
                    updatedBlocks.append(trimmed)
                case "split":
                    // Part before cut
                    var part1 = block
                    part1.endSec = cut.startSec
                    updatedBlocks.append(part1)

                    // Part after cut
                    let afterStart = cut.endSec - cutDuration
                    var part2 = block
                    part2.id = "\(block.id)_split"
                    part2.startSec = afterStart
                    part2.endSec = block.endSec - cutDuration
                    updatedBlocks.append(part2)
                default:
                    updatedBlocks.append(block)
                }
            }
            updatedTrack.blocks = updatedBlocks
                .filter { $0.endSec > $0.startSec + 0.01 }
                .sorted { $0.startSec < $1.startSec }
            return updatedTrack
        }
    }

    private static func retimeAudioTracksAfterCut(_ tracks: [ExtraAudioTrack], cut: TimelineCut, clipDuration: Double) -> [ExtraAudioTrack] {
        let cutDuration = cut.endSec - cut.startSec
        if cutDuration <= 0 { return tracks }

        var result: [ExtraAudioTrack] = []
        for track in tracks {
            let shift = max(0, min(cut.endSec, track.startSec) - cut.startSec)
            var moved = track
            moved.startSec = track.startSec - shift
            result.append(moved)
        }

        return result.filter { track in
            let assetDuration = track.assetDuration ?? clipDuration
            let durationOnTimeline = assetDuration - track.trimStartSec - track.trimEndSec
            return durationOnTimeline > 0.05
        }
    }
}
