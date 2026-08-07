import Foundation
import NativeBolabolCore
import Testing

@MainActor
@Test
func noteStoreSelectsFirstNoteOnInitialization() {
    let first = BolabolNote(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "First",
        rawText: "One"
    )
    let second = BolabolNote(
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
        fileURL: URL(fileURLWithPath: "/tmp/native-bolabol-test.wav"),
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
    let first = BolabolNote(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
        title: "First",
        rawText: "First transcript"
    )
    let second = BolabolNote(
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
        BolabolNote(title: "One", rawText: "One"),
        BolabolNote(title: "Two", rawText: "Two")
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
        .appendingPathComponent("NativeBolabol-note-store-audio-\(UUID().uuidString)", isDirectory: true)
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
            BolabolNote(title: "Voice", rawText: "hi", audioRecording: recording)
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
func bolabolNotePreviewTextPrefersRawTranscript() {
    let note = BolabolNote(
        title: "Voice Note",
        rawText: "  This is a long transcript that should be visible in the sidebar immediately.  "
    )

    #expect(note.previewText(maxLength: 32) == "This is a long transcript tha...")
}

@Test
func bolabolNotePreviewTextUsesLocalizedBlankFallbackWhenNoteHasNoTitleOrText() {
    let note = BolabolNote(title: "   ", rawText: "")

    #expect(note.previewText() == AppText.localized(.blankNoteFallback, language: .english))
}

@Test
func bolabolNotesCopyAllTextJoinsNonEmptyOutputs() {
    let notes = [
        BolabolNote(
            title: "Newest",
            createdAt: Date(timeIntervalSince1970: 300),
            rawText: "Newest text"
        ),
        BolabolNote(
            title: "Oldest",
            createdAt: Date(timeIntervalSince1970: 100),
            rawText: "Oldest text"
        ),
        BolabolNote(
            title: "Middle",
            createdAt: Date(timeIntervalSince1970: 200),
            rawText: "",
            polishedVariantOne: "Middle polished"
        ),
        BolabolNote(
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

@MainActor
@Test
func audioRetentionLimitCountsOnlyAudioNotesAndPreservesTextNotes() {
    let audio = AudioRecording(
        fileURL: URL(fileURLWithPath: "/tmp/bolabol-retention-audio.caf"),
        duration: 1,
        sampleRate: 48_000,
        channelCount: 1,
        source: .microphone
    )
    let notes = [
        BolabolNote(title: "Newest text", rawText: "newest"),
        BolabolNote(title: "Audio", rawText: "audio", audioRecording: audio),
        BolabolNote(title: "Oldest text", rawText: "oldest")
    ]
    let store = NoteStore(notes: notes)

    store.enforceAudioArchiveLimit(maxRecordings: 1)

    #expect(store.notes == notes)
    #expect(store.audioArchiveStats.count == 1)
}

@MainActor
@Test
func deletingImportedAudioNoteNeverDeletesTheUsersSourceFile() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("NativeBolabol-imported-audio-\(UUID().uuidString)", isDirectory: true)
    let importedDirectory = root.appendingPathComponent("Imports", isDirectory: true)
    try fileManager.createDirectory(at: importedDirectory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let importedFile = importedDirectory.appendingPathComponent("user-source.wav")
    try Data("user audio".utf8).write(to: importedFile)
    let recording = AudioRecording(
        fileURL: importedFile,
        duration: 1,
        sampleRate: 48_000,
        channelCount: 1,
        source: .importedFile
    )
    let note = BolabolNote(title: "Imported", rawText: "text", audioRecording: recording)
    let store = NoteStore(
        notes: [note],
        fileManager: fileManager,
        notesFileURL: root.appendingPathComponent("notes.json"),
        isPersistenceEnabled: true
    )

    store.deleteNote(note.id)

    #expect(fileManager.fileExists(atPath: importedFile.path))
}

@MainActor
@Test
func audioRetentionAndOwnershipMatrixKeepsOrderingAndFilesSafe() throws {
    let fileManager = FileManager.default

    func makeRoot(_ name: String) throws -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("NativeBolabol-\(name)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func makeRecording(
        root: URL,
        name: String,
        source: AudioRecording.Source,
        directoryName: String? = nil
    ) throws -> AudioRecording {
        let directory = root.appendingPathComponent(
            directoryName ?? (source == .importedFile ? "Imports" : "Recordings"),
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(name)
        try Data(name.utf8).write(to: fileURL)
        return AudioRecording(
            fileURL: fileURL,
            duration: 1,
            sampleRate: 48_000,
            channelCount: 1,
            source: source
        )
    }

    func makeStore(root: URL, notes: [BolabolNote]) -> NoteStore {
        NoteStore(
            notes: notes,
            fileManager: fileManager,
            notesFileURL: root.appendingPathComponent("notes.json"),
            isPersistenceEnabled: true
        )
    }

    let textOnly = NoteStore(notes: [
        BolabolNote(title: "Text 1", rawText: "one"),
        BolabolNote(title: "Text 2", rawText: "two")
    ])
    textOnly.enforceAudioArchiveLimit(maxRecordings: 0)
    #expect(textOnly.notes.count == 2)

    let oneAudioRoot = try makeRoot("one-audio")
    defer { try? fileManager.removeItem(at: oneAudioRoot) }
    let oneAudio = try makeRecording(root: oneAudioRoot, name: "one.caf", source: .microphone)
    let oneAudioNotes = [
        BolabolNote(title: "Newest text", rawText: "text"),
        BolabolNote(title: "Audio", rawText: "audio", audioRecording: oneAudio),
        BolabolNote(title: "Oldest text", rawText: "text")
    ]
    let oneAudioStore = makeStore(root: oneAudioRoot, notes: oneAudioNotes)
    oneAudioStore.enforceAudioArchiveLimit(maxRecordings: 1)
    #expect(oneAudioStore.notes == oneAudioNotes)
    #expect(fileManager.fileExists(atPath: oneAudio.fileURL.path))

    let orderingRoot = try makeRoot("ordering")
    defer { try? fileManager.removeItem(at: orderingRoot) }
    let newestAudio = try makeRecording(root: orderingRoot, name: "newest.caf", source: .microphone)
    let olderAudio = try makeRecording(root: orderingRoot, name: "older.caf", source: .microphone)
    let oldestAudio = try makeRecording(root: orderingRoot, name: "oldest.caf", source: .microphone)
    let orderedNotes = [
        BolabolNote(title: "Newest text", rawText: "text"),
        BolabolNote(title: "Newest audio", rawText: "audio", audioRecording: newestAudio),
        BolabolNote(title: "Middle text", rawText: "text"),
        BolabolNote(title: "Older audio", rawText: "audio", audioRecording: olderAudio),
        BolabolNote(title: "Oldest audio", rawText: "audio", audioRecording: oldestAudio)
    ]
    let orderedStore = makeStore(root: orderingRoot, notes: orderedNotes)
    orderedStore.enforceAudioArchiveLimit(maxRecordings: 2)
    #expect(orderedStore.notes.contains { $0.audioRecording == newestAudio })
    #expect(orderedStore.notes.contains { $0.audioRecording == olderAudio })
    #expect(!orderedStore.notes.contains { $0.audioRecording == oldestAudio })
    #expect(orderedStore.notes.contains { $0.title == "Newest text" })
    #expect(orderedStore.notes.contains { $0.title == "Middle text" })
    #expect(!fileManager.fileExists(atPath: oldestAudio.fileURL.path))
    #expect(fileManager.fileExists(atPath: newestAudio.fileURL.path))
    #expect(fileManager.fileExists(atPath: olderAudio.fileURL.path))

    let exactRoot = try makeRoot("exact")
    defer { try? fileManager.removeItem(at: exactRoot) }
    let exactAudio = try makeRecording(root: exactRoot, name: "exact.caf", source: .microphone)
    let exactStore = makeStore(
        root: exactRoot,
        notes: [BolabolNote(title: "Exact", rawText: "", audioRecording: exactAudio)]
    )
    exactStore.enforceAudioArchiveLimit(maxRecordings: 1)
    #expect(exactStore.audioArchiveStats.count == 1)
    #expect(fileManager.fileExists(atPath: exactAudio.fileURL.path))

    let zeroRoot = try makeRoot("zero")
    defer { try? fileManager.removeItem(at: zeroRoot) }
    let zeroAudio = try makeRecording(root: zeroRoot, name: "zero.caf", source: .microphone)
    let zeroStore = makeStore(
        root: zeroRoot,
        notes: [
            BolabolNote(title: "Text", rawText: "keep"),
            BolabolNote(title: "Audio", rawText: "remove", audioRecording: zeroAudio)
        ]
    )
    zeroStore.enforceAudioArchiveLimit(maxRecordings: 0)
    #expect(zeroStore.notes.count == 1)
    #expect(zeroStore.notes.first?.title == "Text")
    #expect(!fileManager.fileExists(atPath: zeroAudio.fileURL.path))
    let reloadedZeroStore = NoteStore(
        notes: nil,
        fileManager: fileManager,
        notesFileURL: zeroRoot.appendingPathComponent("notes.json"),
        isPersistenceEnabled: true
    )
    #expect(reloadedZeroStore.notes == zeroStore.notes)

    let importedRoot = try makeRoot("imported-retention")
    defer { try? fileManager.removeItem(at: importedRoot) }
    let imported = try makeRecording(
        root: importedRoot,
        name: "source.wav",
        source: .importedFile,
        directoryName: "Recordings"
    )
    let importedStore = makeStore(
        root: importedRoot,
        notes: [BolabolNote(title: "Imported", rawText: "", audioRecording: imported)]
    )
    importedStore.enforceAudioArchiveLimit(maxRecordings: 0)
    #expect(importedStore.notes.isEmpty)
    #expect(fileManager.fileExists(atPath: imported.fileURL.path))
    #expect(importedStore.purgeOrphanedRecordings() == 0)
    let reloadedImportedStore = NoteStore(
        notes: nil,
        fileManager: fileManager,
        notesFileURL: importedRoot.appendingPathComponent("notes.json"),
        isPersistenceEnabled: true
    )
    #expect(reloadedImportedStore.purgeOrphanedRecordings() == 0)
    #expect(fileManager.fileExists(atPath: imported.fileURL.path))
    importedStore.clearAll()
    #expect(fileManager.fileExists(atPath: imported.fileURL.path))

    let duplicateRoot = try makeRoot("duplicate")
    defer { try? fileManager.removeItem(at: duplicateRoot) }
    let duplicate = try makeRecording(root: duplicateRoot, name: "duplicate.caf", source: .microphone)
    let duplicateStore = makeStore(
        root: duplicateRoot,
        notes: [
            BolabolNote(title: "Newest", rawText: "", audioRecording: duplicate),
            BolabolNote(title: "Older", rawText: "", audioRecording: duplicate)
        ]
    )
    duplicateStore.enforceAudioArchiveLimit(maxRecordings: 1)
    #expect(duplicateStore.audioArchiveStats.count == 1)
    #expect(fileManager.fileExists(atPath: duplicate.fileURL.path))
    duplicateStore.deleteNote(duplicateStore.notes[0].id)
    #expect(!fileManager.fileExists(atPath: duplicate.fileURL.path))

    let traversalRoot = try makeRoot("ownership")
    defer { try? fileManager.removeItem(at: traversalRoot) }
    let recordingsDirectory = traversalRoot.appendingPathComponent("Recordings", isDirectory: true)
    try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
    let outsideFile = traversalRoot.appendingPathComponent("outside.caf")
    try Data("outside".utf8).write(to: outsideFile)
    let traversalURL = recordingsDirectory
        .appendingPathComponent("..", isDirectory: true)
        .appendingPathComponent("outside.caf")
    let traversalRecording = AudioRecording(
        fileURL: traversalURL,
        duration: 1,
        sampleRate: 48_000,
        channelCount: 1,
        source: .microphone
    )
    let traversalStore = makeStore(
        root: traversalRoot,
        notes: [BolabolNote(title: "Traversal", rawText: "", audioRecording: traversalRecording)]
    )
    traversalStore.deleteNote(traversalStore.notes[0].id)
    #expect(fileManager.fileExists(atPath: outsideFile.path))

    let symlinkTarget = traversalRoot.appendingPathComponent("symlink-target.caf")
    try Data("target".utf8).write(to: symlinkTarget)
    let symlinkURL = recordingsDirectory.appendingPathComponent("linked.caf")
    try fileManager.createSymbolicLink(at: symlinkURL, withDestinationURL: symlinkTarget)
    let symlinkRecording = AudioRecording(
        fileURL: symlinkURL,
        duration: 1,
        sampleRate: 48_000,
        channelCount: 1,
        source: .microphone
    )
    let symlinkStore = makeStore(
        root: traversalRoot,
        notes: [BolabolNote(title: "Symlink", rawText: "", audioRecording: symlinkRecording)]
    )
    symlinkStore.deleteNote(symlinkStore.notes[0].id)
    #expect(fileManager.fileExists(atPath: symlinkTarget.path))
    #expect(fileManager.fileExists(atPath: symlinkURL.path))
}
