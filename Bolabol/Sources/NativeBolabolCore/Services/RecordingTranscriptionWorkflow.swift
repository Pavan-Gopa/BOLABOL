import Foundation

@MainActor
public final class RecordingTranscriptionWorkflow {
    private let noteStore: NoteStore
    private let engine: any TranscriptionEngine
    private let glossarySettingsProvider: @MainActor () -> GlossarySettings

    public init(
        noteStore: NoteStore,
        engine: any TranscriptionEngine,
        glossarySettingsProvider: @escaping @MainActor () -> GlossarySettings = { GlossarySettings(enabled: false, entries: []) }
    ) {
        self.noteStore = noteStore
        self.engine = engine
        self.glossarySettingsProvider = glossarySettingsProvider
    }

    @discardableResult
    public func transcribeRecording(
        _ recording: AudioRecording,
        forcedLanguageCode: String? = nil,
        translateToEnglish: Bool = false,
        now: Date = .now
    ) async -> BolabolNote.ID {
        let note = noteStore.addRecordedNote(recording: recording, now: now)
        noteStore.markTranscriptionStarted(for: note.id, backendName: engine.displayName)

        await transcribe(
            noteID: note.id,
            request: TranscriptionRequest(
                audioFileURL: recording.fileURL,
                forcedLanguageCode: forcedLanguageCode,
                translateToEnglish: translateToEnglish
            )
        )

        return note.id
    }

    /// Transcribes through the frozen S11 plan. The engine identity check is
    /// deliberately before the engine call so a stale route cannot reach a
    /// newly selected model instance.
    @discardableResult
    public func transcribeRecording(
        _ recording: AudioRecording,
        plan: TranscriptionSessionPlan,
        now: Date = .now
    ) async -> BolabolNote.ID {
        let note = noteStore.addRecordedNote(recording: recording, now: now)
        guard engine.id == plan.engineIdentity else {
            noteStore.markTranscriptionFailed(
                for: note.id,
                message: TranscriptionSessionUnavailableReason.engineIdentityMismatch(
                    modelID: plan.modelID
                ).localizedDescription,
                backendName: engine.displayName
            )
            return note.id
        }

        noteStore.markTranscriptionStarted(for: note.id, backendName: engine.displayName)
        await transcribe(noteID: note.id, request: plan.request(audioFileURL: recording.fileURL))
        return note.id
    }

    /// Records an honest failed note for an unavailable plan without invoking
    /// any transcription engine.
    @discardableResult
    public func transcribeRecording(
        _ recording: AudioRecording,
        resolution: TranscriptionSessionResolution,
        now: Date = .now
    ) async -> BolabolNote.ID {
        switch resolution {
        case .available(let plan):
            guard engine.id == plan.engineIdentity else {
                return recordUnavailableSession(
                    recording,
                    reason: .engineIdentityMismatch(modelID: plan.modelID),
                    now: now
                )
            }
            return await transcribeRecording(recording, plan: plan, now: now)
        case .unavailable(let reason):
            return recordUnavailableSession(recording, reason: reason, now: now)
        }
    }

    /// Audio-only entry point used by the translation recording path. It still
    /// consumes the same immutable request plan but does not create a note.
    public func transcribeAudio(
        audioFileURL: URL?,
        plan: TranscriptionSessionPlan
    ) async throws -> TranscriptionResult {
        guard engine.id == plan.engineIdentity else {
            throw TranscriptionSessionUnavailableReason.engineIdentityMismatch(
                modelID: plan.modelID
            )
        }
        return try await engine.transcribe(plan.request(audioFileURL: audioFileURL))
    }

    public func transcribeAudio(
        audioFileURL: URL?,
        resolution: TranscriptionSessionResolution
    ) async throws -> TranscriptionResult {
        switch resolution {
        case .available(let plan):
            try await transcribeAudio(audioFileURL: audioFileURL, plan: plan)
        case .unavailable(let reason):
            throw reason
        }
    }

    public func retranscribeExistingNote(
        noteID: BolabolNote.ID,
        audioFileURL: URL,
        forcedLanguageCode: String? = nil,
        translateToEnglish: Bool = false
    ) async {
        noteStore.markTranscriptionStarted(for: noteID, backendName: engine.displayName)

        await transcribe(
            noteID: noteID,
            request: TranscriptionRequest(
                audioFileURL: audioFileURL,
                forcedLanguageCode: forcedLanguageCode,
                translateToEnglish: translateToEnglish
            )
        )
    }

    public func retranscribeExistingNote(
        noteID: BolabolNote.ID,
        audioFileURL: URL,
        plan: TranscriptionSessionPlan
    ) async {
        guard engine.id == plan.engineIdentity else {
            noteStore.markTranscriptionFailed(
                for: noteID,
                message: TranscriptionSessionUnavailableReason.engineIdentityMismatch(
                    modelID: plan.modelID
                ).localizedDescription,
                backendName: engine.displayName
            )
            return
        }

        noteStore.markTranscriptionStarted(for: noteID, backendName: engine.displayName)
        await transcribe(noteID: noteID, request: plan.request(audioFileURL: audioFileURL))
    }

    public func retranscribeExistingNote(
        noteID: BolabolNote.ID,
        audioFileURL: URL,
        resolution: TranscriptionSessionResolution
    ) async {
        switch resolution {
        case .available(let plan):
            await retranscribeExistingNote(
                noteID: noteID,
                audioFileURL: audioFileURL,
                plan: plan
            )
        case .unavailable(let reason):
            noteStore.markTranscriptionFailed(
                for: noteID,
                message: reason.localizedDescription,
                backendName: "Unavailable session"
            )
        }
    }

    @discardableResult
    public func recordUnavailableSession(
        _ recording: AudioRecording,
        reason: TranscriptionSessionUnavailableReason,
        now: Date = .now
    ) -> BolabolNote.ID {
        let note = noteStore.addRecordedNote(recording: recording, now: now)
        noteStore.markTranscriptionFailed(
            for: note.id,
            message: reason.localizedDescription,
            backendName: "Unavailable session"
        )
        return note.id
    }

    private func transcribe(
        noteID: BolabolNote.ID,
        request: TranscriptionRequest
    ) async {
        do {
            let result = try await engine.transcribe(request)
            let glossarySettings = glossarySettingsProvider()
            let rewritten = glossarySettings.enabled
                ? GlossaryTextRewriter.apply(
                    to: result.text,
                    entries: glossarySettings.entries,
                    target: .source
                )
                : GlossaryTextRewriter.Result(text: result.text, count: 0)
            noteStore.applyTranscriptionResult(
                for: noteID,
                result: TranscriptionResult(
                    text: rewritten.text,
                    diagnostics: result.diagnostics
                )
            )
        } catch {
            noteStore.markTranscriptionFailed(
                for: noteID,
                message: error.localizedDescription,
                backendName: engine.displayName
            )
        }
    }
}
