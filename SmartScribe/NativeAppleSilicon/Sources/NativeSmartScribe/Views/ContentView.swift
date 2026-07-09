import AppKit
import ApplicationServices
import NativeSmartScribeCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum Layout {
        static let minimumSidebarWidth = SidebarLayoutMetrics.minimumWidth
        static let idealSidebarWidth = SidebarLayoutMetrics.idealWidth
    }

    @StateObject private var noteStore = NoteStore.live()
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var translationAudioRecorder = AudioRecorder()
    @EnvironmentObject private var polishingEngineStore: PolishingEngineStore
    @EnvironmentObject private var promptTemplateStore: PromptTemplateStore
    @EnvironmentObject private var transcriptionModelStore: TranscriptionModelStore
    @EnvironmentObject private var transcriptionEngineStore: TranscriptionEngineStore
    @EnvironmentObject private var hotkeySettingsStore: HotkeySettingsStore
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var usageStatisticsStore: UsageStatisticsStore
    @EnvironmentObject private var glossaryStore: GlossaryStore
    @State private var selectedVariant: ProcessingVariant = .raw
    @State private var selectedNoteText = ""
    @State private var isShowingTranslation = false
    @State private var translationOriginalText = ""
    @State private var translationTranslatedText = ""
    @AppStorage("translation.targetLanguage") private var translationTargetLanguage = "English"
    @AppStorage("translation.providerID") private var translationProviderID = ""
    @State private var pendingHotkeyTarget: HotkeyTarget?
    @State private var pendingHotkeyOutputMode: HotkeyOutputMode?
    @State private var pendingHotkeySourcePID: pid_t?
    @State private var pendingHotkeyFocusedElement: AXUIElement?
    @State private var isTogglingHotkeyRecording = false
    @State private var hotkeyOwnerID = UUID()
    @State private var hotkeySessionOverlayManager = HotkeySessionOverlayManager()
    @State private var pendingHotkeyForceTargetLanguage = false

    var body: some View {
        GeometryReader { proxy in
            NavigationSplitView {
                SidebarView(noteStore: noteStore)
                    .navigationSplitViewColumnWidth(
                        min: Layout.minimumSidebarWidth,
                        ideal: Layout.idealSidebarWidth,
                        max: SidebarLayoutMetrics.maximumWidth(forWindowWidth: proxy.size.width)
                    )
            } detail: {
                NoteDetailView(
                    note: noteStore.selectedNote,
                    selectedVariant: $selectedVariant,
                    selectedText: $selectedNoteText,
                    audioRecorder: audioRecorder,
                    onRecordingCompleted: transcribeRecording,
                    onPolishRequested: polishNote,
                    onMarkdownRequested: generateMarkdown,
                    onTextChanged: updateText,
                    onAudioFileImportRequested: importAudioFile,
                    onBlankNoteRequested: createBlankNote,
                    onTranslateRequested: openTranslationModal
                )
            }
            .navigationSplitViewStyle(.balanced)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(UIScaleModifier())
            .onDrop(
                of: [
                    UTType.fileURL.identifier,
                    UTType.audio.identifier,
                    UTType.movie.identifier
                ],
                isTargeted: nil,
                perform: handleAudioFileDrop
            )
            .sheet(isPresented: $isShowingTranslation) {
                TranslationModalView(
                    audioRecorder: translationAudioRecorder,
                    providerID: $translationProviderID,
                    targetLanguage: $translationTargetLanguage,
                    originalText: $translationOriginalText,
                    translatedText: $translationTranslatedText,
                    onTranslate: translateText,
                    onRecordingCompleted: transcribeForTranslation
                )
                .environmentObject(generalSettingsStore)
                .environmentObject(polishingEngineStore)
                .environmentObject(glossaryStore)
            }
            .onAppear {
                syncLocalizedServices()
            }
            .onChange(of: generalSettingsStore.settings.uiLanguage) { _, _ in
                syncLocalizedServices()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeSmartScribeHotkeyTriggered)) { _ in
                handleHotkeyTriggered(forceTarget: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeSmartScribeTargetHotkeyTriggered)) { _ in
                handleHotkeyTriggered(forceTarget: true)
            }
            .onReceive(audioRecorder.$frequencyBands) { bands in
                guard audioRecorder.isRecording else { return }
                hotkeySessionOverlayManager.update(spectrumBands: bands)
            }
            .onChange(of: generalSettingsStore.settings.overlay) { _, overlaySettings in
                hotkeySessionOverlayManager.update(settings: overlaySettings)
            }
            .onChange(of: noteStore.selection) { _, _ in
                selectedNoteText = ""
            }
            .onChange(of: selectedVariant) { _, _ in
                selectedNoteText = ""
            }
        }
        .frame(minWidth: 980, minHeight: 680)
    }


    private func transcribeRecording(_ recording: AudioRecording) {
        transcribeRecording(recording, hotkeyTarget: nil, outputMode: nil)
    }

    private func updateRawText(noteID: SmartScribeNote.ID, text: String) {
        noteStore.updateRawText(for: noteID, text: text)
    }

    private func updateText(
        noteID: SmartScribeNote.ID,
        variant: ProcessingVariant,
        text: String
    ) {
        noteStore.updateText(for: noteID, variant: variant, text: text)
    }

    private func createBlankNote() {
        _ = noteStore.addEmptyNote(title: generalSettingsStore.text(.untitledNote))
        selectedVariant = .raw
        selectedNoteText = ""
    }

    private func importAudioFile(_ url: URL) {
        Task { @MainActor in
            do {
                let recording = try AudioFileImporter.recording(from: url)
                transcribeRecording(recording)
            } catch {
                NativeSmartScribeLog.transcription.error("Audio file import failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleAudioFileDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = item as? URL
                    }

                    guard let url else { return }
                    Task { @MainActor in
                        importAudioFile(url)
                    }
                }
                return true
            }

            let supportedType = [UTType.audio, .movie].first {
                provider.hasItemConformingToTypeIdentifier($0.identifier)
            }

            if let supportedType {
                provider.loadFileRepresentation(forTypeIdentifier: supportedType.identifier) { url, _ in
                    guard let url else { return }
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension)
                    do {
                        if FileManager.default.fileExists(atPath: destination.path) {
                            try FileManager.default.removeItem(at: destination)
                        }
                        try FileManager.default.copyItem(at: url, to: destination)
                        Task { @MainActor in
                            importAudioFile(destination)
                        }
                    } catch {
                        NativeSmartScribeLog.transcription.error("Audio drop copy failed: \(error.localizedDescription)")
                    }
                }
                return true
            }
        }

        if providers.isEmpty {
            return true
        }

        return false
    }

    private func openTranslationModal() {
        let selected = selectedNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipboard = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = selected.isEmpty ? clipboard : selected

        translationOriginalText = source
        translationTranslatedText = source.isEmpty ? generalSettingsStore.text(.noTextToTranslate) : ""
        // Provider validation happens inside TranslationModalView.onAppear
        isShowingTranslation = true

        guard !source.isEmpty else { return }
        guard !translationProviderID.isEmpty else {
            translationTranslatedText = generalSettingsStore.text(.noTranslationProvider)
            return
        }
        Task { @MainActor in
            translationTranslatedText = generalSettingsStore.text(.translating)
            do {
                let result = try await translateText(
                    text: source,
                    targetLanguage: translationTargetLanguage,
                    providerID: translationProviderID
                )
                translationTranslatedText = result.text
            } catch {
                translationTranslatedText = error.localizedDescription
            }
        }
    }

    private func translateText(
        text: String,
        targetLanguage: String,
        providerID: String
    ) async throws -> PolishingResult {
        let prompt = try TranslationPrompt.render(text: text, targetLanguage: targetLanguage)

        // Resolve engine: per-model MLX tag vs. cloud provider ID
        let engine: any PolishingEngine
        if let modelID = TranslationModalView.localMLXModelID(from: providerID),
           let model = polishingEngineStore.allModels.first(where: { $0.id == modelID }) {
            engine = polishingEngineStore.engine(forLocalMLXModel: model)
        } else {
            engine = polishingEngineStore.engine(for: providerID)
        }

        let result = try await engine.polish(
            PolishingRequest(
                rawText: prompt,
                variant: .variantOne,
                template: PromptTemplate(
                    id: "translation-pass-through",
                    title: "Translation",
                    body: PromptTemplate.transcriptionPlaceholder
                )
            )
        )

        usageStatisticsStore.record(
            modelID: result.diagnostics.backendName,
            modelName: result.diagnostics.backendName,
            diagnostics: result.diagnostics
        )
        let rewritten = glossaryStore.apply(
            to: result.text,
            target: .translation,
            language: targetLanguage
        )
        return PolishingResult(
            text: rewritten.text,
            diagnostics: result.diagnostics
        )
    }

    private func transcribeForTranslation(_ recording: AudioRecording) async throws -> String {
        let engine = transcriptionEngineStore.activeEngine(modelStore: transcriptionModelStore)
        let languageCode = transcriptionModelStore.resolvedLanguageCode
        let activeModel = transcriptionModelStore.activeModel
        let isMultilingual = activeModel?.languageSupport == .multilingual
        let route = TranscriptionLanguageRouter.route(
            resolvedLanguageCode: languageCode,
            isMultilingualModel: isMultilingual
        )
        let result = try await engine.transcribe(
            TranscriptionRequest(
                audioFileURL: recording.fileURL,
                forcedLanguageCode: route.forcedLanguageCode,
                translateToEnglish: route.translateToEnglish
            )
        )
        return glossaryStore.apply(to: result.text, target: .source).text
    }

    private func transcribeRecording(
        _ recording: AudioRecording,
        hotkeyTarget: HotkeyTarget?,
        outputMode: HotkeyOutputMode?,
        forceTargetLanguage: Bool = false
    ) {
        Task { @MainActor in
            let workflow = RecordingTranscriptionWorkflow(
                noteStore: noteStore,
                engine: transcriptionEngineStore.activeEngine(
                    modelStore: transcriptionModelStore
                ),
                glossarySettingsProvider: { glossaryStore.settings }
            )
            let languageCode: String
            if hotkeyTarget != nil {
                languageCode = "auto"
            } else {
                languageCode = transcriptionModelStore.resolvedLanguageCode
            }
            let activeModel = transcriptionModelStore.activeModel
            let isMultilingual = activeModel?.languageSupport == .multilingual
            let route = TranscriptionLanguageRouter.route(
                resolvedLanguageCode: languageCode,
                isMultilingualModel: isMultilingual
            )

            let noteID = await workflow.transcribeRecording(
                recording,
                forcedLanguageCode: route.forcedLanguageCode,
                translateToEnglish: route.translateToEnglish
            )

            let autoTranslationTargetLanguage = forceTargetLanguage
                ? glossaryStore.settings.autoTranslationLanguage
                : route.autoTranslateTargetLanguageCode.map {
                    TranscriptionLanguageOption.displayName(for: $0)
                }
            if let targetLanguageName = autoTranslationTargetLanguage,
               let note = noteStore.note(withID: noteID),
               !note.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await autoTranslateRawText(
                    noteID: noteID,
                    rawText: note.rawText,
                    targetLanguage: targetLanguageName
                )
            }

            if let hotkeyTarget {
                selectedVariant = hotkeyTarget.processingVariant
                if hotkeyTarget == .raw {
                    applyHotkeyOutputIfNeeded(for: noteID, target: hotkeyTarget, mode: outputMode)
                    finishHotkeySessionIfNeeded(target: hotkeyTarget)
                    return
                }
            }

            guard polishingEngineStore.canAutoPolishAfterTranscription else {
                NativeSmartScribeLog.polishing.info("Skipped automatic polishing because no local polishing model is ready.")
                // Show the raw transcription tab so the user sees the (potentially
                // English-translated) text even when no polishing model is active.
                selectedVariant = hotkeyTarget?.processingVariant ?? .raw
                if polishingEngineStore.selectedEngineID != PolishingEngineStore.disabledEngineID {
                    markPolishingUnavailable(for: noteID)
                }
                applyHotkeyOutputIfNeeded(for: noteID, target: hotkeyTarget, mode: outputMode)
                finishHotkeySessionIfNeeded(target: hotkeyTarget)
                return
            }

            let requestedVariants = hotkeyTarget?.requestedPolishingVariants ?? [.variantOne, .variantTwo]
            selectedVariant = hotkeyTarget?.processingVariant ?? requestedVariants.first ?? .variantOne
            await polish(noteID, variants: requestedVariants)
            selectedVariant = hotkeyTarget?.processingVariant ?? selectedVariant
            applyHotkeyOutputIfNeeded(for: noteID, target: hotkeyTarget, mode: outputMode)
            finishHotkeySessionIfNeeded(target: hotkeyTarget)
        }
    }

    private func polishNote(_ noteID: SmartScribeNote.ID) {
        selectedVariant = .variantOne
        Task { @MainActor in
            await polish(noteID)
        }
    }

    private func polish(
        _ noteID: SmartScribeNote.ID,
        variants: [ProcessingVariant] = [.variantOne, .variantTwo]
    ) async {
        let workflow = PolishingWorkflow(
            noteStore: noteStore,
            engine: polishingEngineStore.activeEngine,
            templateProvider: { variant in
                promptTemplateStore.template(for: variant)
            },
            messageProvider: { key in
                generalSettingsStore.text(key)
            }
        )
        let results = await workflow.polishNote(noteID, variants: variants)
        for result in results.values {
            usageStatisticsStore.record(
                modelID: result.diagnostics.backendName,
                modelName: result.diagnostics.backendName,
                diagnostics: result.diagnostics
            )
        }
    }

    /// Translates the raw transcription to the target language using the active
    /// polishing engine and overwrites `rawText` with the translated version.
    /// Used for auto-translation when any non-auto transcription language is selected,
    /// including English (all languages now share this LLM path).
    private func autoTranslateRawText(
        noteID: SmartScribeNote.ID,
        rawText: String,
        targetLanguage: String
    ) async {
        guard polishingEngineStore.canAutoPolishAfterTranscription else {
            NativeSmartScribeLog.polishing.info(
                "Skipped auto-translation — no polishing engine available."
            )
            return
        }

        do {
            let prompt = try TranslationPrompt.render(
                text: rawText,
                targetLanguage: targetLanguage
            )
            let engine = polishingEngineStore.activeEngine
            let result = try await engine.polish(
                PolishingRequest(
                    rawText: prompt,
                    variant: .variantOne,
                    template: PromptTemplate(
                        id: "auto-translation-pass-through",
                        title: "Auto Translation",
                        body: PromptTemplate.transcriptionPlaceholder
                    )
                )
            )

            let translatedText = glossaryStore.apply(
                to: result.text,
                target: .translation,
                language: targetLanguage
            ).text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translatedText.isEmpty else { return }

            noteStore.updateRawText(for: noteID, text: translatedText)
            usageStatisticsStore.record(
                modelID: result.diagnostics.backendName,
                modelName: result.diagnostics.backendName,
                diagnostics: result.diagnostics
            )
        } catch {
            NativeSmartScribeLog.polishing.error(
                "Auto-translation failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func generateMarkdown(
        for noteID: SmartScribeNote.ID,
        variant: ProcessingVariant
    ) {
        guard variant != .raw else { return }
        guard let note = noteStore.note(withID: noteID) else { return }

        let sourceText: String
        switch variant {
        case .raw:
            sourceText = note.rawText
        case .variantOne:
            sourceText = note.polishedVariantOne
        case .variantTwo:
            sourceText = note.polishedVariantTwo
        }

        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard polishingEngineStore.selectedEngineID != PolishingEngineStore.disabledEngineID else { return }
        guard polishingEngineStore.selectedEngineID != "local-rule-based-polish" else { return }

        Task { @MainActor in
            noteStore.markPolishingStarted(
                for: noteID,
                variant: variant,
                backendName: polishingEngineStore.activeEngine.displayName
            )

            do {
                let result = try await polishingEngineStore.activeEngine.polish(
                    PolishingRequest(
                        rawText: trimmed,
                        variant: variant,
                        template: promptTemplateStore.markdownTemplate()
                    )
                )

                let markdown = MarkdownGenerationPostProcessor.ensureVisibleMarkdown(
                    result.text,
                    sourceText: trimmed
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !markdown.isEmpty else {
                    noteStore.markPolishingFailed(
                        for: noteID,
                        variant: variant,
                        message: generalSettingsStore.text(.emptyPolishingResult),
                        backendName: result.diagnostics.backendName
                    )
                    return
                }

                noteStore.applyPolishingResult(
                    for: noteID,
                    variant: variant,
                    result: PolishingResult(
                        text: markdown,
                        diagnostics: result.diagnostics
                    )
                )
                usageStatisticsStore.record(
                    modelID: result.diagnostics.backendName,
                    modelName: result.diagnostics.backendName,
                    diagnostics: result.diagnostics
                )
            } catch {
                noteStore.markPolishingFailed(
                    for: noteID,
                    variant: variant,
                    message: error.localizedDescription,
                    backendName: polishingEngineStore.activeEngine.displayName
                )
            }
        }
    }

    private func handleHotkeyTriggered(forceTarget: Bool) {
        guard !isTogglingHotkeyRecording else { return }

        let settings = hotkeySettingsStore.settings
        guard settings.enabled else { return }

        isTogglingHotkeyRecording = true
        Task { @MainActor in
            defer { isTogglingHotkeyRecording = false }

            if audioRecorder.isRecording {
                guard HotkeySessionCoordinator.shared.beginProcessing(ownerID: hotkeyOwnerID) else {
                    NativeSmartScribeLog.hotkey.info(
                        "Ignored stop hotkey for non-owner content view owner=\(self.hotkeyOwnerID.uuidString, privacy: .public)"
                    )
                    return
                }

                guard let recording = audioRecorder.stop() else { return }
                hotkeySessionOverlayManager.show(
                    mode: .processing,
                    settings: generalSettingsStore.settings.overlay,
                    onOriginChange: persistOverlayOrigin
                )
                let target = pendingHotkeyTarget ?? settings.target
                let mode = pendingHotkeyOutputMode ?? settings.mode
                let forceTargetValue = pendingHotkeyForceTargetLanguage
                pendingHotkeyTarget = nil
                pendingHotkeyOutputMode = nil
                pendingHotkeyForceTargetLanguage = false
                NativeSmartScribeLog.hotkey.info(
                    "Stopped hotkey recording target=\(target.rawValue, privacy: .public) mode=\(mode.rawValue, privacy: .public) capturedSourcePID=\(pendingHotkeySourcePID ?? -1, privacy: .public) hasFocusedElement=\(pendingHotkeyFocusedElement != nil, privacy: .public)"
                )
                transcribeRecording(recording, hotkeyTarget: target, outputMode: mode, forceTargetLanguage: forceTargetValue)
            } else {
                guard HotkeySessionCoordinator.shared.beginRecording(ownerID: hotkeyOwnerID) else {
                    NativeSmartScribeLog.hotkey.info(
                        "Ignored start hotkey for non-owner content view owner=\(self.hotkeyOwnerID.uuidString, privacy: .public)"
                    )
                    return
                }

                let sourceApplication = NSWorkspace.shared.frontmostApplication
                pendingHotkeySourcePID = sourceApplication?.processIdentifier
                pendingHotkeyFocusedElement = AccessibilityPermissionService.focusedElement()
                pendingHotkeyTarget = settings.target
                pendingHotkeyOutputMode = settings.mode
                pendingHotkeyForceTargetLanguage = forceTarget
                NativeSmartScribeLog.hotkey.info(
                    "Started hotkey recording forceTarget=\(forceTarget) target=\(settings.target.rawValue, privacy: .public) mode=\(settings.mode.rawValue, privacy: .public) sourcePID=\(sourceApplication?.processIdentifier ?? -1, privacy: .public) sourceBundle=\(sourceApplication?.bundleIdentifier ?? "unknown", privacy: .public) hasFocusedElement=\(pendingHotkeyFocusedElement != nil, privacy: .public)"
                )
                await audioRecorder.start()

                if audioRecorder.isRecording {
                    hotkeySessionOverlayManager.show(
                        mode: .listening,
                        settings: generalSettingsStore.settings.overlay,
                        onOriginChange: persistOverlayOrigin
                    )
                    hotkeySessionOverlayManager.update(
                        spectrumBands: audioRecorder.frequencyBands,
                        settings: generalSettingsStore.settings.overlay
                    )
                    hotkeySessionOverlayManager.playCue(.start, settings: generalSettingsStore.settings.overlay)
                } else {
                    pendingHotkeySourcePID = nil
                    pendingHotkeyFocusedElement = nil
                    pendingHotkeyTarget = nil
                    pendingHotkeyOutputMode = nil
                    pendingHotkeyForceTargetLanguage = false
                    hotkeySessionOverlayManager.hide()
                    HotkeySessionCoordinator.shared.finish(ownerID: hotkeyOwnerID)
                }
            }
        }
    }

    private func applyHotkeyOutputIfNeeded(
        for noteID: SmartScribeNote.ID,
        target: HotkeyTarget?,
        mode: HotkeyOutputMode?
    ) {
        guard let mode, let target, let note = noteStore.note(withID: noteID) else { return }

        let text = HotkeyOutputTextResolver.text(from: note, target: target)
        let targetApplication = pendingHotkeySourcePID.flatMap(NSRunningApplication.init(processIdentifier:))
        NativeSmartScribeLog.hotkey.info(
            "Resolved hotkey output target=\(target.rawValue, privacy: .public) mode=\(mode.rawValue, privacy: .public) textLength=\(text.trimmingCharacters(in: .whitespacesAndNewlines).count, privacy: .public) sourcePID=\(pendingHotkeySourcePID ?? -1, privacy: .public) sourceBundle=\(targetApplication?.bundleIdentifier ?? "unknown", privacy: .public)"
        )
        HotkeyOutputDispatcher.shared.dispatch(
            text: text,
            mode: mode,
            targetApplication: targetApplication,
            targetElement: pendingHotkeyFocusedElement
        )
        pendingHotkeySourcePID = nil
        pendingHotkeyFocusedElement = nil
    }

    private func finishHotkeySessionIfNeeded(target: HotkeyTarget?) {
        guard target != nil else { return }
        hotkeySessionOverlayManager.playCue(.finish, settings: generalSettingsStore.settings.overlay)
        hotkeySessionOverlayManager.hide()
        HotkeySessionCoordinator.shared.finish(ownerID: hotkeyOwnerID)
    }

    private func persistOverlayOrigin(_ origin: OverlayHUDOrigin) {
        generalSettingsStore.update { $0.overlay.lastOrigin = origin }
    }

    private func syncLocalizedServices() {
        audioRecorder.setTextProvider(generalSettingsStore.text)
        translationAudioRecorder.setTextProvider(generalSettingsStore.text)
    }

    private func markPolishingUnavailable(for noteID: SmartScribeNote.ID) {
        let message = polishingEngineStore.preparationSnapshot.message
            ?? generalSettingsStore.text(.chooseLocalPolishingModel)

        for variant in [ProcessingVariant.variantOne, .variantTwo] {
            noteStore.markPolishingFailed(
                for: noteID,
                variant: variant,
                message: message,
                backendName: polishingEngineStore.activeEngine.displayName
            )
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PolishingEngineStore.live())
        .environmentObject(PromptTemplateStore.live())
        .environmentObject(TranscriptionModelStore.live())
        .environmentObject(TranscriptionEngineStore.live())
        .environmentObject(HotkeySettingsStore.live())
        .environmentObject(GeneralSettingsStore.live())
        .environmentObject(UsageStatisticsStore.live())
}
