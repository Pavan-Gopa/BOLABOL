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
    @Published public var selectedSettingsTab: SettingsTab = .agents
    @Published public var activeTourScreen = ""
    @Published public private(set) var mcpActiveClients: [McpActiveClient] = []

    @Published var outputFormat: OutputFormat = .txt
    @Published var viewMode: ReviewViewMode = .dual
    @Published var statusMessage = ""
    @Published var projects: [ProjectRecord]
    @Published var isProjectSidebarPresented = false
    @Published var showChatSidebar = false
    @Published var chatInputText = ""
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
    private let mcpConfirmationStore = McpConfirmationStore()
    private let mcpJobManager = McpJobManager()
    private let mcpAuditStore = McpAuditStore()
    private let mcpRequestCache = McpRequestCache()
    private let mcpExportStore = McpExportStore()
    private var visualEditorReturnScreen: UniversalWorkflowScreen = .export
    private var processingActivity: NSObjectProtocol?
    private var processingTask: Task<Void, Never>?
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
        loadedSettings.normalizeMcpSettings()
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
            tourStepIndex = SettingsTab.alphabetized.firstIndex(of: selectedSettingsTab) ?? 0
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
        guard SettingsTab.alphabetized.indices.contains(step) else {
            return
        }
        selectedSettingsTab = SettingsTab.alphabetized[step]
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

    func configureMcpServer() {
        McpServer.shared.configure(
            store: self,
            configuration: McpServerConfiguration(settings: workflow.settings)
        )
    }

    func updateMcpActiveClients(_ clients: [McpActiveClient]) {
        mcpActiveClients = clients.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
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
        workflow.settings.normalizeMcpSettings()
        let transcriptionProviderChanged = workflow.settings.transcriptionProvider != previousSettings.transcriptionProvider
        let translationProviderChanged = workflow.settings.translationProvider != previousSettings.translationProvider
        let mcpSettingsChanged = workflow.settings.mcpServerEnabled != previousSettings.mcpServerEnabled
            || workflow.settings.mcpAllowMutatingTools != previousSettings.mcpAllowMutatingTools
            || workflow.settings.mcpAllowProcessingTools != previousSettings.mcpAllowProcessingTools
            || workflow.settings.mcpAllowFileTools != previousSettings.mcpAllowFileTools
            || workflow.settings.mcpAllowNetworkTools != previousSettings.mcpAllowNetworkTools
            || workflow.settings.mcpAllowDestructiveTools != previousSettings.mcpAllowDestructiveTools
            || workflow.settings.mcpAccessToken != previousSettings.mcpAccessToken
        workflow.synchronizeProviderSelections(
            previousSettings: previousSettings,
            forceTranscriptionProvider: transcriptionProviderChanged,
            forceTranslationProvider: translationProviderChanged
        )
        persistSettings()
        refreshProviderSelections()
        if mcpSettingsChanged {
            configureMcpServer()
        }
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

        processingTask = Task {
            await processCurrentSession()
            await MainActor.run {
                self.isProcessingSegment = false
                self.endNativeProcessingActivity()
                self.processingTask = nil
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

        guard !Task.isCancelled else { return }
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

            let found = await Task.detached(priority: .utility) {
                LocalModelScanner.scanForLocalModels()
            }.value

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

    private func startMcpTranslationJob(name: String, arguments: [String: Any]) throws -> [String: Any] {
        guard let session = workflow.session else {
            throw NSError(domain: "WorkflowStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active VaniScript session"])
        }
        let currentRevision = McpProjectRevision.make(workflow: workflow)
        guard let expectedRevision = arguments["expectedRevision"] as? String,
              expectedRevision == currentRevision else {
            throw NSError(domain: "WorkflowStore", code: -6, userInfo: [NSLocalizedDescriptionKey: "STALE_REVISION: Translation jobs require the latest projectRevision from a read tool."])
        }
        let requestedLanguage = (arguments["language"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = TranslationArchive.displayLanguage(
            requestedLanguage?.isEmpty == false
                ? requestedLanguage!
                : (session.selectedTranslationLanguage ?? archiveTargetLanguage)
        )
        guard TranslationArchive.isRealLanguage(language) else {
            throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Choose or provide a real target language"])
        }

        let jobID: String
        switch name {
        case "translate_chunk", "retry_chunk_translation":
            let chunkIndex = try mcpChunkArrayIndex(arguments["chunkId"], session: session)
            jobID = mcpJobManager.start(
                kind: name,
                message: "Translating segment \(session.chunks[chunkIndex].index + 1) to \(language)"
            ) { [weak self] reporter in
                guard let self else { throw CancellationError() }
                reporter.update(progress: 0.05, stage: "Preparing translation")
                let result = try await self.performMcpChunkTranslation(
                    chunkIndex: chunkIndex,
                    language: language,
                    expectedRevision: currentRevision,
                    reporter: reporter
                )
                reporter.update(progress: 1, stage: "Translation complete")
                return result
            }
        case "translate_cue":
            let chunkIndex = try mcpChunkArrayIndex(arguments["chunkId"], session: session)
            let cueIndex = try mcpCueArrayIndex(arguments: arguments, chunk: session.chunks[chunkIndex], side: "original")
            jobID = mcpJobManager.start(
                kind: name,
                message: "Translating cue \(cueIndex + 1) in segment \(session.chunks[chunkIndex].index + 1)"
            ) { [weak self] reporter in
                guard let self else { throw CancellationError() }
                reporter.update(progress: 0.05, stage: "Preparing cue translation")
                let result = try await self.performMcpCueTranslation(
                    chunkIndex: chunkIndex,
                    cueIndex: cueIndex,
                    language: language,
                    expectedRevision: currentRevision,
                    reporter: reporter
                )
                reporter.update(progress: 1, stage: "Cue translation complete")
                return result
            }
        case "translate_pending_chunks":
            let onlyUntranslated = arguments["onlyUntranslated"] as? Bool ?? true
            let indexes = session.chunks.indices.filter { index in
                let sourceExists = !session.chunks[index].original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return sourceExists && (!onlyUntranslated || session.chunks[index].translationText(for: language) == nil)
            }
            guard !indexes.isEmpty else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "No matching segments require translation"])
            }
            jobID = mcpJobManager.start(
                kind: name,
                message: "Translating \(indexes.count) segment(s) to \(language)"
            ) { [weak self] reporter in
                guard let self else { throw CancellationError() }
                var revision = currentRevision
                var translatedIDs = [String]()
                for (position, chunkIndex) in indexes.enumerated() {
                    try reporter.checkCancellation()
                    reporter.update(
                        progress: Double(position) / Double(indexes.count),
                        stage: "Translating segment \(position + 1) of \(indexes.count)"
                    )
                    let result = try await self.performMcpChunkTranslation(
                        chunkIndex: chunkIndex,
                        language: language,
                        expectedRevision: revision,
                        reporter: reporter
                    )
                    translatedIDs.append(result["chunkId"] as? String ?? "")
                    revision = McpProjectRevision.make(workflow: self.workflow)
                }
                reporter.update(progress: 1, stage: "Translation batch complete")
                return ["translatedChunkIds": translatedIDs, "translatedCount": translatedIDs.count]
            }
        case "polish_translation":
            let scope = ((arguments["scope"] as? String) ?? "chunk").lowercased()
            guard ["cue", "chunk", "project"].contains(scope) else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "scope must be cue, chunk, or project"])
            }
            let indexes: [Int]
            if scope == "project" {
                indexes = session.chunks.indices.filter {
                    session.chunks[$0].translationText(for: language) != nil
                }
            } else {
                indexes = [try mcpChunkArrayIndex(arguments["chunkId"], session: session)]
            }
            guard !indexes.isEmpty else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "No translated text is available to polish"])
            }
            let cueIndex = scope == "cue"
                ? try mcpCueArrayIndex(arguments: arguments, chunk: session.chunks[indexes[0]], side: "translated")
                : nil
            jobID = mcpJobManager.start(
                kind: name,
                message: "Polishing \(scope) translation in \(language)"
            ) { [weak self] reporter in
                guard let self else { throw CancellationError() }
                var revision = currentRevision
                var polishedIDs = [String]()
                for (position, chunkIndex) in indexes.enumerated() {
                    try reporter.checkCancellation()
                    reporter.update(
                        progress: Double(position) / Double(indexes.count),
                        stage: "Polishing segment \(position + 1) of \(indexes.count)"
                    )
                    let result = try await self.performMcpTranslationPolish(
                        chunkIndex: chunkIndex,
                        cueIndex: cueIndex,
                        language: language,
                        expectedRevision: revision,
                        reporter: reporter
                    )
                    polishedIDs.append(result["chunkId"] as? String ?? "")
                    revision = McpProjectRevision.make(workflow: self.workflow)
                }
                reporter.update(progress: 1, stage: "Polish complete")
                return ["polishedChunkIds": polishedIDs, "polishedCount": polishedIDs.count]
            }
        default:
            throw NSError(domain: "WorkflowStore", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unknown translation job tool \(name)"])
        }

        return [
            "success": true,
            "jobId": jobID,
            "status": McpJobStatus.queued.rawValue,
            "projectRevision": currentRevision,
        ]
    }

    private func performMcpChunkTranslation(
        chunkIndex: Int,
        language: String,
        expectedRevision: String,
        reporter: McpJobReporter
    ) async throws -> [String: Any] {
        try reporter.checkCancellation()
        guard McpProjectRevision.make(workflow: workflow) == expectedRevision,
              let session = workflow.session,
              session.chunks.indices.contains(chunkIndex) else {
            throw NSError(domain: "WorkflowStore", code: -6, userInfo: [NSLocalizedDescriptionKey: "STALE_REVISION: Project changed before translation could start"])
        }
        let chunk = session.chunks[chunkIndex]
        let source = chunk.original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "The selected segment has no source transcript"])
        }
        let cloudProvider = activeCloudTranslationProvider(for: session)
        let model = cloudProvider == nil ? activeTranslationModel(for: session) : nil
        guard cloudProvider != nil || model != nil else {
            throw TranslationRoutingError.noTranslationProvider
        }

        reporter.update(progress: 0.2, stage: "Running translation model")
        let translatedCues: [TranscriptCue]
        let translated: String
        let providerID: String
        if let cloudProvider {
            translatedCues = try await translateCurrentStoredCuesWithCloud(
                chunk.originalCues ?? [],
                targetLanguage: language,
                metadata: session.metadata,
                provider: cloudProvider
            )
            translated = translatedCues.isEmpty
                ? try await reviewCloudEngine.translate(
                    text: source,
                    targetLang: language,
                    metadata: session.metadata,
                    glossary: workflow.settings.glossary,
                    provider: cloudProvider,
                    promptPresets: workflow.settings.promptPresets
                )
                : translatedCues.map(\.text).joined(separator: "\n")
            providerID = cloudProvider.id
        } else if let model {
            translatedCues = try await translateCurrentStoredCues(
                chunk.originalCues ?? [],
                targetLanguage: language,
                metadata: session.metadata,
                model: model
            )
            translated = translatedCues.isEmpty
                ? try await reviewMLXEngine.translate(
                    text: source,
                    targetLang: language,
                    metadata: session.metadata,
                    glossary: workflow.settings.glossary,
                    model: model,
                    promptPresets: workflow.settings.promptPresets
                )
                : translatedCues.map(\.text).joined(separator: "\n")
            providerID = model.id
        } else {
            throw TranslationRoutingError.noTranslationProvider
        }
        try reporter.checkCancellation()
        guard TranslationArchive.isUsableTranslationText(translated),
              McpProjectRevision.make(workflow: workflow) == expectedRevision,
              var latest = workflow.session,
              latest.chunks.indices.contains(chunkIndex) else {
            throw NSError(domain: "WorkflowStore", code: -6, userInfo: [NSLocalizedDescriptionKey: "Translation was empty or the project changed before it could be saved"])
        }
        latest.chunks[chunkIndex].translated = translated
        latest.chunks[chunkIndex].setTranslation(
            translated,
            language: language,
            provider: providerID,
            updatedAt: isoString(clock()),
            cues: translatedCues.isEmpty ? nil : translatedCues
        )
        latest.chunks[chunkIndex].status = .done
        latest.setActiveTranslationLanguage(language)
        workflow.session = latest
        workflow.targetLang = language
        archiveTargetLanguage = language
        saveCurrentProject()
        return [
            "chunkId": McpEntityIdentifier.chunkID(latest.chunks[chunkIndex]),
            "language": language,
            "provider": providerID,
            "projectRevision": McpProjectRevision.make(workflow: workflow),
        ]
    }

    private func performMcpCueTranslation(
        chunkIndex: Int,
        cueIndex: Int,
        language: String,
        expectedRevision: String,
        reporter: McpJobReporter
    ) async throws -> [String: Any] {
        try reporter.checkCancellation()
        guard McpProjectRevision.make(workflow: workflow) == expectedRevision,
              let session = workflow.session,
              session.chunks.indices.contains(chunkIndex),
              let sourceCues = session.chunks[chunkIndex].originalCues,
              sourceCues.indices.contains(cueIndex) else {
            throw NSError(domain: "WorkflowStore", code: -6, userInfo: [NSLocalizedDescriptionKey: "STALE_REVISION: Cue changed before translation could start"])
        }
        let sourceCue = sourceCues[cueIndex]
        let cloudProvider = activeCloudTranslationProvider(for: session)
        let model = cloudProvider == nil ? activeTranslationModel(for: session) : nil
        let translated: String
        let providerID: String
        reporter.update(progress: 0.2, stage: "Running cue translation model")
        if let cloudProvider {
            translated = try await reviewCloudEngine.translate(
                text: sourceCue.text,
                targetLang: language,
                metadata: session.metadata,
                glossary: workflow.settings.glossary,
                provider: cloudProvider,
                promptPresets: workflow.settings.promptPresets
            )
            providerID = cloudProvider.id
        } else if let model {
            translated = try await reviewMLXEngine.translate(
                text: sourceCue.text,
                targetLang: language,
                metadata: session.metadata,
                glossary: workflow.settings.glossary,
                model: model,
                promptPresets: workflow.settings.promptPresets
            )
            providerID = model.id
        } else {
            throw TranslationRoutingError.noTranslationProvider
        }
        try reporter.checkCancellation()
        guard TranslationArchive.isUsableTranslationText(translated),
              McpProjectRevision.make(workflow: workflow) == expectedRevision,
              var latest = workflow.session,
              latest.chunks.indices.contains(chunkIndex) else {
            throw NSError(domain: "WorkflowStore", code: -6, userInfo: [NSLocalizedDescriptionKey: "Cue translation was empty or the project changed before save"])
        }
        var targetCues = latest.chunks[chunkIndex].translationCues(for: language)
        if targetCues.count != sourceCues.count {
            targetCues = sourceCues.map { TranscriptCue(startSec: $0.startSec, endSec: $0.endSec, text: "") }
        }
        targetCues[cueIndex].text = translated
        targetCues[cueIndex].words = NativeLLMPromptBuilder.approximateWords(for: translated, source: sourceCue)
        let finalText = targetCues.map(\.text).joined(separator: "\n")
        latest.chunks[chunkIndex].translated = finalText
        latest.chunks[chunkIndex].setTranslation(
            finalText,
            language: language,
            provider: providerID,
            updatedAt: isoString(clock()),
            cues: targetCues
        )
        latest.setActiveTranslationLanguage(language)
        workflow.session = latest
        workflow.targetLang = language
        archiveTargetLanguage = language
        saveCurrentProject()
        return [
            "chunkId": McpEntityIdentifier.chunkID(latest.chunks[chunkIndex]),
            "cueId": McpEntityIdentifier.cueID(chunk: latest.chunks[chunkIndex], side: "translated", index: cueIndex),
            "language": language,
            "provider": providerID,
        ]
    }

    private func performMcpTranslationPolish(
        chunkIndex: Int,
        cueIndex: Int?,
        language: String,
        expectedRevision: String,
        reporter: McpJobReporter
    ) async throws -> [String: Any] {
        try reporter.checkCancellation()
        guard McpProjectRevision.make(workflow: workflow) == expectedRevision,
              let session = workflow.session,
              session.chunks.indices.contains(chunkIndex),
              let model = activeTranslationModel(for: session) else {
            throw NSError(domain: "WorkflowStore", code: -6, userInfo: [NSLocalizedDescriptionKey: "Project changed or no downloaded MLX model is available for polishing"])
        }
        let chunk = session.chunks[chunkIndex]
        var targetCues = chunk.translationCues(for: language)
        let text: String
        if let cueIndex {
            guard targetCues.indices.contains(cueIndex) else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Translated cue is not available"])
            }
            text = targetCues[cueIndex].text
        } else {
            text = chunk.translationText(for: language) ?? chunk.translated
        }
        guard TranslationArchive.isUsableTranslationText(text) else {
            throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "No usable translated text is available to polish"])
        }
        reporter.update(progress: 0.2, stage: "Running polish model")
        let polished = try await reviewMLXEngine.polish(
            text: text,
            targetLang: language,
            model: model,
            lecturer: session.metadata.lecturer,
            glossary: workflow.settings.glossary,
            promptPresets: workflow.settings.promptPresets
        )
        try reporter.checkCancellation()
        guard TranslationArchive.isUsableTranslationText(polished),
              McpProjectRevision.make(workflow: workflow) == expectedRevision,
              var latest = workflow.session else {
            throw NSError(domain: "WorkflowStore", code: -6, userInfo: [NSLocalizedDescriptionKey: "Polish result was empty or the project changed before save"])
        }
        if let cueIndex {
            targetCues[cueIndex].text = polished
            targetCues[cueIndex].words = NativeLLMPromptBuilder.approximateWords(for: polished, source: targetCues[cueIndex])
        } else {
            targetCues = WorkflowStore.reconstructCues(from: polished, matching: chunk.originalCues ?? [])
        }
        let finalText = cueIndex == nil ? polished : targetCues.map(\.text).joined(separator: "\n")
        latest.chunks[chunkIndex].translated = finalText
        latest.chunks[chunkIndex].setTranslation(
            finalText,
            language: language,
            provider: model.id,
            updatedAt: isoString(clock()),
            cues: targetCues.isEmpty ? nil : targetCues
        )
        latest.setActiveTranslationLanguage(language)
        workflow.session = latest
        workflow.targetLang = language
        archiveTargetLanguage = language
        saveCurrentProject()
        return [
            "chunkId": McpEntityIdentifier.chunkID(latest.chunks[chunkIndex]),
            "language": language,
            "scope": cueIndex == nil ? "chunk" : "cue",
        ]
    }

    private func mcpChunkArrayIndex(_ rawValue: Any?, session: SessionState) throws -> Int {
        guard let chunkID = rawValue as? String,
              let stableIndex = McpEntityIdentifier.chunkIndex(from: chunkID),
              let arrayIndex = session.chunks.firstIndex(where: { $0.index == stableIndex }) else {
            throw NSError(domain: "WorkflowStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unknown or missing chunkId. Call list_chunks first."])
        }
        return arrayIndex
    }

    private func mcpCueArrayIndex(arguments: [String: Any], chunk: ChunkData, side: String) throws -> Int {
        let cues = side == "original"
            ? (chunk.originalCues ?? [])
            : chunk.translationCues(for: arguments["language"] as? String ?? workflow.session?.selectedTranslationLanguage)
        if let cueID = arguments["cueId"] as? String,
           let index = cues.indices.first(where: {
               McpEntityIdentifier.cueID(chunk: chunk, side: side, index: $0) == cueID
           }) {
            return index
        }
        if let cueIndex = McpToolArguments.wholeNumber(arguments["cueIndex"]), cues.indices.contains(cueIndex) {
            return cueIndex
        }
        throw NSError(domain: "WorkflowStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unknown cue reference. Call get_chunk_cues first."])
    }

    private func executeMcpWorkspaceTool(
        name: String,
        arguments: [String: Any],
        permissions: McpPermissionSet
    ) async throws -> [String: Any]? {
        switch name {
        case "list_projects":
            let cursor = max(0, McpToolArguments.wholeNumber(arguments["cursor"]) ?? 0)
            let limit = max(1, min(100, McpToolArguments.wholeNumber(arguments["limit"]) ?? 30))
            let sorted = ProjectArchive.sortedRecent(projects)
            let page = Array(sorted.dropFirst(cursor).prefix(limit))
            return [
                "projects": page.map { mcpProjectSummary($0) },
                "cursor": cursor,
                "nextCursor": cursor + page.count,
                "hasMore": cursor + page.count < sorted.count,
                "total": sorted.count,
                "activeProjectId": currentProjectID ?? "",
            ]

        case "get_project_summary":
            guard let projectID = mcpString(arguments["projectId"]),
                  let record = projects.first(where: { $0.id == projectID }) else {
                throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown projectId")
            }
            return ["project": mcpProjectSummary(record), "isActive": currentProjectID == projectID]

        case "open_project":
            guard let projectID = mcpString(arguments["projectId"]),
                  projects.contains(where: { $0.id == projectID }) else {
                throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown projectId")
            }
            let screen = mcpString(arguments["screen"]) ?? "review"
            var chunkIndex: Int?
            if let chunkID = mcpString(arguments["chunkId"]), let stable = McpEntityIdentifier.chunkIndex(from: chunkID) {
                chunkIndex = projects.first(where: { $0.id == projectID })?.session.chunks.firstIndex(where: { $0.index == stable })
                if chunkIndex == nil { throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown chunkId in project") }
            }
            // Open through the non-processing route, then select the requested workspace.
            openProject(id: projectID, chunkIndex: chunkIndex, openExport: true)
            workflow.screen = screen == "export" ? .export : .review
            return [
                "success": true,
                "projectId": projectID,
                "screen": workflow.screen.rawValue,
                "projectRevision": McpProjectRevision.make(workflow: workflow),
            ]

        case "save_project":
            guard currentProjectID != nil, workflow.session != nil else {
                throw mcpError(-1, "NO_ACTIVE_PROJECT: No project is open")
            }
            saveCurrentProject()
            return ["success": true, "projectId": currentProjectID ?? "", "message": "Project saved"]

        case "reset_session":
            let revision = McpProjectRevision.make(workflow: workflow)
            let fingerprint = currentProjectID ?? "unsaved-session"
            if arguments["dryRun"] as? Bool ?? true {
                let token = mcpConfirmationStore.issue(
                    operation: "reset_session",
                    fingerprint: fingerprint,
                    projectRevision: revision
                )
                return [
                    "dryRun": true,
                    "activeProjectId": currentProjectID ?? "",
                    "hasUnsavedSession": workflow.session != nil,
                    "confirmationToken": token,
                    "confirmationExpiresInSec": 120,
                ]
            }
            try consumeMcpConfirmation(
                arguments: arguments,
                operation: "reset_session",
                fingerprint: fingerprint,
                revision: revision
            )
            newSession()
            return ["success": true, "message": "Session reset"]

        case "get_source_media_info":
            let requestedID = mcpString(arguments["projectId"])
            let mediaInfo: SourceMediaInfo?
            if let requestedID {
                mediaInfo = projects.first(where: { $0.id == requestedID })?.session.sourceMediaInfo
                    ?? sourceMediaInfo(for: requestedID)
            } else {
                mediaInfo = workflow.session?.sourceMediaInfo ?? workflow.sourceMediaInfo
            }
            guard let mediaInfo else {
                throw mcpError(-3, "ENTITY_NOT_FOUND: Source media information is unavailable")
            }
            return ["media": mcpSourceMediaInfo(mediaInfo)]

        case "delete_project":
            guard let projectID = mcpString(arguments["projectId"]),
                  let record = projects.first(where: { $0.id == projectID }) else {
                throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown projectId")
            }
            let revision = McpProjectRevision.make(workflow: workflow)
            if arguments["dryRun"] as? Bool ?? true {
                let token = mcpConfirmationStore.issue(
                    operation: "delete_project",
                    fingerprint: projectID,
                    projectRevision: revision
                )
                return [
                    "dryRun": true,
                    "project": mcpProjectSummary(record),
                    "willCloseActiveProject": projectID == currentProjectID,
                    "confirmationToken": token,
                    "confirmationExpiresInSec": 120,
                ]
            }
            try consumeMcpConfirmation(
                arguments: arguments,
                operation: "delete_project",
                fingerprint: projectID,
                revision: revision
            )
            deleteProject(id: projectID)
            return ["success": true, "projectId": projectID, "message": "Project deleted"]

        case "import_media_file":
            return try await mcpImportMediaFile()

        case "import_media_url":
            return try startMcpMediaImportJob(arguments: arguments)

        case "import_project_bundle":
            return try mcpImportProjectBundle()

        case "export_project_bundle":
            return try mcpExportProjectBundle(arguments: arguments)

        case "get_workflow_config":
            return mcpWorkflowConfig()

        case "update_workflow_config":
            return try mcpUpdateWorkflowConfig(arguments: arguments)

        case "start_processing":
            return try startMcpProcessingJob(retryFailedOnly: false)

        case "retry_failed_chunks":
            return try startMcpProcessingJob(retryFailedOnly: true)

        case "cancel_processing":
            if let jobID = mcpString(arguments["jobId"]), mcpJobManager.cancel(id: jobID) {
                return ["success": true, "jobId": jobID, "status": "cancelled"]
            }
            processingTask?.cancel()
            processingTask = nil
            exportTask?.cancel()
            exportTask = nil
            isProcessingSegment = false
            endNativeProcessingActivity()
            return ["success": true, "message": "Active UI processing was cancelled"]

        case "select_chunk":
            guard var session = workflow.session,
                  let chunkID = mcpString(arguments["chunkId"]),
                  let stableIndex = McpEntityIdentifier.chunkIndex(from: chunkID),
                  let arrayIndex = session.chunks.firstIndex(where: { $0.index == stableIndex }) else {
                throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown chunkId")
            }
            stopPlayback()
            session.currentChunkIndex = arrayIndex
            workflow.session = session
            workflow.screen = .review
            return ["success": true, "chunkId": chunkID, "displayNumber": arrayIndex + 1]

        case "generate_shorts_plans":
            return try startMcpShortsPlanningJob(arguments: arguments)

        case "get_shorts_plan":
            let resolved = try mcpResolveShortsPlan(arguments["planId"], rejected: false)
            return ["plan": mcpShortsPlanDictionary(resolved.plan, index: resolved.index, rejected: false)]

        case "create_shorts_plan":
            return try mcpCreateShortsPlan(arguments: arguments)

        case "update_shorts_plan":
            return try mcpUpdateShortsPlan(arguments: arguments)

        case "update_shorts_timing":
            return try mcpUpdateShortsTiming(arguments: arguments)

        case "remove_shorts_plan":
            return try mcpRemoveShortsPlan(arguments: arguments)

        case "list_rejected_shorts_plans":
            let rejected = workflow.session?.shortsRejectedPlans ?? []
            return ["plans": rejected.enumerated().map { mcpShortsPlanDictionary($0.element, index: $0.offset, rejected: true) }]

        case "restore_shorts_plan":
            return try mcpRestoreShortsPlan(arguments: arguments)

        case "translate_shorts_plans":
            return try startMcpShortsTranslationJob(arguments: arguments)

        case "validate_shorts_plan":
            let resolved = try mcpResolveShortsPlan(arguments["planId"], rejected: false)
            return mcpValidateShortsPlan(resolved.plan)

        case "open_visual_editor":
            let resolved = try mcpResolveShortsPlan(arguments["planId"], rejected: false)
            let language = ShortsIdeaDisplayLanguage(rawValue: mcpString(arguments["language"]) ?? "source") ?? .source
            openVisualEditor(at: resolved.index, plan: resolved.plan, language: language)
            return ["success": true, "planId": resolved.plan.id, "screen": workflow.screen.rawValue, "language": language.rawValue]

        case "get_visual_editor_state":
            let resolved = try mcpResolveShortsPlan(arguments["planId"], rejected: false)
            return mcpVisualEditorState(plan: resolved.plan, index: resolved.index)

        case "update_clip_details":
            return try mcpUpdateShortsPlan(arguments: arguments)

        case "update_clip_timing":
            return try mcpUpdateShortsTiming(arguments: arguments)

        case "manage_timeline_cut":
            return try mcpManageTimelineCut(arguments: arguments, permissions: permissions)

        case "manage_subtitle_segment":
            return try mcpManageSubtitleSegment(arguments: arguments, permissions: permissions)

        case "analyze_clip_speech_regions":
            return try await mcpAnalyzeClipSpeechRegions(arguments: arguments)

        case "snap_subtitle_segments_to_speech":
            return try await mcpSnapSubtitleSegmentsToSpeech(arguments: arguments)

        case "set_frame_keyframes":
            return try mcpSetFrameKeyframes(arguments: arguments)

        case "clear_frame_keyframes":
            return try mcpClearFrameKeyframes(arguments: arguments)

        case "update_visual_background":
            return try mcpUpdateVisualBackground(arguments: arguments)

        case "update_visual_subtitle_style":
            return try mcpUpdateVisualSubtitleStyle(arguments: arguments)

        case "update_visual_logo":
            return try mcpUpdateVisualLogo(arguments: arguments, permissions: permissions)

        case "update_intro_outro":
            return try mcpUpdateIntroOutro(arguments: arguments, permissions: permissions)

        case "set_visual_sync":
            return try mcpSetVisualSync(arguments: arguments)

        case "manage_text_track":
            return try mcpManageTextTrack(arguments: arguments, permissions: permissions)

        case "manage_text_block":
            return try mcpManageTextBlock(arguments: arguments, permissions: permissions)

        case "manage_audio_track":
            return try mcpManageAudioTrack(arguments: arguments, permissions: permissions)

        case "save_visual_editor":
            let resolved = try mcpResolveShortsPlan(arguments["planId"], rejected: false)
            saveCurrentProject()
            return ["success": true, "planId": resolved.plan.id, "message": "Visual Editor state saved"]

        case "get_safe_settings":
            return mcpSafeSettings()

        case "update_safe_settings":
            return try mcpUpdateSafeSettings(arguments: arguments)

        case "list_providers":
            return mcpListProviders()

        case "select_provider":
            return try mcpSelectProvider(arguments: arguments)

        case "list_prompt_presets":
            return mcpListPromptPresets()

        case "get_prompt":
            return try mcpGetPrompt(arguments: arguments)

        case "update_prompt":
            return try mcpUpdatePrompt(arguments: arguments)

        case "reset_prompt":
            return try mcpResetPrompt(arguments: arguments)

        case "get_model_status":
            return mcpModelStatus()

        case "scan_local_models":
            scanForLocalModels()
            return ["success": true, "message": "Local model scan started", "models": mcpModelStatus()["models"] ?? []]

        case "download_model":
            return try mcpDownloadModel(arguments: arguments)

        case "locate_model":
            return try mcpLocateModel(arguments: arguments)

        case "remove_model":
            return try mcpRemoveModel(arguments: arguments)

        case "get_playback_state":
            return mcpPlaybackState()

        case "play_chunk":
            if let chunkID = mcpString(arguments["chunkId"]) {
                _ = try await executeMcpWorkspaceTool(name: "select_chunk", arguments: ["chunkId": chunkID], permissions: permissions)
            }
            guard let chunk = currentChunk else { throw mcpError(-1, "NO_ACTIVE_PROJECT: No selected segment") }
            guard !chunk.filePath.isEmpty, FileManager.default.fileExists(atPath: chunk.filePath) else {
                throw mcpError(-3, "Segment audio is unavailable. Use reprocess_chunk with Run Processing permission.")
            }
            startPlayback()
            return mcpPlaybackState()

        case "pause_playback":
            pausePlayback()
            return mcpPlaybackState()

        case "seek_playback":
            guard let position = mcpDouble(arguments["positionSec"]), position >= 0 else {
                throw mcpError(-2, "positionSec must be a non-negative finite number")
            }
            seekCurrentChunk(to: position)
            return mcpPlaybackState()

        case "list_export_options":
            return mcpExportOptions()

        case "validate_export":
            guard let kind = mcpString(arguments["kind"]) else { throw mcpError(-2, "kind is required") }
            return try mcpValidateExport(kind: kind)

        case "export_transcript":
            return try mcpExportTranscript(arguments: arguments)

        case "export_shorts_ideas":
            return try mcpExportShortsIdeas(arguments: arguments)

        case "export_shorts_videos":
            return try startMcpShortsExportJob(arguments: arguments)

        case "reveal_export":
            guard let exportID = mcpString(arguments["exportId"]) else { throw mcpError(-2, "exportId is required") }
            return try mcpExportStore.reveal(exportID: exportID)

        default:
            return nil
        }
    }

    private func mcpImportMediaFile() async throws -> [String: Any] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .quickTimeMovie]
        panel.message = "Choose audio or video to import for this MCP request"
        guard panel.runModal() == .OK, let url = panel.url else {
            throw mcpError(-9, "USER_CANCELLED: Media selection was cancelled")
        }
        guard MediaSource.kind(forPath: url.path) != .unknown else {
            throw mcpError(-2, "VALIDATION_FAILED: Unsupported media file")
        }
        let duration = await MediaDurationReader.durationSeconds(for: url)
        let info = await SourceMediaInspector.inspect(fileURL: url, durationSec: duration)
        selectSource(url: url, duration: duration, sourceMediaInfo: info)
        return ["success": true, "media": mcpSourceMediaInfo(info), "screen": workflow.screen.rawValue]
    }

    private func startMcpMediaImportJob(arguments: [String: Any]) throws -> [String: Any] {
        guard let rawURL = mcpString(arguments["url"]), rawURL.count <= 4_096 else {
            throw mcpError(-2, "url is required and must contain no more than 4,096 characters")
        }
        guard McpNetworkPolicy.validatedPublicMediaURL(rawURL) != nil,
              MediaSource.isWebVideoOrAudioLink(rawURL) || MediaSource.directMediaURL(from: rawURL) != nil else {
            throw mcpError(-2, "VALIDATION_FAILED: URL is not a supported media source")
        }
        let audioOnly = arguments["audioOnly"] as? Bool ?? false
        let jobID = mcpJobManager.start(kind: "import_media_url", message: "Importing media URL") { [weak self] reporter in
            guard let self else { throw self?.mcpError(-1, "VaniScript is unavailable") ?? NSError(domain: "VaniScriptMCP", code: -1) }
            reporter.update(progress: 0.01, stage: "Validating URL")
            let imported = try await DirectMediaImporter.importMediaWithMetadata(
                from: rawURL,
                resolverEndpoint: self.workflow.settings.mediaResolverEndpoint,
                resolverToken: self.workflow.settings.mediaResolverToken,
                audioOnly: audioOnly
            ) { progress in
                Task { @MainActor in reporter.update(progress: max(0.02, progress * 0.88), stage: "Downloading media") }
            } onMessage: { message in
                Task { @MainActor in reporter.update(progress: 0.05, stage: "Importing media", message: message) }
            }
            try reporter.checkCancellation()
            reporter.update(progress: 0.9, stage: "Reading media metadata")
            let duration = await MediaDurationReader.durationSeconds(for: imported.fileURL)
            let info = await SourceMediaInspector.inspect(
                fileURL: imported.fileURL,
                originalURL: rawURL,
                title: imported.title,
                durationSec: duration
            )
            try reporter.checkCancellation()
            self.selectSource(url: imported.fileURL, duration: duration, sourceMediaInfo: info)
            if let title = imported.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                self.workflow.sourceFileName = title
                self.workflow.metadata = MetadataExtractor.extract(fromFileName: title)
            }
            return ["media": self.mcpSourceMediaInfo(info), "screen": self.workflow.screen.rawValue]
        }
        return ["jobId": jobID, "status": "queued", "kind": "import_media_url"]
    }

    private func mcpImportProjectBundle() throws -> [String: Any] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let bundleType = UTType(filenameExtension: "vaniscript", conformingTo: .data) ?? .data
        let libraryType = UTType(filenameExtension: "vaniscript-library", conformingTo: .data) ?? .data
        panel.allowedContentTypes = [.json, bundleType, libraryType]
        panel.message = "Choose a VaniScript project bundle to import for this MCP request"
        guard panel.runModal() == .OK, let url = panel.url else {
            throw mcpError(-9, "USER_CANCELLED: Project bundle selection was cancelled")
        }
        let destination = AppStoragePaths.applicationSupportDirectory()
            .appendingPathComponent("Projects", isDirectory: true)
        let imported = try ProjectBundleImporter.importBundle(fileURL: url, destinationDirectoryURL: destination)
        mergeProjects(imported)
        return ["success": true, "importedCount": imported.count, "projectIds": imported.map(\.id)]
    }

    private func mcpExportProjectBundle(arguments: [String: Any]) throws -> [String: Any] {
        let projectID = mcpString(arguments["projectId"]) ?? currentProjectID
        guard let projectID, let record = projects.first(where: { $0.id == projectID }) else {
            throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown projectId and no active project")
        }
        let export = try mcpExportStore.makeDirectory(label: "project")
        let stem = URL(fileURLWithPath: record.session.sourceFileName).deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"[^A-Za-z0-9А-Яа-я_-]+"#, with: "-", options: .regularExpression)
        let file = export.url.appendingPathComponent(stem.isEmpty ? "VaniScript-Project" : stem).appendingPathExtension("vaniscript")
        try ProjectBundleExporter.exportBundle(record: record, to: file)
        return mcpExportStore.register(exportID: export.id, files: [file])
    }

    private func mcpWorkflowConfig() -> [String: Any] {
        [
            "sourceLanguage": workflow.sourceLang,
            "targetLanguage": workflow.targetLang,
            "transcriptionProvider": workflow.transcriptionProvider,
            "translationProvider": workflow.translationProvider,
            "formats": workflow.outputFormats.map { $0.rawValue.lowercased() },
            "chunkDurationMin": workflow.settings.chunkDurationMin,
            "sliceMode": workflow.settings.sliceMode.rawValue,
            "silenceThresholdDb": workflow.settings.silenceThreshDb,
            "minimumSilenceMs": workflow.settings.minSilenceMs,
            "hasSource": !workflow.sourceFile.isEmpty,
            "hasSession": workflow.session != nil,
        ]
    }

    private func mcpUpdateWorkflowConfig(arguments: [String: Any]) throws -> [String: Any] {
        if let source = mcpString(arguments["sourceLanguage"]) {
            workflow.sourceLang = source
        }
        if let target = mcpString(arguments["targetLanguage"]) {
            guard target.lowercased() == "same" || TranslationArchive.isRealLanguage(target) else {
                throw mcpError(-2, "targetLanguage must be a real language or same")
            }
            workflow.updateTargetLanguage(target)
            archiveTargetLanguage = target
        }
        if let provider = mcpString(arguments["transcriptionProvider"]) {
            let available = ProviderRegistry.availableTranscriptionProviders(settings: workflow.settings)
            guard available.contains(where: { $0.id == provider }) else {
                throw mcpError(-10, "PROVIDER_NOT_READY: Transcription provider is unavailable")
            }
            workflow.transcriptionProvider = provider
        }
        if let provider = mcpString(arguments["translationProvider"]) {
            let available = ProviderRegistry.availableTranslationProviders(
                settings: workflow.settings,
                targetLang: workflow.targetLang
            ).providers
            guard available.contains(where: { $0.id == provider }) else {
                throw mcpError(-10, "PROVIDER_NOT_READY: Translation provider is unavailable")
            }
            workflow.translationProvider = provider
        }
        if let rawFormats = arguments["formats"] as? [String] {
            let formats = try rawFormats.map { value -> OutputFormat in
                switch value.lowercased() {
                case "txt": return .txt
                case "markdown": return .markdown
                case "srt": return .srt
                case "vtt": return .vtt
                default: throw mcpError(-2, "Unsupported output format: \(value)")
                }
            }
            guard !formats.isEmpty else { throw mcpError(-2, "formats may not be empty") }
            workflow.outputFormats = formats.reduce(into: []) { result, format in
                if !result.contains(format) { result.append(format) }
            }
        }
        if let duration = McpToolArguments.wholeNumber(arguments["chunkDurationMin"]) {
            guard (1...120).contains(duration) else { throw mcpError(-2, "chunkDurationMin must be between 1 and 120") }
            workflow.settings.chunkDurationMin = duration
        }
        if let rawMode = mcpString(arguments["sliceMode"]), let mode = SliceMode(rawValue: rawMode) {
            workflow.settings.sliceMode = mode
        }
        if var session = workflow.session {
            session.sourceLang = workflow.sourceLang
            session.targetLang = workflow.targetLang
            session.transcriptionProvider = workflow.transcriptionProvider
            session.translationProvider = workflow.translationProvider
            session.outputFormats = workflow.outputFormats
            workflow.session = session
            saveCurrentProject()
        }
        persistSettings()
        return ["success": true, "config": mcpWorkflowConfig()]
    }

    private func startMcpProcessingJob(retryFailedOnly: Bool) throws -> [String: Any] {
        if workflow.session == nil {
            guard !workflow.sourceFile.isEmpty else { throw mcpError(-1, "NO_ACTIVE_PROJECT: Import media first") }
            workflow.startSession()
            createProjectIfNeeded()
            saveCurrentProject()
        }
        guard let session = workflow.session else { throw mcpError(-1, "NO_ACTIVE_PROJECT") }
        let indexes: [Int]
        if retryFailedOnly {
            indexes = session.chunks.indices.filter { session.chunks[$0].status == .error }
        } else {
            let pending = session.chunks.indices.filter { session.chunks[$0].status != .done }
            indexes = pending.isEmpty ? [session.currentChunkIndex] : Array(pending)
        }
        guard !indexes.isEmpty else { throw mcpError(-3, "No matching segments to process") }
        let startingRevision = McpProjectRevision.make(workflow: workflow)
        let kind = retryFailedOnly ? "retry_failed_chunks" : "start_processing"
        let jobID = mcpJobManager.start(kind: kind, message: "Processing \(indexes.count) segment(s)") { [weak self] reporter in
            guard let self else { throw NSError(domain: "VaniScriptMCP", code: -1) }
            for (position, index) in indexes.enumerated() {
                try reporter.checkCancellation()
                guard var current = self.workflow.session, current.chunks.indices.contains(index) else {
                    throw self.mcpError(-6, "Project changed while processing")
                }
                current.currentChunkIndex = index
                self.workflow.session = current
                self.workflow.screen = .processing
                reporter.update(
                    progress: Double(position) / Double(max(1, indexes.count)),
                    stage: "Processing segment \(position + 1) / \(indexes.count)"
                )
                let processed = await self.processingPipeline.processCurrentChunk(
                    session: current,
                    settings: self.workflow.settings,
                    projectId: self.currentProjectID
                ) { message, progress in
                    await MainActor.run {
                        self.workflow.processingMessage = message
                        self.workflow.processingProgress = progress
                        reporter.update(
                            progress: (Double(position) + progress) / Double(max(1, indexes.count)),
                            stage: message
                        )
                    }
                }
                try reporter.checkCancellation()
                self.workflow.session = processed
                self.saveCurrentProject()
                if processed.chunks.indices.contains(index), processed.chunks[index].status == .error {
                    throw self.mcpError(-10, "Segment \(index + 1) processing failed")
                }
            }
            self.workflow.screen = .review
            let finalRevision = McpProjectRevision.make(workflow: self.workflow)
            let change = self.mcpAuditStore.record(
                toolName: kind,
                requestID: nil,
                previousRevision: startingRevision,
                projectRevision: finalRevision
            )
            return [
                "processedChunkIds": indexes.compactMap { index in
                    self.workflow.session?.chunks.indices.contains(index) == true
                        ? self.workflow.session.map { McpEntityIdentifier.chunkID($0.chunks[index]) } : nil
                },
                "changeSetId": change.id,
                "projectRevision": finalRevision,
            ]
        }
        return ["jobId": jobID, "status": "queued", "kind": kind, "segmentCount": indexes.count]
    }

    private func startMcpShortsPlanningJob(arguments: [String: Any]) throws -> [String: Any] {
        guard let session = workflow.session else { throw mcpError(-1, "NO_ACTIVE_PROJECT: No project is open") }
        let count = max(1, min(20, McpToolArguments.wholeNumber(arguments["count"]) ?? 5))
        let minimum = max(10, min(300, McpToolArguments.wholeNumber(arguments["minDurationSec"]) ?? 30))
        let maximum = max(10, min(300, McpToolArguments.wholeNumber(arguments["maxDurationSec"]) ?? 90))
        guard minimum <= maximum else { throw mcpError(-2, "minDurationSec may not exceed maxDurationSec") }
        let mode = ShortsPlanLanguageMode(rawValue: mcpString(arguments["mode"]) ?? "target")
            ?? (session.selectedTranslationLanguage == nil ? .source : .target)
        let transcript = shortsPlanningTranscript(for: session, mode: mode)
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw mcpError(-3, "No transcript text is available for the requested Shorts mode")
        }
        let route: ShortsPlanRoute
        if let cloud = activeCloudTranslationProvider(for: session) {
            route = .cloud(cloud)
        } else if let model = activeTranslationModel(for: session) {
            route = .mlx(model)
        } else {
            throw mcpError(-10, "PROVIDER_NOT_READY: Configure a cloud provider or download an MLX model")
        }
        let outputLanguage = shortsOutputLanguage(for: session, mode: mode)
        let excluded = (session.shortsPlans ?? []) + (session.shortsRejectedPlans ?? [])
        let startingRevision = McpProjectRevision.make(workflow: workflow)
        let jobID = mcpJobManager.start(kind: "generate_shorts_plans", message: "Finding Shorts/Reels moments with \(route.label)") { [weak self] reporter in
            guard let self else { throw NSError(domain: "VaniScriptMCP", code: -1) }
            reporter.update(progress: 0.05, stage: "Building planning prompt")
            let plans: [ShortsClipPlan]
            switch route {
            case let .cloud(provider):
                plans = try await self.shortsCloudEngine.planShorts(
                    transcript: transcript,
                    count: count,
                    minDurationSec: minimum,
                    maxDurationSec: maximum,
                    outputLanguage: outputLanguage,
                    speakerName: session.metadata.lecturer,
                    mode: mode,
                    existingClips: excluded,
                    provider: provider
                )
            case let .mlx(model):
                plans = try await self.shortsMLXEngine.planShorts(
                    transcript: transcript,
                    count: count,
                    minDurationSec: minimum,
                    maxDurationSec: maximum,
                    outputLanguage: outputLanguage,
                    speakerName: session.metadata.lecturer,
                    mode: mode,
                    existingClips: excluded,
                    model: model
                )
            }
            try reporter.checkCancellation()
            reporter.update(progress: 0.9, stage: "Validating candidate ranges")
            guard var latest = self.workflow.session else { throw self.mcpError(-6, "Project was closed during planning") }
            let incoming = plans.map { plan -> ShortsClipPlan in
                var copy = plan
                copy.languageMode = mode
                return copy
            }
            let appended = ShortsPlanner.appendNonOverlappingPlans(
                existingPlans: latest.shortsPlans ?? [],
                incomingPlans: incoming,
                excludedPlans: latest.shortsRejectedPlans ?? []
            )
            latest.shortsPlans = appended.plans
            latest.normalizeTranslationArchive()
            self.workflow.session = latest
            self.saveCurrentProject()
            let revision = McpProjectRevision.make(workflow: self.workflow)
            let change = self.mcpAuditStore.record(
                toolName: "generate_shorts_plans",
                requestID: nil,
                previousRevision: startingRevision,
                projectRevision: revision
            )
            let addedPlans = appended.addedIndexes.compactMap { appended.plans.indices.contains($0) ? appended.plans[$0] : nil }
            return [
                "addedPlans": addedPlans.enumerated().map { self.mcpShortsPlanDictionary($0.element, index: $0.offset, rejected: false) },
                "addedCount": addedPlans.count,
                "skippedOverlappingCount": appended.skippedOverlapping.count,
                "changeSetId": change.id,
                "projectRevision": revision,
            ]
        }
        return ["jobId": jobID, "status": "queued", "kind": "generate_shorts_plans"]
    }

    private func mcpResolveShortsPlan(_ rawID: Any?, rejected: Bool) throws -> (index: Int, plan: ShortsClipPlan) {
        guard let planID = mcpString(rawID), let session = workflow.session else {
            throw mcpError(-1, "NO_ACTIVE_PROJECT: planId is required")
        }
        let plans = rejected ? (session.shortsRejectedPlans ?? []) : (session.shortsPlans ?? [])
        guard let index = plans.firstIndex(where: { $0.id == planID }) else {
            throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown planId")
        }
        return (index, plans[index])
    }

    private func mcpCreateShortsPlan(arguments: [String: Any]) throws -> [String: Any] {
        guard var session = workflow.session else { throw mcpError(-1, "NO_ACTIVE_PROJECT: No project is open") }
        guard let start = mcpDouble(arguments["startSec"]),
              let end = mcpDouble(arguments["endSec"]),
              let title = mcpString(arguments["title"]), title.count <= 500 else {
            throw mcpError(-2, "startSec, endSec, and title are required")
        }
        let validation = ShortsPlanner.validateClip(startSec: start, endSec: end, minDurationSec: 10, maxDurationSec: 300)
        guard validation.ok, session.durationSec <= 0 || end <= session.durationSec else {
            throw mcpError(-2, validation.reason ?? "Clip range exceeds source duration")
        }
        var plan = ShortsClipPlan(
            start: ShortsPlanner.secondsToShortsTimestamp(start),
            end: ShortsPlanner.secondsToShortsTimestamp(end),
            title: title,
            summary: (arguments["summary"] as? String) ?? "",
            hook: (arguments["hook"] as? String) ?? "",
            category: (arguments["category"] as? String) ?? "clip",
            captionText: arguments["captionText"] as? String,
            languageMode: ShortsPlanLanguageMode(rawValue: mcpString(arguments["mode"]) ?? "source") ?? .source
        )
        plan.stableID = UUID().uuidString.lowercased()
        let appended = ShortsPlanner.appendNonOverlappingPlans(
            existingPlans: session.shortsPlans ?? [],
            incomingPlans: [plan],
            excludedPlans: session.shortsRejectedPlans ?? []
        )
        guard !appended.addedIndexes.isEmpty else { throw mcpError(-2, "Clip overlaps an active or rejected Shorts range") }
        session.shortsPlans = appended.plans
        workflow.session = session
        saveCurrentProject()
        return ["success": true, "plan": mcpShortsPlanDictionary(plan, index: appended.addedIndexes[0], rejected: false)]
    }

    private func mcpUpdateShortsPlan(arguments: [String: Any]) throws -> [String: Any] {
        let resolved = try mcpResolveShortsPlan(arguments["planId"], rejected: false)
        var session = try requireMcpSession()
        var plans = session.shortsPlans ?? []
        var plan = plans[resolved.index]
        let language = ShortsIdeaDisplayLanguage(rawValue: mcpString(arguments["language"]) ?? "source") ?? .source
        let title = arguments["title"] as? String
        let summary = arguments["summary"] as? String
        let hook = arguments["hook"] as? String
        let category = arguments["category"] as? String
        let caption = arguments["captionText"] as? String
        guard title != nil || summary != nil || hook != nil || category != nil || caption != nil else {
            throw mcpError(-2, "Provide at least one Shorts text field to update")
        }
        switch language {
        case .source:
            if let title { plan.sourceTitle = title; if plan.languageMode == .source { plan.title = title } }
            if let summary { plan.sourceSummary = summary; if plan.languageMode == .source { plan.summary = summary } }
            if let hook { plan.sourceHook = hook; if plan.languageMode == .source { plan.hook = hook } }
            if let category { plan.sourceCategory = category; if plan.languageMode == .source { plan.category = category } }
            if let caption { plan.sourceCaptionText = caption; if plan.languageMode == .source { plan.captionText = caption } }
        case .target:
            if let title { plan.targetTitle = title; plan.title = title }
            if let summary { plan.targetSummary = summary; plan.summary = summary }
            if let hook { plan.targetHook = hook; plan.hook = hook }
            if let category { plan.targetCategory = category; plan.category = category }
            if let caption { plan.targetCaptionText = caption; plan.captionText = caption }
        }
        plans[resolved.index] = plan
        session.shortsPlans = plans
        workflow.session = session
        saveCurrentProject()
        return ["success": true, "plan": mcpShortsPlanDictionary(plan, index: resolved.index, rejected: false)]
    }

    private func mcpUpdateShortsTiming(arguments: [String: Any]) throws -> [String: Any] {
        let resolved = try mcpResolveShortsPlan(arguments["planId"], rejected: false)
        guard let start = mcpDouble(arguments["startSec"]), let end = mcpDouble(arguments["endSec"]) else {
            throw mcpError(-2, "startSec and endSec are required")
        }
        var session = try requireMcpSession()
        let validation = ShortsPlanner.validateClip(startSec: start, endSec: end, minDurationSec: 10, maxDurationSec: 300)
        guard validation.ok, session.durationSec <= 0 || end <= session.durationSec else {
            throw mcpError(-2, validation.reason ?? "Clip range exceeds source duration")
        }
        var plans = session.shortsPlans ?? []
        let candidate = ShortsPlanner.replacingClipRange(
            plans[resolved.index],
            start: ShortsPlanner.secondsToShortsTimestamp(start),
            end: ShortsPlanner.secondsToShortsTimestamp(end)
        )
        let others = plans.enumerated().filter { $0.offset != resolved.index }.map(\.element)
        let checked = ShortsPlanner.appendNonOverlappingPlans(
            existingPlans: others,
            incomingPlans: [candidate],
            excludedPlans: session.shortsRejectedPlans ?? []
        )
        guard !checked.addedIndexes.isEmpty else { throw mcpError(-2, "Updated range overlaps another active or rejected plan") }
        plans[resolved.index] = candidate
        session.shortsPlans = plans
        workflow.session = session
        saveCurrentProject()
        return ["success": true, "plan": mcpShortsPlanDictionary(candidate, index: resolved.index, rejected: false)]
    }

    private func mcpRemoveShortsPlan(arguments: [String: Any]) throws -> [String: Any] {
        let resolved = try mcpResolveShortsPlan(arguments["planId"], rejected: false)
        let revision = McpProjectRevision.make(workflow: workflow)
        if arguments["dryRun"] as? Bool ?? true {
            let token = mcpConfirmationStore.issue(
                operation: "remove_shorts_plan",
                fingerprint: resolved.plan.id,
                projectRevision: revision
            )
            return [
                "dryRun": true,
                "plan": mcpShortsPlanDictionary(resolved.plan, index: resolved.index, rejected: false),
                "confirmationToken": token,
                "confirmationExpiresInSec": 120,
            ]
        }
        try consumeMcpConfirmation(
            arguments: arguments,
            operation: "remove_shorts_plan",
            fingerprint: resolved.plan.id,
            revision: revision
        )
        removeShortsPlan(at: resolved.index)
        return ["success": true, "planId": resolved.plan.id, "movedToRejected": true]
    }

    private func mcpRestoreShortsPlan(arguments: [String: Any]) throws -> [String: Any] {
        let resolved = try mcpResolveShortsPlan(arguments["planId"], rejected: true)
        var session = try requireMcpSession()
        var rejected = session.shortsRejectedPlans ?? []
        let remainingRejected = rejected.enumerated().filter { $0.offset != resolved.index }.map(\.element)
        let appended = ShortsPlanner.appendNonOverlappingPlans(
            existingPlans: session.shortsPlans ?? [],
            incomingPlans: [resolved.plan],
            excludedPlans: remainingRejected
        )
        guard !appended.addedIndexes.isEmpty else { throw mcpError(-2, "Rejected plan overlaps an active plan") }
        rejected.remove(at: resolved.index)
        session.shortsPlans = appended.plans
        session.shortsRejectedPlans = rejected
        workflow.session = session
        saveCurrentProject()
        return ["success": true, "plan": mcpShortsPlanDictionary(resolved.plan, index: appended.addedIndexes[0], rejected: false)]
    }

    private func startMcpShortsTranslationJob(arguments: [String: Any]) throws -> [String: Any] {
        let session = try requireMcpSession()
        guard let languageValue = mcpString(arguments["language"]) else { throw mcpError(-2, "language is required") }
        let language = TranslationArchive.displayLanguage(languageValue)
        guard TranslationArchive.isRealLanguage(language) else { throw mcpError(-2, "Provide a real target language") }
        let planIDs = Set((arguments["planIds"] as? [String]) ?? [])
        let allPlans = session.shortsPlans ?? []
        let selectedIndexes = allPlans.indices.filter { planIDs.isEmpty || planIDs.contains(allPlans[$0].id) }
        guard !selectedIndexes.isEmpty else { throw mcpError(-3, "No matching Shorts plans") }
        let route: ShortsPlanRoute
        if let cloud = activeCloudTranslationProvider(for: session) { route = .cloud(cloud) }
        else if let model = activeTranslationModel(for: session) { route = .mlx(model) }
        else { throw mcpError(-10, "PROVIDER_NOT_READY: Configure a cloud provider or MLX model") }
        let startingRevision = McpProjectRevision.make(workflow: workflow)
        let jobID = mcpJobManager.start(kind: "translate_shorts_plans", message: "Translating Shorts metadata to \(language)") { [weak self] reporter in
            guard let self else { throw NSError(domain: "VaniScriptMCP", code: -1) }
            for (position, index) in selectedIndexes.enumerated() {
                try reporter.checkCancellation()
                guard var latest = self.workflow.session,
                      var plans = latest.shortsPlans,
                      plans.indices.contains(index) else { throw self.mcpError(-6, "Project changed during Shorts translation") }
                let translated: ShortsClipTranslation
                switch route {
                case let .cloud(provider):
                    translated = try await self.shortsCloudEngine.translateShortsPlan(plans[index], targetLanguage: language, provider: provider)
                case let .mlx(model):
                    translated = try await self.shortsMLXEngine.translateShortsPlan(plans[index], targetLanguage: language, model: model)
                }
                plans[index].setTranslation(translated)
                latest.shortsPlans = plans
                latest.registerTranslationLanguage(language)
                self.workflow.session = latest
                self.saveCurrentProject()
                reporter.update(
                    progress: Double(position + 1) / Double(selectedIndexes.count),
                    stage: "Translated plan \(position + 1) / \(selectedIndexes.count)"
                )
            }
            let revision = McpProjectRevision.make(workflow: self.workflow)
            let change = self.mcpAuditStore.record(
                toolName: "translate_shorts_plans",
                requestID: nil,
                previousRevision: startingRevision,
                projectRevision: revision
            )
            return [
                "language": language,
                "translatedPlanIds": selectedIndexes.compactMap { self.workflow.session?.shortsPlans?[$0].id },
                "changeSetId": change.id,
                "projectRevision": revision,
            ]
        }
        return ["jobId": jobID, "status": "queued", "kind": "translate_shorts_plans", "planCount": selectedIndexes.count]
    }

    private func mcpValidateShortsPlan(_ plan: ShortsClipPlan) -> [String: Any] {
        var issues: [[String: Any]] = []
        let start = ShortsPlanner.parseTimestampToSeconds(plan.start)
        let end = ShortsPlanner.parseTimestampToSeconds(plan.end)
        let validation = ShortsPlanner.validateClip(startSec: start, endSec: end, minDurationSec: 10, maxDurationSec: 300)
        if !validation.ok {
            issues.append(["severity": "error", "code": "INVALID_DURATION", "message": validation.reason ?? "Invalid duration"])
        }
        if let duration = workflow.session?.durationSec, duration > 0, end > duration {
            issues.append(["severity": "error", "code": "OUTSIDE_SOURCE", "message": "Plan ends after source media."])
        }
        if plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(["severity": "error", "code": "EMPTY_TITLE", "message": "Title is empty."])
        }
        if (plan.captionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(["severity": "warning", "code": "EMPTY_CAPTIONS", "message": "Caption text is empty."])
        }
        for (index, cut) in (plan.timelineCuts ?? []).enumerated() {
            if cut.startSec < 0 || cut.endSec <= cut.startSec || cut.endSec > max(0, end - start) {
                issues.append(["severity": "error", "code": "INVALID_CUT", "entityId": "cut-\(index)", "message": "Timeline cut is outside the clip."])
            }
        }
        return [
            "valid": !issues.contains { $0["severity"] as? String == "error" },
            "planId": plan.id,
            "durationSec": validation.durationSec,
            "issues": issues,
        ]
    }

    private func mcpShortsPlanDictionary(_ plan: ShortsClipPlan, index: Int, rejected: Bool) -> [String: Any] {
        [
            "id": plan.id,
            "displayNumber": index + 1,
            "arrayIndex": index,
            "rejected": rejected,
            "start": plan.start,
            "end": plan.end,
            "startSec": ShortsPlanner.parseTimestampToSeconds(plan.start),
            "endSec": ShortsPlanner.parseTimestampToSeconds(plan.end),
            "title": plan.title,
            "summary": plan.summary,
            "hook": plan.hook,
            "category": plan.category ?? "",
            "captionText": plan.captionText ?? "",
            "languageMode": plan.languageMode?.rawValue ?? "",
            "translationLanguages": plan.translationsByLanguage?.values.map(\.language).sorted() ?? [],
            "visualEditor": [
                "cutCount": plan.timelineCuts?.count ?? 0,
                "sourceSubtitleCount": plan.sourceAlignment?.count ?? 0,
                "targetSubtitleCount": plan.targetAlignment?.count ?? 0,
                "sourceTextTrackCount": plan.sourceTextTracks?.count ?? 0,
                "targetTextTrackCount": plan.targetTextTracks?.count ?? 0,
                "sourceAudioTrackCount": plan.sourceAudioTracks?.count ?? 0,
                "targetAudioTrackCount": plan.targetAudioTracks?.count ?? 0,
                "syncEnabled": plan.syncEnabled ?? true,
            ],
        ]
    }

    // MARK: - MCP Visual Editor

    private func mcpVisualLanguage(_ arguments: [String: Any]) -> ShortsIdeaDisplayLanguage {
        ShortsIdeaDisplayLanguage(rawValue: mcpString(arguments["language"]) ?? "source") ?? .source
    }

    private func mcpRequireDestructivePermission(_ permissions: McpPermissionSet) throws {
        guard permissions.allows(.destructive) else {
            throw mcpError(-5, "DESTRUCTIVE_PERMISSION_REQUIRED: Enable Destructive Actions in Settings > Agents")
        }
    }

    private func mcpMutateVisualPlan(
        _ rawPlanID: Any?,
        mutate: (inout ShortsClipPlan) throws -> Void
    ) throws -> (index: Int, plan: ShortsClipPlan) {
        let resolved = try mcpResolveShortsPlan(rawPlanID, rejected: false)
        var updated = resolved.plan
        try mutate(&updated)
        updateShortsPlan(at: resolved.index) { $0 = updated }
        refreshMcpVisualEditorDraft(index: resolved.index)
        return (resolved.index, updated)
    }

    private func refreshMcpVisualEditorDraft(index: Int) {
        guard let draft = visualEditorDraft, draft.index == index,
              let session = workflow.session,
              let plans = session.shortsPlans,
              plans.indices.contains(index) else { return }
        let plan = plans[index]
        visualEditorDraft = VisualClipEditorDraft(index: index, plan: plan, language: draft.language, session: session)
    }

    private func mcpVisualEditorState(plan: ShortsClipPlan, index: Int) -> [String: Any] {
        let duration = ShortsVisualEditorStateBuilder.clipDuration(plan)
        let sourceSegments = ShortsVisualEditorStateBuilder.segments(for: plan, language: .source)
        let targetSegments = ShortsVisualEditorStateBuilder.segments(for: plan, language: .target)
        return [
            "plan": mcpShortsPlanDictionary(plan, index: index, rejected: false),
            "clipDurationSec": duration,
            "timeline": [
                "cuts": (plan.timelineCuts ?? []).map { ["cutId": $0.id, "startSec": $0.startSec, "endSec": $0.endSec] },
                "trim": ["trimStartSec": plan.timelineTrim?.trimStartSec ?? 0, "trimEndSec": plan.timelineTrim?.trimEndSec ?? 0],
            ],
            "source": mcpVisualLanguageState(
                segments: sourceSegments,
                keyframes: plan.sourceFrameKeyframes ?? mcpBaseKeyframes(plan, language: .source),
                logo: plan.sourceLogo ?? plan.logo,
                textTracks: plan.sourceTextTracks ?? plan.textTracks ?? [],
                audioTracks: plan.sourceAudioTracks ?? plan.audioTracks ?? [],
                intro: plan.sourceIntro ?? plan.intro,
                outro: plan.sourceOutro ?? plan.outro
            ),
            "target": mcpVisualLanguageState(
                segments: targetSegments,
                keyframes: plan.targetFrameKeyframes ?? mcpBaseKeyframes(plan, language: .target),
                logo: plan.targetLogo ?? plan.logo,
                textTracks: plan.targetTextTracks ?? plan.textTracks ?? [],
                audioTracks: plan.targetAudioTracks ?? plan.audioTracks ?? [],
                intro: plan.targetIntro ?? plan.intro,
                outro: plan.targetOutro ?? plan.outro
            ),
            "background": mcpBackgroundDictionary(plan.backgroundSettings ?? .universalDefault),
            "subtitleStyle": mcpSubtitleStyleDictionary(plan.subtitleStyle ?? .orangeImpact),
            "syncEnabled": plan.syncEnabled ?? (plan.languageMode == .bilingual),
            "assetPolicy": "MCP never accepts source paths. Add image, video, or audio assets through the Visual Editor file picker, then address the returned existing asset ID here.",
        ]
    }

    private func mcpVisualLanguageState(
        segments: [AlignedSubtitleSegment],
        keyframes: [FrameKeyframe],
        logo: LogoOverlaySettings?,
        textTracks: [TextOverlayTrack],
        audioTracks: [ExtraAudioTrack],
        intro: IntroOutroOverlaySettings?,
        outro: IntroOutroOverlaySettings?
    ) -> [String: Any] {
        [
            "subtitleSegments": segments.map { segment in
                ["segmentId": segment.id, "startSec": segment.start, "endSec": segment.end, "text": segment.text]
            },
            "frameKeyframes": keyframes.map { frame in
                ["keyframeId": frame.id, "timeSec": frame.time, "x": frame.x, "y": frame.y, "zoom": frame.zoom, "backgroundColor": frame.backgroundColor ?? ""]
            },
            "logo": mcpLogoDictionary(logo),
            "textTracks": textTracks.map(mcpTextTrackDictionary),
            "audioTracks": audioTracks.map(mcpAudioTrackDictionary),
            "intro": mcpOverlayDictionary(intro),
            "outro": mcpOverlayDictionary(outro),
        ]
    }

    private func mcpBaseKeyframes(_ plan: ShortsClipPlan, language: ShortsIdeaDisplayLanguage) -> [FrameKeyframe] {
        [FrameKeyframe(
            id: "frame_\(language.rawValue)_base",
            time: 0,
            x: 0,
            y: 0,
            zoom: 1,
            backgroundColor: plan.backgroundSettings?.solidColor ?? "#000000"
        )]
    }

    private func mcpLogoDictionary(_ logo: LogoOverlaySettings?) -> [String: Any] {
        guard let logo else { return ["present": false] }
        return ["present": true, "logoId": logo.id, "name": logo.name ?? "", "size": logo.size, "opacity": logo.opacity, "position": logo.position ?? "", "hidden": logo.hidden ?? false]
    }

    private func mcpOverlayDictionary(_ overlay: IntroOutroOverlaySettings?) -> [String: Any] {
        guard let overlay else { return ["present": false] }
        return ["present": true, "overlayId": overlay.id, "name": overlay.name ?? "", "duration": overlay.duration, "x": overlay.x, "y": overlay.y, "scale": overlay.scale, "animation": overlay.animation, "hidden": overlay.hidden ?? false, "speed": overlay.speed ?? 1, "transitionSec": overlay.transitionSec ?? 0]
    }

    private func mcpTextTrackDictionary(_ track: TextOverlayTrack) -> [String: Any] {
        [
            "trackId": track.id,
            "name": track.name,
            "hidden": track.hidden ?? false,
            "muted": track.muted ?? false,
            "blocks": track.blocks.map { ["blockId": $0.id, "startSec": $0.startSec, "endSec": $0.endSec, "text": $0.text, "hidden": $0.hidden ?? false] },
        ]
    }

    private func mcpAudioTrackDictionary(_ track: ExtraAudioTrack) -> [String: Any] {
        [
            "audioTrackId": track.id,
            "name": track.name,
            "startSec": track.startSec,
            "trimStartSec": track.trimStartSec,
            "trimEndSec": track.trimEndSec,
            "volume": track.volume,
            "fadeInSec": track.fadeInSec,
            "fadeOutSec": track.fadeOutSec,
            "muted": track.muted ?? false,
            "assetDurationSec": track.assetDuration ?? 0,
        ]
    }

    private func mcpBackgroundDictionary(_ value: ShortsBackgroundSettings) -> [String: Any] {
        [
            "solidEnabled": value.solidEnabled, "solidColor": value.solidColor,
            "blurEnabled": value.blurEnabled, "blurStrength": value.blurStrength, "blurScale": value.blurScale, "blurPanX": value.blurPanX ?? 0,
            "gradientEnabled": value.gradientEnabled, "gradientType": value.gradientType, "gradientColorA": value.gradientColorA, "gradientColorB": value.gradientColorB, "gradientAngle": value.gradientAngle, "gradientOpacity": value.gradientOpacity,
            "featherEnabled": value.featherEnabled, "featherTop": value.featherTop, "featherBottom": value.featherBottom, "featherLeft": value.featherLeft, "featherRight": value.featherRight,
            "frameGuideColor": value.frameGuideColor, "frameGuideOpacity": value.frameGuideOpacity, "frameGuideBorderWidth": value.frameGuideBorderWidth, "frameGuideBlur": value.frameGuideBlur, "frameGuideBorderOpacity": value.frameGuideBorderOpacity,
        ]
    }

    private func mcpSubtitleStyleDictionary(_ value: ShortsSubtitleStyle) -> [String: Any] {
        ["fontFamily": value.fontFamily, "fontSize": value.fontSize, "bold": value.bold, "textTransform": value.textTransform.rawValue, "textColor": value.textColor, "boxColor": value.boxColor, "boxOpacity": value.boxOpacity, "boxWidth": value.boxWidth, "boxHeight": value.boxHeight, "outline": value.outline, "shadow": value.shadow]
    }

    private func mcpManageTimelineCut(arguments: [String: Any], permissions: McpPermissionSet) throws -> [String: Any] {
        guard let action = mcpString(arguments["action"]) else { throw mcpError(-2, "action is required") }
        let updated = try mcpMutateVisualPlan(arguments["planId"]) { plan in
            let duration = ShortsVisualEditorStateBuilder.clipDuration(plan)
            var cuts = plan.timelineCuts ?? []
            switch action {
            case "create":
                let cut = try mcpTimelineCut(arguments: arguments, duration: duration)
                guard !cuts.contains(where: { max($0.startSec, cut.startSec) < min($0.endSec, cut.endSec) }) else {
                    throw mcpError(-2, "VALIDATION_FAILED: Timeline cuts may not overlap")
                }
                cuts.append(cut)
            case "update":
                guard let cutID = mcpString(arguments["cutId"]), let index = cuts.firstIndex(where: { $0.id == cutID }) else {
                    throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown cutId")
                }
                var replacement = try mcpTimelineCut(arguments: arguments, duration: duration)
                replacement.stableID = cuts[index].stableID ?? cutID
                let otherCuts = cuts.enumerated().filter { $0.offset != index }.map(\.element)
                guard !otherCuts.contains(where: { max($0.startSec, replacement.startSec) < min($0.endSec, replacement.endSec) }) else {
                    throw mcpError(-2, "VALIDATION_FAILED: Timeline cuts may not overlap")
                }
                cuts[index] = replacement
            case "delete":
                try mcpRequireDestructivePermission(permissions)
                guard let cutID = mcpString(arguments["cutId"]), let index = cuts.firstIndex(where: { $0.id == cutID }) else {
                    throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown cutId")
                }
                cuts.remove(at: index)
            default:
                throw mcpError(-2, "action must be create, update, or delete")
            }
            plan.timelineCuts = cuts.sorted { $0.startSec < $1.startSec }
        }
        return ["success": true, "planId": updated.plan.id, "cuts": (updated.plan.timelineCuts ?? []).map { ["cutId": $0.id, "startSec": $0.startSec, "endSec": $0.endSec] }]
    }

    private func mcpTimelineCut(arguments: [String: Any], duration: Double) throws -> TimelineCut {
        guard let start = mcpDouble(arguments["startSec"]), let end = mcpDouble(arguments["endSec"]), start >= 0, end > start, end <= duration else {
            throw mcpError(-2, "VALIDATION_FAILED: startSec and endSec must define a cut inside the clip")
        }
        return TimelineCut(stableID: UUID().uuidString.lowercased(), startSec: start, endSec: end)
    }

    private func mcpManageSubtitleSegment(arguments: [String: Any], permissions: McpPermissionSet) throws -> [String: Any] {
        guard let action = mcpString(arguments["action"]) else { throw mcpError(-2, "action is required") }
        let language = mcpVisualLanguage(arguments)
        let updated = try mcpMutateVisualPlan(arguments["planId"]) { plan in
            let duration = ShortsVisualEditorStateBuilder.clipDuration(plan)
            var segments = mcpSegments(for: plan, language: language)
            switch action {
            case "create":
                guard let text = mcpString(arguments["text"]), text.count <= 4_000,
                      let start = mcpDouble(arguments["startSec"]), let end = mcpDouble(arguments["endSec"]),
                      start >= 0, end > start, end <= duration else {
                    throw mcpError(-2, "VALIDATION_FAILED: text, startSec, and endSec must define a segment inside the clip")
                }
                let segment = AlignedSubtitleSegment(id: UUID().uuidString.lowercased(), start: start, end: end, text: text)
                guard !segments.contains(where: { max($0.start, segment.start) < min($0.end, segment.end) }) else {
                    throw mcpError(-2, "VALIDATION_FAILED: Subtitle segments may not overlap")
                }
                segments.append(AlignedSubtitleSegment(id: segment.id, start: start, end: end, text: text, words: ShortsVisualEditorStateBuilder.inferredWords(for: segment)))
            case "update":
                guard let segmentID = mcpString(arguments["segmentId"]), let index = segments.firstIndex(where: { $0.id == segmentID }) else {
                    throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown segmentId")
                }
                let start = mcpDouble(arguments["startSec"]) ?? segments[index].start
                let end = mcpDouble(arguments["endSec"]) ?? segments[index].end
                let text = mcpString(arguments["text"]) ?? segments[index].text
                guard text.count <= 4_000, start >= 0, end > start, end <= duration else {
                    throw mcpError(-2, "VALIDATION_FAILED: Invalid subtitle segment")
                }
                let other = segments.enumerated().filter { $0.offset != index }.map(\.element)
                guard !other.contains(where: { max($0.start, start) < min($0.end, end) }) else {
                    throw mcpError(-2, "VALIDATION_FAILED: Subtitle segments may not overlap")
                }
                let base = AlignedSubtitleSegment(id: segmentID, start: start, end: end, text: text)
                segments[index] = AlignedSubtitleSegment(id: base.id, start: base.start, end: base.end, text: base.text, words: ShortsVisualEditorStateBuilder.inferredWords(for: base))
            case "split":
                guard let segmentID = mcpString(arguments["segmentId"]), let index = segments.firstIndex(where: { $0.id == segmentID }),
                      let split = mcpDouble(arguments["splitSec"]), split > segments[index].start + 0.25, split < segments[index].end - 0.25 else {
                    throw mcpError(-2, "VALIDATION_FAILED: splitSec must lie inside an existing segment")
                }
                let original = segments.remove(at: index)
                let words = original.text.split(whereSeparator: \.isWhitespace).map(String.init)
                let pivot = max(1, words.count / 2)
                let leftText = words.prefix(pivot).joined(separator: " ")
                let rightText = words.dropFirst(pivot).joined(separator: " ")
                let left = AlignedSubtitleSegment(id: original.id, start: original.start, end: split, text: leftText)
                let right = AlignedSubtitleSegment(id: UUID().uuidString.lowercased(), start: split, end: original.end, text: rightText.isEmpty ? original.text : rightText)
                segments += [AlignedSubtitleSegment(id: left.id, start: left.start, end: left.end, text: left.text, words: ShortsVisualEditorStateBuilder.inferredWords(for: left)), AlignedSubtitleSegment(id: right.id, start: right.start, end: right.end, text: right.text, words: ShortsVisualEditorStateBuilder.inferredWords(for: right))]
            case "merge":
                guard let firstID = mcpString(arguments["segmentId"]), let secondID = mcpString(arguments["secondSegmentId"]),
                      let firstIndex = segments.firstIndex(where: { $0.id == firstID }), let secondIndex = segments.firstIndex(where: { $0.id == secondID }), firstIndex != secondIndex else {
                    throw mcpError(-2, "VALIDATION_FAILED: segmentId and secondSegmentId must identify two segments")
                }
                let first = segments[firstIndex]
                let second = segments[secondIndex]
                let low = min(first.start, second.start)
                let high = max(first.end, second.end)
                let merged = AlignedSubtitleSegment(id: first.start <= second.start ? first.id : second.id, start: low, end: high, text: [first.text, second.text].joined(separator: " "))
                segments.removeAll { $0.id == firstID || $0.id == secondID }
                segments.append(AlignedSubtitleSegment(id: merged.id, start: merged.start, end: merged.end, text: merged.text, words: ShortsVisualEditorStateBuilder.inferredWords(for: merged)))
            case "delete":
                try mcpRequireDestructivePermission(permissions)
                guard let segmentID = mcpString(arguments["segmentId"]), segments.contains(where: { $0.id == segmentID }) else {
                    throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown segmentId")
                }
                segments.removeAll { $0.id == segmentID }
            default:
                throw mcpError(-2, "Unsupported subtitle action")
            }
            mcpSetSegments(segments.sorted { $0.start < $1.start }, on: &plan, language: language)
        }
        return ["success": true, "planId": updated.plan.id, "language": language.rawValue, "subtitleSegments": mcpSegments(for: updated.plan, language: language).map { ["segmentId": $0.id, "startSec": $0.start, "endSec": $0.end, "text": $0.text] }]
    }

    private func mcpSegments(for plan: ShortsClipPlan, language: ShortsIdeaDisplayLanguage) -> [AlignedSubtitleSegment] {
        ShortsVisualEditorStateBuilder.segments(for: plan, language: language)
    }

    private func mcpSetSegments(_ segments: [AlignedSubtitleSegment], on plan: inout ShortsClipPlan, language: ShortsIdeaDisplayLanguage) {
        switch language {
        case .source: plan.sourceAlignment = segments
        case .target: plan.targetAlignment = segments
        }
    }

    private func mcpClipSourceURL() throws -> URL {
        guard let session = workflow.session,
              let sourcePath = session.sourceFile, !sourcePath.isEmpty,
              FileManager.default.fileExists(atPath: sourcePath) else {
            throw mcpError(-1, "NO_SOURCE_MEDIA: Active project has no local source media file for audio analysis")
        }
        return URL(fileURLWithPath: sourcePath)
    }

    private func mcpClipAbsoluteRange(_ plan: ShortsClipPlan) throws -> (startSec: Double, endSec: Double, durationSec: Double) {
        let start = ShortsPlanner.parseTimestampToSeconds(plan.start)
        let end = ShortsPlanner.parseTimestampToSeconds(plan.end)
        guard end > start else {
            throw mcpError(-2, "VALIDATION_FAILED: plan start/end must define a positive clip duration")
        }
        return (start, end, end - start)
    }

    private func mcpSpeechAnalysisParams(arguments: [String: Any]) -> (thresholdDb: Double, minSilenceMs: Int, padSec: Double) {
        let threshold = mcpDouble(arguments["silenceThresholdDb"]) ?? Double(workflow.settings.silenceThreshDb)
        let minSilence = McpToolArguments.wholeNumber(arguments["minSilenceMs"]) ?? workflow.settings.minSilenceMs
        let pad = mcpDouble(arguments["padSec"]) ?? SubtitleSpeechAligner.defaultPadSec
        return (
            thresholdDb: min(0, max(-80, threshold)),
            minSilenceMs: min(10_000, max(0, minSilence)),
            padSec: min(0.5, max(0, pad))
        )
    }

    private func mcpAnalyzeClipSpeechRegions(arguments: [String: Any]) async throws -> [String: Any] {
        let resolved = try mcpResolveShortsPlan(arguments["planId"], rejected: false)
        let range = try mcpClipAbsoluteRange(resolved.plan)
        let sourceURL = try mcpClipSourceURL()
        let params = mcpSpeechAnalysisParams(arguments: arguments)

        let profile = try await SmartAudioAnalyzer.energyProfile(
            sourceURL: sourceURL,
            startSec: range.startSec,
            endSec: range.endSec
        )
        let speech = SubtitleSpeechAligner.speechRegions(
            profile: profile,
            clipDurationSec: range.durationSec,
            thresholdDb: params.thresholdDb,
            minSilenceMs: params.minSilenceMs
        )
        let silenceMs = SmartSlicePlanner.silenceRegions(
            profile: profile,
            thresholdDb: params.thresholdDb,
            minSilenceMs: params.minSilenceMs
        )

        return [
            "success": true,
            "planId": resolved.plan.id,
            "clipStartSec": range.startSec,
            "clipEndSec": range.endSec,
            "clipDurationSec": range.durationSec,
            "silenceThresholdDb": params.thresholdDb,
            "minSilenceMs": params.minSilenceMs,
            "energyWindowCount": profile.count,
            "speechRegions": speech.map { ["startSec": $0.startSec, "endSec": $0.endSec] },
            "silenceRegions": silenceMs.map {
                ["startSec": Double($0.startMs) / 1_000, "endSec": Double($0.endMs) / 1_000]
            },
        ]
    }

    private func mcpSnapSubtitleSegmentsToSpeech(arguments: [String: Any]) async throws -> [String: Any] {
        let resolved = try mcpResolveShortsPlan(arguments["planId"], rejected: false)
        let range = try mcpClipAbsoluteRange(resolved.plan)
        let sourceURL = try mcpClipSourceURL()
        let params = mcpSpeechAnalysisParams(arguments: arguments)
        let preview = (arguments["preview"] as? Bool) ?? false

        let languageToken = (mcpString(arguments["language"]) ?? "both").lowercased()
        let languages: [ShortsIdeaDisplayLanguage]
        switch languageToken {
        case "source": languages = [.source]
        case "target": languages = [.target]
        case "both", "": languages = [.source, .target]
        default:
            throw mcpError(-2, "VALIDATION_FAILED: language must be source, target, or both")
        }

        let profile = try await SmartAudioAnalyzer.energyProfile(
            sourceURL: sourceURL,
            startSec: range.startSec,
            endSec: range.endSec
        )
        let speech = SubtitleSpeechAligner.speechRegions(
            profile: profile,
            clipDurationSec: range.durationSec,
            thresholdDb: params.thresholdDb,
            minSilenceMs: params.minSilenceMs
        )

        var languageResults: [[String: Any]] = []
        var anyChanged = false

        if preview {
            for language in languages {
                let segments = mcpSegments(for: resolved.plan, language: language)
                let snap = SubtitleSpeechAligner.snapSegmentsToSpeech(
                    segments: segments,
                    speechRegions: speech,
                    clipDurationSec: range.durationSec,
                    padSec: params.padSec
                )
                let changedCount = snap.changes.filter(\.changed).count
                anyChanged = anyChanged || changedCount > 0
                languageResults.append([
                    "language": language.rawValue,
                    "preview": true,
                    "changedCount": changedCount,
                    "segmentCount": snap.segments.count,
                    "changes": snap.changes.map(mcpSpeechSnapChangeDictionary),
                    "subtitleSegments": snap.segments.map {
                        ["segmentId": $0.id, "startSec": $0.start, "endSec": $0.end, "text": $0.text]
                    },
                ])
            }
        } else {
            let updated = try mcpMutateVisualPlan(arguments["planId"]) { plan in
                for language in languages {
                    let segments = mcpSegments(for: plan, language: language)
                    let snap = SubtitleSpeechAligner.snapSegmentsToSpeech(
                        segments: segments,
                        speechRegions: speech,
                        clipDurationSec: range.durationSec,
                        padSec: params.padSec
                    )
                    let changedCount = snap.changes.filter(\.changed).count
                    anyChanged = anyChanged || changedCount > 0
                    mcpSetSegments(snap.segments, on: &plan, language: language)
                    languageResults.append([
                        "language": language.rawValue,
                        "preview": false,
                        "changedCount": changedCount,
                        "segmentCount": snap.segments.count,
                        "changes": snap.changes.map(mcpSpeechSnapChangeDictionary),
                        "subtitleSegments": snap.segments.map {
                            ["segmentId": $0.id, "startSec": $0.start, "endSec": $0.end, "text": $0.text]
                        },
                    ])
                }
            }
            saveCurrentProject()
            languageResults = languageResults.map { row in
                var copy = row
                copy["planId"] = updated.plan.id
                return copy
            }
        }

        return [
            "success": true,
            "planId": resolved.plan.id,
            "preview": preview,
            "applied": !preview,
            "anyChanged": anyChanged,
            "silenceThresholdDb": params.thresholdDb,
            "minSilenceMs": params.minSilenceMs,
            "padSec": params.padSec,
            "speechRegions": speech.map { ["startSec": $0.startSec, "endSec": $0.endSec] },
            "languages": languageResults,
            "message": preview
                ? "Preview only — call again with preview=false to apply."
                : (anyChanged
                    ? "Subtitle segments snapped to speech. Open or refresh Visual Editor if the draft was already open."
                    : "No segment bounds changed."),
        ]
    }

    private func mcpSpeechSnapChangeDictionary(_ change: SubtitleSpeechSnapChange) -> [String: Any] {
        [
            "segmentId": change.segmentId,
            "text": change.text,
            "oldStartSec": change.oldStartSec,
            "oldEndSec": change.oldEndSec,
            "newStartSec": change.newStartSec,
            "newEndSec": change.newEndSec,
            "status": change.status,
            "changed": change.changed,
        ]
    }

    private func mcpSetFrameKeyframes(arguments: [String: Any]) throws -> [String: Any] {
        guard let rawFrames = arguments["keyframes"] as? [Any], !rawFrames.isEmpty, rawFrames.count <= 120 else {
            throw mcpError(-2, "keyframes must contain 1 to 120 objects")
        }
        let language = mcpVisualLanguage(arguments)
        let updated = try mcpMutateVisualPlan(arguments["planId"]) { plan in
            let duration = ShortsVisualEditorStateBuilder.clipDuration(plan)
            let frames = try rawFrames.map { raw -> FrameKeyframe in
                guard let item = raw as? [String: Any],
                      let time = mcpDouble(item["timeSec"] ?? item["time"]), time >= 0, time <= duration,
                      let x = mcpDouble(item["x"]), (-100...100).contains(x),
                      let y = mcpDouble(item["y"]), (-100...100).contains(y),
                      let zoom = mcpDouble(item["zoom"]), (0.1...5).contains(zoom) else {
                    throw mcpError(-2, "VALIDATION_FAILED: Each keyframe needs bounded timeSec, x, y, and zoom")
                }
                let color = try mcpOptionalHexColor(item["backgroundColor"])
                return FrameKeyframe(id: mcpString(item["keyframeId"] ?? item["id"]) ?? UUID().uuidString.lowercased(), time: time, x: x, y: y, zoom: zoom, backgroundColor: color)
            }.sorted { $0.time < $1.time }
            guard Set(frames.map(\.id)).count == frames.count else {
                throw mcpError(-2, "VALIDATION_FAILED: keyframe IDs must be unique")
            }
            switch language {
            case .source: plan.sourceFrameKeyframes = frames
            case .target: plan.targetFrameKeyframes = frames
            }
        }
        let frames = language == .source ? updated.plan.sourceFrameKeyframes : updated.plan.targetFrameKeyframes
        return ["success": true, "planId": updated.plan.id, "language": language.rawValue, "frameKeyframes": (frames ?? []).map { ["keyframeId": $0.id, "timeSec": $0.time, "x": $0.x, "y": $0.y, "zoom": $0.zoom, "backgroundColor": $0.backgroundColor ?? ""] }]
    }

    private func mcpClearFrameKeyframes(arguments: [String: Any]) throws -> [String: Any] {
        let language = mcpVisualLanguage(arguments)
        let updated = try mcpMutateVisualPlan(arguments["planId"]) { plan in
            let base = mcpBaseKeyframes(plan, language: language)
            switch language {
            case .source: plan.sourceFrameKeyframes = base
            case .target: plan.targetFrameKeyframes = base
            }
        }
        return ["success": true, "planId": updated.plan.id, "language": language.rawValue, "message": "Frame keyframes reset to neutral base"]
    }

    private func mcpUpdateVisualBackground(arguments: [String: Any]) throws -> [String: Any] {
        guard let patch = arguments["patch"] as? [String: Any], !patch.isEmpty else {
            throw mcpError(-2, "patch must be a non-empty object")
        }
        let updated = try mcpMutateVisualPlan(arguments["planId"]) { plan in
            var background = plan.backgroundSettings ?? .universalDefault
            for (key, value) in patch {
                switch key {
                case "solidEnabled": background.solidEnabled = try mcpRequiredBool(value, key)
                case "solidColor": background.solidColor = try mcpRequiredHexColor(value, key)
                case "blurEnabled": background.blurEnabled = try mcpRequiredBool(value, key)
                case "blurStrength": background.blurStrength = try mcpBoundedNumber(value, key, range: 0...100)
                case "blurScale": background.blurScale = try mcpBoundedNumber(value, key, range: 0.1...4)
                case "blurPanX": background.blurPanX = try mcpBoundedNumber(value, key, range: -100...100)
                case "gradientEnabled": background.gradientEnabled = try mcpRequiredBool(value, key)
                case "gradientType":
                    guard let type = mcpString(value), ["linear", "radial"].contains(type) else { throw mcpError(-2, "gradientType must be linear or radial") }
                    background.gradientType = type
                case "gradientColorA": background.gradientColorA = try mcpRequiredHexColor(value, key)
                case "gradientColorB": background.gradientColorB = try mcpRequiredHexColor(value, key)
                case "gradientAngle": background.gradientAngle = try mcpBoundedNumber(value, key, range: 0...360)
                case "gradientOpacity": background.gradientOpacity = try mcpBoundedNumber(value, key, range: 0...1)
                case "featherEnabled": background.featherEnabled = try mcpRequiredBool(value, key)
                case "featherTop": background.featherTop = try mcpBoundedNumber(value, key, range: 0...100)
                case "featherBottom": background.featherBottom = try mcpBoundedNumber(value, key, range: 0...100)
                case "featherLeft": background.featherLeft = try mcpBoundedNumber(value, key, range: 0...100)
                case "featherRight": background.featherRight = try mcpBoundedNumber(value, key, range: 0...100)
                case "frameGuideColor": background.frameGuideColor = try mcpRequiredHexColor(value, key)
                case "frameGuideOpacity": background.frameGuideOpacity = try mcpBoundedNumber(value, key, range: 0...1)
                case "frameGuideBorderWidth": background.frameGuideBorderWidth = try mcpBoundedNumber(value, key, range: 0...20)
                case "frameGuideBlur": background.frameGuideBlur = try mcpBoundedNumber(value, key, range: 0...100)
                case "frameGuideBorderOpacity": background.frameGuideBorderOpacity = try mcpBoundedNumber(value, key, range: 0...1)
                default: throw mcpError(-2, "Unsupported background field: \(key)")
                }
            }
            plan.backgroundSettings = background
        }
        return ["success": true, "planId": updated.plan.id, "background": mcpBackgroundDictionary(updated.plan.backgroundSettings ?? .universalDefault)]
    }

    private func mcpUpdateVisualSubtitleStyle(arguments: [String: Any]) throws -> [String: Any] {
        guard let patch = arguments["patch"] as? [String: Any], !patch.isEmpty else {
            throw mcpError(-2, "patch must be a non-empty object")
        }
        let updated = try mcpMutateVisualPlan(arguments["planId"]) { plan in
            var style = plan.subtitleStyle ?? .orangeImpact
            for (key, value) in patch {
                switch key {
                case "fontFamily":
                    guard let font = mcpString(value), font.count <= 100 else { throw mcpError(-2, "fontFamily must be at most 100 characters") }
                    style.fontFamily = font
                case "fontSize": style.fontSize = try mcpBoundedNumber(value, key, range: 12...240)
                case "bold": style.bold = try mcpRequiredBool(value, key)
                case "textTransform":
                    guard let transform = mcpString(value), let parsed = ShortsTextTransform(rawValue: transform) else { throw mcpError(-2, "textTransform must be none, uppercase, or title") }
                    style.textTransform = parsed
                case "textColor": style.textColor = try mcpRequiredHexColor(value, key)
                case "boxColor": style.boxColor = try mcpRequiredHexColor(value, key)
                case "boxOpacity": style.boxOpacity = try mcpBoundedNumber(value, key, range: 0...1)
                case "boxWidth": style.boxWidth = try mcpBoundedNumber(value, key, range: 1...100)
                case "boxHeight": style.boxHeight = try mcpBoundedNumber(value, key, range: 0...100)
                case "edgeBlur": style.edgeBlur = try mcpBoundedNumber(value, key, range: 0...100)
                case "letterSpacing": style.letterSpacing = try mcpBoundedNumber(value, key, range: -20...50)
                case "lineSpacing": style.lineSpacing = try mcpBoundedNumber(value, key, range: 0.5...5)
                case "edgeSoftness": style.edgeSoftness = try mcpBoundedNumber(value, key, range: 0...1)
                case "outline": style.outline = try mcpBoundedNumber(value, key, range: 0...30)
                case "outlineColor": style.outlineColor = try mcpRequiredHexColor(value, key)
                case "outlineOpacity": style.outlineOpacity = try mcpBoundedNumber(value, key, range: 0...1)
                case "shadow": style.shadow = try mcpBoundedNumber(value, key, range: 0...30)
                case "shadowColor": style.shadowColor = try mcpRequiredHexColor(value, key)
                case "shadowOpacity": style.shadowOpacity = try mcpBoundedNumber(value, key, range: 0...1)
                case "shadowBlur": style.shadowBlur = try mcpBoundedNumber(value, key, range: 0...100)
                case "shadowDistance": style.shadowDistance = try mcpBoundedNumber(value, key, range: 0...100)
                case "shadowAngle": style.shadowAngle = try mcpBoundedNumber(value, key, range: 0...360)
                case "subtitleBottomMargin": style.subtitleBottomMargin = try mcpBoundedNumber(value, key, range: 0...2_000)
                default: throw mcpError(-2, "Unsupported subtitle style field: \(key)")
                }
            }
            plan.subtitleStyle = style
        }
        return ["success": true, "planId": updated.plan.id, "subtitleStyle": mcpSubtitleStyleDictionary(updated.plan.subtitleStyle ?? .orangeImpact)]
    }

    private func mcpSetVisualSync(arguments: [String: Any]) throws -> [String: Any] {
        guard let enabled = arguments["enabled"] as? Bool else { throw mcpError(-2, "enabled must be a boolean") }
        let updated = try mcpMutateVisualPlan(arguments["planId"]) { $0.syncEnabled = enabled }
        return ["success": true, "planId": updated.plan.id, "syncEnabled": enabled]
    }

    private func mcpUpdateVisualLogo(arguments: [String: Any], permissions: McpPermissionSet) throws -> [String: Any] {
        guard let action = mcpString(arguments["action"]) else { throw mcpError(-2, "action is required") }
        let language = mcpVisualLanguage(arguments)
        let updated = try mcpMutateVisualPlan(arguments["planId"]) { plan in
            var logo = mcpLogo(for: plan, language: language)
            switch action {
            case "update":
                guard var existing = logo else {
                    throw mcpError(-9, "ASSET_SELECTION_REQUIRED: Add a logo through the Visual Editor file picker before editing it through MCP")
                }
                if let logoID = mcpString(arguments["logoId"]), existing.id != logoID { throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown logoId") }
                if let size = mcpDouble(arguments["size"]), (0.05...5).contains(size) { existing.size = size }
                else if arguments["size"] != nil { throw mcpError(-2, "size must be between 0.05 and 5") }
                if let opacity = mcpDouble(arguments["opacity"]), (0...1).contains(opacity) { existing.opacity = opacity }
                else if arguments["opacity"] != nil { throw mcpError(-2, "opacity must be between 0 and 1") }
                if let position = mcpString(arguments["position"]), ["topLeft", "topRight", "bottomLeft", "bottomRight", "center"].contains(position) { existing.position = position }
                else if arguments["position"] != nil { throw mcpError(-2, "position is invalid") }
                if let hidden = arguments["hidden"] as? Bool { existing.hidden = hidden }
                logo = existing
            case "clear":
                try mcpRequireDestructivePermission(permissions)
                if let logoID = mcpString(arguments["logoId"]), logo?.id != logoID { throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown logoId") }
                logo = nil
            default: throw mcpError(-2, "action must be update or clear")
            }
            mcpSetLogo(logo, on: &plan, language: language)
        }
        return ["success": true, "planId": updated.plan.id, "language": language.rawValue, "logo": mcpLogoDictionary(mcpLogo(for: updated.plan, language: language))]
    }

    private func mcpLogo(for plan: ShortsClipPlan, language: ShortsIdeaDisplayLanguage) -> LogoOverlaySettings? {
        switch language {
        case .source: plan.sourceLogo ?? plan.logo
        case .target: plan.targetLogo ?? plan.logo
        }
    }

    private func mcpSetLogo(_ logo: LogoOverlaySettings?, on plan: inout ShortsClipPlan, language: ShortsIdeaDisplayLanguage) {
        switch language {
        case .source: plan.sourceLogo = logo
        case .target: plan.targetLogo = logo
        }
    }

    private func mcpUpdateIntroOutro(arguments: [String: Any], permissions: McpPermissionSet) throws -> [String: Any] {
        guard let kind = mcpString(arguments["kind"]), ["intro", "outro"].contains(kind),
              let action = mcpString(arguments["action"]) else { throw mcpError(-2, "kind and action are required") }
        let language = mcpVisualLanguage(arguments)
        let updated = try mcpMutateVisualPlan(arguments["planId"]) { plan in
            var overlay = mcpOverlay(for: plan, language: language, kind: kind)
            switch action {
            case "update":
                guard var existing = overlay else {
                    throw mcpError(-9, "ASSET_SELECTION_REQUIRED: Add the \(kind) asset through the Visual Editor file picker before editing it through MCP")
                }
                if let id = mcpString(arguments["overlayId"]), id != existing.id { throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown overlayId") }
                if let value = mcpDouble(arguments["duration"]), (0...30).contains(value) { existing.duration = value } else if arguments["duration"] != nil { throw mcpError(-2, "duration must be between 0 and 30 seconds") }
                if let value = mcpDouble(arguments["x"]), (-100...100).contains(value) { existing.x = value } else if arguments["x"] != nil { throw mcpError(-2, "x must be between -100 and 100") }
                if let value = mcpDouble(arguments["y"]), (-100...100).contains(value) { existing.y = value } else if arguments["y"] != nil { throw mcpError(-2, "y must be between -100 and 100") }
                if let value = mcpDouble(arguments["scale"]), (0.05...5).contains(value) { existing.scale = value } else if arguments["scale"] != nil { throw mcpError(-2, "scale must be between 0.05 and 5") }
                if let value = mcpString(arguments["animation"]), ["none", "fade", "slide", "zoom"].contains(value) { existing.animation = value } else if arguments["animation"] != nil { throw mcpError(-2, "animation is invalid") }
                if let value = arguments["hidden"] as? Bool { existing.hidden = value }
                if let value = mcpDouble(arguments["speed"]), (0.1...4).contains(value) { existing.speed = value } else if arguments["speed"] != nil { throw mcpError(-2, "speed must be between 0.1 and 4") }
                if let value = mcpDouble(arguments["transitionSec"]), (0...10).contains(value) { existing.transitionSec = value } else if arguments["transitionSec"] != nil { throw mcpError(-2, "transitionSec must be between 0 and 10") }
                overlay = existing
            case "clear":
                try mcpRequireDestructivePermission(permissions)
                if let id = mcpString(arguments["overlayId"]), overlay?.id != id { throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown overlayId") }
                overlay = nil
            default: throw mcpError(-2, "action must be update or clear")
            }
            mcpSetOverlay(overlay, on: &plan, language: language, kind: kind)
        }
        return ["success": true, "planId": updated.plan.id, "language": language.rawValue, "kind": kind, "overlay": mcpOverlayDictionary(mcpOverlay(for: updated.plan, language: language, kind: kind))]
    }

    private func mcpOverlay(for plan: ShortsClipPlan, language: ShortsIdeaDisplayLanguage, kind: String) -> IntroOutroOverlaySettings? {
        switch (language, kind) {
        case (.source, "intro"): plan.sourceIntro ?? plan.intro
        case (.target, "intro"): plan.targetIntro ?? plan.intro
        case (.source, "outro"): plan.sourceOutro ?? plan.outro
        default: plan.targetOutro ?? plan.outro
        }
    }

    private func mcpSetOverlay(_ overlay: IntroOutroOverlaySettings?, on plan: inout ShortsClipPlan, language: ShortsIdeaDisplayLanguage, kind: String) {
        switch (language, kind) {
        case (.source, "intro"): plan.sourceIntro = overlay
        case (.target, "intro"): plan.targetIntro = overlay
        case (.source, "outro"): plan.sourceOutro = overlay
        default: plan.targetOutro = overlay
        }
    }

    private func mcpManageTextTrack(arguments: [String: Any], permissions: McpPermissionSet) throws -> [String: Any] {
        guard let action = mcpString(arguments["action"]) else { throw mcpError(-2, "action is required") }
        let language = mcpVisualLanguage(arguments)
        let updated = try mcpMutateVisualPlan(arguments["planId"]) { plan in
            var tracks = mcpTextTracks(for: plan, language: language)
            switch action {
            case "create":
                guard let name = mcpString(arguments["name"]), name.count <= 200 else { throw mcpError(-2, "name is required and must be at most 200 characters") }
                tracks.append(TextOverlayTrack(id: UUID().uuidString.lowercased(), name: name, hidden: arguments["hidden"] as? Bool, muted: arguments["muted"] as? Bool, blocks: []))
            case "update":
                guard let id = mcpString(arguments["trackId"]), let index = tracks.firstIndex(where: { $0.id == id }) else { throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown trackId") }
                if let name = mcpString(arguments["name"]), name.count <= 200 { tracks[index].name = name } else if arguments["name"] != nil { throw mcpError(-2, "name must be at most 200 characters") }
                if let hidden = arguments["hidden"] as? Bool { tracks[index].hidden = hidden }
                if let muted = arguments["muted"] as? Bool { tracks[index].muted = muted }
            case "delete":
                try mcpRequireDestructivePermission(permissions)
                guard let id = mcpString(arguments["trackId"]), tracks.contains(where: { $0.id == id }) else { throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown trackId") }
                tracks.removeAll { $0.id == id }
            default: throw mcpError(-2, "action must be create, update, or delete")
            }
            mcpSetTextTracks(tracks, on: &plan, language: language)
        }
        return ["success": true, "planId": updated.plan.id, "language": language.rawValue, "textTracks": mcpTextTracks(for: updated.plan, language: language).map(mcpTextTrackDictionary)]
    }

    private func mcpTextTracks(for plan: ShortsClipPlan, language: ShortsIdeaDisplayLanguage) -> [TextOverlayTrack] {
        switch language {
        case .source: plan.sourceTextTracks ?? plan.textTracks ?? []
        case .target: plan.targetTextTracks ?? plan.textTracks ?? []
        }
    }

    private func mcpSetTextTracks(_ tracks: [TextOverlayTrack], on plan: inout ShortsClipPlan, language: ShortsIdeaDisplayLanguage) {
        switch language {
        case .source: plan.sourceTextTracks = tracks
        case .target: plan.targetTextTracks = tracks
        }
    }

    private func mcpManageTextBlock(arguments: [String: Any], permissions: McpPermissionSet) throws -> [String: Any] {
        guard let action = mcpString(arguments["action"]), let trackID = mcpString(arguments["trackId"]) else {
            throw mcpError(-2, "action and trackId are required")
        }
        let language = mcpVisualLanguage(arguments)
        let updated = try mcpMutateVisualPlan(arguments["planId"]) { plan in
            let duration = ShortsVisualEditorStateBuilder.clipDuration(plan)
            var tracks = mcpTextTracks(for: plan, language: language)
            guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }) else { throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown trackId") }
            switch action {
            case "create":
                guard let text = mcpString(arguments["text"]), text.count <= 4_000,
                      let start = mcpDouble(arguments["startSec"]), let end = mcpDouble(arguments["endSec"]), start >= 0, end > start, end <= duration else {
                    throw mcpError(-2, "VALIDATION_FAILED: text, startSec, and endSec are required inside the clip")
                }
                tracks[trackIndex].blocks.append(TextOverlayBlock(id: UUID().uuidString.lowercased(), startSec: start, endSec: end, text: text, hidden: arguments["hidden"] as? Bool))
            case "update":
                guard let blockID = mcpString(arguments["blockId"]), let blockIndex = tracks[trackIndex].blocks.firstIndex(where: { $0.id == blockID }) else { throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown blockId") }
                let start = mcpDouble(arguments["startSec"]) ?? tracks[trackIndex].blocks[blockIndex].startSec
                let end = mcpDouble(arguments["endSec"]) ?? tracks[trackIndex].blocks[blockIndex].endSec
                guard start >= 0, end > start, end <= duration else { throw mcpError(-2, "VALIDATION_FAILED: Text block must lie inside the clip") }
                tracks[trackIndex].blocks[blockIndex].startSec = start
                tracks[trackIndex].blocks[blockIndex].endSec = end
                if let text = mcpString(arguments["text"]), text.count <= 4_000 { tracks[trackIndex].blocks[blockIndex].text = text } else if arguments["text"] != nil { throw mcpError(-2, "text must be at most 4,000 characters") }
                if let hidden = arguments["hidden"] as? Bool { tracks[trackIndex].blocks[blockIndex].hidden = hidden }
            case "delete":
                try mcpRequireDestructivePermission(permissions)
                guard let blockID = mcpString(arguments["blockId"]), tracks[trackIndex].blocks.contains(where: { $0.id == blockID }) else { throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown blockId") }
                tracks[trackIndex].blocks.removeAll { $0.id == blockID }
            default: throw mcpError(-2, "action must be create, update, or delete")
            }
            tracks[trackIndex].blocks.sort { $0.startSec < $1.startSec }
            mcpSetTextTracks(tracks, on: &plan, language: language)
        }
        return ["success": true, "planId": updated.plan.id, "language": language.rawValue, "textTracks": mcpTextTracks(for: updated.plan, language: language).map(mcpTextTrackDictionary)]
    }

    private func mcpManageAudioTrack(arguments: [String: Any], permissions: McpPermissionSet) throws -> [String: Any] {
        guard let action = mcpString(arguments["action"]), let trackID = mcpString(arguments["audioTrackId"]) else {
            throw mcpError(-2, "action and audioTrackId are required")
        }
        let language = mcpVisualLanguage(arguments)
        let updated = try mcpMutateVisualPlan(arguments["planId"]) { plan in
            var tracks = mcpAudioTracks(for: plan, language: language)
            guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown audioTrackId") }
            switch action {
            case "update":
                if let name = mcpString(arguments["name"]), name.count <= 200 { tracks[index].name = name } else if arguments["name"] != nil { throw mcpError(-2, "name must be at most 200 characters") }
                if let start = mcpDouble(arguments["startSec"]), start >= 0 { tracks[index].startSec = start } else if arguments["startSec"] != nil { throw mcpError(-2, "startSec must be non-negative") }
                if let trim = mcpDouble(arguments["trimStartSec"]), trim >= 0 { tracks[index].trimStartSec = trim } else if arguments["trimStartSec"] != nil { throw mcpError(-2, "trimStartSec must be non-negative") }
                if let trim = mcpDouble(arguments["trimEndSec"]), trim >= 0 { tracks[index].trimEndSec = trim } else if arguments["trimEndSec"] != nil { throw mcpError(-2, "trimEndSec must be non-negative") }
                if let volume = mcpDouble(arguments["volume"]), (0...2).contains(volume) { tracks[index].volume = volume } else if arguments["volume"] != nil { throw mcpError(-2, "volume must be between 0 and 2") }
                if let fade = mcpDouble(arguments["fadeInSec"]), (0...30).contains(fade) { tracks[index].fadeInSec = fade } else if arguments["fadeInSec"] != nil { throw mcpError(-2, "fadeInSec must be between 0 and 30") }
                if let fade = mcpDouble(arguments["fadeOutSec"]), (0...30).contains(fade) { tracks[index].fadeOutSec = fade } else if arguments["fadeOutSec"] != nil { throw mcpError(-2, "fadeOutSec must be between 0 and 30") }
                if let muted = arguments["muted"] as? Bool { tracks[index].muted = muted }
            case "delete":
                try mcpRequireDestructivePermission(permissions)
                tracks.remove(at: index)
            default: throw mcpError(-2, "action must be update or delete")
            }
            mcpSetAudioTracks(tracks, on: &plan, language: language)
        }
        return ["success": true, "planId": updated.plan.id, "language": language.rawValue, "audioTracks": mcpAudioTracks(for: updated.plan, language: language).map(mcpAudioTrackDictionary)]
    }

    private func mcpAudioTracks(for plan: ShortsClipPlan, language: ShortsIdeaDisplayLanguage) -> [ExtraAudioTrack] {
        switch language {
        case .source: plan.sourceAudioTracks ?? plan.audioTracks ?? []
        case .target: plan.targetAudioTracks ?? plan.audioTracks ?? []
        }
    }

    private func mcpSetAudioTracks(_ tracks: [ExtraAudioTrack], on plan: inout ShortsClipPlan, language: ShortsIdeaDisplayLanguage) {
        switch language {
        case .source: plan.sourceAudioTracks = tracks
        case .target: plan.targetAudioTracks = tracks
        }
    }

    private func mcpOptionalHexColor(_ value: Any?) throws -> String? {
        guard value != nil else { return nil }
        return try mcpRequiredHexColor(value, "backgroundColor")
    }

    private func mcpRequiredHexColor(_ value: Any?, _ key: String) throws -> String {
        guard let color = mcpString(value), color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else {
            throw mcpError(-2, "\(key) must be a #RRGGBB hex colour")
        }
        return color.uppercased()
    }

    private func mcpRequiredBool(_ value: Any, _ key: String) throws -> Bool {
        guard let result = value as? Bool else { throw mcpError(-2, "\(key) must be a boolean") }
        return result
    }

    private func mcpBoundedNumber(_ value: Any, _ key: String, range: ClosedRange<Double>) throws -> Double {
        guard let number = mcpDouble(value), range.contains(number) else {
            throw mcpError(-2, "\(key) must be between \(range.lowerBound) and \(range.upperBound)")
        }
        return number
    }

    // MARK: - MCP safe settings, providers, prompts, and models

    private func mcpSafeSettings() -> [String: Any] {
        let settings = workflow.settings
        return [
            "theme": settings.theme.rawValue,
            "fontSize": settings.fontSize.rawValue,
            "fontScale": settings.fontScale,
            "fontFamily": settings.fontFamily.rawValue,
            "defaultSourceLanguage": settings.defaultSourceLang,
            "defaultTargetLanguage": settings.defaultTargetLang,
            "chunkDurationMin": settings.chunkDurationMin,
            "sliceMode": settings.sliceMode.rawValue,
            "silenceThresholdDb": settings.silenceThreshDb,
            "minimumSilenceMs": settings.minSilenceMs,
            "onboardingCompleted": settings.hasCompletedOnboarding,
            "permissions": McpPermissionSet(settings: settings).safeDictionary,
            "secretPolicy": "API keys, resolver tokens, MCP tokens, model paths, and custom provider credentials are never returned or accepted by MCP.",
        ]
    }

    private func mcpUpdateSafeSettings(arguments: [String: Any]) throws -> [String: Any] {
        guard !arguments.isEmpty else { throw mcpError(-2, "Provide at least one safe setting to update") }
        var updates = 0
        updateSettings { settings in
            if let value = mcpString(arguments["theme"]), let theme = Theme(rawValue: value) { settings.theme = theme; updates += 1 }
            if let value = mcpString(arguments["fontSize"]), let size = FontSize(rawValue: value) { settings.fontSize = size; updates += 1 }
            if let value = mcpDouble(arguments["fontScale"]), (0.8...1.8).contains(value) { settings.fontScale = value; updates += 1 }
            if let value = mcpString(arguments["fontFamily"]), let family = FontFamily(rawValue: value) { settings.fontFamily = family; updates += 1 }
            if let value = mcpString(arguments["defaultSourceLanguage"]), value.count <= 100 { settings.defaultSourceLang = value; updates += 1 }
            if let value = mcpString(arguments["defaultTargetLanguage"]), value.count <= 100, value.lowercased() == "same" || TranslationArchive.isRealLanguage(value) { settings.defaultTargetLang = value; updates += 1 }
            if let value = McpToolArguments.wholeNumber(arguments["chunkDurationMin"]), (1...120).contains(value) { settings.chunkDurationMin = value; updates += 1 }
            if let value = mcpString(arguments["sliceMode"]), let mode = SliceMode(rawValue: value) { settings.sliceMode = mode; updates += 1 }
            if let value = McpToolArguments.wholeNumber(arguments["silenceThresholdDb"]), (-80...0).contains(value) { settings.silenceThreshDb = value; updates += 1 }
            if let value = McpToolArguments.wholeNumber(arguments["minimumSilenceMs"]), (0...10_000).contains(value) { settings.minSilenceMs = value; updates += 1 }
        }
        guard updates > 0 else { throw mcpError(-2, "VALIDATION_FAILED: No supported safe setting was supplied") }
        return ["success": true, "updatedFieldCount": updates, "settings": mcpSafeSettings()]
    }

    private func mcpListProviders() -> [String: Any] {
        let settings = workflow.settings
        let transcription = ProviderRegistry.availableTranscriptionProviders(settings: settings).map(mcpProviderDictionary)
        let translationAvailability = ProviderRegistry.availableTranslationProviders(settings: settings, targetLang: workflow.targetLang)
        return [
            "transcription": transcription,
            "translationEnabled": translationAvailability.enabled,
            "translation": translationAvailability.providers.map(mcpProviderDictionary),
            "selected": ["transcriptionProvider": workflow.transcriptionProvider, "translationProvider": workflow.translationProvider],
        ]
    }

    private func mcpProviderDictionary(_ option: ProviderOption) -> [String: Any] {
        ["providerId": option.id, "label": option.label, "kind": option.kind.rawValue, "group": option.group.rawValue, "ready": true]
    }

    private func mcpSelectProvider(arguments: [String: Any]) throws -> [String: Any] {
        guard let kind = mcpString(arguments["kind"]), let providerID = mcpString(arguments["providerId"]) else {
            throw mcpError(-2, "kind and providerId are required")
        }
        switch kind {
        case "transcription":
            guard ProviderRegistry.availableTranscriptionProviders(settings: workflow.settings).contains(where: { $0.id == providerID }) else { throw mcpError(-10, "PROVIDER_NOT_READY: Transcription provider is unavailable") }
            workflow.transcriptionProvider = providerID
            updateSettings { $0.transcriptionProvider = providerID }
            if var session = workflow.session { session.transcriptionProvider = providerID; workflow.session = session; saveCurrentProject() }
        case "translation":
            guard ProviderRegistry.availableTranslationProviders(settings: workflow.settings, targetLang: workflow.targetLang).providers.contains(where: { $0.id == providerID }) else { throw mcpError(-10, "PROVIDER_NOT_READY: Translation provider is unavailable") }
            workflow.translationProvider = providerID
            updateSettings { $0.translationProvider = providerID }
            if var session = workflow.session { session.translationProvider = providerID; workflow.session = session; saveCurrentProject() }
        default: throw mcpError(-2, "kind must be transcription or translation")
        }
        return ["success": true, "kind": kind, "providerId": providerID]
    }

    private func mcpListPromptPresets() -> [String: Any] {
        ["prompts": DefaultPrompts.definitions.map { definition in
            let preset = workflow.settings.promptPresets[definition.id] ?? DefaultPrompts.defaultPresets[definition.id] ?? PromptPresetSettings()
            return ["promptId": definition.id, "label": definition.label, "stage": definition.stage, "description": definition.description, "variables": definition.variables, "activeSlot": preset.active, "customSlots": preset.custom.keys.sorted()]
        }]
    }

    private func mcpGetPrompt(arguments: [String: Any]) throws -> [String: Any] {
        guard let promptID = mcpString(arguments["promptId"]), let definition = DefaultPrompts.definition(id: promptID) else { throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown promptId") }
        let preset = workflow.settings.promptPresets[promptID] ?? DefaultPrompts.defaultPresets[promptID] ?? PromptPresetSettings()
        let requested = mcpString(arguments["slot"]) ?? "active"
        let slot = requested == "active" ? preset.active : requested
        let text: String
        if slot == "default" { text = definition.defaultText }
        else if let custom = preset.custom[slot] { text = custom.isEmpty ? definition.defaultText : custom }
        else { throw mcpError(-2, "slot must be default, active, custom1, custom2, or custom3") }
        return ["promptId": promptID, "slot": slot, "activeSlot": preset.active, "label": definition.label, "variables": definition.variables, "text": text]
    }

    private func mcpUpdatePrompt(arguments: [String: Any]) throws -> [String: Any] {
        guard let promptID = mcpString(arguments["promptId"]), DefaultPrompts.definition(id: promptID) != nil,
              let slot = mcpString(arguments["slot"]), ["custom1", "custom2", "custom3"].contains(slot),
              let text = arguments["text"] as? String, (1...20_000).contains(text.count) else {
            throw mcpError(-2, "promptId, custom slot, and text (1-20,000 characters) are required")
        }
        let activate = arguments["activate"] as? Bool ?? false
        updateSettings { settings in
            var preset = settings.promptPresets[promptID] ?? PromptPresetSettings()
            preset.custom[slot] = text
            if activate { preset.active = slot }
            settings.promptPresets[promptID] = preset
        }
        return try mcpGetPrompt(arguments: ["promptId": promptID, "slot": slot])
    }

    private func mcpResetPrompt(arguments: [String: Any]) throws -> [String: Any] {
        guard let promptID = mcpString(arguments["promptId"]), DefaultPrompts.definition(id: promptID) != nil else { throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown promptId") }
        let slot = mcpString(arguments["slot"]) ?? "active"
        guard ["active", "custom1", "custom2", "custom3"].contains(slot) else { throw mcpError(-2, "slot must be active, custom1, custom2, or custom3") }
        updateSettings { settings in
            var preset = settings.promptPresets[promptID] ?? PromptPresetSettings()
            if slot == "active" { preset.active = "default" } else { preset.custom[slot] = ""; if preset.active == slot { preset.active = "default" } }
            settings.promptPresets[promptID] = preset
        }
        return try mcpGetPrompt(arguments: ["promptId": promptID, "slot": "active"])
    }

    private func mcpModelStatus() -> [String: Any] {
        let settings = workflow.settings
        let asr = settings.localAsrModels.keys.sorted().compactMap { id in settings.localAsrModels[id].map { mcpModelDictionary(id: id, model: $0, kind: "transcription") } }
        let translation = settings.localTranslationModels.keys.sorted().compactMap { id in settings.localTranslationModels[id].map { mcpModelDictionary(id: id, model: $0, kind: "translation") } }
        return ["models": asr + translation]
    }

    private func mcpModelDictionary(id: String, model: LocalModelState, kind: String) -> [String: Any] {
        [
            "modelId": id,
            "label": model.label,
            "kind": kind,
            "runtime": model.runtime.rawValue,
            "status": model.status.rawValue,
            "progress": model.progress ?? 0,
            "progressLabel": model.progressLabel ?? "",
            "hasError": model.error?.isEmpty == false,
            "isConfigured": model.status == .downloaded,
        ]
    }

    private func mcpModelReference(_ id: String) -> (isTranslation: Bool, model: LocalModelState)? {
        if let model = workflow.settings.localTranslationModels[id] { return (true, model) }
        if let model = workflow.settings.localAsrModels[id] { return (false, model) }
        return nil
    }

    private func mcpDownloadModel(arguments: [String: Any]) throws -> [String: Any] {
        guard let modelID = mcpString(arguments["modelId"]), let reference = mcpModelReference(modelID) else {
            throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown modelId")
        }
        guard reference.model.status != .downloading else { throw mcpError(-4, "JOB_ALREADY_RUNNING: This model is already downloading") }
        let isTranslation = reference.isTranslation
        let jobID = mcpJobManager.start(kind: "download_model", message: "Downloading \(reference.model.label)", cancellable: false) { [weak self] reporter in
            guard let self else { throw NSError(domain: "VaniScriptMCP", code: -1) }
            self.updateSettings { settings in
                if isTranslation, var model = settings.localTranslationModels[modelID] {
                    model.status = .downloading; model.progress = 0; model.progressLabel = "Initializing..."; model.error = nil; settings.localTranslationModels[modelID] = model
                } else if !isTranslation, var model = settings.localAsrModels[modelID] {
                    model.status = .downloading; model.progress = 0; model.progressLabel = "Initializing..."; model.error = nil; settings.localAsrModels[modelID] = model
                }
            }
            let path: String = try await withCheckedThrowingContinuation { continuation in
                ModelDownloadManager.shared.downloadModel(id: modelID) { progress, label in
                    Task { @MainActor in
                        reporter.update(progress: progress, stage: label)
                        self.updateSettings { settings in
                            if isTranslation, var model = settings.localTranslationModels[modelID] { model.progress = progress; model.progressLabel = label; settings.localTranslationModels[modelID] = model }
                            else if !isTranslation, var model = settings.localAsrModels[modelID] { model.progress = progress; model.progressLabel = label; settings.localAsrModels[modelID] = model }
                        }
                    }
                } onComplete: { path in
                    continuation.resume(returning: path)
                } onFailure: { error in
                    continuation.resume(throwing: error)
                }
            }
            self.updateSettings { settings in
                if isTranslation, var model = settings.localTranslationModels[modelID] {
                    model.status = .downloaded; model.path = path; model.progress = 1; model.progressLabel = "Done"; model.error = nil; settings.localTranslationModels[modelID] = model
                } else if !isTranslation, var model = settings.localAsrModels[modelID] {
                    model.status = .downloaded; model.path = path; model.progress = 1; model.progressLabel = "Done"; model.error = nil; settings.localAsrModels[modelID] = model
                }
            }
            guard let final = self.mcpModelReference(modelID)?.model else { throw self.mcpError(-6, "Model settings changed during download") }
            return ["model": self.mcpModelDictionary(id: modelID, model: final, kind: isTranslation ? "translation" : "transcription")]
        }
        return ["jobId": jobID, "status": "queued", "kind": "download_model", "modelId": modelID, "cancellable": false]
    }

    private func mcpLocateModel(arguments: [String: Any]) throws -> [String: Any] {
        guard let modelID = mcpString(arguments["modelId"]), let reference = mcpModelReference(modelID) else {
            throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown modelId")
        }
        let runtime: SharedModelRuntime = reference.isTranslation ? .mlx : .whisperkit
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.directoryURL = try? LocalModelPickerDefaults.directory(for: runtime)
        panel.message = "Choose the local model file or folder requested by VaniScript"
        guard panel.runModal() == .OK, let url = panel.url else { throw mcpError(-9, "USER_CANCELLED: Model selection was cancelled") }
        let valid = reference.isTranslation
            ? LocalModelVerification.verifyTranslationModelPath(url.path, modelID: modelID)
            : LocalModelVerification.verifyModelPath(url.path, isWhisper: true)
        guard valid else { throw mcpError(-2, "VALIDATION_FAILED: The selected location is not a valid \(reference.model.label) model") }
        updateSettings { settings in
            if reference.isTranslation, var model = settings.localTranslationModels[modelID] {
                model.status = .downloaded; model.path = url.path; model.progress = 1; model.progressLabel = "Located"; model.error = nil; settings.localTranslationModels[modelID] = model
            } else if !reference.isTranslation, var model = settings.localAsrModels[modelID] {
                model.status = .downloaded; model.path = url.path; model.progress = 1; model.progressLabel = "Located"; model.error = nil; settings.localAsrModels[modelID] = model
            }
        }
        guard let updated = mcpModelReference(modelID)?.model else { throw mcpError(-6, "Model settings changed during selection") }
        return ["success": true, "model": mcpModelDictionary(id: modelID, model: updated, kind: reference.isTranslation ? "translation" : "transcription")]
    }

    private func mcpRemoveModel(arguments: [String: Any]) throws -> [String: Any] {
        guard let modelID = mcpString(arguments["modelId"]), let reference = mcpModelReference(modelID) else {
            throw mcpError(-3, "ENTITY_NOT_FOUND: Unknown modelId")
        }
        let revision = McpProjectRevision.make(workflow: workflow)
        if arguments["dryRun"] as? Bool ?? true {
            let token = mcpConfirmationStore.issue(operation: "remove_model", fingerprint: modelID, projectRevision: revision)
            return ["dryRun": true, "model": mcpModelDictionary(id: modelID, model: reference.model, kind: reference.isTranslation ? "translation" : "transcription"), "effect": "Removes only VaniScript's model reference; no arbitrary file is deleted.", "confirmationToken": token, "confirmationExpiresInSec": 120]
        }
        try consumeMcpConfirmation(arguments: arguments, operation: "remove_model", fingerprint: modelID, revision: revision)
        if reference.isTranslation { removeLocalTranslationModel(id: modelID) } else { removeLocalASRModel(id: modelID) }
        return ["success": true, "modelId": modelID, "message": "Model reference removed from VaniScript settings"]
    }

    private func requireMcpSession() throws -> SessionState {
        guard let session = workflow.session else { throw mcpError(-1, "NO_ACTIVE_PROJECT: No project is open") }
        return session
    }

    private func mcpPlaybackState() -> [String: Any] {
        [
            "isPlaying": isPlayingCurrentChunk,
            "positionSec": playbackTime,
            "absolutePositionSec": currentPlaybackAbsoluteTime,
            "durationSec": currentChunk?.durationSec ?? 0,
            "chunkId": currentChunk.map(McpEntityIdentifier.chunkID) ?? "",
            "screen": workflow.screen.rawValue,
        ]
    }

    private func mcpExportOptions() -> [String: Any] {
        let hasPlans = !(workflow.session?.shortsPlans?.isEmpty ?? true)
        let hasVideo = workflow.session?.sourceMediaInfo?.kind == .video
            || workflow.session?.sourceFile.map { MediaSource.kind(forPath: $0) == .video } == true
        return [
            "transcript": [
                "available": workflow.session != nil,
                "sides": ["original", "translated"],
                "formats": ["txt", "markdown", "srt", "vtt"],
            ],
            "shortsIdeas": ["available": hasPlans, "languages": ["source", "target"]],
            "shortsVideos": [
                "available": hasPlans && hasVideo,
                "formats": ["mp4", "mov"],
                "resolutions": ["source", "1080p", "720p"],
                "frameRates": ["source", "30", "25", "24"],
            ],
            "destinationPolicy": "Files are written only to VaniScript/MCP Exports and returned by exportId.",
        ]
    }

    private func mcpValidateExport(kind: String) throws -> [String: Any] {
        guard let session = workflow.session else { throw mcpError(-1, "NO_ACTIVE_PROJECT: No project is open") }
        var issues: [[String: Any]] = []
        switch kind {
        case "transcript":
            if session.chunks.isEmpty {
                issues.append(["severity": "error", "code": "NO_CHUNKS", "message": "The project has no segments."])
            }
            if session.chunks.allSatisfy({ $0.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                issues.append(["severity": "error", "code": "EMPTY_TRANSCRIPT", "message": "The project has no transcript text."])
            }
        case "shortsIdeas":
            if session.shortsPlans?.isEmpty ?? true {
                issues.append(["severity": "error", "code": "NO_SHORTS_PLANS", "message": "Create Shorts plans first."])
            }
        case "shortsVideos":
            if session.shortsPlans?.isEmpty ?? true {
                issues.append(["severity": "error", "code": "NO_SHORTS_PLANS", "message": "Create Shorts plans first."])
            }
            guard let source = session.sourceFile, FileManager.default.fileExists(atPath: source) else {
                issues.append(["severity": "error", "code": "SOURCE_MEDIA_MISSING", "message": "Original source video is unavailable."])
                return ["valid": false, "kind": kind, "issues": issues]
            }
            if MediaSource.kind(forPath: source) != .video {
                issues.append(["severity": "error", "code": "VIDEO_REQUIRED", "message": "Shorts video export requires video source media."])
            }
        default:
            throw mcpError(-2, "kind must be transcript, shortsIdeas, or shortsVideos")
        }
        return [
            "valid": !issues.contains { $0["severity"] as? String == "error" },
            "kind": kind,
            "issues": issues,
        ]
    }

    private func mcpExportTranscript(arguments: [String: Any]) throws -> [String: Any] {
        guard let session = workflow.session else { throw mcpError(-1, "NO_ACTIVE_PROJECT: No project is open") }
        guard let rawSide = mcpString(arguments["side"]), let side = TranscriptSide(rawValue: rawSide) else {
            throw mcpError(-2, "side must be original or translated")
        }
        guard let rawFormat = mcpString(arguments["format"]) else { throw mcpError(-2, "format is required") }
        let format: OutputFormat
        switch rawFormat.lowercased() {
        case "txt": format = .txt
        case "markdown": format = .markdown
        case "srt": format = .srt
        case "vtt": format = .vtt
        default: throw mcpError(-2, "Unsupported transcript format")
        }
        let language = side == .translated ? mcpString(arguments["language"]) ?? session.selectedTranslationLanguage : nil
        if side == .translated, language == nil {
            throw mcpError(-2, "No translated language is selected")
        }
        let content = TranscriptExportBuilder.build(side: side, format: format, session: session, language: language)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw mcpError(-3, "Export content is empty")
        }
        let export = try mcpExportStore.makeDirectory(label: "transcript")
        let file = export.url.appendingPathComponent(
            TranscriptExportBuilder.defaultFileName(side: side, format: format, session: session, language: language)
        )
        try content.write(to: file, atomically: true, encoding: .utf8)
        return mcpExportStore.register(exportID: export.id, files: [file])
    }

    private func mcpExportShortsIdeas(arguments: [String: Any]) throws -> [String: Any] {
        guard let session = workflow.session, let plans = session.shortsPlans, !plans.isEmpty else {
            throw mcpError(-3, "No Shorts plans are available")
        }
        let requestedIDs = Set((arguments["planIds"] as? [String]) ?? [])
        let selected = requestedIDs.isEmpty ? plans : plans.filter { requestedIDs.contains($0.id) }
        guard !selected.isEmpty else { throw mcpError(-3, "No matching planIds") }
        let language = ShortsIdeaDisplayLanguage(rawValue: mcpString(arguments["language"]) ?? "source") ?? .source
        let json = try ShortsIdeasExporter.renderJSON(plans: selected, displayLanguage: language)
        let text = ShortsIdeasExporter.renderText(plans: selected, displayLanguage: language)
        let export = try mcpExportStore.makeDirectory(label: "shorts-ideas")
        let jsonFile = export.url.appendingPathComponent("shorts-ideas.json")
        let textFile = export.url.appendingPathComponent("shorts-ideas.txt")
        try json.write(to: jsonFile, atomically: true, encoding: .utf8)
        try text.write(to: textFile, atomically: true, encoding: .utf8)
        return mcpExportStore.register(exportID: export.id, files: [jsonFile, textFile])
    }

    private func startMcpShortsExportJob(arguments: [String: Any]) throws -> [String: Any] {
        guard let session = workflow.session,
              let sourcePath = session.sourceFile,
              FileManager.default.fileExists(atPath: sourcePath),
              let plans = session.shortsPlans,
              !plans.isEmpty else {
            throw mcpError(-3, "Export requires source video and Shorts plans")
        }
        guard MediaSource.kind(forPath: sourcePath) == .video else {
            throw mcpError(-2, "Shorts video export requires video source media")
        }
        let requestedIDs = Set((arguments["planIds"] as? [String]) ?? [])
        let selected = plans.enumerated().filter { requestedIDs.isEmpty || requestedIDs.contains($0.element.id) }
        guard !selected.isEmpty else { throw mcpError(-3, "No matching planIds") }
        let language = ShortsIdeaDisplayLanguage(rawValue: mcpString(arguments["language"]) ?? "source") ?? .source
        let format = mcpString(arguments["format"]) ?? "mp4"
        let resolutionValue = mcpString(arguments["resolution"]) ?? "source"
        let resolution = resolutionValue == "source" ? "Source-based" : resolutionValue
        let frameRateValue = mcpString(arguments["frameRate"]) ?? "source"
        let frameRate = frameRateValue == "source" ? "Source-based" : frameRateValue
        let export = try mcpExportStore.makeDirectory(label: "shorts-videos")
        let jobs = selected.map {
            NativeShortsVideoRenderJob(planIndex: $0.offset, plan: $0.element, language: language)
        }
        let jobID = mcpJobManager.start(kind: "export_shorts_videos", message: "Rendering \(jobs.count) Shorts video(s)") { [weak self] reporter in
            guard let self else { throw NSError(domain: "VaniScriptMCP", code: -1) }
            let files = try await NativeShortsVideoRenderer.export(
                sourceURL: URL(fileURLWithPath: sourcePath),
                jobs: jobs,
                directory: export.url,
                options: NativeShortsExportOptions(
                    format: format,
                    resolutionPreset: resolution,
                    frameRatePreset: frameRate,
                    language: language
                )
            ) { progress, stage, _ in
                Task { @MainActor in reporter.update(progress: progress, stage: stage) }
            }
            try reporter.checkCancellation()
            return self.mcpExportStore.register(exportID: export.id, files: files)
        }
        return [
            "jobId": jobID,
            "status": "queued",
            "kind": "export_shorts_videos",
            "exportId": export.id,
            "clipCount": jobs.count,
        ]
    }

    private func mcpDouble(_ value: Any?) -> Double? {
        if let value = value as? Double, value.isFinite { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite {
            return value.doubleValue
        }
        return nil
    }

    private func mcpProjectSummary(_ record: ProjectRecord) -> [String: Any] {
        let summary = record.summary
        return [
            "id": summary.id,
            "name": summary.name,
            "sourceFileName": summary.sourceFileName,
            "createdAt": summary.createdAt,
            "updatedAt": summary.updatedAt,
            "currentChunkId": record.session.chunks.indices.contains(summary.currentIndex)
                ? McpEntityIdentifier.chunkID(record.session.chunks[summary.currentIndex]) : "",
            "totalChunks": summary.totalChunks,
            "approvedChunks": summary.approvedChunks,
            "completedChunks": summary.completedChunks,
            "targetLanguage": summary.targetLang,
            "shortsPlanCount": record.session.shortsPlans?.count ?? 0,
            "sourceMediaAvailable": record.session.sourceFile.map(FileManager.default.fileExists(atPath:)) ?? false,
        ]
    }

    private func mcpSourceMediaInfo(_ info: SourceMediaInfo) -> [String: Any] {
        var result: [String: Any] = [
            "fileName": info.fileName,
            "title": info.title ?? info.fileName,
            "kind": info.kind.rawValue,
            "fileAvailable": FileManager.default.fileExists(atPath: info.filePath),
            "quality": info.qualityLabel,
        ]
        if let value = info.durationSec { result["durationSec"] = value }
        if let value = info.fileSizeBytes { result["fileSizeBytes"] = value }
        if let value = info.width { result["width"] = value }
        if let value = info.height { result["height"] = value }
        if let value = info.frameRate { result["frameRate"] = value }
        if let value = info.videoCodec { result["videoCodec"] = value }
        if let value = info.audioCodec { result["audioCodec"] = value }
        if let value = info.container { result["container"] = value }
        if let value = info.audioSampleRateHz { result["audioSampleRateHz"] = value }
        if let value = info.audioChannelCount { result["audioChannelCount"] = value }
        if let value = info.originalURL { result["sourceWasImportedFromURL"] = !value.isEmpty }
        return result
    }

    private func consumeMcpConfirmation(
        arguments: [String: Any],
        operation: String,
        fingerprint: String,
        revision: String
    ) throws {
        guard mcpString(arguments["expectedRevision"]) == revision else {
            throw mcpError(-6, "STALE_REVISION: Use the projectRevision returned with the preview")
        }
        guard let token = mcpString(arguments["confirmationToken"]),
              mcpConfirmationStore.consume(
                token: token,
                operation: operation,
                fingerprint: fingerprint,
                projectRevision: revision
              ) else {
            throw mcpError(-7, "CONFIRMATION_REQUIRED: Run dryRun=true and use its unexpired confirmationToken")
        }
    }

    private func mcpString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    private func mcpError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "VaniScriptMCP", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    public func executeMcpTool(
        name: String,
        arguments: [String: Any],
        allowMutatingTools: Bool = true
    ) async throws -> [String: Any] {
        try await executeMcpTool(
            name: name,
            arguments: arguments,
            permissions: McpPermissionSet(allowed: allowMutatingTools ? Set(McpToolAccess.allCases) : [.read])
        )
    }

    public func executeMcpTool(
        name: String,
        arguments: [String: Any],
        permissions: McpPermissionSet
    ) async throws -> [String: Any] {
        guard let definition = McpToolRegistry.definition(named: name),
              McpToolRegistry.isAllowed(name, permissions: permissions) else {
            throw NSError(domain: "WorkflowStore", code: -5, userInfo: [NSLocalizedDescriptionKey: "Tool \(name) is not available in the current MCP policy"])
        }
        let requestID = arguments["requestId"] as? String
        if let requestID, requestID.count > 128 {
            throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "requestId must contain no more than 128 characters"])
        }
        let fingerprint = McpRequestCache.fingerprint(arguments: arguments)
        if definition.access != .read,
           let requestID,
           let replay = try mcpRequestCache.result(requestID: requestID, toolName: name, fingerprint: fingerprint) {
            return replay
        }

        let previousRevision = McpProjectRevision.make(workflow: workflow)
        var result = try await executeMcpToolImpl(name: name, arguments: arguments, permissions: permissions)
        let projectRevision = McpProjectRevision.make(workflow: workflow)
        if definition.access != .read, projectRevision != previousRevision {
            let change = mcpAuditStore.record(
                toolName: name,
                requestID: requestID,
                previousRevision: previousRevision,
                projectRevision: projectRevision
            )
            result["changeSetId"] = change.id
            result["projectRevision"] = projectRevision
        }
        if definition.access != .read, let requestID {
            mcpRequestCache.store(requestID: requestID, toolName: name, fingerprint: fingerprint, result: result)
        }
        return result
    }

    private func executeMcpToolImpl(
        name: String,
        arguments: [String: Any],
        permissions: McpPermissionSet
    ) async throws -> [String: Any] {
        let getInt = { (val: Any?) -> Int? in
            McpToolArguments.wholeNumber(val)
        }
        let getDouble = { (val: Any?) -> Double? in
            if let doubleVal = val as? Double, doubleVal.isFinite { return doubleVal }
            if let intVal = val as? Int { return Double(intVal) }
            return nil
        }
        let chunkIndexHelp = { (session: SessionState) -> String in
            let currentIndex = max(0, min(session.currentChunkIndex, max(0, session.chunks.count - 1)))
            return "Missing or invalid chunk reference. Call list_chunks and pass its stable chunkId. Legacy visible Chunk \(currentIndex + 1) uses chunkIndex \(currentIndex)."
        }
        let resolveChunkIndex = { (arguments: [String: Any], session: SessionState) -> Int? in
            if let rawID = arguments["chunkId"] as? String,
               let stableIndex = McpEntityIdentifier.chunkIndex(from: rawID) {
                return session.chunks.firstIndex { $0.index == stableIndex }
            }
            return getInt(arguments["chunkIndex"])
        }
        let mutationResult = { (message: String, workflow: WorkflowState) -> [String: Any] in
            [
                "success": true,
                "message": message,
                "projectRevision": McpProjectRevision.make(workflow: workflow),
            ]
        }

        guard McpToolRegistry.isAllowed(name, permissions: permissions) else {
            throw NSError(domain: "WorkflowStore", code: -5, userInfo: [NSLocalizedDescriptionKey: "Tool \(name) is not available in the current MCP policy"])
        }

        if McpToolRegistry.definition(named: name)?.access != .read,
           let rawExpectedRevision = arguments["expectedRevision"] {
            guard let expectedRevision = rawExpectedRevision as? String else {
                throw NSError(
                    domain: "WorkflowStore",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "expectedRevision must be a string returned by a VaniScript read tool"]
                )
            }
            let currentRevision = McpProjectRevision.make(workflow: workflow)
            guard expectedRevision == currentRevision else {
                throw NSError(
                    domain: "WorkflowStore",
                    code: -6,
                    userInfo: [NSLocalizedDescriptionKey: "STALE_REVISION: The project changed after the agent read it. Read the affected state again. Current revision: \(currentRevision)"]
                )
            }
        }

        if name == "list_jobs" {
            let limit = max(1, min(100, getInt(arguments["limit"]) ?? 20))
            return ["jobs": mcpJobManager.list(limit: limit)]
        }
        if name == "get_change_history" {
            let cursor = max(0, getInt(arguments["cursor"]) ?? 0)
            let limit = max(1, min(100, getInt(arguments["limit"]) ?? 50))
            return mcpAuditStore.list(cursor: cursor, limit: limit)
        }
        if name == "get_job" {
            guard let jobID = arguments["jobId"] as? String,
                  let job = mcpJobManager.get(id: jobID) else {
                throw NSError(domain: "WorkflowStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unknown jobId"])
            }
            return job
        }
        if name == "cancel_job" {
            guard let jobID = arguments["jobId"] as? String,
                  mcpJobManager.cancel(id: jobID) else {
                throw NSError(domain: "WorkflowStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "Job is unknown, finished, or not cancellable"])
            }
            return ["success": true, "jobId": jobID, "status": McpJobStatus.cancelled.rawValue]
        }

        if let workspaceResult = try await executeMcpWorkspaceTool(name: name, arguments: arguments, permissions: permissions) {
            var result = workspaceResult
            result["projectRevision"] = McpProjectRevision.make(workflow: workflow)
            return result
        }

        if McpReadToolService.supportedToolNames.contains(name) {
            var result = try McpReadToolService.execute(
                name: name,
                arguments: arguments,
                workflow: workflow,
                permissions: permissions
            )
            result["projectRevision"] = McpProjectRevision.make(workflow: workflow)
            return result
        }

        if [
            "translate_chunk",
            "translate_cue",
            "translate_pending_chunks",
            "retry_chunk_translation",
            "polish_translation",
        ].contains(name) {
            return try startMcpTranslationJob(name: name, arguments: arguments)
        }

        if McpGlossaryToolService.supportedToolNames.contains(name) {
            let mutation = try McpGlossaryToolService.execute(
                name: name,
                arguments: arguments,
                workflow: workflow,
                confirmationStore: mcpConfirmationStore
            )
            if mutation.workflow != workflow {
                workflow = mutation.workflow
                statusMessage = mutation.message
                persistSettings()
                saveCurrentProject()
            }
            var result = mutation.details
            result["success"] = true
            result["message"] = mutation.message
            result["projectRevision"] = McpProjectRevision.make(workflow: workflow)
            return result
        }

        if McpTranscriptToolService.supportedToolNames.contains(name) {
            let mutation = try McpTranscriptToolService.execute(
                name: name,
                arguments: arguments,
                workflow: workflow,
                confirmationStore: mcpConfirmationStore
            )
            if mutation.workflow != workflow {
                workflow = mutation.workflow
                statusMessage = mutation.message
                saveCurrentProject()
            }
            var result = mutation.details
            result["success"] = true
            result["message"] = mutation.message
            result["projectRevision"] = McpProjectRevision.make(workflow: workflow)
            return result
        }
        
        switch name {
        case "get_project_state":
            return McpProjectStateSnapshot.build(workflow: workflow)

        case "select_translation_language":
            guard var session = workflow.session,
                  let rawLanguage = arguments["language"] as? String else {
                throw NSError(domain: "WorkflowStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active session or language is missing"])
            }
            let language = TranslationArchive.displayLanguage(rawLanguage)
            let availableKeys = Set((session.availableTranslationLanguages ?? []).map(TranslationArchive.languageKey))
            guard availableKeys.contains(TranslationArchive.languageKey(language)) else {
                throw NSError(domain: "WorkflowStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "Translation language is not available. Call add_translation_language first."])
            }
            session.setActiveTranslationLanguage(language)
            workflow.session = session
            workflow.targetLang = language
            archiveTargetLanguage = language
            saveCurrentProject()
            return mutationResult("Selected \(language) translation", workflow)

        case "add_translation_language":
            guard var session = workflow.session,
                  let rawLanguage = arguments["language"] as? String else {
                throw NSError(domain: "WorkflowStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active session or language is missing"])
            }
            let language = TranslationArchive.displayLanguage(rawLanguage)
            guard TranslationArchive.isRealLanguage(language) else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Provide a real translation language"])
            }
            session.registerTranslationLanguage(language)
            session.setActiveTranslationLanguage(language)
            workflow.session = session
            workflow.targetLang = language
            archiveTargetLanguage = language
            saveCurrentProject()
            return mutationResult("Added and selected \(language) translation", workflow)

        case "remove_translation_language":
            guard var session = workflow.session,
                  let rawLanguage = arguments["language"] as? String else {
                throw NSError(domain: "WorkflowStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active session or language is missing"])
            }
            let language = TranslationArchive.displayLanguage(rawLanguage)
            let languageKey = TranslationArchive.languageKey(language)
            let existing = session.availableTranslationLanguages ?? []
            guard existing.contains(where: { TranslationArchive.languageKey($0) == languageKey }) else {
                throw NSError(domain: "WorkflowStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "Translation language is not present in the project"])
            }
            session.availableTranslationLanguages = existing.filter { TranslationArchive.languageKey($0) != languageKey }
            for index in session.chunks.indices {
                session.chunks[index].translationsByLanguage?[languageKey] = nil
            }
            if session.activeTranslationLanguage.map(TranslationArchive.languageKey) == languageKey
                || TranslationArchive.languageKey(session.targetLang) == languageKey {
                session.activeTranslationLanguage = nil
                if let fallback = session.availableTranslationLanguages?.first {
                    session.setActiveTranslationLanguage(fallback)
                    workflow.targetLang = fallback
                    archiveTargetLanguage = fallback
                } else {
                    session.targetLang = "same"
                    workflow.targetLang = "same"
                    for index in session.chunks.indices {
                        session.chunks[index].translated = ""
                    }
                }
            }
            workflow.session = session
            saveCurrentProject()
            return mutationResult("Removed \(language) translation", workflow)
            
        case "update_chunk_text":
            guard var session = workflow.session else {
                throw NSError(domain: "WorkflowStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active session"])
            }
            guard let chunkIndexVal = resolveChunkIndex(arguments, session) else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: chunkIndexHelp(session)])
            }
            guard chunkIndexVal >= 0 && chunkIndexVal < session.chunks.count else {
                throw NSError(domain: "WorkflowStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "chunkIndex out of bounds"])
            }
            guard arguments["original"] is String || arguments["translated"] is String else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Provide original and/or translated text to update"])
            }
            
            if let original = arguments["original"] as? String {
                session.chunks[chunkIndexVal].original = original
            }
            if let translated = arguments["translated"] as? String {
                session.chunks[chunkIndexVal].translated = translated
                if let lang = session.selectedTranslationLanguage {
                    session.chunks[chunkIndexVal].setTranslation(
                        translated,
                        language: lang,
                        provider: session.translationProvider,
                        updatedAt: isoString(clock())
                    )
                }
            }
            
            workflow.session = session
            saveCurrentProject()
            return mutationResult("Updated segment \(chunkIndexVal + 1) text", workflow)
            
        case "approve_chunk":
            guard var session = workflow.session else {
                throw NSError(domain: "WorkflowStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active session"])
            }
            guard let chunkIndexVal = resolveChunkIndex(arguments, session),
                  let approved = arguments["approved"] as? Bool else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "\(chunkIndexHelp(session)) The approved value must be a boolean."])
            }
            guard chunkIndexVal >= 0 && chunkIndexVal < session.chunks.count else {
                throw NSError(domain: "WorkflowStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "chunkIndex out of bounds"])
            }
            
            session.chunks[chunkIndexVal].approved = approved
            workflow.session = session
            saveCurrentProject()
            return mutationResult("Updated approval for segment \(chunkIndexVal + 1) to \(approved)", workflow)
            
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
            return mutationResult("Updated subtitle style for active shorts plans", workflow)
            
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
                        "hook": plan.hook
                    ])
                }
            }
            return ["plans": plansInfo]
            
        case "update_cue_timestamps":
            guard var session = workflow.session else {
                throw NSError(domain: "WorkflowStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active session"])
            }
            guard let chunkIndexVal = resolveChunkIndex(arguments, session),
                  let cueIndexVal = getInt(arguments["cueIndex"]),
                  let sideVal = arguments["side"] as? String else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "\(chunkIndexHelp(session)) cueIndex must be a zero-based number and side must be original or translated."])
            }
            guard chunkIndexVal >= 0 && chunkIndexVal < session.chunks.count else {
                throw NSError(domain: "WorkflowStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "chunkIndex out of bounds"])
            }
            
            let startSecVal = getDouble(arguments["startSec"])
            let endSecVal = getDouble(arguments["endSec"])
            
            let side = sideVal.lowercased()
            guard side == "original" || side == "translated" else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "side must be original or translated"])
            }

            if side == "original" {
                var cues = session.chunks[chunkIndexVal].originalCues ?? []
                guard cueIndexVal >= 0 && cueIndexVal < cues.count else {
                    throw NSError(domain: "WorkflowStore", code: -4, userInfo: [NSLocalizedDescriptionKey: "cueIndex out of bounds"])
                }
                if let start = startSecVal { cues[cueIndexVal].startSec = start }
                if let end = endSecVal { cues[cueIndexVal].endSec = end }
                session.chunks[chunkIndexVal].originalCues = cues
            } else {
                let lang = session.selectedTranslationLanguage ?? ""
                var cues = session.chunks[chunkIndexVal].translationCues(for: lang)
                if cues.isEmpty {
                    let sourceCues = session.chunks[chunkIndexVal].originalCues ?? []
                    cues = sourceCues.map { source in
                        TranscriptCue(startSec: source.startSec, endSec: source.endSec, text: "")
                    }
                }
                guard cueIndexVal >= 0 && cueIndexVal < cues.count else {
                    throw NSError(domain: "WorkflowStore", code: -4, userInfo: [NSLocalizedDescriptionKey: "cueIndex out of bounds"])
                }
                if let start = startSecVal { cues[cueIndexVal].startSec = start }
                if let end = endSecVal { cues[cueIndexVal].endSec = end }
                
                let translated = cues.map(\.text).joined(separator: "\n")
                session.chunks[chunkIndexVal].translated = translated
                session.chunks[chunkIndexVal].setTranslation(
                    translated,
                    language: lang,
                    provider: session.translationProvider,
                    updatedAt: isoString(clock()),
                    cues: cues
                )
            }
            
            workflow.session = session
            saveCurrentProject()
            return mutationResult("Updated \(sideVal) cue \(cueIndexVal) timestamps", workflow)
            
        case "align_translation_timings":
            guard var session = workflow.session else {
                throw NSError(domain: "WorkflowStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active session"])
            }
            guard let chunkIndexVal = resolveChunkIndex(arguments, session) else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: chunkIndexHelp(session)])
            }
            guard chunkIndexVal >= 0 && chunkIndexVal < session.chunks.count else {
                throw NSError(domain: "WorkflowStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "chunkIndex out of bounds"])
            }
            
            let lang = session.selectedTranslationLanguage ?? ""
            let sourceCues = session.chunks[chunkIndexVal].originalCues ?? []
            var targetCues = session.chunks[chunkIndexVal].translationCues(for: lang)
            
            if targetCues.isEmpty {
                targetCues = sourceCues.map { source in
                    TranscriptCue(startSec: source.startSec, endSec: source.endSec, text: "")
                }
            } else {
                for i in 0..<min(sourceCues.count, targetCues.count) {
                    targetCues[i].startSec = sourceCues[i].startSec
                    targetCues[i].endSec = sourceCues[i].endSec
                }
            }
            
            let translated = targetCues.map(\.text).joined(separator: "\n")
            session.chunks[chunkIndexVal].translated = translated
            session.chunks[chunkIndexVal].setTranslation(
                translated,
                language: lang,
                provider: session.translationProvider,
                updatedAt: isoString(clock()),
                cues: targetCues
            )
            
            workflow.session = session
            saveCurrentProject()
            return mutationResult("Aligned translated cue timings with original cues for segment \(chunkIndexVal + 1)", workflow)
            
        case "reprocess_chunk":
            guard var session = workflow.session else {
                throw NSError(domain: "WorkflowStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active session"])
            }
            guard let chunkIndexVal = resolveChunkIndex(arguments, session) else {
                throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: chunkIndexHelp(session)])
            }
            guard chunkIndexVal >= 0 && chunkIndexVal < session.chunks.count else {
                throw NSError(domain: "WorkflowStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "chunkIndex out of bounds"])
            }
            
            session.currentChunkIndex = chunkIndexVal
            session.chunks[chunkIndexVal].approved = false
            session.chunks[chunkIndexVal].status = .pending
            
            workflow.session = session
            saveCurrentProject()
            
            await MainActor.run {
                self.processCurrentChunkIfNeeded(force: true)
            }
            
            return mutationResult("Triggered reprocessing (transcription & translation) for segment \(chunkIndexVal + 1)", workflow)
            
        default:
            throw NSError(domain: "WorkflowStore", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unknown tool \(name)"])
        }
    }

    public func transcribeDictation(url: URL) async throws -> String {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw NSError(domain: "WorkflowStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Audio file not found."])
        }
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? UInt64 ?? 0
        guard size > 0 else {
            throw NSError(domain: "WorkflowStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "Audio recording is empty (0 bytes)."])
        }

        guard let model = NativeModelCatalog.activeWhisperKitModel(
            settings: workflow.settings,
            providerID: workflow.settings.transcriptionProvider
        ) else {
            throw NSError(domain: "WorkflowStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No local Whisper model is selected. Please check Settings."])
        }
        
        let defaultLang = workflow.settings.defaultSourceLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let langCode: String?
        if defaultLang.hasPrefix("ru") {
            langCode = "ru"
        } else if defaultLang.hasPrefix("en") {
            langCode = "en"
        } else if defaultLang.hasPrefix("es") {
            langCode = "es"
        } else if defaultLang.hasPrefix("fr") {
            langCode = "fr"
        } else if defaultLang.hasPrefix("de") {
            langCode = "de"
        } else if defaultLang.hasPrefix("it") {
            langCode = "it"
        } else if defaultLang.hasPrefix("pt") {
            langCode = "pt"
        } else if defaultLang.hasPrefix("hi") {
            langCode = "hi"
        } else {
            langCode = nil
        }

        let pipeline = try await processingPipeline.loadWhisperKit(model: model)
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: langCode,
            temperature: 0,
            detectLanguage: langCode == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
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
