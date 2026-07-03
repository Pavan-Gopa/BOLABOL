import Foundation
import CoreGraphics
import Testing
@testable import VaniScriptCore

@Suite("Universal visual clip editor state")
struct ShortsVisualEditorStateTests {
    private func expectApprox(_ actual: Double, _ expected: Double, tolerance: Double = 0.0001) {
        #expect(abs(actual - expected) <= tolerance)
    }

    @Test("decodes Universal visual editor fields")
    func decodesUniversalVisualEditorFields() throws {
        let json = """
        {
          "start": "13:48",
          "end": "15:59",
          "title": "Prabhupada's Architect",
          "summary": "A story clip",
          "hook": "A striking moment",
          "category": "story",
          "languageMode": "bilingual",
          "linkedClipGroupId": "group_1",
          "syncEnabled": true,
          "sourceAlignment": [
            {
              "id": "source-1",
              "start": 0,
              "end": 3,
              "text": "and he visited Mumbai",
              "words": [
                { "id": "word-1", "text": "and", "start": 0, "end": 0.3 }
              ]
            }
          ],
          "targetAlignment": [
            {
              "id": "target-1",
              "start": 0,
              "end": 3,
              "text": "и он посетил Мумбаи",
              "words": []
            }
          ],
          "sourceFrameKeyframes": [
            { "id": "frame-1", "time": 0, "x": 5, "y": -2, "zoom": 1.15, "backgroundColor": "#ffaa19" }
          ],
          "timelineCuts": [
            { "startSec": 6, "endSec": 8 }
          ],
          "timelineTrim": { "trimStartSec": 1, "trimEndSec": 2 },
          "subtitleStyle": {
            "fontFamily": "Cuprum",
            "fontSize": 74,
            "bold": true,
            "textTransform": "uppercase",
            "textColor": "#FFFFFF",
            "boxColor": "#FF8C00",
            "boxOpacity": 0.5,
            "boxWidth": 86,
            "boxHeight": 1,
            "edgeBlur": 0,
            "letterSpacing": 0,
            "lineSpacing": 1,
            "edgeSoftness": 0.25,
            "outline": 3,
            "shadow": 4
          },
          "backgroundSettings": {
            "solidEnabled": true,
            "solidColor": "#000000",
            "blurEnabled": true,
            "blurStrength": 30,
            "blurScale": 1.3,
            "gradientEnabled": false,
            "gradientType": "linear",
            "gradientColorA": "#000000",
            "gradientColorB": "#1a1a2e",
            "gradientAngle": 180,
            "gradientOpacity": 0.6,
            "featherEnabled": false,
            "featherTop": 20,
            "featherBottom": 20,
            "featherLeft": 10,
            "featherRight": 10,
            "frameGuideColor": "#ffaa19",
            "frameGuideOpacity": 0.5,
            "frameGuideBorderWidth": 2,
            "frameGuideBlur": 0,
            "frameGuideBorderOpacity": 1
          }
        }
        """

        let plan = try JSONDecoder().decode(ShortsClipPlan.self, from: Data(json.utf8))

        #expect(plan.syncEnabled == true)
        #expect(plan.linkedClipGroupId == "group_1")
        #expect(plan.sourceAlignment?.first?.text == "and he visited Mumbai")
        #expect(plan.targetAlignment?.first?.text == "и он посетил Мумбаи")
        #expect(plan.sourceFrameKeyframes?.first?.zoom == 1.15)
        #expect(plan.timelineCuts?.first?.startSec == 6)
        #expect(plan.timelineTrim?.trimEndSec == 2)
        #expect(plan.subtitleStyle?.fontFamily == "Cuprum")
        #expect(plan.backgroundSettings?.blurEnabled == true)
    }

    @Test("visual editor preview canvas preserves source aspect around centered shorts guide")
    func visualEditorPreviewCanvasPreservesSourceAspectAroundCenteredShortsGuide() {
        let sourceSize = CGSize(width: 3840, height: 2160)
        let canvas = VisualEditorPreviewCanvas.size(for: sourceSize, exportResolution: "Source-based")

        #expect(canvas.height == 2160)
        #expect(canvas.width == 3840)

        let guideWidth = Double(canvas.height) * 9.0 / 16.0
        #expect(Double(canvas.width) > guideWidth)
    }

    @Test("builds local subtitle segments from absolute caption text")
    func buildsLocalSubtitleSegmentsFromAbsoluteCaptionText() {
        let segments = ShortsVisualEditorStateBuilder.segments(
            fromCaptionText: """
            [13:48] and he visited Mumbai
            [13:51] before he came
            [13:54] to Krishna consciousness.
            """,
            clipStartSec: 13 * 60 + 48,
            clipEndSec: 15 * 60 + 59
        )

        #expect(segments.count == 3)
        #expect(segments[0].start == 0)
        #expect(segments[0].end == 3)
        #expect(segments[1].start == 3)
        #expect(segments[2].end == 131)
        #expect(segments[0].words.count == 4)
        #expect(segments[0].words.first?.text == "and")
    }

    @Test("matches Universal orange impact subtitle defaults")
    func matchesUniversalOrangeImpactSubtitleDefaults() {
        let style = ShortsSubtitleStyle.orangeImpact

        #expect(style.fontFamily == "Cuprum")
        #expect(style.fontSize == 74)
        #expect(style.bold)
        #expect(style.textTransform == .uppercase)
        #expect(style.boxColor == "#FF8C00")
        #expect(style.boxOpacity == 0.5)
    }

    @Test("decodes partial Universal text track style as overrides over subtitle defaults")
    func decodesPartialUniversalTextTrackStyleAsOverridesOverSubtitleDefaults() throws {
        let json = """
        {
          "start": "13:48",
          "end": "15:59",
          "title": "Prabhupada's Architect",
          "summary": "A story clip",
          "hook": "A striking moment",
          "sourceTextTracks": [
            {
              "id": "track-1",
              "name": "Text Track 1",
              "hidden": false,
              "blocks": [
                { "id": "block-1", "startSec": 40, "endSec": 44, "text": "PRABHUPADA'S EYES" }
              ],
              "style": {
                "boxColor": "#ffffff",
                "edgeBlur": 16,
                "edgeSoftness": 0.2,
                "boxHeight": 3.1
              }
            }
          ]
        }
        """

        let plan = try JSONDecoder().decode(ShortsClipPlan.self, from: Data(json.utf8))
        let style = try #require(plan.sourceTextTracks?.first?.style)

        #expect(style.fontFamily == ShortsSubtitleStyle.orangeImpact.fontFamily)
        #expect(style.fontSize == ShortsSubtitleStyle.orangeImpact.fontSize)
        #expect(style.bold == ShortsSubtitleStyle.orangeImpact.bold)
        #expect(style.textTransform == ShortsSubtitleStyle.orangeImpact.textTransform)
        #expect(style.textColor == ShortsSubtitleStyle.orangeImpact.textColor)
        #expect(style.boxOpacity == ShortsSubtitleStyle.orangeImpact.boxOpacity)
        #expect(style.boxWidth == ShortsSubtitleStyle.orangeImpact.boxWidth)
        #expect(style.lineSpacing == ShortsSubtitleStyle.orangeImpact.lineSpacing)
        #expect(style.outline == ShortsSubtitleStyle.orangeImpact.outline)
        #expect(style.shadow == ShortsSubtitleStyle.orangeImpact.shadow)
        #expect(style.boxColor == "#ffffff")
        #expect(style.edgeBlur == 16)
        #expect(style.edgeSoftness == 0.2)
        #expect(style.boxHeight == 3.1)
    }

    @Test("builds native render plan with trim cuts layers and shifted captions")
    func buildsNativeRenderPlanWithTrimCutsLayersAndShiftedCaptions() {
        var plan = ShortsClipPlan(
            start: "13:48",
            end: "14:08",
            title: "Source title",
            summary: "Summary",
            hook: "Hook",
            category: "story"
        )
        plan.sourceCaptionText = """
        [13:48] first line
        [13:52] second line
        [13:58] third line
        """
        plan.timelineTrim = TimelineTrim(trimStartSec: 2, trimEndSec: 1)
        plan.timelineCuts = [TimelineCut(startSec: 7, endSec: 9)]
        plan.sourceFrameKeyframes = [
            FrameKeyframe(id: "f0", time: 0, x: 0, y: 0, zoom: 1),
            FrameKeyframe(id: "f1", time: 8, x: 12, y: -3, zoom: 1.25)
        ]
        plan.sourceLogo = LogoOverlaySettings(id: "logo", src: "file:///tmp/logo.png", size: 1.2, opacity: 0.8)
        plan.sourceTextTracks = [
            TextOverlayTrack(
                id: "track",
                name: "CTA",
                blocks: [TextOverlayBlock(id: "block", startSec: 5, endSec: 8, text: "Subscribe")]
            )
        ]
        plan.sourceAudioTracks = [
            ExtraAudioTrack(
                id: "music",
                name: "Music",
                src: "file:///tmp/music.m4a",
                startSec: 3,
                trimStartSec: 1,
                trimEndSec: 0,
                volume: 0.5,
                fadeInSec: 0.3,
                fadeOutSec: 0.2
            )
        ]
        plan.sourceIntro = IntroOutroOverlaySettings(
            id: "intro",
            src: "file:///tmp/intro.png",
            duration: 2,
            x: 50,
            y: 45,
            scale: 0.8,
            animation: "fade"
        )

        let render = NativeShortsRenderPlanBuilder.build(
            id: "render-1",
            plan: plan,
            language: .source,
            outputWidth: 1080,
            outputHeight: 1920,
            fps: 30
        )

        #expect(render.width == 1080)
        #expect(render.height == 1920)
        #expect(render.fps == 30)
        #expect(render.timelineTrim.trimStartSec == 2)
        #expect(render.mediaSegments.count == 2)
        #expect(render.mediaSegments[0].sourceStartSec == 13 * 60 + 50)
        #expect(render.mediaSegments[0].outputStartSec == 2)
        #expect(render.subtitles.first?.startSec == 2)
        #expect(render.subtitles[1].startSec == 4)
        #expect(render.textTracks.first?.blocks.first?.startSec == 5)
        #expect(render.audioTracks.first?.startSec == 3)
        #expect(render.logo?.id == "logo")
        #expect(render.intro?.id == "intro")
    }

    @Test("native render plan does not restore source media when cut range removes the active range")
    func nativeRenderPlanDoesNotRestoreSourceMediaWhenCutRangeRemovesActiveRange() {
        var plan = ShortsClipPlan(
            start: "00:00",
            end: "00:10",
            title: "Cut range removes all",
            summary: "Summary",
            hook: "Hook"
        )
        plan.timelineCuts = [TimelineCut(startSec: 0, endSec: 10)]

        let render = NativeShortsRenderPlanBuilder.build(
            id: "render-cut-all",
            plan: plan,
            language: .source,
            outputWidth: 1080,
            outputHeight: 1920,
            fps: 25
        )

        #expect(render.timelineCuts.count == 1)
        #expect(render.mediaSegments.isEmpty)
        #expect(render.durationSec == 0.05)
    }

    @Test("builds native render plan and retimes elements after cuts correctly")
    func buildsNativeRenderPlanAndRetimesElementsAfterCutsCorrectly() {
        var plan = ShortsClipPlan(
            start: "00:00",
            end: "00:20",
            title: "Retime test",
            summary: "Summary",
            hook: "Hook"
        )
        plan.sourceCaptionText = """
        [00:00] first
        [00:05] second
        [00:12] third
        """
        plan.timelineTrim = TimelineTrim(trimStartSec: 0, trimEndSec: 0)
        // Cut 8s to 10s (duration 2s)
        plan.timelineCuts = [TimelineCut(startSec: 8, endSec: 10)]
        plan.sourceFrameKeyframes = [
            FrameKeyframe(id: "f0", time: 4, x: 0, y: 0, zoom: 1),
            FrameKeyframe(id: "f1", time: 14, x: 10, y: 10, zoom: 1.5)
        ]
        plan.sourceTextTracks = [
            TextOverlayTrack(
                id: "t1",
                name: "Track",
                blocks: [
                    TextOverlayBlock(id: "b1", startSec: 5, endSec: 7, text: "before cut"),
                    TextOverlayBlock(id: "b2", startSec: 11, endSec: 13, text: "after cut")
                ]
            )
        ]
        plan.sourceAudioTracks = [
            ExtraAudioTrack(
                id: "a1",
                name: "Audio",
                src: "file:///tmp/music.m4a",
                startSec: 15,
                trimStartSec: 0,
                trimEndSec: 0,
                volume: 0.5,
                fadeInSec: 0,
                fadeOutSec: 0,
                assetDuration: 10
            )
        ]

        let render = NativeShortsRenderPlanBuilder.build(
            id: "retime-render",
            plan: plan,
            language: .source,
            outputWidth: 1080,
            outputHeight: 1920,
            fps: 30
        )

        // Verifications
        // Cut is 8 to 10 (duration 2s).
        // 1. Subtitles:
        // "first" (0s) -> before cut -> unchanged (0s)
        // "second" (5s) -> before cut -> split by cut -> 5s to 8s (part 1) and 8s to 10s (part 2)
        // "third" (12s) -> after cut -> shifted left by 2s -> 10s
        #expect(render.subtitles.count == 4)
        #expect(render.subtitles[0].startSec == 0)
        #expect(render.subtitles[1].startSec == 5)
        #expect(render.subtitles[2].startSec == 8)
        #expect(render.subtitles[3].startSec == 10)

        // 2. Keyframes:
        // f0 (4s) -> before cut -> unchanged (4s)
        // f1 (14s) -> after cut -> shifted left by 2s -> 12s
        #expect(render.frameKeyframes.contains { $0.id == "f0" && $0.time == 4 })
        #expect(render.frameKeyframes.contains { $0.id == "f1" && $0.time == 12 })

        // 3. TextTracks:
        // b1 (5s to 7s) -> before cut -> unchanged (5s to 7s)
        // b2 (11s to 13s) -> after cut -> shifted left by 2s -> 9s to 11s
        let textBlocks = render.textTracks.first?.blocks ?? []
        #expect(textBlocks.count == 2)
        #expect(textBlocks[0].startSec == 5 && textBlocks[0].endSec == 7)
        #expect(textBlocks[1].startSec == 9 && textBlocks[1].endSec == 11)

        // 4. AudioTracks:
        // a1 (15s) -> after cut -> shifted left by 2s -> 13s
        #expect(render.audioTracks.first?.startSec == 13)
    }

    @Test("native render plan preserves exact visual editor style background and language layers")
    func nativeRenderPlanPreservesExactVisualEditorValues() {
        var plan = ShortsClipPlan(
            start: "13:48",
            end: "14:48",
            title: "Target title",
            summary: "Summary",
            hook: "Hook"
        )
        plan.sourceTitle = "Source title"
        plan.sourceCaptionText = "[13:48] source line"
        plan.targetCaptionText = "[13:48] target line"
        plan.subtitleStyle = ShortsSubtitleStyle(
            fontFamily: "Cuprum",
            fontSize: 70,
            bold: true,
            textTransform: .uppercase,
            textColor: "#FAFAFA",
            boxColor: "#123456",
            boxOpacity: 0.66,
            boxWidth: 91,
            boxHeight: 1.55,
            edgeBlur: 7,
            letterSpacing: 0.25,
            lineSpacing: 1.2,
            edgeSoftness: 0.3,
            outline: 2,
            outlineColor: "#010203",
            outlineOpacity: 0.44,
            shadow: 6,
            shadowColor: "#0A0B0C",
            shadowOpacity: 0.55,
            shadowBlur: 4,
            shadowDistance: 8,
            shadowAngle: 135,
            subtitleBottomMargin: 432
        )
        plan.backgroundSettings = ShortsBackgroundSettings(
            effectReferenceHeight: 460,
            solidEnabled: true,
            solidColor: "#000000",
            blurEnabled: true,
            blurStrength: 30,
            blurScale: 1.3,
            gradientEnabled: true,
            gradientType: "radial",
            gradientColorA: "#111111",
            gradientColorB: "#222222",
            gradientAngle: 143,
            gradientOpacity: 0.37,
            featherEnabled: true,
            featherTop: 12,
            featherBottom: 34,
            featherLeft: 5,
            featherRight: 6,
            frameGuideColor: "#FFFFFF",
            frameGuideOpacity: 0.42,
            frameGuideBorderWidth: 2,
            frameGuideBlur: 9,
            frameGuideBorderOpacity: 0.8,
            featherTopHeight: 75,
            featherBottomHeight: 62,
            blurPanX: 11
        )
        plan.sourceFrameKeyframes = [
            FrameKeyframe(id: "source-frame", time: 0, x: 5, y: -2, zoom: 0.84, backgroundColor: "#000000")
        ]
        plan.targetFrameKeyframes = [
            FrameKeyframe(id: "target-frame", time: 0, x: -6, y: 3, zoom: 1.25, backgroundColor: "#111111")
        ]
        plan.sourceTextTracks = [
            TextOverlayTrack(
                id: "source-track",
                name: "Source CTA",
                hidden: true,
                blocks: [TextOverlayBlock(id: "source-block", startSec: 2, endSec: 4, text: "hidden source")]
            )
        ]
        plan.targetTextTracks = [
            TextOverlayTrack(
                id: "target-track",
                name: "Target CTA",
                hidden: false,
                blocks: [TextOverlayBlock(id: "target-block", startSec: 3, endSec: 5, text: "target overlay")]
            )
        ]

        let sourceRender = NativeShortsRenderPlanBuilder.build(
            id: "source-render",
            plan: plan,
            language: .source,
            outputWidth: 1080,
            outputHeight: 1920,
            fps: 24
        )
        let targetRender = NativeShortsRenderPlanBuilder.build(
            id: "target-render",
            plan: plan,
            language: .target,
            outputWidth: 1080,
            outputHeight: 1920,
            fps: 24
        )

        #expect(sourceRender.captionStyle == plan.subtitleStyle)
        #expect(sourceRender.subtitleBottomMargin == 432)
        #expect(sourceRender.backgroundSettings == plan.backgroundSettings)
        #expect(NativeShortsRenderPlanBuilder.interpolateFrameState(sourceRender.frameKeyframes, timeSec: 0).x == 5)
        #expect(NativeShortsRenderPlanBuilder.interpolateFrameState(sourceRender.frameKeyframes, timeSec: 0).y == -2)
        #expect(NativeShortsRenderPlanBuilder.interpolateFrameState(sourceRender.frameKeyframes, timeSec: 0).zoom == 0.84)
        #expect(NativeShortsRenderPlanBuilder.interpolateFrameState(sourceRender.frameKeyframes, timeSec: 0).backgroundColor == "#000000")
        #expect(sourceRender.textTracks.first?.id == "source-track")
        #expect(sourceRender.textTracks.first?.hidden == true)

        #expect(targetRender.captionStyle == plan.subtitleStyle)
        #expect(targetRender.subtitleBottomMargin == 432)
        #expect(targetRender.backgroundSettings == plan.backgroundSettings)
        #expect(NativeShortsRenderPlanBuilder.interpolateFrameState(targetRender.frameKeyframes, timeSec: 0).x == -6)
        #expect(NativeShortsRenderPlanBuilder.interpolateFrameState(targetRender.frameKeyframes, timeSec: 0).y == 3)
        #expect(NativeShortsRenderPlanBuilder.interpolateFrameState(targetRender.frameKeyframes, timeSec: 0).zoom == 1.25)
        #expect(NativeShortsRenderPlanBuilder.interpolateFrameState(targetRender.frameKeyframes, timeSec: 0).backgroundColor == "#111111")
        #expect(targetRender.textTracks.first?.id == "target-track")
        #expect(targetRender.textTracks.first?.hidden == false)
        #expect(targetRender.textTracks.first?.blocks.first?.text == "target overlay")
    }

    @Test("cut time mapper keeps second cut near beginning after an existing beginning cut")
    func cutTimeMapperKeepsSecondCutNearBeginningAfterExistingBeginningCut() {
        let trim = TimelineTrim.zero
        let cuts = [TimelineCut(startSec: 0, endSec: 2)]

        expectApprox(TimelineCutTimeMapper.activeOutputDuration(clipDuration: 20, trim: trim, cuts: cuts), 18)
        expectApprox(TimelineCutTimeMapper.mapVirtualToPhysical(
            virtualSec: 0.0,
            clipDuration: 20,
            trim: trim,
            cuts: cuts,
            introDuration: 0,
            outroDuration: 0
        ), 2.0)
        expectApprox(TimelineCutTimeMapper.mapVirtualToPhysical(
            virtualSec: 0.4,
            clipDuration: 20,
            trim: trim,
            cuts: cuts,
            introDuration: 0,
            outroDuration: 0
        ), 2.4)
        expectApprox(TimelineCutTimeMapper.mapPhysicalToVirtual(
            physicalSec: 2.4,
            clipDuration: 20,
            trim: trim,
            cuts: cuts,
            introDuration: 0,
            outroDuration: 0
        ), 0.4)
    }

    @Test("cut time mapper skips middle cuts without moving clicks to unrelated timeline locations")
    func cutTimeMapperSkipsMiddleCutsWithoutMovingClicksToUnrelatedLocations() {
        let trim = TimelineTrim(trimStartSec: 1, trimEndSec: 2)
        let cuts = [
            TimelineCut(startSec: 3, endSec: 5),
            TimelineCut(startSec: 8, endSec: 9)
        ]

        expectApprox(TimelineCutTimeMapper.activeOutputDuration(clipDuration: 12, trim: trim, cuts: cuts), 6)
        expectApprox(TimelineCutTimeMapper.mapVirtualToPhysical(
            virtualSec: 2.5,
            clipDuration: 12,
            trim: trim,
            cuts: cuts,
            introDuration: 1,
            outroDuration: 0
        ), 1.5)
        expectApprox(TimelineCutTimeMapper.mapVirtualToPhysical(
            virtualSec: 4.5,
            clipDuration: 12,
            trim: trim,
            cuts: cuts,
            introDuration: 1,
            outroDuration: 0
        ), 5.5)
        expectApprox(TimelineCutTimeMapper.mapPhysicalToVirtual(
            physicalSec: 5.5,
            clipDuration: 12,
            trim: trim,
            cuts: cuts,
            introDuration: 1,
            outroDuration: 0
        ), 4.5)
    }

    @Test("cut range only reports newly removed cut fragments")
    func cutRangeOnlyReportsNewlyRemovedCutFragments() {
        let existing = [
            TimelineCut(startSec: 10, endSec: 20),
            TimelineCut(startSec: 30, endSec: 35)
        ]

        let insideExisting = TimelineCutTimeMapper.incrementalCutFragments(
            existingCuts: existing,
            newCut: TimelineCut(startSec: 12, endSec: 18),
            clipDuration: 60
        )
        #expect(insideExisting.isEmpty)

        let overlappingExisting = TimelineCutTimeMapper.incrementalCutFragments(
            existingCuts: existing,
            newCut: TimelineCut(startSec: 15, endSec: 25),
            clipDuration: 60
        )
        #expect(overlappingExisting == [TimelineCut(startSec: 20, endSec: 25)])

        let spanningMultipleCuts = TimelineCutTimeMapper.incrementalCutFragments(
            existingCuts: existing,
            newCut: TimelineCut(startSec: 5, endSec: 40),
            clipDuration: 60
        )
        #expect(spanningMultipleCuts == [
            TimelineCut(startSec: 5, endSec: 10),
            TimelineCut(startSec: 20, endSec: 30),
            TimelineCut(startSec: 35, endSec: 40)
        ])
    }
}
