import Testing
@testable import VaniScriptCore

@Suite("Universal workflow state")
struct WorkflowStateTests {
    @Test("selecting a source moves upload to config")
    func selectingSourceMovesToConfig() {
        var state = WorkflowState.initial(settings: .defaults)

        state.selectSource(path: "/audio/2026-05-22 HH Kadamba Kanana Swami Mayapur.mp3", durationSec: 900)

        #expect(state.screen == .config)
        #expect(state.sourceFileName == "2026-05-22 HH Kadamba Kanana Swami Mayapur.mp3")
        #expect(state.metadata.lecturer == "HH Kadamba Kanana Swami")
        #expect(state.durationSec == 900)
    }

    @Test("starting a session builds chunks and opens review")
    func startingSessionBuildsChunksAndOpensReview() {
        var state = WorkflowState.initial(settings: .defaults)
        state.selectSource(path: "/audio/lecture.wav", durationSec: 1_250)

        state.startSession()

        #expect(state.screen == .review)
        #expect(state.session?.sourceFile == "/audio/lecture.wav")
        #expect(state.session?.chunks.count == 3)
        #expect(state.session?.currentChunkIndex == 0)
    }

    @Test("can start when duration is not available before processing")
    func canStartWithoutPreflightDuration() {
        var state = WorkflowState.initial(settings: .defaults)
        state.selectSource(path: "/audio/lecture.wav", durationSec: 0)

        #expect(state.canStartSession)
    }

    @Test("settings provider changes update active workflow providers")
    func settingsProviderChangesUpdateActiveWorkflowProviders() {
        let previousSettings = AppSettings.defaults
        var nextSettings = previousSettings
        nextSettings.geminiKey = "gemini-key"
        nextSettings.transcriptionProvider = "gemini-cloud"
        nextSettings.translationProvider = "gemini-cloud"

        var state = WorkflowState.initial(settings: previousSettings)
        state.settings = nextSettings

        state.synchronizeProviderSelections(previousSettings: previousSettings)

        #expect(state.transcriptionProvider == "gemini-cloud")
        #expect(state.translationProvider == "gemini-cloud")
    }

    @Test("settings provider changes do not override explicit workflow provider choices")
    func settingsProviderChangesDoNotOverrideExplicitWorkflowProviderChoices() {
        var previousSettings = AppSettings.defaults
        previousSettings.geminiKey = "gemini-key"
        previousSettings.openaiKey = "openai-key"
        var nextSettings = previousSettings
        nextSettings.transcriptionProvider = "gpt-cloud"
        nextSettings.translationProvider = "gpt-cloud"

        var state = WorkflowState.initial(settings: previousSettings)
        state.transcriptionProvider = "gemini-cloud"
        state.translationProvider = "gemini-cloud"
        state.settings = nextSettings

        state.synchronizeProviderSelections(previousSettings: previousSettings)

        #expect(state.transcriptionProvider == "gemini-cloud")
        #expect(state.translationProvider == "gemini-cloud")
    }

    @Test("forced settings provider changes override explicit workflow provider choices")
    func forcedSettingsProviderChangesOverrideExplicitWorkflowProviderChoices() {
        let previousSettings = AppSettings.defaults
        var nextSettings = previousSettings
        nextSettings.geminiKey = "gemini-key"
        nextSettings.transcriptionProvider = "gemini-cloud"
        nextSettings.translationProvider = "gemini-cloud"

        var state = WorkflowState.initial(settings: previousSettings)
        state.transcriptionProvider = "whisper-large-v3"
        state.translationProvider = "qwen35-4b-4bit"
        state.settings = nextSettings

        state.synchronizeProviderSelections(
            previousSettings: previousSettings,
            forceTranscriptionProvider: true,
            forceTranslationProvider: true
        )

        #expect(state.transcriptionProvider == "gemini-cloud")
        #expect(state.translationProvider == "gemini-cloud")
    }

    @Test("forced settings provider changes update active session providers")
    func forcedSettingsProviderChangesUpdateActiveSessionProviders() {
        let previousSettings = AppSettings.defaults
        var nextSettings = previousSettings
        nextSettings.geminiKey = "gemini-key"
        nextSettings.transcriptionProvider = "gemini-cloud"
        nextSettings.translationProvider = "gemini-cloud"

        var state = WorkflowState.initial(settings: previousSettings)
        state.selectSource(path: "/audio/lecture.wav", durationSec: 120)
        state.startSession()
        state.settings = nextSettings
        state.synchronizeProviderSelections(
            previousSettings: previousSettings,
            forceTranscriptionProvider: true,
            forceTranslationProvider: true
        )
        state.synchronizeActiveSessionProviders(
            forceTranscriptionProvider: true,
            forceTranslationProvider: true
        )

        #expect(state.session?.transcriptionProvider == "gemini-cloud")
        #expect(state.session?.translationProvider == "gemini-cloud")
    }

    @Test("same target language preserves translation provider for polishing and editing")
    func sameTargetLanguagePreservesTranslationProviderAfterSettingsSync() {
        let previousSettings = AppSettings.defaults
        var nextSettings = previousSettings
        nextSettings.geminiKey = "gemini-key"
        nextSettings.translationProvider = "gemini-cloud"

        var state = WorkflowState.initial(settings: previousSettings)
        state.updateTargetLanguage("same")
        state.settings = nextSettings

        state.synchronizeProviderSelections(previousSettings: previousSettings)

        #expect(state.translationProvider == "gemini-cloud")
    }

    @Test("export opens only after a session exists")
    func exportRequiresSession() {
        var state = WorkflowState.initial(settings: .defaults)

        state.openExport()
        #expect(state.screen == .upload)

        state.selectSource(path: "/audio/lecture.wav", durationSec: 120)
        state.startSession()
        state.openExport()
        #expect(state.screen == .export)
    }
}
