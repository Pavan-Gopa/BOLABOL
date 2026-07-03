import AppKit
import SwiftUI
import VaniScriptCore

struct ReviewWorkspaceView: View {
    @EnvironmentObject private var store: WorkflowStore
    @Environment(\.openSettings) private var openSettings
    @State private var keyMonitor: Any?
    @State private var editDraft: ReviewEditDraft?
    @State private var glossaryDraft: ReviewGlossaryDraft?
    @State private var searchReplaceDraft: SearchReplaceDraft?

    var body: some View {
        if let session = store.session, let chunk = store.currentChunk {
            ZStack {
                VStack(spacing: 0) {
                    topBar(session: session, chunk: chunk)
                    audioBar(session: session, chunk: chunk)
                    thinProgress(session: session)
                    panes(session: session, chunk: chunk)
                    actionBar(session: session, chunk: chunk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.08))

                if let draft = editDraft {
                    EditTextSnippetModal(
                        draft: Binding(
                            get: { editDraft ?? draft },
                            set: { editDraft = $0 }
                        ),
                        onCancel: { editDraft = nil },
                        onSave: saveEditDraft
                    )
                }

                if let draft = glossaryDraft {
                    GlossaryDraftModal(
                        draft: Binding(
                            get: { glossaryDraft ?? draft },
                            set: { glossaryDraft = $0 }
                        ),
                        glossary: store.settings.glossary,
                        categories: glossaryCategories,
                        onCancel: { glossaryDraft = nil },
                        onSave: saveGlossaryDraft
                    )
                }

                if let draft = searchReplaceDraft {
                    SearchReplaceModal(
                        draft: Binding(
                            get: { searchReplaceDraft ?? draft },
                            set: { searchReplaceDraft = $0 }
                        ),
                        onCancel: { searchReplaceDraft = nil },
                        onReplaceAll: { draft in
                            store.globalSearchAndReplace(
                                query: draft.searchQuery,
                                replacement: draft.replacementText,
                                targetSide: draft.targetSide,
                                language: store.activeTranslationLanguage,
                                caseSensitive: draft.caseSensitive,
                                wholeWord: draft.wholeWord
                            )
                            searchReplaceDraft = nil
                        }
                    )
                }
            }
            .onAppear(perform: installSpacebarMonitor)
            .onDisappear(perform: removeSpacebarMonitor)
        } else {
            UploadWorkspaceView()
        }
    }

    private func topBar(session: SessionState, chunk: ChunkData) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                VaniScriptLogoMark(size: 28)
                Text("VaniScript")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(VaniScriptTheme.accent)

                HStack(spacing: 5) {
                    Circle()
                        .fill(VaniScriptTheme.green)
                        .frame(width: 6, height: 6)
                    Text(statusLabel(chunk.status))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VaniScriptTheme.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(VaniScriptTheme.green.opacity(0.1))
                .overlay(Capsule().stroke(VaniScriptTheme.green.opacity(0.25), lineWidth: 1))
                .clipShape(Capsule())
            }

            Spacer()

            HStack(spacing: 10) {
                if !store.editingProviders.isEmpty {
                    HStack(spacing: 7) {
                        Text("EDITING MODEL")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(VaniScriptTheme.text2)
                        Picker("Editing Model", selection: Binding(
                            get: { store.editingProviderID },
                            set: { store.setEditingProvider($0) }
                        )) {
                            ForEach(store.editingProviders, id: \.id) { provider in
                                Text(provider.label).tag(provider.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onboardingTarget("review-editing-model")
                }

                Picker("View", selection: $store.viewMode) {
                    ForEach(ReviewViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                .onboardingTarget("review-view-group")
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    searchReplaceDraft = SearchReplaceDraft(
                        searchQuery: "",
                        replacementText: "",
                        targetSide: store.viewMode == .translated ? .translated : .original,
                        caseSensitive: false,
                        wholeWord: false
                    )
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(ReviewIconButtonStyle())
                .help("Search & Replace")

                Button {
                    store.startTour(for: "review")
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(ReviewIconButtonStyle())
                .help("Help Tour")

                Button {
                    store.presentProjectSidebar()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(ReviewIconButtonStyle())
                .help("Projects")

                Button {
                    if store.isTourActive && store.activeTourScreen != "settings" {
                        store.startTour(for: "settings")
                    }
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(ReviewIconButtonStyle())
                .help("Settings")
                .onboardingTarget("settings-btn")

                Button("+ New Session") {
                    store.newSession()
                }
                .buttonStyle(ReviewTextButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color(red: 10 / 255, green: 12 / 255, blue: 28 / 255).opacity(0.86))
        .overlay(Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1), alignment: .bottom)
    }

    private func audioBar(session: SessionState, chunk: ChunkData) -> some View {
        HStack(spacing: 12) {
            Text("CURRENT SEGMENT AUDIO")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(VaniScriptTheme.text2)

            HStack(spacing: 10) {
                Button {
                    store.toggleCurrentChunkPlayback()
                } label: {
                    Image(systemName: store.isPlayingCurrentChunk ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                }
                .frame(width: 24, height: 24)
                .foregroundStyle(Color(red: 10 / 255, green: 10 / 255, blue: 18 / 255))
                .background(VaniScriptTheme.accent)
                .clipShape(Circle())
                .disabled(store.isProcessingSegment)

                Text("\(formatPlayerClock(store.playbackTime)) / \(formatPlayerClock(chunk.durationSec))")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(VaniScriptTheme.accent)
                    .frame(width: 116, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { store.playbackTime },
                        set: { store.seekCurrentChunk(to: $0) }
                    ),
                    in: 0...max(0.1, chunk.durationSec)
                )
                    .tint(VaniScriptTheme.accent)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(VaniScriptTheme.accent.opacity(0.12))
            .overlay(Capsule().stroke(VaniScriptTheme.accent.opacity(0.18), lineWidth: 1))
            .clipShape(Capsule())

            Text("Audio ready")
                .font(.system(size: 11))
                .foregroundStyle(VaniScriptTheme.text2)
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.02))
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .bottom)
        .onboardingTarget("review-audio-bar")
    }

    private func thinProgress(session: SessionState) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Color.white.opacity(0.07)
                VaniScriptTheme.accent
                    .frame(width: proxy.size.width * reviewProgress(session))
            }
        }
        .frame(height: 2)
    }

    private func panes(session: SessionState, chunk: ChunkData) -> some View {
        let activeLanguage = session.selectedTranslationLanguage
        let hasTranslation = activeLanguage != nil
        return Group {
            if store.viewMode == .dual,
               hasTranslation,
               !store.currentOriginalCues.isEmpty,
               !store.currentTranslationCues.isEmpty {
                DualTimedReviewPane(
                    metadata: session.metadata,
                    translationTitle: "TRANSLATED: \((activeLanguage ?? session.targetLang).uppercased())",
                    translationLanguage: activeLanguage ?? session.targetLang,
                    sourceCues: store.currentOriginalCues,
                    targetCues: store.currentTranslationCues,
                    playbackTime: store.currentPlaybackAbsoluteTime,
                    updateSourceCue: store.updateCurrentOriginalCue,
                    updateTargetCue: store.updateCurrentTranslatedCue,
                    exportSource: { store.export(side: .original, format: store.outputFormat) },
                    exportTarget: { store.export(side: .translated, format: store.outputFormat) },
                    polishTarget: store.polishCurrentTranslation,
                    beginInlineEdit: beginInlineEdit,
                    beginGlossaryDraft: beginGlossaryDraft
                )
            } else {
                HStack(spacing: 0) {
                    if store.viewMode == .source || store.viewMode == .dual || !hasTranslation {
                        ReviewTextPane(
                            title: "ORIGINAL TRANSCRIPTION",
                            metadata: session.metadata,
                            translationLanguage: nil,
                            content: Binding(
                                get: { store.currentChunk?.original ?? "" },
                                set: { store.updateCurrentOriginal($0) }
                            ),
                            cues: store.currentOriginalCues,
                            playbackTime: store.currentPlaybackAbsoluteTime,
                            updateCue: store.updateCurrentOriginalCue,
                            side: .original,
                            accent: false,
                            exportAction: { store.export(side: .original, format: store.outputFormat) },
                            polishAction: nil,
                            beginInlineEdit: beginInlineEdit,
                            beginGlossaryDraft: beginGlossaryDraft
                        )
                        .onboardingTarget("review-pane-original")
                    }

                    if hasTranslation, store.viewMode == .translated || store.viewMode == .dual {
                        ReviewTextPane(
                            title: "TRANSLATED: \((activeLanguage ?? session.targetLang).uppercased())",
                            metadata: session.metadata,
                            translationLanguage: activeLanguage ?? session.targetLang,
                            content: Binding(
                                get: { store.currentTranslationText },
                                set: { store.updateCurrentTranslated($0) }
                            ),
                            cues: store.currentTranslationCues,
                            playbackTime: store.currentPlaybackAbsoluteTime,
                            updateCue: store.updateCurrentTranslatedCue,
                            side: .translated,
                            accent: true,
                            exportAction: { store.export(side: .translated, format: store.outputFormat) },
                            polishAction: store.polishCurrentTranslation,
                            beginInlineEdit: beginInlineEdit,
                            beginGlossaryDraft: beginGlossaryDraft
                        )
                        .onboardingTarget("review-pane-translation")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func actionBar(session: SessionState, chunk: ChunkData) -> some View {
        HStack {
            HStack(spacing: 10) {
                Text("Segment \(session.currentChunkIndex + 1) / \(session.chunks.count) · \(formatClock(chunk.startSec))-\(formatClock(chunk.endSec))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.42))

                ProgressView(value: reviewProgress(session))
                    .tint(VaniScriptTheme.accent)
                    .frame(width: 120)

                Text("\(store.approvedCount)/\(session.chunks.count) approved")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.32))
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    store.retranscribeCurrentSegment()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                        Text(store.isProcessingSegment ? "Trying" : "Try Transcription")
                    }
                }
                .buttonStyle(ReviewTextButtonStyle())
                .disabled(store.isProcessingSegment)
                .help("Re-transcribe this segment with the selected transcription model")

                if shouldShowRegenerateTimings(chunk: chunk) {
                    Button {
                        store.regenerateCurrentSegment()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text(store.isProcessingSegment ? "Regenerating" : "Regenerate Timings")
                        }
                    }
                    .buttonStyle(ReviewTextButtonStyle())
                    .disabled(store.isProcessingSegment)
                    .help("Re-transcribe this segment with Core ML timestamps")
                }

                if shouldShowRetryTranslation(chunk: chunk) {
                    Button {
                        store.retryCurrentTranslation()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text(store.isAddingTranscriptTranslation ? "Translating" : "Retry Translation")
                        }
                    }
                    .buttonStyle(ReviewTextButtonStyle())
                    .disabled(store.isAddingTranscriptTranslation)
                    .help("Retry MLX translation for the current segment")
                }

                if store.archivedTranslationLanguages.count > 1 {
                    Picker("Translation", selection: Binding(
                        get: { store.activeTranslationLanguage },
                        set: { store.activateTranslationLanguage($0) }
                    )) {
                        ForEach(store.archivedTranslationLanguages, id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }

                Text("Add")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.35))

                Picker("New translation", selection: $store.archiveTargetLanguage) {
                    ForEach(store.supportedTranslationLanguages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 130)

                Button {
                    store.addTranscriptTranslation()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: store.isAddingTranscriptTranslation ? "hourglass" : "plus.bubble")
                        Text(store.isAddingTranscriptTranslation ? "Translating" : "Add Translation")
                    }
                }
                .buttonStyle(ReviewTextButtonStyle())
                .disabled(store.isAddingTranscriptTranslation)

                Button("‹ Previous") {
                    store.moveChunk(delta: -1)
                }
                .buttonStyle(ReviewTextButtonStyle())
                .disabled(session.currentChunkIndex == 0)
                .onboardingTarget("previous-segment-btn")

                Button(session.currentChunkIndex < session.chunks.count - 1 ? "✓ Approve & Next ›" : "✓ Complete & Export") {
                    store.approveAndAdvance()
                }
                .buttonStyle(ReviewApproveButtonStyle())
                .onboardingTarget("approve-next-btn")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 10 / 255, green: 12 / 255, blue: 28 / 255).opacity(0.86))
        .overlay(Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1), alignment: .top)
    }

    private func statusLabel(_ status: ChunkStatus) -> String {
        switch status {
        case .pending:
            "Waiting"
        case .processing:
            "Processing"
        case .done:
            "Ready"
        case .error:
            "Error"
        }
    }

    private func reviewProgress(_ session: SessionState) -> Double {
        guard !session.chunks.isEmpty else { return 0 }
        return Double(store.approvedCount) / Double(session.chunks.count)
    }

    private func shouldShowRetryTranslation(chunk: ChunkData) -> Bool {
        let hasOriginal = !chunk.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasOriginal && TranslationArchive.isRealLanguage(store.activeTranslationLanguage)
    }

    private func shouldShowRegenerateTimings(chunk: ChunkData) -> Bool {
        let hasOriginal = !chunk.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasOriginal else { return false }
        let cues = chunk.originalCues ?? []
        return cues.isEmpty || cues.allSatisfy { ($0.words ?? []).isEmpty }
    }

    private func formatClock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    private func formatPlayerClock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func installSpacebarMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49 else { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            guard shouldHandlePlaybackSpacebar(event) else { return event }
            store.toggleCurrentChunkPlayback()
            return nil
        }
    }

    private func removeSpacebarMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func shouldHandlePlaybackSpacebar(_ event: NSEvent) -> Bool {
        guard store.session != nil, !store.isProcessingSegment else { return false }
        guard let firstResponder = event.window?.firstResponder else { return true }
        if firstResponder is NSTextView {
            return false
        }
        return true
    }

    private var glossaryCategories: [String] {
        let categories = store.settings.glossary.compactMap { entry in
            let value = entry.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        return Array(Set(categories)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func beginInlineEdit(cueID: TranscriptCue.ID, side: TranscriptSide, selectedText: String, contextText: String) {
        let cleanSelected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContext = contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = cleanSelected.isEmpty ? cleanContext : cleanSelected
        guard !snippet.isEmpty else { return }

        editDraft = ReviewEditDraft(
            cueID: cueID,
            side: side,
            selectedText: snippet,
            contextText: cleanContext.isEmpty ? snippet : cleanContext,
            replacementText: snippet
        )
    }

    private func saveEditDraft(_ draft: ReviewEditDraft) {
        store.replaceCueSelection(
            cueID: draft.cueID,
            side: draft.side,
            selectedText: draft.selectedText,
            contextText: draft.contextText,
            replacementText: draft.replacementText
        )
        editDraft = nil
    }

    private func beginGlossaryDraft(selectedText: String, side: TranscriptSide) {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return }
        glossaryDraft = ReviewGlossaryDraft(selectedText: selected, side: side)
    }

    private func saveGlossaryDraft(_ draft: ReviewGlossaryDraft) {
        switch draft.mode {
        case .existing:
            guard let entryID = draft.existingEntryID else { return }
            store.addGlossaryVariants(
                entryID: entryID,
                variantsText: draft.variants,
                selectedText: draft.selectedText,
                currentChunkOnly: draft.scope == .current
            )
        case .new:
            store.createGlossaryEntryFromReview(
                source: draft.source,
                translation: draft.translation,
                category: draft.category,
                variantsText: draft.variants,
                selectedText: draft.selectedText,
                currentChunkOnly: draft.scope == .current
            )
        }
        glossaryDraft = nil
    }
}

private struct ReviewEditDraft: Identifiable, Equatable {
    let id = UUID()
    var cueID: TranscriptCue.ID
    var side: TranscriptSide
    var selectedText: String
    var contextText: String
    var replacementText: String
}

private enum ReviewGlossaryMode: String, CaseIterable, Identifiable {
    case existing = "Add to Existing"
    case new = "Create New Term"

    var id: String { rawValue }
}

private enum ReviewGlossaryScope: String, CaseIterable, Identifiable {
    case processed = "All processed chunks and future sessions"
    case current = "Current chunk and future sessions"

    var id: String { rawValue }
}

private struct ReviewGlossaryDraft: Identifiable, Equatable {
    let id = UUID()
    var selectedText: String
    var side: TranscriptSide
    var mode: ReviewGlossaryMode = .existing
    var existingEntryID: GlossaryEntry.ID?
    var categoryFilter = "all"
    var search = ""
    var source: String
    var translation: String
    var category = "Review Selection"
    var variants: String
    var scope: ReviewGlossaryScope = .processed

    init(selectedText: String, side: TranscriptSide) {
        self.selectedText = selectedText
        self.side = side
        self.source = side == .original ? selectedText : ""
        self.translation = side == .translated ? selectedText : ""
        self.variants = selectedText
    }
}

private struct EditTextSnippetModal: View {
    @Binding var draft: ReviewEditDraft
    let onCancel: () -> Void
    let onSave: (ReviewEditDraft) -> Void

    var body: some View {
        ReviewModalBackdrop {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "pencil")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Edit Text Snippet")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(VaniScriptTheme.text0)

                TextEditor(text: $draft.replacementText)
                    .font(.system(size: 18, weight: .regular, design: .monospaced))
                    .foregroundStyle(VaniScriptTheme.text0)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .padding(16)
                    .frame(height: 210)
                    .background(Color.black.opacity(0.28))
                    .background(ThinScrollbarTuner())
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(VaniScriptTheme.accent, lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(ReviewTextButtonStyle())
                    Button("Save Revision") {
                        onSave(draft)
                    }
                    .buttonStyle(ReviewApproveButtonStyle())
                    .disabled(draft.replacementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 680)
            .background(Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 34, y: 20)
        }
    }
}

private struct GlossaryDraftModal: View {
    @Binding var draft: ReviewGlossaryDraft
    let glossary: [GlossaryEntry]
    let categories: [String]
    let onCancel: () -> Void
    let onSave: (ReviewGlossaryDraft) -> Void

    private var selectedEntry: GlossaryEntry? {
        guard let id = draft.existingEntryID else { return nil }
        return glossary.first { $0.id == id }
    }

    private var filteredEntries: [GlossaryEntry] {
        let query = draft.search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return glossary.filter { entry in
            let category = entry.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let categoryMatches = draft.categoryFilter == "all" || category == draft.categoryFilter
            guard categoryMatches else { return false }
            guard !query.isEmpty else { return true }
            let haystack = ([entry.source, entry.translation, category] + entry.variants)
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(query)
        }
        .prefix(24)
        .map { $0 }
    }

    private var canSave: Bool {
        switch draft.mode {
        case .existing:
            draft.existingEntryID != nil && !draft.variants.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .new:
            !draft.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !draft.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        ReviewModalBackdrop {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add to Glossary")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(VaniScriptTheme.text0)
                    Text("Add the selected misspelling to an existing term, or create a new glossary term.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VaniScriptTheme.text2)
                }

                HStack(spacing: 4) {
                    ForEach(ReviewGlossaryMode.allCases) { mode in
                        Button {
                            draft.mode = mode
                            draft.existingEntryID = nil
                            if mode == .new {
                                draft.source = draft.side == .original ? draft.selectedText : draft.source
                                draft.translation = draft.side == .translated ? draft.selectedText : draft.translation
                            }
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .foregroundStyle(draft.mode == mode ? Color(red: 10 / 255, green: 10 / 255, blue: 18 / 255) : VaniScriptTheme.text2)
                                .background(draft.mode == mode ? VaniScriptTheme.accent : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if draft.mode == .existing {
                    existingTermSection
                } else {
                    newTermSection
                }

                VStack(alignment: .leading, spacing: 6) {
                    ReviewFieldLabel(text: draft.mode == .existing ? "New Wrong Variants To Add" : "Wrong Variants")
                    TextEditor(text: $draft.variants)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(VaniScriptTheme.text0)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.hidden)
                        .padding(10)
                        .frame(height: 86)
                        .background(Color.black.opacity(0.24))
                        .background(ThinScrollbarTuner())
                        .overlay(ReviewFieldBorder())
                }

                VStack(alignment: .leading, spacing: 6) {
                    ReviewFieldLabel(text: "Apply To")
                    Picker("Apply to", selection: $draft.scope) {
                        ForEach(ReviewGlossaryScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(ReviewTextButtonStyle())
                    Button(draft.mode == .existing ? "Add Variant" : "Save Term") {
                        onSave(draft)
                    }
                    .buttonStyle(ReviewApproveButtonStyle())
                    .disabled(!canSave)
                }
            }
            .padding(22)
            .frame(width: 700)
            .background(Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 34, y: 20)
        }
    }

    private var existingTermSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReviewFieldLabel(text: "Find Existing Glossary Term")
            HStack(spacing: 8) {
                Picker("Category", selection: $draft.categoryFilter) {
                    Text("All categories").tag("all")
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .frame(width: 190)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(VaniScriptTheme.text2)
                    TextField("Type to find an existing term or wrong variant...", text: $draft.search)
                        .textFieldStyle(.plain)
                        .foregroundStyle(VaniScriptTheme.text0)
                }
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(Color.black.opacity(0.24))
                .overlay(ReviewFieldBorder())
            }

            ScrollView {
                ThinScrollbarTuner()
                    .frame(width: 0, height: 0)

                LazyVStack(spacing: 6) {
                    if filteredEntries.isEmpty {
                        Text(draft.search.isEmpty && draft.categoryFilter == "all"
                             ? "Choose a category or type in the search field to find an existing glossary term."
                             : "No matching term. Switch to Create New Term if this is new terminology.")
                            .font(.system(size: 12))
                            .foregroundStyle(VaniScriptTheme.text2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    } else {
                        ForEach(filteredEntries) { entry in
                            Button {
                                draft.existingEntryID = entry.id
                                draft.source = entry.source
                                draft.translation = entry.translation
                                draft.category = entry.category ?? ""
                                draft.search = entry.source
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.source)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(VaniScriptTheme.text0)
                                    Text("\(entry.translation.isEmpty ? "No translation" : entry.translation)\(entry.category.map { " · \($0)" } ?? "")")
                                        .font(.system(size: 11))
                                        .foregroundStyle(VaniScriptTheme.text2)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(draft.existingEntryID == entry.id ? VaniScriptTheme.accent.opacity(0.12) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(draft.existingEntryID == entry.id ? VaniScriptTheme.accent.opacity(0.42) : Color.clear, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(4)
            }
            .frame(height: 170)
            .scrollIndicators(.hidden)
            .background(Color.black.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let selectedEntry {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedEntry.source)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.text0)
                    Text(selectedEntry.translation.isEmpty ? "No translation" : selectedEntry.translation)
                        .font(.system(size: 12))
                        .foregroundStyle(VaniScriptTheme.text2)
                    if let category = selectedEntry.category, !category.isEmpty {
                        Text(category)
                            .font(.system(size: 11))
                            .foregroundStyle(VaniScriptTheme.text2)
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VaniScriptTheme.accent.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(VaniScriptTheme.accent.opacity(0.28), lineWidth: 1)
                )
            } else {
                Text("Select the existing term that should receive the new wrong variant.")
                    .font(.system(size: 12))
                    .foregroundStyle(VaniScriptTheme.text1)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(VaniScriptTheme.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private var newTermSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    ReviewFieldLabel(text: "Correct Source Term")
                    ReviewTextField(text: $draft.source, placeholder: "Jayapataka Maharaja")
                }
                VStack(alignment: .leading, spacing: 6) {
                    ReviewFieldLabel(text: "Correct Translation")
                    ReviewTextField(text: $draft.translation, placeholder: "Джаяпатака Махарадж")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ReviewFieldLabel(text: "Category")
                ReviewTextField(text: $draft.category, placeholder: "Acharyas / Teachers, Sacred places...")
            }
        }
    }
}

private struct ReviewModalBackdrop<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255)
                .opacity(0.74)
                .ignoresSafeArea()
            content
        }
        .zIndex(50)
    }
}

private struct ReviewFieldLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(VaniScriptTheme.text2)
    }
}

private struct ReviewTextField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(VaniScriptTheme.text0)
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(Color.black.opacity(0.24))
            .overlay(ReviewFieldBorder())
    }
}

private struct ReviewFieldBorder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(Color.white.opacity(0.12), lineWidth: 1)
    }
}



private struct DualTimedReviewPane: View {
    @EnvironmentObject private var store: WorkflowStore
    let metadata: AudioMetadata
    let translationTitle: String
    let translationLanguage: String
    let sourceCues: [TranscriptCue]
    let targetCues: [TranscriptCue]
    let playbackTime: Double
    let updateSourceCue: (TranscriptCue.ID, String) -> Void
    let updateTargetCue: (TranscriptCue.ID, String) -> Void
    let exportSource: () -> Void
    let exportTarget: () -> Void
    let polishTarget: () -> Void
    let beginInlineEdit: (TranscriptCue.ID, TranscriptSide, String, String) -> Void
    let beginGlossaryDraft: (String, TranscriptSide) -> Void

    @State private var isSourceCopied = false
    @State private var isTargetCopied = false

    private var pairedCues: [PairedCue] {
        sourceCues.enumerated().compactMap { index, source in
            guard targetCues.indices.contains(index) else { return nil }
            return PairedCue(source: source, target: targetCues[index])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                paneHeader(title: "ORIGINAL TRANSCRIPTION", accent: false, exportAction: exportSource, polishAction: nil, isCopied: $isSourceCopied) {
                    let text = sourceCues.map(\.text).joined(separator: "\n\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    withAnimation(.easeInOut(duration: 0.15)) { isSourceCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.15)) { isSourceCopied = false }
                    }
                }
                .frame(maxWidth: .infinity)
                .onboardingTarget("review-pane-original")

                paneHeader(title: translationTitle, accent: true, exportAction: exportTarget, polishAction: polishTarget, isCopied: $isTargetCopied) {
                    let text = targetCues.map(\.text).joined(separator: "\n\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    withAnimation(.easeInOut(duration: 0.15)) { isTargetCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.15)) { isTargetCopied = false }
                    }
                }
                .frame(maxWidth: .infinity)
                .onboardingTarget("review-pane-translation")
            }
            .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1), alignment: .bottom)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ThinScrollbarTuner()
                            .frame(width: 0, height: 0)

                        HStack(alignment: .top, spacing: 10) {
                            MetadataBlock(metadata: metadata, language: nil)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            MetadataBlock(metadata: metadata, language: translationLanguage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.bottom, 4)

                        ForEach(pairedCues) { pair in
                            HStack(alignment: .top, spacing: 10) {
                                TimedCueEditor(
                                    cue: pair.source,
                                    isActive: playbackTime >= pair.source.startSec && playbackTime < pair.source.endSec,
                                    playbackTime: playbackTime,
                                    fontFamily: store.settings.fontFamily,
                                    fontSize: store.settings.fontSize,
                                    fontScale: store.settings.fontScale,
                                    accent: false,
                                    side: .original,
                                    updateCue: updateSourceCue,
                                    beginInlineEdit: beginInlineEdit,
                                    beginGlossaryDraft: beginGlossaryDraft
                                )
                                .frame(maxWidth: .infinity)

                                TimedCueEditor(
                                    cue: pair.target,
                                    isActive: playbackTime >= pair.source.startSec && playbackTime < pair.source.endSec,
                                    playbackTime: playbackTime,
                                    fontFamily: store.settings.fontFamily,
                                    fontSize: store.settings.fontSize,
                                    fontScale: store.settings.fontScale,
                                    accent: true,
                                    side: .translated,
                                    updateCue: updateTargetCue,
                                    beginInlineEdit: beginInlineEdit,
                                    beginGlossaryDraft: beginGlossaryDraft
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .id(pair.id)
                        }
                    }
                    .padding(14)
                }
                .onChange(of: playbackTime) { _, newValue in
                    guard let active = pairedCues.first(where: { newValue >= $0.source.startSec && newValue < $0.source.endSec }) else {
                        return
                    }
                    if store.synchronizedReviewCueID != active.id {
                        store.synchronizedReviewCueID = active.id
                    }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(active.id, anchor: .center)
                    }
                }
                .scrollIndicators(.hidden)
                .background(Color.dynamic(
                    light: Color(red: 235 / 255, green: 237 / 255, blue: 243 / 255).opacity(0.85),
                    dark: Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255).opacity(0.82)
                ))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .background(Color.black.opacity(0.02))
    }

    private func paneHeader(
        title: String,
        accent: Bool,
        exportAction: @escaping () -> Void,
        polishAction: (() -> Void)?,
        isCopied: Binding<Bool>,
        copyAction: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent ? VaniScriptTheme.accent : VaniScriptTheme.text2)
            Spacer()

            if let polishAction {
                Button(action: polishAction) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(VaniScriptTheme.accent)
                .help("Polish with MLX")
            }

            Button(action: copyAction) {
                Image(systemName: isCopied.wrappedValue ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCopied.wrappedValue ? VaniScriptTheme.green : VaniScriptTheme.text2)
            }
            .buttonStyle(.plain)
            .help(isCopied.wrappedValue ? "Copied!" : "Copy to clipboard")
            .animation(.easeInOut(duration: 0.15), value: isCopied.wrappedValue)

            Button(action: exportAction) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(VaniScriptTheme.text2)
            .help("Download")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private struct PairedCue: Identifiable {
        var id: TranscriptCue.ID { source.id }

        var source: TranscriptCue
        var target: TranscriptCue
    }
}

private struct MetadataBlock: View {
    let metadata: AudioMetadata
    let language: String?

    private var rows: [(String, String)] {
        let russian = language?.localizedCaseInsensitiveContains("russian") == true
        let empty = russian ? "Нет" : "None"
        return [
            (russian ? "Дата" : "Date", metadata.date.isEmpty ? empty : metadata.date),
            (russian ? "Место" : "Location", metadata.location.isEmpty ? empty : metadata.location),
            (russian ? "Лектор" : "Lecturer", metadata.lecturer.isEmpty ? empty : metadata.lecturer),
            (russian ? "Интервьюер / Участники" : "Interviewer / Participants", metadata.participants.isEmpty ? empty : metadata.participants),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.0) { row in
                Text("\(row.0): \(row.1)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(VaniScriptTheme.text1.opacity(0.84))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

private struct ReviewTextPane: View {
    @EnvironmentObject private var store: WorkflowStore
    let title: String
    let metadata: AudioMetadata
    let translationLanguage: String?
    @Binding var content: String
    let cues: [TranscriptCue]
    let playbackTime: Double
    let updateCue: (TranscriptCue.ID, String) -> Void
    let side: TranscriptSide
    let accent: Bool
    let exportAction: () -> Void
    let polishAction: (() -> Void)?
    let beginInlineEdit: (TranscriptCue.ID, TranscriptSide, String, String) -> Void
    let beginGlossaryDraft: (String, TranscriptSide) -> Void

    @State private var isCopied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent ? VaniScriptTheme.accent : VaniScriptTheme.text2)
                Spacer()

                // Real-time Interactive Font Style & Scale controls
                HStack(spacing: 8) {
                    Button(action: {
                        store.updateSettings { settings in
                            let all = FontFamily.allCases
                            if let idx = all.firstIndex(of: settings.fontFamily) {
                                let nextIdx = (idx + 1) % all.count
                                settings.fontFamily = all[nextIdx]
                            }
                        }
                    }) {
                        Image(systemName: "textformat.alt")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VaniScriptTheme.text2)
                    .help("Font Style: \(store.settings.fontFamily.rawValue.uppercased())")

                    Divider()
                        .frame(height: 10)
                        .background(Color.white.opacity(0.15))

                    HStack(spacing: 4) {
                        Button(action: {
                            store.updateSettings { settings in
                                settings.fontScale = max(0.5, settings.fontScale - 0.05)
                            }
                        }) {
                            Image(systemName: "textformat.size.smaller")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(VaniScriptTheme.text2)
                        .help("Decrease Size")

                        Text(String(format: "%.0f%%", store.settings.fontScale * 100))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(VaniScriptTheme.text2)
                            .frame(width: 32, alignment: .center)

                        Button(action: {
                            store.updateSettings { settings in
                                settings.fontScale = min(3.0, settings.fontScale + 0.05)
                            }
                        }) {
                            Image(systemName: "textformat.size.larger")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(VaniScriptTheme.text2)
                        .help("Increase Size")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer().frame(width: 4)

                if let polishAction {
                    Button(action: polishAction) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VaniScriptTheme.accent)
                    .help("Polish with MLX")
                }

                Button {
                    let text = cues.isEmpty
                        ? content
                        : cues.map(\.text).joined(separator: "\n\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    withAnimation(.easeInOut(duration: 0.15)) { isCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.15)) { isCopied = false }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isCopied ? VaniScriptTheme.green : VaniScriptTheme.text2)
                }
                .buttonStyle(.plain)
                .help(isCopied ? "Copied!" : "Copy to clipboard")
                .animation(.easeInOut(duration: 0.15), value: isCopied)

                Button(action: exportAction) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(VaniScriptTheme.text2)
                .help("Download")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1), alignment: .bottom)

            if cues.isEmpty {
                TextEditor(text: $content)
                    .font(.customAppFont(family: store.settings.fontFamily, size: store.settings.fontSize, scale: store.settings.fontScale))
                    .id("\(store.settings.fontFamily)-\(store.settings.fontSize)-\(store.settings.fontScale)")
                    .foregroundStyle(VaniScriptTheme.text0)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .padding(12)
                    .background(Color.dynamic(
                        light: Color(red: 235 / 255, green: 237 / 255, blue: 243 / 255).opacity(0.85),
                        dark: Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255).opacity(0.82)
                    ))
                    .background(ThinScrollbarTuner())
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 8) {
                            ThinScrollbarTuner()
                                .frame(width: 0, height: 0)

                            MetadataBlock(metadata: metadata, language: translationLanguage)
                                .padding(.bottom, 4)

                            ForEach(cues) { cue in
                                TimedCueEditor(
                                    cue: cue,
                                    isActive: playbackTime >= cue.startSec && playbackTime < cue.endSec,
                                    playbackTime: playbackTime,
                                    fontFamily: store.settings.fontFamily,
                                    fontSize: store.settings.fontSize,
                                    fontScale: store.settings.fontScale,
                                    accent: accent,
                                    side: side,
                                    updateCue: updateCue,
                                    beginInlineEdit: beginInlineEdit,
                                    beginGlossaryDraft: beginGlossaryDraft
                                )
                                .id(cue.id)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(12)
                    }
                    .scrollPosition(id: $store.synchronizedReviewCueID, anchor: .center)
                    .onChange(of: playbackTime) { _, newValue in
                        if let active = cues.first(where: { newValue >= $0.startSec && newValue < $0.endSec }) {
                            if store.synchronizedReviewCueID != active.id {
                                store.synchronizedReviewCueID = active.id
                            }
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo(active.id, anchor: .center)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .background(Color.dynamic(
                        light: Color(red: 235 / 255, green: 237 / 255, blue: 243 / 255).opacity(0.85),
                        dark: Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255).opacity(0.82)
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1), alignment: .trailing)
    }
}

private struct SelectionAwareCueTextView: NSViewRepresentable {
    @Binding var text: String
    let words: [TranscriptWord]?
    let isActive: Bool
    let playbackTime: Double
    let fontFamily: FontFamily
    let fontSize: FontSize
    let fontScale: Double
    let accent: Bool
    let side: TranscriptSide
    let cueID: TranscriptCue.ID
    let beginInlineEdit: (TranscriptCue.ID, TranscriptSide, String, String) -> Void
    let beginGlossaryDraft: (String, TranscriptSide) -> Void
    let retranslateCue: (TranscriptCue.ID) -> Void
    let polishSelection: (TranscriptCue.ID, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = CueNSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.textColor = NSColor(VaniScriptTheme.text0).withAlphaComponent(0.92)
        textView.insertionPointColor = NSColor(VaniScriptTheme.text0)
        textView.font = nsFont(family: fontFamily, size: fontSize, scale: fontScale)
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.contextMenuProvider = { [weak coordinator = context.coordinator] in
            coordinator?.makeContextMenu()
        }

        context.coordinator.textView = textView
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? CueNSTextView else { return }
        context.coordinator.textView = textView
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selectedRange.location <= (text as NSString).length ? selectedRange : NSRange(location: 0, length: 0))

            // Invalidate cached properties in coordinator
            context.coordinator.cachedText = ""
            context.coordinator.lastIsActive = nil
            context.coordinator.lastActiveWordIDs = []
            context.coordinator.lastBaseFont = nil
            context.coordinator.lastBaseColor = nil
        }
        textView.font = nsFont(family: fontFamily, size: fontSize, scale: fontScale)
        applyKaraokeAttributes(to: textView, context: context)
    }

    private func applyKaraokeAttributes(to textView: NSTextView, context: Context) {
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        guard fullRange.length > 0 else { return }

        let baseColor = NSColor(VaniScriptTheme.text0).withAlphaComponent(isActive ? 0.90 : 0.32)
        let baseFont = nsFont(family: fontFamily, size: fontSize, scale: fontScale)

        let resolvedWords: [TranscriptWord]
        if let words = words, !words.isEmpty {
            resolvedWords = words
        } else {
            let parts = cueID.components(separatedBy: "-")
            if parts.count >= 2,
               let startSec = Double(parts[0]),
               let endSec = Double(parts[1]) {
                let text = textView.string
                let splitWords = text.split(whereSeparator: \.isWhitespace).map(String.init)
                let duration = max(0.05, endSec - startSec)
                let step = duration / Double(max(1, splitWords.count))
                resolvedWords = splitWords.enumerated().map { idx, w in
                    let start = startSec + Double(idx) * step
                    let end = idx == splitWords.count - 1 ? endSec : min(endSec, start + step)
                    return TranscriptWord(startSec: start, endSec: max(start + 0.03, end), text: w)
                }
            } else {
                resolvedWords = []
            }
        }

        let activeWords = isActive ? resolvedWords.filter { playbackTime >= $0.startSec && playbackTime < $0.endSec } : []
        let activeWordIDs = Set(activeWords.map(\.id))

        let coordinator = context.coordinator
        if coordinator.lastIsActive == isActive &&
           coordinator.lastActiveWordIDs == activeWordIDs &&
           coordinator.lastBaseFont == baseFont &&
           coordinator.lastBaseColor == baseColor &&
           coordinator.cachedText == textView.string &&
           coordinator.cachedResolvedWords == resolvedWords {
            return
        }

        // Cache resolution of ranges if needed
        var wordRanges: [NSRange] = []
        if coordinator.cachedText == textView.string && coordinator.cachedResolvedWords == resolvedWords {
            wordRanges = coordinator.cachedWordRanges
        } else {
            var searchStart = textView.string.startIndex
            for word in resolvedWords {
                let cleanedWord = word.text.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                if cleanedWord.isEmpty {
                    wordRanges.append(NSRange(location: NSNotFound, length: 0))
                    continue
                }
                if let range = textView.string.range(
                    of: cleanedWord,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<textView.string.endIndex
                ) {
                    searchStart = range.upperBound
                    wordRanges.append(NSRange(range, in: textView.string))
                } else {
                    wordRanges.append(NSRange(location: NSNotFound, length: 0))
                }
            }
            coordinator.cachedText = textView.string
            coordinator.cachedResolvedWords = resolvedWords
            coordinator.cachedWordRanges = wordRanges
        }

        // Apply attributes
        textView.textStorage?.setAttributes([
            .font: baseFont,
            .foregroundColor: baseColor,
        ], range: fullRange)

        if isActive && !resolvedWords.isEmpty && !activeWords.isEmpty {
            for (idx, word) in resolvedWords.enumerated() {
                guard idx < wordRanges.count else { break }
                let nsRange = wordRanges[idx]
                guard nsRange.location != NSNotFound else { continue }
                guard activeWordIDs.contains(word.id) else { continue }

                let highlightFg = NSColor(Color.dynamic(
                    light: Color(red: 180 / 255, green: 90 / 255, blue: 0 / 255),
                    dark: Color(red: 245 / 255, green: 166 / 255, blue: 35 / 255)
                ))
                let highlightBg = NSColor(Color.dynamic(
                    light: Color(red: 245 / 255, green: 166 / 255, blue: 35 / 255).opacity(0.35),
                    dark: Color(red: 245 / 255, green: 166 / 255, blue: 35 / 255).opacity(accent ? 0.22 : 0.18)
                ))

                textView.textStorage?.addAttributes([
                    .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .bold),
                    .foregroundColor: highlightFg,
                    .backgroundColor: highlightBg,
                ], range: nsRange)
            }
        }

        coordinator.lastIsActive = isActive
        coordinator.lastActiveWordIDs = activeWordIDs
        coordinator.lastBaseFont = baseFont
        coordinator.lastBaseColor = baseColor
        textView.needsDisplay = true
    }

    private func nsFont(family: FontFamily, size: FontSize, scale: Double) -> NSFont {
        let baseSize: CGFloat
        switch size {
        case .sm: baseSize = 11
        case .md: baseSize = 13
        case .lg: baseSize = 15
        case .xl: baseSize = 18
        }
        let finalSize = baseSize * CGFloat(scale)
        switch family {
        case .mono:
            return NSFont.monospacedSystemFont(ofSize: finalSize, weight: .regular)
        case .sans:
            return NSFont.systemFont(ofSize: finalSize, weight: .regular)
        case .serif:
            return NSFont(name: "Times New Roman", size: finalSize) ?? NSFont.systemFont(ofSize: finalSize, weight: .regular)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectionAwareCueTextView
        weak var textView: CueNSTextView?

        // Caching variables for karaoke optimization
        var cachedText: String = ""
        var cachedResolvedWords: [TranscriptWord] = []
        var cachedWordRanges: [NSRange] = []

        var lastIsActive: Bool?
        var lastActiveWordIDs: Set<String> = []
        var lastBaseFont: NSFont?
        var lastBaseColor: NSColor?

        init(_ parent: SelectionAwareCueTextView) {
            self.parent = parent
        }

        func makeContextMenu() -> NSMenu? {
            let selected = selectedString()
            let menu = NSMenu()

            let inlineItem = NSMenuItem(title: "Inline Edit", action: #selector(inlineEdit), keyEquivalent: "")
            inlineItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
            inlineItem.target = self
            menu.addItem(inlineItem)
            menu.addItem(.separator())

            let retranslateItem = NSMenuItem(title: "Audio-Aware Review", action: #selector(retranslateCue), keyEquivalent: "")
            retranslateItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            retranslateItem.target = self
            menu.addItem(retranslateItem)

            if parent.side == .translated, !selected.isEmpty {
                let polishItem = NSMenuItem(title: "Polish Selection", action: #selector(polishSelection), keyEquivalent: "")
                polishItem.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
                polishItem.target = self
                menu.addItem(polishItem)
            }

            if !selected.isEmpty {
                menu.addItem(.separator())
                let addItem = NSMenuItem(title: "Add to Glossary", action: #selector(addToGlossary), keyEquivalent: "")
                addItem.image = NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: nil)
                addItem.target = self
                menu.addItem(addItem)
            }

            return menu.items.isEmpty ? nil : menu
        }

        @objc private func addToGlossary() {
            let selected = selectedString()
            guard !selected.isEmpty else { return }
            parent.beginGlossaryDraft(selected, parent.side)
        }

        @objc private func inlineEdit() {
            let selected = selectedString()
            let fallback = parent.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = selected.isEmpty ? fallback : selected
            guard !snippet.isEmpty else { return }
            parent.beginInlineEdit(parent.cueID, parent.side, snippet, parent.text)
        }

        @objc private func retranslateCue() {
            parent.retranslateCue(parent.cueID)
        }

        @objc private func polishSelection() {
            let selected = selectedString()
            guard !selected.isEmpty else { return }
            parent.polishSelection(parent.cueID, selected)
        }

        private func selectedString() -> String {
            guard let textView else { return "" }
            let range = textView.selectedRange()
            guard range.length > 0,
                  let swiftRange = Range(range, in: textView.string)
            else { return "" }
            return String(textView.string[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

private final class CueNSTextView: NSTextView {
    var contextMenuProvider: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?() ?? super.menu(for: event)
    }
}

private struct TimedCueEditor: View {
    @EnvironmentObject private var store: WorkflowStore
    let cue: TranscriptCue
    let isActive: Bool
    let playbackTime: Double
    let fontFamily: FontFamily
    let fontSize: FontSize
    let fontScale: Double
    let accent: Bool
    let side: TranscriptSide
    let updateCue: (TranscriptCue.ID, String) -> Void
    let beginInlineEdit: (TranscriptCue.ID, TranscriptSide, String, String) -> Void
    let beginGlossaryDraft: (String, TranscriptSide) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(timeRange(cue))
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundStyle(isActive ? VaniScriptTheme.accent : VaniScriptTheme.text2.opacity(0.82))
                .frame(width: 112, alignment: .leading)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                SelectionAwareCueTextView(
                    text: Binding(
                        get: { cue.text },
                        set: { updateCue(cue.id, $0) }
                    ),
                    words: cue.words,
                    isActive: isActive,
                    playbackTime: playbackTime,
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    fontScale: fontScale,
                    accent: accent,
                    side: side,
                    cueID: cue.id,
                    beginInlineEdit: beginInlineEdit,
                    beginGlossaryDraft: beginGlossaryDraft,
                    retranslateCue: store.retranslateCue,
                    polishSelection: store.polishTranslatedSelection
                )
                .frame(minHeight: estimatedTextHeight)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: isActive
                    ? [VaniScriptTheme.accent.opacity(0.18), VaniScriptTheme.accent.opacity(0.10), VaniScriptTheme.accent.opacity(0.04)]
                    : [Color.white.opacity(0.018), Color.white.opacity(0.018)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? VaniScriptTheme.accent.opacity(0.40) : Color.white.opacity(0.055), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func timeRange(_ cue: TranscriptCue) -> String {
        "\(formatClock(cue.startSec))-\(formatClock(cue.endSec))"
    }

    private var estimatedTextHeight: CGFloat {
        let lineCount = max(1, Int(ceil(Double(max(1, cue.text.count)) / 84.0)))
        let baseSize: CGFloat
        switch fontSize {
        case .sm: baseSize = 11
        case .md: baseSize = 13
        case .lg: baseSize = 15
        case .xl: baseSize = 18
        }
        return max(32, CGFloat(lineCount) * baseSize * CGFloat(fontScale) * 1.55)
    }

    private func formatClock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

private struct ReviewIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? VaniScriptTheme.accent : VaniScriptTheme.text1)
            .frame(width: 30, height: 30)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ReviewTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(VaniScriptTheme.text1)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ReviewApproveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color(red: 10 / 255, green: 10 / 255, blue: 18 / 255))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(configuration.isPressed ? VaniScriptTheme.accentHover : VaniScriptTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SearchReplaceDraft: Identifiable, Equatable {
    let id = UUID()
    var searchQuery: String = ""
    var replacementText: String = ""
    var targetSide: TranscriptSide = .original
    var caseSensitive: Bool = false
    var wholeWord: Bool = false
}

private struct SearchMatch: Identifiable, Equatable {
    let id = UUID()
    let chunkIndex: Int
    let startSec: Double
    let endSec: Double
    let text: String
    let ranges: [NSRange]
}

private struct SearchMatchRow: View {
    let match: SearchMatch
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Segment \(match.chunkIndex + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.accent)
                    Spacer()
                    Text(formatClock(match.startSec) + " - " + formatClock(match.endSec))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(VaniScriptTheme.text2)
                }

                HighlightTextView(text: match.text, ranges: match.ranges)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(VaniScriptTheme.text1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? VaniScriptTheme.accent.opacity(0.42) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func formatClock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

private struct SearchReplaceModal: View {
    @Binding var draft: SearchReplaceDraft
    @EnvironmentObject private var store: WorkflowStore
    let onCancel: () -> Void
    let onReplaceAll: (SearchReplaceDraft) -> Void

    private var currentChunkIndex: Int? {
        store.workflow.session?.currentChunkIndex
    }

    private func selectMatch(_ match: SearchMatch) {
        if var session = store.workflow.session {
            session.currentChunkIndex = match.chunkIndex
            store.workflow.session = session
            store.selectChunkIndex(match.chunkIndex)
        }
    }

    private var matches: [SearchMatch] {
        guard let session = store.session else { return [] }
        let query = draft.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let pattern: String
        if draft.wholeWord {
            pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: query) + "(?![\\p{L}\\p{N}_])"
        } else {
            pattern = NSRegularExpression.escapedPattern(for: query)
        }

        let options: NSRegularExpression.Options = draft.caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        var list: [SearchMatch] = []
        for chunk in session.chunks {
            let textToSearch: String
            switch draft.targetSide {
            case .original:
                textToSearch = chunk.original
            case .translated:
                textToSearch = chunk.translated
            }

            let nsRange = NSRange(textToSearch.startIndex..<textToSearch.endIndex, in: textToSearch)
            let results = regex.matches(in: textToSearch, range: nsRange)
            if !results.isEmpty {
                list.append(SearchMatch(
                    chunkIndex: chunk.index,
                    startSec: chunk.startSec,
                    endSec: chunk.endSec,
                    text: textToSearch,
                    ranges: results.map { $0.range }
                ))
            }
        }
        return list
    }

    var body: some View {
        ReviewModalBackdrop {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Global Search & Replace")
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                }
                .foregroundStyle(VaniScriptTheme.text0)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        ReviewFieldLabel(text: "Find Text")
                        ReviewTextField(text: $draft.searchQuery, placeholder: "Search for word or phrase...")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ReviewFieldLabel(text: "Replace With")
                        ReviewTextField(text: $draft.replacementText, placeholder: "Replacement text...")
                    }
                }

                HStack(spacing: 16) {
                    Toggle(isOn: $draft.caseSensitive) {
                        Text("Match Case")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VaniScriptTheme.text1)
                    }
                    .toggleStyle(.checkbox)

                    Toggle(isOn: $draft.wholeWord) {
                        Text("Whole Word")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VaniScriptTheme.text1)
                    }
                    .toggleStyle(.checkbox)

                    Spacer()

                    HStack(spacing: 8) {
                        Text("Search Target:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VaniScriptTheme.text1)

                        Picker("Search Target", selection: $draft.targetSide) {
                            Text("Original").tag(TranscriptSide.original)
                            if store.session?.selectedTranslationLanguage != nil {
                                Text("Translation").tag(TranscriptSide.translated)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }

                HStack {
                    Text("MATCHES FOUND: \(matches.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.text2)
                    Spacer()
                }
                .padding(.top, 4)

                ScrollView {
                    ThinScrollbarTuner()
                        .frame(width: 0, height: 0)

                    LazyVStack(spacing: 6) {
                        if matches.isEmpty {
                            Text(draft.searchQuery.isEmpty ? "Enter search text to begin." : "No matches found.")
                                .font(.system(size: 12))
                                .foregroundStyle(VaniScriptTheme.text2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        } else {
                            ForEach(matches) { match in
                                SearchMatchRow(
                                    match: match,
                                    isSelected: currentChunkIndex == match.chunkIndex,
                                    action: { selectMatch(match) }
                                )
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(height: 220)
                .background(Color.black.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(ReviewTextButtonStyle())
                    Button("Replace All") {
                        onReplaceAll(draft)
                    }
                    .buttonStyle(ReviewApproveButtonStyle())
                    .disabled(matches.isEmpty)
                }
            }
            .padding(22)
            .frame(width: 700)
            .background(Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 34, y: 20)
        }
    }
}

private struct HighlightTextView: View {
    let text: String
    let ranges: [NSRange]

    var body: some View {
        highlightedText
            .font(.system(size: 12))
            .lineLimit(2)
    }

    private var highlightedText: Text {
        let sortedRanges = ranges.sorted(by: { $0.location < $1.location })
        var lastIndex = 0
        var result = Text("")

        for range in sortedRanges {
            if let swiftRange = Range(range, in: text) {
                let prefixStart = text.index(text.startIndex, offsetBy: lastIndex)
                let prefix = String(text[prefixStart..<swiftRange.lowerBound])
                if !prefix.isEmpty {
                    result = result + Text(prefix)
                }

                let match = String(text[swiftRange])
                result = result + Text(match)
                    .bold()
                    .foregroundColor(VaniScriptTheme.accent)

                lastIndex = range.location + range.length
            }
        }

        let suffixStart = text.index(text.startIndex, offsetBy: lastIndex)
        let suffix = String(text[suffixStart...])
        if !suffix.isEmpty {
            result = result + Text(suffix)
        }

        return result
    }
}
