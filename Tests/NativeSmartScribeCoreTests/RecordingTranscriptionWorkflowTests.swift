import Foundation
import NativeSmartScribeCore
import Testing

@MainActor
@Test
func recordingTranscriptionWorkflowCreatesNoteAndStoresTranscript() async {
    let store = NoteStore()
    let recording = AudioRecording(
        fileURL: URL(fileURLWithPath: "/tmp/native-smartscribe-workflow.wav"),
        createdAt: Date(timeIntervalSince1970: 1_775_030_000),
        duration: 4,
        sampleRate: 48_000,
        channelCount: 1,
        suggestedTitle: "Workflow note"
    )
    let engine = SuccessfulTranscriptionEngine(
        text: "Workflow transcript.",
        expectedLastPathComponent: "native-smartscribe-workflow.wav"
    )
    let workflow = RecordingTranscriptionWorkflow(noteStore: store, engine: engine)

    let noteID = await workflow.transcribeRecording(recording, now: recording.createdAt)

    let note = store.notes.first { $0.id == noteID }
    #expect(note?.title == "Workflow note")
    #expect(note?.rawText == "Workflow transcript.")
    #expect(note?.transcriptionStatus.phase == .completed)
    #expect(note?.transcriptionStatus.backendName == "Successful Test Engine")
    #expect(store.selection == noteID)
}

@MainActor
@Test
func recordingTranscriptionWorkflowStoresFailureStatus() async {
    let store = NoteStore()
    let recording = AudioRecording(
        fileURL: URL(fileURLWithPath: "/tmp/native-smartscribe-failure.wav"),
        createdAt: Date(timeIntervalSince1970: 1_775_040_000),
        duration: 4,
        sampleRate: 48_000,
        channelCount: 1,
        suggestedTitle: "Failure note"
    )
    let workflow = RecordingTranscriptionWorkflow(
        noteStore: store,
        engine: FailingTranscriptionEngine()
    )

    let noteID = await workflow.transcribeRecording(recording, now: recording.createdAt)

    let note = store.notes.first { $0.id == noteID }
    #expect(note?.rawText == "")
    #expect(note?.transcriptionStatus.phase == .failed)
    #expect(note?.transcriptionStatus.message == "Transcription failed in test.")
    #expect(note?.transcriptionStatus.backendName == "Failing Test Engine")
}

@MainActor
@Test
func recordingTranscriptionWorkflowPassesForcedLanguageCodeToEngine() async {
    let store = NoteStore()
    let recording = AudioRecording(
        fileURL: URL(fileURLWithPath: "/tmp/native-smartscribe-language.wav"),
        createdAt: Date(timeIntervalSince1970: 1_775_050_000),
        duration: 4,
        sampleRate: 48_000,
        channelCount: 1,
        suggestedTitle: "Language note"
    )
    let workflow = RecordingTranscriptionWorkflow(
        noteStore: store,
        engine: LanguageCheckingTranscriptionEngine(expectedLanguageCode: "ru")
    )

    _ = await workflow.transcribeRecording(
        recording,
        forcedLanguageCode: "ru",
        now: recording.createdAt
    )
}

@MainActor
@Test
func recordingTranscriptionWorkflowPassesTranslateToEnglishToEngine() async {
    let store = NoteStore()
    let recording = AudioRecording(
        fileURL: URL(fileURLWithPath: "/tmp/native-smartscribe-translate.wav"),
        createdAt: Date(timeIntervalSince1970: 1_775_060_000),
        duration: 4,
        sampleRate: 48_000,
        channelCount: 1,
        suggestedTitle: "Translate note"
    )
    let workflow = RecordingTranscriptionWorkflow(
        noteStore: store,
        engine: TranslateCheckingTranscriptionEngine()
    )

    _ = await workflow.transcribeRecording(
        recording,
        translateToEnglish: true,
        now: recording.createdAt
    )
}

@MainActor
@Test
func recordingTranscriptionWorkflowAppliesEnabledGlossaryBeforeSavingTranscript() async {
    let store = NoteStore()
    let recording = AudioRecording(
        fileURL: URL(fileURLWithPath: "/tmp/native-smartscribe-glossary.wav"),
        createdAt: Date(timeIntervalSince1970: 1_775_070_000),
        duration: 4,
        sampleRate: 48_000,
        channelCount: 1,
        suggestedTitle: "Glossary note"
    )
    let glossarySettings = GlossarySettings(
        enabled: true,
        entries: [
            GlossaryEntry(
                id: "g1",
                variants: ["Krishna"],
                source: "Kṛṣṇa",
                translation: "Кришна",
                category: "Names",
                translations: [:],
                remember: true,
                createdAt: "",
                updatedAt: ""
            )
        ]
    )
    let workflow = RecordingTranscriptionWorkflow(
        noteStore: store,
        engine: SuccessfulTranscriptionEngine(text: "Krishna spoke."),
        glossarySettingsProvider: { glossarySettings }
    )

    let noteID = await workflow.transcribeRecording(recording, now: recording.createdAt)

    let note = store.notes.first { $0.id == noteID }
    #expect(note?.rawText == "Kṛṣṇa spoke.")
    #expect(note?.transcriptionStatus.phase == .completed)
}

@MainActor
@Test
func recordingTranscriptionWorkflowUsesAuthorTranscriptionLanguageGlossaryTarget() async {
    let store = NoteStore()
    let recording = AudioRecording(
        fileURL: URL(fileURLWithPath: "/tmp/native-smartscribe-author-language-glossary.wav"),
        createdAt: Date(timeIntervalSince1970: 1_775_080_000),
        duration: 4,
        sampleRate: 48_000,
        channelCount: 1,
        suggestedTitle: "Author language glossary note"
    )
    let glossarySettings = GlossarySettings(
        enabled: true,
        authorTranscriptionLanguage: "Russian",
        autoTranslationLanguage: "English",
        entries: [
            GlossaryEntry(
                id: "g1",
                variants: ["Шрила Прабупада"],
                source: "Шрила Прабхупада",
                translation: "Śrīla Prabhupāda",
                category: "Teachers",
                translations: [:],
                remember: true,
                createdAt: "",
                updatedAt: ""
            )
        ]
    )
    let workflow = RecordingTranscriptionWorkflow(
        noteStore: store,
        engine: SuccessfulTranscriptionEngine(text: "Шрила Прабупада spoke."),
        glossarySettingsProvider: { glossarySettings }
    )

    let noteID = await workflow.transcribeRecording(recording, now: recording.createdAt)

    let note = store.notes.first { $0.id == noteID }
    #expect(note?.rawText == "Шрила Прабхупада spoke.")
    #expect(note?.transcriptionStatus.phase == .completed)
}

private struct SuccessfulTranscriptionEngine: TranscriptionEngine {
    let text: String
    var expectedLastPathComponent: String?
    let id = "successful-test-engine"
    let displayName = "Successful Test Engine"

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        if let expectedLastPathComponent {
            #expect(request.audioFileURL?.lastPathComponent == expectedLastPathComponent)
        }
        return TranscriptionResult(
            text: text,
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private struct FailingTranscriptionEngine: TranscriptionEngine {
    let id = "failing-test-engine"
    let displayName = "Failing Test Engine"

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        throw TestTranscriptionError()
    }
}

private struct LanguageCheckingTranscriptionEngine: TranscriptionEngine {
    let expectedLanguageCode: String
    let id = "language-checking-test-engine"
    let displayName = "Language Checking Test Engine"

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        #expect(request.forcedLanguageCode == expectedLanguageCode)
        return TranscriptionResult(
            text: "Language checked.",
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private struct TranslateCheckingTranscriptionEngine: TranscriptionEngine {
    let id = "translate-checking-test-engine"
    let displayName = "Translate Checking Test Engine"

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        #expect(request.translateToEnglish)
        #expect(request.forcedLanguageCode == nil)
        return TranscriptionResult(
            text: "Translated.",
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private struct TestTranscriptionError: LocalizedError, Sendable {
    var errorDescription: String? {
        "Transcription failed in test."
    }
}
