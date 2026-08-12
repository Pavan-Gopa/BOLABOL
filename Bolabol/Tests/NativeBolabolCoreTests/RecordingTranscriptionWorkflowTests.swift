import Foundation
import NativeBolabolCore
import Testing

@MainActor
@Test
func recordingTranscriptionWorkflowCreatesNoteAndStoresTranscript() async {
    let store = NoteStore()
    let recording = AudioRecording(
        fileURL: URL(fileURLWithPath: "/tmp/native-bolabol-workflow.wav"),
        createdAt: Date(timeIntervalSince1970: 1_775_030_000),
        duration: 4,
        sampleRate: 48_000,
        channelCount: 1,
        suggestedTitle: "Workflow note"
    )
    let engine = SuccessfulTranscriptionEngine(
        text: "Workflow transcript.",
        expectedLastPathComponent: "native-bolabol-workflow.wav"
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
        fileURL: URL(fileURLWithPath: "/tmp/native-bolabol-failure.wav"),
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
        fileURL: URL(fileURLWithPath: "/tmp/native-bolabol-language.wav"),
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
        fileURL: URL(fileURLWithPath: "/tmp/native-bolabol-translate.wav"),
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
func recordingTranscriptionWorkflowPassesTheExactS11PlanRequest() async throws {
    let store = NoteStore()
    let recording = AudioRecording(
        fileURL: URL(fileURLWithPath: "/tmp/native-bolabol-plan.wav"),
        createdAt: Date(timeIntervalSince1970: 1_775_065_000),
        duration: 4,
        sampleRate: 48_000,
        channelCount: 1,
        suggestedTitle: "Plan note"
    )
    let model = try #require(
        TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-180m-flash-coreml")
    )
    let resolution = TranscriptionSessionResolver.resolve(
        activeModel: model,
        modelFolderURL: URL(fileURLWithPath: "/tmp/bolabol-plan-model"),
        engineIdentity: "workflow-plan-engine",
        currentOSVersion: ASRModelCapabilities.OSVersion(majorVersion: 15),
        hasCompleteModel: true,
        primaryLanguageCode: "de",
        additionalLanguageCode: "en",
        operation: .asr
    )
    guard case .available(let plan) = resolution else {
        Issue.record("Expected a valid Flash session plan")
        return
    }

    let engine = CapturingTranscriptionEngine(id: "workflow-plan-engine")
    let workflow = RecordingTranscriptionWorkflow(noteStore: store, engine: engine)
    _ = await workflow.transcribeRecording(recording, plan: plan, now: recording.createdAt)

    #expect(engine.calls == 1)
    #expect(engine.lastRequest?.audioFileURL == recording.fileURL)
    #expect(engine.lastRequest?.forcedLanguageCode == "de")
    #expect(engine.lastRequest?.translateToEnglish == false)
}

@MainActor
@Test
func recordingTranscriptionWorkflowDoesNotCallEngineForUnavailableSession() async {
    let store = NoteStore()
    let recording = AudioRecording(
        fileURL: URL(fileURLWithPath: "/tmp/native-bolabol-unavailable.wav"),
        createdAt: Date(timeIntervalSince1970: 1_775_066_000),
        duration: 4,
        sampleRate: 48_000,
        channelCount: 1,
        suggestedTitle: "Unavailable note"
    )
    let engine = CapturingTranscriptionEngine(id: "must-not-call")
    let workflow = RecordingTranscriptionWorkflow(noteStore: store, engine: engine)
    let reason = TranscriptionSessionUnavailableReason.englishSourceRequired(
        modelID: "canary-1b-v2-coreml"
    )

    let noteID = await workflow.transcribeRecording(
        recording,
        resolution: .unavailable(reason),
        now: recording.createdAt
    )

    #expect(engine.calls == 0)
    #expect(store.note(withID: noteID)?.transcriptionStatus.phase == .failed)
}

@MainActor
@Test
func recordingTranscriptionWorkflowDoesNotCallEngineForTypedNonWhisperTranslation() async throws {
    let store = NoteStore()
    let recording = AudioRecording(
        fileURL: URL(fileURLWithPath: "/tmp/native-bolabol-typed-unavailable.wav"),
        createdAt: Date(timeIntervalSince1970: 1_775_066_500),
        duration: 4,
        sampleRate: 48_000,
        channelCount: 1,
        suggestedTitle: "Typed unavailable note"
    )
    let model = try #require(
        TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-180m-flash-coreml")
    )
    let resolution = TranscriptionSessionResolver.resolve(
        activeModel: model,
        currentOSVersion: ASRModelCapabilities.OSVersion(majorVersion: 15),
        hasCompleteModel: true,
        primaryLanguageCode: "en",
        additionalLanguageCode: "de",
        operation: .whisperTargetTranslation(languageCode: "en")
    )
    let engine = CapturingTranscriptionEngine(id: "must-not-call-typed")
    let workflow = RecordingTranscriptionWorkflow(noteStore: store, engine: engine)

    let noteID = await workflow.transcribeRecording(
        recording,
        resolution: resolution,
        now: recording.createdAt
    )

    #expect(engine.calls == 0)
    #expect(store.note(withID: noteID)?.transcriptionStatus.phase == .failed)
}

@MainActor
@Test
func recordingTranscriptionWorkflowRejectsEngineIdentityMismatchBeforeCall() async throws {
    let store = NoteStore()
    let recording = AudioRecording(
        fileURL: URL(fileURLWithPath: "/tmp/native-bolabol-mismatch.wav"),
        createdAt: Date(timeIntervalSince1970: 1_775_067_000),
        duration: 4,
        sampleRate: 48_000,
        channelCount: 1,
        suggestedTitle: "Mismatch note"
    )
    let model = try #require(
        TranscriptionModelCatalog.nativeWhisperKit.model(withID: "gigaam-v3-rnnt-coreml")
    )
    let resolution = TranscriptionSessionResolver.resolve(
        activeModel: model,
        modelFolderURL: URL(fileURLWithPath: "/tmp/bolabol-mismatch-model"),
        engineIdentity: "plan-engine",
        currentOSVersion: ASRModelCapabilities.OSVersion(majorVersion: 15),
        hasCompleteModel: true,
        primaryLanguageCode: "en",
        additionalLanguageCode: "ru",
        operation: .asr
    )
    guard case .available(let plan) = resolution else {
        Issue.record("Expected a valid GigaAM session plan")
        return
    }

    let engine = CapturingTranscriptionEngine(id: "different-engine")
    let workflow = RecordingTranscriptionWorkflow(noteStore: store, engine: engine)
    let noteID = await workflow.transcribeRecording(recording, plan: plan, now: recording.createdAt)

    #expect(engine.calls == 0)
    #expect(store.note(withID: noteID)?.transcriptionStatus.phase == .failed)
}

@MainActor
@Test
func recordingTranscriptionWorkflowAppliesEnabledGlossaryBeforeSavingTranscript() async {
    let store = NoteStore()
    let recording = AudioRecording(
        fileURL: URL(fileURLWithPath: "/tmp/native-bolabol-glossary.wav"),
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
        fileURL: URL(fileURLWithPath: "/tmp/native-bolabol-author-language-glossary.wav"),
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

private final class CapturingTranscriptionEngine: @unchecked Sendable, TranscriptionEngine {
    let id: String
    let displayName = "Capturing Test Engine"
    private(set) var calls = 0
    private(set) var lastRequest: TranscriptionRequest?

    init(id: String) {
        self.id = id
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        calls += 1
        lastRequest = request
        return TranscriptionResult(
            text: "Captured.",
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private struct TestTranscriptionError: LocalizedError, Sendable {
    var errorDescription: String? {
        "Transcription failed in test."
    }
}
