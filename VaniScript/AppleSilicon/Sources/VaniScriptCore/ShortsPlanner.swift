import Foundation

public struct ClipValidationResult: Equatable, Sendable {
    public var ok: Bool
    public var durationSec: Double
    public var reason: String?
}

public struct AppendShortsPlansResult: Equatable, Sendable {
    public var plans: [ShortsClipPlan]
    public var addedIndexes: [Int]
    public var skippedOverlapping: [ShortsClipPlan]
}

public enum ShortsPlanner {
    public static let existingClipExclusionPaddingSec: Double = 15

    public static func buildPrompt(
        transcript: String,
        count: Int,
        minDurationSec: Int,
        maxDurationSec: Int,
        outputLanguage: String,
        speakerName: String?,
        mode: ShortsPlanLanguageMode,
        existingClips: [ShortsClipPlan] = []
    ) -> String {
        let modeInstruction: String
        let captionSchema: String
        switch mode {
        case .source:
            modeInstruction = "Analyze the source-language transcript and write title, summary, hook, category, and captionText in the source language."
            captionSchema = "Return only a JSON array. Each item must contain: start, end, title, summary, hook, category, captionText."
        case .bilingual:
            modeInstruction = "Analyze the paired source and target transcript. Choose moments that work well in both languages. For every item, write sourceTitle, sourceSummary, sourceHook, sourceCategory, sourceCaptionText in the source language, and targetTitle, targetSummary, targetHook, targetCategory, targetCaptionText in the target language. Also set title, summary, hook, category, captionText equal to the target-language values."
            captionSchema = "Return only a JSON array. Each item must contain: start, end, title, summary, hook, category, captionText, sourceTitle, sourceSummary, sourceHook, sourceCategory, sourceCaptionText, targetTitle, targetSummary, targetHook, targetCategory, targetCaptionText."
        case .target:
            modeInstruction = "Analyze the target-language transcript and write title, summary, hook, category, and captionText in \(outputLanguage)."
            captionSchema = "Return only a JSON array. Each item must contain: start, end, title, summary, hook, category, captionText."
        }

        let speakerMetadataLine: String
        if let speakerName, !speakerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            speakerMetadataLine = "Speaker metadata: \(speakerName.trimmingCharacters(in: .whitespacesAndNewlines)). When describing who is speaking, use this name or a respectful shortened form such as Maharaj or Swami. Do not write generic phrases like \"the speaker\", \"the speaker shares\", \"спикер\", or \"говорящий\" when this metadata is available."
        } else {
            speakerMetadataLine = "Speaker metadata is unknown. If you refer to the person speaking, use a generic phrase such as \"the speaker\"."
        }

        let existingRanges = existingRangesInstruction(existingClips)

        return """
        You are selecting clips for YouTube Shorts, Instagram Reels, and TikTok.
        Context: Vaishnava lecture. Prefer moments with a clear story, paradox, emotional point, practical teaching, or memorable quote.
        \(speakerMetadataLine)
        Find exactly \(count) candidate clips.
        Each clip must be between \(minDurationSec) and \(maxDurationSec) seconds.
        \(modeInstruction)
        \(captionSchema)
        captionText is the exact short-form subtitle script for this clip. It is not a summary.
        captionText must contain many dense timestamped subtitle cues, one cue per line, formatted exactly as "[MM:SS] text".
        Use absolute timestamps from the transcript, not relative timestamps. The first caption timestamp should be the clip start or the first spoken line inside the clip.
        Create a new caption cue roughly every 1.5-4 seconds, or whenever the spoken phrase naturally changes.
        Never put a whole 45-180 second clip into one or two caption cues. That makes the reel unusable.
        Each caption cue should fit on a phone screen: aim for one line, maximum two short lines, usually 3-10 words or about 18-42 characters.
        Preserve meaning and spoken order. Do not add commentary, explanations, markdown, numbering, or speaker labels inside captionText.
        For bilingual output, sourceCaptionText and targetCaptionText must use the same timestamp markers and the same number/order of cues so both videos stay aligned.
        Example captionText format: "[04:56] The spiritual city is\\n[04:59] the spiritual character of His residence\\n[05:03] In building the city of Mayapur"
        Use short category tags such as story, philosophy, quote, teaching, humor, or history.
        Do not invent timestamps. Use only timestamps from the transcript.
        Scan the full transcript from beginning to end. Do not default to the earliest strong moment when later distinct moments are available.
        \(existingRanges)

        Transcript:
        \(transcript)
        """
    }

    public static func parsePlanResponse(_ text: String) throws -> [ShortsClipPlan] {
        let clean = text
            .replacingRegex(#"(?i)^```(?:json)?\s*"#)
            .replacingRegex(#"\s*```$"#)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let start = clean.firstIndex(of: "["),
              let end = clean.lastIndex(of: "]"),
              start <= end
        else {
            throw ShortsPlannerError.missingJSONArray
        }

        let json = String(clean[start...end])
        guard let data = json.data(using: .utf8) else {
            throw ShortsPlannerError.invalidJSON
        }

        let rawPlans = try JSONDecoder().decode([RawShortsClipPlan].self, from: data)
        return rawPlans
            .map { raw in
                ShortsClipPlan(
                    start: raw.start ?? "",
                    end: raw.end ?? "",
                    title: raw.title ?? "",
                    summary: raw.summary ?? "",
                    hook: raw.hook ?? "",
                    category: raw.category ?? "clip",
                    sourceTitle: raw.sourceTitle,
                    sourceSummary: raw.sourceSummary,
                    sourceHook: raw.sourceHook,
                    sourceCategory: raw.sourceCategory,
                    targetTitle: raw.targetTitle,
                    targetSummary: raw.targetSummary,
                    targetHook: raw.targetHook,
                    targetCategory: raw.targetCategory,
                    captionText: raw.captionText,
                    sourceCaptionText: raw.sourceCaptionText,
                    targetCaptionText: raw.targetCaptionText,
                    languageMode: nil
                )
            }
            .filter { !$0.start.isEmpty && !$0.end.isEmpty && !$0.title.isEmpty }
    }

    public static func buildTranslationPrompt(plan: ShortsClipPlan, targetLanguage: String) -> String {
        """
        Translate this YouTube Shorts / Instagram Reels metadata to \(targetLanguage).
        Keep the meaning, tone, and timestamp markers. Do not change start or end time.
        Return only one JSON object with keys: title, summary, hook, category, captionText.
        captionText must preserve every timestamp marker exactly and keep one cue per line.

        Source metadata:
        title: \(plan.title)
        summary: \(plan.summary)
        hook: \(plan.hook)
        category: \(plan.category ?? "clip")
        captionText:
        \(plan.captionText ?? plan.targetCaptionText ?? plan.sourceCaptionText ?? "")
        """
    }

    public static func parseTranslationResponse(
        _ text: String,
        language: String,
        provider: String? = nil,
        updatedAt: String? = nil
    ) throws -> ShortsClipTranslation {
        let clean = text
            .replacingRegex(#"(?i)^```(?:json)?\s*"#)
            .replacingRegex(#"\s*```$"#)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let start = clean.firstIndex(of: "{"),
              let end = clean.lastIndex(of: "}"),
              start <= end
        else {
            throw ShortsPlannerError.missingJSONObject
        }

        let json = String(clean[start...end])
        guard let data = json.data(using: .utf8) else {
            throw ShortsPlannerError.invalidJSON
        }

        let raw = try JSONDecoder().decode(RawShortsClipTranslation.self, from: data)
        return ShortsClipTranslation(
            language: language,
            title: raw.title ?? "",
            summary: raw.summary ?? "",
            hook: raw.hook ?? "",
            category: raw.category,
            captionText: raw.captionText,
            provider: provider,
            updatedAt: updatedAt
        )
    }

    public static func parseTimestampToSeconds(_ timestamp: String) -> Double {
        let clean = timestamp
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        let parts = clean.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return 0 }
        if parts.count == 3 {
            return parts[0] * 3_600 + parts[1] * 60 + parts[2]
        }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        return parts[0]
    }

    public static func secondsToShortsTimestamp(_ totalSeconds: Double) -> String {
        let safe = max(0, Int(totalSeconds.rounded(.down)))
        let hours = safe / 3_600
        let minutes = (safe % 3_600) / 60
        let seconds = safe % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public static func validateClip(
        startSec: Double,
        endSec: Double,
        minDurationSec: Double,
        maxDurationSec: Double
    ) -> ClipValidationResult {
        let duration = endSec - startSec
        if duration < minDurationSec {
            return ClipValidationResult(ok: false, durationSec: duration, reason: "Clip is shorter than minimum duration.")
        }
        if duration > maxDurationSec {
            return ClipValidationResult(ok: false, durationSec: duration, reason: "Clip is longer than maximum duration.")
        }
        return ClipValidationResult(ok: true, durationSec: duration, reason: nil)
    }

    public static func appendNonOverlappingPlans(
        existingPlans: [ShortsClipPlan],
        incomingPlans: [ShortsClipPlan],
        excludedPlans: [ShortsClipPlan] = [],
        minOverlapSec: Double = 1,
        exclusionPaddingSec: Double = existingClipExclusionPaddingSec
    ) -> AppendShortsPlansResult {
        var plans = existingPlans
        var exclusionPlans = existingPlans + excludedPlans
        var addedIndexes: [Int] = []
        var skippedOverlapping: [ShortsClipPlan] = []

        for incoming in incomingPlans {
            let incomingRange = clipRange(incoming)
            let overlaps = exclusionPlans.contains { plan in
                overlapSeconds(incomingRange, exclusionWindow(for: plan, paddingSec: exclusionPaddingSec)) > minOverlapSec
            }
            if overlaps {
                skippedOverlapping.append(incoming)
                continue
            }
            addedIndexes.append(plans.count)
            plans.append(incoming)
            exclusionPlans.append(incoming)
        }

        return AppendShortsPlansResult(
            plans: plans,
            addedIndexes: addedIndexes,
            skippedOverlapping: skippedOverlapping
        )
    }

    public static func replacingClipRange(
        _ plan: ShortsClipPlan,
        start: String,
        end: String
    ) -> ShortsClipPlan {
        var replaced = plan
        replaced.start = start
        replaced.end = end
        replaced.captionText = nil
        replaced.sourceCaptionText = nil
        replaced.targetCaptionText = nil
        replaced.sourceAlignment = nil
        replaced.targetAlignment = nil
        replaced.timelineCuts = []
        replaced.timelineTrim = .zero
        return replaced
    }

    private static func existingRangesInstruction(_ existingClips: [ShortsClipPlan]) -> String {
        let ranges = existingClips
            .filter { !$0.start.isEmpty && !$0.end.isEmpty }
            .enumerated()
            .map { index, clip in
                let title = clip.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(index + 1). \(clip.start) -> \(clip.end)\(title.isEmpty ? "" : " - \(title)")"
            }
        guard !ranges.isEmpty else { return "" }
        let excludedWindows = existingClips
            .filter { !$0.start.isEmpty && !$0.end.isEmpty }
            .enumerated()
            .map { index, clip in
                let window = exclusionWindow(for: clip, paddingSec: existingClipExclusionPaddingSec)
                let title = clip.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(index + 1). \(secondsToShortsTimestamp(window.startSec)) -> \(secondsToShortsTimestamp(window.endSec))\(title.isEmpty ? "" : " - \(title)")"
            }
        return (
            ["Already selected or rejected ranges:"] +
            ranges +
            ["Do not choose moments that overlap any already selected or rejected range.",
             "",
             "Excluded timeline windows (selected or rejected ranges plus \(Int(existingClipExclusionPaddingSec)) seconds of context on both sides):"] +
            excludedWindows +
            ["Do not inspect, quote, continue, summarize, or select anything from the excluded timeline windows above, even if the transcript text appears later in this prompt.",
             "Find different, non-overlapping moments outside these windows. Avoid repeating the same title, hook, teaching, story, or immediate continuation of any already selected or rejected clip."]
        ).joined(separator: "\n")
    }

    private static func clipRange(_ plan: ShortsClipPlan) -> (startSec: Double, endSec: Double) {
        let startSec = parseTimestampToSeconds(plan.start)
        let endSec = parseTimestampToSeconds(plan.end)
        return (min(startSec, endSec), max(startSec, endSec))
    }

    private static func exclusionWindow(
        for plan: ShortsClipPlan,
        paddingSec: Double
    ) -> (startSec: Double, endSec: Double) {
        let range = clipRange(plan)
        return (
            max(0, range.startSec - max(0, paddingSec)),
            range.endSec + max(0, paddingSec)
        )
    }

    private static func overlapSeconds(
        _ a: (startSec: Double, endSec: Double),
        _ b: (startSec: Double, endSec: Double)
    ) -> Double {
        max(0, min(a.endSec, b.endSec) - max(a.startSec, b.startSec))
    }
}

public enum ShortsPlannerError: LocalizedError {
    case missingJSONArray
    case missingJSONObject
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .missingJSONArray:
            "Shorts plan response did not contain a JSON array."
        case .missingJSONObject:
            "Shorts translation response did not contain a JSON object."
        case .invalidJSON:
            "Shorts plan response was not valid JSON."
        }
    }
}

private struct RawShortsClipPlan: Decodable {
    var start: String?
    var end: String?
    var title: String?
    var summary: String?
    var hook: String?
    var category: String?
    var sourceTitle: String?
    var sourceSummary: String?
    var sourceHook: String?
    var sourceCategory: String?
    var targetTitle: String?
    var targetSummary: String?
    var targetHook: String?
    var targetCategory: String?
    var captionText: String?
    var sourceCaptionText: String?
    var targetCaptionText: String?
}

private struct RawShortsClipTranslation: Decodable {
    var title: String?
    var summary: String?
    var hook: String?
    var category: String?
    var captionText: String?
}

private extension String {
    func replacingRegex(_ pattern: String, with replacement: String = "") -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: replacement)
    }
}
