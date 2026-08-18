import AVKit
import SwiftUI
import VaniScriptCore

struct ExportWorkspaceView: View {
    @EnvironmentObject private var store: WorkflowStore

    @AppStorage("shortsExportClipCount") private var clipCount = 2.0
    @AppStorage("shortsExportMinLength") private var minLength = 50.0
    @AppStorage("shortsExportMaxLength") private var maxLength = 200.0
    @AppStorage("shortsExportFormat") private var exportFormat = "MP4"
    @AppStorage("shortsExportResolution") private var exportResolution = "Source-based"
    @AppStorage("shortsExportFrameRate") private var exportFrameRate = "Source-based"

    @State private var exportSelection = ShortsExportSelection()
    @State private var displayLanguage: ShortsIdeaDisplayLanguage = .source
    @State private var detailsDraft: ClipDetailsDraft?
    @State private var replaceDraft: ReplaceClipDraft?

    private var clipCardColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: 2)
    }

    private var exportControlColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 14, alignment: .topLeading), count: 3)
    }

    var body: some View {
        if let session = store.session {
            ZStack {
                ScrollView {
                    VStack(spacing: VaniScriptTheme.Density.space12) {
                        VStack(alignment: .leading, spacing: 20) {
                            exportHeader(session: session)
                            documentExportSection(session: session)
                                .onboardingTarget("export-documents")
                            shortsReelsSection(session: session)
                                .onboardingTarget("shorts-panel")
                            exportFooterActions()
                                .onboardingTarget("export-footer-actions")
                            // Status lives in ContentView's thin bottom strip —
                            // do not re-render the full log string here.
                        }
                        .frame(maxWidth: 1120, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 22)
                        .glassPanel()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(VaniScriptTheme.Density.space12)
                }
                .sheet(item: $detailsDraft) { draft in
                    ClipDetailsSheet(
                        plan: draft.plan,
                        transcript: ShortsTranscriptExtractor.extract(
                            plan: draft.plan,
                            session: session,
                            targetLanguage: session.selectedTranslationLanguage
                        ),
                        displayLanguage: $displayLanguage,
                        onFindAlternatives: {
                            detailsDraft = nil
                            findMoments(mode: draft.plan.languageMode ?? (session.selectedTranslationLanguage == nil ? .source : .target))
                        },
                        onEdit: {
                            detailsDraft = nil
                            store.openVisualEditor(
                                at: draft.index,
                                plan: draft.plan,
                                language: displayLanguage,
                            )
                        },
                        onDelete: {
                            detailsDraft = nil
                            removePlan(at: draft.index)
                        }
                    )
                }
                .sheet(item: $replaceDraft) { draft in
                    ReplaceClipSheet(
                        draft: draft,
                        isBusy: store.isPlanningShorts,
                        onCancel: { replaceDraft = nil },
                        onSave: { start, end in
                            store.replaceShortsPlanTiming(at: draft.index, start: start, end: end)
                            replaceDraft = nil
                        }
                    )
                }
                .onChange(of: session.shortsPlans?.count ?? 0) { _, count in
                    seedDefaultSourceSelectionIfNeeded(count: count)
                }
                .onAppear {
                    seedDefaultSourceSelectionIfNeeded(count: session.shortsPlans?.count ?? 0)
                }

                if store.isExportingShorts {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    ExportProgressModalView()
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: store.isExportingShorts)
        } else {
            UploadWorkspaceView()
        }
    }

    private func exportHeader(session: SessionState) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(VaniScriptTheme.text0)
                Text("\(session.chunks.count) segments · \(session.sourceFileName)")
                    .font(.system(size: 12))
                    .foregroundStyle(VaniScriptTheme.text2)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    store.startTour(for: "export")
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(ReviewBackButtonStyle())
                .help("Help Tour")

                Button("Back to Chunks") {
                    store.openReview()
                }
                .buttonStyle(ReviewBackButtonStyle())
            }
        }
    }

    private func documentExportSection(session: SessionState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ExportSectionHeading(
                title: "Document export",
                subtitle: session.sourceKind == .document
                    ? "Download the localized DOCX, a three-file translation package, or standalone PDF / TXT."
                    : "Download the reviewed transcript as text, subtitles, or a formatted Markdown document."
            )
            if session.sourceKind == .document {
                let exportBlocked = store.hasStaleDocumentChunks
                if exportBlocked {
                    Text("Fix the highlighted chunks before exporting — their translations no longer match the source.")
                        .font(.system(size: 12))
                        .foregroundStyle(VaniScriptTheme.errorText)
                }
                HStack(spacing: 8) {
                    ExportButton(title: "DOCX", primary: true) {
                        store.exportDocument(format: .docx)
                    }
                    ExportButton(title: "Package (3 files)", primary: false) {
                        store.exportDocumentTranslationPackage()
                    }
                    ExportButton(title: "PDF", primary: false) {
                        store.exportDocument(format: .pdf)
                    }
                    ExportButton(title: "TXT", primary: false) {
                        store.exportDocument(format: .txt)
                    }
                }
                .disabled(exportBlocked)
                .help(exportBlocked ? "Fix the stale chunks before exporting — their translations no longer match the source." : "")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(OutputFormat.allCases, id: \.rawValue) { format in
                        ExportButton(title: "Original \(format.rawValue)", primary: false) {
                            store.export(side: .original, format: format)
                        }
                    }
                    if session.selectedTranslationLanguage != nil {
                        ForEach(OutputFormat.allCases, id: \.rawValue) { format in
                            ExportButton(title: "Target \(format.rawValue)", primary: true) {
                                store.export(side: .translated, format: format)
                            }
                        }
                    }
                }
            }
        }
    }

    private func shortsReelsSection(session: SessionState) -> some View {
        let plans = session.shortsPlans ?? []
        let canUseTarget = session.selectedTranslationLanguage != nil
        let selectedCount = exportSelection.selectedCount(validClipCount: plans.count)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                ExportSectionHeading(
                    title: "Shorts & Reels",
                    subtitle: "Four steps in one scroll: find moments, select clips, tune captions, export video or ideas."
                )
                Spacer()
                planningTools
            }

            ShortsStepSection(number: 1, title: "Find short moments") {
                VStack(spacing: VaniScriptTheme.Density.space8) {
                    HStack(spacing: 14) {
                        ShortsSlider(
                            title: "Number of clips",
                            value: $clipCount,
                            range: 1...8,
                            step: 1,
                            suffix: ""
                        )
                        ShortsSlider(
                            title: "Min length",
                            value: $minLength,
                            range: 15...120,
                            step: 5,
                            suffix: "s"
                        )
                        ShortsSlider(
                            title: "Max length",
                            value: $maxLength,
                            range: 30...240,
                            step: 5,
                            suffix: "s"
                        )
                    }

                    HStack(spacing: 10) {
                        FindMomentButton(title: "Source language", isBusy: store.isPlanningShorts) {
                            findMoments(mode: .source)
                        }
                        FindMomentButton(title: "Source + Target", isBusy: store.isPlanningShorts, disabled: !canUseTarget) {
                            findMoments(mode: .bilingual)
                        }
                        FindMomentButton(
                            title: "Target language: \(session.selectedTranslationLanguage ?? "None")",
                            isBusy: store.isPlanningShorts,
                            disabled: !canUseTarget
                        ) {
                            findMoments(mode: .target)
                        }
                    }
                }
            }
            .onboardingTarget("shorts-find-moments")

            ShortsStepSection(number: 2, title: "Choose clips", trailing: languageToggle(canUseTarget: canUseTarget)) {
                VStack(spacing: 10) {
                    if plans.isEmpty {
                        Text("Click \"Find Moments\" to create clip cards with title, timing, description, and category.")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(VaniScriptTheme.text2)
                            .frame(maxWidth: .infinity, minHeight: 82, alignment: .center)
                    } else {
                        LazyVGrid(columns: clipCardColumns, spacing: 12) {
                            ForEach(Array(plans.enumerated()), id: \.offset) { index, plan in
                                ShortsPlanCard(
                                    plan: plan,
                                    index: index,
                                    displayLanguage: displayLanguage,
                                    selected: exportSelection.contains(index: index, language: displayLanguage),
                                    onToggle: { togglePlan(index) },
                                    onDetails: { detailsDraft = ClipDetailsDraft(index: index, plan: plan) },
                                    onReplace: { replaceDraft = ReplaceClipDraft(index: index, plan: plan) },
                                    onDelete: { removePlan(at: index) },
                                    onEdit: {
                                        exportSelection.insert(index: index, language: displayLanguage)
                                        store.openVisualEditor(at: index, plan: plan, language: displayLanguage)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .onboardingTarget("shorts-choose-clips")

            ShortsStepSection(number: 3, title: "Export") {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: exportControlColumns, spacing: 14) {
                        ExportPicker(title: "Format", selection: $exportFormat, options: ["MP4", "MOV"])
                        ExportPicker(title: "Resolution", selection: $exportResolution, options: ["Source-based", "Full HD 1080x1920", "2K 1440x2560", "4K 2160x3840"])
                        ExportPicker(title: "Frame rate", selection: $exportFrameRate, options: ["Source-based", "24 FPS", "25 FPS", "30 FPS", "50 FPS", "60 FPS"])
                    }
                    .onboardingTarget("shorts-export-settings")
                    HStack(spacing: 10) {
                        ExportActionButton(title: "Export ideas JSON/TXT", primary: false, disabled: plans.isEmpty) {
                            store.exportShortsIdeas(
                                indices: exportSelection.indexes(for: displayLanguage, validClipCount: plans.count),
                                displayLanguage: displayLanguage
                            )
                        }

                        ExportActionButton(title: "Export selected videos (\(selectedCount))", primary: true, disabled: selectedCount == 0) {
                            store.exportSelectedShortsVideos(
                                jobs: exportSelection.jobs(validClipCount: plans.count),
                                format: exportFormat,
                                resolution: exportResolution,
                                frameRate: exportFrameRate
                            )
                        }
                    }
                    .onboardingTarget("shorts-export-actions")
                    Text("Clips are trimmed and encoded with AVFoundation. Clip metadata and captions stay editable in the clip editor.")
                        .font(.system(size: 11))
                        .foregroundStyle(VaniScriptTheme.text2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    private var planningTools: some View {
        HStack(spacing: 10) {
            if !store.editingProviders.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PLANNING MODEL")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.text2)
                    Picker("Planning model", selection: Binding(
                        get: { store.editingProviderID },
                        set: { store.setEditingProvider($0) }
                    )) {
                        ForEach(store.editingProviders, id: \.id) { provider in
                            Text(provider.label).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250)
                }
            }
            Button("Save defaults") {
                store.statusMessage = "Shorts/Reels defaults saved."
            }
            .buttonStyle(ReviewBackButtonStyle())
        }
    }

    private func exportFooterActions() -> some View {
        HStack(spacing: 10) {
            Button {
                store.openReview()
            } label: {
                Label("Back to Chunks", systemImage: "arrow.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ExportSecondaryButtonStyle())

            Button {
                store.presentProjectSidebar()
            } label: {
                Label("Sessions", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ExportSecondaryButtonStyle())

            Button {
                store.newSession()
            } label: {
                Text("New Session")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ExportSecondaryButtonStyle())
        }
    }

    private func languageToggle(canUseTarget: Bool) -> some View {
        HStack(spacing: 0) {
            Button("Source") {
                displayLanguage = .source
            }
            .buttonStyle(TogglePillStyle(active: displayLanguage == .source))

            Button("Target") {
                displayLanguage = .target
            }
            .buttonStyle(TogglePillStyle(active: displayLanguage == .target))
            .disabled(!canUseTarget)
        }
        .padding(4)
        .background(VaniScriptTheme.control)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func findMoments(mode: ShortsPlanLanguageMode) {
        store.generateShortsPlan(
            count: Int(clipCount.rounded()),
            minDurationSec: Int(minLength.rounded()),
            maxDurationSec: Int(maxLength.rounded()),
            mode: mode
        )
        exportSelection.removeAll()
        displayLanguage = mode == .source ? .source : .target
    }

    private func togglePlan(_ index: Int) {
        exportSelection.toggle(index: index, language: displayLanguage)
    }

    private func seedDefaultSourceSelectionIfNeeded(count: Int) {
        guard count > 0, exportSelection.selectedCount(validClipCount: count) == 0 else { return }
        exportSelection.selectAllSource(validClipCount: count)
    }

    private func removePlan(at index: Int) {
        store.removeShortsPlan(at: index)
        exportSelection.removeAll()
    }

    private func plan(at index: Int, in session: SessionState) -> ShortsClipPlan? {
        guard let plans = session.shortsPlans, plans.indices.contains(index) else { return nil }
        return plans[index]
    }
}

private struct ReplaceClipDraft: Identifiable {
    let id = UUID()
    let index: Int
    let start: String
    let end: String
    let languageMode: ShortsPlanLanguageMode?

    init(index: Int, plan: ShortsClipPlan) {
        self.index = index
        self.start = plan.start
        self.end = plan.end
        self.languageMode = plan.languageMode
    }
}

private struct ClipDetailsDraft: Identifiable {
    let id = UUID()
    let index: Int
    let plan: ShortsClipPlan
}

struct VisualClipEditorDraft: Identifiable {
    let id = UUID()
    let index: Int
    let language: ShortsIdeaDisplayLanguage
    let sourceURL: URL?
    let start: String
    let end: String
    let transcript: ShortsTranscriptDetail
    let title: String
    let summary: String
    let hook: String
    let category: String
    let captionText: String
    let sourceAlignment: [AlignedSubtitleSegment]
    let targetAlignment: [AlignedSubtitleSegment]
    let sourceFrameKeyframes: [FrameKeyframe]
    let targetFrameKeyframes: [FrameKeyframe]
    let timelineCuts: [TimelineCut]
    let timelineTrim: TimelineTrim
    let backgroundSettings: ShortsBackgroundSettings
    let subtitleStyle: ShortsSubtitleStyle
    let syncEnabled: Bool
    let hasLinkedPartner: Bool
    let sourceLogo: LogoOverlaySettings?
    let targetLogo: LogoOverlaySettings?
    let sourceTextTracks: [TextOverlayTrack]
    let targetTextTracks: [TextOverlayTrack]
    let sourceAudioTracks: [ExtraAudioTrack]
    let targetAudioTracks: [ExtraAudioTrack]
    let sourceIntro: IntroOutroOverlaySettings?
    let targetIntro: IntroOutroOverlaySettings?
    let sourceOutro: IntroOutroOverlaySettings?
    let targetOutro: IntroOutroOverlaySettings?

    init(index: Int, plan: ShortsClipPlan, language: ShortsIdeaDisplayLanguage, session: SessionState) {
        let fields = ShortsIdeasExporter.displayFields(for: plan, language: language)
        let sourceFields = ShortsIdeasExporter.displayFields(for: plan, language: .source)
        let targetFields = ShortsIdeasExporter.displayFields(for: plan, language: .target)
        let extractedTranscript = ShortsTranscriptExtractor.extract(
            plan: plan,
            session: session,
            targetLanguage: session.selectedTranslationLanguage
        )
        let sourceCaptionText = sourceFields.captionText.isEmpty ? extractedTranscript.source : sourceFields.captionText
        let targetCaptionText = targetFields.captionText.isEmpty ? extractedTranscript.target : targetFields.captionText
        self.index = index
        self.language = language
        self.sourceURL = session.sourceFile.map(URL.init(fileURLWithPath:))
        self.start = plan.start
        self.end = plan.end
        self.transcript = extractedTranscript
        self.title = fields.title
        self.summary = fields.summary
        self.hook = fields.hook
        self.category = fields.category
        self.captionText = fields.captionText.isEmpty
            ? (language == .source ? extractedTranscript.source : extractedTranscript.target)
            : fields.captionText
        self.sourceAlignment = plan.sourceAlignment?.isEmpty == false
            ? ShortsVisualEditorStateBuilder.normalized(plan.sourceAlignment ?? [], duration: ShortsVisualEditorStateBuilder.clipDuration(plan))
            : ShortsVisualEditorStateBuilder.segments(
                fromCaptionText: sourceCaptionText,
                clipStartSec: ShortsPlanner.parseTimestampToSeconds(plan.start),
                clipEndSec: ShortsPlanner.parseTimestampToSeconds(plan.end)
            )
        self.targetAlignment = plan.targetAlignment?.isEmpty == false
            ? ShortsVisualEditorStateBuilder.normalized(plan.targetAlignment ?? [], duration: ShortsVisualEditorStateBuilder.clipDuration(plan))
            : ShortsVisualEditorStateBuilder.segments(
                fromCaptionText: targetCaptionText,
                clipStartSec: ShortsPlanner.parseTimestampToSeconds(plan.start),
                clipEndSec: ShortsPlanner.parseTimestampToSeconds(plan.end)
            )
        self.sourceFrameKeyframes = plan.sourceFrameKeyframes ?? [
            FrameKeyframe(id: "frame_source_base", time: 0, x: 0, y: 0, zoom: 1, backgroundColor: plan.backgroundSettings?.solidColor ?? "#000000")
        ]
        self.targetFrameKeyframes = plan.targetFrameKeyframes ?? [
            FrameKeyframe(id: "frame_target_base", time: 0, x: 0, y: 0, zoom: 1, backgroundColor: plan.backgroundSettings?.solidColor ?? "#000000")
        ]
        self.timelineCuts = plan.timelineCuts ?? []
        self.timelineTrim = plan.timelineTrim ?? .zero
        self.backgroundSettings = plan.backgroundSettings ?? .universalDefault
        self.subtitleStyle = plan.subtitleStyle ?? .orangeImpact
        self.syncEnabled = plan.syncEnabled ?? (plan.languageMode == .bilingual)
        self.hasLinkedPartner = plan.linkedClipGroupId != nil || plan.languageMode == .bilingual
        self.sourceLogo = plan.sourceLogo ?? plan.logo
        self.targetLogo = plan.targetLogo ?? plan.logo
        self.sourceTextTracks = plan.sourceTextTracks ?? plan.textTracks ?? []
        self.targetTextTracks = plan.targetTextTracks ?? plan.textTracks ?? []
        self.sourceAudioTracks = plan.sourceAudioTracks ?? plan.audioTracks ?? []
        self.targetAudioTracks = plan.targetAudioTracks ?? plan.audioTracks ?? []
        self.sourceIntro = plan.sourceIntro ?? plan.intro
        self.targetIntro = plan.targetIntro ?? plan.intro
        self.sourceOutro = plan.sourceOutro ?? plan.outro
        self.targetOutro = plan.targetOutro ?? plan.outro
    }
}

struct EditClipValues {
    var language: ShortsIdeaDisplayLanguage = .target
    var start: String
    var end: String
    var title: String
    var summary: String
    var hook: String
    var category: String
    var captionText: String
    var sourceAlignment: [AlignedSubtitleSegment] = []
    var targetAlignment: [AlignedSubtitleSegment] = []
    var sourceFrameKeyframes: [FrameKeyframe] = []
    var targetFrameKeyframes: [FrameKeyframe] = []
    var timelineCuts: [TimelineCut] = []
    var timelineTrim: TimelineTrim = .zero
    var backgroundSettings: ShortsBackgroundSettings = .universalDefault
    var subtitleStyle: ShortsSubtitleStyle = .orangeImpact
    var syncEnabled: Bool = false
    var sourceLogo: LogoOverlaySettings? = nil
    var targetLogo: LogoOverlaySettings? = nil
    var sourceTextTracks: [TextOverlayTrack] = []
    var targetTextTracks: [TextOverlayTrack] = []
    var sourceAudioTracks: [ExtraAudioTrack] = []
    var targetAudioTracks: [ExtraAudioTrack] = []
    var sourceIntro: IntroOutroOverlaySettings? = nil
    var targetIntro: IntroOutroOverlaySettings? = nil
    var sourceOutro: IntroOutroOverlaySettings? = nil
    var targetOutro: IntroOutroOverlaySettings? = nil
}

private struct ShortsStepSection<Content: View, Trailing: View>: View {
    let number: Int
    let title: String
    let trailing: Trailing
    @ViewBuilder let content: Content

    init(number: Int, title: String, trailing: Trailing = EmptyView(), @ViewBuilder content: () -> Content) {
        self.number = number
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
            HStack {
                HStack(spacing: 10) {
                    Text("\(number)")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.onAccent)
                        .frame(width: 24, height: 24)
                        .background(VaniScriptTheme.accent)
                        .clipShape(Circle())
                    Text(title)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.text0)
                }
                Spacer()
                trailing
            }
            content
        }
        .padding(VaniScriptTheme.Density.space12)
        .background(VaniScriptTheme.surfaceSubtle)
        .overlay(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM).stroke(VaniScriptTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
    }
}

private struct ShortsSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(VaniScriptTheme.text2)
                Spacer()
                Text("\(Int(value.rounded()))\(suffix)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(VaniScriptTheme.accent)
            }
            Slider(value: $value, in: range, step: step)
                .tint(VaniScriptTheme.accent)
        }
    }
}

private struct FindMomentButton: View {
    let title: String
    let isBusy: Bool
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isBusy ? "Working..." : title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ExportPrimaryButtonStyle())
        .disabled(isBusy || disabled)
    }
}

private struct ShortsPlanCard: View {
    let plan: ShortsClipPlan
    let index: Int
    let displayLanguage: ShortsIdeaDisplayLanguage
    let selected: Bool
    let onToggle: () -> Void
    let onDetails: () -> Void
    let onReplace: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    var body: some View {
        let fields = ShortsIdeasExporter.displayFields(for: plan, language: displayLanguage)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(VaniScriptTheme.onAccent)
                        .opacity(selected ? 1 : 0)
                        .background(selected ? VaniScriptTheme.accent : VaniScriptTheme.control)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(VaniScriptTheme.accent.opacity(selected ? 0 : 0.6), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(fields.title)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(VaniScriptTheme.text0)
                        Text("\(plan.start)  ->  \(plan.end)  ·  \(clipDurationLabel(plan))")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(VaniScriptTheme.accent)
                        Text(fields.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(VaniScriptTheme.text1)
                            .lineLimit(3)
                        HStack {
                            Text(fields.category.uppercased())
                            Text((plan.languageMode?.rawValue ?? "target").uppercased())
                        }
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                CardActionButton(title: "Details", action: onDetails)
                CardActionButton(title: "Replace", action: onReplace)
                CardActionButton(title: "Delete", action: onDelete)
                CardActionButton(title: "Edit Clip", systemImage: "pencil", action: onEdit)
                    .onboardingTarget("shorts-edit-clip")
            }
        }
        .padding(14)
        .background(selected ? VaniScriptTheme.controlSelected : VaniScriptTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM)
                .stroke(selected ? VaniScriptTheme.controlSelectedBorder : VaniScriptTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
    }

    private func clipDurationLabel(_ plan: ShortsClipPlan) -> String {
        let seconds = max(0, Int((ShortsPlanner.parseTimestampToSeconds(plan.end) - ShortsPlanner.parseTimestampToSeconds(plan.start)).rounded()))
        return "\(seconds)s"
    }
}

private struct CardActionButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ExportSecondaryButtonStyle())
    }
}

private struct ClipDetailsSheet: View {
    let plan: ShortsClipPlan
    let transcript: ShortsTranscriptDetail
    @Binding var displayLanguage: ShortsIdeaDisplayLanguage
    let onFindAlternatives: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let fields = ShortsIdeasExporter.displayFields(for: plan, language: displayLanguage)
        VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clip details")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.text0)
                    Text("\(plan.start) -> \(plan.end) · \(plan.languageMode?.rawValue ?? "target")")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.accent)
                }
                Spacer()
                HStack(spacing: 0) {
                    Button("Source") { displayLanguage = .source }
                        .buttonStyle(TogglePillStyle(active: displayLanguage == .source))
                    Button("Target") { displayLanguage = .target }
                        .buttonStyle(TogglePillStyle(active: displayLanguage == .target))
                }
                .padding(4)
                .background(VaniScriptTheme.control)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DetailField(title: "Title", value: fields.title)
                    DetailField(title: "Category", value: fields.category)
                    DetailField(title: "Description", value: fields.summary)
                    DetailField(title: "Hook", value: fields.hook)
                    DetailField(title: "Rendered caption lines", value: fields.captionText, monospaced: true)

                    HStack(alignment: .top, spacing: 12) {
                        DetailField(title: "Source transcript", value: transcript.source, monospaced: true)
                        DetailField(title: "Target transcript", value: transcript.target, monospaced: true)
                    }
                }
            }

            HStack {
                Button("Find alternatives", action: onFindAlternatives)
                    .buttonStyle(ExportSecondaryButtonStyle())
                Button("Delete clip", action: onDelete)
                    .buttonStyle(ExportSecondaryButtonStyle())
                Button("Edit Clip", action: onEdit)
                    .buttonStyle(ExportSecondaryButtonStyle())
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(ExportPrimaryButtonStyle())
            }
        }
        .padding(VaniScriptTheme.Density.space12)
        .frame(width: 880, height: 720)
        .background(VaniScriptTheme.card)
    }
}

private struct DetailField: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(VaniScriptTheme.text2)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 12, weight: .semibold, design: monospaced ? .monospaced : .default))
                .foregroundStyle(VaniScriptTheme.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(VaniScriptTheme.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct ReplaceClipSheet: View {
    let draft: ReplaceClipDraft
    let isBusy: Bool
    let onCancel: () -> Void
    let onSave: (String, String) -> Void

    @State private var startValue: String
    @State private var endValue: String

    init(draft: ReplaceClipDraft, isBusy: Bool, onCancel: @escaping () -> Void, onSave: @escaping (String, String) -> Void) {
        self.draft = draft
        self.isBusy = isBusy
        self.onCancel = onCancel
        self.onSave = onSave
        _startValue = State(initialValue: draft.start)
        _endValue = State(initialValue: draft.end)
    }

    var body: some View {
        let validation = ShortsPlanner.validateClip(
            startSec: ShortsPlanner.parseTimestampToSeconds(startValue),
            endSec: ShortsPlanner.parseTimestampToSeconds(endValue),
            minDurationSec: 10,
            maxDurationSec: 300
        )

        VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space12) {
            Text("Replace Clip")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(VaniScriptTheme.text0)
            Text("Adjust the time range and regenerate the native clip range. The language pairing (\(draft.languageMode?.rawValue ?? "target")) is preserved.")
                .font(.system(size: 12))
                .foregroundStyle(VaniScriptTheme.text2)

            HStack(spacing: 12) {
                TextInputBlock(title: "Start time", text: $startValue, hint: "Original: \(draft.start)")
                TextInputBlock(title: "End time", text: $endValue, hint: "Original: \(draft.end)")
            }

            if let reason = validation.reason {
                Text(reason)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
            } else {
                Text("Duration: \(Int(validation.durationSec.rounded()))s")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.text2)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(ExportSecondaryButtonStyle())
                Button(isBusy ? "Regenerating..." : "Regenerate Clip") {
                    onSave(startValue, endValue)
                }
                .buttonStyle(ExportPrimaryButtonStyle())
                .disabled(!validation.ok || isBusy)
            }
        }
        .padding(VaniScriptTheme.Density.space12)
        .frame(width: 560)
        .background(VaniScriptTheme.card)
    }
}

private struct LegacyClipVisualEditorSheet: View {
    let draft: VisualClipEditorDraft
    let onCancel: () -> Void
    let onSave: (EditClipValues) -> Void

    @State private var player: AVPlayer?
    @State private var startSec: Double
    @State private var endSec: Double
    @State private var title: String
    @State private var category: String
    @State private var summary: String
    @State private var hook: String
    @State private var captionText: String

    init(draft: VisualClipEditorDraft, onCancel: @escaping () -> Void, onSave: @escaping (EditClipValues) -> Void) {
        self.draft = draft
        self.onCancel = onCancel
        self.onSave = onSave
        let initialStart = ShortsPlanner.parseTimestampToSeconds(draft.start)
        let initialEnd = ShortsPlanner.parseTimestampToSeconds(draft.end)
        _startSec = State(initialValue: initialStart)
        _endSec = State(initialValue: max(initialStart + 1, initialEnd))
        _title = State(initialValue: draft.title)
        _category = State(initialValue: draft.category)
        _summary = State(initialValue: draft.summary)
        _hook = State(initialValue: draft.hook)
        _captionText = State(initialValue: draft.captionText)
        if let sourceURL = draft.sourceURL {
            _player = State(initialValue: AVPlayer(url: sourceURL))
        } else {
            _player = State(initialValue: nil)
        }
    }

    var body: some View {
        let timelineMax = max(endSec + 60, 60)
        let isValidRange = endSec > startSec && (endSec - startSec) <= 300

        VStack(alignment: .leading, spacing: VaniScriptTheme.Density.space8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Visual Clip Editor")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.text0)
                    Text("\(draft.language == .source ? "Source" : "Target") clip · \(ShortsPlanner.secondsToShortsTimestamp(startSec)) -> \(ShortsPlanner.secondsToShortsTimestamp(endSec))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.accent)
                }
                Spacer()
                Button("Preview Clip") {
                    previewClip()
                }
                .buttonStyle(ExportSecondaryButtonStyle())
                .disabled(player == nil)
            }

            HStack(alignment: .top, spacing: VaniScriptTheme.Density.space12) {
                VStack(alignment: .leading, spacing: 14) {
                    ZStack {
                        if let player {
                            NativeAVPlayerView(player: player)
                                .frame(height: 360)
                                .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusMD, style: .continuous))
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "video.slash")
                                    .font(.system(size: 28, weight: .semibold))
                                Text("Original local video is not attached to this imported project.")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(VaniScriptTheme.text2)
                            .frame(maxWidth: .infinity, minHeight: 360)
                            .background(Color.black.opacity(0.28))
                            .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusMD, style: .continuous))
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            TimeAdjustBlock(title: "Start", value: $startSec, maxValue: timelineMax)
                            TimeAdjustBlock(title: "End", value: $endSec, maxValue: timelineMax)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("DURATION")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(VaniScriptTheme.text2)
                                Text("\(Int(max(0, endSec - startSec).rounded()))s")
                                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(isValidRange ? VaniScriptTheme.accent : VaniScriptTheme.red)
                            }
                            .frame(width: 90, alignment: .leading)
                        }

                        if !isValidRange {
                            Text("Clip range must be after start and no longer than 5 minutes.")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(VaniScriptTheme.red)
                        }
                    }
                }
                .frame(width: 520)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        TextInputBlock(title: "Title", text: $title)
                        TextInputBlock(title: "Category", text: $category)
                        TextAreaBlock(title: "Description", text: $summary, height: 82)
                        TextAreaBlock(title: "Hook", text: $hook, height: 64)
                        TextAreaBlock(title: "Rendered caption lines", text: $captionText, height: 150, monospaced: true)
                        DetailField(title: "Source transcript", value: draft.transcript.source, monospaced: true)
                        DetailField(title: "Target transcript", value: draft.transcript.target, monospaced: true)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(ExportSecondaryButtonStyle())
                Button("Save Clip") {
                    onSave(
                        EditClipValues(
                            start: ShortsPlanner.secondsToShortsTimestamp(startSec),
                            end: ShortsPlanner.secondsToShortsTimestamp(endSec),
                            title: title,
                            summary: summary,
                            hook: hook,
                            category: category,
                            captionText: captionText
                        )
                    )
                }
                .buttonStyle(ExportPrimaryButtonStyle())
                .disabled(!isValidRange)
            }
        }
        .padding(VaniScriptTheme.Density.space12)
        .frame(width: 1040, height: 760)
        .background(VaniScriptTheme.card)
        .onDisappear {
            player?.pause()
        }
    }

    private func previewClip() {
        guard let player else { return }
        player.seek(to: CMTime(seconds: startSec, preferredTimescale: 600))
        player.play()
    }
}

struct NativeAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}

private struct TimeAdjustBlock: View {
    let title: String
    @Binding var value: Double
    let maxValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(VaniScriptTheme.text2)
            Text(ShortsPlanner.secondsToShortsTimestamp(value))
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundStyle(VaniScriptTheme.accent)
            Slider(value: $value, in: 0...maxValue, step: 1)
                .tint(VaniScriptTheme.accent)
                .frame(width: 170)
        }
    }
}

private struct TextInputBlock: View {
    let title: String
    @Binding var text: String
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(VaniScriptTheme.text2)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .padding(10)
                .background(VaniScriptTheme.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(VaniScriptTheme.text2)
            }
        }
    }
}

private struct TextAreaBlock: View {
    let title: String
    @Binding var text: String
    let height: Double
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(VaniScriptTheme.text2)
            TextEditor(text: $text)
                .font(.system(size: 12, weight: .semibold, design: monospaced ? .monospaced : .default))
                .scrollContentBackground(.hidden)
                .frame(height: height)
                .padding(8)
                .background(VaniScriptTheme.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct ExportPicker: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(VaniScriptTheme.text2)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        selection = option
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selection)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VaniScriptTheme.text1)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.accent)
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .padding(.horizontal, 10)
                .background(VaniScriptTheme.input)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(VaniScriptTheme.controlBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExportActionButton: View {
    let title: String
    let primary: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if primary {
                Button(action: action) {
                    Text(title)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
                }
                .buttonStyle(ExportPrimaryButtonStyle())
            } else {
                Button(action: action) {
                    Text(title)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
                }
                .buttonStyle(ExportSecondaryButtonStyle())
            }
        }
        .disabled(disabled)
        .frame(maxWidth: .infinity)
    }
}

private struct ExportSectionHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(VaniScriptTheme.text0)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(VaniScriptTheme.text2)
        }
    }
}

private struct ExportButton: View {
    let title: String
    let primary: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if primary {
                Button(action: action) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.down")
                        Text(title)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ExportPrimaryButtonStyle())
            } else {
                Button(action: action) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.down")
                        Text(title)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ExportSecondaryButtonStyle())
            }
        }
    }
}

private struct ExportPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? VaniScriptTheme.onAccent : VaniScriptTheme.disabledText)
            .padding(.vertical, VaniScriptTheme.Density.space8)
            .padding(.horizontal, VaniScriptTheme.Density.space12)
            .background(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.accentHover : VaniScriptTheme.accent)
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(
                RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous)
                    .stroke(isEnabled ? Color.clear : VaniScriptTheme.controlBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
            .opacity(isEnabled && configuration.isPressed ? 0.9 : 1)
    }
}

private struct ExportSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? VaniScriptTheme.text1 : VaniScriptTheme.disabledText)
            .padding(.vertical, VaniScriptTheme.Density.space8)
            .padding(.horizontal, VaniScriptTheme.Density.space12)
            .background(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.controlPressed : VaniScriptTheme.control)
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM).stroke(isEnabled ? VaniScriptTheme.controlBorder : VaniScriptTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
    }
}

private struct ReviewBackButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? VaniScriptTheme.text1 : VaniScriptTheme.disabledText)
            .padding(.horizontal, VaniScriptTheme.Density.space12)
            .frame(height: VaniScriptTheme.Density.controlHeightMD)
            .background(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.controlPressed : VaniScriptTheme.control)
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM).stroke(isEnabled ? VaniScriptTheme.controlBorder : VaniScriptTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
    }
}

private struct TogglePillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(
                isEnabled
                    ? (active ? VaniScriptTheme.onAccent : VaniScriptTheme.text2)
                    : VaniScriptTheme.disabledText
            )
            .padding(.horizontal, VaniScriptTheme.Density.space12)
            .frame(height: VaniScriptTheme.Density.controlHeightMD)
            .background(
                isEnabled
                    ? (active ? VaniScriptTheme.accent : Color.clear)
                    : (active ? VaniScriptTheme.disabledSurface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous)
                    .stroke(isEnabled ? Color.clear : (active ? VaniScriptTheme.border : Color.clear), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: VaniScriptTheme.Density.radiusSM, style: .continuous))
            .opacity(isEnabled && configuration.isPressed ? 0.85 : 1)
    }
}

struct SpinningRingsView: View {
    @State private var outerRotation: Double = 0
    @State private var innerRotation: Double = 0

    var body: some View {
        ZStack {
            // Outer Ring Trace
            Circle()
                .stroke(VaniScriptTheme.border, lineWidth: 4)
                .frame(width: 80, height: 80)

            // Outer Ring Arc
            Circle()
                .trim(from: 0.0, to: 0.35)
                .stroke(
                    VaniScriptTheme.accent,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(outerRotation))

            // Inner Ring Trace
            Circle()
                .stroke(VaniScriptTheme.border, lineWidth: 2)
                .frame(width: 62, height: 62)

            // Inner Ring Arc
            Circle()
                .trim(from: 0.0, to: 0.25)
                .stroke(
                    VaniScriptTheme.text0,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 62, height: 62)
                .rotationEffect(.degrees(-innerRotation))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                outerRotation = 360
            }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                innerRotation = 360
            }
        }
    }
}

struct ExportProgressModalView: View {
    @EnvironmentObject private var store: WorkflowStore

    var body: some View {
        VStack(spacing: VaniScriptTheme.Density.space12) {
            if let completionState = store.exportCompletionState {
                switch completionState {
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 62))
                        .foregroundStyle(Color.green)
                        .padding(.top, 8)
                case .failure:
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 62))
                        .foregroundStyle(Color.red)
                        .padding(.top, 8)
                }
            } else {
                SpinningRingsView()
                    .padding(.top, 8)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let completionState = store.exportCompletionState {
                    switch completionState {
                    case .success:
                        Text("Export Completed")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(VaniScriptTheme.text0)
                    case .failure:
                        Text("Export Failed")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(VaniScriptTheme.text0)
                    }
                } else {
                    Text("Exporting Shorts/Reels")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.text0)
                }

                if let completionState = store.exportCompletionState, case .failure(let error) = completionState {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(VaniScriptTheme.errorText)
                } else {
                    Text(store.exportStage)
                        .font(.system(size: 13))
                        .foregroundStyle(VaniScriptTheme.text2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                HStack {
                    Text(store.exportClipProgressText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.text0)
                    Spacer()
                    Text("\(Int(store.exportProgress * 100))%")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.text0)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(VaniScriptTheme.border)
                            .frame(height: 8)

                        Capsule()
                            .fill(VaniScriptTheme.accent)
                            .frame(width: geometry.size.width * CGFloat(store.exportProgress), height: 8)
                    }
                }
                .frame(height: 8)
            }

            HStack(spacing: VaniScriptTheme.Density.space12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Clip")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.text2)
                    HStack(spacing: 8) {
                        Text("Elapsed: \(store.formatTimeInterval(store.currentClipElapsedTime))")
                        if store.exportCompletionState == nil, let remaining = store.currentClipRemainingTime {
                            Text("•")
                            Text("ETA: \(store.formatTimeInterval(remaining))")
                        }
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(VaniScriptTheme.text1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total Export")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.text2)
                    HStack(spacing: 8) {
                        Text("Elapsed: \(store.formatTimeInterval(store.overallElapsedTime))")
                        if store.exportCompletionState == nil, let remaining = store.overallRemainingTime {
                            Text("•")
                            Text("ETA: \(store.formatTimeInterval(remaining))")
                        }
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(VaniScriptTheme.text1)
                }
            }
            .padding(.top, 4)

            if store.exportTotalClips > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clips Render Status")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.text2)
                        .padding(.bottom, 2)

                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(0..<store.exportTotalClips, id: \.self) { idx in
                                HStack {
                                    Text("Clip \(idx + 1)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(VaniScriptTheme.text1)
                                    Spacer()
                                    if let duration = store.exportDurations[idx] {
                                        Text("Done (\(store.formatTimeInterval(duration)))")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(Color.green.opacity(0.8))
                                    } else if store.exportCompletionState != nil {
                                        if case .failure = store.exportCompletionState, idx == store.exportActiveClipIndex - 1 {
                                            Text("Failed")
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.red)
                                        } else {
                                            Text("Pending")
                                                .font(.system(size: 12))
                                                .foregroundStyle(VaniScriptTheme.text2.opacity(0.6))
                                        }
                                    } else if idx == store.exportActiveClipIndex - 1 {
                                        Text("Rendering...")
                                            .font(.system(size: 12))
                                            .foregroundStyle(VaniScriptTheme.accent)
                                    } else {
                                        Text("Pending")
                                            .font(.system(size: 12))
                                            .foregroundStyle(VaniScriptTheme.text2.opacity(0.6))
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.dynamic(light: Color.black.opacity(0.03), dark: Color.white.opacity(0.03)))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }
                .padding(.top, 8)
            }

            Text(store.exportPhaseTag)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(VaniScriptTheme.text2.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)

            if store.exportCompletionState != nil {
                Button(action: {
                    store.closeExportShortsModal()
                }) {
                    Text("Close")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ExportPrimaryButtonStyle())
            } else {
                Button(action: {
                    store.cancelExportShorts()
                }) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ExportSecondaryButtonStyle())
            }
        }
        .padding(VaniScriptTheme.Density.space12)
        .frame(width: 440)
        .background(VaniScriptTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(VaniScriptTheme.border, lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 30, x: 0, y: 15)
    }
}
