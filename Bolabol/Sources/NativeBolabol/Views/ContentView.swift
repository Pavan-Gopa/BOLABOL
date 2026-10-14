import AppKit
import ApplicationServices
import Carbon
import NativeBolabolCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
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
    @EnvironmentObject private var accessibilityPermissionStore: AccessibilityPermissionStore
    @State private var selectedVariant: ProcessingVariant = .raw
    @State private var selectedNoteText = ""
    @State private var isShowingTranslation = false
    @State private var isShowingOnboarding = false
    @State private var translationOriginalText = ""
    @State private var translationTranslatedText = ""
    @AppStorage("translation.targetLanguage") private var translationTargetLanguage = "English"
    @AppStorage("translation.providerID") private var translationProviderID = ""
    @State private var pendingHotkeyTarget: HotkeyTarget?
    @State private var pendingHotkeyOutputMode: HotkeyOutputMode?
    @State private var pendingHotkeySourcePID: pid_t?
    @State private var relaunchGateRecordingCheckerID: UUID?
    @State private var relaunchGateQuiescenceHandlerID: UUID?
    @State private var pendingHotkeyFocusedElement: AXUIElement?
    @State private var sessionWarningMessage: String?
    @State private var isTogglingHotkeyRecording = false
    @State private var hotkeyOwnerID = UUID()
    @State private var hotkeySessionOverlayManager = HotkeySessionOverlayManager()
    @State private var providerQuickSwitcher = ProviderQuickSwitcher()
    @State private var pendingHotkeySession: TranscriptionEngineSession?
    /// ADR-029: frozen per-session target snapshot. Captured once at hotkey
    /// start; only explicit HUD actions during that recording replace it;
    /// stop hands it unchanged to the pipeline.
    @State private var pendingHotkeySnapshot: HotkeyLanguageSnapshot?
    @State private var pendingHotkeyHumorSession: HumorSessionState?
    @AppStorage("hud.forceTargetLanguage") private var persistentHUDForceTargetLanguage = false
    /// ADR-029: the old dual-purpose `hudTargetLanguageOverride` is split.
    /// Canary ASR source vs post-ASR target language are separate concerns.
    @State private var canarySourceOverride: String?
    @State private var hudTargetOverride: String?
    @State private var lastObservedAdditionalLanguageCode: String?
    @State private var languagePickerController = LanguagePickerPopoverController()

    private func dismissLanguagePickerPopover() {
        languagePickerController.dismiss()
    }
    @ViewBuilder
    private func mainSplitView(windowWidth: CGFloat) -> some View {
        NavigationSplitView {
            SidebarView(noteStore: noteStore)
                .navigationSplitViewColumnWidth(
                    min: Layout.minimumSidebarWidth,
                    ideal: Layout.idealSidebarWidth,
                    max: SidebarLayoutMetrics.maximumWidth(forWindowWidth: windowWidth)
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
    }

    @ViewBuilder
    private func attachSheets<V: View>(_ content: V) -> some View {
        content
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
            .sheet(isPresented: $isShowingOnboarding) {
                OnboardingView(
                    accessibility: accessibilityPermissionStore,
                    audioRecorder: audioRecorder
                )
                .environmentObject(generalSettingsStore)
                .environmentObject(glossaryStore)
                .environmentObject(transcriptionModelStore)
                .environmentObject(polishingEngineStore)
                .environmentObject(hotkeySettingsStore)
            }
    }

    @ViewBuilder
    private func attachNotifications<V: View>(_ content: V) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
                isShowingOnboarding = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeBolabolHotkeyTriggered)) { _ in
                handleHotkeyTriggered()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeBolabolHotkeyKeyDown)) { _ in
                handleHotkeyKeyDown()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeBolabolHotkeyKeyUp)) { _ in
                handleHotkeyKeyUp()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeBolabolTargetHotkeyTriggered)) { _ in
                openFloatingTranslationWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeBolabolQuickTranslationHotkeyTriggered)) { _ in
                openQuickTranslationWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeBolabolSettingsHotkeyTriggered)) { _ in
                AppDelegate.shared?.cycleSettingsAndMainWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeBolabolDismissSheets)) { _ in
                isShowingTranslation = false
                isShowingOnboarding = false
            }
    }

    @ViewBuilder
    private func attachObservers<V: View>(_ content: V) -> some View {
        content
            .onAppear {
                syncLocalizedServices()
                isShowingOnboarding = !generalSettingsStore.settings.hasCompletedOnboarding
                configureProviderQuickSwitcher()
                relaunchGateRecordingCheckerID = UpdateRelaunchGate.shared.registerRecordingChecker {
                    audioRecorder.isRecording || translationAudioRecorder.isRecording
                }
                relaunchGateQuiescenceHandlerID = UpdateRelaunchGate.shared.registerQuiescenceHandler {
                    // Quiescence check passed: safe to restart
                }
            }
            .onDisappear {
                if let id = relaunchGateRecordingCheckerID {
                    UpdateRelaunchGate.shared.unregisterRecordingChecker(id)
                }
                if let id = relaunchGateQuiescenceHandlerID {
                    UpdateRelaunchGate.shared.unregisterQuiescenceHandler(id)
                }
            }
            .onChange(of: generalSettingsStore.settings.uiLanguage) { _, _ in
                syncLocalizedServices()
            }
            .onReceive(audioRecorder.$frequencyBands) { bands in
                guard audioRecorder.isRecording else { return }
                hotkeySessionOverlayManager.update(spectrumBands: bands)
            }
            .onChange(of: generalSettingsStore.settings.overlay) { _, overlaySettings in
                hotkeySessionOverlayManager.update(settings: overlaySettings)
            }
            .onChange(of: hotkeySettingsStore.settings.humorSliderEnabled) { _, isEnabled in
                if audioRecorder.isRecording {
                    updatePendingHotkeyHumorSession(sliderEnabled: isEnabled)
                }
                hotkeySessionOverlayManager.update(
                    humorLevel: hotkeySettingsStore.settings.humorLevel,
                    humorSliderEnabled: isEnabled
                )
            }
            .onChange(of: hotkeySettingsStore.settings.humorLevel) { _, level in
                if audioRecorder.isRecording {
                    updatePendingHotkeyHumorSession(level: level)
                }
                hotkeySessionOverlayManager.update(
                    humorLevel: level
                )
            }
            .onChange(of: hotkeySettingsStore.settings.humorPromptMode) { _, mode in
                if audioRecorder.isRecording {
                    updatePendingHotkeyHumorSession(promptMode: mode)
                }
            }
            .onReceive(promptTemplateStore.objectWillChange) { _ in
                hotkeySessionOverlayManager.update(
                    activePromptSlot: currentHUDActivePromptSlot,
                    promptSlotNames: currentHUDPromptSlotNames
                )
            }
            .onChange(of: noteStore.selection) { _, _ in
                selectedNoteText = ""
            }
            .onChange(of: selectedVariant) { _, _ in
                selectedNoteText = ""
            }
            .onReceive(transcriptionModelStore.objectWillChange) { _ in
                dismissLanguagePickerPopover()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                dismissLanguagePickerPopover()
            }
    }

    var body: some View {
        GeometryReader { proxy in
            attachObservers(
                attachNotifications(
                    attachSheets(
                        mainSplitView(windowWidth: proxy.size.width)
                            .onDrop(
                                of: [
                                    UTType.fileURL.identifier,
                                    UTType.audio.identifier,
                                    UTType.movie.identifier
                                ],
                                isTargeted: nil,
                                perform: handleAudioFileDrop
                            )
                    )
                )
            )
        }
        .frame(minWidth: 820, minHeight: 580)
        .alert(
            generalSettingsStore.text(.transcriptionFailed),
            isPresented: Binding(
                get: { sessionWarningMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        sessionWarningMessage = nil
                    }
                }
            )
        ) {
            Button(generalSettingsStore.text(.close), role: .cancel) {
                sessionWarningMessage = nil
            }
        } message: {
            Text(sessionWarningMessage ?? "")
        }
    }


    private func transcribeRecording(_ recording: AudioRecording) {
        // Respect the HUD A/E toggle (auto vs. forced target language) exactly like the
        // hotkey path does. Without this, HUD-button recordings always ran in "auto"
        // mode and Gemini kept whatever language it heard, ignoring the E (target)
        // setting — e.g. returning Russian text even when E1 was selected.
        transcribeRecording(
            recording,
            hotkeyTarget: nil,
            outputMode: nil,
            forceTargetLanguage: effectiveHUDForceTargetLanguage
        )
    }

    private func updateText(
        noteID: BolabolNote.ID,
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
                NativeBolabolLog.transcription.error("Audio file import failed: \(error.localizedDescription)")
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
                        NativeBolabolLog.transcription.error("Audio drop copy failed: \(error.localizedDescription)")
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

    private func openFloatingTranslationWindow() {
        // Toggle: if already visible, close it
        if FloatingTranslationWindowManager.shared.isVisible {
            FloatingTranslationWindowManager.shared.close()
            return
        }

        Task { @MainActor in
            // Attempt to copy any currently selected text from external active app
            await postSyntheticCopy()

            let selected = selectedNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
            let clipboard = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let source = selected.isEmpty ? clipboard : selected

            translationOriginalText = source
            translationTranslatedText = source.isEmpty ? generalSettingsStore.text(.noTextToTranslate) : ""

            FloatingTranslationWindowManager.shared.show(
                audioRecorder: translationAudioRecorder,
                providerID: $translationProviderID,
                targetLanguage: $translationTargetLanguage,
                originalText: $translationOriginalText,
                translatedText: $translationTranslatedText,
                generalSettingsStore: generalSettingsStore,
                polishingEngineStore: polishingEngineStore,
                glossaryStore: glossaryStore,
                onTranslate: translateText,
                onRecordingCompleted: transcribeForTranslation
            )

            guard !source.isEmpty else { return }
            guard !translationProviderID.isEmpty else {
                translationTranslatedText = generalSettingsStore.text(.noTranslationProvider)
                return
            }

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

    private func postSyntheticCopy() async {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        cDown?.flags = .maskCommand
        cUp?.flags = .maskCommand
        cDown?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 30_000_000)
        cUp?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    private func openQuickTranslationWindow() {
        // Toggle: if already visible, close it
        if QuickTranslationWindowManager.shared.isVisible {
            QuickTranslationWindowManager.shared.close()
            return
        }

        Task { @MainActor in
            await postSyntheticCopy()

            let selected = selectedNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
            let clipboard = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let source = selected.isEmpty ? clipboard : selected

            guard !source.isEmpty, !translationProviderID.isEmpty else {
                QuickTranslationWindowManager.shared.show(
                    text: "",
                    generalSettingsStore: generalSettingsStore
                )
                return
            }

            do {
                let result = try await translateText(
                    text: source,
                    targetLanguage: translationTargetLanguage,
                    providerID: translationProviderID
                )
                QuickTranslationWindowManager.shared.show(
                    text: result.text,
                    generalSettingsStore: generalSettingsStore
                )
            } catch {
                QuickTranslationWindowManager.shared.show(
                    text: error.localizedDescription,
                    generalSettingsStore: generalSettingsStore
                )
            }
        }
    }

    private func translateText(
        text: String,
        targetLanguage: String,
        providerID: String
    ) async throws -> PolishingResult {
        let prompt = try TranslationPrompt.render(text: text, targetLanguage: targetLanguage)

        // Resolve engine: per-model MLX tag vs. cloud provider ID. A deleted
        // custom instance resolves to nil and throws instead of polishing
        // with an empty configuration.
        let engine: any PolishingEngine
        if let modelID = TranslationModalView.localMLXModelID(from: providerID),
           let model = polishingEngineStore.allModels.first(where: { $0.id == modelID }) {
            engine = polishingEngineStore.engine(forLocalMLXModel: model)
        } else {
            guard let resolved = polishingEngineStore.engine(for: providerID) else {
                throw CloudRequestRetryError.emptySuccessfulResponse
            }
            engine = resolved
        }

        let startedAt = Date()
        NativeBolabolLog.polishing.info(
            "Translation started provider=\(providerID, privacy: .public) engine=\(engine.displayName, privacy: .public) textLength=\(text.count)"
        )

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

        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        NativeBolabolLog.polishing.info(
            "Translation completed in \(elapsedMs)ms provider=\(providerID, privacy: .public) engine=\(engine.displayName, privacy: .public)"
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
        // Cloud · Google Gemini: the local TranscriptionEngineStore returns
        // UnavailableTranscriptionEngine for .geminiCloud, so route through
        // the dictation engine directly — plain transcription, no polishing.
        if transcriptionModelStore.settings.backend == .geminiCloud {
            let google = polishingEngineStore.apiSettings.configuration(for: .google)
            let engine = GeminiCloudDictationEngine(
                apiKeys: google.sanitizedAPIKeys,
                modelID: google.textModel
            )
            let result = try await engine.dictate(
                GeminiCloudDictationEngine.DictationRequest(
                    audioFileURL: recording.fileURL,
                    forceTargetLanguage: false,
                    targetLanguageName: ""
                )
            )
            return glossaryStore.apply(to: result.text, target: .source).text
        }

        let resolution = makeLocalSession(
            forceTargetLanguage: false,
            hotkeySession: false
        )
        switch resolution {
        case .available(let session):
            let workflow = RecordingTranscriptionWorkflow(
                noteStore: noteStore,
                engine: session.engine,
                glossarySettingsProvider: { glossaryStore.settings }
            )
            let result = try await workflow.transcribeAudio(
                audioFileURL: recording.fileURL,
                plan: session.plan
            )
            return glossaryStore.apply(to: result.text, target: .source).text
        case .unavailable(let reason):
            throw localizedSessionError(reason)
        }
    }

    private func transcribeRecording(
        _ recording: AudioRecording,
        hotkeyTarget: HotkeyTarget?,
        outputMode: HotkeyOutputMode?,
        forceTargetLanguage: Bool = false,
        session: TranscriptionEngineSession? = nil,
        languageSnapshot: HotkeyLanguageSnapshot? = nil,
        humorSnapshot: HumorSessionSnapshot? = nil
    ) {
        Task { @MainActor in
            // Cloud · Google Gemini: fast audio-to-Raw first, followed by an
            // optional text-only Variant 1/2 polishing pass.
            if transcriptionModelStore.settings.backend == .geminiCloud {
                await transcribeRecordingViaGeminiCloud(
                    recording,
                    hotkeyTarget: hotkeyTarget,
                    outputMode: outputMode,
                    forceTargetLanguage: forceTargetLanguage,
                    languageSnapshot: languageSnapshot,
                    humorSnapshot: humorSnapshot
                )
                return
            }

            // ADR-029: the frozen hotkey snapshot (or an idle resolution for
            // non-hotkey flows) is the only target truth. Main-window flows
            // (hotkeyTarget == nil) polish like Variant 1 when E is on.
            let snapshot = languageSnapshot ?? frozenSnapshot(
                for: hotkeyTarget ?? .note,
                wantsTarget: HotkeyLanguageSnapshotResolver.userWantsTargetOutput(
                    for: hotkeyTarget ?? .note,
                    forceTargetLanguage: persistentHUDForceTargetLanguage || forceTargetLanguage
                )
            )
            let wantsWhisperTarget = sessionWantsWhisperTarget(snapshot)
            let resolution: TranscriptionEngineSessionResolution
            if let session, session.plan.isWhisperTargetMode == wantsWhisperTarget {
                resolution = .available(session)
            } else {
                resolution = makeLocalSession(
                    forceTargetLanguage: wantsWhisperTarget,
                    hotkeySession: hotkeyTarget != nil
                )
            }

            guard case .available(let resolvedSession) = resolution else {
                let reason: TranscriptionSessionUnavailableReason
                if case .unavailable(let unavailableReason) = resolution {
                    reason = unavailableReason
                    sessionWarningMessage = sessionUnavailableMessage(for: reason)
                } else {
                    return
                }
                let workflow = RecordingTranscriptionWorkflow(
                    noteStore: noteStore,
                    engine: UnavailableTranscriptionEngine(),
                    glossarySettingsProvider: { glossaryStore.settings }
                )
                _ = await workflow.transcribeRecording(
                    recording,
                    resolution: .unavailable(reason)
                )
                finishHotkeySessionIfNeeded(target: hotkeyTarget)
                return
            }

            let workflow = RecordingTranscriptionWorkflow(
                noteStore: noteStore,
                engine: resolvedSession.engine,
                glossarySettingsProvider: { glossaryStore.settings }
            )
            let plan = resolvedSession.plan
            if let warning = plan.sourceLanguageWarning {
                sessionWarningMessage = languageWarningMessage(for: warning)
            }
            SessionLedger.shared.record(
                sessionID: hotkeyOwnerID.uuidString,
                event: "transcription.start",
                fields: [
                    "model": plan.modelID,
                    "whisperTarget": "\(plan.isWhisperTargetMode)",
                    "wantsTarget": "\(snapshot.wantsTarget)",
                    "targetCode": snapshot.targetCode ?? "none",
                ]
            )

            let noteID = await workflow.transcribeRecording(
                recording,
                plan: plan
            )
            let transcribedChars = noteStore.note(withID: noteID)?.rawText.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
            SessionLedger.shared.record(
                sessionID: hotkeyOwnerID.uuidString,
                event: "transcription.done",
                fields: ["chars": "\(transcribedChars)"]
            )

            // ADR-029: Raw + native ASR verifies only, never an LLM; V1/V2
            // runs polish(target) → verify → provider → source fallback.
            // Raw is never overwritten by translation.
            if let hotkeyTarget {
                selectedVariant = hotkeyTarget.processingVariant
            }
            let polishVariants = hotkeyTarget?.requestedPolishingVariants ?? [.variantOne, .variantTwo]
            if hotkeyTarget == .raw {
                selectedVariant = .raw
            } else if hotkeyTarget == nil {
                selectedVariant = polishVariants.first ?? .variantOne
            }
            let resolved = await polishAndResolveOutput(
                noteID: noteID,
                hotkeyTarget: hotkeyTarget,
                snapshot: snapshot,
                polishVariants: hotkeyTarget == .raw ? [] : polishVariants,
                humorSnapshot: humorSnapshot
            )
            selectedVariant = hotkeyTarget?.processingVariant ?? selectedVariant
            applyHotkeyOutputIfNeeded(for: noteID, target: hotkeyTarget, mode: outputMode, dispatchText: resolved.dispatchText)
            finishHotkeySessionIfNeeded(target: hotkeyTarget, fallbackSignalled: resolved.fallbackSignalled)
        }
    }

    /// ADR-029/Q3a/Q4d/Q5a: polishes (when requested) then resolves the single
    /// verified output. Returns the exact dispatch text and whether the source
    /// fallback signal (Funk cue + badge) is required. Never rewrites Raw.
    private func polishAndResolveOutput(
        noteID: BolabolNote.ID,
        hotkeyTarget: HotkeyTarget?,
        snapshot: HotkeyLanguageSnapshot,
        polishVariants: [ProcessingVariant],
        humorSnapshot: HumorSessionSnapshot?
    ) async -> (dispatchText: String?, fallbackSignalled: Bool) {
        // Q5a: one clock for the whole output-language chain — polish first
        // pass included. No new key, strict retry, or provider call starts at
        // or after the hard cap; the pipeline aborts to the signalled source
        // fallback instead.
        let chainStartedAt = Date()
        let chainBudget = CloudKeyFailover.TimeBudget.default
        let chainDeadline = chainStartedAt.addingTimeInterval(chainBudget.hardCapSeconds)
        let languages = generalSettingsStore.speechLanguages
        let rawText = noteStore.note(withID: noteID)?.rawText ?? ""

        if !polishVariants.isEmpty {
            if polishingEngineStore.canAutoPolishAfterTranscription {
                let polishingTarget = snapshot.wantsTarget && snapshot.mechanism == .polishing
                    ? snapshot.targetCode
                    : nil
                NativeBolabolLog.polishing.info(
                    "Polishing with targetLanguage=\(polishingTarget ?? "none", privacy: .public) variants=\(polishVariants.map(\.rawValue).joined(separator: ","), privacy: .public)"
                )
                let polishStarted = Date()
                do {
                    // Q5a: cancel in-flight polish at the chain cap instead of
                    // letting key chains run past it.
                    try await CloudKeyFailover.withTimeout(seconds: chainDeadline.timeIntervalSinceNow) { [self] in
                        await self.polish(
                            noteID,
                            variants: polishVariants,
                            targetLanguage: polishingTarget,
                            primaryLanguageCode: languages.primaryLanguageCode,
                            additionalLanguageCode: languages.additionalLanguageCode,
                            humorSnapshot: humorSnapshot,
                            deadline: chainDeadline
                        )
                    }
                } catch {
                    // Polish blew the chain cap: mark requested variants failed
                    // so the pipeline falls back with a signal — but never
                    // downgrade a variant that already holds polished text
                    // (Q5a: strict retry cancelled after the first pass kept
                    // it as completed; the pipeline must insert it, not Raw).
                    for variant in polishVariants where variant != .raw {
                        if let note = noteStore.note(withID: noteID),
                           note.polishingStatus(for: variant).phase == .completed {
                            let stored: String
                            switch variant {
                            case .raw: stored = note.rawText
                            case .variantOne: stored = note.polishedVariantOne
                            case .variantTwo: stored = note.polishedVariantTwo
                            }
                            if !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                continue
                            }
                        }
                        noteStore.markPolishingFailed(
                            for: noteID,
                            variant: variant,
                            message: CloudKeyFailover.TimeoutError().localizedDescription,
                            backendName: polishingEngineStore.activeEngine.displayName
                        )
                    }
                }
                SessionLedger.shared.record(
                    sessionID: hotkeyOwnerID.uuidString,
                    event: "polish",
                    fields: [
                        "variants": polishVariants.map(\.rawValue).joined(separator: ","),
                        "engine": polishingEngineStore.activeEngine.displayName,
                        "target": polishingTarget ?? "none",
                        "ms": "\(Int(Date().timeIntervalSince(polishStarted) * 1000))",
                    ]
                )
            } else {
                NativeBolabolLog.polishing.info("Skipped automatic polishing because no local polishing model is ready.")
                if polishingEngineStore.selectedEngineID != PolishingEngineStore.disabledEngineID {
                    markPolishingUnavailable(for: noteID)
                }
            }
        }

        guard snapshot.wantsTarget, let targetCode = snapshot.targetCode else {
            // Auto mode: no language claim, no badge. Requested slot wins;
            // an empty polish slot dispatches Raw so nothing is lost.
            if let hotkeyTarget {
                let slot = HotkeyOutputTextResolver.text(
                    from: noteStore.note(withID: noteID) ?? BolabolNote(title: "", rawText: rawText),
                    target: hotkeyTarget
                )
                let text = slot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? rawText : slot
                return (text, false)
            }
            return (nil, false)
        }

        let variant = (hotkeyTarget ?? .note).processingVariant
        let note = noteStore.note(withID: noteID)
        let polishedText: String? = {
            switch variant {
            case .raw: return nil
            case .variantOne: return note?.polishedVariantOne
            case .variantTwo: return note?.polishedVariantTwo
            }
        }()
        let polishSucceeded: Bool = {
            guard let note else { return false }
            if note.polishingStatus(for: variant).phase == .completed {
                return !(polishedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
            return false
        }()
        let context = TargetLanguageOutputPipeline.Context(
            snapshot: snapshot,
            requestedVariant: variant,
            primaryCode: languages.primaryLanguageCode,
            additionalCode: languages.additionalLanguageCode,
            budget: chainBudget,
            startedAt: chainStartedAt
        )
        let outcome = await TargetLanguageOutputPipeline.run(
            rawText: rawText,
            polishText: polishSucceeded ? polishedText : nil,
            polishSucceeded: polishSucceeded,
            context: context,
            polish: nil,
            translate: { [self] text, target in
                try await self.translateForPipeline(
                    text: text,
                    targetCode: target,
                    translationSeconds: chainBudget.translationSeconds,
                    deadline: chainDeadline
                )
            }
        )
        let translated = outcome.kind != .sourceFallback
        SessionLedger.shared.record(
            sessionID: hotkeyOwnerID.uuidString,
            event: "lang.verify",
            fields: [
                "target": targetCode,
                "verified": outcome.verifiedCode ?? "none",
                "kind": outcome.kind.rawValue,
                "via": outcome.via ?? "none",
                "reason": outcome.reason ?? "none",
            ]
        )
        SessionLedger.shared.record(
            sessionID: hotkeyOwnerID.uuidString,
            event: "output.dispatch",
            fields: ["chars": "\(outcome.text.count)", "kind": outcome.kind.rawValue]
        )
        noteStore.setOutputLanguage(
            for: noteID,
            record: NoteOutputLanguage(
                targetCode: targetCode,
                verifiedCode: outcome.verifiedCode,
                translated: translated,
                reason: translated ? nil : outcome.reason
            )
        )
        // A provider win is the delivered output: persist it on the variant.
        if outcome.kind == .translated, outcome.via == "translation-provider", variant != .raw {
            noteStore.updateText(for: noteID, variant: variant, text: outcome.text)
        }
        return (outcome.text, !translated)
    }

    private func polishNote(_ noteID: BolabolNote.ID) {
        selectedVariant = .variantOne
        // Manual polish action: E on → explicit target override, else source.
        let target = persistentHUDForceTargetLanguage ? targetLanguageCode : nil
        Task { @MainActor in
            await polish(noteID, targetLanguage: target)
        }
    }

    private func polish(
        _ noteID: BolabolNote.ID,
        variants: [ProcessingVariant] = [.variantOne, .variantTwo],
        targetLanguage: String? = nil,
        primaryLanguageCode: String? = nil,
        additionalLanguageCode: String? = nil,
        humorSnapshot: HumorSessionSnapshot? = nil,
        deadline: Date? = nil
    ) async {
        let settings = hotkeySettingsStore.settings
        let workflow = PolishingWorkflow.make(
            noteStore: noteStore,
            engine: polishingEngineStore.activeEngine,
            templateProvider: { variant in
                if let humorSnapshot, humorSnapshot.selectedVariant == variant {
                    return humorSnapshot.selectedPrompt
                }
                return promptTemplateStore.template(for: variant)
            },
            messageProvider: { key in
                generalSettingsStore.text(key)
            },
            humorSliderEnabled: humorSnapshot?.sliderEnabled ?? settings.humorSliderEnabled,
            humorLevel: humorSnapshot?.level ?? settings.humorLevel,
            humorPromptMode: humorSnapshot?.promptMode ?? settings.humorPromptMode
        )
        let results = await workflow.polishNote(
            noteID,
            variants: variants,
            targetLanguage: targetLanguage,
            primaryLanguageCode: primaryLanguageCode,
            additionalLanguageCode: additionalLanguageCode,
            deadline: deadline
        )
        for result in results.values {
            usageStatisticsStore.record(
                modelID: result.diagnostics.backendName,
                modelName: result.diagnostics.backendName,
                diagnostics: result.diagnostics
            )
        }
    }

    /// ADR-029: translation-provider step for the output pipeline. Translates
    /// the polished text (else Raw) and returns it — never writes to the note.
    /// Raw is never overwritten by translation. Q5a: the step shares
    /// `translationSeconds` and the chain-cap deadline. Throws when no
    /// provider is available, the provider errors, or it returns empty text.
    private func translateForPipeline(
        text: String,
        targetCode: String,
        translationSeconds: TimeInterval,
        deadline: Date
    ) async throws -> String {
        // Resolve the translation engine the same way the in-app Translation
        // modal does: prefer the user-selected translation provider (which may be
        // a local MLX model tagged "local-mlx:<modelID>"), and only fall back to
        // the active polishing engine when no translation provider is configured.
        let engine: any PolishingEngine
        if let resolved = resolveTranslationEngine(providerID: translationProviderID) {
            engine = resolved
        } else if polishingEngineStore.canAutoPolishAfterTranscription {
            engine = polishingEngineStore.activeEngine
        } else {
            throw CloudRequestRetryError.emptySuccessfulResponse
        }

        let targetLanguage = TranscriptionLanguageOption.displayName(for: targetCode)
        let startedAt = Date()
        let prompt = try TranslationPrompt.render(text: text, targetLanguage: targetLanguage)
        let translationRequest = PolishingRequest(
            rawText: prompt,
            variant: .variantOne,
            template: PromptTemplate(
                id: "pipeline-translation-pass-through",
                title: "Pipeline Translation",
                body: PromptTemplate.transcriptionPlaceholder
            )
        )
        // Q5a: the provider step (including its key failover) shares the
        // translation budget and never starts a new key at or after the
        // chain-cap deadline. Other engines are bounded by the pipeline's
        // timeout race around this call.
        let result: PolishingResult
        if let cloud = engine as? CloudTextPolishingEngine {
            let keyChainSeconds = min(translationSeconds, max(0, deadline.timeIntervalSinceNow))
            guard keyChainSeconds > 0 else { throw CloudRequestRetryError.emptySuccessfulResponse }
            result = try await cloud.polish(
                translationRequest,
                keyChainSeconds: keyChainSeconds,
                deadline: deadline
            )
        } else {
            result = try await engine.polish(translationRequest)
        }
        let translatedText = glossaryStore.apply(
            to: result.text,
            target: .translation,
            language: targetLanguage
        ).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        SessionLedger.shared.record(
            sessionID: hotkeyOwnerID.uuidString,
            event: "polish",
            fields: [
                "variants": "translation-provider",
                "engine": result.diagnostics.backendName,
                "target": targetCode,
                "ms": "\(Int(Date().timeIntervalSince(startedAt) * 1000))",
                "chars": "\(translatedText.count)",
            ]
        )
        usageStatisticsStore.record(
            modelID: result.diagnostics.backendName,
            modelName: result.diagnostics.backendName,
            diagnostics: result.diagnostics
        )
        guard !translatedText.isEmpty else {
            throw CloudRequestRetryError.emptySuccessfulResponse
        }
        return translatedText
    }

    /// Resolves the polishing engine to use for translation from a translation
    /// provider tag, mirroring `translateText`. Local MLX models are tagged
    /// "local-mlx:<modelID>"; anything else is treated as a provider/engine ID.
    /// Returns `nil` when the provider tag is empty or its model is unavailable.
    private func resolveTranslationEngine(providerID: String) -> (any PolishingEngine)? {
        let trimmed = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let modelID = TranslationModalView.localMLXModelID(from: trimmed) {
            guard let model = polishingEngineStore.allModels.first(where: { $0.id == modelID }) else {
                return nil
            }
            return polishingEngineStore.engine(forLocalMLXModel: model)
        }

        return polishingEngineStore.engine(for: trimmed)
    }

    private func generateMarkdown(
        for noteID: BolabolNote.ID,
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

    private func handleHotkeyKeyDown() {
        let settings = hotkeySettingsStore.settings
        guard settings.enabled, settings.holdToRecord else { return }
        guard !audioRecorder.isRecording else { return }
        startHotkeyRecording()
    }

    private func handleHotkeyKeyUp() {
        if audioRecorder.isRecording {
            stopHotkeyRecording()
        }
    }

    private func startHotkeyRecording() {
        guard !isTogglingHotkeyRecording else { return }
        let settings = hotkeySettingsStore.settings
        guard settings.enabled else { return }

        isTogglingHotkeyRecording = true
        Task { @MainActor in
            defer { isTogglingHotkeyRecording = false }
            guard !audioRecorder.isRecording else { return }

            guard HotkeySessionCoordinator.shared.beginRecording(ownerID: hotkeyOwnerID) else {
                NativeBolabolLog.hotkey.info(
                    "Ignored start hotkey for non-owner content view owner=\(self.hotkeyOwnerID.uuidString, privacy: .public)"
                )
                return
            }

            let sourceApplication = NSWorkspace.shared.frontmostApplication
            pendingHotkeySourcePID = sourceApplication?.processIdentifier
            pendingHotkeyFocusedElement = AccessibilityPermissionService.focusedElement()
            let resolvedTarget = settings.target
            // ADR-029: freeze the target snapshot once, before any audio.
            // Only explicit HUD actions during this recording replace it.
            let frozen = frozenSnapshot(
                for: resolvedTarget,
                wantsTarget: HotkeyLanguageSnapshotResolver.userWantsTargetOutput(
                    for: resolvedTarget,
                    forceTargetLanguage: persistentHUDForceTargetLanguage
                )
            )
            SessionLedger.shared.record(
                sessionID: hotkeyOwnerID.uuidString,
                event: "hotkey.press",
                fields: [
                    "target": resolvedTarget.rawValue,
                    "wantsTarget": "\(frozen.wantsTarget)",
                    "targetCode": frozen.targetCode ?? "none",
                    "mechanism": frozen.mechanism.rawValue,
                    "backend": isGeminiCloudBackend ? "geminiCloud" : (transcriptionModelStore.activeModel?.backend.rawValue ?? "none"),
                    "model": transcriptionModelStore.activeModel?.id ?? "none",
                ]
            )
            let session: TranscriptionEngineSession?
            if transcriptionModelStore.settings.backend == .geminiCloud {
                session = nil
            } else {
                let resolution = makeLocalSession(
                    forceTargetLanguage: sessionWantsWhisperTarget(frozen),
                    hotkeySession: true
                )
                guard case .available(let resolvedSession) = resolution else {
                    if case .unavailable(let reason) = resolution {
                        sessionWarningMessage = sessionUnavailableMessage(for: reason)
                        NativeBolabolLog.hotkey.error(
                            "Hotkey session unavailable reason=\(reason.localizedDescription, privacy: .public)"
                        )
                        SessionLedger.shared.record(
                            sessionID: hotkeyOwnerID.uuidString,
                            event: "session.resolve",
                            fields: ["available": "false", "reason": String(describing: reason)]
                        )
                    }
                    HotkeySessionCoordinator.shared.finish(ownerID: hotkeyOwnerID)
                    pendingHotkeyHumorSession = nil
                    pendingHotkeySnapshot = nil
                    return
                }
                session = resolvedSession
                SessionLedger.shared.record(
                    sessionID: hotkeyOwnerID.uuidString,
                    event: "session.resolve",
                    fields: [
                        "available": "true",
                        "model": resolvedSession.plan.modelID,
                        "backend": resolvedSession.plan.backend.rawValue,
                        "whisperTarget": "\(resolvedSession.plan.isWhisperTargetMode)",
                    ]
                )
            }

            if let warning = session?.plan.sourceLanguageWarning {
                sessionWarningMessage = languageWarningMessage(for: warning)
            }

            let languageControlEnabled = isHUDLanguageControlEnabled(for: resolvedTarget)
            pendingHotkeySession = session
            pendingHotkeySnapshot = frozen
            pendingHotkeyTarget = resolvedTarget
            pendingHotkeyOutputMode = settings.mode
            pendingHotkeyHumorSession = makeHotkeyHumorSessionState(
                for: resolvedTarget,
                settings: settings
            )
            if resolvedTarget != .raw {
                polishingEngineStore.ensurePolishingEnabledForWidgetTarget()
            }
            NativeBolabolLog.hotkey.info(
                "Started hotkey recording wantsTarget=\(frozen.wantsTarget) targetCode=\(frozen.targetCode ?? "none", privacy: .public) mechanism=\(frozen.mechanism.rawValue, privacy: .public) languageControlEnabled=\(languageControlEnabled) target=\(settings.target.rawValue, privacy: .public) mode=\(settings.mode.rawValue, privacy: .public) sourcePID=\(sourceApplication?.processIdentifier ?? -1, privacy: .public) sourceBundle=\(sourceApplication?.bundleIdentifier ?? "unknown", privacy: .public) hasFocusedElement=\(pendingHotkeyFocusedElement != nil, privacy: .public)"
            )
            SessionLedger.shared.record(
                sessionID: hotkeyOwnerID.uuidString,
                event: "recorder.start",
                fields: ["target": resolvedTarget.rawValue]
            )
            await audioRecorder.start()

            if audioRecorder.isRecording {
                hotkeySessionOverlayManager.show(
                    mode: .listening,
                    settings: generalSettingsStore.settings.overlay,
                    languageMode: effectiveHUDLanguageMode,
                    hotkeyTarget: resolvedTarget,
                    targetLanguageLabel: effectiveHUDLanguageLabel,
                    activePromptSlot: currentHUDActivePromptSlot,
                    promptSlotNames: currentHUDPromptSlotNames,
                    humorLevel: hotkeySettingsStore.settings.humorLevel,
                    humorSliderEnabled: hotkeySettingsStore.settings.humorSliderEnabled,
                    humorAccessibilityLabel: generalSettingsStore.text(.humorLevel),
                    promptSlotSelectedLabel: generalSettingsStore.text(.promptSlotSelected),
                    promptSlotUnselectedLabel: generalSettingsStore.text(.promptSlotUnselected),
                    promptSlotSwitchHint: generalSettingsStore.text(.promptSlotSwitch),
                    showsControls: true,
                    languageControlEnabled: languageControlEnabled,
                    onOriginChange: persistOverlayOrigin,
                    onLanguageTap: handleOverlayLanguageTap,
                    onLanguageRightClick: handleOverlayLanguageRightClick,
                    onTargetTap: handleOverlayTargetTap,
                    onPromptSlotChange: handleOverlayPromptSlotChange,
                    onHumorLevelChange: handleOverlayHumorLevelChange,
                    onScroll: handleOverlayProviderScroll,
                    sessionPlan: session?.plan
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
                pendingHotkeySession = nil
                pendingHotkeySnapshot = nil
                pendingHotkeyHumorSession = nil
                hotkeySessionOverlayManager.hide()
                HotkeySessionCoordinator.shared.finish(ownerID: hotkeyOwnerID)
            }
        }
    }

    private func stopHotkeyRecording() {
        dismissLanguagePickerPopover()
        guard !isTogglingHotkeyRecording else { return }
        let settings = hotkeySettingsStore.settings

        isTogglingHotkeyRecording = true
        Task { @MainActor in
            defer { isTogglingHotkeyRecording = false }
            let canProcess = HotkeySessionCoordinator.shared.beginProcessing(ownerID: hotkeyOwnerID)
                || HotkeySessionCoordinator.shared.reclaimOrphanedRecordingForStop(ownerID: hotkeyOwnerID)
            guard canProcess else {
                NativeBolabolLog.hotkey.info(
                    "Ignored stop hotkey for non-owner content view owner=\(self.hotkeyOwnerID.uuidString, privacy: .public) phaseOwned=\(HotkeySessionCoordinator.shared.isOwned(by: self.hotkeyOwnerID))"
                )
                pendingHotkeyHumorSession = nil
                return
            }

            guard let recording = audioRecorder.stop() else {
                NativeBolabolLog.hotkey.error(
                    "Stop hotkey: audioRecorder reported isRecording but stop() returned nil"
                )
                HotkeySessionCoordinator.shared.finish(ownerID: hotkeyOwnerID)
                hotkeySessionOverlayManager.hide()
                pendingHotkeyHumorSession = nil
                return
            }
            let target = pendingHotkeyTarget ?? settings.target
            let humorSnapshot = freezeHotkeyHumorSession(for: target)
            hotkeySessionOverlayManager.show(
                mode: .processing,
                settings: generalSettingsStore.settings.overlay,
                languageMode: effectiveHUDLanguageMode,
                hotkeyTarget: target,
                targetLanguageLabel: effectiveHUDLanguageLabel,
                showsControls: false,
                onOriginChange: persistOverlayOrigin,
                sessionPlan: pendingHotkeySession?.plan
            )
            let mode = pendingHotkeyOutputMode ?? settings.mode
            let session = pendingHotkeySession
            // ADR-029: stop hands the frozen snapshot unchanged to the
            // pipeline. No re-derivation from ambient state here.
            let snapshot = pendingHotkeySnapshot ?? frozenSnapshot(
                for: target,
                wantsTarget: HotkeyLanguageSnapshotResolver.userWantsTargetOutput(
                    for: target,
                    forceTargetLanguage: persistentHUDForceTargetLanguage
                )
            )
            pendingHotkeyTarget = nil
            pendingHotkeyOutputMode = nil
            pendingHotkeySession = nil
            pendingHotkeySnapshot = nil
            NativeBolabolLog.hotkey.info(
                "Stopped hotkey recording target=\(target.rawValue, privacy: .public) mode=\(mode.rawValue, privacy: .public) wantsTarget=\(snapshot.wantsTarget) targetCode=\(snapshot.targetCode ?? "none", privacy: .public) mechanism=\(snapshot.mechanism.rawValue, privacy: .public) capturedSourcePID=\(pendingHotkeySourcePID ?? -1, privacy: .public) hasFocusedElement=\(pendingHotkeyFocusedElement != nil, privacy: .public)"
            )
            SessionLedger.shared.record(
                sessionID: hotkeyOwnerID.uuidString,
                event: "recorder.stop",
                fields: ["target": target.rawValue, "wantsTarget": "\(snapshot.wantsTarget)"]
            )
            transcribeRecording(
                recording,
                hotkeyTarget: target,
                outputMode: mode,
                forceTargetLanguage: snapshot.wantsTarget,
                session: session,
                languageSnapshot: snapshot,
                humorSnapshot: humorSnapshot
            )
        }
    }

    private func handleHotkeyTriggered() {
        if audioRecorder.isRecording {
            stopHotkeyRecording()
        } else {
            startHotkeyRecording()
        }
    }

    private func applyHotkeyOutputIfNeeded(
        for noteID: BolabolNote.ID,
        target: HotkeyTarget?,
        mode: HotkeyOutputMode?,
        dispatchText: String? = nil
    ) {
        guard let mode, let target, let note = noteStore.note(withID: noteID) else { return }

        // ADR-029: the verified pipeline outcome wins. The strict resolver
        // (no silent fallback) is the Auto-mode backstop only.
        let text = dispatchText ?? HotkeyOutputTextResolver.text(from: note, target: target)
        let targetApplication = pendingHotkeySourcePID.flatMap(NSRunningApplication.init(processIdentifier:))
        NativeBolabolLog.hotkey.info(
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

    /// ADR-029/Q4d: a source fallback plays the distinct Funk cue (plus the
    /// persistent note badge) and flashes the HUD amber for ~600 ms before it
    /// hides; success hides immediately with the normal finish cue.
    private func finishHotkeySessionIfNeeded(target: HotkeyTarget?, fallbackSignalled: Bool = false) {
        languagePickerController.invalidateForFinishedHotkeySession()
        hotkeySessionOverlayManager.playCue(
            fallbackSignalled ? .fallback : .finish,
            settings: generalSettingsStore.settings.overlay
        )
        SessionLedger.shared.record(
            sessionID: hotkeyOwnerID.uuidString,
            event: "finish",
            fields: [
                "cue": fallbackSignalled ? "Funk" : "Bottle",
                "reason": fallbackSignalled ? "source-fallback" : "completed",
            ]
        )
        if fallbackSignalled {
            hotkeySessionOverlayManager.flashSourceFallbackTintThenHide()
        } else {
            hotkeySessionOverlayManager.hide()
        }
        providerQuickSwitcher.hide()
        pendingHotkeyHumorSession = nil
        HotkeySessionCoordinator.shared.finish(ownerID: hotkeyOwnerID)
    }

    private func persistOverlayOrigin(_ origin: OverlayHUDOrigin) {
        generalSettingsStore.update { settings in
            settings.overlay.setOrigin(origin, for: settings.overlay.style)
        }
    }

    // MARK: - Provider quick switcher (hidden HUD scroll gesture)

    private func configureProviderQuickSwitcher() {
        let store = polishingEngineStore
        let switcher = providerQuickSwitcher
        switcher.onSwitchProvider = { providerID in
            ContentView.applyQuickSwitchProvider(providerID: providerID, store: store)
        }
        switcher.onModelMenuRequested = { providerID, anchorView, location in
            ContentView.presentQuickSwitchModelMenu(
                providerID: providerID,
                anchorView: anchorView,
                location: location,
                store: store,
                switcher: switcher
            )
        }
    }

    private func handleOverlayProviderScroll(deltaY: CGFloat) {
        let providers = HUDProviderListComposer.providers(
            apiSettings: polishingEngineStore.apiSettings,
            localEngineID: PolishingEngineStore.mlxSwiftEngineID,
            localDisplayName: "Local.AI"
        )

        guard !providers.isEmpty,
              let anchorFrame = hotkeySessionOverlayManager.currentHUDFrame() else {
            return
        }
        providerQuickSwitcher.handleHUDScroll(
            deltaY: deltaY,
            providers: providers,
            activeID: polishingEngineStore.selectedEngineID,
            anchorFrame: anchorFrame
        )
    }

    private static func applyQuickSwitchProvider(providerID: String, store: PolishingEngineStore) {
        if providerID == PolishingEngineStore.mlxSwiftEngineID {
            store.selectedEngineID = PolishingEngineStore.mlxSwiftEngineID
        } else {
            store.selectAPIProvider(engineID: providerID)
        }
    }

    private static func presentQuickSwitchModelMenu(
        providerID: String,
        anchorView: NSView,
        location: NSPoint,
        store: PolishingEngineStore,
        switcher: ProviderQuickSwitcher
    ) {
        if providerID == PolishingEngineStore.mlxSwiftEngineID {
            let downloadedModels = store.allModels.filter { store.installationState(for: $0).isDownloaded }
            let currentActiveID = store.settings.activeModelID
            let menu = NSMenu()
            menu.autoenablesItems = false
            var targets: [QuickSwitcherMenuTarget] = []

            if downloadedModels.isEmpty {
                let item = NSMenuItem(
                    title: "No local models downloaded",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                menu.addItem(item)
            } else {
                for model in downloadedModels {
                    let target = QuickSwitcherMenuTarget {
                        store.activate(model)
                        switcher.hide()
                    }
                    targets.append(target)
                    let item = NSMenuItem(
                        title: model.displayName,
                        action: #selector(QuickSwitcherMenuTarget.invoke),
                        keyEquivalent: ""
                    )
                    item.target = target
                    if model.id == currentActiveID {
                        item.state = NSControl.StateValue.on
                    }
                    menu.addItem(item)
                }
            }
            menu.popUp(positioning: nil, at: location, in: anchorView)
            return
        }

        let optionsProvider = PolishingModelOptionsProvider(apiSettings: store.apiSettings)
        guard optionsProvider.configurationForEngineID(providerID) != nil else { return }
        let options = optionsProvider.providerModelOptions(
            forEngineID: providerID,
            favorites: FavoriteModelsStore.loadFavorites(engineID: providerID)
        )

        let currentModel = store.apiSettings.configuration(forEngineID: providerID)?.textModel ?? ""
        let menu = NSMenu()
        menu.autoenablesItems = false
        var targets: [QuickSwitcherMenuTarget] = []
        for option in options {
            let target = QuickSwitcherMenuTarget {
                if var config = store.apiSettings.configuration(forEngineID: providerID) {
                    config.textModel = option.id
                    _ = store.updateAPIConfiguration(config, forEngineID: providerID)
                }
                store.selectAPIProvider(engineID: providerID)
                switcher.hide()
            }
            targets.append(target)
            let item = NSMenuItem(
                title: option.displayName,
                action: #selector(QuickSwitcherMenuTarget.invoke),
                keyEquivalent: ""
            )
            item.target = target
            if option.id == currentModel {
                item.state = NSControl.StateValue.on
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: location, in: anchorView)
    }

    /// Retains a closure behind an `NSMenuItem` target for the duration of a
    /// synchronous `NSMenu.popUp` call.
    private final class QuickSwitcherMenuTarget: NSObject {
        private let handler: () -> Void
        init(handler: @escaping () -> Void) {
            self.handler = handler
        }
        @objc func invoke() {
            handler()
        }
    }

    private var isExplicitCoreMLBackend: Bool {
        guard let backend = hudLanguageBackend else { return false }
        return backend == .canaryCoreML || backend == .gigaAMCoreML
    }

    /// ADR-029: capability-truthful backend. Gemini cloud dictation has no
    /// local backend — callers branch on `settings.backend == .geminiCloud`
    /// instead of receiving a fake Whisper backend here.
    private var hudLanguageBackend: TranscriptionModelDescriptor.Backend? {
        if let pendingBackend = pendingHotkeySession?.plan.backend {
            return pendingBackend
        }
        if transcriptionModelStore.settings.backend == .geminiCloud {
            return nil
        }
        return transcriptionModelStore.activeModel?.backend
    }

    /// Builds the one local session route used by hotkey, main-window and
    /// translation-recording entry points. Core ML ignores the legacy Whisper
    /// target preference and always resolves from the canonical pair.
    private func makeLocalSession(
        forceTargetLanguage: Bool,
        hotkeySession: Bool,
        sourceLanguageOverride: String? = nil
    ) -> TranscriptionEngineSessionResolution {
        if isExplicitCoreMLBackend
            || transcriptionModelStore.activeModel?.backend == .fluidAudioCoreML {
            return transcriptionEngineStore.makeSession(
                modelStore: transcriptionModelStore,
                operation: .asr,
                sourceLanguageOverride: transcriptionModelStore.activeModel?.backend == .canaryCoreML
                    ? (sourceLanguageOverride ?? canarySourceOverride)
                    : nil
            )
        }

        let operation: TranscriptionSessionOperation = forceTargetLanguage
            ? .whisperTargetTranslation(languageCode: targetLanguageCode)
            : .asr
        let legacyLanguageCode = forceTargetLanguage
            ? targetLanguageCode
            : (hotkeySession ? "auto" : transcriptionModelStore.resolvedLanguageCode)
        return transcriptionEngineStore.makeSession(
            modelStore: transcriptionModelStore,
            operation: operation,
            legacyLanguageCode: legacyLanguageCode
        )
    }
    private var isGeminiCloudBackend: Bool {
        transcriptionModelStore.settings.backend == .geminiCloud
    }

    /// ADR-029: the one resolver for idle HUD and session freeze.
    /// Capability-truthful: Raw+E only for native ASR translation, V1/V2+E
    /// only when the polishing engine can translate.
    private func frozenSnapshot(for target: HotkeyTarget, wantsTarget: Bool) -> HotkeyLanguageSnapshot {
        HotkeyLanguageSnapshotResolver.resolve(
            hotkeyTarget: target,
            wantsTargetOutput: wantsTarget,
            requestedTargetCode: targetLanguageCode,
            backend: hudLanguageBackend,
            modelSupportsNativeTranslation: activeModelSupportsNativeTranslation,
            isGeminiCloud: isGeminiCloudBackend,
            polishingCanTranslate: polishingEngineStore.isActiveEngineTranslationCapable
        )
    }

    /// Whisper native-target sessions exist only for native-ASR snapshots
    /// (multilingual full/medium/small → English). Every other target intent
    /// stays `.asr`; the polishing pipeline owns the output language.
    private func sessionWantsWhisperTarget(_ snapshot: HotkeyLanguageSnapshot) -> Bool {
        snapshot.wantsTarget
            && snapshot.mechanism == .nativeASR
            && snapshot.targetCode?.lowercased() == "en"
            && !isGeminiCloudBackend
    }

    private func localizedSessionError(
        _ reason: TranscriptionSessionUnavailableReason
    ) -> NSError {
        NSError(
            domain: "NativeBolabol.TranscriptionSession",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: sessionUnavailableMessage(for: reason)]
        )
    }

    private func sessionUnavailableMessage(
        for reason: TranscriptionSessionUnavailableReason
    ) -> String {
        switch reason {
        case .noActiveModel:
            generalSettingsStore.text(.noLocalModelSelected)
        case .incompleteModel:
            generalSettingsStore.text(.localModelsPackageUnavailable)
        case .unsupportedOS:
            generalSettingsStore.text(.localModelsRequiresMacOS)
        case .invalidCapabilities:
            generalSettingsStore.text(.localModelsPackageUnavailable)
        case .noSupportedSource:
            generalSettingsStore.text(.localModelsCanaryLanguageBlock)
        case .unsupportedSourceLanguage(_, let requestedCode, let supportedCodes):
            generalSettingsStore.formattedText(
                .localModelsCanaryClampWarning,
                supportedCodes.map(TranscriptionLanguageOption.displayName(for:)).joined(separator: ", "),
                TranscriptionLanguageOption.displayName(for: requestedCode)
            )
        case .englishSourceRequired:
            generalSettingsStore.text(.localModelsCanary1BEnglishRequired)
        case .translationUnsupported, .unsupportedOperation:
            generalSettingsStore.text(.transcriptionSessionTranslationUnavailable)
        case .engineIdentityMismatch:
            generalSettingsStore.text(.transcriptionSessionEngineMismatch)
        }
    }

    private func languageWarningMessage(
        for warning: TranscriptionSessionLanguageWarning
    ) -> String {
        generalSettingsStore.formattedText(
            .localModelsCanaryClampWarning,
            TranscriptionLanguageOption.displayName(for: warning.effectiveSourceLanguageCode),
            TranscriptionLanguageOption.displayName(for: warning.primaryLanguageCode)
        )
    }

    /// Target language for HUD forced-target mode and post-ASR translation.
    /// The transient HUD choice takes precedence over configured language fallbacks.
    private var targetLanguageCode: String {
        HUDPolishingTranslation.resolvedHUDTargetLanguageCode(
            override: hudTargetOverride,
            speechLanguages: generalSettingsStore.speechLanguages,
            glossaryAutoLanguage: glossaryStore.settings.autoTranslationLanguage
        )
    }


    /// Compact HUD letter for the configured target language
    /// (English → E, Spanish → S, French → F, Chinese → C, …).
    private var autoTranslationLanguageLabel: String {
        TranscriptionLanguageOption.hudLabel(for: targetLanguageCode)
    }

    /// Whether the active transcription model can translate speech natively.
    /// ADR-029: only full/medium/small multilingual Whisper (X→English).
    /// Turbo is excluded (returns the source language); Parakeet, English-only
    /// Whisper, Canary, and GigaAM cannot translate natively.
    private var activeModelSupportsNativeTranslation: Bool {
        transcriptionModelStore.activeModel?.supportsNativeTranslationToEnglish ?? false
    }

    /// The processing target currently reflected by the HUD (R / 1 / 2).
    private var currentHUDTarget: HotkeyTarget {
        pendingHotkeyTarget ?? hotkeySettingsStore.settings.target
    }

    private var isHUDLanguageControlEnabled: Bool {
        isHUDLanguageControlEnabled(for: currentHUDTarget)
    }

    /// Whether the HUD language ("A") control should be enabled for a given target.
    /// - Gemini Cloud and native-translation models (multilingual Whisper): always.
    /// - Non-translating models (Parakeet, English-only Whisper): only for polishing
    ///   variants (1/2) and only when an LLM polishing engine is available, because
    ///   the translation is performed by the polishing model. On RAW there is no
    ///   translation path, so the control stays disabled.
    private func isHUDLanguageControlEnabled(for target: HotkeyTarget) -> Bool {
        if transcriptionModelStore.settings.backend == .geminiCloud {
            return true
        }
        if target == .raw {
            if activeModelSupportsNativeTranslation {
                return true
            }
            // ADR-029: no session construction in HUD computed properties.
            // Canary offers a source switcher iff it has >1 verified source.
            if transcriptionModelStore.activeModel?.backend == .canaryCoreML {
                return idleCanarySourceChoices.count > 1
            }
            return false
        }
        return polishingEngineStore.isActiveEngineTranslationCapable
    }

    /// Verified Canary source choices from capabilities + the speech pair —
    /// the same policy the session resolver uses, without building a session.
    private var idleCanarySourceChoices: [String] {
        let languages = generalSettingsStore.speechLanguages
        return HUDLanguageMenuPolicy.canarySourceCodes(
            primary: languages.primaryLanguageCode,
            additional: languages.additionalLanguageCode,
            supportedCodes: transcriptionModelStore.activeModel?.capabilities.explicitSupportedLanguageCodes ?? []
        )
    }

    private var effectiveHUDForceTargetLanguage: Bool {
        HotkeyLanguageSnapshotResolver.userWantsTargetOutput(
            for: currentHUDTarget,
            forceTargetLanguage: persistentHUDForceTargetLanguage
        )
    }

    /// ADR-029: idle HUD uses the same resolver as the session freeze, and a
    /// recording HUD reflects the frozen snapshot — never ambient state, and
    /// no session is constructed here. The letter is active only when the
    /// snapshot is capability-truthful (Raw+E native-only; V1/V2+E iff the
    /// polishing engine can translate).
    private var effectiveHUDLanguageMode: TranscriptionLanguageMode {
        if audioRecorder.isRecording, let snapshot = pendingHotkeySnapshot {
            if snapshot.wantsTarget {
                return .target
            }
            return pendingHotkeySession?.plan.languageMode ?? .auto
        }
        if let sessionPlan = pendingHotkeySession?.plan {
            return sessionPlan.languageMode
        }
        let idle = frozenSnapshot(for: currentHUDTarget, wantsTarget: effectiveHUDForceTargetLanguage)
        if idle.wantsTarget {
            return .target
        }
        if transcriptionModelStore.activeModel?.backend == .canaryCoreML {
            return idleCanarySourceChoices.count > 1 ? .switchable : .fixed
        }
        if isExplicitCoreMLBackend {
            return .switchable
        }
        return .auto
    }

    private var effectiveHUDLanguageLabel: String {
        if audioRecorder.isRecording, let snapshot = pendingHotkeySnapshot {
            if snapshot.wantsTarget {
                return snapshot.hudLetter
            }
            return pendingHotkeySession?.plan.hudLanguageLabel ?? snapshot.hudLetter
        }
        if let sessionPlan = pendingHotkeySession?.plan {
            return sessionPlan.hudLanguageLabel
        }
        let idle = frozenSnapshot(for: currentHUDTarget, wantsTarget: effectiveHUDForceTargetLanguage)
        if idle.wantsTarget {
            return idle.hudLetter
        }
        if transcriptionModelStore.activeModel?.backend == .canaryCoreML {
            let languages = generalSettingsStore.speechLanguages
            let sourceCode = canarySourceOverride ?? languages.primaryLanguageCode
            return TranscriptionLanguageOption.hudLabel(for: sourceCode)
        }
        if isExplicitCoreMLBackend {
            let languages = generalSettingsStore.speechLanguages
            let sourceCode = canarySourceOverride ?? languages.primaryLanguageCode
            return TranscriptionLanguageOption.hudLabel(for: sourceCode)
        }
        return autoTranslationLanguageLabel
    }

    /// Toggles the transcription language mode between auto-detection
    /// and the configured target language, persisting the selection for future sessions.
    private func handleOverlayLanguageTap() {
        dismissLanguagePickerPopover()
        let languages = generalSettingsStore.speechLanguages

        if currentHUDTarget == .raw {
            if let session = pendingHotkeySession {
                switch session.plan.backend {
                case .canaryCoreML:
                    let current = session.plan.sourceLanguageCode ?? canarySourceOverride ?? languages.primaryLanguageCode
                    let choices = HUDLanguageMenuPolicy.canarySourceCodes(
                        primary: languages.primaryLanguageCode,
                        additional: languages.additionalLanguageCode,
                        supportedCodes: session.plan.capabilities.explicitSupportedLanguageCodes
                    )
                    if let nextSource = HUDLanguageMenuPolicy.nextCode(current: current, choices: choices) {
                        canarySourceOverride = nextSource
                        _ = replacePendingCanarySession(withSourceLanguageCode: nextSource)
                    }
                    return
                case .gigaAMCoreML:
                    return
                case .whisperKitCoreML, .fluidAudioCoreML:
                    break
                }
            } else if isExplicitCoreMLBackend {
                let activeModel = transcriptionModelStore.activeModel
                if activeModel?.backend == .canaryCoreML {
                    let current = canarySourceOverride ?? languages.primaryLanguageCode
                    let choices = HUDLanguageMenuPolicy.canarySourceCodes(
                        primary: languages.primaryLanguageCode,
                        additional: languages.additionalLanguageCode,
                        supportedCodes: activeModel?.capabilities.explicitSupportedLanguageCodes ?? []
                    )
                    if let nextSource = HUDLanguageMenuPolicy.nextCode(current: current, choices: choices) {
                        canarySourceOverride = nextSource
                        hotkeySessionOverlayManager.update(
                            languageMode: .switchable,
                            targetLanguageLabel: TranscriptionLanguageOption.hudLabel(for: nextSource)
                        )
                    }
                }
                return
            }
        }

        guard isHUDLanguageControlEnabled else {
            hotkeySessionOverlayManager.update(
                languageMode: .auto,
                languageControlEnabled: false
            )
            return
        }

        persistentHUDForceTargetLanguage.toggle()
        if !persistentHUDForceTargetLanguage {
            transcriptionEngineStore.resetAllEnginesState()
        }
        if audioRecorder.isRecording {
            // ADR-029: explicit HUD action during recording always replaces
            // the frozen snapshot for this session only — even when no local
            // session exists (Gemini cloud dictation). Only the local-session
            // replacement is gated on `.available`.
            let refreshed = frozenSnapshot(
                for: currentHUDTarget,
                wantsTarget: HotkeyLanguageSnapshotResolver.userWantsTargetOutput(
                    for: currentHUDTarget,
                    forceTargetLanguage: persistentHUDForceTargetLanguage
                )
            )
            let resolution = makeLocalSession(
                forceTargetLanguage: sessionWantsWhisperTarget(refreshed),
                hotkeySession: true
            )
            let localSessionAvailable = if case .available = resolution { true } else { false }
            pendingHotkeySnapshot = HotkeyLanguageSnapshot.snapshotAfterExplicitHUDAction(
                current: pendingHotkeySnapshot,
                refreshed: refreshed,
                localSessionAvailable: localSessionAvailable
            )
            if case .available(let newSession) = resolution {
                pendingHotkeySession = newSession
            }
        }
        hotkeySessionOverlayManager.update(
            languageMode: effectiveHUDLanguageMode,
            targetLanguageLabel: effectiveHUDLanguageLabel
        )
    }

    private func replacePendingCanarySession(
        withSourceLanguageCode sourceLanguageCode: String
    ) -> TranscriptionEngineSession? {
        dismissLanguagePickerPopover()
        let normalizedSourceLanguageCode = sourceLanguageCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard audioRecorder.isRecording,
              let pendingSession = pendingHotkeySession,
              pendingSession.plan.backend == .canaryCoreML,
              pendingSession.plan.capabilities.explicitSupportedLanguageCodes.contains(normalizedSourceLanguageCode)
        else {
            return nil
        }

        let resolution = TranscriptionSessionResolver.replacingCanarySource(
            in: pendingSession.plan,
            with: normalizedSourceLanguageCode
        )
        guard case .available(let replacementPlan) = resolution else { return nil }
        let replacement = pendingSession.replacing(plan: replacementPlan)

        pendingHotkeySession = replacement
        hotkeySessionOverlayManager.update(
            languageMode: replacement.plan.languageMode,
            targetLanguageLabel: replacement.plan.hudLanguageLabel,
            languageControlEnabled: replacement.plan.languageControlEnabled,
            sessionPlan: replacement.plan
        )
        return replacement
    }

    private func handleOverlayLanguageRightClick(
        anchorView: NSView,
        location: NSPoint
    ) {
        dismissLanguagePickerPopover()

        let sessionPlan = pendingHotkeySession?.plan
        // ADR-029: Gemini cloud has no local backend; the menu policy only
        // needs a routing key here (Gemini branches below stay authoritative).
        let backend = sessionPlan?.backend ?? hudLanguageBackend
            ?? (transcriptionModelStore.settings.backend == .geminiCloud ? .whisperKitCoreML : nil)
        guard let backend else { return }

        let languages = generalSettingsStore.speechLanguages
        if lastObservedAdditionalLanguageCode != languages.additionalLanguageCode {
            // Settings is authoritative for the default Additional language. A
            // previous transient HUD target must not keep the picker marker stale.
            hudTargetOverride = nil
            lastObservedAdditionalLanguageCode = languages.additionalLanguageCode
        }
        let isAutomatic: Bool
        let currentCode: String
        let purpose: HUDLanguageMenuPolicy.PickerPurpose
        switch backend {
        case .canaryCoreML, .gigaAMCoreML:
            if currentHUDTarget == .raw {
                isAutomatic = false
                currentCode = sessionPlan?.sourceLanguageCode
                    ?? canarySourceOverride
                    ?? (backend == .gigaAMCoreML ? "ru" : languages.additionalLanguageCode)
                purpose = .explicitASRSource
            } else {
                isAutomatic = !persistentHUDForceTargetLanguage
                currentCode = persistentHUDForceTargetLanguage ? (hudTargetOverride ?? languages.additionalLanguageCode) : "auto"
                purpose = .targetLanguageSelection
            }
        case .whisperKitCoreML, .fluidAudioCoreML:
            if transcriptionModelStore.settings.backend == .geminiCloud {
                isAutomatic = !persistentHUDForceTargetLanguage
                currentCode = persistentHUDForceTargetLanguage ? (hudTargetOverride ?? languages.additionalLanguageCode) : "auto"
            } else {
                isAutomatic = sessionPlan?.isWhisperTargetMode == false && !persistentHUDForceTargetLanguage
                currentCode = sessionPlan?.isWhisperTargetMode == true
                    ? (sessionPlan?.requestedLanguageCode ?? languages.additionalLanguageCode)
                    : (hudTargetOverride ?? languages.additionalLanguageCode)
            }
            purpose = .targetLanguageSelection
        }

        let supportedCodes: [String]
        if transcriptionModelStore.settings.backend == .geminiCloud {
            supportedCodes = languages.orderedDistinctCodes
        } else if let sessionCodes = sessionPlan?.capabilities.explicitSupportedLanguageCodes, !sessionCodes.isEmpty {
            supportedCodes = sessionCodes
        } else if let activeCodes = transcriptionModelStore.activeModel?.capabilities.explicitSupportedLanguageCodes, !activeCodes.isEmpty {
            supportedCodes = activeCodes
        } else {
            supportedCodes = LanguagePickerOrder.orderedSpeechCodes
        }

        let options = HUDLanguageMenuPolicy.options(
            backend: backend,
            languages: languages,
            supportedSourceCodes: supportedCodes,
            currentCode: currentCode,
            isAutomatic: isAutomatic,
            uiLanguage: generalSettingsStore.settings.uiLanguage,
            systemLocale: .current,
            purpose: purpose
        )

        languagePickerController.present(
            options: options,
            languages: languages,
            anchorView: anchorView,
            location: location,
            onSelectLanguage: { popoverID, selectedCode in
                self.handleOverlayLanguageSelection(selectedCode, popoverID: popoverID)
            },
            onSelectPrimaryLanguage: { popoverID, selectedCode in
                self.handleOverlayPrimaryLanguageSelection(selectedCode, popoverID: popoverID)
            },
            onClose: { _ in
            }
        )
    }

    private func handleOverlayLanguageSelection(_ code: String, popoverID: UUID) {
        guard languagePickerController.popoverID == nil || languagePickerController.popoverID == popoverID else { return }

        let backend = pendingHotkeySession?.plan.backend ?? hudLanguageBackend
            ?? (transcriptionModelStore.settings.backend == .geminiCloud ? .whisperKitCoreML : nil)
        guard let backend else { return }

        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if currentHUDTarget != .raw {
            applyTargetSelection(normalizedCode, backend: backend)
            return
        }

        switch backend {
        case .canaryCoreML:
            let automatic = normalizedCode == "auto"
            if !automatic {
                canarySourceOverride = normalizedCode
            }
            if audioRecorder.isRecording {
                _ = replacePendingCanarySession(withSourceLanguageCode: normalizedCode)
            } else {
                hotkeySessionOverlayManager.update(
                    languageMode: .switchable,
                    targetLanguageLabel: TranscriptionLanguageOption.hudLabel(for: normalizedCode)
                )
            }
        case .gigaAMCoreML:
            return
        case .whisperKitCoreML, .fluidAudioCoreML:
            applyTargetSelection(normalizedCode, backend: backend)
        }
    }

    /// ADR-029: explicit target pick (E on/off). During a recording it also
    /// replaces the frozen snapshot; otherwise it affects the next session.
    private func applyTargetSelection(_ normalizedCode: String, backend: TranscriptionModelDescriptor.Backend) {
        _ = backend
        let automatic = normalizedCode == "auto"
        hudTargetOverride = automatic ? nil : normalizedCode
        persistentHUDForceTargetLanguage = !automatic

        if !automatic {
            applyHUDAdditionalLanguageSelection(normalizedCode)
        } else {
            transcriptionEngineStore.resetAllEnginesState()
        }
        if audioRecorder.isRecording {
            // ADR-029: explicit target pick during recording always replaces
            // the frozen snapshot — even when no local session exists (Gemini
            // cloud dictation). Only the local-session replacement is gated
            // on `.available`.
            let refreshed = frozenSnapshot(
                for: currentHUDTarget,
                wantsTarget: HotkeyLanguageSnapshotResolver.userWantsTargetOutput(
                    for: currentHUDTarget,
                    forceTargetLanguage: !automatic
                )
            )
            let resolution = makeLocalSession(
                forceTargetLanguage: sessionWantsWhisperTarget(refreshed),
                hotkeySession: true
            )
            let localSessionAvailable = if case .available = resolution { true } else { false }
            pendingHotkeySnapshot = HotkeyLanguageSnapshot.snapshotAfterExplicitHUDAction(
                current: pendingHotkeySnapshot,
                refreshed: refreshed,
                localSessionAvailable: localSessionAvailable
            )
            if case .available(let replacement) = resolution {
                pendingHotkeySession = replacement
            }
        }

        hotkeySessionOverlayManager.update(
            languageMode: automatic ? effectiveHUDLanguageMode : .target,
            targetLanguageLabel: automatic ? effectiveHUDLanguageLabel : autoTranslationLanguageLabel
        )
    }
    private func handleOverlayPrimaryLanguageSelection(_ code: String, popoverID: UUID) {
        guard languagePickerController.popoverID == nil || languagePickerController.popoverID == popoverID else { return }

        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedCode.isEmpty, normalizedCode != "auto" else { return }

        let current = generalSettingsStore.speechLanguages
        let updated = current.settingPrimary(normalizedCode)
        guard updated != current else { return }
        generalSettingsStore.speechLanguages = updated

        if audioRecorder.isRecording,
           let pendingSession = pendingHotkeySession,
           pendingSession.plan.backend == .canaryCoreML {
            _ = replacePendingCanarySession(withSourceLanguageCode: normalizedCode)
        }

        hotkeySessionOverlayManager.update(
            languageMode: effectiveHUDLanguageMode,
            targetLanguageLabel: effectiveHUDLanguageLabel
        )
    }

    /// Target-language picker selections also choose the persisted Additional
    /// speech language. The HUD override remains ephemeral for the current
    /// target/session; explicit Canary source selections never use this path.
    private func applyHUDAdditionalLanguageSelection(_ code: String) {
        guard code != "auto", LanguagePickerOrder.isKnownSpeechCode(code) else { return }

        let current = generalSettingsStore.speechLanguages
        let updated = current.settingAdditional(code)
        guard updated != current else { return }
        generalSettingsStore.speechLanguages = updated
    }

    /// Cycles the processing target (raw -> variant 1 -> variant 2) and persists
    /// it as the new default for future sessions. Automatically re-enables the last used
    /// polishing engine/model if polishing was previously disabled.
    private func handleOverlayTargetTap() {
        let current = pendingHotkeyTarget ?? hotkeySettingsStore.settings.target
        let next = current.next()
        pendingHotkeyTarget = next
        hotkeySettingsStore.settings.target = next
        if next != .raw {
            polishingEngineStore.ensurePolishingEnabledForWidgetTarget()
        }
        // For non-translating models the language ("A") control is only available on
        // polishing variants. Re-evaluate it after every target change and reset the
        // forced target language when the control becomes unavailable (e.g. on RAW).
        let languageControlEnabled = isHUDLanguageControlEnabled(for: next)
        let targetVariant: ProcessingVariant = (next == .x2) ? .variantTwo : .variantOne
        let activeSlot = promptTemplateStore.activeSlot(for: targetVariant)
        let slotNames = hudPromptSlotNames(for: targetVariant)
        updatePendingHotkeyPromptSnapshot(for: next)
        if audioRecorder.isRecording {
            // ADR-029: explicit HUD target cycle replaces the frozen snapshot.
            pendingHotkeyTarget = next
            pendingHotkeySnapshot = frozenSnapshot(
                for: next,
                wantsTarget: HotkeyLanguageSnapshotResolver.userWantsTargetOutput(
                    for: next,
                    forceTargetLanguage: persistentHUDForceTargetLanguage
                )
            )
        }

        hotkeySessionOverlayManager.update(
            languageMode: effectiveHUDLanguageMode,
            hotkeyTarget: next,
            targetLanguageLabel: effectiveHUDLanguageLabel,
            activePromptSlot: activeSlot,
            promptSlotNames: slotNames,
            humorLevel: hotkeySettingsStore.settings.humorLevel,
            humorSliderEnabled: hotkeySettingsStore.settings.humorSliderEnabled,
            languageControlEnabled: languageControlEnabled,
            sessionPlan: isExplicitCoreMLBackend ? pendingHotkeySession?.plan : nil
        )
    }
    /// The HUD is a live preference control. Its value is persisted immediately,
    /// while the listening session keeps its own pending copy for the eventual
    /// frozen request snapshot; cancel does not roll back the preference.
    private func handleOverlayHumorLevelChange(_ level: HumorLevel) {
        guard hotkeySettingsStore.settings.humorLevel != level else { return }
        hotkeySettingsStore.settings.humorLevel = level
    }

    private func makeHotkeyHumorSessionState(
        for target: HotkeyTarget,
        settings: HotkeySettings
    ) -> HumorSessionState {
        let variant = target.processingVariant
        return HumorSessionState(
            sliderEnabled: settings.humorSliderEnabled,
            level: settings.humorLevel,
            promptMode: settings.humorPromptMode,
            selectedVariant: variant,
            selectedPromptSlot: promptTemplateStore.activeSlot(for: variant),
            selectedPrompt: promptTemplateStore.template(for: variant)
        )
    }

    private func updatePendingHotkeyHumorSession(
        sliderEnabled: Bool? = nil,
        level: HumorLevel? = nil,
        promptMode: HumorPromptMode? = nil
    ) {
        guard var session = pendingHotkeyHumorSession else { return }
        session.update(sliderEnabled: sliderEnabled, level: level, promptMode: promptMode)
        pendingHotkeyHumorSession = session
    }

    private func updatePendingHotkeyPromptSnapshot(for target: HotkeyTarget) {
        guard var session = pendingHotkeyHumorSession else { return }
        let variant = target.processingVariant
        session.updateSelection(
            variant: variant,
            promptSlot: promptTemplateStore.activeSlot(for: variant),
            prompt: promptTemplateStore.template(for: variant)
        )
        pendingHotkeyHumorSession = session
    }

    private func freezeHotkeyHumorSession(for target: HotkeyTarget) -> HumorSessionSnapshot? {
        guard var session = pendingHotkeyHumorSession else { return nil }
        let variant = target.processingVariant
        session.updateSelection(
            variant: variant,
            promptSlot: promptTemplateStore.activeSlot(for: variant),
            prompt: promptTemplateStore.template(for: variant)
        )
        let snapshot = session.freeze()
        pendingHotkeyHumorSession = nil
        return snapshot
    }

    private var currentHUDPromptVariant: ProcessingVariant {
        currentHUDTarget == .x2 ? .variantTwo : .variantOne
    }

    private var currentHUDActivePromptSlot: PromptSlot {
        promptTemplateStore.activeSlot(for: currentHUDPromptVariant)
    }

    private var currentHUDPromptSlotNames: [PromptSlot: String] {
        hudPromptSlotNames(for: currentHUDPromptVariant)
    }

    private func hudPromptSlotNames(for variant: ProcessingVariant) -> [PromptSlot: String] {
        Dictionary(
            uniqueKeysWithValues: PromptSlot.allCases.map { slot in
                let storedName = promptTemplateStore.slotName(in: slot, for: variant)
                let localizedDefault: String
                switch slot {
                case .default:
                    localizedDefault = generalSettingsStore.text(.promptSlotDefault)
                case .customOne:
                    localizedDefault = generalSettingsStore.text(.promptSlotCustomOne)
                case .customTwo:
                    localizedDefault = generalSettingsStore.text(.promptSlotCustomTwo)
                case .customThree:
                    localizedDefault = generalSettingsStore.text(.promptSlotCustomThree)
                case .customFour:
                    localizedDefault = generalSettingsStore.text(.promptSlotCustomFour)
                }
                return (slot, storedName == slot.title ? localizedDefault : storedName)
            }
        )
    }

    private func handleOverlayPromptSlotChange(_ slot: PromptSlot) {
        promptTemplateStore.setActiveSlot(slot, for: currentHUDPromptVariant)
        updatePendingHotkeyPromptSnapshot(for: currentHUDTarget)
    }

    /// Two-stage cloud dictation:
    /// 1. Gemini Flash/Flash-Lite turns audio into a faithful, lightly cleaned Raw transcript.
    /// 2. Variant 1/2, when requested, runs as a separate text-only polishing request.
    private func transcribeRecordingViaGeminiCloud(
        _ recording: AudioRecording,
        hotkeyTarget: HotkeyTarget?,
        outputMode: HotkeyOutputMode?,
        forceTargetLanguage: Bool,
        languageSnapshot: HotkeyLanguageSnapshot? = nil,
        humorSnapshot: HumorSessionSnapshot? = nil
    ) async {
        let google = polishingEngineStore.apiSettings.configuration(for: .google)
        let resolvedTarget = hotkeyTarget ?? hotkeySettingsStore.settings.target
        // ADR-029: frozen snapshot or idle resolution; Gemini natively
        // translates to any target (mechanism nativeASR).
        let snapshot = languageSnapshot ?? frozenSnapshot(
            for: hotkeyTarget ?? .note,
            wantsTarget: HotkeyLanguageSnapshotResolver.userWantsTargetOutput(
                for: hotkeyTarget ?? .note,
                forceTargetLanguage: persistentHUDForceTargetLanguage || forceTargetLanguage
            )
        )
        let targetName = TranscriptionLanguageOption.displayName(
            for: snapshot.targetCode ?? targetLanguageCode
        )

        let note = noteStore.addRecordedNote(recording: recording, now: .now)
        let noteID = note.id
        noteStore.markTranscriptionStarted(for: noteID, backendName: "Google Gemini")
        SessionLedger.shared.record(
            sessionID: hotkeyOwnerID.uuidString,
            event: "transcription.start",
            fields: ["model": "gemini-cloud", "wantsTarget": "\(snapshot.wantsTarget)"]
        )

        do {
            let engine = GeminiCloudDictationEngine(
                apiKeys: google.sanitizedAPIKeys,
                modelID: google.textModel
            )
            let result = try await engine.dictate(
                GeminiCloudDictationEngine.DictationRequest(
                    audioFileURL: recording.fileURL,
                    forceTargetLanguage: snapshot.wantsTarget && snapshot.mechanism == .nativeASR,
                    targetLanguageName: targetName
                )
            )

            let glossarySettings = glossaryStore.settings
            let rewrittenRaw = glossarySettings.enabled
                ? GlossaryTextRewriter.apply(
                    to: result.text,
                    entries: glossarySettings.entries,
                    target: .source
                )
                : GlossaryTextRewriter.Result(text: result.text, count: 0)

            noteStore.applyTranscriptionResult(
                for: noteID,
                result: TranscriptionResult(
                    text: rewrittenRaw.text,
                    diagnostics: result.diagnostics
                )
            )

            usageStatisticsStore.record(
                modelID: result.diagnostics.backendName,
                modelName: result.diagnostics.backendName,
                diagnostics: result.diagnostics
            )
            SessionLedger.shared.record(
                sessionID: hotkeyOwnerID.uuidString,
                event: "transcription.done",
                fields: ["chars": "\(rewrittenRaw.text.count)"]
            )

            let polishVariants = resolvedTarget == .raw ? [] : [resolvedTarget.processingVariant]
            selectedVariant = resolvedTarget.processingVariant
            let resolved = await polishAndResolveOutput(
                noteID: noteID,
                hotkeyTarget: hotkeyTarget,
                snapshot: snapshot,
                polishVariants: polishVariants,
                humorSnapshot: humorSnapshot
            )
            selectedVariant = resolvedTarget.processingVariant
            applyHotkeyOutputIfNeeded(for: noteID, target: resolvedTarget, mode: outputMode, dispatchText: resolved.dispatchText)
            finishHotkeySessionIfNeeded(target: hotkeyTarget == nil ? nil : resolvedTarget, fallbackSignalled: resolved.fallbackSignalled)
        } catch {
            NativeBolabolLog.transcription.error(
                "Gemini cloud dictation failed: \(error.localizedDescription, privacy: .public)"
            )
            noteStore.markTranscriptionFailed(
                for: noteID,
                message: error.localizedDescription,
                backendName: "Google Gemini"
            )
            if resolvedTarget != .raw {
                noteStore.markPolishingFailed(
                    for: noteID,
                    variant: resolvedTarget.processingVariant,
                    message: error.localizedDescription,
                    backendName: polishingEngineStore.activeEngine.displayName
                )
            }
            selectedVariant = resolvedTarget.processingVariant
            finishHotkeySessionIfNeeded(target: hotkeyTarget == nil ? nil : resolvedTarget)
        }
    }

    private func syncLocalizedServices() {
        audioRecorder.setTextProvider(generalSettingsStore.text)
        translationAudioRecorder.setTextProvider(generalSettingsStore.text)
    }

    private func markPolishingUnavailable(for noteID: BolabolNote.ID) {
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
        .environmentObject(UpdateCoordinator(driver: FakeUpdateDriver()))
}
