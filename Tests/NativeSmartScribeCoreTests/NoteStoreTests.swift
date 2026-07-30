import Foundation
import NativeSmartScribeCore
import Testing

@MainActor
@Test
func noteStoreSelectsFirstNoteOnInitialization() {
    let first = SmartScribeNote(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "First",
        rawText: "One"
    )
    let second = SmartScribeNote(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        title: "Second",
        rawText: "Two"
    )

    let store = NoteStore(notes: [first, second])

    #expect(store.selection == first.id)
    #expect(store.selectedNote == first)
}

@MainActor
@Test
func noteStoreAddsEmptyNoteAtTopAndSelectsIt() {
    let store = NoteStore()
    let now = Date(timeIntervalSince1970: 1_775_010_000)

    let note = store.addEmptyNote(now: now)

    #expect(store.notes.first == note)
    #expect(store.selection == note.id)
    #expect(note.title == "Untitled Note")
    #expect(note.createdAt == now)
}

@MainActor
@Test
func noteStoreAddsRecordedNoteAtTopAndSelectsIt() {
    let store = NoteStore()
    let now = Date(timeIntervalSince1970: 1_775_020_000)
    let recording = AudioRecording(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000100")!,
        fileURL: URL(fileURLWithPath: "/tmp/native-smartscribe-test.wav"),
        createdAt: now,
        duration: 12.5,
        sampleRate: 48_000,
        channelCount: 1,
        fileSizeBytes: 1024,
        suggestedTitle: "Recorded note"
    )

    let note = store.addRecordedNote(recording: recording, now: now)

    #expect(store.notes.first == note)
    #expect(store.selection == note.id)
    #expect(note.title == "Recorded note")
    #expect(note.createdAt == now)
    #expect(note.rawText == "")
    #expect(note.audioRecording == recording)
    #expect(note.transcriptionStatus.phase == .pending)
}

@MainActor
@Test
func noteStoreAppliesTranscriptionResult() {
    let store = NoteStore()
    let note = store.addEmptyNote()
    let result = TranscriptionResult(
        text: "This is the native transcript.",
        diagnostics: EngineDiagnostics(backendName: "Unit Test Engine")
    )

    store.applyTranscriptionResult(for: note.id, result: result)

    #expect(store.selectedNote?.rawText == "This is the native transcript.")
    #expect(store.selectedNote?.transcriptionStatus.phase == .completed)
    #expect(store.selectedNote?.transcriptionStatus.backendName == "Unit Test Engine")
}

@MainActor
@Test
func noteStoreUpdatesRawTextForBlankNotes() {
    let store = NoteStore()
    let note = store.addEmptyNote()

    store.updateRawText(for: note.id, text: "Text pasted into a blank note.")

    #expect(store.selectedNote?.rawText == "Text pasted into a blank note.")
    #expect(store.selectedNote?.title == "Untitled Note")
}

@MainActor
@Test
func noteStoreUpdatesVariantOneTextManually() {
    let store = NoteStore()
    let note = store.addEmptyNote()

    store.updateText(for: note.id, variant: .variantOne, text: "Manual variant one edit.")

    #expect(store.selectedNote?.polishedVariantOne == "Manual variant one edit.")
}

@MainActor
@Test
func noteStoreUpdatesVariantTwoTextManually() {
    let store = NoteStore()
    let note = store.addEmptyNote()

    store.updateText(for: note.id, variant: .variantTwo, text: "Manual variant two edit.")

    #expect(store.selectedNote?.polishedVariantTwo == "Manual variant two edit.")
}

@MainActor
@Test
func noteStoreDeletesSelectedNoteAndSelectsNextAvailableNote() {
    let first = SmartScribeNote(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
        title: "First",
        rawText: "First transcript"
    )
    let second = SmartScribeNote(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
        title: "Second",
        rawText: "Second transcript"
    )
    let store = NoteStore(notes: [first, second])

    store.deleteNote(first.id)

    #expect(store.notes == [second])
    #expect(store.selection == second.id)
}

@MainActor
@Test
func noteStoreClearsAllNotesAndSelection() {
    let store = NoteStore(notes: [
        SmartScribeNote(title: "One", rawText: "One"),
        SmartScribeNote(title: "Two", rawText: "Two")
    ])

    store.clearAll()

    #expect(store.notes.isEmpty)
    #expect(store.selection == nil)
}

@MainActor
@Test
func noteStoreClearAllAndPurgeRemoveMicrophoneRecordingsAndOrphans() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("NativeSmartScribe-note-store-audio-\(UUID().uuidString)", isDirectory: true)
    let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try fileManager.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let linked = recordings.appendingPathComponent("linked.caf")
    let orphan = recordings.appendingPathComponent("orphan.caf")
    try Data("linked".utf8).write(to: linked)
    try Data("orphan".utf8).write(to: orphan)

    let notesURL = root.appendingPathComponent("notes.json")
    let recording = AudioRecording(
        fileURL: linked,
        duration: 1,
        sampleRate: 48_000,
        channelCount: 1,
        source: .microphone
    )
    let store = NoteStore(
        notes: [
            SmartScribeNote(title: "Voice", rawText: "hi", audioRecording: recording)
        ],
        fileManager: fileManager,
        notesFileURL: notesURL,
        isPersistenceEnabled: true
    )

    #expect(store.purgeOrphanedRecordings() == 1)
    #expect(fileManager.fileExists(atPath: linked.path))
    #expect(!fileManager.fileExists(atPath: orphan.path))

    store.clearAll()
    #expect(store.notes.isEmpty)
    #expect(!fileManager.fileExists(atPath: linked.path))
    #expect(!fileManager.fileExists(atPath: orphan.path))
}

@Test
func smartScribeNotePreviewTextPrefersRawTranscript() {
    let note = SmartScribeNote(
        title: "Voice Note",
        rawText: "  This is a long transcript that should be visible in the sidebar immediately.  "
    )

    #expect(note.previewText(maxLength: 32) == "This is a long transcript tha...")
}

@Test
func smartScribeNotePreviewTextUsesLocalizedBlankFallbackWhenNoteHasNoTitleOrText() {
    let note = SmartScribeNote(title: "   ", rawText: "")

    #expect(note.previewText() == AppText.localized(.blankNoteFallback, language: .english))
}

@Test
func smartScribeNotesCopyAllTextJoinsNonEmptyOutputs() {
    let notes = [
        SmartScribeNote(
            title: "Newest",
            createdAt: Date(timeIntervalSince1970: 300),
            rawText: "Newest text"
        ),
        SmartScribeNote(
            title: "Oldest",
            createdAt: Date(timeIntervalSince1970: 100),
            rawText: "Oldest text"
        ),
        SmartScribeNote(
            title: "Middle",
            createdAt: Date(timeIntervalSince1970: 200),
            rawText: "",
            polishedVariantOne: "Middle polished"
        ),
        SmartScribeNote(
            title: "Blank",
            createdAt: Date(timeIntervalSince1970: 50),
            rawText: ""
        )
    ]

    #expect(notes.copyAllText() == "Oldest text\n\nMiddle polished\n\nNewest text")
}

@MainActor
@Test
func noteStoreMarksTranscriptionFailure() {
    let store = NoteStore()
    let note = store.addEmptyNote()

    store.markTranscriptionFailed(
        for: note.id,
        message: "The local engine failed.",
        backendName: "Unit Test Engine"
    )

    #expect(store.selectedNote?.transcriptionStatus.phase == .failed)
    #expect(store.selectedNote?.transcriptionStatus.message == "The local engine failed.")
    #expect(store.selectedNote?.transcriptionStatus.backendName == "Unit Test Engine")
}

@MainActor
@Test
func noteStoreAppliesPolishingResultToVariantOne() {
    let store = NoteStore()
    let note = store.addEmptyNote()
    let result = PolishingResult(
        text: "Cleaned transcript.",
        diagnostics: EngineDiagnostics(backendName: "Unit Test Polish")
    )

    store.applyPolishingResult(for: note.id, variant: .variantOne, result: result)

    #expect(store.selectedNote?.polishedVariantOne == "Cleaned transcript.")
    #expect(store.selectedNote?.polishingStatus(for: .variantOne).phase == .completed)
    #expect(store.selectedNote?.polishingStatus(for: .variantOne).backendName == "Unit Test Polish")
}

@MainActor
@Test
func noteStoreMarksPolishingFailureForVariantTwo() {
    let store = NoteStore()
    let note = store.addEmptyNote()

    store.markPolishingFailed(
        for: note.id,
        variant: .variantTwo,
        message: "Local polishing failed.",
        backendName: "Unit Test Polish"
    )

    #expect(store.selectedNote?.polishingStatus(for: .variantTwo).phase == .failed)
    #expect(store.selectedNote?.polishingStatus(for: .variantTwo).message == "Local polishing failed.")
    #expect(store.selectedNote?.polishingStatus(for: .variantTwo).backendName == "Unit Test Polish")
}

@MainActor
@Test
func noteStorePersistenceSavesAndLoadsCorrectly() throws {
    let fileManager = FileManager.default
    let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer {
        try? fileManager.removeItem(at: tempURL)
    }

    let store1 = NoteStore(notes: [], fileManager: fileManager, notesFileURL: tempURL, isPersistenceEnabled: true)
    let note = store1.addEmptyNote(title: "Persistent Note")

    let store2 = NoteStore(notes: [], fileManager: fileManager, notesFileURL: tempURL, isPersistenceEnabled: true)
    #expect(store2.notes.isEmpty)

    let store3 = NoteStore(notes: nil, fileManager: fileManager, notesFileURL: tempURL, isPersistenceEnabled: true)
    #expect(store3.notes.count == 1)
    #expect(store3.notes.first?.title == "Persistent Note")
    #expect(store3.notes.first?.id == note.id)
    #expect(store3.selection == note.id)
}

