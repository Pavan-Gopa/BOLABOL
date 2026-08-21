import AppKit
import CryptoKit
import SwiftUI
import VaniScriptCore

struct ReviewWorkspaceView: View {
    @EnvironmentObject private var store: WorkflowStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.undoManager) private var undoManager
    @State private var keyMonitor: Any?
    @State private var documentScrollCoordinator = DocumentDualScrollCoordinator()
    @State private var editDraft: ReviewEditDraft?
    @State private var glossaryDraft: ReviewGlossaryDraft?
    @State private var searchReplaceDraft: SearchReplaceDraft?
    @State private var replaceEverywhereDraft: ReplaceEverywhereDraft?
    @StateObject private var proofreading = ProofreadingHighlightController()
    /// Bumps on every chunk open (Previous / Approve & Next / jump) so both
    /// panes force-scroll to the top of the new chunk content.
    @State private var chunkOpenToken: Int = 0

    var body: some View {
        if let session = store.session, let chunk = store.currentChunk {
            let documentPresentation = DocumentReviewPresentationPolicy.make(session: session, chunk: chunk)
            let isDocument = documentPresentation != nil
            let activeLanguage = session.selectedTranslationLanguage
            // Linked dual-scroll stays on in Dual View, including Proof Mode.
            // Unit jumps scroll both panes to their own ranges; wheel scroll
            // keeps them linked via direct same-tree attach.
            let documentScrollEnabled = isDocument
                && store.viewMode == .dual
                && activeLanguage != nil
            let documentScrollScope = documentPresentation.map { _ in
                DocumentScrollScope(
                    documentID: documentScrollIdentity(session),
                    chunkID: chunk.id,
                    language: activeLanguage ?? session.targetLang
                )
            }
            ZStack {
                VStack(spacing: 0) {
                    topBar(session: session, chunk: chunk, documentPresentation: documentPresentation)
                    if proofreading.isEnabled, documentPresentation != nil {
                        proofreadingModeBanner
                    }
                    if !isDocument {
                        audioBar(session: session, chunk: chunk)
                    }
                    thinProgress(session: session)
                    panes(
                        session: session,
                        chunk: chunk,
                        documentPresentation: documentPresentation,
                        documentScrollEnabled: documentScrollEnabled,
                        documentScrollScope: documentScrollScope
                    )
                    actionBar(session: session, chunk: chunk, documentPresentation: documentPresentation)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VaniScriptTheme.barSurface)

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

                if let draft = replaceEverywhereDraft {
                    ReplaceEverywhereSheet(
                        draft: Binding(
                            get: { replaceEverywhereDraft ?? draft },
                            set: { replaceEverywhereDraft = $0 }
                        ),
                        onCancel: { replaceEverywhereDraft = nil },
                        onReplaceAll: { draft in
                            _ = store.replaceEverywhereInDocument(
                                query: draft.findText,
                                replacement: draft.replacementText,
                                side: draft.side,
                                options: .init(
                                    wholeWord: draft.wholeWord,
                                    caseSensitive: draft.caseSensitive,
                                    skipProtected: draft.skipProtected,
                                    saveAsGlossary: draft.saveAsGlossary
                                )
                            )
                            if draft.saveAsGlossary, draft.side == .translation {
                                // PRD §12.2: source term ambiguous — let the user
                                // finish the rule in the glossary draft.
                                beginGlossaryDraft(selectedText: draft.replacementText, side: .translated)
                            }
                            replaceEverywhereDraft = nil
                        }
                    )
                }
            }
            .onAppear(perform: installKeyMonitor)
            .onDisappear(perform: removeKeyMonitor)
            .onDisappear { documentScrollCoordinator.detach() }
            .onAppear { store.documentUndoManager = undoManager }
            .onChange(of: documentScrollEnabled) { _, enabled in
                if !enabled {
                    documentScrollCoordinator.detach()
                }
            }
            .onChange(of: documentScrollScope) { _, scope in
                documentScrollCoordinator.setScope(scope)
            }
            .onChange(of: chunk.id) { _, _ in
                // Previous / Approve & Next / jump: open the new chunk from the top.
                chunkOpenToken &+= 1
                documentScrollCoordinator.resetToTop()
                // Proof mode: always restart highlight at the first unit.
                rebuildProofreadingUnits(session: session, chunk: chunk, startAtFirst: true)
            }
            .onChange(of: store.currentTranslationText) { _, _ in
                if proofreading.isEnabled {
                    // In-chunk edit: try to keep the current unit by id.
                    rebuildProofreadingUnits(session: session, chunk: chunk, startAtFirst: false)
                }
            }
            .onChange(of: store.viewMode) { _, mode in
                if mode != .dual, proofreading.isEnabled {
                    proofreading.disable()
                }
            }
            .onChange(of: proofreading.isEnabled) { _, enabled in
                if enabled {
                    // Entering proof mode: stay linked; pin both panes to the
                    // first unit via focusToken, not by tearing dual-scroll down.
                    documentScrollCoordinator.resetToTop()
                }
            }
            .onAppear {
                if proofreading.isEnabled {
                    rebuildProofreadingUnits(session: session, chunk: chunk, startAtFirst: true)
                }
            }
        } else {
            UploadWorkspaceView()
        }
    }

    private func topBar(session: SessionState, chunk: ChunkData, documentPresentation: DocumentReviewPresentation?) -> some View {
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
            if let presentation = DocumentReviewPresentationPolicy.make(session: session, chunk: chunk) {
                Text(presentation.displayLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.text2)
                    .lineLimit(1)
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
                            let cloudProviders = store.editingProviders.filter { $0.group == .cloud }
                            let localProviders = store.editingProviders.filter { $0.group == .local }
                            if !cloudProviders.isEmpty {
                                Section("Cloud") {
                                    ForEach(cloudProviders, id: \.id) { provider in
                                        Text(provider.label).tag(provider.id)
                                    }
                                }
                            }
                            if !localProviders.isEmpty {
                                Section("Local") {
                                    ForEach(localProviders, id: \.id) { provider in
                                        Text(provider.label).tag(provider.id)
                                    }
                                }
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(VaniScriptTheme.control)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(VaniScriptTheme.controlBorder, lineWidth: 1))
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

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if documentPresentation != nil {
                    Button {
                        toggleProofreadingHighlightMode(session: session, chunk: chunk)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "text.magnifyingglass")
                                .font(.system(size: 11, weight: .bold))
                            Text(proofreading.isEnabled ? "Proof Mode" : "Highlight")
                                .font(.system(size: 11, weight: .heavy))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .foregroundStyle(
                            proofreading.isEnabled
                            ? VaniScriptTheme.onAccent
                            : VaniScriptTheme.text1
                        )
                        .background(
                            proofreading.isEnabled
                            ? VaniScriptTheme.accent
                            : VaniScriptTheme.control
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    proofreading.isEnabled
                                    ? VaniScriptTheme.accent
                                    : VaniScriptTheme.controlBorder,
                                    lineWidth: 1
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(proofreading.isEnabled
                          ? "Exit proofreading highlight mode"
                          : "Proofreading highlight: sync source and translation units; navigate with arrow keys")
                    .disabled(store.viewMode != .dual || session.selectedTranslationLanguage == nil)
                    .opacity(store.viewMode == .dual && session.selectedTranslationLanguage != nil ? 1 : 0.45)
                }

                Button {
                    if session.sourceKind == .document {
                        // PRD §11: document sessions use Replace Everywhere, which
                        // operates on the canonical DocumentState. Media sessions
                        // keep the existing chunk-level Search & Replace modal.
                        replaceEverywhereDraft = ReplaceEverywhereDraft(
                            side: store.viewMode == .translated ? .translation : .source
                        )
                    } else {
                        searchReplaceDraft = SearchReplaceDraft(
                            searchQuery: "",
                            replacementText: "",
                            targetSide: store.viewMode == .translated ? .translated : .original,
                            caseSensitive: false,
                            wholeWord: false
                        )
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(ReviewIconButtonStyle())
                .help("Search & Replace")

                Button {
                    store.showChatSidebar.toggle()
                } label: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(store.showChatSidebar ? VaniScriptTheme.accent : VaniScriptTheme.text2)
                }
                .buttonStyle(ReviewIconButtonStyle())
                .help("AI Assistant")

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
        .background(VaniScriptTheme.barSurface)
        .overlay(Rectangle().fill(VaniScriptTheme.separator).frame(height: 1), alignment: .bottom)
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
                .foregroundStyle(VaniScriptTheme.onAccent)
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
        .background(VaniScriptTheme.surfaceSubtle)
        .overlay(Rectangle().fill(VaniScriptTheme.separator).frame(height: 1), alignment: .bottom)
        .onboardingTarget("review-audio-bar")
    }

    private func thinProgress(session: SessionState) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                VaniScriptTheme.control
                VaniScriptTheme.accent
                    .frame(width: proxy.size.width * reviewProgress(session))
            }
        }
        .frame(height: 2)
    }

    private func panes(
        session: SessionState,
        chunk: ChunkData,
        documentPresentation: DocumentReviewPresentation?,
        documentScrollEnabled: Bool,
        documentScrollScope: DocumentScrollScope?
    ) -> some View {
        let activeLanguage = session.selectedTranslationLanguage
        let hasTranslation = activeLanguage != nil
        return Group {
            if let presentation = documentPresentation {
                HStack(spacing: 0) {
                    if store.viewMode == .source || store.viewMode == .dual || !hasTranslation {
                        let sourceBlocks = store.currentDocumentSourceBlocks.map { block in
                            DocumentEditorBlockItem(
                                id: block.id,
                                spans: block.spans,
                                fallbackText: block.spans.map(\.text).joined()
                            )
                        }
                        ReviewTextPane(
                            title: "ORIGINAL DOCUMENT · \(presentation.displayLabel)",
                            metadata: session.metadata,
                            translationLanguage: nil,
                            content: Binding(
                                get: {
                                    let current = store.currentChunk?.original ?? ""
                                    return current.isEmpty
                                        ? DocumentReviewPresentationPolicy.visibleSourceText(session: session, chunk: chunk)
                                        : current
                                },
                                set: { store.updateCurrentOriginal($0) }
                            ),
                            cues: [],
                            playbackTime: 0,
                            updateCue: { _, _ in },
                            side: .original,
                            accent: false,
                            exportAction: { store.export(side: .original, format: store.outputFormat) },
                            polishAction: nil,
                            beginInlineEdit: beginInlineEdit,
                            beginGlossaryDraft: beginGlossaryDraft,
                            documentScrollCoordinator: documentScrollEnabled ? documentScrollCoordinator : nil,
                            documentScrollPane: documentScrollEnabled ? .source : nil,
                            documentScrollScope: documentScrollScope,
                            documentBlocks: sourceBlocks,
                            updateDocumentBlocks: { blocks, text in
                                store.updateCurrentDocumentSource(blocks: blocks.map { ($0.id, $0.spans, $0.fallbackText) }, text: text)
                            },
                            onReplaceEverywhere: { text, side in
                                replaceEverywhereDraft = ReplaceEverywhereDraft(findText: text, side: side)
                            },
                            proofreadingHighlightRange: proofreading.currentSourceRange,
                            proofreadingFocusToken: proofreading.focusToken,
                            chunkOpenToken: chunkOpenToken
                        )
                        .onboardingTarget("review-pane-original")
                    }

                    if hasTranslation, store.viewMode == .translated || store.viewMode == .dual {
                        let translatedBlocks = DocumentEditorBlockItem.translatedDisplayBlocks(
                            translated: store.currentDocumentTranslatedBlocks,
                            sourceBlocks: store.currentDocumentSourceBlocks
                        )
                        // PRD §9: show a review banner when any translated block in
                        // the current chunk no longer matches its source hash. The
                        // banner and the approve gate share one derivation.
                        let hasStaleTranslation = store.isCurrentDocumentChunkStale
                        VStack(spacing: 0) {
                            if hasStaleTranslation {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Source changed — translation needs review")
                                        .font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                }
                                .foregroundStyle(VaniScriptTheme.warningText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(VaniScriptTheme.warningSurface)
                                .overlay(Rectangle().fill(VaniScriptTheme.warningBorder).frame(height: 1), alignment: .bottom)
                            }
                            ReviewTextPane(
                                title: "TRANSLATED DOCUMENT · \((activeLanguage ?? session.targetLang).uppercased())",
                                metadata: session.metadata,
                                translationLanguage: activeLanguage ?? session.targetLang,
                                content: Binding(
                                    get: { store.currentTranslationText },
                                    set: { store.updateCurrentTranslated($0) }
                                ),
                                cues: [],
                                playbackTime: 0,
                                updateCue: { _, _ in },
                                side: .translated,
                                accent: true,
                                exportAction: { store.export(side: .translated, format: store.outputFormat) },
                                polishAction: nil,
                                beginInlineEdit: beginInlineEdit,
                                beginGlossaryDraft: beginGlossaryDraft,
                                documentScrollCoordinator: documentScrollEnabled ? documentScrollCoordinator : nil,
                                documentScrollPane: documentScrollEnabled ? .translated : nil,
                                documentScrollScope: documentScrollScope,
                                documentBlocks: translatedBlocks,
                                updateDocumentBlocks: { blocks, text in
                                    store.updateCurrentDocumentTranslated(blocks: blocks.map { ($0.id, $0.spans, $0.fallbackText) }, text: text)
                                },
                                onReplaceEverywhere: { text, side in
                                    replaceEverywhereDraft = ReplaceEverywhereDraft(findText: text, side: side)
                                },
                                proofreadingHighlightRange: proofreading.currentTranslatedRange,
                                proofreadingFocusToken: proofreading.focusToken,
                                chunkOpenToken: chunkOpenToken
                            )
                        }
                    }
                }
            } else if store.viewMode == .dual,
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

    @ViewBuilder
    private func actionBar(
        session: SessionState,
        chunk: ChunkData,
        documentPresentation: DocumentReviewPresentation?
    ) -> some View {
        if let presentation = documentPresentation {
            VStack(spacing: 0) {
                documentQualityPanel(chunk: chunk)
                documentActionBar(session: session, presentation: presentation)
            }
        } else {
            HStack {
            HStack(spacing: 10) {
                Text("Segment \(session.currentChunkIndex + 1) / \(session.chunks.count) · \(formatClock(chunk.startSec))-\(formatClock(chunk.endSec))")
                    .font(.system(size: 12))
                    .foregroundStyle(VaniScriptTheme.text2)

                ProgressView(value: reviewProgress(session))
                    .tint(VaniScriptTheme.accent)
                    .frame(width: 120)

                Text("\(store.approvedCount)/\(session.chunks.count) approved")
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
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
                    .foregroundStyle(VaniScriptTheme.text2)
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
        .background(VaniScriptTheme.barSurface)
        .overlay(Rectangle().fill(VaniScriptTheme.separator).frame(height: 1), alignment: .top)
    }
        }

    private func documentActionBar(
        session: SessionState,
        presentation: DocumentReviewPresentation
    ) -> some View {
        HStack {
            HStack(spacing: 10) {
                Text("\(presentation.displayLabel) · \(session.currentChunkIndex + 1) / \(session.chunks.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.text1)

                ProgressView(value: reviewProgress(session))
                    .tint(VaniScriptTheme.accent)
                    .frame(width: 120)

                Text("\(store.approvedCount)/\(session.chunks.count) approved")
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
            }
            Spacer()

            Button {
                store.retranslateCurrentDocumentChunk()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text(store.isDocumentTranslationActive ? "Retranslating" : "Retranslate Current")
                }
            }
            .buttonStyle(ReviewTextButtonStyle())
            .disabled(store.isDocumentTranslationActive)
            .help("Translate only the selected document chunk; the replacement requires manual approval.")

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
            .disabled(store.isCurrentDocumentChunkStale)
            .help(store.isCurrentDocumentChunkStale
                ? "The source changed — update the translation before approving this chunk."
                : "Approve this chunk and move to the next one.")
            .onboardingTarget("approve-next-btn")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(VaniScriptTheme.barSurface)
        .overlay(Rectangle().fill(VaniScriptTheme.separator).frame(height: 1), alignment: .top)
    }

    @ViewBuilder
    private func documentQualityPanel(chunk: ChunkData) -> some View {
        let errors = chunk.qualityReport?.errors ?? []
        let warnings = chunk.qualityReport?.warnings ?? []
        // Soft length-ratio noise alone is not worth a sticky bar.
        let actionableWarnings = warnings.filter { $0.code != "lengthRatio" }

        // Stale residue banners after a successful manual fix must disappear
        // even if an older qualityReport is still on disk.
        let translation = store.currentTranslationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let source = chunk.original.trimmingCharacters(in: .whitespacesAndNewlines)
        let translationLooksReal = TranslationArchive.isUsableTranslationText(translation)
            && (source.isEmpty || translation.caseInsensitiveCompare(source) != .orderedSame)
        let onlyResidue = !errors.isEmpty
            && errors.allSatisfy { $0.code == "languageResidue" }
            && actionableWarnings.isEmpty

        if onlyResidue && translationLooksReal {
            EmptyView()
        } else if !errors.isEmpty || !actionableWarnings.isEmpty {
            let isHardFailure = !errors.isEmpty
            let title = isHardFailure ? "Translation failed" : "Translation warning"
            let detail: String = {
                if errors.contains(where: {
                    $0.code == "languageResidue"
                        || $0.code == "translationFailed"
                        || $0.code == "provider"
                }) {
                    return "Try again — nothing was kept on the right."
                }
                return (errors + actionableWarnings).first?.message ?? "Try again."
            }()

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isHardFailure ? "xmark.octagon.fill" : "exclamationmark.circle")
                    .foregroundStyle(isHardFailure ? VaniScriptTheme.errorText : VaniScriptTheme.warningText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isHardFailure ? VaniScriptTheme.errorText : VaniScriptTheme.warningText)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(VaniScriptTheme.text1)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button {
                    store.retranslateCurrentDocumentChunk()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ReviewTextButtonStyle())
                .disabled(store.isDocumentTranslationActive)
                .help("Retry translation for this document chunk.")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isHardFailure ? VaniScriptTheme.errorSurface : VaniScriptTheme.warningSurface)
            .overlay(
                Rectangle()
                    .fill(isHardFailure ? VaniScriptTheme.errorBorder : VaniScriptTheme.warningBorder)
                    .frame(height: 1),
                alignment: .top
            )
        }
    }

    private func documentScrollIdentity(_ session: SessionState) -> String {
        if let sourceFile = session.sourceFile, !sourceFile.isEmpty {
            return sourceFile
        }
        if !session.sourceFileName.isEmpty {
            return session.sourceFileName
        }
        return "document"
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
        guard store.session?.sourceKind == .media else { return false }
        return !chunk.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func shouldShowRegenerateTimings(chunk: ChunkData) -> Bool {
        guard store.session?.sourceKind == .media else { return false }
        return !(chunk.originalCues ?? []).isEmpty
    }

    private var proofreadingModeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(VaniScriptTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Proofreading highlight")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(VaniScriptTheme.text0)
                Text(proofreading.statusLine)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VaniScriptTheme.text2)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Button {
                    proofreading.move(delta: -1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(ReviewIconButtonStyle())
                .disabled(proofreading.units.isEmpty)
                .help("Previous unit (↑ / ←)")

                Button {
                    proofreading.move(delta: 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(ReviewIconButtonStyle())
                .disabled(proofreading.units.isEmpty)
                .help("Next unit (↓ / →)")

                Button("Exit") {
                    proofreading.disable()
                }
                .buttonStyle(ReviewTextButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(VaniScriptTheme.proofreadingBannerBackground)
        .overlay(Rectangle().fill(VaniScriptTheme.proofreadingBannerBorder).frame(height: 1), alignment: .bottom)
    }


    private func toggleProofreadingHighlightMode(session: SessionState, chunk: ChunkData) {
        let sourceBlocks = store.currentDocumentSourceBlocks.map {
            DocumentProofreadingAlignment.BlockText(
                id: $0.id,
                text: $0.spans.map(\.text).joined()
            )
        }
        let translatedBlocks = DocumentEditorBlockItem.translatedDisplayBlocks(
            translated: store.currentDocumentTranslatedBlocks,
            sourceBlocks: store.currentDocumentSourceBlocks
        ).map {
            DocumentProofreadingAlignment.BlockText(
                id: $0.id,
                text: $0.spans.isEmpty ? $0.fallbackText : $0.spans.map(\.text).joined()
            )
        }
        let scope = "\(documentScrollIdentity(session))|\(chunk.id)|\(session.selectedTranslationLanguage ?? session.targetLang)"
        if let message = proofreading.toggle(
            canEnable: store.viewMode == .dual && session.selectedTranslationLanguage != nil,
            sourceBlocks: sourceBlocks,
            translatedBlocks: translatedBlocks,
            scopeKey: scope
        ) {
            store.statusMessage = message
        }
    }

    private func rebuildProofreadingUnits(
        session: SessionState,
        chunk: ChunkData,
        startAtFirst: Bool
    ) {
        guard proofreading.isEnabled else { return }
        let sourceBlocks = store.currentDocumentSourceBlocks.map {
            DocumentProofreadingAlignment.BlockText(
                id: $0.id,
                text: $0.spans.map(\.text).joined()
            )
        }
        let translatedBlocks = DocumentEditorBlockItem.translatedDisplayBlocks(
            translated: store.currentDocumentTranslatedBlocks,
            sourceBlocks: store.currentDocumentSourceBlocks
        ).map {
            DocumentProofreadingAlignment.BlockText(
                id: $0.id,
                text: $0.spans.isEmpty ? $0.fallbackText : $0.spans.map(\.text).joined()
            )
        }
        let scope = "\(documentScrollIdentity(session))|\(chunk.id)|\(session.selectedTranslationLanguage ?? session.targetLang)"
        proofreading.rebuild(
            sourceBlocks: sourceBlocks,
            translatedBlocks: translatedBlocks,
            scopeKey: scope,
            startAtFirst: startAtFirst
        )
    }


    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Spacebar still toggles media playback when not editing text.
            if event.keyCode == 49,
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               shouldHandlePlaybackSpacebar(event) {
                store.toggleCurrentChunkPlayback()
                return nil
            }

            guard proofreading.isEnabled,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            else { return event }

            // Arrow keys navigate proofreading units even while a text view has focus.
            switch event.keyCode {
            case 125, 124: // down, right
                proofreading.move(delta: 1)
                return nil
            case 126, 123: // up, left
                proofreading.move(delta: -1)
                return nil
            case 53: // escape
                proofreading.disable()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func shouldHandlePlaybackSpacebar(_ event: NSEvent) -> Bool {
        guard store.session?.sourceKind == .media, !store.isProcessingSegment else { return false }
        guard let firstResponder = event.window?.firstResponder else { return true }
        if firstResponder is NSTextView {
            return false
        }
        return true
    }

    private func formatPlayerClock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func formatClock(_ seconds: Double) -> String {
        formatPlayerClock(seconds)
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
                    .background(VaniScriptTheme.input)
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
            .background(VaniScriptTheme.modalSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(VaniScriptTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                                .foregroundStyle(draft.mode == mode ? VaniScriptTheme.onAccent : VaniScriptTheme.text2)
                                .background(draft.mode == mode ? VaniScriptTheme.accent : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(VaniScriptTheme.control)
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
                        .background(VaniScriptTheme.input)
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
            .background(VaniScriptTheme.modalSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(VaniScriptTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                .background(VaniScriptTheme.input)
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
            .background(VaniScriptTheme.surfaceSubtle)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(VaniScriptTheme.border, lineWidth: 1)
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
            .background(VaniScriptTheme.input)
            .overlay(ReviewFieldBorder())
    }
}

private struct ReviewFieldBorder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(VaniScriptTheme.controlBorder, lineWidth: 1)
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
            .overlay(Rectangle().fill(VaniScriptTheme.separator).frame(height: 1), alignment: .bottom)

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
                            .contextMenu {
                                Button {
                                    sendToAssistant(pair)
                                } label: {
                                    Label("Send to Assistant", systemImage: "sparkles")
                                }
                            }
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
                .background(VaniScriptTheme.editorSurface)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .background(Color.clear)
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

    private func sendToAssistant(_ pair: PairedCue) {
        let timeStr = formatLocalClock(pair.source.startSec) + " - " + formatLocalClock(pair.source.endSec)
        let msg = "Analyze segment (\(timeStr)):\n[EN]: \(pair.source.text)\n[RU]: \(pair.target.text)\n\n"
        store.chatInputText = msg
        withAnimation {
            store.showChatSidebar = true
        }
    }

    private func formatLocalClock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
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
    let documentScrollCoordinator: DocumentDualScrollCoordinator?
    let documentScrollPane: DocumentScrollPane?
    let documentScrollScope: DocumentScrollScope?
    let documentBlocks: [DocumentEditorBlockItem]
    let updateDocumentBlocks: (([DocumentEditorBlockItem], String) -> Void)?
    let onReplaceEverywhere: ((String, DocumentEditorSide) -> Void)?
    let proofreadingHighlightRange: NSRange?
    let proofreadingFocusToken: Int
    let chunkOpenToken: Int
    init(
        title: String,
        metadata: AudioMetadata,
        translationLanguage: String?,
        content: Binding<String>,
        cues: [TranscriptCue],
        playbackTime: Double,
        updateCue: @escaping (TranscriptCue.ID, String) -> Void,
        side: TranscriptSide,
        accent: Bool,
        exportAction: @escaping () -> Void,
        polishAction: (() -> Void)?,
        beginInlineEdit: @escaping (TranscriptCue.ID, TranscriptSide, String, String) -> Void,
        beginGlossaryDraft: @escaping (String, TranscriptSide) -> Void,
        documentScrollCoordinator: DocumentDualScrollCoordinator? = nil,
        documentScrollPane: DocumentScrollPane? = nil,
        documentScrollScope: DocumentScrollScope? = nil,
        documentBlocks: [DocumentEditorBlockItem] = [],
        updateDocumentBlocks: (([DocumentEditorBlockItem], String) -> Void)? = nil,
        documentSpans: [RichTextSpan] = [],
        updateDocumentSpans: (([RichTextSpan], String) -> Void)? = nil,
        onReplaceEverywhere: ((String, DocumentEditorSide) -> Void)? = nil,
        proofreadingHighlightRange: NSRange? = nil,
        proofreadingFocusToken: Int = 0,
        chunkOpenToken: Int = 0
    ) {
        self.title = title
        self.metadata = metadata
        self.translationLanguage = translationLanguage
        self._content = content
        self.cues = cues
        self.playbackTime = playbackTime
        self.updateCue = updateCue
        self.side = side
        self.accent = accent
        self.exportAction = exportAction
        self.polishAction = polishAction
        self.beginInlineEdit = beginInlineEdit
        self.beginGlossaryDraft = beginGlossaryDraft
        self.documentScrollCoordinator = documentScrollCoordinator
        self.documentScrollPane = documentScrollPane
        self.documentScrollScope = documentScrollScope
        self.onReplaceEverywhere = onReplaceEverywhere
        self.proofreadingHighlightRange = proofreadingHighlightRange
        self.proofreadingFocusToken = proofreadingFocusToken
        self.chunkOpenToken = chunkOpenToken
        if !documentBlocks.isEmpty || updateDocumentBlocks != nil {
            self.documentBlocks = documentBlocks
            self.updateDocumentBlocks = updateDocumentBlocks
        } else {
            self.documentBlocks = documentSpans.isEmpty ? [] : [DocumentEditorBlockItem(id: "block-0", spans: documentSpans, fallbackText: content.wrappedValue)]
            if let updateDocumentSpans {
                self.updateDocumentBlocks = { blocks, text in
                    updateDocumentSpans(blocks.flatMap(\.spans), text)
                }
            } else {
                self.updateDocumentBlocks = nil
            }
        }
    }

    @State private var isCopied = false

    /// Dual-scroll now binds directly from DocumentAttributedTextView.
    /// Keep a no-op placeholder so call sites compile without the old bridge.
    @ViewBuilder
    private var documentScrollBridge: some View {
        EmptyView()
    }
    private func requestSelectionTranslation(
        _ snapshot: DocumentTextSelectionSnapshot,
        coordinator: DocumentAttributedTextView.Coordinator
    ) {
        guard side == .translated else { return }
        guard let session = store.session,
              let documentState = session.documentState
        else {
            coordinator.setSelectionTranslationBusy(false)
            store.statusMessage = "AI selection retranslation is unavailable until the document state is loaded."
            return
        }

        let targetLanguage = session.selectedTranslationLanguage ?? session.targetLang
        let sourceBlocks = documentState.blocks
        let targetBlocks = store.currentDocumentTranslatedBlocks
        let profile = documentState.profile
        let providerID = store.editingProviderID
        let previousBlocks = coordinator.currentEditorBlocks()
        let previousText = coordinator.currentEditorText

        coordinator.setSelectionTranslationBusy(true, status: "Retranslating selection with AI…")
        store.statusMessage = "Retranslating selection with AI…"

        Task { @MainActor in
            do {
                let engine = try DocumentSelectionTranslationEngine.live(
                    settings: store.settings,
                    providerID: providerID
                )
                let outcome = try await engine.execute(
                    snapshot: snapshot,
                    sourceBlocks: sourceBlocks,
                    targetBlocks: targetBlocks,
                    profile: profile,
                    targetLanguage: targetLanguage,
                    currentTargetBlock: { blockID in
                        store.currentDocumentTranslatedBlocks.first {
                            $0.sourceBlockID == blockID || $0.id == blockID
                        }
                    },
                    apply: { updatedBlock in
                        store.updateCurrentDocumentTranslated(blocks: [
                            (
                                blockID: updatedBlock.sourceBlockID,
                                spans: updatedBlock.spans,
                                text: updatedBlock.text
                            )
                        ])
                        coordinator.renderExternalSelectionMutation(
                            updatedBlock,
                            previousBlocks: previousBlocks,
                            previousText: previousText
                        )
                    }
                )
                coordinator.setSelectionTranslationBusy(false, status: "Selection retranslated.")
                let warningSuffix = outcome.warningCodes.isEmpty
                    ? ""
                    : " Review warnings: \(outcome.warningCodes.joined(separator: ", "))."
                store.statusMessage = "Selection retranslated with \(outcome.providerID).\(warningSuffix)"
            } catch is CancellationError {
                coordinator.setSelectionTranslationBusy(false, status: "Selection retranslation cancelled.")
                store.statusMessage = "Selection retranslation cancelled."
            } catch let error as DocumentSelectionTranslationEngineError {
                coordinator.setSelectionTranslationBusy(false, status: error.localizedDescription)
                store.statusMessage = error.localizedDescription
                presentSelectionTranslationAlert(
                    title: "AI Selection Retranslation",
                    message: error.localizedDescription,
                    coordinator: coordinator
                )
            } catch {
                coordinator.setSelectionTranslationBusy(false, status: "Selection retranslation failed.")
                store.statusMessage = "Selection retranslation failed."
                presentSelectionTranslationAlert(
                    title: "AI Selection Retranslation",
                    message: "The selected editing provider failed. The original selection was preserved.",
                    coordinator: coordinator
                )
            }
        }
    }

    private func presentSelectionTranslationAlert(
        title: String,
        message: String,
        coordinator: DocumentAttributedTextView.Coordinator
    ) {
        guard let window = coordinator.textView?.window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

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
                        .background(VaniScriptTheme.separator)

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
                .background(VaniScriptTheme.control)
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
            .overlay(Rectangle().fill(VaniScriptTheme.separator).frame(height: 1), alignment: .bottom)

            if cues.isEmpty {
                DocumentAttributedTextView(
                    text: $content,
                    blocks: documentBlocks,
                    onBlocksChanged: updateDocumentBlocks,
                    onSelectionTranslation: side == .translated
                        ? { snapshot, coordinator in
                            requestSelectionTranslation(snapshot, coordinator: coordinator)
                        }
                        : nil,
                    fontFamily: store.settings.fontFamily,
                    fontSize: store.settings.fontSize,
                    fontScale: store.settings.fontScale,
                    side: side == .original ? .source : .translation,
                    onFocusLost: { store.flushAutosave() },
                    onReplaceEverywhere: onReplaceEverywhere,
                    proofreadingHighlightRange: proofreadingHighlightRange,
                    proofreadingFocusToken: proofreadingFocusToken,
                    chunkOpenToken: chunkOpenToken,
                    dualScrollCoordinator: documentScrollCoordinator,
                    dualScrollPane: documentScrollPane,
                    dualScrollScope: documentScrollScope
                )
                .id("\(store.settings.fontFamily)-\(store.settings.fontSize)-\(store.settings.fontScale)")
                .padding(12)
                .background(VaniScriptTheme.editorSurface)
                .background(ThinScrollbarTuner())
                .background(documentScrollBridge)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(VaniScriptTheme.border, lineWidth: 1)
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
                    .background(VaniScriptTheme.editorSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(VaniScriptTheme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(Rectangle().fill(VaniScriptTheme.separator).frame(width: 1), alignment: .trailing)
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
        reviewNSFont(family: family, size: size, scale: scale)
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
                    : [VaniScriptTheme.surfaceSubtle, VaniScriptTheme.surfaceSubtle],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? VaniScriptTheme.accent.opacity(0.40) : VaniScriptTheme.border, lineWidth: 1)
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
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.accent : VaniScriptTheme.text1)
                    : VaniScriptTheme.disabledText
            )
            .frame(width: 30, height: 30)
            .background(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.controlPressed : VaniScriptTheme.control)
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isEnabled ? VaniScriptTheme.controlBorder : VaniScriptTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ReviewTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? VaniScriptTheme.text1 : VaniScriptTheme.disabledText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.controlPressed : VaniScriptTheme.control)
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isEnabled ? VaniScriptTheme.controlBorder : VaniScriptTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ReviewApproveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(isEnabled ? VaniScriptTheme.onAccent : VaniScriptTheme.disabledText)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                isEnabled
                    ? (configuration.isPressed ? VaniScriptTheme.accentHover : VaniScriptTheme.accent)
                    : VaniScriptTheme.disabledSurface
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isEnabled ? Color.clear : VaniScriptTheme.controlBorder, lineWidth: 1)
            )
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

/// Draft state for the document-wide Replace Everywhere sheet (PRD §11.1).
private struct ReplaceEverywhereDraft: Identifiable, Equatable {
    let id = UUID()
    var findText: String = ""
    var replacementText: String = ""
    var side: DocumentEditorSide = .source
    var wholeWord: Bool = true
    var caseSensitive: Bool = false
    var skipProtected: Bool = true
    var saveAsGlossary: Bool = false
}

/// Document-wide Replace Everywhere sheet (PRD §11.1): live match counts over
/// the canonical DocumentState and a Replace button that is disabled for a
/// 0-match no-op (PRD §26.6).
private struct ReplaceEverywhereSheet: View {
    @Binding var draft: ReplaceEverywhereDraft
    @EnvironmentObject private var store: WorkflowStore
    let onCancel: () -> Void
    let onReplaceAll: (ReplaceEverywhereDraft) -> Void

    private var scope: DocumentSearchScope {
        switch draft.side {
        case .source:
            return .currentSourceDocument
        case .translation:
            let language = store.session?.selectedTranslationLanguage ?? store.session?.targetLang ?? ""
            return .currentTranslation(languageKey: TranslationArchive.languageKey(language))
        }
    }

    private var scopeLabel: String {
        switch draft.side {
        case .source:
            return "Scope: Current document — Source"
        case .translation:
            let language = store.session?.selectedTranslationLanguage ?? store.session?.targetLang ?? ""
            return "Scope: Current translation — \(language)"
        }
    }

    /// Live counts recomputed on every draft change; the engine compiles one
    /// regex per call (PRD §25).
    private var report: DocumentFindReplaceReport {
        guard let documentState = store.session?.documentState else {
            return DocumentFindReplaceReport()
        }
        return DocumentFindReplaceEngine.matches(
            in: documentState,
            scope: scope,
            query: draft.findText,
            options: DocumentFindReplaceOptions(
                wholeWord: draft.wholeWord,
                caseSensitive: draft.caseSensitive,
                skipProtected: draft.skipProtected
            )
        )
    }

    var body: some View {
        let report = report
        ReviewModalBackdrop {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Replace Everywhere")
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                }
                .foregroundStyle(VaniScriptTheme.text0)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        ReviewFieldLabel(text: "Find")
                        ReviewTextField(text: $draft.findText, placeholder: "Search for word or phrase...")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ReviewFieldLabel(text: "Replace")
                        ReviewTextField(text: $draft.replacementText, placeholder: "Replacement text...")
                    }
                }

                Text(scopeLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VaniScriptTheme.text2)

                HStack(spacing: 16) {
                    Toggle(isOn: $draft.wholeWord) {
                        Text("Whole word")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VaniScriptTheme.text1)
                    }
                    .toggleStyle(.checkbox)

                    Toggle(isOn: $draft.caseSensitive) {
                        Text("Case sensitive")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VaniScriptTheme.text1)
                    }
                    .toggleStyle(.checkbox)

                    Toggle(isOn: $draft.skipProtected) {
                        Text("Skip protected text")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VaniScriptTheme.text1)
                    }
                    .toggleStyle(.checkbox)

                    Toggle(isOn: $draft.saveAsGlossary) {
                        Text("Save as glossary rule")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VaniScriptTheme.text1)
                    }
                    .toggleStyle(.checkbox)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Found: \(report.foundCount) occurrences in \(report.blockCount) blocks")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VaniScriptTheme.text2)
                    if report.skippedProtectedCount > 0 {
                        Text("Skipped: \(report.skippedProtectedCount) protected")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VaniScriptTheme.warningText)
                    }
                    if report.skippedMixedStyleCount > 0 {
                        Text("Skipped: \(report.skippedMixedStyleCount) mixed-style")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VaniScriptTheme.warningText)
                    }
                }

                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(ReviewTextButtonStyle())
                    Button("Replace All \(report.foundCount)") {
                        onReplaceAll(draft)
                    }
                    .buttonStyle(ReviewApproveButtonStyle())
                    .disabled(report.foundCount == 0)
                }
            }
            .padding(22)
            .frame(width: 640)
            .background(VaniScriptTheme.modalSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(VaniScriptTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 34, y: 20)
        }
    }
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
            .background(VaniScriptTheme.surfaceSubtle)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? VaniScriptTheme.accent.opacity(0.42) : VaniScriptTheme.border, lineWidth: 1)
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
                .background(VaniScriptTheme.surfaceSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(VaniScriptTheme.border, lineWidth: 1)
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
            .background(VaniScriptTheme.modalSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(VaniScriptTheme.border, lineWidth: 1)
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

struct DocumentEditorBlockItem: Equatable, Sendable {
    var id: String
    var spans: [RichTextSpan]
    var fallbackText: String

    init(id: String, spans: [RichTextSpan], fallbackText: String = "") {
        self.id = id
        self.spans = spans
        self.fallbackText = fallbackText
    }
}

extension DocumentEditorBlockItem {
    /// Builds the translation-pane block list.
    /// - Empty translated spans → show source spans (export-compatible fallback).
    /// - Non-empty spans → keep translated text, but inherit explicit source
    ///   foreground colors by span id / preserved token text so retranslate
    ///   and Review always show source red/markers on the right.
    static func translatedDisplayBlocks(
        translated: [TranslatedBlock],
        sourceBlocks: [DocumentBlock]
    ) -> [DocumentEditorBlockItem] {
        let sourceSpansByBlockID = Dictionary(
            sourceBlocks.map { ($0.id, $0.spans) },
            uniquingKeysWith: { first, _ in first }
        )
        return translated.map { block in
            let sourceSpans = sourceSpansByBlockID[block.sourceBlockID] ?? []
            let spans: [RichTextSpan]
            if block.spans.isEmpty {
                spans = sourceSpans
            } else {
                spans = DocumentSourceColorTransfer.apply(
                    to: block.spans,
                    sourceSpans: sourceSpans
                )
            }
            return DocumentEditorBlockItem(
                id: block.sourceBlockID,
                spans: spans,
                fallbackText: block.text
            )
        }
    }
}

enum DocumentTextAttribute {
    static let blockID = NSAttributedString.Key("VaniScript.BlockID")
    static let spanID = NSAttributedString.Key("VaniScript.SpanID")
    static let styleKey = NSAttributedString.Key("VaniScript.StyleKey")
    static let translationPolicy = NSAttributedString.Key("VaniScript.TranslationPolicy")
    static let explicitColorHex = NSAttributedString.Key("VaniScript.ExplicitColorHex")
    static let isBlockSeparator = NSAttributedString.Key("VaniScript.IsBlockSeparator")
    static let inlineTraits = NSAttributedString.Key("VaniScript.InlineTraits")
}

public enum DocumentSelectionBridge {
    private static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Builds a structural selection snapshot from an attributed string and target selection range.
    public static func buildSnapshot(
        from attrString: NSAttributedString,
        selectedRange: NSRange,
        side: DocumentEditorSide,
        languageKey: String? = nil,
        chunkPlanID: String = "",
        targetRevisionHash: String = ""
    ) -> DocumentTextSelectionSnapshot {
        let nsString = attrString.string as NSString
        let fullLen = nsString.length
        let safeRange = NSRange(
            location: max(0, min(selectedRange.location, fullLen)),
            length: max(0, min(selectedRange.length, fullLen - max(0, min(selectedRange.location, fullLen))))
        )

        guard safeRange.length > 0 else {
            return DocumentTextSelectionSnapshot(
                side: side,
                languageKey: languageKey,
                chunkPlanID: chunkPlanID,
                fragments: [],
                selectedText: "",
                blockHashes: [:],
                targetRevisionHash: targetRevisionHash
            )
        }

        var spanStartOffsets: [String: Int] = [:]
        var blockTexts: [String: String] = [:]

        attrString.enumerateAttributes(in: NSRange(location: 0, length: fullLen), options: []) { attrs, range, _ in
            let isSeparator = attrs[DocumentTextAttribute.isBlockSeparator] as? Bool ?? false
            let blockID = attrs[DocumentTextAttribute.blockID] as? String ?? ""
            let spanID = attrs[DocumentTextAttribute.spanID] as? String

            if let spanID, !spanID.isEmpty, spanStartOffsets[spanID] == nil {
                spanStartOffsets[spanID] = range.location
            }

            if !isSeparator && !blockID.isEmpty {
                let piece = nsString.substring(with: range)
                blockTexts[blockID, default: ""] += piece
            }
        }

        var fragments: [DocumentTextFragment] = []
        var blockHashes: [String: String] = [:]

        attrString.enumerateAttributes(in: safeRange, options: []) { attrs, range, _ in
            let isSeparator = attrs[DocumentTextAttribute.isBlockSeparator] as? Bool ?? false
            guard !isSeparator else { return }

            let blockID = attrs[DocumentTextAttribute.blockID] as? String ?? ""
            let spanID = attrs[DocumentTextAttribute.spanID] as? String
            let styleKey = attrs[DocumentTextAttribute.styleKey] as? String ?? ""
            let translationPolicy = (attrs[DocumentTextAttribute.translationPolicy] as? String).flatMap(SpanTranslationPolicy.init(rawValue:)) ?? .translate
            let explicitColorHex = attrs[DocumentTextAttribute.explicitColorHex] as? String

            let traits: Set<InlineTrait>
            if let traitStrings = attrs[DocumentTextAttribute.inlineTraits] as? [String] {
                traits = Set(traitStrings.compactMap(InlineTrait.init(rawValue:)))
            } else if let traitArray = attrs[DocumentTextAttribute.inlineTraits] as? [Any] {
                traits = Set(traitArray.compactMap { ($0 as? String).flatMap(InlineTrait.init(rawValue:)) })
            } else if let traitSet = attrs[DocumentTextAttribute.inlineTraits] as? Set<InlineTrait> {
                traits = traitSet
            } else {
                traits = []
            }

            let runText = nsString.substring(with: range)
            guard !runText.isEmpty else { return }

            let spanStart = (spanID != nil) ? (spanStartOffsets[spanID!] ?? range.location) : range.location
            let offsetInSpan = max(0, range.location - spanStart)

            let fragment = DocumentTextFragment(
                blockID: blockID,
                spanID: spanID,
                utf16RangeInSpan: NSRange(location: offsetInSpan, length: range.length),
                text: runText,
                styleKey: styleKey,
                traits: traits,
                translationPolicy: translationPolicy,
                foregroundColorHex: explicitColorHex
            )
            fragments.append(fragment)

            if !blockID.isEmpty && blockHashes[blockID] == nil {
                let text = blockTexts[blockID] ?? ""
                blockHashes[blockID] = sha256Hex(text)
            }
        }

        let selectedText = fragments.map(\.text).joined()

        return DocumentTextSelectionSnapshot(
            side: side,
            languageKey: languageKey,
            chunkPlanID: chunkPlanID,
            fragments: fragments,
            selectedText: selectedText,
            blockHashes: blockHashes,
            targetRevisionHash: targetRevisionHash
        )
    }
}

struct DocumentAttributedTextView: NSViewRepresentable {
    @Binding var text: String
    let blocks: [DocumentEditorBlockItem]
    let onBlocksChanged: (([DocumentEditorBlockItem], String) -> Void)?
    let onSelectionTranslation: ((DocumentTextSelectionSnapshot, Coordinator) -> Void)?
    let fontFamily: FontFamily
    let fontSize: FontSize
    let fontScale: Double
    let side: DocumentEditorSide
    let onFocusLost: (() -> Void)?
    let onReplaceEverywhere: ((String, DocumentEditorSide) -> Void)?
    let proofreadingHighlightRange: NSRange?
    let proofreadingFocusToken: Int
    let chunkOpenToken: Int
    let dualScrollCoordinator: DocumentDualScrollCoordinator?
    let dualScrollPane: DocumentScrollPane?
    let dualScrollScope: DocumentScrollScope?

    init(
        text: Binding<String>,
        blocks: [DocumentEditorBlockItem],
        onBlocksChanged: (([DocumentEditorBlockItem], String) -> Void)?,
        onSelectionTranslation: ((DocumentTextSelectionSnapshot, Coordinator) -> Void)? = nil,
        fontFamily: FontFamily,
        fontSize: FontSize,
        fontScale: Double,
        side: DocumentEditorSide = .source,
        onFocusLost: (() -> Void)? = nil,
        onReplaceEverywhere: ((String, DocumentEditorSide) -> Void)? = nil,
        proofreadingHighlightRange: NSRange? = nil,
        proofreadingFocusToken: Int = 0,
        chunkOpenToken: Int = 0,
        dualScrollCoordinator: DocumentDualScrollCoordinator? = nil,
        dualScrollPane: DocumentScrollPane? = nil,
        dualScrollScope: DocumentScrollScope? = nil
    ) {
        self._text = text
        self.blocks = blocks
        self.onBlocksChanged = onBlocksChanged
        self.onSelectionTranslation = onSelectionTranslation
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontScale = fontScale
        self.side = side
        self.onFocusLost = onFocusLost
        self.onReplaceEverywhere = onReplaceEverywhere
        self.proofreadingHighlightRange = proofreadingHighlightRange
        self.proofreadingFocusToken = proofreadingFocusToken
        self.chunkOpenToken = chunkOpenToken
        self.dualScrollCoordinator = dualScrollCoordinator
        self.dualScrollPane = dualScrollPane
        self.dualScrollScope = dualScrollScope
    }

    init(
        text: Binding<String>,
        spans: [RichTextSpan],
        onSpansChanged: (([RichTextSpan], String) -> Void)?,
        onSelectionTranslation: ((DocumentTextSelectionSnapshot, Coordinator) -> Void)? = nil,
        fontFamily: FontFamily,
        fontSize: FontSize,
        fontScale: Double,
        side: DocumentEditorSide = .source,
        onFocusLost: (() -> Void)? = nil,
        onReplaceEverywhere: ((String, DocumentEditorSide) -> Void)? = nil,
        proofreadingHighlightRange: NSRange? = nil,
        proofreadingFocusToken: Int = 0,
        chunkOpenToken: Int = 0,
        dualScrollCoordinator: DocumentDualScrollCoordinator? = nil,
        dualScrollPane: DocumentScrollPane? = nil,
        dualScrollScope: DocumentScrollScope? = nil
    ) {
        self._text = text
        self.blocks = [DocumentEditorBlockItem(id: "block-0", spans: spans, fallbackText: text.wrappedValue)]
        if let onSpansChanged {
            self.onBlocksChanged = { blocks, updatedText in
                onSpansChanged(blocks.flatMap(\.spans), updatedText)
            }
        } else {
            self.onBlocksChanged = nil
        }
        self.onSelectionTranslation = onSelectionTranslation
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontScale = fontScale
        self.side = side
        self.onFocusLost = onFocusLost
        self.onReplaceEverywhere = onReplaceEverywhere
        self.proofreadingHighlightRange = proofreadingHighlightRange
        self.proofreadingFocusToken = proofreadingFocusToken
        self.chunkOpenToken = chunkOpenToken
        self.dualScrollCoordinator = dualScrollCoordinator
        self.dualScrollPane = dualScrollPane
        self.dualScrollScope = dualScrollScope
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        let textView = DocumentNSTextView()
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        // Default typing color only. Never assign `textColor` after content is
        // loaded: NSTextView.textColor rewrites the entire textStorage and
        // destroys per-span explicit colors (red placeholders, etc.).
        textView.typingAttributes[.foregroundColor] = NSColor(VaniScriptTheme.text0)
        textView.insertionPointColor = NSColor(VaniScriptTheme.text0)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        // Critical for long documents: without these the text view can collapse
        // to viewport height and refuse to scroll (or thrash on layout).
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.editorSide = side

        context.coordinator.textView = textView
        context.coordinator.setAttributedString(from: blocks, fallbackText: text, textView: textView)
        scrollView.documentView = textView
        context.coordinator.bindDualScroll(scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? DocumentNSTextView else { return }
        context.coordinator.textView = textView
        textView.coordinator = context.coordinator
        textView.editorSide = side
        if !context.coordinator.isUserEditing {
            context.coordinator.setAttributedString(from: blocks, fallbackText: text, textView: textView)
        }
        context.coordinator.bindDualScroll(scrollView)
        // Chunk open (Previous / Approve & Next): always land at the top.
        context.coordinator.handleChunkOpenIfNeeded(chunkOpenToken)

        let next = proofreadingHighlightRange
        let token = proofreadingFocusToken
        let focusChanged = token != context.coordinator.lastProofreadingFocusToken
        // Scroll when the controller intentionally changed focus (enable,
        // chunk change / Approve & Next, arrow move) — not on every SwiftUI tick.
        context.coordinator.applyProofreadingHighlight(
            next,
            focusToken: token,
            scroll: focusChanged
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DocumentAttributedTextView
        weak var textView: DocumentNSTextView?
        var isUserEditing = false
        private var lastRenderedBlocks: [DocumentEditorBlockItem] = []
        private var lastRenderedText: String = ""
        private var lastContentFingerprint: String = ""
        private weak var boundDualScrollView: NSScrollView?
        private var lastBoundDualScrollPane: DocumentScrollPane?
        private var lastChunkOpenToken: Int = -1
        init(_ parent: DocumentAttributedTextView) {
            self.parent = parent
        }

        /// Force the pane to the top of the new chunk. Independent of dual-scroll
        /// and of proofreading ranges (both chunks can share NSRange(0, n)).
        func handleChunkOpenIfNeeded(_ token: Int) {
            guard token != lastChunkOpenToken else { return }
            lastChunkOpenToken = token
            guard let textView else { return }
            guard let scrollView = textView.enclosingScrollView else {
                // Fallback: select start so caret/visible range is at top.
                textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
                return
            }
            let doc = scrollView.documentView
            let topY: CGFloat
            if let doc, !doc.isFlipped {
                // Unflipped NSTextView: top is the maximum origin.
                let viewport = scrollView.contentView.bounds.height
                let height = max(doc.bounds.height, doc.frame.height)
                topY = max(0, height - viewport)
            } else {
                topY = 0
            }
            let origin = NSPoint(x: 0, y: topY)
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        /// Direct same-tree attach: this pane's NSScrollView only. Never search
        /// siblings (that cross-bound left/right and blanked panes).
        func bindDualScroll(_ scrollView: NSScrollView) {
            guard let coordinator = parent.dualScrollCoordinator,
                  let pane = parent.dualScrollPane,
                  let scope = parent.dualScrollScope
            else {
                if let pane = lastBoundDualScrollPane {
                    // Dual-scroll turned off (proof mode / single pane).
                    // Global detach also runs from ReviewWorkspaceView onChange.
                    parent.dualScrollCoordinator?.detach(pane: pane, scrollView: boundDualScrollView)
                    lastBoundDualScrollPane = nil
                }
                boundDualScrollView = nil
                return
            }
            boundDualScrollView = scrollView
            lastBoundDualScrollPane = pane
            coordinator.attach(scrollView, pane: pane, scope: scope)
        }

        /// PRD §15: editor focus loss is a mandatory autosave flush point.
        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusLost?()
        }

        private(set) var selectionTranslationBusy = false
        private(set) var selectionTranslationStatus = ""

        func currentEditorBlocks() -> [DocumentEditorBlockItem] {
            lastRenderedBlocks.isEmpty ? parent.blocks : lastRenderedBlocks
        }

        /// Re-render the last known blocks so theme defaults refresh without
        /// losing explicit per-span colors after appearance changes.
        func reapplyLastRenderedAttributedString() {
            guard let textView else { return }
            let blocks = currentEditorBlocks()
            let fallback = lastRenderedText.isEmpty ? parent.text : lastRenderedText
            // Force a real rebuild even when content is unchanged.
            lastRenderedBlocks = []
            lastRenderedText = ""
            lastContentFingerprint = ""
            setAttributedString(from: blocks, fallbackText: fallback, textView: textView)
        }

        var currentEditorText: String {
            textView?.string ?? lastRenderedText
        }

        func selectionSnapshot() -> DocumentTextSelectionSnapshot? {
            guard let textView, let storage = textView.textStorage else { return nil }
            return DocumentSelectionBridge.buildSnapshot(
                from: storage,
                selectedRange: textView.selectedRange(),
                side: parent.side,
                languageKey: nil,
                chunkPlanID: ""
            )
        }

        func performSelectionTranslation() {
            guard let snapshot = selectionSnapshot(),
                  DocumentSelectionTranslationEngine.isEligible(snapshot)
            else { return }
            parent.onSelectionTranslation?(snapshot, self)
        }

        func setSelectionTranslationBusy(_ busy: Bool, status: String = "") {
            selectionTranslationBusy = busy
            selectionTranslationStatus = status
            textView?.toolTip = status.isEmpty ? nil : status
        }

        func renderExternalSelectionMutation(
            _ updatedBlock: TranslatedBlock,
            previousBlocks: [DocumentEditorBlockItem],
            previousText: String
        ) {
            guard let textView else { return }
            var updatedBlocks = currentEditorBlocks()
            let item = DocumentEditorBlockItem(
                id: updatedBlock.sourceBlockID,
                spans: updatedBlock.spans,
                fallbackText: updatedBlock.text
            )
            if let index = updatedBlocks.firstIndex(where: { $0.id == item.id }) {
                updatedBlocks[index] = item
            } else {
                updatedBlocks.append(item)
            }
            let updatedText = updatedBlocks.map(\.fallbackText).joined(separator: "\n\n")
            registerUndo(previousBlocks: previousBlocks, previousText: previousText)
            setAttributedString(from: updatedBlocks, fallbackText: updatedText, textView: textView)
            parent.text = updatedText
            lastMutationError = nil
        }

        private func registerUndo(previousBlocks: [DocumentEditorBlockItem], previousText: String) {
            guard let undoManager = textView?.undoManager else { return }
            undoManager.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    guard let textView = target.textView else { return }
                    target.setAttributedString(from: previousBlocks, fallbackText: previousText, textView: textView)
                    target.parent.text = previousText
                    target.parent.onBlocksChanged?(previousBlocks, previousText)
                }
            }
            undoManager.setActionName("Retranslate Selection with AI")
        }

        var lastMutationError: (any Error)?

        func applyMutation(transform: ([DocumentEditorBlockItem]) throws -> [DocumentEditorBlockItem]) {
            guard let textView else { return }
            let selectedRange = textView.selectedRange()
            do {
                let updatedBlocks = try transform(currentEditorBlocks())
                lastRenderedBlocks = updatedBlocks
                setAttributedString(from: updatedBlocks, fallbackText: parent.text, textView: textView)
                if selectedRange.location + selectedRange.length <= (textView.string as NSString).length {
                    textView.setSelectedRange(selectedRange)
                }
                let fullText = textView.string
                lastRenderedText = fullText
                parent.text = fullText
                lastMutationError = nil
                parent.onBlocksChanged?(updatedBlocks, fullText)
            } catch {
                // Mutation failure is safely caught without claiming success;
                // leave the model unchanged and record operation metadata only.
                lastMutationError = error
                AppLogger.shared.error("Document mutation failed: \(type(of: error))")
            }
        }
        func setAttributedString(from blocks: [DocumentEditorBlockItem], fallbackText: String, textView: NSTextView) {
            // Fingerprint model content. Do NOT compare textView.string to
            // fallbackText: the view string includes "\n\n" block separators and
            // would force a full rewrite every SwiftUI tick (blink + scroll reset).
            let fingerprint = contentFingerprint(blocks: blocks, fallbackText: fallbackText)
            if fingerprint == lastContentFingerprint {
                return
            }
            lastContentFingerprint = fingerprint
            lastRenderedBlocks = blocks
            lastRenderedText = fallbackText

            // Preserve scroll origin across rare real content changes.
            let savedOrigin = textView.enclosingScrollView?.contentView.bounds.origin
            let baseFont = reviewNSFont(family: parent.fontFamily, size: parent.fontSize, scale: parent.fontScale)
            let defaultColor = VaniScriptTheme.displayAdaptedTextColor(hex: nil)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 3
            paragraphStyle.paragraphSpacing = 6

            let attrString = NSMutableAttributedString()
            if !blocks.isEmpty {
                for (bIdx, block) in blocks.enumerated() {
                    if bIdx > 0 {
                        let sepAttrs: [NSAttributedString.Key: Any] = [
                            DocumentTextAttribute.isBlockSeparator: true,
                            DocumentTextAttribute.blockID: block.id,
                            .font: baseFont,
                            .foregroundColor: defaultColor,
                            .paragraphStyle: paragraphStyle
                        ]
                        attrString.append(NSAttributedString(string: "\n\n", attributes: sepAttrs))
                    }
                    if !block.spans.isEmpty {
                        for span in block.spans {
                            guard !span.text.isEmpty else { continue }
                            var fontDescriptor = baseFont.fontDescriptor
                            var symTraits: NSFontDescriptor.SymbolicTraits = []
                            if span.traits.contains(.bold) { symTraits.insert(.bold) }
                            if span.traits.contains(.italic) { symTraits.insert(.italic) }
                            if !symTraits.isEmpty {
                                fontDescriptor = fontDescriptor.withSymbolicTraits(symTraits)
                            }
                            let font = NSFont(descriptor: fontDescriptor, size: baseFont.pointSize) ?? baseFont
                            let displayColor = VaniScriptTheme.displayAdaptedTextColor(hex: span.foregroundColorHex)

                            var attrs: [NSAttributedString.Key: Any] = [
                                .font: font,
                                .foregroundColor: displayColor,
                                .paragraphStyle: paragraphStyle,
                                DocumentTextAttribute.blockID: block.id,
                                DocumentTextAttribute.spanID: span.id,
                                DocumentTextAttribute.styleKey: span.styleKey,
                                DocumentTextAttribute.translationPolicy: span.translationPolicy.rawValue,
                                DocumentTextAttribute.inlineTraits: span.traits.map(\.rawValue).sorted()
                            ]
                            if let hex = span.foregroundColorHex {
                                attrs[DocumentTextAttribute.explicitColorHex] = hex
                            }
                            if span.traits.contains(.underline) {
                                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                            }
                            if span.traits.contains(.strikethrough) {
                                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                            }
                            attrString.append(NSAttributedString(string: span.text, attributes: attrs))
                        }
                    } else if !block.fallbackText.isEmpty {
                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: baseFont,
                            .foregroundColor: defaultColor,
                            .paragraphStyle: paragraphStyle,
                            DocumentTextAttribute.blockID: block.id,
                            DocumentTextAttribute.styleKey: "",
                            DocumentTextAttribute.translationPolicy: SpanTranslationPolicy.translate.rawValue,
                            DocumentTextAttribute.inlineTraits: [String]()
                        ]
                        attrString.append(NSAttributedString(string: block.fallbackText, attributes: attrs))
                    }
                }
            } else if !fallbackText.isEmpty {
                attrString.append(NSAttributedString(string: fallbackText, attributes: [
                    .font: baseFont,
                    .foregroundColor: defaultColor,
                    .paragraphStyle: paragraphStyle,
                    DocumentTextAttribute.styleKey: "",
                    DocumentTextAttribute.translationPolicy: SpanTranslationPolicy.translate.rawValue,
                    DocumentTextAttribute.inlineTraits: [String]()
                ]))
            }

            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(attrString)
            // Grow the text view to the laid-out content height so long chunks
            // actually scroll instead of clipping/thrashing inside the viewport.
            if let container = textView.textContainer,
               let layoutManager = textView.layoutManager {
                layoutManager.ensureLayout(for: container)
                let used = layoutManager.usedRect(for: container)
                let width = textView.enclosingScrollView?.contentSize.width
                    ?? textView.bounds.width
                let height = max(
                    ceil(used.height + textView.textContainerInset.height * 2),
                    textView.enclosingScrollView?.contentSize.height ?? 0
                )
                if width > 0 {
                    textView.setFrameSize(NSSize(width: width, height: height))
                }
            }
            if selectedRange.location + selectedRange.length <= (textView.string as NSString).length {
                textView.setSelectedRange(selectedRange)
            }
            if let savedOrigin, let scrollView = textView.enclosingScrollView {
                scrollView.contentView.scroll(to: savedOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            // Content rewrite clears temporary attributes — restore mark without
            // scrolling (unit navigation scrolls explicitly).
            applyProofreadingHighlight(
                parent.proofreadingHighlightRange ?? lastProofreadingHighlight,
                focusToken: parent.proofreadingFocusToken,
                scroll: false
            )
        }

        private func contentFingerprint(blocks: [DocumentEditorBlockItem], fallbackText: String) -> String {
            if blocks.isEmpty {
                return "fallback|\(fallbackText.utf16.count)|\(fallbackText.hashValue)"
            }
            var parts: [String] = []
            parts.reserveCapacity(blocks.count)
            for block in blocks {
                var spanParts: [String] = []
                spanParts.reserveCapacity(block.spans.count)
                for span in block.spans {
                    spanParts.append(
                        "\(span.id)|\(span.text.utf16.count)|\(span.text.hashValue)|\(span.foregroundColorHex ?? "")|\(span.traits.map(\.rawValue).sorted().joined(separator: ","))"
                    )
                }
                parts.append("\(block.id)#\(spanParts.joined(separator: ";"))#\(block.fallbackText.hashValue)")
            }
            return parts.joined(separator: "\n")
        }

        private(set) var lastProofreadingHighlight: NSRange?
        private(set) var lastProofreadingFocusToken: Int = -1

        func applyProofreadingHighlight(_ range: NSRange?, focusToken: Int = 0, scroll: Bool = true) {
            guard let textView, let layoutManager = textView.layoutManager else { return }
            let fullLen = (textView.string as NSString).length
            let full = NSRange(location: 0, length: fullLen)

            let normalized: NSRange? = {
                guard let range, range.length > 0, range.location >= 0,
                      fullLen > 0,
                      range.location + range.length <= fullLen
                else { return nil }
                return range
            }()

            // Same unit + same focus token already painted → skip. Re-painting
            // every SwiftUI tick made long dual panes blink / refuse to scroll.
            // A new focusToken (enable / chunk change / arrow) always re-applies
            // and may scroll even when the NSRange looks identical.
            if !scroll,
               focusToken == lastProofreadingFocusToken,
               rangesEqual(normalized, lastProofreadingHighlight) {
                if let normalized {
                    let existingBg = layoutManager.temporaryAttribute(
                        .backgroundColor,
                        atCharacterIndex: normalized.location,
                        effectiveRange: nil
                    )
                    let existingFg = layoutManager.temporaryAttribute(
                        .foregroundColor,
                        atCharacterIndex: normalized.location,
                        effectiveRange: nil
                    )
                    if existingBg != nil && existingFg != nil {
                        return
                    }
                } else {
                    return
                }
            }

            if fullLen > 0 {
                layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
            }
            lastProofreadingHighlight = normalized
            lastProofreadingFocusToken = focusToken
            guard let normalized else { return }

            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: VaniScriptTheme.proofreadingHighlightNSBackground,
                forCharacterRange: normalized
            )
            layoutManager.addTemporaryAttribute(
                .foregroundColor,
                value: VaniScriptTheme.proofreadingHighlightNSForeground,
                forCharacterRange: normalized
            )
            if scroll {
                textView.scrollRangeToVisible(normalized)
                // Keep dual-scroll coherent after a unit jump: publish this
                // pane's progress and pull the opposite pane.
                if let dual = parent.dualScrollCoordinator,
                   let pane = parent.dualScrollPane {
                    dual.syncFromProgrammaticScroll(pane: pane)
                }
            }
        }

        private func rangesEqual(_ a: NSRange?, _ b: NSRange?) -> Bool {
            switch (a, b) {
            case (nil, nil): return true
            case (nil, _?), (_?, nil): return false
            case let (lhs?, rhs?): return NSEqualRanges(lhs, rhs)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            isUserEditing = true
            let updatedText = textView.string
            parent.text = updatedText

            let serializedBlocks = serializeBlocks(from: textView.attributedString(), knownBlocks: parent.blocks)
            lastRenderedBlocks = serializedBlocks
            lastRenderedText = updatedText
            parent.onBlocksChanged?(serializedBlocks, updatedText)
            isUserEditing = false
        }

        private func serializeBlocks(from attrString: NSAttributedString, knownBlocks: [DocumentEditorBlockItem]) -> [DocumentEditorBlockItem] {
            let nsString = attrString.string as NSString
            let fullRange = NSRange(location: 0, length: nsString.length)
            guard fullRange.length > 0 else {
                return knownBlocks.map { DocumentEditorBlockItem(id: $0.id, spans: [], fallbackText: "") }
            }

            var spansByBlockID: [String: [RichTextSpan]] = [:]
            var orderedBlockIDs: [String] = []
            for b in knownBlocks {
                orderedBlockIDs.append(b.id)
                spansByBlockID[b.id] = []
            }
            var currentBlockID = knownBlocks.first?.id ?? "block-0"
            if !orderedBlockIDs.contains(currentBlockID) {
                orderedBlockIDs.append(currentBlockID)
            }

            attrString.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
                let isSeparator = attrs[DocumentTextAttribute.isBlockSeparator] as? Bool ?? false
                let runText = nsString.substring(with: range).precomposedStringWithCanonicalMapping

                if let blockIDAttr = attrs[DocumentTextAttribute.blockID] as? String, !blockIDAttr.isEmpty {
                    currentBlockID = blockIDAttr
                    if !orderedBlockIDs.contains(currentBlockID) {
                        orderedBlockIDs.append(currentBlockID)
                    }
                }

                if isSeparator {
                    let trimmed = runText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        return
                    }
                }

                guard !runText.isEmpty else { return }

                let traits: Set<InlineTrait>
                if let traitStrings = attrs[DocumentTextAttribute.inlineTraits] as? [String] {
                    traits = Set(traitStrings.compactMap(InlineTrait.init(rawValue:)))
                } else if let traitArray = attrs[DocumentTextAttribute.inlineTraits] as? [Any] {
                    traits = Set(traitArray.compactMap { ($0 as? String).flatMap(InlineTrait.init(rawValue:)) })
                } else if let traitSet = attrs[DocumentTextAttribute.inlineTraits] as? Set<InlineTrait> {
                    traits = traitSet
                } else {
                    var fallbackTraits: Set<InlineTrait> = []
                    if let font = attrs[.font] as? NSFont {
                        let symTraits = font.fontDescriptor.symbolicTraits
                        if symTraits.contains(.bold) { fallbackTraits.insert(.bold) }
                        if symTraits.contains(.italic) { fallbackTraits.insert(.italic) }
                    }
                    if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
                        fallbackTraits.insert(.underline)
                    }
                    if let strike = attrs[.strikethroughStyle] as? Int, strike != 0 {
                        fallbackTraits.insert(.strikethrough)
                    }
                    traits = fallbackTraits
                }

                let styleKey = attrs[DocumentTextAttribute.styleKey] as? String ?? ""
                let translationPolicy = (attrs[DocumentTextAttribute.translationPolicy] as? String).flatMap(SpanTranslationPolicy.init(rawValue:)) ?? .translate
                let explicitColorHex = attrs[DocumentTextAttribute.explicitColorHex] as? String
                let existingSpanID = attrs[DocumentTextAttribute.spanID] as? String

                var blockSpans = spansByBlockID[currentBlockID] ?? []

                if let lastIndex = blockSpans.indices.last,
                   let existingID = existingSpanID,
                   !existingID.isEmpty,
                   blockSpans[lastIndex].id == existingID,
                   blockSpans[lastIndex].styleKey == styleKey,
                   blockSpans[lastIndex].traits == traits,
                   blockSpans[lastIndex].translationPolicy == translationPolicy,
                   blockSpans[lastIndex].foregroundColorHex == explicitColorHex {
                    blockSpans[lastIndex].text += runText
                } else if let lastIndex = blockSpans.indices.last,
                          (existingSpanID == nil || existingSpanID!.isEmpty),
                          blockSpans[lastIndex].styleKey == styleKey,
                          blockSpans[lastIndex].traits == traits,
                          blockSpans[lastIndex].translationPolicy == translationPolicy,
                          blockSpans[lastIndex].foregroundColorHex == explicitColorHex {
                    blockSpans[lastIndex].text += runText
                } else {
                    let spanID = (existingSpanID != nil && !existingSpanID!.isEmpty) ? existingSpanID! : UUID().uuidString
                    let span = RichTextSpan(
                        id: spanID,
                        text: runText,
                        styleKey: styleKey,
                        traits: traits,
                        translationPolicy: translationPolicy,
                        foregroundColorHex: explicitColorHex
                    )
                    blockSpans.append(span)
                }
                spansByBlockID[currentBlockID] = blockSpans
            }

            return orderedBlockIDs.map { blockID in
                let spans = spansByBlockID[blockID] ?? []
                let blockText = spans.map(\.text).joined()
                return DocumentEditorBlockItem(id: blockID, spans: spans, fallbackText: blockText)
            }
        }
    }
}

private func reviewNSFont(family: FontFamily, size: FontSize, scale: Double) -> NSFont {
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
final class DocumentNSTextView: NSTextView {
    weak var coordinator: DocumentAttributedTextView.Coordinator?
    var editorSide: DocumentEditorSide = .source
    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Only refresh caret / typing defaults. Assigning `textColor` here used
        // to repaint the whole storage with theme text0 and permanently strip
        // explicit span colors until the next unequal content update — which is
        // exactly the "left stays red, right goes black" dual-pane failure
        // after import / appearance resolution.
        typingAttributes[.foregroundColor] = NSColor(VaniScriptTheme.text0)
        insertionPointColor = NSColor(VaniScriptTheme.text0)
        coordinator?.reapplyLastRenderedAttributedString()
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        augmentMenu(menu)
        return menu
    }

    private func augmentMenu(_ menu: NSMenu) {
        var addedAnyItem = false

        // PRD §11.1: Replace Everywhere is available on BOTH editor sides when
        // the selection is non-empty.
        let selectedText = replaceEverywhereSelectedText
        if !selectedText.isEmpty {
            if menu.numberOfItems > 0 {
                menu.addItem(NSMenuItem.separator())
            }
            let label = selectedText.count > 40 ? String(selectedText.prefix(40)) + "…" : selectedText
            let item = NSMenuItem(
                title: "Replace \"\(label)\" Everywhere…",
                action: #selector(replaceEverywhereSelection(_:)),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
            addedAnyItem = true
        }

        // The AI retranslate item stays translation-only.
        if editorSide == .translation {
            if menu.numberOfItems > 0, !addedAnyItem {
                menu.addItem(NSMenuItem.separator())
            }
            let item = NSMenuItem(
                title: coordinator?.selectionTranslationBusy == true
                    ? "Retranslating Selection with AI…"
                    : "Retranslate Selection with AI…",
                action: #selector(retranslateSelectionWithAI(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.isEnabled = canRetranslateSelectionWithAI
            menu.addItem(item)
        }
    }

    /// The trimmed selected text used by the Replace Everywhere context-menu
    /// entry (PRD §11.1). Empty when nothing is selected.
    private var replaceEverywhereSelectedText: String {
        guard let storage = textStorage else { return "" }
        let range = selectedRange()
        guard range.length > 0, range.location + range.length <= storage.length else { return "" }
        return (storage.string as NSString)
            .substring(with: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc private func replaceEverywhereSelection(_ sender: Any?) {
        let selectedText = replaceEverywhereSelectedText
        guard !selectedText.isEmpty else { return }
        coordinator?.parent.onReplaceEverywhere?(selectedText, editorSide)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(retranslateSelectionWithAI(_:)) {
            return canRetranslateSelectionWithAI
        }
        return super.validateMenuItem(menuItem)
    }

    var canRetranslateSelectionWithAI: Bool {
        guard isEditable, let snapshot = selectionSnapshotForCommand() else { return false }
        return DocumentSelectionTranslationEngine.isEligible(snapshot)
    }

    private func selectionSnapshotForCommand() -> DocumentTextSelectionSnapshot? {
        guard let storage = textStorage else { return nil }
        return DocumentSelectionBridge.buildSnapshot(
            from: storage,
            selectedRange: selectedRange(),
            side: editorSide
        )
    }

    @objc private func retranslateSelectionWithAI(_ sender: Any?) {
        guard canRetranslateSelectionWithAI else { return }
        coordinator?.performSelectionTranslation()
    }

    func selectionContainsNonSeparatorText(range: NSRange) -> Bool {
        guard let attrString = textStorage, range.location + range.length <= attrString.length else { return false }
        var found = false
        attrString.enumerateAttributes(in: range, options: []) { attrs, _, stop in
            let isSeparator = attrs[DocumentTextAttribute.isBlockSeparator] as? Bool ?? false
            if !isSeparator {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if let attrData = pboard.data(forType: .rtf) ?? pboard.data(forType: .rtfd),
           let attrString = try? NSAttributedString(data: attrData, options: [:], documentAttributes: nil) {
            let sanitized = sanitizePastedAttributedString(attrString)
            self.insertText(sanitized, replacementRange: selectedRange())
            return true
        } else if let plainText = pboard.string(forType: .string) {
            let cleanText = plainText.precomposedStringWithCanonicalMapping
            self.insertText(cleanText, replacementRange: selectedRange())
            return true
        }
        return super.readSelection(from: pboard, type: type)
    }

    func sanitizePastedAttributedString(_ attrString: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(string: attrString.string.precomposedStringWithCanonicalMapping)
        let fullRange = NSRange(location: 0, length: attrString.length)

        attrString.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            var allowedAttrs: [NSAttributedString.Key: Any] = [:]

            var traits: Set<InlineTrait> = []
            if let font = attrs[.font] as? NSFont {
                let sym = font.fontDescriptor.symbolicTraits
                if sym.contains(.bold) { traits.insert(.bold) }
                if sym.contains(.italic) { traits.insert(.italic) }
                allowedAttrs[.font] = font
            }
            if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
                traits.insert(.underline)
                allowedAttrs[.underlineStyle] = underline
            }
            if let strike = attrs[.strikethroughStyle] as? Int, strike != 0 {
                traits.insert(.strikethrough)
                allowedAttrs[.strikethroughStyle] = strike
            }
            if let color = attrs[.foregroundColor] as? NSColor {
                allowedAttrs[.foregroundColor] = color
            }

            if !traits.isEmpty {
                allowedAttrs[DocumentTextAttribute.inlineTraits] = traits.map(\.rawValue).sorted()
            }

            result.setAttributes(allowedAttrs, range: range)
        }

        return result
    }
}
