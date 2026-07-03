import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Universal Shorts/Reels planner")
struct ShortsPlannerTests {
    @Test("builds bilingual planning prompt")
    func buildsBilingualPrompt() {
        let prompt = ShortsPlanner.buildPrompt(
            transcript: "[04:56] The spiritual city is...",
            count: 3,
            minDurationSec: 30,
            maxDurationSec: 90,
            outputLanguage: "Russian",
            speakerName: "Kadamba Kanana Swami",
            mode: .bilingual
        )

        #expect(prompt.contains("Find exactly 3 candidate clips"))
        #expect(prompt.contains("between 30 and 90 seconds"))
        #expect(prompt.contains("Kadamba Kanana Swami"))
        #expect(prompt.contains("sourceTitle"))
        #expect(prompt.contains("targetTitle"))
    }

    @Test("planning prompt asks the model to avoid existing clip ranges")
    func buildPromptIncludesExistingRanges() {
        let prompt = ShortsPlanner.buildPrompt(
            transcript: "[04:56] The spiritual city is...",
            count: 2,
            minDurationSec: 30,
            maxDurationSec: 90,
            outputLanguage: "Russian",
            speakerName: nil,
            mode: .target,
            existingClips: [
                ShortsClipPlan(
                    start: "04:56",
                    end: "05:40",
                    title: "A spiritual city",
                    summary: "Meaningful moment",
                    hook: "What makes a place spiritual?"
                )
            ]
        )

        #expect(prompt.contains("Already selected or rejected ranges:"))
        #expect(prompt.contains("1. 04:56 -> 05:40 - A spiritual city"))
        #expect(prompt.contains("Do not choose moments that overlap any already selected or rejected range."))
        #expect(prompt.contains("Scan the full transcript from beginning to end."))
    }

    @Test("planning prompt excludes buffered windows around existing clips")
    func buildPromptIncludesBufferedExcludedWindows() {
        let prompt = ShortsPlanner.buildPrompt(
            transcript: "[03:00] Giving in Mayapur...\n\n[05:02] Giving in Mayapur continues...",
            count: 1,
            minDurationSec: 50,
            maxDurationSec: 200,
            outputLanguage: "Russian",
            speakerName: nil,
            mode: .source,
            existingClips: [
                ShortsClipPlan(
                    start: "03:00",
                    end: "04:59",
                    title: "The Economy of Giving in Mayapur",
                    summary: "Already selected.",
                    hook: "Already selected."
                )
            ]
        )

        #expect(prompt.contains("Excluded timeline windows"))
        #expect(prompt.contains("02:45 -> 05:14"))
        #expect(prompt.contains("Do not inspect, quote, continue, summarize, or select"))
        #expect(prompt.contains("The Economy of Giving in Mayapur"))
    }

    @Test("parses JSON plan from fenced model response")
    func parsesPlanResponse() throws {
        let response = """
        ```json
        [
          {"start":"04:56","end":"05:40","title":"A spiritual city","summary":"Meaningful moment","hook":"What makes a place spiritual?","category":"philosophy","captionText":"[04:56] The spiritual city is"}
        ]
        ```
        """

        let plans = try ShortsPlanner.parsePlanResponse(response)

        #expect(plans.count == 1)
        #expect(plans[0].start == "04:56")
        #expect(plans[0].title == "A spiritual city")
        #expect(plans[0].category == "philosophy")
    }

    @Test("validates clip duration bounds")
    func validatesClipDuration() {
        let valid = ShortsPlanner.validateClip(startSec: 10, endSec: 70, minDurationSec: 30, maxDurationSec: 90)
        let short = ShortsPlanner.validateClip(startSec: 10, endSec: 20, minDurationSec: 30, maxDurationSec: 90)
        let long = ShortsPlanner.validateClip(startSec: 10, endSec: 150, minDurationSec: 30, maxDurationSec: 90)

        #expect(valid.ok)
        #expect(!short.ok)
        #expect(short.reason == "Clip is shorter than minimum duration.")
        #expect(!long.ok)
        #expect(long.reason == "Clip is longer than maximum duration.")
    }

    @Test("appends non-overlapping Shorts plans without replacing edited clips")
    func appendNonOverlappingPlansPreservesExistingClips() {
        let existing = [
            ShortsClipPlan(
                start: "00:30",
                end: "01:18",
                title: "Existing edited clip",
                summary: "Already tuned",
                hook: "Existing hook"
            )
        ]
        let incoming = [
            ShortsClipPlan(
                start: "00:45",
                end: "01:20",
                title: "Overlaps existing",
                summary: "Duplicate range",
                hook: "Duplicate hook"
            ),
            ShortsClipPlan(
                start: "02:00",
                end: "02:40",
                title: "Fresh clip",
                summary: "New range",
                hook: "New hook"
            )
        ]

        let result = ShortsPlanner.appendNonOverlappingPlans(existingPlans: existing, incomingPlans: incoming)

        #expect(result.plans.map(\.title) == ["Existing edited clip", "Fresh clip"])
        #expect(result.addedIndexes == [1])
        #expect(result.skippedOverlapping.map(\.title) == ["Overlaps existing"])
    }

    @Test("skips adjacent duplicate Shorts candidates inside existing clip exclusion buffer")
    func appendNonOverlappingPlansSkipsAdjacentDuplicatesInsideExclusionBuffer() {
        let existing = [
            ShortsClipPlan(
                start: "03:00",
                end: "04:59",
                title: "The Economy of Giving in Mayapur",
                summary: "Already selected.",
                hook: "Already selected."
            )
        ]
        let incoming = [
            ShortsClipPlan(
                start: "05:02",
                end: "07:17",
                title: "The Economy of Giving in Mayapur",
                summary: "Same idea continued immediately after the existing clip.",
                hook: "Same hook."
            ),
            ShortsClipPlan(
                start: "08:00",
                end: "09:20",
                title: "A different teaching",
                summary: "Separate part of the lecture.",
                hook: "A new point."
            )
        ]

        let result = ShortsPlanner.appendNonOverlappingPlans(existingPlans: existing, incomingPlans: incoming)

        #expect(result.plans.map(\.title) == ["The Economy of Giving in Mayapur", "A different teaching"])
        #expect(result.addedIndexes == [1])
        #expect(result.skippedOverlapping.map(\.title) == ["The Economy of Giving in Mayapur"])
    }

    @Test("skips candidates overlapping deleted Shorts without showing deleted clips again")
    func appendNonOverlappingPlansUsesRejectedPlansAsHiddenExclusions() {
        let rejected = [
            ShortsClipPlan(
                start: "03:00",
                end: "04:59",
                title: "Rejected economy clip",
                summary: "The user deleted this moment.",
                hook: "Do not suggest again."
            )
        ]
        let incoming = [
            ShortsClipPlan(
                start: "05:02",
                end: "07:17",
                title: "Same economy clip again",
                summary: "Immediate continuation of the deleted moment.",
                hook: "Repeat."
            ),
            ShortsClipPlan(
                start: "20:00",
                end: "21:10",
                title: "Fresh later clip",
                summary: "A different part of the lecture.",
                hook: "New moment."
            )
        ]

        let result = ShortsPlanner.appendNonOverlappingPlans(
            existingPlans: [],
            incomingPlans: incoming,
            excludedPlans: rejected
        )

        #expect(result.plans.map(\.title) == ["Fresh later clip"])
        #expect(result.addedIndexes == [0])
        #expect(result.skippedOverlapping.map(\.title) == ["Same economy clip again"])
    }

    @Test("session preserves rejected Shorts plans for future planning exclusions")
    func sessionPreservesRejectedShortsPlans() throws {
        let rejected = ShortsClipPlan(
            start: "03:00",
            end: "04:59",
            title: "Rejected economy clip",
            summary: "The user deleted this moment.",
            hook: "Do not suggest again."
        )
        let session = SessionState(
            sourceFile: "/tmp/source.mov",
            sourceFileName: "source.mov",
            durationSec: 3600,
            metadata: .empty,
            sourceLang: "English",
            targetLang: "Russian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "gemini-cloud",
            outputFormats: [.txt],
            chunks: [],
            currentChunkIndex: 0,
            shortsRejectedPlans: [rejected]
        )

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SessionState.self, from: data)

        #expect(decoded.shortsRejectedPlans?.map(\.title) == ["Rejected economy clip"])
    }

    @Test("replace range clears stale captions and alignments so subtitles rebuild from transcript cues")
    func replaceRangeClearsGeneratedCaptionState() {
        let replaced = ShortsPlanner.replacingClipRange(
            ShortsClipPlan(
                start: "00:48",
                end: "01:48",
                title: "Generated clip",
                summary: "Good moment.",
                hook: "Strong hook.",
                category: "clip",
                captionText: "[00:48] Old target caption",
                sourceCaptionText: "[00:48] Old source caption",
                targetCaptionText: "[00:48] Old target caption",
                sourceAlignment: [
                    AlignedSubtitleSegment(id: "source-sub", start: 0, end: 2, text: "Old source")
                ],
                targetAlignment: [
                    AlignedSubtitleSegment(id: "target-sub", start: 0, end: 2, text: "Old target")
                ],
                sourceFrameKeyframes: [
                    FrameKeyframe(id: "kf", time: 0, x: 50, y: 50, zoom: 1)
                ],
                syncEnabled: true,
                timelineCuts: [TimelineCut(startSec: 5, endSec: 8)],
                timelineTrim: TimelineTrim(trimStartSec: 2, trimEndSec: 1)
            ),
            start: "00:30",
            end: "01:48"
        )

        #expect(replaced.start == "00:30")
        #expect(replaced.end == "01:48")
        #expect(replaced.captionText == nil)
        #expect(replaced.sourceCaptionText == nil)
        #expect(replaced.targetCaptionText == nil)
        #expect(replaced.sourceAlignment == nil)
        #expect(replaced.targetAlignment == nil)
        #expect(replaced.timelineCuts?.isEmpty == true)
        #expect(replaced.timelineTrim == .zero)
        #expect(replaced.sourceFrameKeyframes == [FrameKeyframe(id: "kf", time: 0, x: 50, y: 50, zoom: 1)])
        #expect(replaced.syncEnabled == true)
    }

    @Test("stores translated Shorts metadata by language")
    func storesTranslatedShortsMetadataByLanguage() throws {
        var plan = ShortsClipPlan(
            start: "04:56",
            end: "05:40",
            title: "A spiritual city",
            summary: "Meaningful moment",
            hook: "What makes a place spiritual?",
            category: "philosophy",
            sourceTitle: nil,
            sourceSummary: nil,
            sourceHook: nil,
            sourceCategory: nil,
            targetTitle: nil,
            targetSummary: nil,
            targetHook: nil,
            targetCategory: nil,
            captionText: "[04:56] The spiritual city is",
            sourceCaptionText: nil,
            targetCaptionText: nil,
            languageMode: .source
        )

        plan.setTranslation(
            ShortsClipTranslation(
                language: "German",
                title: "Eine spirituelle Stadt",
                summary: "Bedeutungsvoller Moment",
                hook: "Was macht einen Ort spirituell?",
                category: "philosophy",
                captionText: "[04:56] Die spirituelle Stadt ist",
                provider: "mlx-native",
                updatedAt: "2026-05-26T10:00:00Z"
            )
        )

        let translated = try #require(plan.translation(for: "German"))
        #expect(translated.title == "Eine spirituelle Stadt")
        #expect(translated.captionText == "[04:56] Die spirituelle Stadt ist")
        #expect(plan.translation(for: "Russian") == nil)
    }

    @Test("parses translated Shorts metadata response")
    func parsesTranslatedShortsMetadataResponse() throws {
        let response = """
        ```json
        {"title":"Eine spirituelle Stadt","summary":"Bedeutungsvoller Moment","hook":"Was macht einen Ort spirituell?","category":"philosophy","captionText":"[04:56] Die spirituelle Stadt ist"}
        ```
        """

        let translation = try ShortsPlanner.parseTranslationResponse(response, language: "German", provider: "mlx-native")

        #expect(translation.language == "German")
        #expect(translation.title == "Eine spirituelle Stadt")
        #expect(translation.captionText == "[04:56] Die spirituelle Stadt ist")
        #expect(translation.provider == "mlx-native")
    }

    @Test("exports selected Shorts ideas as text and JSON")
    func exportsSelectedShortsIdeas() throws {
        let plans = [
            ShortsClipPlan(
                start: "04:56",
                end: "05:40",
                title: "A spiritual city",
                summary: "Meaningful moment",
                hook: "What makes a place spiritual?",
                category: "philosophy",
                sourceTitle: "A spiritual city",
                sourceSummary: "Meaningful moment",
                sourceHook: "What makes a place spiritual?",
                sourceCategory: "philosophy",
                targetTitle: "Духовный город",
                targetSummary: "Важный момент",
                targetHook: "Что делает место духовным?",
                targetCategory: "философия",
                captionText: "[04:56] The spiritual city is",
                sourceCaptionText: "[04:56] The spiritual city is",
                targetCaptionText: "[04:56] Духовный город",
                languageMode: .bilingual
            )
        ]

        let text = ShortsIdeasExporter.renderText(plans: plans, displayLanguage: .target)
        #expect(text.contains("Духовный город"))
        #expect(text.contains("04:56 -> 05:40"))
        #expect(text.contains("[04:56] Духовный город"))

        let json = try ShortsIdeasExporter.renderJSON(plans: plans, displayLanguage: .source)
        #expect(json.contains(#""title" : "A spiritual city""#))
        #expect(json.contains(#""start" : "04:56""#))
    }

    @Test("extracts source and target transcript text for Shorts details")
    func extractsShortsDetailsTranscriptRange() throws {
        var chunk = ChunkData(
            index: 0,
            filePath: "/tmp/chunk.wav",
            durationSec: 90,
            startSec: 240,
            endSec: 330,
            original: "Full source chunk",
            translated: "",
            originalCues: [
                TranscriptCue(startSec: 0, endSec: 3, text: "Before clip"),
                TranscriptCue(startSec: 16, endSec: 20, text: "This is the selected source text"),
                TranscriptCue(startSec: 35, endSec: 40, text: "After clip")
            ],
            status: .done,
            approved: true
        )
        chunk.setTranslation(
            "Full target chunk",
            language: "Russian",
            cues: [
                TranscriptCue(startSec: 0, endSec: 3, text: "До клипа"),
                TranscriptCue(startSec: 16, endSec: 20, text: "Это выбранный переведенный текст"),
                TranscriptCue(startSec: 35, endSec: 40, text: "После клипа")
            ]
        )
        let session = SessionState(
            sourceFile: "/tmp/source.mov",
            sourceFileName: "source.mov",
            durationSec: 360,
            metadata: .empty,
            sourceLang: "English",
            targetLang: "Russian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "mlx",
            outputFormats: [.txt],
            chunks: [chunk],
            currentChunkIndex: 0,
            activeTranslationLanguage: "Russian"
        )
        let plan = ShortsClipPlan(
            start: "04:15",
            end: "04:25",
            title: "Clip",
            summary: "Summary",
            hook: "Hook",
            category: "clip",
            captionText: "[04:16] caption",
            languageMode: .bilingual
        )

        let detail = ShortsTranscriptExtractor.extract(plan: plan, session: session, targetLanguage: "Russian")

        #expect(detail.source.contains("[04:16] This is the selected source text"))
        #expect(!detail.source.contains("Before clip"))
        #expect(detail.target.contains("[04:16] Это выбранный переведенный текст"))
        #expect(!detail.target.contains("После клипа"))

        let sourceSegments = ShortsVisualEditorStateBuilder.segments(
            fromCaptionText: detail.source,
            clipStartSec: ShortsPlanner.parseTimestampToSeconds(plan.start),
            clipEndSec: ShortsPlanner.parseTimestampToSeconds(plan.end)
        )
        let targetSegments = ShortsVisualEditorStateBuilder.segments(
            fromCaptionText: detail.target,
            clipStartSec: ShortsPlanner.parseTimestampToSeconds(plan.start),
            clipEndSec: ShortsPlanner.parseTimestampToSeconds(plan.end)
        )
        #expect(sourceSegments.map(\.text) == ["This is the selected source text"])
        #expect(targetSegments.map(\.text) == ["Это выбранный переведенный текст"])
        #expect(sourceSegments.first?.start == 1)
        #expect(targetSegments.first?.start == 1)
    }

    @Test("builds Shorts planning transcript from structured cues instead of raw chunk text")
    func buildsPlanningTranscriptFromStructuredCues() {
        var chunk = ChunkData(
            index: 0,
            filePath: "/tmp/chunk.wav",
            durationSec: 60,
            startSec: 120,
            endSec: 180,
            original: "",
            translated: "",
            originalCues: [
                TranscriptCue(startSec: 3, endSec: 6, text: "First approved source cue"),
                TranscriptCue(startSec: 9, endSec: 12, text: "Second approved source cue")
            ],
            status: .done,
            approved: true
        )
        chunk.setTranslation(
            "Full target fallback",
            language: "Russian",
            cues: [
                TranscriptCue(startSec: 3, endSec: 6, text: "Первый утвержденный перевод"),
                TranscriptCue(startSec: 9, endSec: 12, text: "Второй утвержденный перевод")
            ]
        )
        let session = SessionState(
            sourceFile: "/tmp/source.mov",
            sourceFileName: "source.mov",
            durationSec: 180,
            metadata: .empty,
            sourceLang: "English",
            targetLang: "Russian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "mlx",
            outputFormats: [.txt],
            chunks: [chunk],
            currentChunkIndex: 0,
            activeTranslationLanguage: "Russian"
        )

        let source = ShortsTranscriptExtractor.planningTranscript(session: session, mode: .source)
        let target = ShortsTranscriptExtractor.planningTranscript(session: session, mode: .target)

        #expect(source.contains("[02:03] First approved source cue"))
        #expect(source.contains("[02:09] Second approved source cue"))
        #expect(!source.contains("Full target fallback"))
        #expect(target.contains("[02:03] Первый утвержденный перевод"))
        #expect(target.contains("[02:09] Второй утвержденный перевод"))
        #expect(!target.contains("Full target fallback"))
    }

    @Test("builds bilingual planning transcript by pairing source and target cues by time")
    func buildsBilingualPlanningTranscriptFromNearestCues() {
        var chunk = ChunkData(
            index: 0,
            filePath: "/tmp/chunk.wav",
            durationSec: 20,
            startSec: 0,
            endSec: 20,
            original: "Fallback source",
            translated: "",
            originalCues: [
                TranscriptCue(startSec: 1, endSec: 3, text: "Source first"),
                TranscriptCue(startSec: 7, endSec: 9, text: "Source second")
            ],
            status: .done,
            approved: true
        )
        chunk.setTranslation(
            "Fallback target",
            language: "Russian",
            cues: [
                TranscriptCue(startSec: 1.2, endSec: 3.2, text: "Цель первая"),
                TranscriptCue(startSec: 7.1, endSec: 9.1, text: "Цель вторая")
            ]
        )
        let session = SessionState(
            sourceFile: "/tmp/source.mov",
            sourceFileName: "source.mov",
            durationSec: 20,
            metadata: .empty,
            sourceLang: "English",
            targetLang: "Russian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "mlx",
            outputFormats: [.txt],
            chunks: [chunk],
            currentChunkIndex: 0,
            activeTranslationLanguage: "Russian"
        )

        let transcript = ShortsTranscriptExtractor.planningTranscript(session: session, mode: .bilingual)

        #expect(transcript.contains("[00:01]\nSource: Source first\nTarget: Цель первая"))
        #expect(transcript.contains("[00:07]\nSource: Source second\nTarget: Цель вторая"))
    }
}
