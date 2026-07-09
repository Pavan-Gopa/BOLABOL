import AVKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VaniScriptCore

struct ClipVisualEditorWorkspace: View {
    @EnvironmentObject private var store: WorkflowStore
    let draft: VisualClipEditorDraft
    let onCancel: () -> Void
    let onSave: (EditClipValues) -> Void

    @AppStorage("shortsExportResolution") private var exportResolution = "Source-based"
    @AppStorage("shortsExportFrameRate") private var exportFrameRate = "Source-based"

    @State private var player: AVPlayer?
    @State private var language: ShortsIdeaDisplayLanguage
    @State private var sourceSegments: [AlignedSubtitleSegment]
    @State private var targetSegments: [AlignedSubtitleSegment]
    @State private var sourceFrameKeyframes: [FrameKeyframe]
    @State private var targetFrameKeyframes: [FrameKeyframe]
    @State private var selectedSegmentID: String
    @State private var currentSec: Double = 0
    @State private var playing = false
    @State private var looping = false
    @State private var cutRangeActive = false
    @State private var cutRangeStartSec: Double? = nil
    @State private var cutRangePreviewEndSec: Double? = nil
    @State private var timelineZoom: Double = 1.0
    @State private var inspectorOpen = true
    @State private var inspectorTab: EditorInspectorTab = .style
    @State private var sourceMode = true
    @State private var syncEnabled: Bool
    @State private var startSec: Double
    @State private var endSec: Double
    @State private var title: String
    @State private var category: String
    @State private var summary: String
    @State private var hook: String
    @State private var captionText: String
    @State private var style: ShortsSubtitleStyle
    @State private var selectedStyleTab: Int = 0
    @State private var backgroundSettings: ShortsBackgroundSettings
    @State private var timelineCuts: [TimelineCut]
    @State private var timelineTrim: TimelineTrim
    @State private var sourceLogo: LogoOverlaySettings?
    @State private var targetLogo: LogoOverlaySettings?
    @State private var sourceTextTracks: [TextOverlayTrack]
    @State private var targetTextTracks: [TextOverlayTrack]
    @State private var sourceAudioTracks: [ExtraAudioTrack]
    @State private var targetAudioTracks: [ExtraAudioTrack]
    @State private var extraAudioPlayers: [String: AVPlayer] = [:]
    @State private var sourceIntro: IntroOutroOverlaySettings?
    @State private var targetIntro: IntroOutroOverlaySettings?
    @State private var sourceOutro: IntroOutroOverlaySettings?
    @State private var targetOutro: IntroOutroOverlaySettings?
    @State private var selectedTextBlock: (trackID: String, blockID: String)?
    @State private var frameZoom: Double
    @State private var framePanX: Double
    @State private var framePanY: Double
    @State private var savedFlash = false
    @State private var keyMonitor: Any?
    @State private var undoStack: [EditorSnapshot] = []
    @State private var redoStack: [EditorSnapshot] = []
    @State private var restoringSnapshot = false
    @State private var waveformPeaks: [Double] = []
    @State private var isDraggingTrim = false
    @State private var dragStartTrimStartSec: Double = 0
    @State private var dragStartTrimEndSec: Double = 0
    @State private var showResetDialog = false
    @State private var lastSeekTargetSec: Double? = nil
    @State private var onboardingFrames: [String: CGRect] = [:]

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let timelineMergeGapToleranceSec: Double = 0.25

    private enum TimelineSelection: Equatable {
        case subtitle(String)
        case text(trackID: String, blockID: String)
    }

    init(draft: VisualClipEditorDraft, onCancel: @escaping () -> Void, onSave: @escaping (EditClipValues) -> Void) {
        self.draft = draft
        self.onCancel = onCancel
        self.onSave = onSave
        _language = State(initialValue: draft.language)
        _sourceSegments = State(initialValue: draft.sourceAlignment)
        _targetSegments = State(initialValue: draft.targetAlignment)
        _sourceFrameKeyframes = State(initialValue: draft.sourceFrameKeyframes)
        _targetFrameKeyframes = State(initialValue: draft.targetFrameKeyframes)
        _selectedSegmentID = State(initialValue: (draft.language == .source ? draft.sourceAlignment : draft.targetAlignment).first?.id ?? "")
        _syncEnabled = State(initialValue: draft.syncEnabled)
        _startSec = State(initialValue: ShortsPlanner.parseTimestampToSeconds(draft.start))
        _endSec = State(initialValue: ShortsPlanner.parseTimestampToSeconds(draft.end))
        _title = State(initialValue: draft.title)
        _category = State(initialValue: draft.category)
        _summary = State(initialValue: draft.summary)
        _hook = State(initialValue: draft.hook)
        _captionText = State(initialValue: draft.captionText)
        _style = State(initialValue: draft.subtitleStyle)
        _selectedStyleTab = State(initialValue: 0)
        _backgroundSettings = State(initialValue: draft.backgroundSettings)
        _timelineCuts = State(initialValue: draft.timelineCuts)
        _timelineTrim = State(initialValue: draft.timelineTrim)
        _sourceLogo = State(initialValue: draft.sourceLogo)
        _targetLogo = State(initialValue: draft.targetLogo)
        _sourceTextTracks = State(initialValue: draft.sourceTextTracks)
        _targetTextTracks = State(initialValue: draft.targetTextTracks)
        _sourceAudioTracks = State(initialValue: draft.sourceAudioTracks)
        _targetAudioTracks = State(initialValue: draft.targetAudioTracks)
        _sourceIntro = State(initialValue: draft.sourceIntro)
        _targetIntro = State(initialValue: draft.targetIntro)
        _sourceOutro = State(initialValue: draft.sourceOutro)
        _targetOutro = State(initialValue: draft.targetOutro)
        let keyframe = (draft.language == .source ? draft.sourceFrameKeyframes : draft.targetFrameKeyframes).first
        _frameZoom = State(initialValue: keyframe?.zoom ?? 1)
        _framePanX = State(initialValue: keyframe?.x ?? 0)
        _framePanY = State(initialValue: keyframe?.y ?? 0)
        if let sourceURL = draft.sourceURL {
            _player = State(initialValue: AVPlayer(url: sourceURL))
        } else {
            _player = State(initialValue: nil)
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                editorHeader
                Divider().overlay(VaniScriptTheme.accent.opacity(0.55))
                HStack(spacing: 0) {
                    editorMain
                    if inspectorOpen {
                        inspector
                            .onboardingTarget("alignment-right")
                            .frame(width: 300)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VaniScriptTheme.background)
            .onReceive(timer) { _ in tickPlayback() }
            .onAppear {
                installKeyboardMonitor()
            }
            .task {
                seek(to: currentSec, autoplay: false)
                if let sourceURL = draft.sourceURL {
                    let peaks = await AudioWaveformExtractor.extractPeaks(from: sourceURL, count: 3000, startSec: startSec, durationSec: clipDuration)
                    await MainActor.run {
                        self.waveformPeaks = peaks
                    }
                }
            }
            .onDisappear {
                player?.pause()
                removeKeyboardMonitor()
                stopAllExtraAudio()
            }

            if showResetDialog {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showResetDialog = false
                    }
                    .transition(.opacity)

                VStack(spacing: 20) {
                    Text("Reset all edits? This will discard all changes and restore the clip to its initial state.")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.text0)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.top, 6)

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            showResetDialog = false
                        }
                        .buttonStyle(ModalCancelButtonStyle())

                        Button("OK") {
                            resetEditor()
                            showResetDialog = false
                        }
                        .buttonStyle(ModalOKButtonStyle())
                    }
                }
                .padding(22)
                .frame(width: 320)
                .background(VaniScriptTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(VaniScriptTheme.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            if store.isTourActive {
                OnboardingTourView(
                    screen: "visualEditor",
                    store: store,
                    frames: onboardingFrames
                )
            }
        }
        .coordinateSpace(name: "OnboardingSpace")
        .onPreferenceChange(OnboardingFramesPreferenceKey.self) { dict in
            onboardingFrames = dict
        }
        .focusable()
        .onKeyPress(.space) {
            return handleSpacebarKeyPress() ? .handled : .ignored
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "Clip editor" : title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(VaniScriptTheme.text0)
                    .lineLimit(1)
                Text("\(language == .source ? "Source captions" : "Target captions") · \(clock(startSec)) -> \(clock(endSec))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VaniScriptTheme.text2)
            }
            Spacer()
            sourceTargetToggle
                .onboardingTarget("alignment-lang-toggle")
            Button {
                syncEnabled.toggle()
                if syncEnabled {
                    mirrorCurrentVisualStateToOtherLanguage()
                }
            } label: {
                Label("Sync", systemImage: syncEnabled ? "link" : "link.badge.plus")
            }
            .buttonStyle(EditorToolbarButtonStyle(active: syncEnabled))
            .onboardingTarget("btn-dl-sync")
            Button(action: undoEdit, label: { Image(systemName: "arrow.uturn.backward") })
                .buttonStyle(EditorIconButtonStyle(disabled: undoStack.isEmpty))
                .disabled(undoStack.isEmpty)
                .help("Undo")
            Button(action: redoEdit, label: { Image(systemName: "arrow.uturn.forward") })
                .buttonStyle(EditorIconButtonStyle(disabled: redoStack.isEmpty))
                .disabled(redoStack.isEmpty)
                .help("Redo")
            Button {
                store.showChatSidebar.toggle()
            } label: {
                Image(systemName: "sparkles")
                    .foregroundStyle(store.showChatSidebar ? VaniScriptTheme.accent : VaniScriptTheme.text2)
            }
            .buttonStyle(EditorIconButtonStyle())
            .help("AI Assistant")

            Button(action: { store.startTour(for: "visualEditor") }, label: { Image(systemName: "questionmark.circle") })
                .buttonStyle(EditorIconButtonStyle())
                .help("Help Tour")
            Button(inspectorOpen ? "Hide inspector" : "Show inspector") {
                withAnimation(.easeInOut(duration: 0.18)) { inspectorOpen.toggle() }
            }
            .buttonStyle(EditorToolbarButtonStyle())
            Button {
                showResetDialog = true
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(EditorDangerButtonStyle())
            Button {
                save(stayOpen: true)
            } label: {
                Label("Save edits", systemImage: savedFlash ? "checkmark.seal" : "externaldrive")
            }
            .buttonStyle(EditorPrimaryButtonStyle(isSaved: savedFlash))
            .onboardingTarget("alignment-save-btn")
            Button(action: onCancel, label: { Image(systemName: "xmark") })
                .buttonStyle(EditorIconButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.dynamic(light: Color.white, dark: Color(red: 9 / 255, green: 12 / 255, blue: 26 / 255)))
    }

    private var sourceTargetToggle: some View {
        HStack(spacing: 0) {
            Button("SOURCE") { switchLanguage(.source) }
                .buttonStyle(EditorSegmentButtonStyle(active: language == .source))
            Button("TARGET") { switchLanguage(.target) }
                .buttonStyle(EditorSegmentButtonStyle(active: language == .target))
        }
        .padding(3)
        .background(Color.dynamic(light: Color.black.opacity(0.055), dark: Color.white.opacity(0.055)))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var editorMain: some View {
        VStack(spacing: 10) {
            preview
                .onboardingTarget("alignment-preview")
                .frame(maxWidth: .infinity)
                .frame(minHeight: 400, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.top, 4)

            playbackRow
                .padding(.horizontal, 12)

            multitrackTimeline
                .onboardingTarget("alignment-multitrack")
                .frame(height: timelineHeight)
                .padding(.horizontal, 12)

            editPanel
                .frame(height: 190)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var preview: some View {
        GeometryReader { geometry in
            let maxPreviewWidth = max(1, geometry.size.width)
            let maxPreviewHeight = max(1, geometry.size.height - 8)
            let previewAspect = editorPreviewAspectRatio
            let frameWidth = min(maxPreviewWidth, maxPreviewHeight * previewAspect)
            let frameHeight = frameWidth / previewAspect
            let previewRenderSize = visualEditorRenderSize(for: nativePreviewSourceSize)
            let renderPlan = liveNativeRenderPlan(
                outputWidth: previewRenderSize.width,
                outputHeight: previewRenderSize.height,
                fps: visualEditorFrameRate(for: nativePreviewSourceFPS)
            )
            ZStack {
                Color.black
                NativeMetalClipPreviewView(
                    player: player,
                    renderPlan: renderPlan,
                    timeSec: min(nativePreviewTimeSec, renderPlan.durationSec),
                    sourceSize: nativePreviewSourceSize
                )
                .frame(width: frameWidth, height: frameHeight)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.dynamic(light: Color.black.opacity(0.18), dark: Color.white.opacity(0.38)), lineWidth: 1))
        }
    }

    private var editorPreviewAspectRatio: CGFloat {
        let aspect = nativePreviewSourceSize.width / max(1, nativePreviewSourceSize.height)
        guard aspect.isFinite, aspect > 0 else { return 16.0 / 9.0 }
        return max(0.2, min(5.0, aspect))
    }

    private var nativePreviewTimeSec: Double {
        let introDur = introDuration
        let currentTrim = timelineTrim
        let activeVideoStartVirtual = currentTrim.trimStartSec + introDur
        let activeVideoEndVirtual = activeVideoStartVirtual + (clipDuration - currentTrim.trimStartSec - currentTrim.trimEndSec)

        if currentSec < activeVideoStartVirtual {
            return max(0, currentSec - currentTrim.trimStartSec)
        } else if currentSec >= activeVideoEndVirtual {
            let activeDur = TimelineCutTimeMapper.activeOutputDuration(
                clipDuration: clipDuration,
                trim: currentTrim,
                cuts: timelineCuts
            )
            return max(0, introDur + activeDur + (currentSec - activeVideoEndVirtual))
        } else {
            let physicalSec = mapVirtualToPhysical(virtualSec: currentSec, currentTrim: currentTrim)
            let collapsedV = TimelineCutTimeMapper.mapPhysicalToVirtual(
                physicalSec: physicalSec,
                clipDuration: clipDuration,
                trim: currentTrim,
                cuts: timelineCuts,
                introDuration: introDur,
                outroDuration: outroDuration
            )
            return max(0, collapsedV - currentTrim.trimStartSec)
        }
    }

    private var nativePreviewSourceSize: CGSize {
        if let item = player?.currentItem {
            if item.presentationSize.width > 0, item.presentationSize.height > 0 {
                return item.presentationSize
            }
            if let track = item.asset.tracks(withMediaType: .video).first {
                let size = track.naturalSize.applying(track.preferredTransform)
                let width = abs(size.width)
                let height = abs(size.height)
                if width > 0, height > 0 {
                    return CGSize(width: width, height: height)
                }
            }
        }
        return CGSize(width: max(1, videoAspectRatio * 1000), height: 1000)
    }

    private var nativePreviewSourceFPS: Double {
        if let track = player?.currentItem?.asset.tracks(withMediaType: .video).first {
            let fps = Double(track.nominalFrameRate)
            if fps.isFinite, fps > 0 { return fps }
        }
        return 30
    }

    private func visualEditorRenderSize(for sourceSize: CGSize) -> (width: Int, height: Int) {
        VisualEditorPreviewCanvas.size(for: sourceSize, exportResolution: exportResolution)
    }

    private func visualEditorFrameRate(for sourceFPS: Double) -> Int {
        if exportFrameRate.contains("24") { return 24 }
        if exportFrameRate.contains("25") { return 25 }
        if exportFrameRate.contains("50") { return 50 }
        if exportFrameRate.contains("60") { return 60 }
        if exportFrameRate.contains("30") { return 30 }
        if exportFrameRate.contains("Source-based") { return max(1, Int(sourceFPS.rounded())) }
        return min(60, max(1, Int(sourceFPS.rounded())))
    }

    private func liveNativeRenderPlan(outputWidth: Int, outputHeight: Int, fps: Int) -> NativeShortsRenderPlan {
        let plan = ShortsClipPlan(
            start: ShortsPlanner.secondsToShortsTimestamp(startSec),
            end: ShortsPlanner.secondsToShortsTimestamp(endSec),
            title: title,
            summary: summary,
            hook: hook,
            category: category,
            sourceTitle: title,
            sourceSummary: summary,
            sourceHook: hook,
            sourceCategory: category,
            targetTitle: title,
            targetSummary: summary,
            targetHook: hook,
            targetCategory: category,
            captionText: captionText,
            sourceCaptionText: captionText(from: sourceSegments),
            targetCaptionText: captionText(from: targetSegments),
            languageMode: syncEnabled ? .bilingual : languageModeForPreview,
            sourceAlignment: sourceSegments,
            targetAlignment: targetSegments,
            sourceFrameKeyframes: liveFrameKeyframes(for: .source),
            targetFrameKeyframes: liveFrameKeyframes(for: .target),
            syncEnabled: syncEnabled,
            timelineCuts: timelineCuts,
            timelineTrim: timelineTrim,
            backgroundSettings: backgroundSettings,
            subtitleStyle: style,
            sourceLogo: sourceLogo,
            targetLogo: targetLogo,
            sourceTextTracks: sourceTextTracks,
            targetTextTracks: targetTextTracks,
            sourceAudioTracks: sourceAudioTracks,
            targetAudioTracks: targetAudioTracks,
            sourceIntro: sourceIntro,
            targetIntro: targetIntro,
            sourceOutro: sourceOutro,
            targetOutro: targetOutro
        )
        return NativeShortsRenderPlanBuilder.build(
            id: "visual-editor-preview-\(draft.index)-\(language.rawValue)",
            plan: plan,
            language: language,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            fps: fps,
            subtitleBottomMargin: style.subtitleBottomMargin ?? 450
        )
    }

    private var languageModeForPreview: ShortsPlanLanguageMode {
        language == .source ? .source : .target
    }

    private func liveFrameKeyframes(for side: ShortsIdeaDisplayLanguage) -> [FrameKeyframe] {
        let keyframes = side == .source ? sourceFrameKeyframes : targetFrameKeyframes
        guard side == language else { return keyframes }
        let physicalSec = mapVirtualToPhysical(virtualSec: currentSec, currentTrim: timelineTrim)
        let point = FrameKeyframe(
            id: "frame_live_preview",
            time: physicalSec,
            x: framePanX,
            y: framePanY,
            zoom: frameZoom,
            backgroundColor: backgroundSettings.solidColor
        )
        return replacingKeyframe(point, in: keyframes)
    }

    private func captionText(from segments: [AlignedSubtitleSegment]) -> String {
        segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "[\(ShortsPlanner.secondsToShortsTimestamp(startSec + $0.start))] \($0.text)" }
            .joined(separator: "\n")
    }

    @ViewBuilder
    private func featherMask(
        featherTop: Double,
        featherTopHeight: Double, // This is Top Strength (0...100%)
        featherBottom: Double,
        featherBottomHeight: Double, // This is Bottom Strength (0...100%)
        containerHeight: CGFloat
    ) -> some View {
        let height = max(1.0, containerHeight)

        let S_top = min(1.0, max(0.0, featherTopHeight / 100.0))
        let topEnd = min(height / 2.0, max(0.0, CGFloat(featherTop)))
        let topStart = topEnd * (1.0 - CGFloat(S_top))

        let S_bottom = min(1.0, max(0.0, featherBottomHeight / 100.0))
        let bottomStart = max(topEnd, height - max(0.0, CGFloat(featherBottom)))
        let bottomEnd = bottomStart + (height - bottomStart) * (1.0 - CGFloat(S_bottom))

        let topStartRatio = topStart / height
        let topEndRatio = topEnd / height
        let bottomStartRatio = bottomStart / height
        let bottomEndRatio = bottomEnd / height

        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: topStartRatio),
                .init(color: .black, location: topEndRatio),
                .init(color: .black, location: bottomStartRatio),
                .init(color: .clear, location: bottomEndRatio),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private func visualLayerOverlays(frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
        let scale = frameHeight / 1920
        let guideSize = shortsGuideSize(frameWidth: frameWidth, frameHeight: frameHeight)
        let introDur = introDuration
        let activeVideoStartVirtual = timelineTrim.trimStartSec + introDur
        let activeVideoEndVirtual = activeVideoStartVirtual + (clipDuration - timelineTrim.trimStartSec - timelineTrim.trimEndSec)

        if let logo = currentLogo, logo.hidden != true,
           currentSec >= activeVideoStartVirtual,
           currentSec <= activeVideoEndVirtual,
           let image = image(from: logo.src) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: max(46 * scale, 120 * scale * logo.size))
                .opacity(logo.opacity)
                .frame(width: guideSize.width, height: guideSize.height, alignment: logoAlignment(logo.position ?? "top-left"))
                .padding(max(16 * scale, 40 * scale))
                .frame(width: frameWidth, height: frameHeight)
        }

        ForEach(activeTextOverlayBlocks()) { block in
            let blockStyle = block.style ?? defaultTextTrackStyle(trackIndex: block.trackIndex)
            let baseMargin = blockStyle.subtitleBottomMargin ?? defaultTextTrackBottomMargin(trackIndex: block.trackIndex)
            let marginRatio = baseMargin / 1920.0
            let calculatedBottomPadding = guideSize.height * CGFloat(marginRatio)
            captionOverlayText(block.text, style: blockStyle, fontFactor: 0.82, viewportWidth: guideSize.width, viewportHeight: guideSize.height)
                .padding(.bottom, calculatedBottomPadding)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }

        if let intro = currentIntro,
           intro.hidden != true,
           currentSec >= timelineTrim.trimStartSec,
           currentSec <= timelineTrim.trimStartSec + intro.duration,
           let image = image(from: intro.src) {
            introOutroImage(image, item: intro, elapsed: currentSec - timelineTrim.trimStartSec, frameWidth: frameWidth, frameHeight: frameHeight)
        }

        if let outro = currentOutro,
           outro.hidden != true,
           currentSec >= activeVideoEndVirtual,
           currentSec <= activeVideoEndVirtual + outro.duration,
           let image = image(from: outro.src) {
            introOutroImage(image, item: outro, elapsed: currentSec - activeVideoEndVirtual, frameWidth: frameWidth, frameHeight: frameHeight)
        }
    }

    private func captionOverlay(_ caption: String, frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
        let guideSize = shortsGuideSize(frameWidth: frameWidth, frameHeight: frameHeight)
        return captionOverlayText(caption, style: style, fontFactor: 1, viewportWidth: guideSize.width, viewportHeight: guideSize.height)
    }

    private func shortsGuideSize(frameWidth: CGFloat, frameHeight: CGFloat) -> CGSize {
        let width = max(1, frameWidth)
        let height = max(1, frameHeight)
        let guideWidth = min(width, height * 9 / 16)
        let guideHeight = min(height, guideWidth * 16 / 9)
        return CGSize(width: guideWidth, height: guideHeight)
    }

    private func resolvedSwiftUIFontName(_ family: String, bold: Bool) -> String {
        NativeFontRegistry.registerVisualEditorFonts()
        return NativeFontRegistry.preferredFontName(for: family, bold: bold)
    }

    private func captionOverlayText(_ caption: String, style: ShortsSubtitleStyle, fontFactor: Double, viewportWidth: CGFloat, viewportHeight: CGFloat) -> AnyView {
        let displayText = transformed(caption, style: style)
        guard !displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AnyView(EmptyView())
        }
        let previewScale = viewportHeight / 1920.0
        let fontSize = CGFloat(style.fontSize * previewScale * fontFactor)
        let fontWeight: Font.Weight = style.bold ? .heavy : .semibold

        let boxWidth = viewportWidth * CGFloat(style.boxWidth / 100.0)
        let outlineWidth = CGFloat(max(0.0, style.outline * previewScale * fontFactor))

        // React dynamic padding formulas:
        let paddingY = CGFloat(max(1.0, Double(fontSize) * 0.12 * style.boxHeight))
        let paddingX = CGFloat(max(1.0, Double(paddingY) * 1.45))
        let approximateBoxHeight = max(fontSize + paddingY * 2, fontSize * 1.25)
        let cornerRadius = smoothCaptionCornerRadius(
            edgeSoftness: style.edgeSoftness,
            boxHeight: approximateBoxHeight,
            scale: previewScale
        )

        // Spacing:
        let lineSpacingPoints = CGFloat((style.lineSpacing - 1.0) * Double(fontSize))

        // Outline & Drop shadow colors and calculations:
        let strokeColor = Color(hex: style.outlineColor ?? "#000000").opacity(style.outlineOpacity ?? 0.58)

        let shadowDist = CGFloat(style.shadowDistance ?? style.shadow) * previewScale * fontFactor
        let shadowAngle = Double(style.shadowAngle ?? 90.0)
        let rad = (shadowAngle * .pi) / 180.0
        let shadowX = shadowDist * CGFloat(cos(rad))
        let shadowY = shadowDist * CGFloat(sin(rad))
        let shadowBlur = CGFloat(style.shadowBlur ?? 3.0) * previewScale * fontFactor
        let shadowColorColor = Color(hex: style.shadowColor ?? "#000000").opacity(style.shadowOpacity ?? 0.72)

        var text: AnyView = AnyView(
            Text(displayText)
                .font(.custom(resolvedSwiftUIFontName(style.fontFamily, bold: style.bold), size: fontSize).weight(fontWeight))
                .foregroundStyle(Color(hex: style.textColor))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .tracking(style.letterSpacing * previewScale * fontFactor)
                .lineSpacing(lineSpacingPoints)
        )

        if outlineWidth > 0 {
            text = AnyView(
                text
                    .shadow(color: strokeColor, radius: 0, x: -outlineWidth, y: 0)
                    .shadow(color: strokeColor, radius: 0, x: outlineWidth, y: 0)
                    .shadow(color: strokeColor, radius: 0, x: 0, y: -outlineWidth)
                    .shadow(color: strokeColor, radius: 0, x: 0, y: outlineWidth)
            )
            text = AnyView(
                text
                    .shadow(color: strokeColor, radius: 0, x: -outlineWidth * 0.707, y: -outlineWidth * 0.707)
                    .shadow(color: strokeColor, radius: 0, x: outlineWidth * 0.707, y: -outlineWidth * 0.707)
                    .shadow(color: strokeColor, radius: 0, x: -outlineWidth * 0.707, y: outlineWidth * 0.707)
                    .shadow(color: strokeColor, radius: 0, x: outlineWidth * 0.707, y: outlineWidth * 0.707)
            )
        }

        let shadowedText = text
            .shadow(color: shadowColorColor, radius: shadowBlur, x: shadowX, y: shadowY)

        return AnyView(
            shadowedText
                .padding(.horizontal, paddingX)
                .padding(.vertical, paddingY)
                .frame(width: boxWidth)
                .background(
                    Group {
                        if style.edgeBlur > 0 {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Color(hex: style.boxColor).opacity(style.boxOpacity))
                                .blur(radius: CGFloat(style.edgeBlur * previewScale * fontFactor))
                        } else {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Color(hex: style.boxColor).opacity(style.boxOpacity))
                        }
                    }
                )
        )
    }

    private func smoothCaptionCornerRadius(edgeSoftness: Double, boxHeight: CGFloat, scale: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, CGFloat(edgeSoftness)))
        _ = scale
        return min(boxHeight / 2, max(0, boxHeight / 2 * clamped))
    }

    private func introOutroImage(_ image: NSImage, item: IntroOutroOverlaySettings, elapsed: Double, frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
        let scale = frameHeight / 1920.0
        let fade = min(0.5, item.duration * 0.15)
        let fadeIn = fade > 0 ? min(1, max(0, elapsed / fade)) : 1
        let fadeOut = fade > 0 ? min(1, max(0, (item.duration - elapsed) / fade)) : 1
        let speed = item.speed ?? 1
        let pulse = item.animation == "pulse" ? 1 + (0.06 * sin(elapsed * speed * 4.18)) : 1
        let bounce = item.animation == "bounce" ? 12 * sin(elapsed * speed * 5.24) : 0
        return Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: max(70 * scale, 300 * scale * item.scale))
            .scaleEffect(pulse)
            .opacity(min(fadeIn, fadeOut))
            .position(x: frameWidth * CGFloat(item.x / 100), y: frameHeight * CGFloat(item.y / 100) + CGFloat(bounce) * scale)
    }

    private var playbackRow: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(EditorRoundPlayButtonStyle())

            Text("\(clock(currentSec)) / \(clock(virtualDuration))")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(VaniScriptTheme.text1)
                .frame(width: 108, alignment: .leading)

            Button {
                if cutRangeActive {
                    cutRangeActive = false
                    cutRangeStartSec = nil
                    cutRangePreviewEndSec = nil
                } else {
                    cutRangeStartSec = nil
                    cutRangePreviewEndSec = nil
                    cutRangeActive = true
                }
                AppLogger.shared.info("VisualEditor CutRange toggled active=\(cutRangeActive)")
            } label: {
                Label(cutRangeActive ? "Cancel Cut" : "Cut Range", systemImage: "rectangle.badge.minus")
            }
            .buttonStyle(EditorToolbarButtonStyle(active: cutRangeActive))

            if !timelineCuts.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(timelineCuts.enumerated()), id: \.offset) { index, cut in
                        CutRangeBadge(
                            title: "Cut \(index + 1)",
                            detail: "\(clock(cut.startSec))-\(clock(cut.endSec))",
                            onDelete: { deleteCut(at: index) }
                        )
                    }
                }
            }

            Button {
                looping.toggle()
            } label: {
                Label(looping ? "Loop ON" : "Loop", systemImage: "repeat")
            }
            .buttonStyle(EditorToolbarButtonStyle(active: looping))

            Text("In: \(clock(timelineTrim.trimStartSec)) - Out: \(clock(max(0, clipDuration - timelineTrim.trimEndSec)))")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(VaniScriptTheme.text2)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass.zoomout")
                    .font(.system(size: 10))
                    .foregroundStyle(VaniScriptTheme.text2)
                Slider(value: $timelineZoom, in: 1...12, step: 0.1)
                    .frame(width: 90)
                    .controlSize(.mini)
                Image(systemName: "magnifyingglass.zoomin")
                    .font(.system(size: 10))
                    .foregroundStyle(VaniScriptTheme.text2)
            }
            .padding(.trailing, 4)
        }
    }

    private var multitrackTimeline: some View {
        GeometryReader { outerGeo in
            let baseWidth = max(50.0, outerGeo.size.width - 12)
            let timelineDuration = virtualDuration
            let timelineCurrentSec = currentSec
            let timelineActiveVideoDuration = activeVideoOutputDuration
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .leading) {
                    VStack(spacing: 3) {
                        EditorTrackRow(label: "Video", currentSec: timelineCurrentSec, duration: timelineDuration, onSeek: handleTrackClickOrScrub, onCutRangeBegin: beginCutRangeDrag, onCutRangeUpdate: updateCutRangeDrag, onCutRangeFinish: finishCutRangeDrag, onCutRangeCancel: cancelCutRangeDrag, height: 14, bgFill: Color.dynamic(light: Color(red: 225 / 255, green: 232 / 255, blue: 245 / 255), dark: Color(red: 21 / 255, green: 38 / 255, blue: 68 / 255)), cutRangeActive: cutRangeActive) {
                            GeometryReader { trackGeo in
                                let width = trackGeo.size.width
                                let trimStartVirtual = timelineTrim.trimStartSec + introDuration
                                let activeVideoDuration = timelineActiveVideoDuration
                                let trimEndVirtual = trimStartVirtual + activeVideoDuration

                                let startX = width * CGFloat(trimStartVirtual / timelineDuration)
                                let endX = width * CGFloat(trimEndVirtual / timelineDuration)

                                ZStack(alignment: .leading) {
                                    // Shaded trim start
                                    if trimStartVirtual > 0 {
                                        TimelineTrimRegion(width: startX)
                                            .frame(width: startX)
                                    }

                                    // Intro block background overlay
                                    if introDuration > 0 && timelineTrim.trimStartSec < timelineTrim.trimStartSec + introDuration {
                                        let introStartX = width * CGFloat(timelineTrim.trimStartSec / timelineDuration)
                                        let introWidth = width * CGFloat(introDuration / timelineDuration)
                                        Rectangle()
                                            .fill(LinearGradient(colors: [Color(hex: "#9333ea").opacity(0.15), Color(hex: "#9333ea").opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                                            .overlay(
                                                Rectangle().stroke(Color(hex: "#9333ea").opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                            )
                                            .frame(width: introWidth)
                                            .offset(x: introStartX)
                                    }

                                    // Active Video content region
                                    Color.white.opacity(0.08)
                                        .frame(width: width * CGFloat(activeVideoDuration / timelineDuration))
                                        .offset(x: startX)

                                    // Outro block background overlay
                                    if outroDuration > 0 {
                                        let outroStartX = width * CGFloat(trimEndVirtual / timelineDuration)
                                        let outroWidth = width * CGFloat(outroDuration / timelineDuration)
                                        Rectangle()
                                            .fill(LinearGradient(colors: [Color(hex: "#9333ea").opacity(0.3), Color(hex: "#9333ea").opacity(0.15)], startPoint: .leading, endPoint: .trailing))
                                            .overlay(
                                                Rectangle().stroke(Color(hex: "#9333ea").opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                            )
                                            .frame(width: outroWidth)
                                            .offset(x: outroStartX)
                                    }

                                    // Shaded trim end
                                    if timelineDuration - trimEndVirtual > 0 {
                                        TimelineTrimRegion(width: width - endX)
                                            .frame(width: width - endX)
                                            .offset(x: endX)
                                    }

                                    // Cut regions overlay
                                    TimelineCutRegionOverlay(cuts: timelineCuts, trim: timelineTrim, clipDuration: clipDuration, introDuration: introDuration, virtualDuration: timelineDuration, recordUndo: recordUndo, onUpdateCut: updateCut) { idx in
                                        deleteCut(at: idx)
                                    }

                                    // Trim handles (Start)
                                    TimelineTrimHandle(isStart: true, position: startX, height: 14) { value in
                                        if !isDraggingTrim {
                                            isDraggingTrim = true
                                            dragStartTrimStartSec = timelineTrim.trimStartSec
                                            recordUndo()
                                        }
                                        let deltaSec = (value.translation.width / width) * timelineDuration
                                        let maxStart = clipDuration * 0.45
                                        timelineTrim.trimStartSec = max(0, min(maxStart, dragStartTrimStartSec + deltaSec))
                                    } onDragEnd: {
                                        isDraggingTrim = false
                                    }

                                    // Trim handles (End)
                                    TimelineTrimHandle(isStart: false, position: endX, height: 14) { value in
                                        if !isDraggingTrim {
                                            isDraggingTrim = true
                                            dragStartTrimEndSec = timelineTrim.trimEndSec
                                            recordUndo()
                                        }
                                        let deltaSec = (value.translation.width / width) * timelineDuration
                                        let maxEnd = clipDuration * 0.45
                                        timelineTrim.trimEndSec = max(0, min(maxEnd, dragStartTrimEndSec - deltaSec))
                                    } onDragEnd: {
                                        isDraggingTrim = false
                                    }
                                }
                            }
                        }
                        EditorTrackRow(label: "Audio", currentSec: timelineCurrentSec, duration: timelineDuration, onSeek: handleTrackClickOrScrub, onCutRangeBegin: beginCutRangeDrag, onCutRangeUpdate: updateCutRangeDrag, onCutRangeFinish: finishCutRangeDrag, onCutRangeCancel: cancelCutRangeDrag, height: 52, bgFill: Color.dynamic(light: Color(red: 235 / 255, green: 235 / 255, blue: 235 / 255), dark: Color.black), cutRangeActive: cutRangeActive) {
                            GeometryReader { trackGeo in
                                let width = trackGeo.size.width

                                ZStack(alignment: .leading) {
                                    waveformBars(width: width, timelineDuration: timelineDuration, timelineCurrentSec: timelineCurrentSec, activeVideoDuration: timelineActiveVideoDuration)

                                    // Intro block background overlay
                                    if introDuration > 0 && timelineTrim.trimStartSec < timelineTrim.trimStartSec + introDuration {
                                        let introStartX = width * CGFloat(timelineTrim.trimStartSec / timelineDuration)
                                        let introWidth = width * CGFloat(introDuration / timelineDuration)
                                        Rectangle()
                                            .fill(Color(hex: "#9333ea").opacity(0.12))
                                            .overlay(
                                                Rectangle().stroke(Color(hex: "#9333ea").opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                            )
                                            .frame(width: introWidth)
                                            .offset(x: introStartX)
                                    }

                                    // Outro block background overlay
                                    if outroDuration > 0 {
                                        let activeVideoStartVirtual = timelineTrim.trimStartSec + introDuration
                                        let outroStartVirtual = activeVideoStartVirtual + timelineActiveVideoDuration
                                        let outroStartX = width * CGFloat(outroStartVirtual / timelineDuration)
                                        let outroWidth = width * CGFloat(outroDuration / timelineDuration)
                                        Rectangle()
                                            .fill(Color(hex: "#9333ea").opacity(0.12))
                                            .overlay(
                                                Rectangle().stroke(Color(hex: "#9333ea").opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                            )
                                            .frame(width: outroWidth)
                                            .offset(x: outroStartX)
                                    }

                                    // Cut regions overlay
                                    TimelineCutRegionOverlay(cuts: timelineCuts, trim: timelineTrim, clipDuration: clipDuration, introDuration: introDuration, virtualDuration: timelineDuration, recordUndo: recordUndo, onUpdateCut: updateCut) { idx in
                                        deleteCut(at: idx)
                                    }
                                }
                            }
                        }
                        ForEach(Array(currentAudioTracks.enumerated()), id: \.element.id) { index, track in
                            let player = extraAudioPlayers[track.id]
                            let rawAssetDuration = player?.currentItem?.asset.duration.seconds ?? 0.0
                            let assetDuration = (rawAssetDuration.isNaN || rawAssetDuration <= 0) ? clipDuration : rawAssetDuration

                            EditorTrackRow(label: "Audio \(index + 1)", currentSec: timelineCurrentSec, duration: timelineDuration, onSeek: handleTrackClickOrScrub, height: 26, bgFill: Color.dynamic(light: Color(red: 235 / 255, green: 235 / 255, blue: 235 / 255), dark: Color.black), muted: track.muted == true, cutRangeActive: false) {
                                TimelineAudioBlock(
                                    track: track,
                                    duration: timelineDuration,
                                    assetDuration: assetDuration,
                                    selected: false,
                                    onSelect: {},
                                    onUpdateTimes: { startSec, trimStartSec, trimEndSec in
                                        updateAudioTrack(id: track.id, syncPlayback: false) { t in
                                            t.startSec = startSec
                                            t.trimStartSec = trimStartSec
                                            t.trimEndSec = trimEndSec
                                        }
                                    },
                                    onCommitUpdate: {
                                        updateExtraAudioPlayback()
                                    },
                                    onDelete: {
                                        removeAudioTrack(id: track.id)
                                    },
                                    recordUndo: {
                                        recordUndo()
                                    }
                                )
                            }
                        }
                        EditorTrackRow(label: "Subs", currentSec: timelineCurrentSec, duration: timelineDuration, onSeek: handleTrackClickOrScrub, onCutRangeBegin: beginCutRangeDrag, onCutRangeUpdate: updateCutRangeDrag, onCutRangeFinish: finishCutRangeDrag, onCutRangeCancel: cancelCutRangeDrag, height: 36, cutRangeActive: cutRangeActive) {
                            GeometryReader { trackGeo in
                                ZStack(alignment: .leading) {
                                    ForEach(currentSegments) { segment in
                                        let active = segment.id == activeSegment?.id
                                        let selected = segment.id == selectedSegmentID && selectedTextBlock == nil
                                        TimelineBlock(
                                            segment: segment,
                                            duration: timelineDuration,
                                            introDuration: introDuration,
                                            clipDuration: clipDuration,
                                            active: active,
                                            selected: selected,
                                            onSelect: {
                                                selectSubtitleTimelineBlock(segment.id)
                                                seek(to: segment.start + introDuration, autoplay: playing)
                                            },
                                            onUpdateTimes: { id, start, end in
                                                updateSegmentTimes(id: id, start: start, end: end)
                                            },
                                            recordUndo: {
                                                recordUndo()
                                            }
                                        )
                                    }

                                    // Cut regions overlay
                                    TimelineCutRegionOverlay(cuts: timelineCuts, trim: timelineTrim, clipDuration: clipDuration, introDuration: introDuration, virtualDuration: timelineDuration, recordUndo: recordUndo, onUpdateCut: updateCut) { idx in
                                        deleteCut(at: idx)
                                    }
                                }
                            }
                        }
                        ForEach(Array(currentTextTracks.enumerated()), id: \.element.id) { index, track in
                            EditorTrackRow(label: "Text \(index + 1)", currentSec: timelineCurrentSec, duration: timelineDuration, onSeek: handleTrackClickOrScrub, onCutRangeBegin: beginCutRangeDrag, onCutRangeUpdate: updateCutRangeDrag, onCutRangeFinish: finishCutRangeDrag, onCutRangeCancel: cancelCutRangeDrag, height: 36, muted: track.hidden == true, cutRangeActive: cutRangeActive) {
                                ForEach(track.blocks) { block in
                                    let active = currentSec >= block.startSec + introDuration && currentSec < block.endSec + introDuration
                                    TimelineTextBlock(
                                        block: block,
                                        duration: timelineDuration,
                                        introDuration: introDuration,
                                        clipDuration: clipDuration,
                                        active: active,
                                        selected: selectedTextBlock?.trackID == track.id && selectedTextBlock?.blockID == block.id,
                                        muted: track.hidden == true,
                                        onSelect: {
                                            selectTextTimelineBlock(trackID: track.id, blockID: block.id)
                                            seek(to: block.startSec + introDuration, autoplay: playing)
                                        },
                                        onUpdateTimes: { start, end in
                                            updateTextBlockTimes(trackID: track.id, blockID: block.id, start: start, end: end)
                                        },
                                        recordUndo: {
                                            recordUndo()
                                        }
                                    )
                                }
                            }
                        }
                    }

                    // Cut range start overlay
                    if cutRangeActive, let startSec = cutRangeStartSec {
                        let totalWidth = max(baseWidth, baseWidth * CGFloat(timelineZoom))
                        let contentWidth = totalWidth - 49.0
                        let endSec = cutRangePreviewEndSec ?? startSec
                        let startVirtual = mapPhysicalToVirtual(physicalSec: startSec, currentTrim: timelineTrim)
                        let endVirtual = mapPhysicalToVirtual(physicalSec: endSec, currentTrim: timelineTrim)

                        CutRangePreviewOverlay(
                            startVirtual: min(startVirtual, endVirtual),
                            endVirtual: max(startVirtual, endVirtual),
                            virtualDuration: timelineDuration,
                            contentWidth: contentWidth,
                            labelWidth: 49.0
                        )
                    }
                }
                .frame(width: max(baseWidth, baseWidth * CGFloat(timelineZoom)))
                .coordinateSpace(name: "timeline")
                .background(TimelineScrollWheelTuner(zoom: $timelineZoom))
            }
        }
        .padding(6)
        .background(Color.dynamic(light: Color.black.opacity(0.035), dark: Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dynamic(light: Color.black.opacity(0.11), dark: Color.white.opacity(0.11)), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func waveformBars(width: CGFloat, timelineDuration: Double, timelineCurrentSec: Double, activeVideoDuration: Double) -> some View {
        Canvas { context, size in
            let N = waveformPeaks.count

            // Draw horizontal midline (zero line)
            let midY = size.height / 2
            let zeroPath = Path { p in
                p.move(to: CGPoint(x: 0, y: midY))
                p.addLine(to: CGPoint(x: size.width, y: midY))
            }
            context.stroke(zeroPath, with: .color(Color.dynamic(light: Color(red: 160 / 255, green: 175 / 255, blue: 200 / 255), dark: Color(red: 45 / 255, green: 75 / 255, blue: 120 / 255))), style: StrokeStyle(lineWidth: 1.0))

            if N == 0 {
                let placeholderCount = Int(size.width / 2.0)
                let barWidth: CGFloat = 1.5
                for i in 0..<placeholderCount {
                    let x = CGFloat(i) * 2.0
                    let h: CGFloat = 10.0
                    let y = (size.height - h) / 2
                    let rect = CGRect(x: x, y: y, width: barWidth, height: h)
                    let path = Path(rect)
                    context.fill(path, with: .color(Color.dynamic(light: Color.black.opacity(0.06), dark: Color.white.opacity(0.06))))
                }
                return
            }

            let introDur = introDuration
            let outroDur = outroDuration
            let trimStart = timelineTrim.trimStartSec
            let activeVideoEndVirtual = trimStart + introDur + activeVideoDuration
            let outroEndVirtual = activeVideoEndVirtual + outroDur

            let activeStart = trimStart + introDur
            let activeEnd = activeVideoEndVirtual

            let barWidth: CGFloat = 1.5
            let drawCount = Int(size.width / barWidth)

            for j in 0..<drawCount {
                let vTime = (Double(j) / Double(max(1, drawCount - 1))) * timelineDuration
                let x = CGFloat(j) * barWidth

                let pTime: Double?
                let isSilent: Bool

                if vTime < trimStart {
                    pTime = vTime
                    isSilent = false
                } else if vTime >= trimStart && vTime < trimStart + introDur {
                    pTime = nil
                    isSilent = true
                } else if vTime >= trimStart + introDur && vTime < activeVideoEndVirtual {
                    pTime = vTime - introDur
                    isSilent = false
                } else if vTime >= activeVideoEndVirtual && vTime < outroEndVirtual {
                    pTime = nil
                    isSilent = true
                } else {
                    pTime = vTime - introDur - outroDur
                    isSilent = false
                }

                var peak = 0.0
                if !isSilent, let pTime = pTime, clipDuration > 0 {
                    let peakIndex = Int((pTime / clipDuration) * Double(N - 1))
                    peak = waveformPeaks[min(N - 1, max(0, peakIndex))]
                }

                let peakHeight = CGFloat(peak) * (size.height - 4)
                let y = (size.height - peakHeight) / 2

                let color: Color
                if vTime < activeStart || vTime > activeEnd {
                    color = Color.dynamic(light: Color(red: 200 / 255, green: 210 / 255, blue: 225 / 255), dark: Color(red: 23 / 255, green: 45 / 255, blue: 74 / 255))
                } else if vTime <= timelineCurrentSec {
                    color = Color.dynamic(light: Color(red: 30 / 255, green: 130 / 255, blue: 230 / 255), dark: Color(red: 57 / 255, green: 181 / 255, blue: 255 / 255))
                } else {
                    color = Color.dynamic(light: Color(red: 150 / 255, green: 195 / 255, blue: 245 / 255), dark: Color(red: 0 / 255, green: 130 / 255, blue: 240 / 255))
                }

                let rect = CGRect(x: x, y: y, width: barWidth, height: max(1.5, peakHeight))
                let path = Path(rect)
                context.fill(path, with: .color(color))
            }
        }
        .frame(width: width, height: 44)
        .padding(.horizontal, 4)
    }

    private var editPanel: some View {
        HStack(spacing: 10) {
            segmentList
                .frame(width: 300)
            VStack(spacing: 8) {
                toolbar
                ZStack(alignment: .topLeading) {
                    TextEditor(text: activeTextBinding)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(VaniScriptTheme.text0)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.dynamic(light: Color.black.opacity(0.04), dark: Color(red: 7 / 255, green: 11 / 255, blue: 23 / 255)))
                    if activeTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(activeTextPlaceholder)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(VaniScriptTheme.text2.opacity(0.58))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dynamic(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.12)), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if !activeWordsForChips.isEmpty {
                    wordChips
                }
            }
        }
    }

    private var segmentList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(currentSegments) { segment in
                    Button {
                        selectSubtitleTimelineBlock(segment.id)
                        seek(to: segment.start, autoplay: playing)
                    } label: {
                        let selected = segment.id == selectedSegmentID && selectedTextBlock == nil
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(clock(segment.start)) -> \(clock(segment.end))")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .foregroundStyle(VaniScriptTheme.accent)
                            Text(segment.text.isEmpty ? "[ Empty subtitle block ]" : segment.text)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selected ? VaniScriptTheme.text0 : VaniScriptTheme.text1)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(selected ? Color.dynamic(light: VaniScriptTheme.accent.opacity(0.15), dark: Color(red: 54 / 255, green: 42 / 255, blue: 26 / 255).opacity(0.88)) : Color.dynamic(light: Color.black.opacity(0.035), dark: Color.white.opacity(0.035)))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? VaniScriptTheme.accent.opacity(0.7) : Color.dynamic(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.08)), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if !currentTextTracks.isEmpty {
                    Text("TEXT OVERLAYS")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                    ForEach(currentTextTracks) { track in
                        ForEach(track.blocks) { block in
                            Button {
                                selectTextTimelineBlock(trackID: track.id, blockID: block.id)
                                seek(to: block.startSec, autoplay: playing)
                            } label: {
                                TextOverlayListRow(
                                    trackName: track.name,
                                    block: block,
                                    selected: selectedTextBlock?.trackID == track.id && selectedTextBlock?.blockID == block.id,
                                    startClock: clock(block.startSec),
                                    endClock: clock(block.endSec)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(6)
        }
        .background(Color.dynamic(light: Color.black.opacity(0.025), dark: Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dynamic(light: Color.black.opacity(0.1), dark: Color.white.opacity(0.1)), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            if canSplitSelectedTimelineBlock {
                EditorSmallButton(title: "Split", systemImage: "scissors", action: splitSelectedTimelineBlock)
            }
            if selectedSegment != nil {
                EditorSmallButton(title: "Add Subtitle Block", systemImage: "captions.bubble", action: addSubtitleBlock)
            }
            EditorSmallButton(title: "Add Text Block", systemImage: "text.badge.plus", action: addTextOverlayBlock)
            if canMergeNextSelectedTimelineBlock {
                EditorSmallButton(title: "Merge next", systemImage: "rectangle.split.2x1", action: mergeNextTimelineBlock)
            }
            if timelineSelection != nil {
                EditorSmallButton(title: "Delete", systemImage: "trash", action: deleteSelectedTimelineBlock)
            }
            Spacer()
        }
    }

    private var wordChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(activeWordsForChips.enumerated()), id: \.offset) { index, word in
                    HStack(spacing: 4) {
                        Button("<-") { moveWord(index: index, direction: -1) }
                            .buttonStyle(WordMoveButtonStyle())
                        Text(word)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VaniScriptTheme.text1)
                        Button("->") { moveWord(index: index, direction: 1) }
                            .buttonStyle(WordMoveButtonStyle())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.dynamic(light: Color.black.opacity(0.04), dark: Color.white.opacity(0.04)))
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var inspector: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(EditorInspectorTab.allCases, id: \.self) { tab in
                    Button {
                        inspectorTab = tab
                    } label: {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(InspectorTabButtonStyle(active: inspectorTab == tab))
                    .help(tab.tooltip)
                }
            }
            .padding(4)
            .background(Color.dynamic(light: Color.black.opacity(0.045), dark: Color.white.opacity(0.045)))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            ScrollView {
                switch inspectorTab {
                case .style:
                    styleInspector
                case .frame:
                    frameInspector
                case .background:
                    backgroundInspector
                case .layers:
                    layersInspector
                }
            }
        }
        .padding(12)
        .background(Color.dynamic(light: Color.white, dark: Color(red: 13 / 255, green: 17 / 255, blue: 34 / 255)))
        .overlay(Rectangle().fill(Color.dynamic(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.08))).frame(width: 1), alignment: .leading)
    }

    private var styleInspector: some View {
        let b = activeStyleBinding
        return VStack(alignment: .leading, spacing: 12) {
            InspectorTitle("Style", subtitle: "Subtitles and each text overlay track can have its own style.")

            styleTabSelector
                .padding(.bottom, 6)

            PickerRow(title: "Font", selection: b.fontFamily, options: ["Cuprum", "Oswald", "Unbounded", "Montserrat", "Inter", "Arial"])
            Toggle("Bold", isOn: b.bold)
                .toggleStyle(.checkbox)
                .foregroundStyle(VaniScriptTheme.text1)
            PickerRow(title: "Case", selection: Binding(
                get: { b.wrappedValue.textTransform.rawValue },
                set: { newValue in
                    var updated = b.wrappedValue
                    updated.textTransform = ShortsTextTransform(rawValue: newValue) ?? .none
                    b.wrappedValue = updated
                }
            ), options: ["uppercase", "title", "none"])
            SliderRow(title: "Size", value: b.fontSize, range: 30...200, suffix: "")
            SliderRow(title: "Bottom margin", value: Binding(
                get: { b.wrappedValue.subtitleBottomMargin ?? 560.0 },
                set: { newValue in
                    var updated = b.wrappedValue
                    updated.subtitleBottomMargin = newValue
                    b.wrappedValue = updated
                }
            ), range: 0...1800, step: 10, suffix: "px")
            ColorTextRow(title: "Text color", value: b.textColor)
            SliderRow(title: "Letter spacing", value: b.letterSpacing, range: -2...8, step: 0.25, suffix: "")
            SliderRow(title: "Line spacing", value: b.lineSpacing, range: 0.8...1.6, step: 0.05, suffix: "x")
            SliderRow(title: "Outline", value: b.outline, range: 0...10, step: 0.5, suffix: "px")
            OptionalSliderRow(title: "Outline opacity", value: b.outlineOpacity, fallback: 0.58, range: 0...1, step: 0.05, percent: true)
            OptionalColorTextRow(title: "Outline color", value: b.outlineColor, fallback: "#000000")
            OptionalSliderRow(title: "Shadow size", value: b.shadowDistance, fallback: 6, range: 0...20, suffix: "px")
            OptionalSliderRow(title: "Shadow blur", value: b.shadowBlur, fallback: 3, range: 0...20, suffix: "px")
            OptionalSliderRow(title: "Shadow angle", value: b.shadowAngle, fallback: 90, range: 0...360, step: 5, suffix: "deg")
            OptionalSliderRow(title: "Shadow opacity", value: b.shadowOpacity, fallback: 0.72, range: 0...1, step: 0.05, percent: true)
            OptionalColorTextRow(title: "Shadow color", value: b.shadowColor, fallback: "#000000")
            ColorTextRow(title: "Box color", value: b.boxColor)
            SliderRow(title: "Box opacity", value: b.boxOpacity, range: 0...1, step: 0.02, percent: true)
            SliderRow(title: "Box width", value: b.boxWidth, range: 48...96, suffix: "%")
            SliderRow(title: "Box height", value: b.boxHeight, range: 0.5...8, step: 0.05, suffix: "x")
            SliderRow(title: "Edge softness", value: b.edgeSoftness, range: 0...1, step: 0.01, percent: true)
            SliderRow(title: "Edge blur", value: b.edgeBlur, range: 0...80, step: 0.5, suffix: "px")
        }
    }

    private var frameInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorTitle("Frame animation", subtitle: "Adjust the frame, then add a point. Transitions between points are smooth.")
            ColorTextRow(title: "Border color", value: $backgroundSettings.frameGuideColor)
            SliderRow(title: "Dim", value: $backgroundSettings.frameGuideOpacity, range: 0...1, step: 0.05, percent: true)
            SliderRow(title: "Border", value: $backgroundSettings.frameGuideBorderWidth, range: 0...30, step: 0.5, suffix: "px")
            SliderRow(title: "Opacity", value: $backgroundSettings.frameGuideBorderOpacity, range: 0...1, step: 0.05, percent: true)
            SliderRow(title: "Glow", value: $backgroundSettings.frameGuideBlur, range: 0...160, step: 1, suffix: "px")
            SliderRow(title: "Zoom", value: $frameZoom, range: 0.5...2.5, step: 0.01, suffix: "x", onChange: materializeCurrentKeyframe)
            SliderRow(title: "Pan X", value: $framePanX, range: -50...50, suffix: "", onChange: materializeCurrentKeyframe)
            SliderRow(title: "Pan Y", value: $framePanY, range: -30...30, suffix: "", onChange: materializeCurrentKeyframe)
            HStack {
                EditorSmallButton(title: "Add point", systemImage: "plus", action: materializeCurrentKeyframe)
                EditorSmallButton(title: "Clear", systemImage: "trash", action: clearKeyframes)
            }
            keyframeList
        }
    }

    private var keyframeList: some View {
        VStack(spacing: 6) {
            if currentFrameKeyframes.isEmpty {
                Text("No animation points yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
            } else {
                ForEach(currentFrameKeyframes) { keyframe in
                    Button {
                        frameZoom = keyframe.zoom
                        framePanX = keyframe.x
                        framePanY = keyframe.y
                        seek(to: keyframe.time, autoplay: playing)
                    } label: {
                        HStack {
                            Text(clock(keyframe.time))
                            Spacer()
                            Text("\(keyframe.zoom, specifier: "%.2f")x · X \(Int(keyframe.x)) · Y \(Int(keyframe.y))")
                        }
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(VaniScriptTheme.text1)
                        .padding(8)
                        .background(Color.dynamic(light: Color.black.opacity(0.035), dark: Color.white.opacity(0.035)))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var backgroundInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorTitle("Background settings", subtitle: "Layer multiple background effects. Toggle each mode independently.")
            Toggle("Solid color", isOn: $backgroundSettings.solidEnabled)
                .toggleStyle(.checkbox)
            ColorTextRow(title: "Color", value: $backgroundSettings.solidColor)
            Toggle("Blur background", isOn: $backgroundSettings.blurEnabled)
                .toggleStyle(.checkbox)
            SliderRow(title: "Blur", value: $backgroundSettings.blurStrength, range: 1...80, suffix: "px")
            SliderRow(title: "Scale", value: $backgroundSettings.blurScale, range: 1...2, step: 0.05, suffix: "x")
            SliderRow(title: "Pan X", value: Binding(
                get: { backgroundSettings.blurPanX ?? 0.0 },
                set: { backgroundSettings.blurPanX = $0 }
            ), range: -100...100, step: 1.0, suffix: "%")
            Toggle("Gradient overlay", isOn: $backgroundSettings.gradientEnabled)
                .toggleStyle(.checkbox)
            PickerRow(title: "Type", selection: $backgroundSettings.gradientType, options: ["linear", "radial"])
            ColorTextRow(title: "Color A", value: $backgroundSettings.gradientColorA)
            ColorTextRow(title: "Color B", value: $backgroundSettings.gradientColorB)
            SliderRow(title: "Angle", value: $backgroundSettings.gradientAngle, range: 0...360, suffix: "deg")
            SliderRow(title: "Opacity", value: $backgroundSettings.gradientOpacity, range: 0...1, step: 0.05, percent: true)
            Toggle("Edge feather", isOn: $backgroundSettings.featherEnabled)
                .toggleStyle(.checkbox)
            SliderRow(title: "Top depth", value: $backgroundSettings.featherTop, range: 0...400, suffix: "px")
            SliderRow(title: "Top strength", value: Binding(
                get: { backgroundSettings.featherTopHeight ?? 100.0 },
                set: { backgroundSettings.featherTopHeight = $0 }
            ), range: 0...100, step: 1.0, percent: true)
            SliderRow(title: "Bottom depth", value: $backgroundSettings.featherBottom, range: 0...400, suffix: "px")
            SliderRow(title: "Bottom strength", value: Binding(
                get: { backgroundSettings.featherBottomHeight ?? 100.0 },
                set: { backgroundSettings.featherBottomHeight = $0 }
            ), range: 0...100, step: 1.0, percent: true)
        }
        .foregroundStyle(VaniScriptTheme.text1)
    }

    private var layersInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorTitle("Layers", subtitle: "Logo, intro/outro graphics, extra text tracks, and extra audio match the desktop VaniScript editor.")
            logoLayerEditor
            introOutroLayerEditor(title: "Intro Graphic", type: .intro)
            introOutroLayerEditor(title: "Outro Graphic", type: .outro)
            textTracksLayerEditor
            audioTracksLayerEditor
        }
    }

    private var logoLayerEditor: some View {
        LayerEditorCard(title: "Logo", detail: "Fixed overlay inside safe margins.", systemImage: "photo") {
            HStack {
                EditorSmallButton(title: "Upload Logo", systemImage: "photo.badge.plus", action: importLogo)
                if currentLogo != nil {
                    EditorSmallButton(title: "Remove", systemImage: "trash", action: { setCurrentLogo(nil) })
                }
            }
            if let logo = currentLogo {
                Text(logo.name ?? "Logo")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(VaniScriptTheme.text1)
                SliderRow(title: "Size", value: Binding(get: { currentLogo?.size ?? 1 }, set: { value in updateCurrentLogo { logo in logo.size = value } }), range: 0.5...2, step: 0.05, percent: true)
                PickerRow(title: "Corner", selection: Binding(get: { currentLogo?.position ?? "top-left" }, set: { value in updateCurrentLogo { logo in logo.position = value } }), options: ["top-left", "top-right", "bottom-left", "bottom-right"])
                SliderRow(title: "Opacity", value: Binding(get: { currentLogo?.opacity ?? 1 }, set: { value in updateCurrentLogo { logo in logo.opacity = value } }), range: 0...1, step: 0.05, percent: true)
                Toggle("Visible", isOn: Binding(get: { currentLogo?.hidden != true }, set: { visible in updateCurrentLogo { logo in logo.hidden = !visible } }))
                    .toggleStyle(.checkbox)
            } else {
                EmptyLayerText("No logo uploaded.")
            }
        }
    }

    private func introOutroLayerEditor(title: String, type: IntroOutroLayerType) -> some View {
        let item = type == .intro ? currentIntro : currentOutro
        return LayerEditorCard(title: title, detail: type == .intro ? "Graphic displayed before the clip starts." : "Graphic displayed at the end of the clip.", systemImage: "rectangle.inset.filled") {
            HStack {
                EditorSmallButton(title: "Upload Graphic", systemImage: "photo.badge.plus", action: { importIntroOutro(type) })
                if item != nil {
                    EditorSmallButton(title: "Remove", systemImage: "trash", action: { setCurrentIntroOutro(nil, type: type) })
                }
            }
            if let item {
                Text(item.name ?? title)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(VaniScriptTheme.text1)
                SliderRow(title: "Duration", value: Binding(get: { (type == .intro ? currentIntro : currentOutro)?.duration ?? 3 }, set: { value in updateCurrentIntroOutro(type) { item in item.duration = value } }), range: 1...5, step: 0.5, suffix: "s")
                SliderRow(title: "Transition", value: Binding(get: { (type == .intro ? currentIntro : currentOutro)?.transitionSec ?? 1 }, set: { value in updateCurrentIntroOutro(type) { item in item.transitionSec = value } }), range: 0...3, step: 0.1, suffix: "s")
                SliderRow(title: "Y", value: Binding(get: { (type == .intro ? currentIntro : currentOutro)?.y ?? 50 }, set: { value in updateCurrentIntroOutro(type) { item in item.y = value } }), range: 0...100, suffix: "%")
                SliderRow(title: "Scale", value: Binding(get: { ((type == .intro ? currentIntro : currentOutro)?.scale ?? 0.5) * 100 }, set: { value in updateCurrentIntroOutro(type) { item in item.scale = value / 100 } }), range: 50...500, step: 10, suffix: "%")
                SliderRow(title: "Speed", value: Binding(get: { ((type == .intro ? currentIntro : currentOutro)?.speed ?? 1) * 100 }, set: { value in updateCurrentIntroOutro(type) { item in item.speed = value / 100 } }), range: 0...200, step: 10, suffix: "%")
                PickerRow(title: "Animation", selection: Binding(get: { (type == .intro ? currentIntro : currentOutro)?.animation ?? "fade" }, set: { value in updateCurrentIntroOutro(type) { item in item.animation = value } }), options: ["none", "fade", "pulse", "bounce"])
                Toggle("Visible", isOn: Binding(get: { (type == .intro ? currentIntro : currentOutro)?.hidden != true }, set: { visible in updateCurrentIntroOutro(type) { item in item.hidden = !visible } }))
                    .toggleStyle(.checkbox)
            } else {
                EmptyLayerText("No \(type == .intro ? "intro" : "outro") graphic uploaded.")
            }
        }
    }

    private var textTracksLayerEditor: some View {
        LayerEditorCard(title: "Text overlays", detail: "CTA, speaker names, references, or event notes. Max 3 tracks.", systemImage: "textformat") {
            HStack {
                EditorSmallButton(title: "Text Track", systemImage: "plus", action: addTextTrack)
                EditorSmallButton(title: "Text Block", systemImage: "text.badge.plus", action: addTextOverlayBlock)
            }
            if currentTextTracks.isEmpty {
                EmptyLayerText("No text tracks yet.")
            } else {
                ForEach(currentTextTracks) { track in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Track name", text: Binding(get: { trackName(track.id) }, set: { value in updateTextTrack(id: track.id) { track in track.name = value } }))
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                            Button { removeTextTrack(id: track.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(EditorIconButtonStyle())
                        }
                        Toggle("Visible", isOn: Binding(get: { track.hidden != true }, set: { visible in updateTextTrack(id: track.id) { $0.hidden = !visible } }))
                            .toggleStyle(.checkbox)
                        Text("\(track.blocks.count) block\(track.blocks.count == 1 ? "" : "s"). Add and edit blocks in the center timeline editor.")
                            .font(.system(size: 10))
                            .foregroundStyle(VaniScriptTheme.text2)
                    }
                    .padding(8)
                    .background(Color.dynamic(light: Color.black.opacity(0.03), dark: Color.white.opacity(0.03)))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .opacity(track.hidden == true ? 0.65 : 1.0)
                }
            }
        }
    }

    private var audioTracksLayerEditor: some View {
        LayerEditorCard(title: "Extra audio", detail: "Music, ambient sound, intro, or outro. Max 3 tracks.", systemImage: "waveform") {
            EditorSmallButton(title: "Audio Track", systemImage: "plus", action: importAudioTrack)
            if currentAudioTracks.isEmpty {
                EmptyLayerText("No extra audio tracks.")
            } else {
                ForEach(currentAudioTracks) { track in
                    let player = extraAudioPlayers[track.id]
                    let rawAssetDuration = player?.currentItem?.asset.duration.seconds ?? 0.0
                    let assetDuration = (rawAssetDuration.isNaN || rawAssetDuration <= 0) ? clipDuration : rawAssetDuration

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(track.name)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(VaniScriptTheme.text1)
                            Spacer()
                            Button { removeAudioTrack(id: track.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(EditorIconButtonStyle())
                        }
                        Toggle("Audible", isOn: Binding(get: { track.muted != true }, set: { audible in updateAudioTrack(id: track.id) { $0.muted = !audible } }))
                            .toggleStyle(.checkbox)
                        SliderRow(title: "Start", value: Binding(
                            get: { audioTrack(track.id)?.startSec ?? 0 },
                            set: { value in
                                updateAudioTrack(id: track.id, syncPlayback: false) { t in
                                    let playableDur = max(0.25, assetDuration - t.trimStartSec - t.trimEndSec)
                                    t.startSec = min(max(0, value), max(0, virtualDuration - playableDur))
                                }
                            }
                        ), range: 0...virtualDuration, step: 0.05, suffix: "s", onEditingChanged: { editing in
                            if !editing { updateExtraAudioPlayback() }
                        })

                        SliderRow(title: "Trim In", value: Binding(
                            get: { audioTrack(track.id)?.trimStartSec ?? 0 },
                            set: { value in
                                updateAudioTrack(id: track.id, syncPlayback: false) { t in
                                    let constrainedValue = min(max(0, value), assetDuration - t.trimEndSec - 0.25)
                                    let delta = constrainedValue - t.trimStartSec
                                    t.startSec = min(max(0, t.startSec + delta), max(0, virtualDuration - 0.25))
                                    t.trimStartSec = constrainedValue
                                }
                            }
                        ), range: 0...max(0.1, assetDuration - track.trimEndSec - 0.25), step: 0.05, suffix: "s", onEditingChanged: { editing in
                            if !editing { updateExtraAudioPlayback() }
                        })

                        SliderRow(title: "Trim Out", value: Binding(
                            get: { audioTrack(track.id)?.trimEndSec ?? 0 },
                            set: { value in
                                updateAudioTrack(id: track.id, syncPlayback: false) { t in
                                    let constrainedValue = min(max(0, value), assetDuration - t.trimStartSec - 0.25)
                                    t.trimEndSec = constrainedValue
                                    let playableDur = max(0.25, assetDuration - t.trimStartSec - constrainedValue)
                                    t.startSec = min(t.startSec, max(0, virtualDuration - playableDur))
                                }
                            }
                        ), range: 0...max(0.1, assetDuration - track.trimStartSec - 0.25), step: 0.05, suffix: "s", onEditingChanged: { editing in
                            if !editing { updateExtraAudioPlayback() }
                        })

                        SliderRow(title: "Fade In", value: Binding(get: { audioTrack(track.id)?.fadeInSec ?? 0 }, set: { value in updateAudioTrack(id: track.id) { $0.fadeInSec = value } }), range: 0...10, step: 0.1, suffix: "s")
                        SliderRow(title: "Fade Out", value: Binding(get: { audioTrack(track.id)?.fadeOutSec ?? 0 }, set: { value in updateAudioTrack(id: track.id) { $0.fadeOutSec = value } }), range: 0...10, step: 0.1, suffix: "s")
                        SliderRow(title: "Volume", value: Binding(get: { audioTrack(track.id)?.volume ?? 0.5 }, set: { value in updateAudioTrack(id: track.id) { $0.volume = value } }), range: 0...1, step: 0.05, percent: true)
                    }
                    .padding(8)
                    .background(Color.dynamic(light: Color.black.opacity(0.03), dark: Color.white.opacity(0.03)))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .opacity(track.muted == true ? 0.65 : 1.0)
                }
            }
        }
    }

    private var currentSegments: [AlignedSubtitleSegment] {
        language == .source ? sourceSegments : targetSegments
    }

    private var currentFrameKeyframes: [FrameKeyframe] {
        language == .source ? sourceFrameKeyframes : targetFrameKeyframes
    }

    private var currentLogo: LogoOverlaySettings? {
        language == .source ? sourceLogo : targetLogo
    }

    private var currentTextTracks: [TextOverlayTrack] {
        language == .source ? sourceTextTracks : targetTextTracks
    }

    private var activeStyleBinding: Binding<ShortsSubtitleStyle> {
        Binding(
            get: {
                if selectedStyleTab == 0 {
                    return self.style
                } else {
                    let tracks = self.currentTextTracks
                    let idx = selectedStyleTab - 1
                    if idx >= 0 && idx < tracks.count {
                        return tracks[idx].style ?? self.defaultTextTrackStyle(trackIndex: idx)
                    }
                    return self.style
                }
            },
            set: { newValue in
                if selectedStyleTab == 0 {
                    self.style = newValue
                } else {
                    let tracks = self.currentTextTracks
                    let idx = selectedStyleTab - 1
                    if idx >= 0 && idx < tracks.count {
                        let trackID = tracks[idx].id
                        self.updateTextTrack(id: trackID) { track in
                            track.style = newValue
                        }
                    }
                }
            }
        )
    }

    private func defaultTextTrackStyle(trackIndex: Int) -> ShortsSubtitleStyle {
        var trackStyle = style
        trackStyle.subtitleBottomMargin = defaultTextTrackBottomMargin(trackIndex: trackIndex)
        return trackStyle
    }

    private func defaultTextTrackBottomMargin(trackIndex: Int) -> Double {
        min(1780, 700.0 + Double(trackIndex) * 140.0)
    }

    private var styleTabSelector: some View {
        HStack(spacing: 8) {
            Button {
                selectedStyleTab = 0
            } label: {
                Text("Subtitles")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(selectedStyleTab == 0 ? VaniScriptTheme.accent : VaniScriptTheme.text1)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(selectedStyleTab == 0 ? VaniScriptTheme.accent : Color.dynamic(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.2)), lineWidth: 1)
                            .background(selectedStyleTab == 0 ? VaniScriptTheme.accent.opacity(0.08) : Color.dynamic(light: Color.black.opacity(0.02), dark: Color.white.opacity(0.02)))
                    )
            }
            .buttonStyle(.plain)

            ForEach(Array(currentTextTracks.enumerated()), id: \.element.id) { index, track in
                let tabIndex = index + 1
                Button {
                    selectedStyleTab = tabIndex
                } label: {
                    Text(track.name)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(selectedStyleTab == tabIndex ? VaniScriptTheme.accent : VaniScriptTheme.text1)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selectedStyleTab == tabIndex ? VaniScriptTheme.accent : Color.dynamic(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.2)), lineWidth: 1)
                                .background(selectedStyleTab == tabIndex ? VaniScriptTheme.accent.opacity(0.08) : Color.dynamic(light: Color.black.opacity(0.02), dark: Color.white.opacity(0.02)))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var currentAudioTracks: [ExtraAudioTrack] {
        language == .source ? sourceAudioTracks : targetAudioTracks
    }

    private var currentIntro: IntroOutroOverlaySettings? {
        language == .source ? sourceIntro : targetIntro
    }

    private var currentOutro: IntroOutroOverlaySettings? {
        language == .source ? sourceOutro : targetOutro
    }

    private var clipDuration: Double {
        max(1, endSec - startSec)
    }

    private var videoAspectRatio: Double {
        if let player,
           let currentItem = player.currentItem {
            if currentItem.presentationSize.width > 0 && currentItem.presentationSize.height > 0 {
                return Double(currentItem.presentationSize.width / currentItem.presentationSize.height)
            }
            if let track = currentItem.asset.tracks(withMediaType: .video).first {
                let size = track.naturalSize.applying(track.preferredTransform)
                let w = abs(size.width)
                let h = abs(size.height)
                if w > 0 && h > 0 {
                    return Double(w / h)
                }
            }
        }
        return 16.0 / 9.0
    }

    private var introDuration: Double {
        if let intro = currentIntro, intro.hidden != true {
            return intro.duration
        }
        return 0
    }

    private var outroDuration: Double {
        if let outro = currentOutro, outro.hidden != true {
            return outro.duration
        }
        return 0
    }

    private var activeVideoOutputDuration: Double {
        TimelineCutTimeMapper.activeOutputDuration(
            clipDuration: clipDuration,
            trim: timelineTrim,
            cuts: []
        )
    }

    private var virtualDuration: Double {
        TimelineCutTimeMapper.virtualDuration(
            clipDuration: clipDuration,
            trim: timelineTrim,
            cuts: [],
            introDuration: introDuration,
            outroDuration: outroDuration
        )
    }

    private var mainVideoOpacity: Double {
        let introActive = currentIntro != nil && currentIntro?.hidden != true
        let outroActive = currentOutro != nil && currentOutro?.hidden != true
        let introDur = introDuration
        let outroDur = outroDuration

        let outroStart = timelineTrim.trimStartSec + introDur + activeVideoOutputDuration

        // During Intro, main video is fully hidden
        if introActive && currentSec >= timelineTrim.trimStartSec && currentSec < timelineTrim.trimStartSec + introDur {
            return 0
        }
        // During Outro, main video is fully hidden
        if outroActive && currentSec >= outroStart && currentSec < outroStart + outroDur {
            return 0
        }
        // In trimmed-out regions, video is hidden
        if currentSec < timelineTrim.trimStartSec || currentSec > outroStart + outroDur {
            return 0
        }

        var opacity: Double = 1
        // Fade in right after Intro ends
        let introFadeSec = introActive ? (currentIntro?.transitionSec ?? 1.0) : 1.0
        let activeVideoStart = timelineTrim.trimStartSec + introDur
        if introActive && introFadeSec > 0 && currentSec >= activeVideoStart && currentSec <= activeVideoStart + introFadeSec {
            opacity = (currentSec - activeVideoStart) / introFadeSec
        }
        // Fade out right before Outro starts
        let outroFadeSec = outroActive ? (currentOutro?.transitionSec ?? 1.0) : 1.0
        if outroActive && outroFadeSec > 0 && currentSec >= outroStart - outroFadeSec && currentSec <= outroStart {
            opacity = min(opacity, (outroStart - currentSec) / outroFadeSec)
        }
        return max(0, min(1, opacity))
    }

    private func mapVirtualToPhysical(virtualSec: Double, currentTrim: TimelineTrim) -> Double {
        TimelineCutTimeMapper.mapVirtualToPhysical(
            virtualSec: virtualSec,
            clipDuration: clipDuration,
            trim: currentTrim,
            cuts: [],
            introDuration: introDuration,
            outroDuration: outroDuration
        )
    }

    private func shouldPlayMutedBackgroundVideo(at virtualSec: Double) -> Bool {
        guard backgroundSettings.blurEnabled else { return false }
        let currentTrim = timelineTrim
        let introDur = introDuration
        let outroDur = outroDuration
        let activeVideoStartVirtual = currentTrim.trimStartSec + introDur
        let activeVideoEndVirtual = activeVideoStartVirtual + activeVideoOutputDuration

        if introDur > 0,
           virtualSec >= currentTrim.trimStartSec,
           virtualSec < activeVideoStartVirtual {
            return true
        }
        if outroDur > 0,
           virtualSec >= activeVideoEndVirtual,
           virtualSec < activeVideoEndVirtual + outroDur {
            return true
        }
        return false
    }

    private func blurBackgroundPhysicalSec(virtualSec: Double, currentTrim: TimelineTrim) -> Double {
        let windowStart = min(max(0, currentTrim.trimStartSec), clipDuration)
        let windowEnd = min(max(windowStart, clipDuration - currentTrim.trimEndSec), clipDuration)
        let activeWindowDuration = max(0.05, windowEnd - windowStart)
        let introDur = introDuration
        let activeVideoStartVirtual = currentTrim.trimStartSec + introDur
        let activeVideoEndVirtual = activeVideoStartVirtual + activeVideoOutputDuration

        if virtualSec < activeVideoStartVirtual {
            let elapsed = max(0, virtualSec - currentTrim.trimStartSec)
            return windowStart + loopingOffset(elapsed, duration: activeWindowDuration)
        }
        if virtualSec >= activeVideoEndVirtual {
            let elapsed = max(0, virtualSec - activeVideoEndVirtual)
            return windowStart + loopingOffset(elapsed, duration: activeWindowDuration)
        }
        return mapVirtualToPhysical(virtualSec: virtualSec, currentTrim: currentTrim)
    }

    private func loopingOffset(_ elapsed: Double, duration: Double) -> Double {
        guard duration > 0.05 else { return 0 }
        let value = elapsed.truncatingRemainder(dividingBy: duration)
        return value >= 0 ? value : value + duration
    }

    private func mapPhysicalToVirtual(physicalSec: Double, currentTrim: TimelineTrim) -> Double {
        TimelineCutTimeMapper.mapPhysicalToVirtual(
            physicalSec: physicalSec,
            clipDuration: clipDuration,
            trim: currentTrim,
            cuts: [],
            introDuration: introDuration,
            outroDuration: outroDuration
        )
    }

    private func findCut(at physicalSec: Double) -> TimelineCut? {
        timelineCuts.first { physicalSec >= $0.startSec && physicalSec < $0.endSec }
    }

    private var timelineHeight: CGFloat {
        let baseHeight: CGFloat = 126 // Video (14) + Audio (52) + Subs (36) + spacing
        let extraAudioTracksCount = CGFloat(currentAudioTracks.count)
        let extraTextTracksCount = CGFloat(currentTextTracks.count)
        return baseHeight + (extraAudioTracksCount * 29) + (extraTextTracksCount * 39)
    }

    private var activeSegment: AlignedSubtitleSegment? {
        let introDur = introDuration
        let outroDur = outroDuration
        let limit = virtualDuration - outroDur
        if currentSec < introDur || currentSec >= limit {
            return nil
        }
        return currentSegments.first { currentSec >= $0.start + introDur && currentSec < $0.end + introDur }
    }

    private var timelineSelection: TimelineSelection? {
        if let selectedTextBlock {
            return .text(trackID: selectedTextBlock.trackID, blockID: selectedTextBlock.blockID)
        }
        if !selectedSegmentID.isEmpty {
            return .subtitle(selectedSegmentID)
        }
        return nil
    }

    private func selectSubtitleTimelineBlock(_ id: String) {
        clearTextInputFocus()
        selectedSegmentID = id
        selectedTextBlock = nil
        selectedStyleTab = 0
    }

    private func selectTextTimelineBlock(trackID: String, blockID: String) {
        clearTextInputFocus()
        selectedTextBlock = (trackID, blockID)
        selectedSegmentID = ""
        if let index = currentTextTracks.firstIndex(where: { $0.id == trackID }) {
            selectedStyleTab = index + 1
        }
    }

    private var selectedSegment: AlignedSubtitleSegment? {
        guard selectedTextBlock == nil,
              case let .subtitle(id)? = timelineSelection
        else { return nil }
        return currentSegments.first { $0.id == id }
    }

    private var selectedTextOverlay: TextOverlayBlock? {
        guard let selectedTextBlock,
              let track = currentTextTracks.first(where: { $0.id == selectedTextBlock.trackID })
        else { return nil }
        return track.blocks.first { $0.id == selectedTextBlock.blockID }
    }

    private var activeTextPlaceholder: String {
        selectedTextOverlay != nil ? "[ Empty Text Block ]" : "[ Empty Subtitle Block ]"
    }

    private var selectedSegmentWordCount: Int {
        normalizedWords(selectedSegment?.text ?? "").count
    }

    private var selectedTextWordCount: Int {
        normalizedWords(selectedTextOverlay?.text ?? "").count
    }

    private var canSplitSelectedTimelineBlock: Bool {
        switch timelineSelection {
        case .subtitle:
            return selectedSegmentWordCount > 1
        case .text:
            return selectedTextWordCount > 1
        case .none:
            return false
        }
    }

    private var canMergeNextSelectedTimelineBlock: Bool {
        switch timelineSelection {
        case .subtitle:
            return canMergeNextSegment()
        case .text:
            return canMergeNextTextOverlay()
        case .none:
            return false
        }
    }

    private var activeWordsForChips: [String] {
        guard selectedTextOverlay == nil else { return [] }
        return normalizedWords(selectedSegment?.text ?? "")
    }

    private var activeTextBinding: Binding<String> {
        Binding(
            get: { selectedTextOverlay?.text ?? selectedSegment?.text ?? "" },
            set: { text in
                if selectedTextOverlay != nil {
                    updateSelectedTextOverlay(text: text)
                } else {
                    updateSelectedText(text)
                }
            }
        )
    }

    private func switchLanguage(_ next: ShortsIdeaDisplayLanguage) {
        saveCurrentFrameState()
        language = next
        selectSubtitleTimelineBlock((next == .source ? sourceSegments : targetSegments).first?.id ?? "")
        let keyframe = (next == .source ? sourceFrameKeyframes : targetFrameKeyframes).first
        frameZoom = keyframe?.zoom ?? 1
        framePanX = keyframe?.x ?? 0
        framePanY = keyframe?.y ?? 0
    }

    private func save(stayOpen: Bool) {
        saveCurrentFrameState()
        VisualEditorSettingsBackupStore.capture(makeVisualSettingsSnapshot())

        var updatedSourceAudioTracks = sourceAudioTracks
        for i in 0..<updatedSourceAudioTracks.count {
            let track = updatedSourceAudioTracks[i]
            if let player = extraAudioPlayers[track.id] {
                let dur = player.currentItem?.asset.duration.seconds ?? 0
                if dur > 0 && !dur.isNaN {
                    updatedSourceAudioTracks[i].assetDuration = dur
                }
            }
        }
        var updatedTargetAudioTracks = targetAudioTracks
        for i in 0..<updatedTargetAudioTracks.count {
            let track = updatedTargetAudioTracks[i]
            if let player = extraAudioPlayers[track.id] {
                let dur = player.currentItem?.asset.duration.seconds ?? 0
                if dur > 0 && !dur.isNaN {
                    updatedTargetAudioTracks[i].assetDuration = dur
                }
            }
        }

        onSave(
            EditClipValues(
                language: language,
                start: ShortsPlanner.secondsToShortsTimestamp(startSec),
                end: ShortsPlanner.secondsToShortsTimestamp(endSec),
                title: title,
                summary: summary,
                hook: hook,
                category: category,
                captionText: captionText,
                sourceAlignment: sourceSegments,
                targetAlignment: targetSegments,
                sourceFrameKeyframes: sourceFrameKeyframes,
                targetFrameKeyframes: targetFrameKeyframes,
                timelineCuts: timelineCuts,
                timelineTrim: timelineTrim,
                backgroundSettings: backgroundSettings,
                subtitleStyle: style,
                syncEnabled: syncEnabled,
                sourceLogo: sourceLogo,
                targetLogo: targetLogo,
                sourceTextTracks: sourceTextTracks,
                targetTextTracks: targetTextTracks,
                sourceAudioTracks: updatedSourceAudioTracks,
                targetAudioTracks: updatedTargetAudioTracks,
                sourceIntro: sourceIntro,
                targetIntro: targetIntro,
                sourceOutro: sourceOutro,
                targetOutro: targetOutro
            )
        )
        if stayOpen {
            savedFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                savedFlash = false
            }
        }
    }

    private func makeVisualSettingsSnapshot() -> VisualEditorSettingsSnapshot {
        VisualEditorSettingsSnapshot(
            createdAt: ISO8601DateFormatter().string(from: Date()),
            clipIndex: draft.index,
            language: language,
            title: title,
            start: ShortsPlanner.secondsToShortsTimestamp(startSec),
            end: ShortsPlanner.secondsToShortsTimestamp(endSec),
            subtitleStyle: style,
            backgroundSettings: backgroundSettings,
            timelineCuts: timelineCuts,
            timelineTrim: timelineTrim,
            sourceFrameKeyframes: sourceFrameKeyframes,
            targetFrameKeyframes: targetFrameKeyframes,
            sourceLogo: sourceLogo,
            targetLogo: targetLogo,
            sourceTextTracks: sourceTextTracks,
            targetTextTracks: targetTextTracks,
            sourceAudioTracks: sourceAudioTracks,
            targetAudioTracks: targetAudioTracks,
            sourceIntro: sourceIntro,
            targetIntro: targetIntro,
            sourceOutro: sourceOutro,
            targetOutro: targetOutro
        )
    }

    private func resetEditor() {
        recordUndo()
        sourceSegments = draft.sourceAlignment
        targetSegments = draft.targetAlignment

        // Reset animation points, zoom, and pan to initial centered state
        sourceFrameKeyframes = []
        targetFrameKeyframes = []
        frameZoom = 1.0
        framePanX = 0.0
        framePanY = 0.0

        timelineCuts = []
        timelineTrim = TimelineTrim(trimStartSec: 0, trimEndSec: 0)

        // Reset background settings to zero (all disabled, dim 50%)
        backgroundSettings.solidEnabled = false
        backgroundSettings.blurEnabled = false
        backgroundSettings.gradientEnabled = false
        backgroundSettings.featherEnabled = false
        backgroundSettings.featherTopHeight = 100.0
        backgroundSettings.featherBottomHeight = 100.0
        backgroundSettings.blurPanX = 0.0
        backgroundSettings.frameGuideOpacity = 0.5

        sourceLogo = nil
        targetLogo = nil
        sourceTextTracks = []
        targetTextTracks = []
        sourceAudioTracks = []
        targetAudioTracks = []
        sourceIntro = nil
        targetIntro = nil
        sourceOutro = nil
        targetOutro = nil
        selectedTextBlock = nil
        syncEnabled = draft.syncEnabled
        currentSec = 0
        selectSubtitleTimelineBlock(currentSegments.first?.id ?? "")
        seek(to: 0, autoplay: false)
    }

    private func tickPlayback() {
        guard playing else { return }
        let delta = 0.05

        let introDur = introDuration
        let outroDur = outroDuration
        let currentTrim = timelineTrim

        let currentPlayStart = currentTrim.trimStartSec
        var nextSec = currentSec

        let activeVideoStartVirtual = currentTrim.trimStartSec + introDur
        let activeVideoEndVirtual = activeVideoStartVirtual + (clipDuration - currentTrim.trimStartSec - currentTrim.trimEndSec)
        let outroEndVirtual = activeVideoEndVirtual + outroDur

        if nextSec < currentTrim.trimStartSec {
            nextSec = currentPlayStart
        } else if nextSec < activeVideoStartVirtual {
            // We are in the Intro region
            nextSec += delta
            if shouldPlayMutedBackgroundVideo(at: nextSec) {
                syncMutedBackgroundVideo(to: blurBackgroundPhysicalSec(virtualSec: nextSec, currentTrim: currentTrim))
            } else {
                player?.pause()
            }
            if nextSec >= activeVideoStartVirtual {
                nextSec = activeVideoStartVirtual
                let physicalStart = startSec + currentTrim.trimStartSec
                player?.seek(to: CMTime(seconds: physicalStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                player?.play()
            }
        } else if nextSec >= activeVideoEndVirtual && nextSec < outroEndVirtual {
            // We are in the Outro region
            nextSec += delta
            if shouldPlayMutedBackgroundVideo(at: nextSec) {
                syncMutedBackgroundVideo(to: blurBackgroundPhysicalSec(virtualSec: nextSec, currentTrim: currentTrim))
            } else {
                player?.pause()
            }
        } else if nextSec >= outroEndVirtual {
            // Trimmed end region
            if looping {
                nextSec = currentPlayStart
                let physicalStart = startSec + currentTrim.trimStartSec
                player?.seek(to: CMTime(seconds: physicalStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                player?.play()
            } else {
                playing = false
                player?.pause()
                nextSec = outroEndVirtual
            }
        } else {
            // We are in the Main video region
            if let player {
                if player.rate == 0 {
                    player.play()
                }

                let physicalSec = max(currentTrim.trimStartSec, player.currentTime().seconds - startSec)
                nextSec = physicalSec + introDur

                if let hit = findCut(at: physicalSec) {
                    let jumpTo = hit.endSec + 0.02
                    let targetTime = startSec + jumpTo
                    if lastSeekTargetSec == nil || abs(lastSeekTargetSec! - targetTime) > 0.05 {
                        lastSeekTargetSec = targetTime
                        player.seek(to: CMTime(seconds: targetTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                    nextSec = jumpTo + introDur
                } else {
                    lastSeekTargetSec = nil
                }

                if nextSec >= activeVideoEndVirtual {
                    nextSec = activeVideoEndVirtual
                    player.pause()
                }
            }
        }

        // Audio volume fading based on active intro/outro transitions
        let introActive = introDur > 0
        let outroActive = outroDur > 0
        var mainVideoVolume: Double = 1.0
        let introFadeSec = introActive ? (currentIntro?.transitionSec ?? 1.0) : 1.0
        let outroFadeSec = outroActive ? (currentOutro?.transitionSec ?? 1.0) : 1.0

        if introActive && nextSec >= currentTrim.trimStartSec && nextSec < activeVideoStartVirtual {
            mainVideoVolume = 0.0
        } else if outroActive && nextSec >= activeVideoEndVirtual && nextSec < outroEndVirtual {
            mainVideoVolume = 0.0
        } else {
            if introActive && introFadeSec > 0 && nextSec >= activeVideoStartVirtual && nextSec <= activeVideoStartVirtual + introFadeSec {
                mainVideoVolume = (nextSec - activeVideoStartVirtual) / introFadeSec
            }
            if outroActive && outroFadeSec > 0 && nextSec >= activeVideoEndVirtual - outroFadeSec && nextSec <= activeVideoEndVirtual {
                mainVideoVolume = min(mainVideoVolume, (activeVideoEndVirtual - nextSec) / outroFadeSec)
            }
        }
        player?.volume = Float(max(0.0, min(1.0, mainVideoVolume)))

        if playing {
            updateFrameStateToInterpolated(at: nextSec)
        }
        currentSec = min(max(0, nextSec), virtualDuration)
        updateExtraAudioPlayback(syncToTimeline: false)

    }

    private func togglePlayback() {
        playing ? pause() : play()
    }

    private func play() {
        playing = true
        seek(to: currentSec >= virtualDuration ? 0 : currentSec, autoplay: true)
    }

    private func pause() {
        playing = false
        player?.pause()
        updateExtraAudioPlayback()
    }

    private func seek(to virtualSec: Double, autoplay: Bool) {
        let safeV = min(max(0, virtualSec), virtualDuration)
        let wantsMutedBackground = shouldPlayMutedBackgroundVideo(at: safeV)
        let physicalSec = wantsMutedBackground
            ? blurBackgroundPhysicalSec(virtualSec: safeV, currentTrim: timelineTrim)
            : mapVirtualToPhysical(virtualSec: safeV, currentTrim: timelineTrim)
        var adjustedPhysicalSec = physicalSec
        if !wantsMutedBackground, let hit = findCut(at: physicalSec) {
            adjustedPhysicalSec = hit.endSec
        }
        let adjustedVirtualSec = wantsMutedBackground
            ? safeV
            : mapPhysicalToVirtual(physicalSec: adjustedPhysicalSec, currentTrim: timelineTrim)
        currentSec = min(max(0, adjustedVirtualSec), virtualDuration)
        updateFrameStateToInterpolated(at: currentSec)

        lastSeekTargetSec = startSec + adjustedPhysicalSec
        player?.seek(to: CMTime(seconds: startSec + adjustedPhysicalSec, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)

        if autoplay {
            let currentTrim = timelineTrim
            let introDur = introDuration
            let activeVideoStartVirtual = currentTrim.trimStartSec + introDur
            let activeVideoEndVirtual = activeVideoStartVirtual + activeVideoOutputDuration

            if currentSec >= activeVideoStartVirtual && currentSec < activeVideoEndVirtual {
                player?.play()
            } else if wantsMutedBackground {
                player?.volume = 0
                player?.play()
            } else {
                player?.pause()
            }
        } else {
            player?.pause()
        }
        updateExtraAudioPlayback()
    }

    private func syncMutedBackgroundVideo(to physicalSec: Double) {
        guard let player else { return }
        let targetSec = startSec + min(max(0, physicalSec), clipDuration)
        let currentPlayerSec = player.currentTime().seconds
        if !currentPlayerSec.isFinite || abs(currentPlayerSec - targetSec) > 0.18 {
            player.seek(to: CMTime(seconds: targetSec, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.volume = 0
        if playing, player.rate == 0 {
            player.play()
        }
    }

    private func updateSelectedText(_ text: String) {
        guard let selected = selectedSegment else { return }
        recordUndo()
        updateSegments { segments in
            segments = segments.map { segment in
                guard segment.id == selected.id else { return segment }
                let base = AlignedSubtitleSegment(id: segment.id, start: segment.start, end: segment.end, text: text)
                return AlignedSubtitleSegment(id: segment.id, start: segment.start, end: segment.end, text: text, words: ShortsVisualEditorStateBuilder.inferredWords(for: base))
            }
        }
    }

    private func updateSelectedTextOverlay(text: String) {
        guard let selectedTextBlock else { return }
        recordUndo()
        updateTextTrack(id: selectedTextBlock.trackID) { track in
            track.blocks = track.blocks.map { block in
                guard block.id == selectedTextBlock.blockID else { return block }
                var updated = block
                updated.text = text
                return updated
            }
        }
    }

    private func normalizedWords(_ text: String) -> [String] {
        text.split { $0.isWhitespace || $0.isNewline }.map(String.init)
    }

    private func boundedPlayheadPhysicalSec() -> Double {
        let physical = mapVirtualToPhysical(virtualSec: currentSec, currentTrim: timelineTrim)
        return min(max(0, physical), clipDuration)
    }

    private func mergeGapIsClose(selectedEnd: Double, nextStart: Double) -> Bool {
        let gap = nextStart - selectedEnd
        return gap >= -timelineMergeGapToleranceSec && gap <= timelineMergeGapToleranceSec
    }

    private func canMergeNextSegment() -> Bool {
        guard let selected = selectedSegment else { return false }
        let ordered = currentSegments.sorted { lhs, rhs in
            if lhs.start == rhs.start { return lhs.end < rhs.end }
            return lhs.start < rhs.start
        }
        guard let index = ordered.firstIndex(where: { $0.id == selected.id }),
              index < ordered.count - 1
        else { return false }
        let next = ordered[index + 1]
        return mergeGapIsClose(selectedEnd: selected.end, nextStart: next.start)
    }

    private func canMergeNextTextOverlay() -> Bool {
        guard let selectedTextBlock,
              let track = currentTextTracks.first(where: { $0.id == selectedTextBlock.trackID }),
              let selected = track.blocks.first(where: { $0.id == selectedTextBlock.blockID }),
              let next = nextTextOverlay(after: selected, in: track)
        else { return false }
        return mergeGapIsClose(selectedEnd: selected.endSec, nextStart: next.startSec)
    }

    private func nextTextOverlay(after selected: TextOverlayBlock, in track: TextOverlayTrack) -> TextOverlayBlock? {
        let ordered = track.blocks.sorted { lhs, rhs in
            if lhs.startSec == rhs.startSec { return lhs.endSec < rhs.endSec }
            return lhs.startSec < rhs.startSec
        }
        guard let index = ordered.firstIndex(where: { $0.id == selected.id }),
              index < ordered.count - 1
        else { return nil }
        return ordered[index + 1]
    }

    private func splitSelectedTimelineBlock() {
        switch timelineSelection {
        case .text:
            splitSelectedTextOverlay()
        case .subtitle:
            splitSelectedSegment()
        case .none:
            break
        }
    }

    private func splitSelectedSegment() {
        guard let selected = selectedSegment,
              let index = currentSegments.firstIndex(where: { $0.id == selected.id })
        else { return }
        let words = normalizedWords(selected.text)
        guard words.count > 1 else { return }
        recordUndo()
        let pivot = max(1, words.count / 2)
        let mid = selected.start + ((selected.end - selected.start) * Double(pivot) / Double(words.count))
        let firstBase = AlignedSubtitleSegment(id: "\(selected.id)_a", start: selected.start, end: mid, text: words[..<pivot].joined(separator: " "))
        let secondBase = AlignedSubtitleSegment(id: "\(selected.id)_b", start: mid, end: selected.end, text: words[pivot...].joined(separator: " "))
        let first = AlignedSubtitleSegment(id: firstBase.id, start: firstBase.start, end: firstBase.end, text: firstBase.text, words: ShortsVisualEditorStateBuilder.inferredWords(for: firstBase))
        let second = AlignedSubtitleSegment(id: secondBase.id, start: secondBase.start, end: secondBase.end, text: secondBase.text, words: ShortsVisualEditorStateBuilder.inferredWords(for: secondBase))
        updateSegments { segments in
            segments.replaceSubrange(index...index, with: [first, second])
        }
        selectedSegmentID = first.id
    }

    private func splitSelectedTextOverlay() {
        guard let selectedTextBlock,
              let trackIndex = currentTextTracks.firstIndex(where: { $0.id == selectedTextBlock.trackID }),
              let blockIndex = currentTextTracks[trackIndex].blocks.firstIndex(where: { $0.id == selectedTextBlock.blockID })
        else { return }
        let selected = currentTextTracks[trackIndex].blocks[blockIndex]
        let words = normalizedWords(selected.text)
        guard words.count > 1 else { return }
        recordUndo()
        let pivot = max(1, words.count / 2)
        let mid = selected.startSec + ((selected.endSec - selected.startSec) * Double(pivot) / Double(words.count))
        var first = selected
        first.id = "\(selected.id)_a"
        first.endSec = mid
        first.text = words[..<pivot].joined(separator: " ")
        var second = selected
        second.id = "\(selected.id)_b"
        second.startSec = mid
        second.text = words[pivot...].joined(separator: " ")
        updateTextTrack(id: selectedTextBlock.trackID) { track in
            track.blocks.replaceSubrange(blockIndex...blockIndex, with: [first, second])
        }
        selectTextTimelineBlock(trackID: selectedTextBlock.trackID, blockID: first.id)
    }

    private func addSubtitleBlock() {
        recordUndo()
        let playheadStart = boundedPlayheadPhysicalSec()
        let start = min(playheadStart, max(0, clipDuration - 0.25))
        let end = min(clipDuration, start + 2)
        let base = AlignedSubtitleSegment(id: "sub_new_\(Int(Date().timeIntervalSince1970))", start: start, end: max(start + 0.25, end), text: "")
        updateSegments { segments in
            segments.append(base)
            segments.sort { $0.start < $1.start }
        }
        selectSubtitleTimelineBlock(base.id)
    }

    private func mergeNextTimelineBlock() {
        switch timelineSelection {
        case .text:
            mergeNextTextOverlay()
        case .subtitle:
            mergeNextSegment()
        case .none:
            break
        }
    }

    private func mergeNextSegment() {
        guard let selected = selectedSegment
        else { return }
        let ordered = currentSegments.sorted { lhs, rhs in
            if lhs.start == rhs.start { return lhs.end < rhs.end }
            return lhs.start < rhs.start
        }
        guard let index = ordered.firstIndex(where: { $0.id == selected.id }),
              index < ordered.count - 1
        else { return }
        let next = ordered[index + 1]
        guard mergeGapIsClose(selectedEnd: selected.end, nextStart: next.start) else { return }
        recordUndo()
        updateSegments { segments in
            let base = AlignedSubtitleSegment(
                id: selected.id,
                start: selected.start,
                end: next.end,
                text: "\(selected.text) \(next.text)".replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            )
            let merged = AlignedSubtitleSegment(id: base.id, start: base.start, end: base.end, text: base.text, words: ShortsVisualEditorStateBuilder.inferredWords(for: base))
            segments.removeAll { $0.id == selected.id || $0.id == next.id }
            segments.append(merged)
            segments.sort { $0.start < $1.start }
        }
    }

    private func mergeNextTextOverlay() {
        guard let selectedTextBlock,
              let track = currentTextTracks.first(where: { $0.id == selectedTextBlock.trackID }),
              let selected = track.blocks.first(where: { $0.id == selectedTextBlock.blockID }),
              let next = nextTextOverlay(after: selected, in: track)
        else { return }
        guard mergeGapIsClose(selectedEnd: selected.endSec, nextStart: next.startSec) else { return }
        recordUndo()
        updateTextTrack(id: selectedTextBlock.trackID) { track in
            var merged = selected
            merged.endSec = max(selected.endSec, next.endSec)
            merged.text = "\(selected.text) \(next.text)".replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            track.blocks.removeAll { $0.id == selected.id || $0.id == next.id }
            track.blocks.append(merged)
            track.blocks.sort { $0.startSec < $1.startSec }
        }
    }

    private func deleteSelectedTimelineBlock() {
        switch timelineSelection {
        case .text:
            deleteSelectedTextOverlay()
        case .subtitle:
            deleteSelectedSegment()
        case .none:
            break
        }
    }

    private func deleteSelectedSegment() {
        guard let selected = selectedSegment else { return }
        recordUndo()
        updateSegments { segments in
            segments.removeAll { $0.id == selected.id }
        }
        selectSubtitleTimelineBlock(currentSegments.first?.id ?? "")
    }

    private func deleteSelectedTextOverlay() {
        guard let selected = selectedTextBlock else { return }
        recordUndo()
        updateTextTrack(id: selected.trackID) { track in
            track.blocks.removeAll { $0.id == selected.blockID }
        }
        self.selectedTextBlock = nil
    }

    private func deleteCut(at index: Int) {
        recordUndo()
        timelineCuts.remove(at: index)
    }

    private func moveWord(index: Int, direction: Int) {
        guard let selected = selectedSegment,
              let segmentIndex = currentSegments.firstIndex(where: { $0.id == selected.id })
        else { return }
        let targetIndex = segmentIndex + direction
        guard targetIndex >= 0, targetIndex < currentSegments.count else { return }
        recordUndo()
        updateSegments { segments in
            var sourceWords = segments[segmentIndex].text.split { $0.isWhitespace }.map(String.init)
            guard sourceWords.indices.contains(index) else { return }
            let word = sourceWords.remove(at: index)
            var targetWords = segments[targetIndex].text.split { $0.isWhitespace }.map(String.init)
            if direction < 0 {
                targetWords.append(word)
            } else {
                targetWords.insert(word, at: 0)
            }
            let sourceBase = AlignedSubtitleSegment(id: segments[segmentIndex].id, start: segments[segmentIndex].start, end: segments[segmentIndex].end, text: sourceWords.joined(separator: " "))
            let targetBase = AlignedSubtitleSegment(id: segments[targetIndex].id, start: segments[targetIndex].start, end: segments[targetIndex].end, text: targetWords.joined(separator: " "))
            segments[segmentIndex] = AlignedSubtitleSegment(id: sourceBase.id, start: sourceBase.start, end: sourceBase.end, text: sourceBase.text, words: ShortsVisualEditorStateBuilder.inferredWords(for: sourceBase))
            segments[targetIndex] = AlignedSubtitleSegment(id: targetBase.id, start: targetBase.start, end: targetBase.end, text: targetBase.text, words: ShortsVisualEditorStateBuilder.inferredWords(for: targetBase))
        }
    }

    private func updateSegments(_ mutate: (inout [AlignedSubtitleSegment]) -> Void) {
        if language == .source {
            mutate(&sourceSegments)
            sourceSegments = ShortsVisualEditorStateBuilder.normalized(sourceSegments, duration: clipDuration)
            if syncEnabled {
                targetSegments = mirrorTiming(from: sourceSegments, to: targetSegments)
            }
        } else {
            mutate(&targetSegments)
            targetSegments = ShortsVisualEditorStateBuilder.normalized(targetSegments, duration: clipDuration)
            if syncEnabled {
                sourceSegments = mirrorTiming(from: targetSegments, to: sourceSegments)
            }
        }
    }

    private func updateSegmentTimes(id: String, start: Double, end: Double) {
        updateSegments { segments in
            if let idx = segments.firstIndex(where: { $0.id == id }) {
                let seg = segments[idx]
                let base = AlignedSubtitleSegment(id: seg.id, start: start, end: end, text: seg.text)
                segments[idx] = AlignedSubtitleSegment(id: seg.id, start: start, end: end, text: seg.text, words: ShortsVisualEditorStateBuilder.inferredWords(for: base))
            }
        }
    }

    private func setCurrentLogo(_ logo: LogoOverlaySettings?) {
        recordUndo()
        if language == .source {
            sourceLogo = logo
            if syncEnabled { targetLogo = logo }
        } else {
            targetLogo = logo
            if syncEnabled { sourceLogo = logo }
        }
    }

    private func updateCurrentLogo(_ mutate: (inout LogoOverlaySettings) -> Void) {
        guard var logo = currentLogo else { return }
        mutate(&logo)
        setCurrentLogo(logo)
    }

    private func setCurrentIntroOutro(_ item: IntroOutroOverlaySettings?, type: IntroOutroLayerType) {
        recordUndo()
        if language == .source {
            if type == .intro { sourceIntro = item } else { sourceOutro = item }
            if syncEnabled {
                if type == .intro { targetIntro = item } else { targetOutro = item }
            }
        } else {
            if type == .intro { targetIntro = item } else { targetOutro = item }
            if syncEnabled {
                if type == .intro { sourceIntro = item } else { sourceOutro = item }
            }
        }
    }

    private func updateCurrentIntroOutro(_ type: IntroOutroLayerType, mutate: (inout IntroOutroOverlaySettings) -> Void) {
        guard var item = type == .intro ? currentIntro : currentOutro else { return }
        mutate(&item)
        setCurrentIntroOutro(item, type: type)
    }

    private func setCurrentTextTracks(_ tracks: [TextOverlayTrack]) {
        recordUndo()
        if language == .source {
            sourceTextTracks = tracks
            if syncEnabled { targetTextTracks = tracks }
        } else {
            targetTextTracks = tracks
            if syncEnabled { sourceTextTracks = tracks }
        }
    }

    private func setCurrentAudioTracks(_ tracks: [ExtraAudioTrack]) {
        recordUndo()
        if language == .source {
            sourceAudioTracks = tracks
            if syncEnabled { targetAudioTracks = tracks }
        } else {
            targetAudioTracks = tracks
            if syncEnabled { sourceAudioTracks = tracks }
        }
    }

    private func mirrorCurrentVisualStateToOtherLanguage() {
        recordUndo()
        if language == .source {
            targetSegments = mirrorTiming(from: sourceSegments, to: targetSegments)
            targetFrameKeyframes = sourceFrameKeyframes
            targetLogo = sourceLogo
            targetTextTracks = sourceTextTracks
            targetAudioTracks = sourceAudioTracks
            targetIntro = sourceIntro
            targetOutro = sourceOutro
        } else {
            sourceSegments = mirrorTiming(from: targetSegments, to: sourceSegments)
            sourceFrameKeyframes = targetFrameKeyframes
            sourceLogo = targetLogo
            sourceTextTracks = targetTextTracks
            sourceAudioTracks = targetAudioTracks
            sourceIntro = targetIntro
            sourceOutro = targetOutro
        }
    }

    private func addTextTrack() {
        guard currentTextTracks.count < 3 else { return }
        var tracks = currentTextTracks
        tracks.append(TextOverlayTrack(
            id: "text_track_\(Int(Date().timeIntervalSince1970 * 1000))_\(tracks.count)",
            name: "Text Track \(tracks.count + 1)",
            blocks: [],
            style: defaultTextTrackStyle(trackIndex: tracks.count)
        ))
        setCurrentTextTracks(tracks)
    }

    private func addTextOverlayBlock() {
        var tracks = currentTextTracks
        if tracks.isEmpty {
            tracks.append(TextOverlayTrack(id: "text_track_\(Int(Date().timeIntervalSince1970 * 1000))_0", name: "Text Track 1", blocks: []))
            tracks[0].style = defaultTextTrackStyle(trackIndex: 0)
        }
        let start = min(boundedPlayheadPhysicalSec(), max(0, clipDuration - 1))
        let block = TextOverlayBlock(
            id: "text_block_\(Int(Date().timeIntervalSince1970 * 1000))",
            startSec: start,
            endSec: min(clipDuration, start + 3),
            text: ""
        )
        let targetTrackIndex = selectedTextBlock.flatMap { selected in
            tracks.firstIndex(where: { $0.id == selected.trackID })
        } ?? 0
        tracks[targetTrackIndex].style = tracks[targetTrackIndex].style ?? defaultTextTrackStyle(trackIndex: targetTrackIndex)
        tracks[targetTrackIndex].blocks.append(block)
        tracks[targetTrackIndex].blocks.sort { $0.startSec < $1.startSec }
        setCurrentTextTracks(tracks)
        selectTextTimelineBlock(trackID: tracks[targetTrackIndex].id, blockID: block.id)
    }

    private func trackName(_ id: String) -> String {
        currentTextTracks.first(where: { $0.id == id })?.name ?? ""
    }

    private func updateTextTrack(id: String, mutate: (inout TextOverlayTrack) -> Void) {
        var tracks = currentTextTracks
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tracks[index])
        setCurrentTextTracks(tracks)
    }

    private func updateTextBlockTimes(trackID: String, blockID: String, start: Double, end: Double) {
        updateTextTrack(id: trackID) { track in
            if let idx = track.blocks.firstIndex(where: { $0.id == blockID }) {
                track.blocks[idx].startSec = start
                track.blocks[idx].endSec = end
            }
        }
    }

    private func removeTextTrack(id: String) {
        setCurrentTextTracks(currentTextTracks.filter { $0.id != id })
        if selectedTextBlock?.trackID == id {
            selectedTextBlock = nil
        }
    }

    private func audioTrack(_ id: String) -> ExtraAudioTrack? {
        currentAudioTracks.first { $0.id == id }
    }

    private func updateAudioTrack(id: String, syncPlayback: Bool = true, mutate: (inout ExtraAudioTrack) -> Void) {
        var tracks = currentAudioTracks
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tracks[index])
        setCurrentAudioTracks(tracks)
        if syncPlayback {
            updateExtraAudioPlayback()
        }
    }

    private func removeAudioTrack(id: String) {
        setCurrentAudioTracks(currentAudioTracks.filter { $0.id != id })
        updateExtraAudioPlayback()
    }

    private func resolveAudioURL(src: String) -> URL? {
        if src.hasPrefix("file://") {
            if let decoded = src.removingPercentEncoding, let url = URL(string: decoded) { return url }
            if let url = URL(string: src) { return url }
        }
        if src.hasPrefix("/") {
            return URL(fileURLWithPath: src)
        }
        return URL(string: src) ?? URL(fileURLWithPath: src)
    }

    private func getOrCreatePlayer(for track: ExtraAudioTrack) -> AVPlayer {
        if let existing = extraAudioPlayers[track.id] {
            return existing
        }
        guard let url = resolveAudioURL(src: track.src) else {
            let dummy = AVPlayer()
            extraAudioPlayers[track.id] = dummy
            return dummy
        }
        let player = AVPlayer(url: url)
        extraAudioPlayers[track.id] = player
        return player
    }

    private func updateExtraAudioPlayback(syncToTimeline: Bool = true) {
        for track in currentAudioTracks {
            let isMuted = track.muted == true
            let player = getOrCreatePlayer(for: track)

            let assetDuration = player.currentItem?.asset.duration.seconds ?? 0
            let trimStart = track.trimStartSec
            let trimEnd = track.trimEndSec > 0 ? (assetDuration - track.trimEndSec) : assetDuration
            let trackPlayableDuration = max(0.1, trimEnd - trimStart)

            let physicalSec = mapVirtualToPhysical(virtualSec: currentSec, currentTrim: timelineTrim)
            let collapsedV = TimelineCutTimeMapper.mapPhysicalToVirtual(
                physicalSec: physicalSec,
                clipDuration: clipDuration,
                trim: timelineTrim,
                cuts: timelineCuts,
                introDuration: introDuration,
                outroDuration: outroDuration
            )
            let collapsedStart = TimelineCutTimeMapper.mapPhysicalToVirtual(
                physicalSec: track.startSec,
                clipDuration: clipDuration,
                trim: timelineTrim,
                cuts: timelineCuts,
                introDuration: introDuration,
                outroDuration: outroDuration
            )

            let elapsed = collapsedV - collapsedStart
            let isWithinRange = elapsed >= 0 && elapsed < trackPlayableDuration

            if playing && isWithinRange && !isMuted {
                var targetVolume = track.volume
                let remaining = trackPlayableDuration - elapsed

                if track.fadeInSec > 0 && elapsed < track.fadeInSec {
                    targetVolume *= (elapsed / track.fadeInSec)
                } else if track.fadeOutSec > 0 && remaining < track.fadeOutSec {
                    targetVolume *= (remaining / track.fadeOutSec)
                }
                player.volume = Float(targetVolume)

                let desiredPlaybackTime = trimStart + elapsed
                let currentPlayerTime = player.currentTime().seconds

                let shouldResyncExtraAudio = syncToTimeline || player.rate == 0
                if shouldResyncExtraAudio && abs(currentPlayerTime - desiredPlaybackTime) > 0.15 {
                    player.seek(to: CMTime(seconds: desiredPlaybackTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }

                if player.rate == 0 {
                    player.play()
                }
            } else {
                player.pause()
            }
        }

        let activeIds = Set(currentAudioTracks.map { $0.id })
        for (id, player) in extraAudioPlayers {
            if !activeIds.contains(id) {
                player.pause()
            }
        }
    }

    private func stopAllExtraAudio() {
        for player in extraAudioPlayers.values {
            player.pause()
        }
        extraAudioPlayers.removeAll()
    }

    private func importLogo() {
        guard let url = chooseFile(allowedExtensions: ["png", "svg", "webp"]) else { return }
        guard let source = dataURL(for: url) else { return }
        let existing = currentLogo
        setCurrentLogo(LogoOverlaySettings(
            id: existing?.id ?? "logo_\(Int(Date().timeIntervalSince1970 * 1000))",
            src: source,
            name: url.lastPathComponent,
            size: existing?.size ?? 1,
            opacity: existing?.opacity ?? 1,
            position: existing?.position ?? "top-left",
            hidden: false
        ))
    }

    private func importIntroOutro(_ type: IntroOutroLayerType) {
        guard let url = chooseFile(allowedExtensions: ["png", "svg", "webp"]) else { return }
        guard let source = dataURL(for: url) else { return }
        let existing = type == .intro ? currentIntro : currentOutro
        setCurrentIntroOutro(IntroOutroOverlaySettings(
            id: existing?.id ?? "\(type.rawValue)_\(Int(Date().timeIntervalSince1970 * 1000))",
            src: source,
            name: url.lastPathComponent,
            duration: existing?.duration ?? 3,
            x: existing?.x ?? 50,
            y: existing?.y ?? 50,
            scale: existing?.scale ?? 0.5,
            animation: existing?.animation ?? "fade",
            hidden: false,
            speed: existing?.speed ?? 1,
            transitionSec: existing?.transitionSec ?? 1
        ), type: type)
    }

    private func importAudioTrack() {
        guard currentAudioTracks.count < 3 else { return }
        guard let url = chooseFile(allowedExtensions: ["mp3", "mpeg", "wav", "m4a", "aac"]) else { return }
        var tracks = currentAudioTracks
        tracks.append(ExtraAudioTrack(
            id: "audio_track_\(Int(Date().timeIntervalSince1970 * 1000))_\(tracks.count)",
            name: url.lastPathComponent,
            src: url.absoluteString,
            previewSrc: url.absoluteString,
            startSec: 0,
            trimStartSec: 0,
            trimEndSec: 0,
            volume: 0.5,
            fadeInSec: 0,
            fadeOutSec: 0,
            muted: false
        ))
        setCurrentAudioTracks(tracks)
    }

    private func chooseFile(allowedExtensions: [String]) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func dataURL(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = url.pathExtension.lowercased()
        let mime: String
        switch ext {
        case "svg":
            mime = "image/svg+xml"
        case "webp":
            mime = "image/webp"
        default:
            mime = "image/png"
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private func mirrorTiming(from source: [AlignedSubtitleSegment], to target: [AlignedSubtitleSegment]) -> [AlignedSubtitleSegment] {
        guard !target.isEmpty else { return target }
        return source.enumerated().map { index, sourceSegment in
            let targetSegment = target.indices.contains(index) ? target[index] : target[target.count - 1]
            let base = AlignedSubtitleSegment(id: targetSegment.id, start: sourceSegment.start, end: sourceSegment.end, text: targetSegment.text)
            return AlignedSubtitleSegment(id: targetSegment.id, start: sourceSegment.start, end: sourceSegment.end, text: targetSegment.text, words: ShortsVisualEditorStateBuilder.inferredWords(for: base))
        }
    }

    private func materializeCurrentKeyframe() {
        recordUndo()
        let physicalSec = mapVirtualToPhysical(virtualSec: currentSec, currentTrim: timelineTrim)
        let point = FrameKeyframe(
            id: "frame_\(Int(Date().timeIntervalSince1970 * 1000))",
            time: physicalSec,
            x: framePanX,
            y: framePanY,
            zoom: frameZoom,
            backgroundColor: backgroundSettings.solidColor
        )
        if language == .source {
            sourceFrameKeyframes = replacingKeyframe(point, in: sourceFrameKeyframes)
            if syncEnabled { targetFrameKeyframes = sourceFrameKeyframes }
        } else {
            targetFrameKeyframes = replacingKeyframe(point, in: targetFrameKeyframes)
            if syncEnabled { sourceFrameKeyframes = targetFrameKeyframes }
        }
    }

    private func saveCurrentFrameState() {
        materializeCurrentKeyframe()
    }

    private func updateFrameStateToInterpolated(at time: Double) {
        let kfs = currentFrameKeyframes
        guard !kfs.isEmpty else { return }
        let physicalSec = mapVirtualToPhysical(virtualSec: time, currentTrim: timelineTrim)
        let state = NativeShortsRenderPlanBuilder.interpolateFrameState(kfs, timeSec: physicalSec)
        frameZoom = state.zoom
        framePanX = state.x
        framePanY = state.y
    }

    private func replacingKeyframe(_ point: FrameKeyframe, in keyframes: [FrameKeyframe]) -> [FrameKeyframe] {
        let filtered = keyframes.filter { abs($0.time - point.time) > 0.15 }
        return (filtered + [point]).sorted { $0.time < $1.time }
    }

    private func clearKeyframes() {
        recordUndo()
        if language == .source {
            sourceFrameKeyframes = []
            if syncEnabled { targetFrameKeyframes = [] }
        } else {
            targetFrameKeyframes = []
            if syncEnabled { sourceFrameKeyframes = [] }
        }
    }

    // MARK: - Cut Range Engine

    private func handleTrackClickOrScrub(virtualSec: Double) {
        seek(to: virtualSec, autoplay: playing)
    }

    private func beginCutRangeDrag(virtualSec: Double) {
        let physicalSec = boundedSourcePhysicalSec(for: virtualSec)
        cutRangeStartSec = physicalSec
        cutRangePreviewEndSec = physicalSec
        AppLogger.shared.info("VisualEditor CutRange drag begin virtualSec=\(virtualSec) physicalSec=\(physicalSec)")
    }

    private func updateCutRangeDrag(virtualSec: Double) {
        let physicalSec = boundedSourcePhysicalSec(for: virtualSec)
        if cutRangeStartSec == nil {
            cutRangeStartSec = physicalSec
        }
        cutRangePreviewEndSec = physicalSec
    }

    private func finishCutRangeDrag(virtualSec: Double, wasDragged: Bool) {
        let physicalSec = boundedSourcePhysicalSec(for: virtualSec)
        cutRangePreviewEndSec = physicalSec

        guard wasDragged else {
            cancelCutRangeDrag()
            return
        }

        guard let startSec = cutRangeStartSec else {
            cancelCutRangeDrag()
            return
        }

        commitCutRange(startSec: min(startSec, physicalSec), endSec: max(startSec, physicalSec))
    }

    private func cancelCutRangeDrag() {
        cutRangeStartSec = nil
        cutRangePreviewEndSec = nil
    }

    private func boundedSourcePhysicalSec(for virtualSec: Double) -> Double {
        let physicalSec = mapVirtualToPhysical(virtualSec: virtualSec, currentTrim: timelineTrim)
        return min(max(0, physicalSec), clipDuration)
    }

    private func commitCutRange(startSec: Double, endSec: Double) {
        if endSec <= startSec + 0.1 {
            cutRangeStartSec = nil
            cutRangePreviewEndSec = nil
            AppLogger.shared.warn("VisualEditor CutRange ignored tiny cut startSec=\(startSec) endSec=\(endSec)")
            return
        }
        let newCut = TimelineCut(startSec: startSec, endSec: endSec)
        let nextCuts = addCut(timelineCuts, newCut: newCut, clipDuration: clipDuration)

        if nextCuts == timelineCuts {
            cutRangeActive = false
            cutRangeStartSec = nil
            cutRangePreviewEndSec = nil
            AppLogger.shared.info("VisualEditor CutRange ignored already-cut range physicalStartSec=\(startSec) physicalEndSec=\(endSec)")
            return
        }

        recordUndo()

        timelineCuts = nextCuts
        cutRangeActive = false
        cutRangeStartSec = nil
        cutRangePreviewEndSec = nil
        AppLogger.shared.info("VisualEditor CutRange committed physicalStartSec=\(startSec) physicalEndSec=\(endSec) cuts=\(nextCuts.map { "\($0.startSec)-\($0.endSec)" }.joined(separator: ","))")

        updateExtraAudioPlayback()
    }

    private func updateCut(index: Int, cut: TimelineCut) {
        guard timelineCuts.indices.contains(index) else { return }
        let normalized = TimelineCut(
            startSec: min(max(0, cut.startSec), clipDuration),
            endSec: min(max(0, cut.endSec), clipDuration)
        )
        guard normalized.endSec > normalized.startSec + 0.1 else { return }

        var nextCuts = timelineCuts
        nextCuts.remove(at: index)
        timelineCuts = addCut(nextCuts, newCut: normalized, clipDuration: clipDuration)
        AppLogger.shared.info("VisualEditor CutRange updated index=\(index) physicalStartSec=\(normalized.startSec) physicalEndSec=\(normalized.endSec)")
        updateExtraAudioPlayback()
    }

    private func addCut(_ cuts: [TimelineCut], newCut: TimelineCut, clipDuration: Double) -> [TimelineCut] {
        let cut = TimelineCut(
            startSec: max(0, newCut.startSec),
            endSec: min(clipDuration, newCut.endSec)
        )
        if cut.endSec <= cut.startSec { return cuts }

        var all = cuts
        all.append(cut)
        all.sort { $0.startSec < $1.startSec }

        var merged: [TimelineCut] = []
        for item in all {
            if let last = merged.last {
                if item.startSec <= last.endSec + 0.01 {
                    var updatedLast = last
                    updatedLast.endSec = max(last.endSec, item.endSec)
                    merged[merged.count - 1] = updatedLast
                } else {
                    merged.append(item)
                }
            } else {
                merged.append(item)
            }
        }
        return merged
    }

    private func installKeyboardMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard shouldHandleVisualEditorShortcut(event) else { return event }
            let isCmd = event.modifierFlags.contains(.command)
            let isShift = event.modifierFlags.contains(.shift)

            // Space: Play/Pause
            if event.keyCode == 49 {
                guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
                togglePlayback()
                return nil
            }
            // Escape: Cancel/Close
            if event.keyCode == 53 {
                onCancel()
                return nil
            }
            // Cmd+Z / Cmd+Shift+Z: Undo/Redo
            if isCmd && event.keyCode == 6 {
                if isShift {
                    redoEdit()
                } else {
                    undoEdit()
                }
                return nil
            }
            // Backspace/Delete: Delete cut under playhead
            if event.keyCode == 51 || event.keyCode == 117 {
                let physicalSec = mapVirtualToPhysical(virtualSec: currentSec, currentTrim: timelineTrim)
                if let cutIndex = timelineCuts.firstIndex(where: { physicalSec >= $0.startSec && physicalSec <= $0.endSec }) {
                    deleteCut(at: cutIndex)
                    return nil
                }
            }
            // Left arrow (keyCode 123): step back 0.08s
            if event.keyCode == 123 {
                seek(to: max(0, currentSec - 0.08), autoplay: playing)
                return nil
            }
            // Right arrow (keyCode 124): step forward 0.08s
            if event.keyCode == 124 {
                seek(to: min(virtualDuration, currentSec + 0.08), autoplay: playing)
                return nil
            }
            return event
        }
    }

    private func recordUndo() {
        guard !restoringSnapshot else { return }
        let snapshot = makeSnapshot()
        if undoStack.last == snapshot { return }
        undoStack.append(snapshot)
        if undoStack.count > 80 {
            undoStack.removeFirst(undoStack.count - 80)
        }
        redoStack.removeAll()
    }

    private func undoEdit() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(makeSnapshot())
        restore(snapshot)
    }

    private func redoEdit() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(makeSnapshot())
        restore(snapshot)
    }

    private func makeSnapshot() -> EditorSnapshot {
        EditorSnapshot(
            language: language,
            sourceSegments: sourceSegments,
            targetSegments: targetSegments,
            sourceFrameKeyframes: sourceFrameKeyframes,
            targetFrameKeyframes: targetFrameKeyframes,
            startSec: startSec,
            endSec: endSec,
            title: title,
            category: category,
            summary: summary,
            hook: hook,
            captionText: captionText,
            style: style,
            backgroundSettings: backgroundSettings,
            timelineCuts: timelineCuts,
            timelineTrim: timelineTrim,
            sourceLogo: sourceLogo,
            targetLogo: targetLogo,
            sourceTextTracks: sourceTextTracks,
            targetTextTracks: targetTextTracks,
            sourceAudioTracks: sourceAudioTracks,
            targetAudioTracks: targetAudioTracks,
            sourceIntro: sourceIntro,
            targetIntro: targetIntro,
            sourceOutro: sourceOutro,
            targetOutro: targetOutro,
            selectedSegmentID: selectedSegmentID,
            selectedTextTrackID: selectedTextBlock?.trackID,
            selectedTextBlockID: selectedTextBlock?.blockID,
            syncEnabled: syncEnabled,
            frameZoom: frameZoom,
            framePanX: framePanX,
            framePanY: framePanY
        )
    }

    private func restore(_ snapshot: EditorSnapshot) {
        restoringSnapshot = true
        language = snapshot.language
        sourceSegments = snapshot.sourceSegments
        targetSegments = snapshot.targetSegments
        sourceFrameKeyframes = snapshot.sourceFrameKeyframes
        targetFrameKeyframes = snapshot.targetFrameKeyframes
        startSec = snapshot.startSec
        endSec = snapshot.endSec
        title = snapshot.title
        category = snapshot.category
        summary = snapshot.summary
        hook = snapshot.hook
        captionText = snapshot.captionText
        style = snapshot.style
        backgroundSettings = snapshot.backgroundSettings
        timelineCuts = snapshot.timelineCuts
        timelineTrim = snapshot.timelineTrim
        sourceLogo = snapshot.sourceLogo
        targetLogo = snapshot.targetLogo
        sourceTextTracks = snapshot.sourceTextTracks
        targetTextTracks = snapshot.targetTextTracks
        sourceAudioTracks = snapshot.sourceAudioTracks
        targetAudioTracks = snapshot.targetAudioTracks
        sourceIntro = snapshot.sourceIntro
        targetIntro = snapshot.targetIntro
        sourceOutro = snapshot.sourceOutro
        targetOutro = snapshot.targetOutro
        if let trackID = snapshot.selectedTextTrackID, let blockID = snapshot.selectedTextBlockID {
            selectTextTimelineBlock(trackID: trackID, blockID: blockID)
        } else {
            selectSubtitleTimelineBlock(snapshot.selectedSegmentID)
        }
        syncEnabled = snapshot.syncEnabled
        frameZoom = snapshot.frameZoom
        framePanX = snapshot.framePanX
        framePanY = snapshot.framePanY
        restoringSnapshot = false
    }

    private func removeKeyboardMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleSpacebarKeyPress() -> Bool {
        guard !currentFirstResponderIsEditableTextInput() else { return false }
        togglePlayback()
        return true
    }

    private func shouldHandleVisualEditorShortcut(_ event: NSEvent) -> Bool {
        guard let responder = event.window?.firstResponder ?? NSApp.keyWindow?.firstResponder else {
            return true
        }
        return !responderIsEditableTextInput(responder)
    }

    private func currentFirstResponderIsEditableTextInput() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responderIsEditableTextInput(responder)
    }

    private func responderIsEditableTextInput(_ responder: NSResponder) -> Bool {
        if let textView = responder as? NSTextView {
            return textView.isEditable
        }
        if let textField = responder as? NSTextField {
            return textField.isEditable
        }
        return false
    }

    private func clearTextInputFocus() {
        guard currentFirstResponderIsEditableTextInput() else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func waveformValue(_ index: Int) -> CGFloat {
        let value = abs(sin(Double(index) * 0.45)) * 22 + abs(cos(Double(index) * 0.19)) * 18 + 8
        return CGFloat(value)
    }

    private func indexPercent(_ index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        return Double(index) / Double(count - 1)
    }

    private func percent(_ value: Double, _ total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }

    private func transformed(_ text: String, style: ShortsSubtitleStyle? = nil) -> String {
        let style = style ?? self.style
        switch style.textTransform {
        case .none:
            return text
        case .uppercase:
            return text.uppercased()
        case .title:
            return text.capitalized
        }
    }

    private func activeTextOverlayBlocks() -> [ActiveTextOverlayBlock] {
        let physicalPlayhead = currentSec - introDuration
        return currentTextTracks.enumerated().flatMap { (trackIndex, track) -> [ActiveTextOverlayBlock] in
            guard track.hidden != true, track.muted != true else { return [] }
            return track.blocks.compactMap { block in
                guard block.hidden != true,
                      !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      physicalPlayhead >= block.startSec,
                      physicalPlayhead < block.endSec
                else { return nil }
                return ActiveTextOverlayBlock(
                    id: "\(track.id)-\(block.id)",
                    text: block.text,
                    trackIndex: trackIndex,
                    style: block.styleFallback(track.style)
                )
            }
        }
    }

    private func logoAlignment(_ position: String) -> Alignment {
        switch position {
        case "top-right":
            return .topTrailing
        case "bottom-left":
            return .bottomLeading
        case "bottom-right":
            return .bottomTrailing
        default:
            return .topLeading
        }
    }

    private func image(from source: String) -> NSImage? {
        if source.hasPrefix("data:"),
           let comma = source.firstIndex(of: ",") {
            let metadata = String(source[..<comma])
            let payload = String(source[source.index(after: comma)...])
            if metadata.contains(";base64"),
               let data = Data(base64Encoded: payload) {
                return NSImage(data: data)
            }
        }
        if source.hasPrefix("file://"),
           let url = URL(string: source) {
            return NSImage(contentsOf: url)
        }
        return NSImage(contentsOfFile: source)
    }

    private func clock(_ seconds: Double) -> String {
        let safe = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", safe / 60, safe % 60)
    }
}

private struct ActiveTextOverlayBlock: Identifiable {
    let id: String
    let text: String
    let trackIndex: Int
    let style: ShortsSubtitleStyle?
}

private struct EditorSnapshot: Equatable {
    var language: ShortsIdeaDisplayLanguage
    var sourceSegments: [AlignedSubtitleSegment]
    var targetSegments: [AlignedSubtitleSegment]
    var sourceFrameKeyframes: [FrameKeyframe]
    var targetFrameKeyframes: [FrameKeyframe]
    var startSec: Double
    var endSec: Double
    var title: String
    var category: String
    var summary: String
    var hook: String
    var captionText: String
    var style: ShortsSubtitleStyle
    var backgroundSettings: ShortsBackgroundSettings
    var timelineCuts: [TimelineCut]
    var timelineTrim: TimelineTrim
    var sourceLogo: LogoOverlaySettings?
    var targetLogo: LogoOverlaySettings?
    var sourceTextTracks: [TextOverlayTrack]
    var targetTextTracks: [TextOverlayTrack]
    var sourceAudioTracks: [ExtraAudioTrack]
    var targetAudioTracks: [ExtraAudioTrack]
    var sourceIntro: IntroOutroOverlaySettings?
    var targetIntro: IntroOutroOverlaySettings?
    var sourceOutro: IntroOutroOverlaySettings?
    var targetOutro: IntroOutroOverlaySettings?
    var selectedSegmentID: String
    var selectedTextTrackID: String?
    var selectedTextBlockID: String?
    var syncEnabled: Bool
    var frameZoom: Double
    var framePanX: Double
    var framePanY: Double
}

private struct VisualEditorSettingsSnapshot: Codable {
    var createdAt: String
    var clipIndex: Int
    var language: ShortsIdeaDisplayLanguage
    var title: String
    var start: String
    var end: String
    var subtitleStyle: ShortsSubtitleStyle
    var backgroundSettings: ShortsBackgroundSettings
    var timelineCuts: [TimelineCut]
    var timelineTrim: TimelineTrim
    var sourceFrameKeyframes: [FrameKeyframe]
    var targetFrameKeyframes: [FrameKeyframe]
    var sourceLogo: LogoOverlaySettings?
    var targetLogo: LogoOverlaySettings?
    var sourceTextTracks: [TextOverlayTrack]
    var targetTextTracks: [TextOverlayTrack]
    var sourceAudioTracks: [ExtraAudioTrack]
    var targetAudioTracks: [ExtraAudioTrack]
    var sourceIntro: IntroOutroOverlaySettings?
    var targetIntro: IntroOutroOverlaySettings?
    var sourceOutro: IntroOutroOverlaySettings?
    var targetOutro: IntroOutroOverlaySettings?
}

private enum VisualEditorSettingsBackupStore {
    static func capture(_ snapshot: VisualEditorSettingsSnapshot) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            let directory = try backupDirectory()
            let filename = "\(safeFilePart(snapshot.createdAt))_clip-\(snapshot.clipIndex + 1)_\(safeFilePart(snapshot.title)).json"
            try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        } catch {
            AppLogger.shared.warn("Could not write visual editor settings backup: \(error.localizedDescription)")
        }
    }

    private static func backupDirectory() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        let directory = documents
            .appendingPathComponent("VaniScript Projects", isDirectory: true)
            .appendingPathComponent("_visual-settings-backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func safeFilePart(_ value: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = value
            .components(separatedBy: disallowed)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "visual-settings" : String(cleaned.prefix(80))
    }
}

private extension TextOverlayBlock {
    func styleFallback(_ trackStyle: ShortsSubtitleStyle?) -> ShortsSubtitleStyle? {
        trackStyle
    }
}

private enum EditorInspectorTab: String, CaseIterable {
    case style
    case frame
    case background
    case layers

    var systemImage: String {
        switch self {
        case .style: return "paintbrush.fill"
        case .frame: return "crop"
        case .background: return "photo.fill"
        case .layers: return "square.3.layers.3d"
        }
    }

    var tooltip: String {
        switch self {
        case .style: return "Style"
        case .frame: return "Frame"
        case .background: return "Background"
        case .layers: return "Layers"
        }
    }
}

private enum IntroOutroLayerType: String {
    case intro
    case outro
}

private struct EditorTrackRow<Content: View>: View {
    let label: String
    let currentSec: Double
    let duration: Double
    let onSeek: (Double) -> Void
    var onCutRangeBegin: (Double) -> Void = { _ in }
    var onCutRangeUpdate: (Double) -> Void = { _ in }
    var onCutRangeFinish: (Double, Bool) -> Void = { _, _ in }
    var onCutRangeCancel: () -> Void = {}
    var height: CGFloat = 36
    var bgFill: Color = Color.dynamic(light: Color.black.opacity(0.04), dark: Color.white.opacity(0.04))
    var muted: Bool = false
    var cutRangeActive: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 7) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(muted ? VaniScriptTheme.text2.opacity(0.5) : VaniScriptTheme.text2)
                .frame(width: 42, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(muted ? Color.dynamic(light: Color.black.opacity(0.02), dark: Color.white.opacity(0.02)) : bgFill)
                    content
                        .opacity(muted ? 0.55 : 1.0)
                        .allowsHitTesting(!cutRangeActive)
                    Rectangle()
                        .fill(VaniScriptTheme.accent)
                        .frame(width: 2)
                        .offset(x: max(0, min(geometry.size.width - 2, geometry.size.width * CGFloat(percent(currentSec, duration)))))

                    if cutRangeActive {
                        TimelineCutRangeDragSelector(
                            label: label,
                            duration: duration,
                            onBegan: onCutRangeBegin,
                            onChanged: onCutRangeUpdate,
                            onEnded: onCutRangeFinish,
                            onCancelled: onCutRangeCancel
                        )
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !cutRangeActive {
                                let pct = boundedTimelinePercent(value.location.x, width: geometry.size.width)
                                let clickedSec = max(0, min(duration, pct * duration))
                                onSeek(clickedSec)
                            }
                        }
                )
            }
            .frame(height: height)
        }
    }

    private func percent(_ value: Double, _ total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }

    private func boundedTimelinePercent(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, Double(x / width)))
    }
}

private struct TimelineCutRangeDragSelector: NSViewRepresentable {
    let label: String
    let duration: Double
    let onBegan: (Double) -> Void
    let onChanged: (Double) -> Void
    let onEnded: (Double, Bool) -> Void
    let onCancelled: () -> Void

    func makeNSView(context: Context) -> CutRangeDragView {
        let view = CutRangeDragView()
        view.update(
            label: label,
            duration: duration,
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled
        )
        return view
    }

    func updateNSView(_ nsView: CutRangeDragView, context: Context) {
        nsView.update(
            label: label,
            duration: duration,
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled
        )
    }

    final class CutRangeDragView: NSView {
        private var label: String = ""
        private var duration: Double = 0
        private var onBegan: (Double) -> Void = { _ in }
        private var onChanged: (Double) -> Void = { _ in }
        private var onEnded: (Double, Bool) -> Void = { _, _ in }
        private var onCancelled: () -> Void = {}
        private var dragStartX: CGFloat = 0
        private var didDrag = false
        private let minimumDragDistance: CGFloat = 3

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        func update(
            label: String,
            duration: Double,
            onBegan: @escaping (Double) -> Void,
            onChanged: @escaping (Double) -> Void,
            onEnded: @escaping (Double, Bool) -> Void,
            onCancelled: @escaping () -> Void
        ) {
            self.label = label
            self.duration = duration
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onCancelled = onCancelled
        }

        override var acceptsFirstResponder: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let clampedX = clampedLocalX(point.x)
            dragStartX = clampedX
            didDrag = false
            let seconds = secondsAt(clampedX)
            AppLogger.shared.info("VisualEditor CutRange AppKit drag began label=\(label) windowX=\(event.locationInWindow.x) localX=\(point.x) clampedX=\(clampedX) clickedSec=\(seconds) duration=\(duration)")
            onBegan(seconds)
        }

        override func mouseDragged(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let clampedX = clampedLocalX(point.x)
            if abs(clampedX - dragStartX) >= minimumDragDistance {
                didDrag = true
            }
            let seconds = secondsAt(clampedX)
            AppLogger.shared.info("VisualEditor CutRange AppKit drag changed label=\(label) windowX=\(event.locationInWindow.x) localX=\(point.x) clampedX=\(clampedX) clickedSec=\(seconds) duration=\(duration)")
            onChanged(seconds)
        }

        override func mouseUp(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let clampedX = clampedLocalX(point.x)
            let seconds = secondsAt(clampedX)
            AppLogger.shared.info("VisualEditor CutRange AppKit drag ended label=\(label) windowX=\(event.locationInWindow.x) localX=\(point.x) clampedX=\(clampedX) clickedSec=\(seconds) didDrag=\(didDrag) duration=\(duration)")
            if didDrag {
                onEnded(seconds, true)
            } else {
                onCancelled()
                onEnded(seconds, false)
            }
        }

        private func clampedLocalX(_ x: CGFloat) -> CGFloat {
            let width = max(1, bounds.width)
            return min(max(0, x), width)
        }

        private func secondsAt(_ x: CGFloat) -> Double {
            let width = max(1, bounds.width)
            let pct = min(1, max(0, Double(x / width)))
            return max(0, min(duration, pct * duration))
        }
    }
}

private struct CutRangeBadge: View {
    let title: String
    let detail: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                Text(detail)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .opacity(0.72)
            }
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .heavy))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.12))
            .clipShape(Circle())
        }
        .foregroundStyle(Color.white)
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 32)
        .background(Color(hex: "#b91c1c").opacity(0.78))
        .overlay(
            Capsule()
                .stroke(Color(hex: "#ef4444").opacity(0.7), lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

private struct CutRangePreviewOverlay: View {
    let startVirtual: Double
    let endVirtual: Double
    let virtualDuration: Double
    let contentWidth: CGFloat
    let labelWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            if virtualDuration > 0, endVirtual > startVirtual {
                let left = labelWidth + contentWidth * CGFloat(startVirtual / virtualDuration)
                let width = max(2, contentWidth * CGFloat((endVirtual - startVirtual) / virtualDuration))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(hex: "#ef4444").opacity(0.20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(hex: "#ef4444").opacity(0.72), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    )
                    .frame(width: width, height: geometry.size.height)
                    .offset(x: left)
            }
        }
        .allowsHitTesting(false)
    }
}

private enum TimelineTextBlockPalette {
    static let baseFill = Color(red: 120 / 255, green: 83 / 255, blue: 28 / 255).opacity(0.50)
    static let playheadFill = Color(red: 143 / 255, green: 96 / 255, blue: 27 / 255).opacity(0.66)
    static let selectionFill = Color(red: 168 / 255, green: 108 / 255, blue: 24 / 255).opacity(0.78)
    static let baseStroke = VaniScriptTheme.accent.opacity(0.32)
    static let playheadStroke = VaniScriptTheme.accent.opacity(0.68)
    static let selectionStroke = VaniScriptTheme.accent.opacity(0.92)
}

private struct TimelineBlock: View {
    let segment: AlignedSubtitleSegment
    let duration: Double
    let introDuration: Double
    let clipDuration: Double
    let active: Bool
    let selected: Bool
    let onSelect: () -> Void
    let onUpdateTimes: (String, Double, Double) -> Void
    let recordUndo: () -> Void

    @State private var initialStart: Double = 0.0
    @State private var initialEnd: Double = 0.0
    @State private var hasRecordedUndo = false

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            let secondsPerPixel = duration / Double(max(1, trackWidth))
            let blockWidth = max(18, trackWidth * CGFloat(percent(segment.end - segment.start, duration)))
            let blockOffset = trackWidth * CGFloat(percent(segment.start + introDuration, duration))
            let playheadHighlighted = active && !selected

            ZStack {
                // Background and text
                Text(segment.text.isEmpty ? "..." : segment.text)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(VaniScriptTheme.text0)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        selected
                            ? TimelineTextBlockPalette.selectionFill
                            : playheadHighlighted
                                ? TimelineTextBlockPalette.playheadFill
                                : TimelineTextBlockPalette.baseFill
                    )
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? TimelineTextBlockPalette.selectionStroke : (playheadHighlighted ? TimelineTextBlockPalette.playheadStroke : TimelineTextBlockPalette.baseStroke), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .gesture(
                        DragGesture(coordinateSpace: .named("timeline"))
                            .onChanged { value in
                                if !hasRecordedUndo {
                                    recordUndo()
                                    hasRecordedUndo = true
                                    initialStart = segment.start
                                    initialEnd = segment.end
                                    onSelect()
                                }
                                let dx = value.translation.width
                                let deltaSec = Double(dx) * secondsPerPixel
                                let segDuration = initialEnd - initialStart
                                let newStart = min(max(0, initialStart + deltaSec), max(0, clipDuration - segDuration))
                                onUpdateTimes(segment.id, newStart, newStart + segDuration)
                            }
                            .onEnded { _ in
                                hasRecordedUndo = false
                            }
                    )
                    .cursorOnHover(.pointingHand)
                    .onTapGesture {
                        onSelect()
                    }

                // Left handle for resizing start
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 8)
                        .overlay(
                            Rectangle()
                                .fill(Color.white.opacity(selected ? 0.78 : (playheadHighlighted ? 0.62 : 0.36)))
                                .frame(width: 1.5)
                        )
                        .gesture(
                            DragGesture(coordinateSpace: .named("timeline"))
                                .onChanged { value in
                                    if !hasRecordedUndo {
                                        recordUndo()
                                        hasRecordedUndo = true
                                        initialStart = segment.start
                                        initialEnd = segment.end
                                        onSelect()
                                    }
                                    let dx = value.translation.width
                                    let deltaSec = Double(dx) * secondsPerPixel
                                    let newStart = min(max(0, initialStart + deltaSec), segment.end - 0.25)
                                    onUpdateTimes(segment.id, newStart, segment.end)
                                }
                                .onEnded { _ in
                                    hasRecordedUndo = false
                                }
                        )
                        .cursorOnHover(.resizeLeftRight)

                    Spacer()
                }

                // Right handle for resizing end
                HStack {
                    Spacer()

                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 8)
                        .overlay(
                            Rectangle()
                                .fill(Color.white.opacity(selected ? 0.78 : (playheadHighlighted ? 0.62 : 0.36)))
                                .frame(width: 1.5)
                        )
                        .gesture(
                            DragGesture(coordinateSpace: .named("timeline"))
                                .onChanged { value in
                                    if !hasRecordedUndo {
                                        recordUndo()
                                        hasRecordedUndo = true
                                        initialStart = segment.start
                                        initialEnd = segment.end
                                        onSelect()
                                    }
                                    let dx = value.translation.width
                                    let deltaSec = Double(dx) * secondsPerPixel
                                    let newEnd = max(segment.start + 0.25, min(clipDuration, initialEnd + deltaSec))
                                    onUpdateTimes(segment.id, segment.start, newEnd)
                                }
                                .onEnded { _ in
                                    hasRecordedUndo = false
                                }
                        )
                        .cursorOnHover(.resizeLeftRight)
                }
            }
            .frame(width: blockWidth)
            .offset(x: blockOffset)
        }
    }

    private func percent(_ value: Double, _ total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }
}

private struct TextOverlayListRow: View {
    let trackName: String
    let block: TextOverlayBlock
    let selected: Bool
    let startClock: String
    let endClock: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(trackName) · \(startClock) -> \(endClock)")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(VaniScriptTheme.accent)
            Text(block.text.isEmpty ? "[ Empty Text Block ]" : block.text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? VaniScriptTheme.text0 : VaniScriptTheme.text1)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(selected ? Color.dynamic(light: VaniScriptTheme.accent.opacity(0.15), dark: Color(red: 54 / 255, green: 42 / 255, blue: 26 / 255).opacity(0.88)) : Color.dynamic(light: Color.black.opacity(0.035), dark: Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? VaniScriptTheme.accent.opacity(0.7) : Color.dynamic(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.08)), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct TimelineCutRegion: View {
    let cut: TimelineCut
    let duration: Double

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.red.opacity(0.22))
                .overlay(
                    Rectangle()
                        .stroke(Color.red.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
                .frame(width: max(2, geometry.size.width * CGFloat(percent(cut.endSec - cut.startSec, duration))))
                .offset(x: geometry.size.width * CGFloat(percent(cut.startSec, duration)))
        }
    }

    private func percent(_ value: Double, _ total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }
}

private struct AudioFadeSlopeOverlay: View {
    let width: CGFloat
    let height: CGFloat
    let fadeInWidth: CGFloat
    let fadeOutWidth: CGFloat

    var body: some View {
        ZStack {
            if fadeInWidth > 0 {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: CGPoint(x: fadeInWidth, y: height))
                    path.addLine(to: CGPoint(x: fadeInWidth, y: 0))
                    path.closeSubpath()
                }
                .fill(Color.white.opacity(0.15))

                Path { path in
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: CGPoint(x: fadeInWidth, y: 0))
                }
                .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
            }

            if fadeOutWidth > 0 && fadeOutWidth < width {
                Path { path in
                    path.move(to: CGPoint(x: width - fadeOutWidth, y: 0))
                    path.addLine(to: CGPoint(x: width - fadeOutWidth, y: height))
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(Color.white.opacity(0.15))

                Path { path in
                    path.move(to: CGPoint(x: width - fadeOutWidth, y: 0))
                    path.addLine(to: CGPoint(x: width, y: height))
                }
                .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
            }
        }
    }
}

private struct TimelineAudioBlock: View {
    let track: ExtraAudioTrack
    let duration: Double // virtualDuration
    let assetDuration: Double
    let selected: Bool
    let onSelect: () -> Void
    let onUpdateTimes: (Double, Double, Double) -> Void
    let onCommitUpdate: () -> Void
    let onDelete: () -> Void
    let recordUndo: () -> Void
    private let audioTrimHandleHitWidth: CGFloat = 18
    private let audioTrimHandleVisibleWidth: CGFloat = 6

    @State private var initialStartSec: Double = 0.0
    @State private var initialTrimStartSec: Double = 0.0
    @State private var initialTrimEndSec: Double = 0.0
    @State private var hasRecordedUndo = false

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            let secondsPerPixel = duration / Double(max(1, trackWidth))

            let playableDuration = max(0.25, assetDuration - track.trimStartSec - track.trimEndSec)
            let blockWidth = max(24, trackWidth * CGFloat(percent(playableDuration, duration)))
            let blockOffset = trackWidth * CGFloat(percent(track.startSec, duration))

            ZStack(alignment: .leading) {
                // Main body background and title
                HStack(spacing: 4) {
                    if blockWidth > 50 {
                        Text(track.name)
                            .font(.system(size: 9, weight: .heavy))
                            .lineLimit(1)
                            .foregroundStyle(track.muted == true ? Color.dynamic(light: Color(white: 0.52), dark: Color(white: 0.52)) : Color.white)
                    }
                    Spacer(minLength: 0)
                    if blockWidth > 30 {
                        Button(action: onDelete) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(track.muted == true ? Color.dynamic(light: Color(white: 0.52), dark: Color(white: 0.52)) : Color.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .frame(width: blockWidth, height: 20)
                .background(track.muted == true ? Color.dynamic(light: Color(white: 0.86), dark: Color(white: 0.20)) : Color(red: 131 / 255, green: 90 / 255, blue: 32 / 255))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .gesture(
                    DragGesture(coordinateSpace: .named("timeline"))
                        .onChanged { value in
                            guard track.muted != true else { return }
                            if !hasRecordedUndo {
                                recordUndo()
                                hasRecordedUndo = true
                                initialStartSec = track.startSec
                                onSelect()
                            }
                            let dx = value.translation.width
                            let deltaSec = Double(dx) * secondsPerPixel
                            let playableDur = max(0.25, assetDuration - track.trimStartSec - track.trimEndSec)
                            let newStart = min(max(0, initialStartSec + deltaSec), max(0, duration - playableDur))
                            onUpdateTimes(newStart, track.trimStartSec, track.trimEndSec)
                        }
                        .onEnded { _ in
                            hasRecordedUndo = false
                            onCommitUpdate()
                        }
                )
                .cursorOnHover(track.muted == true ? .arrow : .pointingHand)

                // Fade Slopes Overlay
                let pixelsPerSecond = blockWidth / CGFloat(playableDuration)
                let fadeInWidth = CGFloat(track.fadeInSec) * pixelsPerSecond
                let fadeOutWidth = CGFloat(track.fadeOutSec) * pixelsPerSecond
                AudioFadeSlopeOverlay(width: blockWidth, height: 20, fadeInWidth: fadeInWidth, fadeOutWidth: fadeOutWidth)
                    .allowsHitTesting(false)

                // Border outline
                RoundedRectangle(cornerRadius: 5)
                    .stroke(track.muted == true ? Color.dynamic(light: Color(white: 0.73), dark: Color(white: 0.28)) : VaniScriptTheme.accent.opacity(selected ? 1.0 : 0.45), lineWidth: 1)
                    .allowsHitTesting(false)

                // Left Drag Handle
                if track.muted != true {
                    HStack {
                        ZStack(alignment: .leading) {
                            Color.clear
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: audioTrimHandleVisibleWidth, height: 20)
                                .overlay(
                                    Rectangle()
                                        .fill(Color.white.opacity(0.4))
                                        .frame(width: 1)
                                )
                        }
                        .frame(width: audioTrimHandleHitWidth, height: 20)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(coordinateSpace: .named("timeline"))
                                .onChanged { value in
                                    if !hasRecordedUndo {
                                        recordUndo()
                                        hasRecordedUndo = true
                                        initialStartSec = track.startSec
                                        initialTrimStartSec = track.trimStartSec
                                        initialTrimEndSec = track.trimEndSec
                                        onSelect()
                                    }
                                    let dx = value.translation.width
                                    let deltaSec = Double(dx) * secondsPerPixel
                                    let maxStartSec = initialStartSec + (assetDuration - initialTrimStartSec - initialTrimEndSec) - 0.25
                                    let newStart = min(max(0, initialStartSec + deltaSec), maxStartSec)
                                    let actualDelta = newStart - initialStartSec
                                    let newTrimStart = initialTrimStartSec + actualDelta
                                    let constrainedTrimStart = min(max(0, newTrimStart), assetDuration - initialTrimEndSec - 0.25)
                                    let adjustedStartSec = initialStartSec + (constrainedTrimStart - initialTrimStartSec)
                                    onUpdateTimes(adjustedStartSec, constrainedTrimStart, initialTrimEndSec)
                                }
                                .onEnded { _ in
                                    hasRecordedUndo = false
                                    onCommitUpdate()
                                }
                        )
                        .cursorOnHover(.resizeLeftRight)
                        Spacer()
                    }
                }

                // Right Drag Handle
                if track.muted != true {
                    HStack {
                        Spacer()
                        ZStack(alignment: .trailing) {
                            Color.clear
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: audioTrimHandleVisibleWidth, height: 20)
                                .overlay(
                                    Rectangle()
                                        .fill(Color.white.opacity(0.4))
                                        .frame(width: 1)
                                )
                        }
                        .frame(width: audioTrimHandleHitWidth, height: 20)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(coordinateSpace: .named("timeline"))
                                .onChanged { value in
                                    if !hasRecordedUndo {
                                        recordUndo()
                                        hasRecordedUndo = true
                                        initialStartSec = track.startSec
                                        initialTrimStartSec = track.trimStartSec
                                        initialTrimEndSec = track.trimEndSec
                                        onSelect()
                                    }
                                    let dx = value.translation.width
                                    let deltaSec = Double(dx) * secondsPerPixel
                                    let initialPlayable = assetDuration - initialTrimStartSec - initialTrimEndSec
                                    let newPlayable = initialPlayable + deltaSec
                                    let constrainedPlayable = min(max(0.25, newPlayable), assetDuration - initialTrimStartSec)
                                    let newTrimEnd = assetDuration - initialTrimStartSec - constrainedPlayable
                                    let constrainedTrimEnd = max(0, newTrimEnd)
                                    onUpdateTimes(initialStartSec, initialTrimStartSec, constrainedTrimEnd)
                                }
                                .onEnded { _ in
                                    hasRecordedUndo = false
                                    onCommitUpdate()
                                }
                        )
                        .cursorOnHover(.resizeLeftRight)
                    }
                }
            }
            .frame(width: blockWidth, height: 20)
            .offset(x: blockOffset, y: 3)
        }
    }

    private func percent(_ value: Double, _ total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }
}

private struct TimelineTextBlock: View {
    let block: TextOverlayBlock
    let duration: Double
    let introDuration: Double
    let clipDuration: Double
    let active: Bool
    let selected: Bool
    var muted: Bool = false
    let onSelect: () -> Void
    let onUpdateTimes: (Double, Double) -> Void
    let recordUndo: () -> Void

    @State private var initialStart: Double = 0.0
    @State private var initialEnd: Double = 0.0
    @State private var hasRecordedUndo = false

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            let secondsPerPixel = duration / Double(max(1, trackWidth))
            let blockWidth = max(24, trackWidth * CGFloat(percent(block.endSec - block.startSec, duration)))
            let blockOffset = trackWidth * CGFloat(percent(block.startSec + introDuration, duration))
            let playheadHighlighted = active && !selected

            ZStack {
                // Background and text
                Text(block.text.isEmpty ? "[ Empty Text Block ]" : block.text)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(muted ? Color.dynamic(light: Color(white: 0.52), dark: Color(white: 0.52)) : VaniScriptTheme.text0)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        muted
                            ? Color.dynamic(light: Color(white: 0.86), dark: Color(white: 0.20))
                            : (selected
                                ? TimelineTextBlockPalette.selectionFill
                                : playheadHighlighted
                                    ? TimelineTextBlockPalette.playheadFill
                                    : TimelineTextBlockPalette.baseFill)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(muted ? Color.dynamic(light: Color(white: 0.73), dark: Color(white: 0.28)) : (selected ? TimelineTextBlockPalette.selectionStroke : (playheadHighlighted ? TimelineTextBlockPalette.playheadStroke : TimelineTextBlockPalette.baseStroke)), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .gesture(
                        DragGesture(coordinateSpace: .named("timeline"))
                            .onChanged { value in
                                guard !muted else { return }
                                if !hasRecordedUndo {
                                    recordUndo()
                                    hasRecordedUndo = true
                                    initialStart = block.startSec
                                    initialEnd = block.endSec
                                    onSelect()
                                }
                                let dx = value.translation.width
                                let deltaSec = Double(dx) * secondsPerPixel
                                let blockDur = initialEnd - initialStart
                                let newStart = min(max(0, initialStart + deltaSec), max(0, clipDuration - blockDur))
                                onUpdateTimes(newStart, newStart + blockDur)
                            }
                            .onEnded { _ in
                                hasRecordedUndo = false
                            }
                    )
                    .cursorOnHover(muted ? .arrow : .pointingHand)
                    .onTapGesture {
                        onSelect()
                    }

                // Left handle for resizing start
                if !muted {
                    HStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 8)
                            .overlay(
                                Rectangle()
                                    .fill(Color.white.opacity(selected ? 0.78 : (playheadHighlighted ? 0.62 : 0.36)))
                                    .frame(width: 1.5)
                            )
                            .gesture(
                                DragGesture(coordinateSpace: .named("timeline"))
                                    .onChanged { value in
                                        if !hasRecordedUndo {
                                            recordUndo()
                                            hasRecordedUndo = true
                                            initialStart = block.startSec
                                            initialEnd = block.endSec
                                            onSelect()
                                        }
                                        let dx = value.translation.width
                                        let deltaSec = Double(dx) * secondsPerPixel
                                        let newStart = min(max(0, initialStart + deltaSec), block.endSec - 0.25)
                                        onUpdateTimes(newStart, block.endSec)
                                    }
                                    .onEnded { _ in
                                        hasRecordedUndo = false
                                    }
                            )
                            .cursorOnHover(.resizeLeftRight)

                        Spacer()
                    }
                }

                // Right handle for resizing end
                if !muted {
                    HStack {
                        Spacer()

                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 8)
                            .overlay(
                                Rectangle()
                                    .fill(Color.white.opacity(selected ? 0.78 : (playheadHighlighted ? 0.62 : 0.36)))
                                    .frame(width: 1.5)
                            )
                            .gesture(
                                DragGesture(coordinateSpace: .named("timeline"))
                                    .onChanged { value in
                                        if !hasRecordedUndo {
                                            recordUndo()
                                            hasRecordedUndo = true
                                            initialStart = block.startSec
                                            initialEnd = block.endSec
                                            onSelect()
                                        }
                                        let dx = value.translation.width
                                        let deltaSec = Double(dx) * secondsPerPixel
                                        let newEnd = max(block.startSec + 0.25, min(clipDuration, initialEnd + deltaSec))
                                        onUpdateTimes(block.startSec, newEnd)
                                    }
                                    .onEnded { _ in
                                        hasRecordedUndo = false
                                    }
                            )
                            .cursorOnHover(.resizeLeftRight)
                    }
                }
            }
            .frame(width: blockWidth)
            .offset(x: blockOffset)
        }
    }

    private func percent(_ value: Double, _ total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }
}

private struct InspectorTitle: View {
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(VaniScriptTheme.text0)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(VaniScriptTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var suffix = ""
    var percent = false
    var onChange: () -> Void = {}
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(VaniScriptTheme.text2)
                .frame(width: 76, alignment: .leading)
            Slider(
                value: Binding(get: { value }, set: { value = $0; onChange() }),
                in: range,
                step: step,
                onEditingChanged: onEditingChanged
            )
                .tint(VaniScriptTheme.accent)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(VaniScriptTheme.accent)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private var label: String {
        if percent { return "\(Int((value * 100).rounded()))%" }
        if suffix == "px", step < 1 { return "\(String(format: "%.1f", value))\(suffix)" }
        if step < 1 { return "\(String(format: "%.2f", value))\(suffix)" }
        return "\(Int(value.rounded()))\(suffix)"
    }
}

private struct OptionalSliderRow: View {
    let title: String
    @Binding var value: Double?
    let fallback: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var suffix = ""
    var percent = false

    var body: some View {
        SliderRow(
            title: title,
            value: Binding(get: { value ?? fallback }, set: { value = $0 }),
            range: range,
            step: step,
            suffix: suffix,
            percent: percent
        )
    }
}

private struct ColorTextRow: View {
    let title: String
    @Binding var value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(VaniScriptTheme.text2)
                .frame(width: 76, alignment: .leading)
            ColorPicker("", selection: Binding(get: { Color(hex: value) }, set: { value = $0.hexString ?? value }))
                .labelsHidden()
            TextField("", text: $value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(6)
                .background(Color.dynamic(light: Color.black.opacity(0.06), dark: Color.white.opacity(0.06)))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
}

private struct OptionalColorTextRow: View {
    let title: String
    @Binding var value: String?
    let fallback: String

    var body: some View {
        ColorTextRow(
            title: title,
            value: Binding(get: { value ?? fallback }, set: { value = $0 })
        )
    }
}

private struct PickerRow: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(VaniScriptTheme.text2)
                .frame(width: 76, alignment: .leading)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }
}

private struct LayerRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(VaniScriptTheme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(VaniScriptTheme.text1)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(VaniScriptTheme.text2)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.dynamic(light: Color.black.opacity(0.035), dark: Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.dynamic(light: Color.black.opacity(0.09), dark: Color.white.opacity(0.09)), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct LayerEditorCard<Content: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(VaniScriptTheme.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.text1)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(VaniScriptTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(10)
        .background(Color.dynamic(light: Color.black.opacity(0.035), dark: Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.dynamic(light: Color.black.opacity(0.09), dark: Color.white.opacity(0.09)), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct EmptyLayerText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(VaniScriptTheme.text2)
            .italic()
    }
}

private struct EditorSmallButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(EditorToolbarButtonStyle())
    }
}

private struct EditorPrimaryButtonStyle: ButtonStyle {
    var isSaved: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(isSaved ? Color.white : Color.black)
            .frame(width: 125, height: 30)
            .background(isSaved ? VaniScriptTheme.green : (configuration.isPressed ? VaniScriptTheme.accentHover : VaniScriptTheme.accent))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct EditorToolbarButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? VaniScriptTheme.accent : VaniScriptTheme.text1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(active ? VaniScriptTheme.accent.opacity(0.12) : Color.dynamic(light: Color.black.opacity(configuration.isPressed ? 0.08 : 0.03), dark: Color.white.opacity(configuration.isPressed ? 0.1 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(active ? VaniScriptTheme.accent.opacity(0.55) : Color.dynamic(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.12)), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct EditorDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(VaniScriptTheme.red)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(VaniScriptTheme.red.opacity(configuration.isPressed ? 0.18 : 0.09))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(VaniScriptTheme.red.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct EditorIconButtonStyle: ButtonStyle {
    var disabled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(disabled ? VaniScriptTheme.text2.opacity(0.55) : VaniScriptTheme.text1)
            .frame(width: 30, height: 30)
            .background(Color.dynamic(light: Color.black.opacity(configuration.isPressed ? 0.08 : 0.03), dark: Color.white.opacity(configuration.isPressed ? 0.09 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.dynamic(light: Color.black.opacity(0.1), dark: Color.white.opacity(0.1)), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct EditorSegmentButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(active ? Color.black : VaniScriptTheme.text2)
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(active ? VaniScriptTheme.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct InspectorTabButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(active ? Color.black : VaniScriptTheme.text2)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(active ? VaniScriptTheme.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct EditorRoundPlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.black)
            .frame(width: 34, height: 34)
            .background(configuration.isPressed ? VaniScriptTheme.accentHover : VaniScriptTheme.accent)
            .clipShape(Circle())
    }
}

private struct WordMoveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundStyle(VaniScriptTheme.accent)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.dynamic(light: Color.black.opacity(configuration.isPressed ? 0.08 : 0.03), dark: Color.white.opacity(configuration.isPressed ? 0.12 : 0.04)))
            .clipShape(Capsule())
    }
}

private struct ModalCancelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(VaniScriptTheme.text1)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .frame(minWidth: 100)
            .background(Color.dynamic(light: Color.black.opacity(configuration.isPressed ? 0.08 : 0.04), dark: Color.white.opacity(configuration.isPressed ? 0.08 : 0.04)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.dynamic(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.12)), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ModalOKButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(VaniScriptTheme.text0)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .frame(minWidth: 100)
            .background(Color.dynamic(light: Color.black.opacity(configuration.isPressed ? 0.20 : 0.14), dark: Color.white.opacity(configuration.isPressed ? 0.20 : 0.14)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.dynamic(light: Color.black.opacity(0.24), dark: Color.white.opacity(0.24)), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).prefix(6)
        var value: UInt64 = 0
        Scanner(string: String(clean)).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String? {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = Int(round(components.redComponent * 255))
        let green = Int(round(components.greenComponent * 255))
        let blue = Int(round(components.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

struct StripesPattern: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 12
            let total = size.width + size.height
            var x: CGFloat = 0
            while x < total {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x - size.height, y: size.height))
                context.stroke(path, with: .color(Color(red: 255 / 255, green: 60 / 255, blue: 60 / 255).opacity(0.08)), lineWidth: 3)
                x += step
            }
        }
    }
}

struct TimelineTrimRegion: View {
    let width: CGFloat

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
            StripesPattern()
        }
        .allowsHitTesting(false)
    }
}

struct TimelineTrimHandle: View {
    let isStart: Bool
    let position: CGFloat
    var height: CGFloat = 28
    let onDrag: (DragGesture.Value) -> Void
    let onDragEnd: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 24, height: height + 4)
            Rectangle()
                .fill(VaniScriptTheme.accent)
                .frame(width: 4, height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 1.5, height: max(6, height * 0.43))
                )
        }
        .position(x: position, y: height / 2)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged(onDrag)
                .onEnded { _ in onDragEnd() }
        )
    }
}

struct TimelineCutRegionOverlay: View {
    let cuts: [TimelineCut]
    let trim: TimelineTrim
    let clipDuration: Double
    let introDuration: Double
    let virtualDuration: Double
    let recordUndo: () -> Void
    let onUpdateCut: (Int, TimelineCut) -> Void
    let onDeleteCut: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let activeVideoDuration = clipDuration - trim.trimStartSec - trim.trimEndSec
            if activeVideoDuration > 0 {
                let containerWidth = geometry.size.width
                let activeVideoStartVirtual = trim.trimStartSec + introDuration
                let activeLeft = containerWidth * CGFloat(activeVideoStartVirtual / virtualDuration)
                let activeWidth = containerWidth * CGFloat(activeVideoDuration / virtualDuration)

                ZStack(alignment: .leading) {
                    ForEach(Array(cuts.enumerated()), id: \.offset) { index, cut in
                        if cut.endSec > trim.trimStartSec && cut.startSec < clipDuration - trim.trimEndSec {
                            let visibleStart = max(trim.trimStartSec, cut.startSec)
                            let visibleEnd = min(clipDuration - trim.trimEndSec, cut.endSec)
                            let cutLeft = activeWidth * CGFloat((visibleStart - trim.trimStartSec) / activeVideoDuration)
                            let cutWidth = max(5, activeWidth * CGFloat((visibleEnd - visibleStart) / activeVideoDuration))

                            Rectangle()
                                .fill(Color.red.opacity(0.22))
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.red.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                )
                                .frame(width: cutWidth)
                                .offset(x: cutLeft)
                                .contextMenu {
                                    Button("Delete Cut") {
                                        onDeleteCut(index)
                                    }
                                }
                            TimelineCutRegionHandle(
                                index: index,
                                cut: cut,
                                isStart: true,
                                position: cutLeft,
                                activeWidth: activeWidth,
                                activeVideoDuration: activeVideoDuration,
                                minSec: trim.trimStartSec,
                                maxSec: clipDuration - trim.trimEndSec,
                                height: geometry.size.height,
                                recordUndo: recordUndo,
                                onUpdateCut: onUpdateCut
                            )
                            TimelineCutRegionHandle(
                                index: index,
                                cut: cut,
                                isStart: false,
                                position: cutLeft + cutWidth,
                                activeWidth: activeWidth,
                                activeVideoDuration: activeVideoDuration,
                                minSec: trim.trimStartSec,
                                maxSec: clipDuration - trim.trimEndSec,
                                height: geometry.size.height,
                                recordUndo: recordUndo,
                                onUpdateCut: onUpdateCut
                            )
                        }
                    }
                }
                .frame(width: activeWidth, height: geometry.size.height)
                .offset(x: activeLeft)
            }
        }
    }
}

struct TimelineCutRegionHandle: View {
    let index: Int
    let cut: TimelineCut
    let isStart: Bool
    let position: CGFloat
    let activeWidth: CGFloat
    let activeVideoDuration: Double
    let minSec: Double
    let maxSec: Double
    let height: CGFloat
    let recordUndo: () -> Void
    let onUpdateCut: (Int, TimelineCut) -> Void

    @State private var dragOrigin: TimelineCut?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 18, height: height + 8)
            Rectangle()
                .fill(Color(hex: "#ef4444"))
                .frame(width: 3, height: max(12, height))
                .shadow(color: Color(hex: "#ef4444").opacity(0.55), radius: 2)
        }
        .position(x: position, y: height / 2)
        .cursorOnHover(.resizeLeftRight)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragOrigin == nil {
                        dragOrigin = cut
                        recordUndo()
                    }
                    guard var origin = dragOrigin else { return }
                    let deltaSec = activeWidth > 0
                        ? Double(value.translation.width / activeWidth) * activeVideoDuration
                        : 0
                    if isStart {
                        origin.startSec = min(max(minSec, origin.startSec + deltaSec), origin.endSec - 0.1)
                    } else {
                        origin.endSec = max(min(maxSec, origin.endSec + deltaSec), origin.startSec + 0.1)
                    }
                    onUpdateCut(index, TimelineCut(startSec: origin.startSec, endSec: origin.endSec))
                }
                .onEnded { _ in
                    dragOrigin = nil
                }
        )
    }
}

class PlayerHostingView: NSView {
    override func layout() {
        super.layout()
        if let sublayers = layer?.sublayers {
            for sublayer in sublayers {
                if sublayer is AVPlayerLayer {
                    sublayer.frame = bounds
                }
            }
        }
    }
}

struct EditorAVPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity

    func makeNSView(context: Context) -> PlayerHostingView {
        let view = PlayerHostingView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = videoGravity
        playerLayer.backgroundColor = NSColor.clear.cgColor
        playerLayer.frame = view.bounds

        view.layer?.addSublayer(playerLayer)
        return view
    }

    func updateNSView(_ nsView: PlayerHostingView, context: Context) {
        if let playerLayer = nsView.layer?.sublayers?.first(where: { $0 is AVPlayerLayer }) as? AVPlayerLayer {
            if playerLayer.player !== player {
                playerLayer.player = player
            }
            if playerLayer.videoGravity != videoGravity {
                playerLayer.videoGravity = videoGravity
            }
            playerLayer.frame = nsView.bounds
        }
    }

    static func dismantleNSView(_ nsView: PlayerHostingView, coordinator: ()) {
        if let playerLayer = nsView.layer?.sublayers?.first(where: { $0 is AVPlayerLayer }) as? AVPlayerLayer {
            playerLayer.player = nil
        }
    }
}

struct ViewportMaskShape: Shape {
    let cutoutRect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(cutoutRect)
        return path
    }
}

extension View {
    func cursorOnHover(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct TimelineScrollWheelTuner: NSViewRepresentable {
    @Binding var zoom: Double

    class Coordinator: NSObject {
        var parent: TimelineScrollWheelTuner
        var monitor: Any?
        weak var scrollView: NSScrollView?

        // Panning state
        var isPanning = false
        var initialScrollLeft: CGFloat = 0.0
        var initialMouseX: CGFloat = 0.0

        init(_ parent: TimelineScrollWheelTuner) {
            self.parent = parent
        }

        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        DispatchQueue.main.async {
            guard let scrollView = view.enclosingScrollView else { return }
            context.coordinator.scrollView = scrollView

            if context.coordinator.monitor == nil {
                let mask: NSEvent.EventTypeMask = [.scrollWheel, .otherMouseDown, .otherMouseDragged, .otherMouseUp]
                context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak coordinator = context.coordinator] event in
                    guard let coordinator = coordinator,
                          let scrollView = coordinator.scrollView,
                          let window = scrollView.window,
                          window.isKeyWindow else {
                        return event
                    }

                    let mousePoint = scrollView.convert(event.locationInWindow, from: nil)

                    switch event.type {
                    case .scrollWheel:
                        guard scrollView.bounds.contains(mousePoint) else { return event }

                        // Option key: Zoom
                        if event.modifierFlags.contains(.option) {
                            let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
                            guard abs(delta) > 0.01 else { return nil }

                            let factor = delta > 0 ? 1.08 : 0.92
                            let oldZoom = coordinator.parent.zoom
                            let newZoom = min(12.0, max(1.0, oldZoom * factor))

                            if newZoom != oldZoom {
                                let contentView = scrollView.contentView
                                if let documentView = scrollView.documentView {
                                    let documentPoint = contentView.convert(mousePoint, to: documentView)
                                    let oldScrollWidth = documentView.bounds.width
                                    let anchorRatio = oldScrollWidth > 0 ? documentPoint.x / oldScrollWidth : 0

                                    coordinator.parent.zoom = newZoom

                                    DispatchQueue.main.async {
                                        let newScrollWidth = documentView.bounds.width
                                        let targetX = (anchorRatio * newScrollWidth) - mousePoint.x
                                        contentView.scroll(to: NSPoint(x: max(0, targetX), y: 0))
                                        scrollView.reflectScrolledClipView(contentView)
                                    }
                                }
                            }
                            return nil
                        }

                        // Command key: Horizontal Scroll
                        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
                            let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : (event.deltaY * 10)
                            let contentView = scrollView.contentView
                            let currentOffset = contentView.bounds.origin
                            let newX = max(0, currentOffset.x - delta)

                            contentView.scroll(to: NSPoint(x: newX, y: currentOffset.y))
                            scrollView.reflectScrolledClipView(contentView)
                            return nil
                        }

                    case .otherMouseDown:
                        if event.buttonNumber == 2 && scrollView.bounds.contains(mousePoint) {
                            coordinator.isPanning = true
                            coordinator.initialScrollLeft = scrollView.contentView.bounds.origin.x
                            coordinator.initialMouseX = event.locationInWindow.x
                            NSCursor.closedHand.push()
                            return nil
                        }

                    case .otherMouseDragged:
                        if coordinator.isPanning {
                            let dx = event.locationInWindow.x - coordinator.initialMouseX
                            let newX = max(0, coordinator.initialScrollLeft - dx)
                            let contentView = scrollView.contentView
                            contentView.scroll(to: NSPoint(x: newX, y: 0))
                            scrollView.reflectScrolledClipView(contentView)
                            return nil
                        }

                    case .otherMouseUp:
                        if event.buttonNumber == 2 && coordinator.isPanning {
                            coordinator.isPanning = false
                            NSCursor.pop()
                            return nil
                        }

                    default:
                        break
                    }

                    return event
                }
            }
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }
}
