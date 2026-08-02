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
    ) async -> BlaboomNote.ID {
        let note = noteStore.addRecordedNote(recording: recording, now: now)
        noteStore.markTranscriptionStarted(for: note.id, backendName: engine.displayName)

        do {
            let result = try await engine.transcribe(
                TranscriptionRequest(
                    audioFileURL: recording.fileURL,
                    forcedLanguageCode: forcedLanguageCode,
                    translateToEnglish: translateToEnglish
                )
            )
            let glossarySettings = glossarySettingsProvider()
            let rewritten = glossarySettings.enabled
                ? GlossaryTextRewriter.apply(
                    to: result.text,
                    entries: glossarySettings.entries,
                    target: .source
                )
                : GlossaryTextRewriter.Result(text: result.text, count: 0)
            noteStore.applyTranscriptionResult(
                for: note.id,
                result: TranscriptionResult(
                    text: rewritten.text,
                    diagnostics: result.diagnostics
                )
            )
        } catch {
            noteStore.markTranscriptionFailed(
                for: note.id,
                message: error.localizedDescription,
                backendName: engine.displayName
            )
        }

        return note.id
    }

    public func retranscribeExistingNote(
        noteID: BlaboomNote.ID,
        audioFileURL: URL,
        forcedLanguageCode: String? = nil,
        translateToEnglish: Bool = false
    ) async {
        noteStore.markTranscriptionStarted(for: noteID, backendName: engine.displayName)

        do {
            let result = try await engine.transcribe(
                TranscriptionRequest(
                    audioFileURL: audioFileURL,
                    forcedLanguageCode: forcedLanguageCode,
                    translateToEnglish: translateToEnglish
                )
            )
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
