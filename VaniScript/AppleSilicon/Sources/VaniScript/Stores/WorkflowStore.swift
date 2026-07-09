import AppKit
@preconcurrency import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import VaniScriptCore
import WhisperKit

enum RecordingMode: String, CaseIterable, Identifiable {
    case system
    case microphone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .microphone: "Mic / Virtual"
        }
    }

    var fileBaseName: String {
        switch self {
        case .system: "System Audio Recording"
        case .microphone: "Microphone Recording"
        }
    }
}

struct RecordingInputDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

@MainActor
final class WorkflowStore: ObservableObject {
    @Published var workflow: WorkflowState

    // Onboarding Tour State
    @Published public var isTourActive = false
    @Published public var tourStepIndex = 0
    @Published public var tourLanguage = "en"
    @Published public var selectedSettingsTab: SettingsTab = .apiKeys
    @Published public var activeTourScreen = ""

    @Published var outputFormat: OutputFormat = .txt
    @Published var viewMode: ReviewViewMode = .dual
    @Published var statusMessage = ""
    @Published var projects: [ProjectRecord]
    @Published var isProjectSidebarPresented = false
    @Published var showChatSidebar = false
    @Published var isLinkImporterPresented = false
    @Published var visualEditorDraft: VisualClipEditorDraft?
    @Published var linkImportURL = ""
    @Published var linkImportMessage = ""
    @Published var linkImportProgress: Double? = nil
    @Published var isImportingLink = false
    @Published var linkImportAudioOnly = false
    @Published var isLinkImportCompleted = false
    @Published var linkImportedURL: URL? = nil
    @Published var linkImportedTitle: String? = nil
    @Published var linkImportedDuration: Double? = nil
    @Published var linkImportedSourceMediaInfo: SourceMediaInfo? = nil
    @Published var isRecordingWorkspacePresented = false
    @Published var recordingMode: RecordingMode = .system
    @Published var recordingDevices: [RecordingInputDevice] = []
    @Published var selectedRecordingDeviceID = ""
    @Published var isRecordingSystemAudio = false
    @Published var isPreparingRecordingPreview = false
    @Published var isSavingRecording = false
    @Published var recordingMessage = ""
    @Published var recordingErrorMessage = ""
    @Published var recordingElapsedSec: Double = 0
    @Published var recordingAudioLevels = AudioSpectrumAnalyzer.silenceLevels
    @Published var recordingPreviewURL: URL?
    @Published var recordingPreviewDurationSec: Double = 0
    @Published var recordingPreviewTime: Double = 0
    @Published var isRecordingPreviewPlaying = false
    @Published var isPlanningShorts = false
    @Published var isAddingTranscriptTranslation = false
    @Published var isAddingShortsTranslation = false
    @Published var archiveTargetLanguage = "Russian"
    @Published var isPlayingCurrentChunk = false
    @Published var playbackTime: Double = 0
    @Published var synchronizedReviewCueID: TranscriptCue.ID?
    @Published var isErrorAlertPresented = false
    @Published var errorMessage = ""
    @Published var isScanning = false
    @Published var scanResultMessage = ""
    @Published var isScanResultAlertPresented = false
    @Published var isExportingShorts = false
    @Published var exportCompletionState: ExportCompletionState? = nil
    @Published var exportProgress: Double = 0.0
    @Published var exportStage = ""
    @Published var exportClipProgressText = ""
    @Published var exportPhaseTag = ""
    @Published var exportTotalClips: Int = 1
    @Published var exportActiveClipIndex: Int = 1
    @Published var exportDurations: [Int: Double] = [:]
    @Published var currentClipElapsedTime: Double = 0.0
    @Published var currentClipRemainingTime: Double? = nil
    @Published var overallElapsedTime: Double = 0.0
    @Published var overallRemainingTime: Double? = nil

    private var exportStartTime: Date? = nil
    private var currentClipStartTime: Date? = nil
    private var clipStartTimes: [Int: Date] = [:]
    private var exportTimer: Timer? = nil
    private var exportTask: Task<Void, Never>? = nil

    private var currentProjectID: String?
    private let clock: () -> Date
    private let buildIdentifier: String
    private let processingPipeline = NativeProcessingPipeline()
    private let reviewMLXEngine = MLXTextGenerationEngine()
    private let reviewCloudEngine = CloudTextTranslationEngine()
    private let documentMLXEngine = MLXTextGenerationEngine()
    private let shortsMLXEngine = MLXTextGenerationEngine()
    private let shortsCloudEngine = CloudTextTranslationEngine()
    private let systemAudioRecorder = SystemAudioRecorder()
    private let microphoneAudioRecorder = MicrophoneAudioRecorder()
    private var visualEditorReturnScreen: UniversalWorkflowScreen = .export
    private var processingActivity: NSObjectProtocol?
    @Published private(set) var isProcessingSegment = false
    private var audioPlayer: AVPlayer?
    private var playbackObserver: Any?
    private var recordingPlayer: AVPlayer?
    private var recordingPlaybackObserver: Any?
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?

    init(
        settings: AppSettings? = nil,
        projects: [ProjectRecord]? = nil,
        clock: @escaping () -> Date = Date.init,
        buildIdentifier: String = AppBuildIdentity.current
    ) {
        var loadedSettings = settings ?? SettingsDiskStore.load()
        loadedSettings.adaptGlossaryToTargetLanguage(targetLang: loadedSettings.defaultTargetLang)
        loadedSettings.synchronizeLocalModelsWithDisk()
        self.workflow = .initial(settings: loadedSettings)
        self.projects = ProjectArchive.sortedRecent(projects ?? ProjectDiskStore.load())
        self.clock = clock
        self.buildIdentifier = buildIdentifier
        self.archiveTargetLanguage = loadedSettings.defaultTargetLang

        // Initialize tour language based on system preferred locale
        if let preferred = Locale.preferredLanguages.first, preferred.lowercased().hasPrefix("ru") {
            self.tourLanguage = "ru"
        } else {
            self.tourLanguage = "en"
        }

        Task { @MainActor [weak self] in
            self?.scanForLocalModels(presentResult: false)
        }
    }

    public func startTour(for screen: String = "upload") {
        activeTourScreen = screen
        isTourActive = true
        if screen == "settings" {
            switch selectedSettingsTab {
            case .apiKeys: tourStepIndex = 0
            case .models: tourStepIndex = 1
            case .appearance: tourStepIndex = 2
            case .glossary: tourStepIndex = 3
            case .chunking: tourStepIndex = 4
            case .transcription: tourStepIndex = 5
            case .prompts: tourStepIndex = 6
            }
        } else {
            tourStepIndex = 0
        }
    }

    public func nextTourStep(for screen: String) {
        let steps = TourSteps.steps(for: screen)
        if tourStepIndex < steps.count - 1 {
            tourStepIndex += 1
            if screen == "settings" {
                updateSettingsTabForStep(tourStepIndex)
            }
        } else {
            isTourActive = false
            markOnboardingCompleted()
        }
    }

    public func prevTourStep(for screen: String) {
        if tourStepIndex > 0 {
            tourStepIndex -= 1
            if screen == "settings" {
                updateSettingsTabForStep(tourStepIndex)
            }
        }
    }

    public func skipTour() {
        isTourActive = false
        markOnboardingCompleted()
    }

    public func startFirstRunOnboardingIfNeeded() {
        guard OnboardingCompletionPolicy.needsOnboarding(settings: workflow.settings, currentBuildID: buildIdentifier) else { return }
        guard workflow.screen == .upload else { return }
        guard !isTourActive else { return }
        startTour(for: "upload")
    }

    private func markOnboardingCompleted() {
        guard OnboardingCompletionPolicy.needsOnboarding(settings: workflow.settings, currentBuildID: buildIdentifier) else { return }
        OnboardingCompletionPolicy.markCompleted(settings: &workflow.settings, currentBuildID: buildIdentifier)
        do {
            try SettingsDiskStore.save(workflow.settings)
        } catch {
            statusMessage = "Settings save failed: \(error.localizedDescription)"
        }
    }

    private func updateSettingsTabForStep(_ step: Int) {
        switch step {
        case 0: selectedSettingsTab = .apiKeys
        case 1: selectedSettingsTab = .models
        case 2: selectedSettingsTab = .appearance
        case 3: selectedSettingsTab = .glossary
        case 4: selectedSettingsTab = .chunking
        case 5: selectedSettingsTab = .transcription
        case 6: selectedSettingsTab = .prompts
        default: break
        }
    }


    var session: SessionState? {
        workflow.session
    }

    var currentChunk: ChunkData? {
        guard let session else { return nil }
        guard session.chunks.indices.contains(session.currentChunkIndex) else { return nil }
        return session.chunks[session.currentChunkIndex]
    }

    var approvedCount: Int {
        session?.chunks.filter(\.approved).count ?? 0
    }

    var projectSummaries: [ProjectSummary] {
        ProjectArchive.sortedRecent(projects).map(\.summary)
    }

    var activeProjectID: String? {
        currentProjectID
    }

    var settings: AppSettings {
        workflow.settings
    }

    var supportedTranslationLanguages: [String] {
        ["Russian", "Czech", "French", "German", "Polish", "English", "Hindi", "Spanish", "Swedish", "Italian", "Portuguese", "Dutch"]
    }

    var archivedTranslationLanguages: [String] {
        session?.availableTranslationLanguages ?? []
    }

    var activeTranslationLanguage: String {
        session?.selectedTranslationLanguage ?? archiveTargetLanguage
    }

    var currentTranslationText: String {
        guard let session, let chunk = currentChunk else { return "" }
        let text = chunk.translationText(for: session.selectedTranslationLanguage) ?? chunk.translated
        return TranslationArchive.isUsableTranslationText(text) ? text : ""
    }

    var editingProviders: [ProviderOption] {
        ProviderRegistry.availableTranslationProviders(
            settings: workflow.settings,
            targetLang: activeTranslationLanguage
        ).providers
    }

    var editingProviderID: String {
        session?.translationProvider ?? workflow.translationProvider
    }

    var currentOriginalCues: [TranscriptCue] {
        currentChunk?.originalCues ?? []
    }

    var currentTranslationCues: [TranscriptCue] {
        guard let session, let chunk = currentChunk else { return [] }
        let cues = chunk.translationCues(for: session.selectedTranslationLanguage)
        if cues.isEmpty, let translatedText = chunk.translationText(for: session.selectedTranslationLanguage), !translatedText.isEmpty {
            guard TranslationArchive.isUsableTranslationText(translatedText) else { return [] }
            let originalCues = chunk.originalCues ?? []
            if !originalCues.isEmpty {
                return WorkflowStore.reconstructCues(from: translatedText, matching: originalCues)
            }
        }
        return cues
    }

    public static func reconstructCues(from text: String, matching sourceCues: [TranscriptCue]) -> [TranscriptCue] {
        guard !sourceCues.isEmpty else { return [] }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TranslationArchive.isUsableTranslationText(clean) else { return [] }

        let splitTexts = NativeLLMPromptBuilder.splitTranslatedText(clean, matching: sourceCues)
        let alignedTexts: [String]
        if splitTexts.count == sourceCues.count {
            alignedTexts = splitTexts
        } else {
            var forced = splitTexts
            while forced.count < sourceCues.count {
                forced.append("")
            }
            alignedTexts = Array(forced.prefix(sourceCues.count))
        }

        return zip(sourceCues, alignedTexts).map { source, translated in
            let text = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalOutput = text.isEmpty ? "..." : text
            return TranscriptCue(
                startSec: source.startSec,
                endSec: source.endSec,
                text: finalOutput,
                words: NativeLLMPromptBuilder.approximateWords(for: finalOutput, source: source)
            )
        }
    }

    var currentPlaybackAbsoluteTime: Double {
        (currentChunk?.startSec ?? 0) + playbackTime
    }

    func setEditingProvider(_ providerID: String) {
        guard !providerID.isEmpty else { return }
        workflow.translationProvider = providerID
        if var session = workflow.session {
            session.translationProvider = providerID
            workflow.session = session
            saveCurrentProject()
        }
    }

    func presentProjectSidebar() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            isProjectSidebarPresented = true
        }

        let currentSettings = workflow.settings
        Task.detached(priority: .userInitiated) {
            let loaded = ProjectArchive.sortedRecent(ProjectDiskStore.load())
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                if self.projects != loaded {
                    self.projects = loaded
                }
                AppLogger.shared.info("Project sidebar opened. Loaded \(self.projects.count) projects.", settings: currentSettings)
            }
        }
    }

    func dismissProjectSidebar() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            isProjectSidebarPresented = false
        }
    }

    func chooseSourceFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .quickTimeMovie]
        panel.message = "Choose audio or video for VaniScript"

        guard panel.runModal() == .OK, let url = panel.url else {
            AppLogger.shared.info("User cancelled source file selection.", settings: workflow.settings)
            return
        }

        AppLogger.shared.info("User selected source file: \(url.path)", settings: workflow.settings)
        statusMessage = "Reading media metadata..."
        Task {
            let duration = await MediaDurationReader.durationSeconds(for: url)
            let sourceInfo = await SourceMediaInspector.inspect(fileURL: url, durationSec: duration)
            AppLogger.shared.info("Media duration resolved: \(duration) seconds.", settings: self.workflow.settings)
            await MainActor.run {
                selectSource(url: url, duration: duration, sourceMediaInfo: sourceInfo)
            }
        }
    }

    func presentLinkImporter() {
        linkImportURL = ""
        linkImportMessage = ""
        linkImportProgress = nil
        isImportingLink = false
        isLinkImportCompleted = false
        linkImportedURL = nil
        linkImportedTitle = nil
        linkImportedDuration = nil
        linkImportedSourceMediaInfo = nil
        isLinkImporterPresented = true
    }

    func dismissLinkImporter() {
        guard !isImportingLink else { return }
        if let linkImportedURL, isLinkImportCompleted {
            try? FileManager.default.removeItem(at: linkImportedURL)
        }
        isLinkImporterPresented = false
        isLinkImportCompleted = false
        linkImportedURL = nil
        linkImportedTitle = nil
        linkImportedDuration = nil
        linkImportedSourceMediaInfo = nil
    }

    func continueAfterLinkImport() {
        guard isLinkImportCompleted, let url = linkImportedURL else { return }
        selectSource(url: url, duration: linkImportedDuration ?? 0, sourceMediaInfo: linkImportedSourceMediaInfo)
        if let title = linkImportedTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            workflow.sourceFileName = title
            workflow.metadata = MetadataExtractor.extract(fromFileName: title)
        }
        isLinkImporterPresented = false
        isLinkImportCompleted = false
        linkImportedURL = nil
        linkImportedTitle = nil
        linkImportedDuration = nil
        linkImportedSourceMediaInfo = nil
        linkImportMessage = ""
    }

    func importDirectMediaLink() {
        guard !isImportingLink else { return }
        isImportingLink = true
        isLinkImportCompleted = false
        linkImportProgress = 0.0
        linkImportMessage = "Importing media..."
        Task {
            do {
                let importResult = try await DirectMediaImporter.importMediaWithMetadata(
                    from: linkImportURL,
                    resolverEndpoint: workflow.settings.mediaResolverEndpoint,
                    resolverToken: workflow.settings.mediaResolverToken,
                    audioOnly: linkImportAudioOnly
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.linkImportProgress = progress
                        let percent = Int(progress * 100)
                        self?.linkImportMessage = "Downloading media (\(percent)%)..."
                    }
                } onMessage: { [weak self] message in
                    Task { @MainActor in
                        self?.linkImportMessage = message
                    }
                }
                let importedURL = importResult.fileURL
                let duration = await MediaDurationReader.durationSeconds(for: importedURL)
                let sourceInfo = await SourceMediaInspector.inspect(
                    fileURL: importedURL,
                    originalURL: linkImportURL,
                    title: importResult.title,
                    durationSec: duration
                )
                await MainActor.run {
                    linkImportedURL = importedURL
                    linkImportedTitle = importResult.title
                    linkImportedDuration = duration
                    linkImportedSourceMediaInfo = sourceInfo
                    isImportingLink = false
                    isLinkImportCompleted = true
                    linkImportProgress = 1.0
                    linkImportMessage = "Ready to continue."
                }
            } catch {
                await MainActor.run {
                    isImportingLink = false
                    linkImportProgress = nil
                    linkImportMessage = error.localizedDescription
                }
            }
        }
    }

    var recordingCardStatus: String? {
        if isRecordingSystemAudio {
            return "Recording \(Self.formatRecordingTime(recordingElapsedSec))"
        }
        if isPreparingRecordingPreview {
            return "Preparing preview..."
        }
        if isSavingRecording {
            return "Saving recording..."
        }
        return nil
    }

    func presentRecordingWorkspace() {
        recordingErrorMessage = ""
        isRecordingWorkspacePresented = true
        refreshRecordingDevices()
    }

    func dismissRecordingWorkspace() {
        guard !isRecordingSystemAudio, !isPreparingRecordingPreview, !isSavingRecording else { return }
        discardRecordingPreview(removeFile: true, updateStatus: false)
        isRecordingWorkspacePresented = false
        recordingMessage = ""
        recordingErrorMessage = ""
    }

    func refreshRecordingDevices() {
        let devices = Self.availableRecordingDevices()
        recordingDevices = devices
        if !selectedRecordingDeviceID.isEmpty,
           !devices.contains(where: { $0.id == selectedRecordingDeviceID }) {
            selectedRecordingDeviceID = ""
        }
    }

    func startSystemAudioRecording() {
        recordingMode = .system
        presentRecordingWorkspace()
        startAudioRecording()
    }

    func startAudioRecording() {
        guard !isRecordingSystemAudio, !isPreparingRecordingPreview, !isSavingRecording else { return }
        discardRecordingPreview(removeFile: true, updateStatus: false)
        resetRecordingAudioLevels()
        recordingErrorMessage = ""
        recordingMessage = recordingMode == .system
            ? "Requesting Screen Recording permission..."
            : "Requesting Microphone permission..."
        statusMessage = "Starting audio recording..."

        let mode = recordingMode
        let selectedDeviceID = selectedRecordingDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let url: URL
                switch mode {
                case .system:
                    url = try await systemAudioRecorder.start(onLevels: recordingLevelHandler())
                case .microphone:
                    url = try await microphoneAudioRecorder.start(
                        deviceUniqueID: selectedDeviceID.isEmpty ? nil : selectedDeviceID,
                        onLevels: recordingLevelHandler()
                    )
                }
                await MainActor.run {
                    isRecordingSystemAudio = true
                    beginRecordingTimer()
                    recordingMessage = "Recording \(mode.fileBaseName.lowercased()) to \(url.lastPathComponent)."
                    statusMessage = "Audio recording started."
                }
            } catch {
                await MainActor.run {
                    isRecordingSystemAudio = false
                    stopRecordingTimer()
                    resetRecordingAudioLevels()
                    recordingMessage = error.localizedDescription
                    recordingErrorMessage = error.localizedDescription
                    statusMessage = "Audio recording failed."
                }
            }
        }
    }

    func stopSystemAudioRecording() {
        stopAndPreviewRecording()
    }

    func stopAndPreviewRecording() {
        guard isRecordingSystemAudio else { return }
        let mode = recordingMode
        recordingMessage = "Preparing preview..."
        recordingErrorMessage = ""
        isPreparingRecordingPreview = true

        Task {
            do {
                let url: URL
                switch mode {
                case .system:
                    url = try await systemAudioRecorder.stop()
                case .microphone:
                    url = try await microphoneAudioRecorder.stop()
                }
                let duration = await MediaDurationReader.durationSeconds(for: url)
                await MainActor.run {
                    isRecordingSystemAudio = false
                    isPreparingRecordingPreview = false
                    stopRecordingTimer()
                    resetRecordingAudioLevels()
                    recordingPreviewURL = url
                    recordingPreviewDurationSec = duration
                    recordingPreviewTime = 0
                    prepareRecordingPlayer(url: url)
                    recordingMessage = "Recording ready for review."
                    statusMessage = "Review the recording before continuing."
                }
            } catch {
                await MainActor.run {
                    isRecordingSystemAudio = false
                    isPreparingRecordingPreview = false
                    stopRecordingTimer()
                    resetRecordingAudioLevels()
                    recordingMessage = error.localizedDescription
                    recordingErrorMessage = error.localizedDescription
                    statusMessage = "Audio recording failed."
                }
            }
        }
    }

    func cancelSystemAudioRecording() {
        guard isRecordingSystemAudio else {
            dismissRecordingWorkspace()
            return
        }
        let mode = recordingMode
        Task {
            switch mode {
            case .system:
                await systemAudioRecorder.cancel()
            case .microphone:
                await microphoneAudioRecorder.cancel()
            }
            await MainActor.run {
                isRecordingSystemAudio = false
                isPreparingRecordingPreview = false
                stopRecordingTimer()
                resetRecordingAudioLevels()
                recordingMessage = ""
                recordingErrorMessage = ""
                statusMessage = "Audio recording cancelled."
            }
        }
    }

    func discardRecordingPreview() {
        discardRecordingPreview(removeFile: true, updateStatus: true)
    }

    func useRecordingPreview() {
        guard let url = recordingPreviewURL else { return }
        isSavingRecording = true
        recordingErrorMessage = ""
        recordingMessage = "Saving recording..."
        stopRecordingPreviewPlayback()
        resetRecordingAudioLevels()
        Task {
            let duration = recordingPreviewDurationSec > 0
                ? recordingPreviewDurationSec
                : await MediaDurationReader.durationSeconds(for: url)
            let sourceInfo = await SourceMediaInspector.inspect(fileURL: url, durationSec: duration)
            await MainActor.run {
                isSavingRecording = false
                isRecordingWorkspacePresented = false
                recordingPreviewURL = nil
                recordingPreviewDurationSec = 0
                recordingPreviewTime = 0
                resetRecordingAudioLevels()
                recordingMessage = ""
                selectSource(url: url, duration: duration, sourceMediaInfo: sourceInfo)
                statusMessage = "Recording ready: \(url.lastPathComponent)"
            }
        }
    }

    func toggleRecordingPreviewPlayback() {
        guard let url = recordingPreviewURL else { return }
        if recordingPlayer == nil {
            prepareRecordingPlayer(url: url)
        }
        guard let recordingPlayer else { return }
        if isRecordingPreviewPlaying {
            recordingPlayer.pause()
            isRecordingPreviewPlaying = false
        } else {
            if recordingPreviewDurationSec > 0, recordingPreviewTime >= recordingPreviewDurationSec - 0.1 {
                seekRecordingPreview(to: 0)
            }
            recordingPlayer.play()
            isRecordingPreviewPlaying = true
        }
    }

    func seekRecordingPreview(to seconds: Double) {
        let clamped = max(0, min(seconds, max(recordingPreviewDurationSec, seconds)))
        recordingPreviewTime = clamped
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        recordingPlayer?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func openRecordingsFolder() {
        let directory = AppStoragePaths.recordingsDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func cancelConfig() {
        workflow.reset()
        statusMessage = ""
    }

    func startSession() {
        workflow.startSession()
        createProjectIfNeeded()
        saveCurrentProject()
        statusMessage = "Native segment processing started."
        processCurrentChunkIfNeeded()
    }

    func openExport() {
        visualEditorDraft = nil
        workflow.openExport()
    }

    func openReview() {
        visualEditorDraft = nil
        workflow.openReview()
    }

    func openVisualEditor(at index: Int, plan: ShortsClipPlan, language: ShortsIdeaDisplayLanguage) {
        guard let session = workflow.session else { return }
        visualEditorReturnScreen = workflow.screen == .visualEditor ? .export : workflow.screen
        visualEditorDraft = VisualClipEditorDraft(index: index, plan: plan, language: language, session: session)
        workflow.screen = .visualEditor
    }

    func closeVisualEditor() {
        visualEditorDraft = nil
        workflow.screen = visualEditorReturnScreen == .visualEditor ? .export : visualEditorReturnScreen
    }

    func saveVisualEditor(_ updated: EditClipValues) {
        guard let draft = visualEditorDraft else { return }
        replaceShortsPlanTiming(at: draft.index, start: updated.start, end: updated.end)
        updateShortsPlan(
            at: draft.index,
            displayLanguage: updated.language,
            title: updated.title,
            summary: updated.summary,
            hook: updated.hook,
            category: updated.category,
            captionText: updated.captionText
        )
        updateShortsVisualEditorState(
            at: draft.index,
            sourceAlignment: updated.sourceAlignment,
            targetAlignment: updated.targetAlignment,
            sourceFrameKeyframes: updated.sourceFrameKeyframes,
            targetFrameKeyframes: updated.targetFrameKeyframes,
            timelineCuts: updated.timelineCuts,
            timelineTrim: updated.timelineTrim,
            backgroundSettings: updated.backgroundSettings,
            subtitleStyle: updated.subtitleStyle,
            syncEnabled: updated.syncEnabled,
            sourceLogo: updated.sourceLogo,
            targetLogo: updated.targetLogo,
            sourceTextTracks: updated.sourceTextTracks,
            targetTextTracks: updated.targetTextTracks,
            sourceAudioTracks: updated.sourceAudioTracks,
            targetAudioTracks: updated.targetAudioTracks,
            sourceIntro: updated.sourceIntro,
            targetIntro: updated.targetIntro,
            sourceOutro: updated.sourceOutro,
            targetOutro: updated.targetOutro
        )
    }

    func setTargetLanguage(_ targetLang: String) {
        workflow.updateTargetLanguage(targetLang)
        if TranslationArchive.isRealLanguage(targetLang) {
            archiveTargetLanguage = targetLang
        }
        updateSettings { settings in
            settings.adaptGlossaryToTargetLanguage(targetLang: targetLang)
        }
        refreshProviderSelections()
    }

    func newSession() {
        AppLogger.shared.info("Created new session. Resetting workflow.", settings: workflow.settings)
        stopPlayback()
        visualEditorDraft = nil
        workflow.reset()
        currentProjectID = nil
        statusMessage = ""
    }

    func moveChunk(delta: Int) {
        guard var session = workflow.session else { return }
        stopPlayback()
        let next = min(max(0, session.currentChunkIndex + delta), max(0, session.chunks.count - 1))
        session.currentChunkIndex = next
        synchronizedReviewCueID = nil
        workflow.session = session
        processCurrentChunkIfNeeded()
    }

    func selectChunkIndex(_ index: Int) {
        guard var session = workflow.session else { return }
        guard session.chunks.indices.contains(index) else { return }
        stopPlayback()
        session.currentChunkIndex = index
        synchronizedReviewCueID = nil
        workflow.session = session
        processCurrentChunkIfNeeded()
    }

    func approveAndAdvance() {
        guard var session = workflow.session else { return }
        guard session.chunks.indices.contains(session.currentChunkIndex) else { return }
        stopPlayback()
        session.chunks[session.currentChunkIndex].approved = true
        session.chunks[session.currentChunkIndex].status = .done

        AppLogger.shared.info("Approved segment \(session.currentChunkIndex + 1) / \(session.chunks.count).", settings: workflow.settings)

        if session.currentChunkIndex < session.chunks.count - 1 {
            session.currentChunkIndex += 1
            synchronizedReviewCueID = nil
            workflow.session = session
            saveCurrentProject()
            processCurrentChunkIfNeeded()
        } else {
            workflow.session = session
            workflow.openExport()
            saveCurrentProject()
        }
    }

    func updateCurrentOriginal(_ text: String) {
        updateCurrentChunk { chunk in
            chunk.original = text
            chunk.originalCues = nil
            chunk.status = .done
        }
    }

    func updateCurrentTranslated(_ text: String) {
        guard let language = workflow.session?.selectedTranslationLanguage else {
            updateCurrentChunk { chunk in
                chunk.translated = text
                chunk.status = .done
            }
            return
        }

        updateCurrentChunk { chunk in
            chunk.translated = text
            let originalCues = chunk.originalCues ?? []
            if TranslationArchive.isUsableTranslationText(text) {
                let reconstructed = WorkflowStore.reconstructCues(from: text, matching: originalCues)
                chunk.setTranslation(text, language: language, cues: reconstructed.isEmpty ? nil : reconstructed)
            }
            chunk.status = .done
        }
    }

    func updateCurrentOriginalCue(id: TranscriptCue.ID, text: String) {
        updateCurrentChunk { chunk in
            guard var cues = chunk.originalCues,
                  let cueIndex = cues.firstIndex(where: { $0.id == id })
            else { return }
            cues[cueIndex].text = text

            let duration = max(0.05, cues[cueIndex].endSec - cues[cueIndex].startSec)
            let splitWords = text.split(whereSeparator: \.isWhitespace).map(String.init)
            let step = duration / Double(max(1, splitWords.count))
            cues[cueIndex].words = splitWords.enumerated().map { idx, w in
                let start = cues[cueIndex].startSec + Double(idx) * step
                let end = idx == splitWords.count - 1 ? cues[cueIndex].endSec : min(cues[cueIndex].endSec, start + step)
                return TranscriptWord(startSec: start, endSec: max(start + 0.03, end), text: w)
            }

            chunk.originalCues = cues
            chunk.original = cues.map(\.text).joined(separator: " ")
            chunk.status = .done
        }
    }

    func updateCurrentTranslatedCue(id: TranscriptCue.ID, text: String) {
        guard let language = workflow.session?.selectedTranslationLanguage else { return }
        updateCurrentChunk { chunk in
            var cues = chunk.translationCues(for: language)
            guard let cueIndex = cues.firstIndex(where: { $0.id == id }) else { return }
            cues[cueIndex].text = text

            let duration = max(0.05, cues[cueIndex].endSec - cues[cueIndex].startSec)
            let splitWords = text.split(whereSeparator: \.isWhitespace).map(String.init)
            let step = duration / Double(max(1, splitWords.count))
            cues[cueIndex].words = splitWords.enumerated().map { idx, w in
                let start = cues[cueIndex].startSec + Double(idx) * step
                let end = idx == splitWords.count - 1 ? cues[cueIndex].endSec : min(cues[cueIndex].endSec, start + step)
                return TranscriptWord(startSec: start, endSec: max(start + 0.03, end), text: w)
            }

            let translated = cues.map(\.text).joined(separator: "\n")
            chunk.translated = translated
            chunk.setTranslation(translated, language: language, cues: cues)
            chunk.status = .done
        }
    }

    func addSelectionToGlossary(_ selectedText: String, side: TranscriptSide) {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return }

        let targetLanguage = activeTranslationLanguage
        let translation = side == .translated ? selected : ""
        let entry = GlossaryEntry(
            id: UUID().uuidString,
            variants: [],
            source: selected,
            translation: translation,
            category: "Review Selection",
            translations: side == .translated && TranslationArchive.isRealLanguage(targetLanguage)
                ? [targetLanguage: selected]
                : [:],
            remember: true,
            createdAt: isoString(clock()),
            updatedAt: isoString(clock())
        )

        updateSettings { settings in
            settings.glossary.insert(entry, at: 0)
        }
        statusMessage = "Added selected text to glossary."
    }

    func replaceCueSelection(
        cueID: TranscriptCue.ID,
        side: TranscriptSide,
        selectedText: String,
        contextText: String,
        replacementText: String
    ) {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return }

        switch side {
        case .original:
            updateCurrentChunk { chunk in
                guard var cues = chunk.originalCues,
                      let cueIndex = cues.firstIndex(where: { $0.id == cueID })
                else { return }

                let result = TextSnippetRevision.replaceSelectedText(
                    in: cues[cueIndex].text,
                    selectedText: selected,
                    replacementText: replacement,
                    contextText: contextText
                )
                guard result.changed else { return }
                cues[cueIndex].text = result.text
                cues[cueIndex].words = NativeLLMPromptBuilder.approximateWords(for: result.text, source: cues[cueIndex])
                chunk.originalCues = cues
                chunk.original = cues.map(\.text).joined(separator: " ")
                chunk.status = .done
            }
        case .translated:
            guard let language = workflow.session?.selectedTranslationLanguage else { return }
            updateCurrentChunk { chunk in
                var cues = chunk.translationCues(for: language)
                guard let cueIndex = cues.firstIndex(where: { $0.id == cueID }) else { return }

                let result = TextSnippetRevision.replaceSelectedText(
                    in: cues[cueIndex].text,
                    selectedText: selected,
                    replacementText: replacement,
                    contextText: contextText
                )
                guard result.changed else { return }
                cues[cueIndex].text = result.text
                cues[cueIndex].words = NativeLLMPromptBuilder.approximateWords(for: result.text, source: cues[cueIndex])
                let translated = cues.map(\.text).joined(separator: "\n")
                chunk.translated = translated
                chunk.setTranslation(
                    translated,
                    language: language,
                    updatedAt: isoString(clock()),
                    cues: cues
                )
                chunk.status = .done
            }
        }

        statusMessage = "Text snippet updated."
        saveCurrentProject()
    }

    @discardableResult
    func globalSearchAndReplace(
        query: String,
        replacement: String,
        targetSide: TranscriptSide,
        language: String?,
        caseSensitive: Bool = false,
        wholeWord: Bool = false
    ) -> Int {
        guard var session = workflow.session, !query.isEmpty else { return 0 }

        let pattern: String
        if wholeWord {
            pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: query) + "(?![\\p{L}\\p{N}_])"
        } else {
            pattern = NSRegularExpression.escapedPattern(for: query)
        }

        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return 0
        }

        var totalReplacements = 0

        for index in session.chunks.indices {
            var chunk = session.chunks[index]
            var chunkReplaced = false

            switch targetSide {
            case .original:
                let originalText = chunk.original
                let range = NSRange(originalText.startIndex..<originalText.endIndex, in: originalText)
                let matches = regex.matches(in: originalText, range: range)
                if !matches.isEmpty {
                    let updated = regex.stringByReplacingMatches(in: originalText, range: range, withTemplate: replacement)
                    chunk.original = updated
                    chunkReplaced = true
                    totalReplacements += matches.count
                }

                if var cues = chunk.originalCues {
                    var cuesReplaced = false
                    for cueIdx in cues.indices {
                        let cueText = cues[cueIdx].text
                        let cueRange = NSRange(cueText.startIndex..<cueText.endIndex, in: cueText)
                        let cueMatches = regex.matches(in: cueText, range: cueRange)
                        if !cueMatches.isEmpty {
                            let updatedCue = regex.stringByReplacingMatches(in: cueText, range: cueRange, withTemplate: replacement)
                            cues[cueIdx].text = updatedCue
                            cues[cueIdx].words = NativeLLMPromptBuilder.approximateWords(for: updatedCue, source: cues[cueIdx])
                            cuesReplaced = true
                            if !chunkReplaced {
                                totalReplacements += cueMatches.count
                            }
                        }
                    }
                    if cuesReplaced {
                        chunk.originalCues = cues
                        chunk.original = cues.map(\.text).joined(separator: " ")
                        chunkReplaced = true
                    }
                }

            case .translated:
                guard let activeLang = language ?? session.selectedTranslationLanguage else { continue }
                let translatedText = chunk.translated
                let range = NSRange(translatedText.startIndex..<translatedText.endIndex, in: translatedText)
                let matches = regex.matches(in: translatedText, range: range)
                if !matches.isEmpty {
                    let updated = regex.stringByReplacingMatches(in: translatedText, range: range, withTemplate: replacement)
                    chunk.translated = updated
                    chunkReplaced = true
                    totalReplacements += matches.count
                }

                var cues = chunk.translationCues(for: activeLang)
                if !cues.isEmpty {
                    var cuesReplaced = false
                    for cueIdx in cues.indices {
                        let cueText = cues[cueIdx].text
                        let cueRange = NSRange(cueText.startIndex..<cueText.endIndex, in: cueText)
                        let cueMatches = regex.matches(in: cueText, range: cueRange)
                        if !cueMatches.isEmpty {
                            let updatedCue = regex.stringByReplacingMatches(in: cueText, range: cueRange, withTemplate: replacement)
                            cues[cueIdx].text = updatedCue
                            cues[cueIdx].words = NativeLLMPromptBuilder.approximateWords(for: updatedCue, source: cues[cueIdx])
                            cuesReplaced = true
                            if !chunkReplaced {
                                totalReplacements += cueMatches.count
                            }
                        }
                    }
                    if cuesReplaced {
                        let translated = cues.map(\.text).joined(separator: "\n")
                        chunk.translated = translated
                        chunk.setTranslation(
                            translated,
                            language: activeLang,
                            updatedAt: isoString(clock()),
                            cues: cues
                        )
                        chunkReplaced = true
                    }
                } else if chunkReplaced {
                    chunk.setTranslation(
                        chunk.translated,
                        language: activeLang,
                        updatedAt: isoString(clock())
                    )
                }
            }

            if chunkReplaced {
                chunk.status = .done
                session.chunks[index] = chunk
            }
        }

        if totalReplacements > 0 {
            session.normalizeTranslationArchive()
            workflow.session = session
            saveCurrentProject()
            statusMessage = "Replaced \(totalReplacements) occurrence(s)."
        }

        return totalReplacements
    }


    func addGlossaryVariants(
        entryID: GlossaryEntry.ID,
        variantsText: String,
        selectedText: String,
        currentChunkOnly: Bool
    ) {
        let variants = WorkflowStore.parseGlossaryVariants(variantsText, fallback: selectedText)
        guard !variants.isEmpty else { return }
        var updatedEntry: GlossaryEntry?

        updateSettings { settings in
            guard let entryIndex = settings.glossary.firstIndex(where: { $0.id == entryID }) else { return }
            let existingKeys = Set(settings.glossary[entryIndex].variants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            let sourceKey = settings.glossary[entryIndex].source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let translationKey = settings.glossary[entryIndex].translation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let additions = variants.filter { variant in
                let key = variant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !key.isEmpty && key != sourceKey && key != translationKey && !existingKeys.contains(key)
            }
            if !additions.isEmpty {
                settings.glossary[entryIndex].variants.append(contentsOf: additions)
                settings.glossary[entryIndex].updatedAt = isoString(clock())
            }
            updatedEntry = settings.glossary[entryIndex]
        }

        if let updatedEntry {
            let replacements = applyGlossaryEntryToWorkflow(updatedEntry, currentChunkOnly: currentChunkOnly)
            statusMessage = replacements > 0
                ? "Glossary variant added and applied to \(replacements) occurrence\(replacements == 1 ? "" : "s")."
                : "Glossary variant saved."
        } else {
            statusMessage = "Glossary already contains this variant."
        }
    }

    func createGlossaryEntryFromReview(
        source: String,
        translation: String,
        category: String,
        variantsText: String,
        selectedText: String,
        currentChunkOnly: Bool
    ) {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSource = cleanSource.isEmpty ? selected : cleanSource
        guard !finalSource.isEmpty || !cleanTranslation.isEmpty else { return }

        let language = activeTranslationLanguage
        let variants = WorkflowStore.parseGlossaryVariants(variantsText, fallback: selected)
        let entry = GlossaryEntry(
            id: UUID().uuidString,
            variants: variants.filter {
                let key = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return key != finalSource.lowercased() && key != cleanTranslation.lowercased()
            },
            source: finalSource,
            translation: cleanTranslation,
            category: category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : category.trimmingCharacters(in: .whitespacesAndNewlines),
            translations: TranslationArchive.isRealLanguage(language) && !cleanTranslation.isEmpty ? [language: cleanTranslation] : [:],
            remember: true,
            createdAt: isoString(clock()),
            updatedAt: isoString(clock())
        )

        updateSettings { settings in
            settings.glossary.insert(entry, at: 0)
        }
        let replacements = applyGlossaryEntryToWorkflow(entry, currentChunkOnly: currentChunkOnly)
        statusMessage = replacements > 0
            ? "Glossary term created and applied to \(replacements) occurrence\(replacements == 1 ? "" : "s")."
            : "Glossary term created."
    }

    func retranslateCue(_ cueID: TranscriptCue.ID) {
        guard !isAddingTranscriptTranslation else { return }
        guard let session,
              let chunk = currentChunk,
              let sourceCue = (chunk.originalCues ?? []).first(where: { $0.id == cueID })
        else { return }
        let targetLanguage = TranslationArchive.displayLanguage(session.selectedTranslationLanguage ?? archiveTargetLanguage)
        guard TranslationArchive.isRealLanguage(targetLanguage) else {
            statusMessage = "Choose a target language before re-translating a cue."
            return
        }
        isAddingTranscriptTranslation = true
        statusMessage = "Re-translating selected cue..."
        Task {
            do {
                let translated: String
                let providerID: String
                if let cloudProvider = activeCloudTranslationProvider(for: session) {
                    translated = try await reviewCloudEngine.translate(
                        text: sourceCue.text,
                        targetLang: targetLanguage,
                        metadata: session.metadata,
                        glossary: workflow.settings.glossary,
                        provider: cloudProvider,
                        promptPresets: workflow.settings.promptPresets
                    )
                    providerID = cloudProvider.id
                } else if let model = activeTranslationModel(for: session) {
                    translated = try await reviewMLXEngine.translate(
                        text: sourceCue.text,
                        targetLang: targetLanguage,
                        metadata: session.metadata,
                        glossary: workflow.settings.glossary,
                        model: model,
                        promptPresets: workflow.settings.promptPresets
                    )
                    providerID = model.id
                } else {
                    throw TranslationRoutingError.noTranslationProvider
                }
                await MainActor.run {
                    applyTranslatedCueText(cueID: cueID, text: translated, language: targetLanguage, provider: providerID)
                    isAddingTranscriptTranslation = false
                    statusMessage = "Cue re-translated."
                    saveCurrentProject()
                }
            } catch {
                await MainActor.run {
                    isAddingTranscriptTranslation = false
                    statusMessage = "Cue re-translation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func polishTranslatedSelection(cueID: TranscriptCue.ID, selectedText: String) {
        guard !isAddingTranscriptTranslation else { return }
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty, let session else { return }
        let targetLanguage = TranslationArchive.displayLanguage(session.selectedTranslationLanguage ?? archiveTargetLanguage)
        guard TranslationArchive.isRealLanguage(targetLanguage) else { return }
        guard let model = activeTranslationModel(for: session) else {
            statusMessage = "Locate a downloaded MLX model before polishing selection."
            return
        }

        isAddingTranscriptTranslation = true
        statusMessage = "Polishing selected translation..."
        Task {
            do {
                let polished = try await reviewMLXEngine.polish(
                    text: selected,
                    targetLang: targetLanguage,
                    model: model,
                    lecturer: session.metadata.lecturer,
                    glossary: workflow.settings.glossary,
                    promptPresets: workflow.settings.promptPresets
                )
                await MainActor.run {
                    replaceSelectionInTranslatedCue(cueID: cueID, selectedText: selected, replacement: polished)
                    isAddingTranscriptTranslation = false
                    statusMessage = "Selected translation polished."
                    saveCurrentProject()
                }
            } catch {
                await MainActor.run {
                    isAddingTranscriptTranslation = false
                    statusMessage = "Selection polish failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func polishCurrentTranslation() {
        guard let session,
              !currentTranslationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            statusMessage = "No translated text to polish."
            return
        }

        let textToPolish = currentTranslationText
        let language = session.selectedTranslationLanguage ?? session.targetLang

        guard let model = NativeModelCatalog.activeMLXModel(
            settings: workflow.settings,
            providerID: session.translationProvider
        ) else {
            statusMessage = "Locate a downloaded MLX model in Settings before polishing."
            return
        }

        statusMessage = "Polishing translation with MLX..."
        Task {
            do {
                let polished = try await reviewMLXEngine.polish(
                    text: textToPolish,
                    targetLang: language,
                    model: model,
                    lecturer: session.metadata.lecturer,
                    glossary: workflow.settings.glossary,
                    promptPresets: workflow.settings.promptPresets
                )
                await MainActor.run {
                    updateCurrentTranslated(polished)
                    statusMessage = "MLX polish complete."
                }
            } catch {
                await MainActor.run {
                    statusMessage = "MLX polish failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func activateTranslationLanguage(_ language: String) {
        guard var session = workflow.session else { return }
        stopPlayback()
        session.setActiveTranslationLanguage(language)
        workflow.session = session
        workflow.targetLang = language
        archiveTargetLanguage = language
        saveCurrentProject()
    }

    func addTranscriptTranslation() {
        guard !isAddingTranscriptTranslation else { return }
        guard var session else { return }
        let targetLanguage = TranslationArchive.displayLanguage(archiveTargetLanguage)
        guard TranslationArchive.isRealLanguage(targetLanguage) else {
            statusMessage = "Choose a target language for the added translation."
            return
        }
        let cloudProvider = activeCloudTranslationProvider(for: session)
        let model = cloudProvider == nil ? activeTranslationModel(for: session) : nil
        guard cloudProvider != nil || model != nil else {
            statusMessage = "Choose a cloud translation provider with an API key, or locate a downloaded MLX model."
            return
        }

        isAddingTranscriptTranslation = true
        statusMessage = "Adding \(targetLanguage) transcript translation..."
        session.setActiveTranslationLanguage(targetLanguage)
        workflow.session = session
        workflow.targetLang = targetLanguage
        saveCurrentProject()

        Task {
            var updated = session
            do {
                for index in updated.chunks.indices {
                    let original = updated.chunks[index].original.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !original.isEmpty else { continue }

                    await MainActor.run {
                        statusMessage = "Translating segment \(index + 1) / \(updated.chunks.count) to \(targetLanguage)..."
                    }

                    let translatedCues: [TranscriptCue]
                    let translated: String
                    let providerID: String
                    if let cloudProvider {
                        translatedCues = try await translateCurrentStoredCuesWithCloud(
                            updated.chunks[index].originalCues ?? [],
                            targetLanguage: targetLanguage,
                            metadata: updated.metadata,
                            provider: cloudProvider
                        )
                        translated = translatedCues.isEmpty
                            ? try await reviewCloudEngine.translate(
                                text: original,
                                targetLang: targetLanguage,
                                metadata: updated.metadata,
                                glossary: workflow.settings.glossary,
                                provider: cloudProvider,
                                promptPresets: workflow.settings.promptPresets
                            )
                            : ""
                        providerID = cloudProvider.id
                    } else if let model {
                        translatedCues = try await translateCurrentStoredCues(
                            updated.chunks[index].originalCues ?? [],
                            targetLanguage: targetLanguage,
                            metadata: updated.metadata,
                            model: model
                        )
                        translated = translatedCues.isEmpty
                            ? try await reviewMLXEngine.translate(
                                text: original,
                                targetLang: targetLanguage,
                                metadata: updated.metadata,
                                glossary: workflow.settings.glossary,
                                model: model,
                                promptPresets: workflow.settings.promptPresets
                            )
                            : ""
                        providerID = model.id
                    } else {
                        throw TranslationRoutingError.noTranslationProvider
                    }
                    let finalText = translatedCues.isEmpty ? translated : translatedCues.map(\.text).joined(separator: "\n")
                    updated.chunks[index].setTranslation(
                        finalText,
                        language: targetLanguage,
                        provider: providerID,
                        updatedAt: isoString(clock()),
                        cues: translatedCues.isEmpty ? nil : translatedCues
                    )
                    updated.setActiveTranslationLanguage(targetLanguage)

                    await MainActor.run {
                        workflow.session = updated
                        workflow.targetLang = targetLanguage
                        archiveTargetLanguage = targetLanguage
                        saveCurrentProject()
                    }
                }

                await MainActor.run {
                    isAddingTranscriptTranslation = false
                    statusMessage = "\(targetLanguage) transcript translation added."
                }
            } catch {
                await MainActor.run {
                    isAddingTranscriptTranslation = false
                    statusMessage = "\(targetLanguage) translation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func retryCurrentTranslation() {
        guard !isAddingTranscriptTranslation else { return }
        guard var session, let chunk = currentChunk else { return }
        let targetLanguage = TranslationArchive.displayLanguage(session.selectedTranslationLanguage ?? archiveTargetLanguage)
        guard TranslationArchive.isRealLanguage(targetLanguage) else {
            statusMessage = "Choose a target language before retrying translation."
            return
        }
        let cloudProvider = activeCloudTranslationProvider(for: session)
        let model = cloudProvider == nil ? activeTranslationModel(for: session) : nil
        guard cloudProvider != nil || model != nil else {
            statusMessage = "Choose a cloud translation provider with an API key, or locate a downloaded MLX model."
            return
        }

        let index = session.currentChunkIndex
        guard !chunk.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "No source transcript is available for translation."
            return
        }

        isAddingTranscriptTranslation = true
        statusMessage = "Retrying \(targetLanguage) translation for segment \(index + 1)..."
        session.setActiveTranslationLanguage(targetLanguage)
        workflow.session = session
        workflow.targetLang = targetLanguage
        archiveTargetLanguage = targetLanguage

        Task {
            var updated = session
            do {
                let sourceCues = updated.chunks[index].originalCues ?? []
                let translatedCues: [TranscriptCue]
                let translated: String
                let providerID: String
                if let cloudProvider {
                    translatedCues = try await translateCurrentStoredCuesWithCloud(
                        sourceCues,
                        targetLanguage: targetLanguage,
                        metadata: updated.metadata,
                        provider: cloudProvider
                    )
                    translated = translatedCues.isEmpty
                        ? try await reviewCloudEngine.translate(
                            text: updated.chunks[index].original,
                            targetLang: targetLanguage,
                            metadata: updated.metadata,
                            glossary: workflow.settings.glossary,
                            provider: cloudProvider,
                            promptPresets: workflow.settings.promptPresets
                        )
                        : translatedCues.map(\.text).joined(separator: "\n")
                    providerID = cloudProvider.id
                } else if let model {
                    translatedCues = try await translateCurrentStoredCues(
                        sourceCues,
                        targetLanguage: targetLanguage,
                        metadata: updated.metadata,
                        model: model
                    )
                    translated = translatedCues.isEmpty
                        ? try await reviewMLXEngine.translate(
                            text: updated.chunks[index].original,
                            targetLang: targetLanguage,
                            metadata: updated.metadata,
                            glossary: workflow.settings.glossary,
                            model: model,
                            promptPresets: workflow.settings.promptPresets
                        )
                        : translatedCues.map(\.text).joined(separator: "\n")
                    providerID = model.id
                } else {
                    throw TranslationRoutingError.noTranslationProvider
                }
                updated.chunks[index].translated = translated
                updated.chunks[index].setTranslation(
                    translated,
                    language: targetLanguage,
                    provider: providerID,
                    updatedAt: isoString(clock()),
                    cues: translatedCues.isEmpty ? nil : translatedCues
                )
                updated.setActiveTranslationLanguage(targetLanguage)

                await MainActor.run {
                    workflow.session = updated
                    workflow.targetLang = targetLanguage
                    archiveTargetLanguage = targetLanguage
                    isAddingTranscriptTranslation = false
                    statusMessage = "\(targetLanguage) translation updated for segment \(index + 1)."
                    saveCurrentProject()
                }
            } catch {
                await MainActor.run {
                    isAddingTranscriptTranslation = false
                    statusMessage = "\(targetLanguage) translation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func toggleCurrentChunkPlayback() {
        if isPlayingCurrentChunk {
            pausePlayback()
        } else {
            startPlayback()
        }
    }

    func regenerateCurrentSegment() {
        guard session != nil else { return }
        stopPlayback()
        statusMessage = "Regenerating current segment timings..."
        processCurrentChunkIfNeeded(force: true)
    }

    func retranscribeCurrentSegment() {
        guard session != nil else { return }
        stopPlayback()
        statusMessage = "Trying transcription again for current segment..."
        updateCurrentChunk { chunk in
            chunk.approved = false
            chunk.status = .pending
        }
        processCurrentChunkIfNeeded(force: true)
    }

    func seekCurrentChunk(to seconds: Double) {
        let safe = min(max(0, seconds), currentChunk?.durationSec ?? 0)
        playbackTime = safe
        audioPlayer?.seek(to: CMTime(seconds: safe, preferredTimescale: 600))
    }

    func addShortsTranslation() {
        guard !isAddingShortsTranslation else { return }
        guard let session, let plans = session.shortsPlans, !plans.isEmpty else {
            statusMessage = "Create Shorts/Reels moments before translating them."
            return
        }
        let targetLanguage = TranslationArchive.displayLanguage(archiveTargetLanguage)
        guard TranslationArchive.isRealLanguage(targetLanguage) else {
            statusMessage = "Choose a target language for Shorts/Reels translation."
            return
        }
        guard let model = activeTranslationModel(for: session) else {
            statusMessage = "Locate a downloaded MLX model before translating Shorts/Reels."
            return
        }

        isAddingShortsTranslation = true
        statusMessage = "Adding \(targetLanguage) Shorts/Reels translation..."

        Task {
            var updated = session
            do {
                for index in plans.indices {
                    guard let plan = updated.shortsPlans?[index] else { continue }
                    await MainActor.run {
                        statusMessage = "Translating Shorts/Reels \(index + 1) / \(plans.count) to \(targetLanguage)..."
                    }

                    let translated = try await shortsMLXEngine.translateShortsPlan(
                        plan,
                        targetLanguage: targetLanguage,
                        model: model
                    )
                    updated.shortsPlans?[index].setTranslation(translated)
                    updated.registerTranslationLanguage(targetLanguage)

                    await MainActor.run {
                        workflow.session = updated
                        archiveTargetLanguage = targetLanguage
                        saveCurrentProject()
                    }
                }

                await MainActor.run {
                    isAddingShortsTranslation = false
                    statusMessage = "\(targetLanguage) Shorts/Reels translation added."
                }
            } catch {
                await MainActor.run {
                    isAddingShortsTranslation = false
                    statusMessage = "\(targetLanguage) Shorts/Reels translation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func export(side: TranscriptSide, format: OutputFormat) {
        guard let session else { return }
        let language = side == .translated ? session.selectedTranslationLanguage : nil
        let baseContent = TranscriptExportBuilder.build(side: side, format: format, session: session, language: language)
        let defaultFileName = TranscriptExportBuilder.defaultFileName(side: side, format: format, session: session, language: language)

        guard format != .txt,
              let model = NativeModelCatalog.activeMLXModel(
                settings: workflow.settings,
                providerID: session.translationProvider
              )
        else {
            saveExportContent(baseContent, defaultFileName: defaultFileName)
            return
        }

        statusMessage = "Formatting \(format.rawValue) export with MLX..."
        Task {
            do {
                let formatted = try await documentMLXEngine.formatDocument(
                    format: format,
                    targetLang: exportTargetLanguage(side: side, session: session),
                    text: baseContent,
                    model: model
                )
                _ = await MainActor.run {
                    saveExportContent(
                        formatted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? baseContent : formatted,
                        defaultFileName: defaultFileName
                    )
                }
            } catch {
                _ = await MainActor.run {
                    statusMessage = "MLX document formatting failed, exporting deterministic file."
                    saveExportContent(baseContent, defaultFileName: defaultFileName)
                }
            }
        }
    }

    @discardableResult
    private func saveExportContent(_ content: String, defaultFileName: String) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFileName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            statusMessage = "Export cancelled."
            return false
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Export saved: \(url.lastPathComponent)"
            return true
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
            return false
        }
    }

    private func exportTargetLanguage(side: TranscriptSide, session: SessionState) -> String {
        if side == .translated {
            return session.selectedTranslationLanguage ?? session.targetLang
        }
        return session.targetLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "same"
            ? "English"
            : session.targetLang
    }

    private func activeTranslationModel(for session: SessionState) -> ActiveMLXModel? {
        reconcileLocalModelStates()
        return NativeModelCatalog.activeMLXModel(
            settings: workflow.settings,
            providerID: session.translationProvider
        ) ?? NativeModelCatalog.activeMLXModel(
            settings: workflow.settings,
            providerID: workflow.settings.translationProvider
        )
    }

    private func activeCloudTranslationProvider(for session: SessionState) -> ActiveCloudTranslationProvider? {
        ActiveCloudTranslationProvider.resolve(
            settings: workflow.settings,
            providerID: session.translationProvider
        ) ?? ActiveCloudTranslationProvider.resolve(
            settings: workflow.settings,
            providerID: workflow.settings.translationProvider
        )
    }

    private func applyTranslatedCueText(
        cueID: TranscriptCue.ID,
        text: String,
        language: String,
        provider: String
    ) {
        updateCurrentChunk { chunk in
            let sourceCues = chunk.originalCues ?? []
            guard !sourceCues.isEmpty else { return }

            var cues = chunk.translationCues(for: language)
            if cues.count != sourceCues.count {
                cues = sourceCues.map { source in
                    TranscriptCue(startSec: source.startSec, endSec: source.endSec, text: "")
                }
            }
            guard let cueIndex = cues.firstIndex(where: { $0.id == cueID }) else { return }

            cues[cueIndex].text = text
            cues[cueIndex].words = NativeLLMPromptBuilder.approximateWords(for: text, source: cues[cueIndex])
            let translated = cues.map(\.text).joined(separator: "\n")
            chunk.translated = translated
            chunk.setTranslation(
                translated,
                language: language,
                provider: provider,
                updatedAt: isoString(clock()),
                cues: cues
            )
            chunk.status = .done
        }
    }

    private func replaceSelectionInTranslatedCue(
        cueID: TranscriptCue.ID,
        selectedText: String,
        replacement: String
    ) {
        guard let language = workflow.session?.selectedTranslationLanguage else { return }
        updateCurrentChunk { chunk in
            var cues = chunk.translationCues(for: language)
            guard let cueIndex = cues.firstIndex(where: { $0.id == cueID }),
                  let range = cues[cueIndex].text.range(of: selectedText)
            else { return }

            cues[cueIndex].text.replaceSubrange(range, with: replacement)
            cues[cueIndex].words = NativeLLMPromptBuilder.approximateWords(for: cues[cueIndex].text, source: cues[cueIndex])
            let translated = cues.map(\.text).joined(separator: "\n")
            chunk.translated = translated
            chunk.setTranslation(
                translated,
                language: language,
                updatedAt: isoString(clock()),
                cues: cues
            )
            chunk.status = .done
        }
    }

    private func translateCurrentStoredCues(
        _ cues: [TranscriptCue],
        targetLanguage: String,
        metadata: AudioMetadata,
        model: ActiveMLXModel
    ) async throws -> [TranscriptCue] {
        guard !cues.isEmpty else { return [] }
        return try await reviewMLXEngine.translateCues(
            cues,
            targetLang: targetLanguage,
            metadata: metadata,
            glossary: workflow.settings.glossary,
            model: model,
            promptPresets: workflow.settings.promptPresets
        )
    }

    private func translateCurrentStoredCuesWithCloud(
        _ cues: [TranscriptCue],
        targetLanguage: String,
        metadata: AudioMetadata,
        provider: ActiveCloudTranslationProvider
    ) async throws -> [TranscriptCue] {
        guard !cues.isEmpty else { return [] }
        return try await reviewCloudEngine.translateCues(
            cues,
            targetLang: targetLanguage,
            metadata: metadata,
            glossary: workflow.settings.glossary,
            provider: provider,
            promptPresets: workflow.settings.promptPresets
        )
    }

    private func startPlayback() {
        guard let chunk = currentChunk else { return }
        guard !chunk.filePath.isEmpty else {
            statusMessage = "Audio for this segment is not available. Regenerate timings to create segment audio."
            return
        }
        let url = URL(fileURLWithPath: chunk.filePath)
        if !FileManager.default.fileExists(atPath: url.path) {
            if let session = session,
               let sourceFile = session.sourceFile,
               !sourceFile.isEmpty,
               FileManager.default.fileExists(atPath: sourceFile) {
                let sourceURL = URL(fileURLWithPath: sourceFile)
                statusMessage = "Restoring segment audio from source media..."
                Task {
                    do {
                        let chunkURLs = try await AudioChunkExporter.exportChunks(
                            sourceURL: sourceURL,
                            chunks: [chunk],
                            projectId: currentProjectID
                        )
                        if let restoredURL = chunkURLs[chunk.index] {
                            await MainActor.run {
                                updateCurrentChunk { $0.filePath = restoredURL.path }
                                self.startPlayback()
                            }
                        } else {
                            await MainActor.run {
                                statusMessage = "Failed to restore segment audio: chunk not sliced."
                            }
                        }
                    } catch {
                        await MainActor.run {
                            statusMessage = "Failed to restore segment audio: \(error.localizedDescription)"
                        }
                    }
                }
                return
            } else {
                statusMessage = "Audio for this segment is not available. Reprocess the segment to regenerate timed audio."
                return
            }
        }

        if audioPlayer == nil || (audioPlayer?.currentItem?.asset as? AVURLAsset)?.url != url {
            removePlaybackObserver()
            audioPlayer = AVPlayer(url: url)
            playbackTime = 0
        }

        addPlaybackObserverIfNeeded(duration: chunk.durationSec)
        audioPlayer?.play()
        isPlayingCurrentChunk = true
    }

    private func pausePlayback() {
        audioPlayer?.pause()
        isPlayingCurrentChunk = false
    }

    private func stopPlayback() {
        audioPlayer?.pause()
        removePlaybackObserver()
        audioPlayer = nil
        isPlayingCurrentChunk = false
        playbackTime = 0
    }

    private func addPlaybackObserverIfNeeded(duration: Double) {
        guard playbackObserver == nil else { return }
        playbackObserver = audioPlayer?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.10, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = min(max(0, time.seconds), duration)
                self.playbackTime = seconds
                if seconds >= duration - 0.05 {
                    self.pausePlayback()
                    self.audioPlayer?.seek(to: .zero)
                    self.playbackTime = 0
                }
            }
        }
    }

    private func removePlaybackObserver() {
        if let playbackObserver {
            audioPlayer?.removeTimeObserver(playbackObserver)
            self.playbackObserver = nil
        }
    }

    private enum ShortsPlanRoute: Sendable {
        case cloud(ActiveCloudTranslationProvider)
        case mlx(ActiveMLXModel)

        var label: String {
            switch self {
            case let .cloud(provider): provider.label
            case .mlx: "MLX"
            }
        }
    }

    func generateShortsPlan(
        count: Int = 5,
        minDurationSec: Int = 30,
        maxDurationSec: Int = 90,
        mode: ShortsPlanLanguageMode? = nil
    ) {
        guard !isPlanningShorts else { return }
        guard let session else { return }

        let planMode = mode ?? (session.selectedTranslationLanguage == nil ? .source : .target)
        let transcript = shortsPlanningTranscript(for: session, mode: planMode)
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "No \(planMode.rawValue) transcript text is available for Shorts/Reels planning."
            return
        }

        // Honor the "Planning model" selector: use the chosen cloud provider when it
        // has an API key, and only fall back to a local MLX model otherwise.
        let route: ShortsPlanRoute
        if let cloudProvider = activeCloudTranslationProvider(for: session) {
            route = .cloud(cloudProvider)
        } else if let model = activeTranslationModel(for: session) {
            route = .mlx(model)
        } else {
            statusMessage = "Select a cloud provider (e.g. Gemini Cloud) as the Planning model, or download an MLX model in Settings before planning Shorts/Reels."
            return
        }

        let outputLanguage = shortsOutputLanguage(for: session, mode: planMode)
        let speakerName = session.metadata.lecturer
        let existingShortsPlans = session.shortsPlans ?? []
        let rejectedShortsPlans = session.shortsRejectedPlans ?? []
        let shortsPlanningExclusions = existingShortsPlans + rejectedShortsPlans

        isPlanningShorts = true
        statusMessage = "Finding Shorts/Reels moments with \(route.label)..."
        Task {
            do {
                let plans: [ShortsClipPlan]
                switch route {
                case let .cloud(provider):
                    plans = try await shortsCloudEngine.planShorts(
                        transcript: transcript,
                        count: count,
                        minDurationSec: minDurationSec,
                        maxDurationSec: maxDurationSec,
                        outputLanguage: outputLanguage,
                        speakerName: speakerName,
                        mode: planMode,
                        existingClips: shortsPlanningExclusions,
                        provider: provider
                    )
                case let .mlx(model):
                    plans = try await shortsMLXEngine.planShorts(
                        transcript: transcript,
                        count: count,
                        minDurationSec: minDurationSec,
                        maxDurationSec: maxDurationSec,
                        outputLanguage: outputLanguage,
                        speakerName: speakerName,
                        mode: planMode,
                        existingClips: shortsPlanningExclusions,
                        model: model
                    )
                }
                await MainActor.run {
                    var updated = session
                    let incomingPlans = plans.map { plan in
                        var copy = plan
                        copy.languageMode = planMode
                        return copy
                    }
                    let appendResult = ShortsPlanner.appendNonOverlappingPlans(
                        existingPlans: updated.shortsPlans ?? [],
                        incomingPlans: incomingPlans,
                        excludedPlans: updated.shortsRejectedPlans ?? []
                    )
                    updated.shortsPlans = appendResult.plans
                    workflow.session = updated
                    isPlanningShorts = false
                    if plans.isEmpty {
                        statusMessage = "\(route.label) returned no usable Shorts/Reels moments."
                    } else if appendResult.addedIndexes.isEmpty {
                        statusMessage = "\(route.label) returned \(plans.count) Shorts/Reels moment\(plans.count == 1 ? "" : "s"), but all overlapped existing or deleted clips."
                    } else if appendResult.skippedOverlapping.isEmpty {
                        let added = appendResult.addedIndexes.count
                        statusMessage = "Added \(added) Shorts/Reels moment\(added == 1 ? "" : "s")."
                    } else {
                        let added = appendResult.addedIndexes.count
                        let skipped = appendResult.skippedOverlapping.count
                        statusMessage = "Added \(added) Shorts/Reels moment\(added == 1 ? "" : "s"); skipped \(skipped) candidate\(skipped == 1 ? "" : "s") overlapping existing or deleted clips."
                    }
                    saveCurrentProject()
                }
            } catch {
                await MainActor.run {
                    isPlanningShorts = false
                    statusMessage = "Shorts/Reels planning failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func updateShortsPlan(
        at index: Int,
        displayLanguage: ShortsIdeaDisplayLanguage,
        title: String,
        summary: String,
        hook: String,
        category: String,
        captionText: String
    ) {
        updateShortsPlan(at: index) { plan in
            switch displayLanguage {
            case .source:
                plan.sourceTitle = title
                plan.sourceSummary = summary
                plan.sourceHook = hook
                plan.sourceCategory = category
                plan.sourceCaptionText = captionText
                if plan.languageMode == .source {
                    plan.title = title
                    plan.summary = summary
                    plan.hook = hook
                    plan.category = category
                    plan.captionText = captionText
                }
            case .target:
                plan.targetTitle = title
                plan.targetSummary = summary
                plan.targetHook = hook
                plan.targetCategory = category
                plan.targetCaptionText = captionText
                plan.title = title
                plan.summary = summary
                plan.hook = hook
                plan.category = category
                plan.captionText = captionText
            }
        }
        statusMessage = "Shorts/Reels clip updated."
    }

    func updateShortsVisualEditorState(
        at index: Int,
        sourceAlignment: [AlignedSubtitleSegment],
        targetAlignment: [AlignedSubtitleSegment],
        sourceFrameKeyframes: [FrameKeyframe],
        targetFrameKeyframes: [FrameKeyframe],
        timelineCuts: [TimelineCut],
        timelineTrim: TimelineTrim,
        backgroundSettings: ShortsBackgroundSettings,
        subtitleStyle: ShortsSubtitleStyle,
        syncEnabled: Bool,
        sourceLogo: LogoOverlaySettings?,
        targetLogo: LogoOverlaySettings?,
        sourceTextTracks: [TextOverlayTrack],
        targetTextTracks: [TextOverlayTrack],
        sourceAudioTracks: [ExtraAudioTrack],
        targetAudioTracks: [ExtraAudioTrack],
        sourceIntro: IntroOutroOverlaySettings?,
        targetIntro: IntroOutroOverlaySettings?,
        sourceOutro: IntroOutroOverlaySettings?,
        targetOutro: IntroOutroOverlaySettings?
    ) {
        updateShortsPlan(at: index) { plan in
            plan.sourceAlignment = sourceAlignment
            plan.targetAlignment = targetAlignment
            plan.sourceFrameKeyframes = sourceFrameKeyframes
            plan.targetFrameKeyframes = targetFrameKeyframes
            plan.timelineCuts = timelineCuts
            plan.timelineTrim = timelineTrim
            plan.backgroundSettings = backgroundSettings
            plan.subtitleStyle = subtitleStyle
            plan.syncEnabled = syncEnabled
            plan.sourceLogo = sourceLogo
            plan.targetLogo = targetLogo
            plan.sourceTextTracks = sourceTextTracks
            plan.targetTextTracks = targetTextTracks
            plan.sourceAudioTracks = sourceAudioTracks
            plan.targetAudioTracks = targetAudioTracks
            plan.sourceIntro = sourceIntro
            plan.targetIntro = targetIntro
            plan.sourceOutro = sourceOutro
            plan.targetOutro = targetOutro
        }
        statusMessage = "Visual clip editor state saved."
    }

    func replaceShortsPlanTiming(at index: Int, start: String, end: String) {
        let startSec = ShortsPlanner.parseTimestampToSeconds(start)
        let endSec = ShortsPlanner.parseTimestampToSeconds(end)
        let validation = ShortsPlanner.validateClip(startSec: startSec, endSec: endSec, minDurationSec: 10, maxDurationSec: 300)
        guard validation.ok else {
            statusMessage = validation.reason ?? "Invalid clip timing."
            return
        }

        updateShortsPlan(at: index) { plan in
            plan = ShortsPlanner.replacingClipRange(
                plan,
                start: ShortsPlanner.secondsToShortsTimestamp(startSec),
                end: ShortsPlanner.secondsToShortsTimestamp(endSec)
            )
        }
        statusMessage = "Clip timing replaced."
    }

    func removeShortsPlan(at index: Int) {
        guard var session = workflow.session, var plans = session.shortsPlans, plans.indices.contains(index) else { return }
        let removed = plans.remove(at: index)
        session.shortsPlans = plans
        var rejectedPlans = session.shortsRejectedPlans ?? []
        rejectedPlans.removeAll { $0.start == removed.start && $0.end == removed.end }
        rejectedPlans.append(removed)
        if rejectedPlans.count > 50 {
            rejectedPlans = Array(rejectedPlans.suffix(50))
        }
        session.shortsRejectedPlans = rejectedPlans
        workflow.session = session
        saveCurrentProject()
        statusMessage = "Clip removed and excluded from future Shorts/Reels planning."
    }

    func exportShortsIdeas(indices: Set<Int>, displayLanguage: ShortsIdeaDisplayLanguage) {
        guard let plans = selectedShortsPlans(indices: indices), !plans.isEmpty else {
            statusMessage = "No Shorts/Reels ideas to export."
            return
        }

        do {
            let json = try ShortsIdeasExporter.renderJSON(plans: plans, displayLanguage: displayLanguage)
            let text = ShortsIdeasExporter.renderText(plans: plans, displayLanguage: displayLanguage)
            let baseName = ((session?.sourceFileName as NSString?)?.deletingPathExtension ?? "VaniScript")
                .replacingOccurrences(of: "/", with: "-")

            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(baseName)-shorts-ideas.json"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else {
                statusMessage = "Shorts/Reels ideas export cancelled."
                return
            }

            try json.write(to: url, atomically: true, encoding: .utf8)
            let textURL = url.deletingPathExtension().appendingPathExtension("txt")
            try text.write(to: textURL, atomically: true, encoding: .utf8)
            statusMessage = "Shorts/Reels ideas exported: \(url.lastPathComponent), \(textURL.lastPathComponent)"
        } catch {
            statusMessage = "Shorts/Reels ideas export failed: \(error.localizedDescription)"
        }
    }

    func exportSelectedShortsVideos(
        jobs: [ShortsExportJob],
        format: String,
        resolution: String,
        frameRate: String
    ) {
        guard let session, let allPlans = session.shortsPlans else {
            statusMessage = "Select at least one clip before exporting videos."
            return
        }
        let renderJobs = jobs.compactMap { job -> NativeShortsVideoRenderJob? in
            guard allPlans.indices.contains(job.index) else { return nil }
            return NativeShortsVideoRenderJob(planIndex: job.index, plan: allPlans[job.index], language: job.language)
        }
        guard !renderJobs.isEmpty else {
            statusMessage = "Select at least one clip before exporting videos."
            return
        }
        guard let sourceFile = session.sourceFile, FileManager.default.fileExists(atPath: sourceFile) else {
            statusMessage = "Video export requires the original local media file."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Videos"
        guard panel.runModal() == .OK, let directory = panel.url else {
            statusMessage = "Video export cancelled."
            return
        }

        statusMessage = "Exporting \(renderJobs.count) Shorts/Reels video\(renderJobs.count == 1 ? "" : "s")..."

        isExportingShorts = true
        exportProgress = 0.0
        exportStage = "Preparing render job"
        exportClipProgressText = "Clip 1 / \(renderJobs.count)"
        exportPhaseTag = "prepare"

        exportTotalClips = renderJobs.count
        exportActiveClipIndex = 1
        exportDurations = [:]
        currentClipElapsedTime = 0.0
        currentClipRemainingTime = nil
        overallElapsedTime = 0.0
        overallRemainingTime = nil
        exportCompletionState = nil

        let startTime = Date()
        self.exportStartTime = startTime
        self.currentClipStartTime = startTime
        self.clipStartTimes = [0: startTime]

        // Start a Timer ticking every 1 second
        self.exportTimer?.invalidate()
        self.exportTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let now = Date()
                let overallElapsed = now.timeIntervalSince(self.exportStartTime ?? now)
                self.overallElapsedTime = overallElapsed

                let clipElapsed = now.timeIntervalSince(self.currentClipStartTime ?? now)
                self.currentClipElapsedTime = clipElapsed

                // Estimate remaining times if progress is available
                if self.exportProgress > 0.005 {
                    self.overallRemainingTime = overallElapsed * (1.0 - self.exportProgress) / self.exportProgress
                } else {
                    self.overallRemainingTime = nil
                }

                let totalPlans = Double(self.exportTotalClips)
                let currentIdx = Double(self.exportActiveClipIndex)
                let clipProgress = (self.exportProgress * totalPlans) - (currentIdx - 1.0)
                if clipProgress > 0.01 && clipProgress < 0.99 {
                    self.currentClipRemainingTime = clipElapsed * (1.0 - clipProgress) / clipProgress
                } else {
                    self.currentClipRemainingTime = nil
                }
            }
        }

        exportTask = Task {
            do {
                let totalPlans = renderJobs.count
                let exported = try await NativeShortsVideoRenderer.export(
                    sourceURL: URL(fileURLWithPath: sourceFile),
                    jobs: renderJobs,
                    directory: directory,
                    options: NativeShortsExportOptions(
                        format: format,
                        resolutionPreset: resolution,
                        frameRatePreset: frameRate,
                        language: .source
                    ),
                    progressCallback: { @Sendable progress, stage, phaseTag in
                        Task { @MainActor in
                            let currentIdx = min(totalPlans, Int(progress * Double(totalPlans)) + 1)
                            self.exportProgress = progress
                            self.exportStage = stage
                            self.exportClipProgressText = "Clip \(currentIdx) / \(totalPlans)"
                            self.exportPhaseTag = phaseTag

                            // Check if the clip index changed (i.e. we transitioned to a new clip)
                            if currentIdx > self.exportActiveClipIndex {
                                let now = Date()
                                // Record the duration of all completed clips up to currentIdx - 1
                                for idx in self.exportActiveClipIndex..<currentIdx {
                                    let cStart = self.clipStartTimes[idx - 1] ?? self.exportStartTime ?? now
                                    self.exportDurations[idx - 1] = now.timeIntervalSince(cStart)
                                }
                                self.clipStartTimes[currentIdx - 1] = now
                                self.currentClipStartTime = now
                                self.exportActiveClipIndex = currentIdx
                            }
                        }
                    }
                )
                await MainActor.run {
                    self.exportTimer?.invalidate()
                    self.exportTimer = nil
                    let now = Date()
                    // Record final clip duration
                    let lastIdx = totalPlans
                    let cStart = self.clipStartTimes[lastIdx - 1] ?? self.currentClipStartTime ?? now
                    self.exportDurations[lastIdx - 1] = now.timeIntervalSince(cStart)

                    self.exportProgress = 1.0
                    self.exportStage = "Render completed successfully!"
                    self.exportPhaseTag = "completed"
                    self.exportCompletionState = .success
                    self.isExportingShorts = true
                    self.statusMessage = "Exported \(exported.count) Shorts/Reels video\(exported.count == 1 ? "" : "s")."
                    self.exportTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.exportTimer?.invalidate()
                    self.exportTimer = nil
                    self.isExportingShorts = false
                    self.exportCompletionState = nil
                    self.statusMessage = "Shorts/Reels video export cancelled."
                    self.exportTask = nil
                }
            } catch {
                await MainActor.run {
                    self.exportTimer?.invalidate()
                    self.exportTimer = nil
                    self.exportStage = "Render failed"
                    self.exportPhaseTag = "failed"
                    self.exportCompletionState = .failure(error.localizedDescription)
                    self.isExportingShorts = true
                    self.statusMessage = "Shorts/Reels video export failed: \(error.localizedDescription)"
                    self.exportTask = nil
                }
            }
        }
    }

    func cancelExportShorts() {
        exportTimer?.invalidate()
        exportTimer = nil
        exportTask?.cancel()
        exportTask = nil
        isExportingShorts = false
        exportCompletionState = nil
        statusMessage = "Video export cancelled by user."
    }

    func closeExportShortsModal() {
        isExportingShorts = false
        exportCompletionState = nil
    }

    func formatTimeInterval(_ interval: Double) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    private func selectedShortsPlans(indices: Set<Int>) -> [ShortsClipPlan]? {
        guard let plans = session?.shortsPlans else { return nil }
        if indices.isEmpty {
            return plans
        }
        return indices.sorted().compactMap { plans.indices.contains($0) ? plans[$0] : nil }
    }

    private func updateShortsPlan(at index: Int, mutate: (inout ShortsClipPlan) -> Void) {
        guard var session = workflow.session, var plans = session.shortsPlans, plans.indices.contains(index) else { return }
        mutate(&plans[index])
        session.shortsPlans = plans
        workflow.session = session
        saveCurrentProject()
    }

    private func shortsPlanningTranscript(for session: SessionState, mode: ShortsPlanLanguageMode) -> String {
        ShortsTranscriptExtractor.planningTranscript(session: session, mode: mode)
    }

    private func shortsOutputLanguage(for session: SessionState, mode: ShortsPlanLanguageMode) -> String {
        switch mode {
        case .source:
            return "source language"
        case .target, .bilingual:
            return session.selectedTranslationLanguage ?? session.targetLang
        }
    }

    func openProject(id: String, chunkIndex: Int? = nil, openExport: Bool = false) {
        if id == currentProjectID, let chunkIndex, var session = workflow.session {
            let maxIndex = max(0, session.chunks.count - 1)
            let newIndex = min(max(0, chunkIndex), maxIndex)
            stopPlayback()
            session.currentChunkIndex = newIndex
            synchronizedReviewCueID = nil
            workflow.session = session
            if openExport {
                workflow.screen = .export
            } else {
                workflow.screen = .review
            }
            dismissProjectSidebar()
            if !openExport {
                processCurrentChunkIfNeeded()
            }
            return
        }

        guard let record = projects.first(where: { $0.id == id }) else { return }
        AppLogger.shared.info("Opening project: \(record.session.sourceFileName) (ID: \(id))", settings: workflow.settings)
        visualEditorDraft = nil
        var openedSession = record.session
        openedSession.normalizeTranslationArchive()
        if let index = projects.firstIndex(where: { $0.id == record.id }) {
            projects[index].session = openedSession
            persistProjects()
        }
        if let chunkIndex {
            let maxIndex = max(0, openedSession.chunks.count - 1)
            openedSession.currentChunkIndex = min(max(0, chunkIndex), maxIndex)
        }
        currentProjectID = record.id
        workflow.session = openedSession
        if openExport {
            workflow.screen = .export
        } else {
            workflow.screen = .review
        }
        workflow.sourceFile = openedSession.sourceFile ?? ""
        workflow.sourceFileName = openedSession.sourceFileName
        workflow.sourceMediaInfo = openedSession.sourceMediaInfo
        workflow.durationSec = openedSession.durationSec
        workflow.metadata = openedSession.metadata
        workflow.sourceLang = openedSession.sourceLang
        workflow.targetLang = openedSession.targetLang
        workflow.transcriptionProvider = openedSession.transcriptionProvider
        workflow.translationProvider = openedSession.translationProvider
        workflow.outputFormats = openedSession.outputFormats
        archiveTargetLanguage = openedSession.selectedTranslationLanguage ?? workflow.settings.defaultTargetLang
        updateSettings { settings in
            settings.adaptGlossaryToTargetLanguage(targetLang: openedSession.targetLang)
        }
        statusMessage = "Project opened: \(openedSession.sourceFileName)"
        // Glossary application removed from navigation path to optimize performance
        dismissProjectSidebar()
        if !openExport {
            processCurrentChunkIfNeeded()
        }
    }

    func deleteProject(id: String) {
        AppLogger.shared.info("Deleting project ID: \(id)", settings: workflow.settings)
        projects.removeAll { $0.id == id }
        if currentProjectID == id {
            newSession()
        }
        persistProjects()
    }

    func exportAllProjects() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "VaniScript Library.vaniscript-library"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProjectBundleExporter.exportLibrary(records: projects, to: url)
            statusMessage = "Library exported: \(url.lastPathComponent)"
        } catch {
            statusMessage = "Library export failed: \(error.localizedDescription)"
        }
    }

    func exportProject(id: String) {
        guard let record = projects.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        let baseName = URL(fileURLWithPath: record.session.sourceFileName)
            .deletingPathExtension()
            .lastPathComponent
        panel.nameFieldStringValue = "\(baseName.isEmpty ? "VaniScript_Project" : baseName).vaniscript"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProjectBundleExporter.exportBundle(record: record, to: url)
            statusMessage = "Project exported: \(url.lastPathComponent)"
        } catch {
            statusMessage = "Project export failed: \(error.localizedDescription)"
        }
    }

    func openProjectSourceFile(id: String) {
        guard let mediaInfo = sourceMediaInfo(for: id) else {
            statusMessage = "No source media file is attached to this session."
            return
        }
        let url = URL(fileURLWithPath: mediaInfo.filePath)
        guard FileManager.default.fileExists(atPath: mediaInfo.filePath) else {
            statusMessage = "Source media file is missing: \(mediaInfo.filePath)"
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealProjectSourceFile(id: String) {
        guard let mediaInfo = sourceMediaInfo(for: id) else {
            statusMessage = "No source media file is attached to this session."
            return
        }
        let url = URL(fileURLWithPath: mediaInfo.filePath)
        guard FileManager.default.fileExists(atPath: mediaInfo.filePath) else {
            statusMessage = "Source media file is missing: \(mediaInfo.filePath)"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func showProjectSourceInfo(id: String) {
        guard let mediaInfo = sourceMediaInfo(for: id) else {
            statusMessage = "No source media information is attached to this session."
            return
        }
        let fileURL = URL(fileURLWithPath: mediaInfo.filePath)
        guard FileManager.default.fileExists(atPath: mediaInfo.filePath) else {
            statusMessage = "Source media file is missing: \(mediaInfo.filePath)"
            return
        }
        statusMessage = "Reading source media details..."
        Task { [weak self] in
            let refreshedInfo = await SourceMediaInspector.inspect(
                fileURL: fileURL,
                originalURL: mediaInfo.originalURL,
                title: mediaInfo.title,
                durationSec: mediaInfo.durationSec
            )
            await MainActor.run {
                guard let self else { return }
                self.updateProjectSourceMediaInfo(refreshedInfo, for: id)
                self.statusMessage = "Source media details refreshed."
                self.presentSourceMediaInfo(refreshedInfo, id: id)
            }
        }
    }

    private func presentSourceMediaInfo(_ mediaInfo: SourceMediaInfo, id: String) {
        let alert = NSAlert()
        alert.messageText = "Source Media"
        alert.informativeText = sourceInfoDetails(mediaInfo)
        alert.addButton(withTitle: "Open File")
        alert.addButton(withTitle: "Reveal in Finder")
        alert.addButton(withTitle: "OK")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openProjectSourceFile(id: id)
        } else if response == .alertSecondButtonReturn {
            revealProjectSourceFile(id: id)
        }
    }

    func exportSystemLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "VaniScript_Logs.log"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let logContents = AppLogger.shared.getLogContents()
            try logContents.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Logs exported: \(url.lastPathComponent)"
        } catch {
            statusMessage = "Logs export failed: \(error.localizedDescription)"
        }
    }

    func importProjects() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        let vaniscriptType = UTType(filenameExtension: "vaniscript", conformingTo: .data) ?? .data
        let vaniscriptLibraryType = UTType(filenameExtension: "vaniscript-library", conformingTo: .data) ?? .data
        panel.allowedContentTypes = [.json, vaniscriptType, vaniscriptLibraryType]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let destDir = AppStoragePaths.applicationSupportDirectory().appendingPathComponent("Projects", isDirectory: true)
            let imported = try ProjectBundleImporter.importBundle(fileURL: url, destinationDirectoryURL: destDir)
            mergeProjects(imported)
            statusMessage = "Imported \(imported.count) project\(imported.count == 1 ? "" : "s")."
        } catch let error as DecodingError {
            switch error {
            case .keyNotFound(let key, let context):
                statusMessage = "Project import failed: key '\(key.stringValue)' not found at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .valueNotFound(let type, let context):
                statusMessage = "Project import failed: value of type '\(type)' not found at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .typeMismatch(let type, let context):
                statusMessage = "Project import failed: type mismatch for '\(type)' at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .dataCorrupted(let context):
                statusMessage = "Project import failed: data corrupted at path: \(context.codingPath.map(\.stringValue).joined(separator: ".")) (\(context.debugDescription))"
            @unknown default:
                statusMessage = "Project import failed: \(error.localizedDescription)"
            }
        } catch {
            statusMessage = "Project import failed: \(error.localizedDescription)"
        }
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        let previousSettings = workflow.settings
        mutate(&workflow.settings)
        workflow.settings.synchronizeLocalModelsWithDisk()
        let transcriptionProviderChanged = workflow.settings.transcriptionProvider != previousSettings.transcriptionProvider
        let translationProviderChanged = workflow.settings.translationProvider != previousSettings.translationProvider
        workflow.synchronizeProviderSelections(
            previousSettings: previousSettings,
            forceTranscriptionProvider: transcriptionProviderChanged,
            forceTranslationProvider: translationProviderChanged
        )
        persistSettings()
        refreshProviderSelections()
        if workflow.session != nil, transcriptionProviderChanged || translationProviderChanged {
            workflow.synchronizeActiveSessionProviders(
                forceTranscriptionProvider: transcriptionProviderChanged,
                forceTranslationProvider: translationProviderChanged
            )
            saveCurrentProject()
        }
    }

    func reconcileLocalModelStates() {
        let currentSettings = self.workflow.settings
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            var settingsCopy = currentSettings
            settingsCopy.synchronizeLocalModelsWithDisk()
            let synchronizedSettings = settingsCopy
            
            Task { @MainActor in
                self.workflow.settings = synchronizedSettings
                self.persistSettings()
                self.refreshProviderSelections()
            }
        }
    }

    func locateLocalASRModel(id: String) {
        locateLocalModel(runtime: .whisperkit) { path in
            updateSettings { settings in
                guard var model = settings.localAsrModels[id] else { return }
                model.status = .downloaded
                model.path = path
                model.progress = 1
                model.error = nil
                settings.localAsrModels[id] = model
            }
        }
    }

    func locateLocalTranslationModel(id: String) {
        locateLocalModel(runtime: .mlx) { path in
            updateSettings { settings in
                guard var model = settings.localTranslationModels[id] else { return }
                model.status = .downloaded
                model.path = path
                model.progress = 1
                model.error = nil
                settings.localTranslationModels[id] = model
            }
        }
    }

    func removeLocalASRModel(id: String) {
        updateSettings { settings in
            guard var model = settings.localAsrModels[id] else { return }
            model.status = .notDownloaded
            model.path = nil
            model.progress = nil
            settings.localAsrModels[id] = model
        }
    }

    func removeLocalTranslationModel(id: String) {
        updateSettings { settings in
            guard var model = settings.localTranslationModels[id] else { return }
            model.status = .notDownloaded
            model.path = nil
            model.progress = nil
            settings.localTranslationModels[id] = model
        }
    }

    func downloadLocalModel(id: String, isTranslation: Bool) {
        updateSettings { settings in
            if isTranslation {
                guard var model = settings.localTranslationModels[id] else { return }
                model.status = .downloading
                model.progress = 0.0
                model.progressLabel = "Initializing..."
                settings.localTranslationModels[id] = model
            } else {
                guard var model = settings.localAsrModels[id] else { return }
                model.status = .downloading
                model.progress = 0.0
                model.progressLabel = "Initializing..."
                settings.localAsrModels[id] = model
            }
        }

        ModelDownloadManager.shared.downloadModel(id: id) { [weak self] progress, label in
            Task { @MainActor in
                self?.updateSettings { settings in
                    if isTranslation {
                        guard var model = settings.localTranslationModels[id] else { return }
                        model.progress = progress
                        model.progressLabel = label
                        settings.localTranslationModels[id] = model
                    } else {
                        guard var model = settings.localAsrModels[id] else { return }
                        model.progress = progress
                        model.progressLabel = label
                        settings.localAsrModels[id] = model
                    }
                }
            }
        } onComplete: { [weak self] path in
            Task { @MainActor in
                self?.updateSettings { settings in
                    if isTranslation {
                        guard var model = settings.localTranslationModels[id] else { return }
                        model.status = .downloaded
                        model.path = path
                        model.progress = 1.0
                        model.progressLabel = "Done"
                        settings.localTranslationModels[id] = model
                    } else {
                        guard var model = settings.localAsrModels[id] else { return }
                        model.status = .downloaded
                        model.path = path
                        model.progress = 1.0
                        model.progressLabel = "Done"
                        settings.localAsrModels[id] = model
                    }
                }
            }
        } onFailure: { [weak self] error in
            Task { @MainActor in
                self?.updateSettings { settings in
                    if isTranslation {
                        guard var model = settings.localTranslationModels[id] else { return }
                        model.status = .failed
                        model.error = error.localizedDescription
                        settings.localTranslationModels[id] = model
                    } else {
                        guard var model = settings.localAsrModels[id] else { return }
                        model.status = .failed
                        model.error = error.localizedDescription
                        settings.localAsrModels[id] = model
                    }
                }
            }
        }
    }

    private func beginRecordingTimer() {
        stopRecordingTimer()
        recordingStartedAt = Date()
        recordingElapsedSec = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startedAt = self.recordingStartedAt else { return }
                self.recordingElapsedSec = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartedAt = nil
    }

    private func recordingLevelHandler() -> @Sendable ([Double]) -> Void {
        { [weak self] levels in
            Task { @MainActor [weak self] in
                self?.updateRecordingAudioLevels(levels)
            }
        }
    }

    private func updateRecordingAudioLevels(_ levels: [Double]) {
        guard !levels.isEmpty else { return }
        var next = Array(levels.prefix(AudioSpectrumAnalyzer.defaultBandCount))
        if next.count < AudioSpectrumAnalyzer.defaultBandCount {
            next.append(contentsOf: Array(repeating: AudioSpectrumAnalyzer.visualFloor, count: AudioSpectrumAnalyzer.defaultBandCount - next.count))
        }
        next = next.map { max(AudioSpectrumAnalyzer.visualFloor, min(1, $0)) }

        guard recordingAudioLevels.count == next.count else {
            recordingAudioLevels = next
            return
        }

        recordingAudioLevels = zip(recordingAudioLevels, next).map { current, incoming in
            let attack = incoming > current ? 0.58 : 0.24
            return current + ((incoming - current) * attack)
        }
    }

    private func resetRecordingAudioLevels() {
        recordingAudioLevels = AudioSpectrumAnalyzer.silenceLevels
    }

    private func prepareRecordingPlayer(url: URL) {
        stopRecordingPreviewPlayback()
        recordingPlayer = AVPlayer(url: url)
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        recordingPlaybackObserver = recordingPlayer?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = time.seconds.isFinite ? time.seconds : 0
                self.recordingPreviewTime = max(0, seconds)
                if self.recordingPreviewDurationSec > 0,
                   seconds >= self.recordingPreviewDurationSec - 0.1 {
                    self.isRecordingPreviewPlaying = false
                }
            }
        }
    }

    private func stopRecordingPreviewPlayback() {
        recordingPlayer?.pause()
        if let recordingPlaybackObserver {
            recordingPlayer?.removeTimeObserver(recordingPlaybackObserver)
            self.recordingPlaybackObserver = nil
        }
        recordingPlayer = nil
        isRecordingPreviewPlaying = false
    }

    private func discardRecordingPreview(removeFile: Bool, updateStatus: Bool) {
        let previewURL = recordingPreviewURL
        stopRecordingPreviewPlayback()
        recordingPreviewURL = nil
        recordingPreviewDurationSec = 0
        recordingPreviewTime = 0
        resetRecordingAudioLevels()
        if removeFile, let previewURL {
            try? FileManager.default.removeItem(at: previewURL)
        }
        if updateStatus {
            recordingMessage = ""
            recordingErrorMessage = ""
            statusMessage = "Recording discarded."
        }
    }

    private static func availableRecordingDevices() -> [RecordingInputDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.map { device in
            RecordingInputDevice(id: device.uniqueID, name: device.localizedName)
        }
    }

    static func formatRecordingTime(_ seconds: Double) -> String {
        let safe = max(0, Int(seconds.rounded(.down)))
        let minutes = safe / 60
        let remainingSeconds = safe % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func updateCurrentChunk(_ mutate: (inout ChunkData) -> Void) {
        guard var session = workflow.session else { return }
        guard session.chunks.indices.contains(session.currentChunkIndex) else { return }
        mutate(&session.chunks[session.currentChunkIndex])
        session.normalizeTranslationArchive()
        workflow.session = session
        saveCurrentProject()
    }

    private func selectSource(url: URL, duration: Double, sourceMediaInfo: SourceMediaInfo? = nil) {
        workflow.selectSource(path: url.path(percentEncoded: false), durationSec: duration, sourceMediaInfo: sourceMediaInfo)
        statusMessage = duration > 0 ? "Media loaded." : "Media loaded. Duration will be resolved during processing."
    }

    private func sourceMediaInfo(for id: String) -> SourceMediaInfo? {
        if id == currentProjectID, let info = workflow.session?.sourceMediaInfo ?? workflow.sourceMediaInfo {
            return info
        }
        return projects.first(where: { $0.id == id })?.summary.sourceMediaInfo
    }

    private func sourceInfoDetails(_ info: SourceMediaInfo) -> String {
        info.mediaInfoLines().joined(separator: "\n")
    }

    private func updateProjectSourceMediaInfo(_ mediaInfo: SourceMediaInfo, for id: String) {
        if id == currentProjectID {
            workflow.sourceMediaInfo = mediaInfo
            if workflow.session != nil {
                workflow.session?.sourceMediaInfo = mediaInfo
            }
        }
        if let index = projects.firstIndex(where: { $0.id == id }) {
            projects[index].session.sourceMediaInfo = mediaInfo
        }
        persistProjects()
    }

    private func createProjectIfNeeded() {
        guard currentProjectID == nil, let session else { return }
        let now = isoString(clock())
        let record = ProjectRecord(id: UUID().uuidString, createdAt: now, updatedAt: now, session: session)
        currentProjectID = record.id
        projects.insert(record, at: 0)
        persistProjects()
    }

    private func saveCurrentProject() {
        guard let currentProjectID, let session else { return }
        var normalizedSession = session
        normalizedSession.normalizeTranslationArchive()
        workflow.session = normalizedSession
        let now = isoString(clock())
        if let index = projects.firstIndex(where: { $0.id == currentProjectID }) {
            projects[index].updatedAt = now
            projects[index].session = normalizedSession
        } else {
            projects.append(ProjectRecord(id: currentProjectID, createdAt: now, updatedAt: now, session: normalizedSession))
        }
        projects = ProjectArchive.sortedRecent(projects)
        persistProjects()
    }

    private func mergeProjects(_ imported: [ProjectRecord]) {
        var updatedProjects = imported
        let glossary = workflow.settings.glossary
        if !glossary.isEmpty {
            for i in updatedProjects.indices {
                for chunkIndex in updatedProjects[i].session.chunks.indices {
                    let status = updatedProjects[i].session.chunks[chunkIndex].status
                    guard status == .done || !updatedProjects[i].session.chunks[chunkIndex].original.isEmpty else { continue }
                    for entry in glossary {
                        _ = applyGlossaryEntry(&updatedProjects[i].session.chunks[chunkIndex], entry: entry)
                    }
                }
            }
        }
        for record in updatedProjects {
            if let index = projects.firstIndex(where: { $0.id == record.id }) {
                projects[index] = record
            } else {
                projects.append(record)
            }
        }
        projects = ProjectArchive.sortedRecent(projects)
        persistProjects()
    }

    private func persistProjects() {
        let projectsToSave = projects
        Task.detached(priority: .background) { [weak self] in
            do {
                try ProjectDiskStore.save(projectsToSave)
            } catch {
                await MainActor.run {
                    self?.statusMessage = "Project save failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func persistSettings() {
        let settingsToSave = workflow.settings
        Task.detached(priority: .background) { [weak self] in
            do {
                try SettingsDiskStore.save(settingsToSave)
            } catch {
                await MainActor.run {
                    self?.statusMessage = "Settings save failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func refreshProviderSelections() {
        let transcriptionIDs = ProviderRegistry.availableTranscriptionProviders(settings: workflow.settings).map(\.id)
        if !transcriptionIDs.contains(workflow.transcriptionProvider), let first = transcriptionIDs.first {
            workflow.transcriptionProvider = first
        }

        let availability = ProviderRegistry.availableTranslationProviders(settings: workflow.settings, targetLang: workflow.targetLang)
        if !availability.enabled {
            workflow.translationProvider = ""
        } else {
            let translationIDs = availability.providers.map(\.id)
            if !translationIDs.contains(workflow.translationProvider), let first = translationIDs.first {
                workflow.translationProvider = first
            }
        }
    }

    private func locateLocalModel(runtime: SharedModelRuntime, _ apply: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canCreateDirectories = true
        panel.directoryURL = try? LocalModelPickerDefaults.directory(for: runtime)
        panel.message = "Choose a local model file or folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        apply(url.path(percentEncoded: false))
    }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    @discardableResult
    private func applyGlossaryEntryToWorkflow(_ entry: GlossaryEntry, currentChunkOnly: Bool) -> Int {
        applyGlossaryEntriesToWorkflow([entry], currentChunkOnly: currentChunkOnly)
    }

    @discardableResult
    private func applyGlossaryEntriesToWorkflow(_ entries: [GlossaryEntry], currentChunkOnly: Bool) -> Int {
        guard var session = workflow.session else { return 0 }
        var total = 0

        for index in session.chunks.indices {
            let shouldApply = currentChunkOnly
                ? index == session.currentChunkIndex
                : session.chunks[index].status == .done || index == session.currentChunkIndex
            guard shouldApply else { continue }
            for entry in entries {
                total += applyGlossaryEntry(&session.chunks[index], entry: entry)
            }
        }

        guard total > 0 else { return 0 }
        workflow.session = session
        saveCurrentProject()
        return total
    }

    @discardableResult
    private func applyGlossaryEntry(_ chunk: inout ChunkData, entry: GlossaryEntry) -> Int {
        var total = 0
        let entries = [entry]

        let originalResult = GlossaryTextRewriter.apply(to: chunk.original, entries: entries, target: .source)
        if originalResult.count > 0 {
            chunk.original = originalResult.text
            total += originalResult.count
        }

        if let cues = chunk.originalCues {
            let rewritten = GlossaryTextRewriter.apply(to: cues, entries: entries, target: .source)
            if rewritten.1 > 0 {
                chunk.originalCues = rewritten.0
                chunk.original = rewritten.0.map(\.text).joined(separator: " ")
                total += rewritten.1
            }
        }

        if let formats = chunk.originalFormats {
            chunk.originalFormats = applyGlossaryToFormats(formats, entries: entries, target: .source, total: &total)
        }

        let translatedResult = GlossaryTextRewriter.apply(to: chunk.translated, entries: entries, target: .translation)
        if translatedResult.count > 0 {
            chunk.translated = translatedResult.text
            total += translatedResult.count
        }

        if let formats = chunk.translatedFormats {
            chunk.translatedFormats = applyGlossaryToFormats(formats, entries: entries, target: .translation, total: &total)
        }

        if var archive = chunk.translationsByLanguage {
            for key in archive.keys {
                guard var variant = archive[key] else { continue }

                let textResult = GlossaryTextRewriter.apply(to: variant.text, entries: entries, target: .translation)
                if textResult.count > 0 {
                    variant.text = textResult.text
                    total += textResult.count
                }

                if let cues = variant.cues {
                    let cueResult = GlossaryTextRewriter.apply(to: cues, entries: entries, target: .translation)
                    if cueResult.1 > 0 {
                        variant.cues = cueResult.0
                        variant.text = cueResult.0.map(\.text).joined(separator: "\n")
                        total += cueResult.1
                    }
                }

                if let formats = variant.formats {
                    variant.formats = applyGlossaryToFormats(formats, entries: entries, target: .translation, total: &total)
                }

                variant.updatedAt = isoString(clock())
                archive[key] = variant
            }
            chunk.translationsByLanguage = archive

            if let language = workflow.session?.selectedTranslationLanguage,
               let activeVariant = archive[TranslationArchive.languageKey(language)] {
                chunk.translated = activeVariant.text
                chunk.translatedFormats = activeVariant.formats
            }
        }

        if total > 0 {
            chunk.status = .done
        }
        return total
    }

    private func applyGlossaryToFormats(
        _ formats: LanguageResult,
        entries: [GlossaryEntry],
        target: GlossaryTextRewriter.Target,
        total: inout Int
    ) -> LanguageResult {
        var copy = formats
        if let value = copy.txt {
            let result = GlossaryTextRewriter.apply(to: value, entries: entries, target: target)
            copy.txt = result.text
            total += result.count
        }
        if let value = copy.srt {
            let result = GlossaryTextRewriter.apply(to: value, entries: entries, target: target)
            copy.srt = result.text
            total += result.count
        }
        if let value = copy.vtt {
            let result = GlossaryTextRewriter.apply(to: value, entries: entries, target: target)
            copy.vtt = result.text
            total += result.count
        }
        if let value = copy.markdown {
            let result = GlossaryTextRewriter.apply(to: value, entries: entries, target: target)
            copy.markdown = result.text
            total += result.count
        }
        return copy
    }

    private static func parseGlossaryVariants(_ variantsText: String, fallback: String) -> [String] {
        let raw = variantsText
            .split { character in
                character == "," || character == "\n" || character == ";"
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let fallbackValue = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = raw.isEmpty && !fallbackValue.isEmpty ? [fallbackValue] : raw
        var seen = Set<String>()
        return values.compactMap { value in
            let key = value.lowercased()
            guard !value.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return value
        }
    }

    private func processCurrentChunkIfNeeded(force: Bool = false) {
        guard !isProcessingSegment else { return }
        reconcileLocalModelStates()
        guard let session = workflow.session else { return }
        guard let chunk = currentChunk else { return }

        if !force, chunk.status == .done {
            workflow.screen = .review
            return
        }

        workflow.screen = .processing
        workflow.processingMessage = "Preparing segment \(session.currentChunkIndex + 1) / \(session.chunks.count)..."
        workflow.processingProgress = 0
        isProcessingSegment = true
        beginNativeProcessingActivity()

        Task {
            await processCurrentSession()
            await MainActor.run {
                self.isProcessingSegment = false
                self.endNativeProcessingActivity()
            }
        }
    }

    private func processCurrentSession() async {
        guard let session = workflow.session else { return }
        let requestedIndex = session.currentChunkIndex
        let processed = await processingPipeline.processCurrentChunk(
            session: session,
            settings: workflow.settings,
            projectId: currentProjectID
        ) { [weak self] message, progress in
            await MainActor.run {
                self?.workflow.processingMessage = message
                self?.workflow.processingProgress = progress
            }
        }

        workflow.session = processed
        saveCurrentProject()

        let failedChunk = processed.chunks.indices.contains(requestedIndex) && processed.chunks[requestedIndex].status == .error
            ? processed.chunks[requestedIndex]
            : nil

        if let failedChunk {
            let failureMessage = failedChunk.translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? failedChunk.original
                : failedChunk.translated
            workflow.screen = .config
            errorMessage = failureMessage
            isErrorAlertPresented = true
            statusMessage = "Segment processing failed: \(failureMessage)"
        } else {
            workflow.screen = .review
            statusMessage = "Segment \(processed.currentChunkIndex + 1) ready for review."
        }
    }

    private func beginNativeProcessingActivity() {
        endNativeProcessingActivity()
        processingActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .suddenTerminationDisabled, .automaticTerminationDisabled],
            reason: "VaniScript native segment processing"
        )
    }

    private func endNativeProcessingActivity() {
        if let processingActivity {
            ProcessInfo.processInfo.endActivity(processingActivity)
            self.processingActivity = nil
        }
    }

    func scanForLocalModels() {
        scanForLocalModels(presentResult: true)
    }

    private func scanForLocalModels(presentResult: Bool) {
        AppLogger.shared.info("Starting computer-wide scan for local models...", settings: workflow.settings)
        isScanning = true
        if presentResult {
            statusMessage = "Scanning computer for local models..."
        }

        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)

            let found = LocalModelScanner.scanForLocalModels()

            await MainActor.run {
                var updatedASR = 0
                var updatedTranslation = 0

                self.updateSettings { settings in
                    for scanned in found {
                        if scanned.isTranslation {
                            if var model = settings.localTranslationModels[scanned.id] {
                                model.status = .downloaded
                                model.path = scanned.path
                                model.progress = 1.0
                                model.progressLabel = "Done (Scanned)"
                                settings.localTranslationModels[scanned.id] = model
                                updatedTranslation += 1
                            } else {
                                settings.localTranslationModels[scanned.id] = LocalModelState(
                                    status: .downloaded,
                                    progress: 1.0,
                                    progressLabel: "Done (Scanned)",
                                    label: scanned.label ?? URL(fileURLWithPath: scanned.path).lastPathComponent,
                                    path: scanned.path,
                                    runtime: .mlx
                                )
                                updatedTranslation += 1
                            }
                        } else {
                            if var model = settings.localAsrModels[scanned.id] {
                                model.status = .downloaded
                                model.path = scanned.path
                                model.progress = 1.0
                                model.progressLabel = "Done (Scanned)"
                                settings.localAsrModels[scanned.id] = model
                                updatedASR += 1
                            }
                        }
                    }
                }

                self.isScanning = false
                let total = updatedASR + updatedTranslation
                AppLogger.shared.info("Model scan finished. Found \(found.count) total models on disk (ASR Connected: \(updatedASR), Translation Connected: \(updatedTranslation)).", settings: self.workflow.settings)

                if presentResult {
                    if total > 0 {
                        self.scanResultMessage = "Successfully scanned and connected \(total) local model\(total == 1 ? "" : "s")!\n- Whisper: \(updatedASR)\n- MLX Translation: \(updatedTranslation)"
                        self.statusMessage = "Found and connected \(total) local models."
                    } else {
                        self.scanResultMessage = "No additional local models found in typical system folders."
                        self.statusMessage = "No local models found during scan."
                    }
                    self.isScanResultAlertPresented = true
                }
            }
        }
    }

    public func executeMcpTool(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        let getInt = { (val: Any?) -> Int? in
            if let doubleVal = val as? Double { return Int(doubleVal) }
            return val as? Int
        }
        let getDouble = { (val: Any?) -> Double? in
            if let doubleVal = val as? Double { return doubleVal }
            if let intVal = val as? Int { return Double(intVal) }
            return nil
        }
        
        switch name {
        case "get_project_state":
            var result: [String: Any] = [:]
            result["currentScreen"] = workflow.screen.rawValue
            if let session = workflow.session {
                var sessionInfo: [String: Any] = [:]
                sessionInfo["targetLang"] = session.targetLang
                
                var chunksInfo: [[String: Any]] = []
                for (idx, chunk) in session.chunks.enumerated() {
                    chunksInfo.append([
                        "index": idx,
                        "original": chunk.original,
                        "translated": chunk.translated,
                        "approved": chunk.approved
                    ])
                }
                sessionInfo["chunks"] = chunksInfo
                result["session"] = sessionInfo
            }
            
            // settings
            var settingsInfo: [String: Any] = [:]
            settingsInfo["geminiKey"] = workflow.settings.geminiKey
            result["settings"] = settingsInfo
            
            // shorts plans
            var plansInfo: [[String: Any]] = []
            if let session = workflow.session, let plans = session.shortsPlans {
                for plan in plans {
                    plansInfo.append([
                        "id": plan.id,
                        "title": plan.title,
                        "start": plan.start,
                        "end": plan.end,
                        "summary": plan.summary,
                        "category": plan.category ?? "",
                        "hook": plan.hook ?? ""
                    ])
                }
            }
            result["shortsPlans"] = plansInfo
            return result
            
        case "update_chunk_text":
            guard var session = workflow.session else {
                throw NSError(domain: "WorkflowStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active session"])
            }
            guard let chunkIndexVal = getInt(arguments["chunkIndex"]) else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing or invalid chunkIndex"])
            }
            guard chunkIndexVal >= 0 && chunkIndexVal < session.chunks.count else {
                throw NSError(domain: "WorkflowStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "chunkIndex out of bounds"])
            }
            
            if let original = arguments["original"] as? String {
                session.chunks[chunkIndexVal].original = original
            }
            if let translated = arguments["translated"] as? String {
                session.chunks[chunkIndexVal].translated = translated
            }
            
            workflow.session = session
            saveCurrentProject()
            return ["success": true, "message": "Updated segment \(chunkIndexVal + 1) text"]
            
        case "approve_chunk":
            guard var session = workflow.session else {
                throw NSError(domain: "WorkflowStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active session"])
            }
            guard let chunkIndexVal = getInt(arguments["chunkIndex"]),
                  let approved = arguments["approved"] as? Bool else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing chunkIndex or approved"])
            }
            guard chunkIndexVal >= 0 && chunkIndexVal < session.chunks.count else {
                throw NSError(domain: "WorkflowStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "chunkIndex out of bounds"])
            }
            
            session.chunks[chunkIndexVal].approved = approved
            workflow.session = session
            saveCurrentProject()
            return ["success": true, "message": "Updated approval for segment \(chunkIndexVal + 1) to \(approved)"]
            
        case "get_subtitle_style":
            if let session = workflow.session,
               let plans = session.shortsPlans,
               !plans.isEmpty,
               let style = plans[0].subtitleStyle {
                return [
                    "fontFamily": style.fontFamily,
                    "fontSize": style.fontSize,
                    "textColor": style.textColor,
                    "bold": style.bold
                ]
            }
            return [:]
            
        case "update_subtitle_style":
            guard var session = workflow.session,
                  var plans = session.shortsPlans,
                  !plans.isEmpty else {
                throw NSError(domain: "WorkflowStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active shorts plan to update style for"])
            }
            guard let stylePatch = arguments["stylePatch"] as? [String: Any] else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing stylePatch"])
            }
            
            for idx in plans.indices {
                var style = plans[idx].subtitleStyle ?? ShortsSubtitleStyle(
                    fontFamily: "Outfit",
                    fontSize: 24.0,
                    bold: true,
                    textTransform: .uppercase,
                    textColor: "#ffffff",
                    boxColor: "#000000",
                    boxOpacity: 0.0,
                    boxWidth: 0.0,
                    boxHeight: 0.0,
                    edgeBlur: 0.0,
                    letterSpacing: 0.0,
                    lineSpacing: 0.0,
                    edgeSoftness: 0.0,
                    outline: 0.0,
                    shadow: 0.0
                )
                
                if let fontFamily = stylePatch["fontFamily"] as? String {
                    style.fontFamily = fontFamily
                }
                if let fontSize = getDouble(stylePatch["fontSize"]) {
                    style.fontSize = fontSize
                }
                if let textColor = stylePatch["textColor"] as? String {
                    style.textColor = textColor
                }
                if let bold = stylePatch["bold"] as? Bool {
                    style.bold = bold
                }
                plans[idx].subtitleStyle = style
            }
            session.shortsPlans = plans
            workflow.session = session
            saveCurrentProject()
            return ["success": true, "message": "Updated subtitle style for active shorts plans"]
            
        case "get_shorts_plans":
            var plansInfo: [[String: Any]] = []
            if let session = workflow.session, let plans = session.shortsPlans {
                for plan in plans {
                    plansInfo.append([
                        "id": plan.id,
                        "title": plan.title,
                        "start": plan.start,
                        "end": plan.end,
                        "summary": plan.summary,
                        "category": plan.category ?? "",
                        "hook": plan.hook ?? ""
                    ])
                }
            }
            return ["plans": plansInfo]
            
        default:
            throw NSError(domain: "WorkflowStore", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unknown tool \(name)"])
        }
    }

    public func transcribeDictation(url: URL) async throws -> String {
        guard let model = NativeModelCatalog.activeWhisperKitModel(
            settings: workflow.settings,
            providerID: workflow.settings.transcriptionProvider
        ) else {
            throw NSError(domain: "WorkflowStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No local Whisper model is selected. Please check Settings."])
        }
        
        let config = WhisperKitConfig(
            model: model.variant,
            modelFolder: model.path,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )
        let pipeline = try await WhisperKit(config)
        let options = DecodingOptions()
        let results = try await pipeline.transcribe(audioPath: url.path, decodeOptions: options)
        let text = results.map { $0.text }.joined(separator: " ")
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}

private enum ExportWorkspaceError: LocalizedError {
    case videoExporterUnavailable
    case videoExportFailed

    var errorDescription: String? {
        switch self {
        case .videoExporterUnavailable:
            return "AVFoundation could not create a native video exporter for this media."
        case .videoExportFailed:
            return "AVFoundation video export did not complete."
        }
    }
}

private enum TranslationRoutingError: LocalizedError {
    case noTranslationProvider

    var errorDescription: String? {
        "No cloud translation provider with an API key or downloaded MLX translation model is available."
    }
}

private struct SendableExportSession: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

enum ReviewViewMode: String, CaseIterable, Identifiable {
    case source = "Source"
    case translated = "Translated"
    case dual = "Dual View"

    var id: String { rawValue }
}

public enum ExportCompletionState: Equatable {
    case success
    case failure(String)
}
