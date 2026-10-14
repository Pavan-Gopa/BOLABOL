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
func noteStoreClearsAllNotesAndSelection() throws {
    // S11: destructive fixtures own a unique root. Explicit nonpersistent
    // stores may clean only their own nondefault root — never default audio.
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("NativeBolabol-clearall-text-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }
    let store = NoteStore(
        notes: [
            BolabolNote(title: "One", rawText: "One"),
            BolabolNote(title: "Two", rawText: "Two")
        ],
        fileManager: fileManager,
        notesFileURL: root.appendingPathComponent("notes.json")
    )

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
    try fileManager.setAttributes(
        [.modificationDate: Date.now.addingTimeInterval(-1200)],
        ofItemAtPath: orphan.path
    )
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
    // S11: metadata lives in a unique owned directory so the derived
    // Recordings root is private, not the shared temporary directory.
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("NativeBolabol-persistence-roundtrip-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: root)
    }
    let tempURL = root.appendingPathComponent("notes.json")

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

@MainActor
@Test
func corruptMetadataEntersGuardedStateAndPerformsNoDeletions() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("NativeBolabol-corrupt-guard-\(UUID().uuidString)", isDirectory: true)
    let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try fileManager.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let audioFile = recordings.appendingPathComponent("precious_audio.caf")
    try Data("precious_audio_bytes".utf8).write(to: audioFile)
    // Backdate the audio file so age guard alone would not prevent deletion
    try fileManager.setAttributes(
        [.modificationDate: Date.now.addingTimeInterval(-3600)],
        ofItemAtPath: audioFile.path
    )

    let notesURL = root.appendingPathComponent("notes.json")
    let corruptData = Data("{ corrupt_json: true, ...".utf8)
    try corruptData.write(to: notesURL)

    let store = NoteStore(
        notes: nil,
        fileManager: fileManager,
        notesFileURL: notesURL,
        isPersistenceEnabled: true
    )

    #expect(store.loadState.isGuarded)
    #expect(store.isDestructiveMaintenanceGuarded)
    #expect(store.loadErrorDescription != nil)
    #expect(store.notes.isEmpty)
    #expect(fileManager.fileExists(atPath: audioFile.path))

    // All destructive operations must be safely refused
    #expect(store.purgeOrphanedRecordings() == 0)
    #expect(fileManager.fileExists(atPath: audioFile.path))

    store.enforceAudioArchiveLimit(maxRecordings: 0)
    #expect(fileManager.fileExists(atPath: audioFile.path))

    store.clearAll()
    #expect(fileManager.fileExists(atPath: audioFile.path))

    // Corrupted metadata file must NEVER be overwritten with an empty array
    let currentData = try Data(contentsOf: notesURL)
    #expect(currentData == corruptData)
}

@MainActor
@Test
func successfulLoadWithOrphanMovesOrphanToTrashAndKeepsReferencedFiles() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("NativeBolabol-trash-orphan-\(UUID().uuidString)", isDirectory: true)
    let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try fileManager.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let linked = recordings.appendingPathComponent("linked.caf")
    let orphan = recordings.appendingPathComponent("orphan.caf")
    try Data("linked_data".utf8).write(to: linked)
    try Data("orphan_data".utf8).write(to: orphan)
    try fileManager.setAttributes(
        [.modificationDate: Date.now.addingTimeInterval(-1800)],
        ofItemAtPath: orphan.path
    )

    let notesURL = root.appendingPathComponent("notes.json")
    let recording = AudioRecording(
        fileURL: linked,
        duration: 2,
        sampleRate: 48_000,
        channelCount: 1,
        source: .microphone
    )

    // Seed persistence file
    let initialStore = NoteStore(
        notes: [],
        fileManager: fileManager,
        notesFileURL: notesURL,
        isPersistenceEnabled: true
    )
    initialStore.addRecordedNote(recording: recording, rawText: "test")
    let store = NoteStore(
        notes: nil,
        fileManager: fileManager,
        notesFileURL: notesURL,
        isPersistenceEnabled: true
    )
    #expect(store.loadState == .loaded)
    #expect(store.notes.count == 1)

    let removedCount = store.purgeOrphanedRecordings()
    #expect(removedCount == 1)
    #expect(fileManager.fileExists(atPath: linked.path))
    #expect(!fileManager.fileExists(atPath: orphan.path))
}

@MainActor
@Test
func freshRecordingYoungerThanAgeGuardSurvivesPurge() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("NativeBolabol-in-flight-\(UUID().uuidString)", isDirectory: true)
    let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try fileManager.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let inFlightFile = recordings.appendingPathComponent("in_flight.caf")
    try Data("in_flight_bytes".utf8).write(to: inFlightFile)
    // Fresh file: modification date is now (0s old < 15min)

    let notesURL = root.appendingPathComponent("notes.json")
    let store = NoteStore(
        notes: [],
        fileManager: fileManager,
        notesFileURL: notesURL,
        isPersistenceEnabled: true
    )

    let purged = store.purgeOrphanedRecordings()
    #expect(purged == 0)
    #expect(fileManager.fileExists(atPath: inFlightFile.path))
}

@MainActor
@Test
func freshInstallCaseAllowsNormalOperation() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("NativeBolabol-fresh-install-\(UUID().uuidString)", isDirectory: true)
    let notesURL = root.appendingPathComponent("notes.json")
    defer { try? fileManager.removeItem(at: root) }

    let store = NoteStore(
        notes: nil,
        fileManager: fileManager,
        notesFileURL: notesURL,
        isPersistenceEnabled: true
    )

    #expect(store.loadState == .freshInstall)
    #expect(store.loadErrorDescription == nil)
    #expect(!store.isDestructiveMaintenanceGuarded)
    #expect(store.notes.isEmpty)

    let note = store.addEmptyNote(title: "Brand New Note")
    #expect(store.notes.count == 1)
    #expect(fileManager.fileExists(atPath: notesURL.path))

    let reloadedStore = NoteStore(
        notes: nil,
        fileManager: fileManager,
        notesFileURL: notesURL,
        isPersistenceEnabled: true
    )
    #expect(reloadedStore.loadState == .loaded)
    #expect(reloadedStore.notes.count == 1)
    #expect(reloadedStore.notes.first?.id == note.id)
    #expect(reloadedStore.notes.first?.title == "Brand New Note")
}

@MainActor
@Test
func corruptMetadataFollowedByNoteAdditionDoesNotOverwriteCorruptFile() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("NativeBolabol-corrupt-no-overwrite-\(UUID().uuidString)", isDirectory: true)
    let notesURL = root.appendingPathComponent("notes.json")
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let corruptBytes = Data("corrupted-raw-content-that-must-not-be-lost".utf8)
    try corruptBytes.write(to: notesURL)

    let store = NoteStore(
        notes: nil,
        fileManager: fileManager,
        notesFileURL: notesURL,
        isPersistenceEnabled: true
    )
    #expect(store.loadState.isGuarded)

    // Adding a note in memory must not overwrite the corrupt file on disk
    _ = store.addEmptyNote(title: "Emergency Note")
    let onDisk = try Data(contentsOf: notesURL)
    #expect(onDisk == corruptBytes)
}

@MainActor
@Test
func clockInjectionAllowsDeterministicTestingOfAgeGuard() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("NativeBolabol-clock-injection-\(UUID().uuidString)", isDirectory: true)
    let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try fileManager.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let orphan = recordings.appendingPathComponent("custom_clock_orphan.caf")
    try Data("audio_content".utf8).write(to: orphan)

    // Fixed reference point in time
    let fileCreationTime = Date()
    try fileManager.setAttributes([.modificationDate: fileCreationTime], ofItemAtPath: orphan.path)

    let notesURL = root.appendingPathComponent("notes.json")

    // Store with simulated clock at +10 minutes (younger than 15-minute minimum age)
    let storeAt10Min = NoteStore(
        notes: [],
        fileManager: fileManager,
        notesFileURL: notesURL,
        isPersistenceEnabled: true,
        now: { fileCreationTime.addingTimeInterval(10 * 60) }
    )
    #expect(storeAt10Min.purgeOrphanedRecordings() == 0)
    #expect(fileManager.fileExists(atPath: orphan.path))

    // Store with simulated clock at +20 minutes (older than 15-minute minimum age)
    let storeAt20Min = NoteStore(
        notes: [],
        fileManager: fileManager,
        notesFileURL: notesURL,
        isPersistenceEnabled: true,
        now: { fileCreationTime.addingTimeInterval(20 * 60) }
    )
    #expect(storeAt20Min.purgeOrphanedRecordings() == 1)
    #expect(!fileManager.fileExists(atPath: orphan.path))
}

// The live() + retention-notification tests below share the global
// NotificationCenter and the live-instance registry, so they run serialized.
// (Parallel execution lets one test's retention post evict another's notes.)
@Suite("S11 NoteStore live writer", .serialized)
@MainActor
struct S11NoteStoreLiveTests {
// MARK: - S11/ADR-030: single writer + cap FIFO

@MainActor
@Test
func noteStoreLiveReturnsSingleInstancePerURL() {
    NoteStore.resetLiveInstancesForTesting()
    defer { NoteStore.resetLiveInstancesForTesting() }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("NativeBolabol-live-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("notes.json")

    let first = NoteStore.live(notesFileURL: url)
    let second = NoteStore.live(notesFileURL: url)
    #expect(first === second, "two live() calls on one notes.json must share one instance")
    #expect(first.ledger?.ledgerURL == url.deletingLastPathComponent().appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("session-ledger.log"))
}

@MainActor
@Test
func noteStoreStaleWriterCannotDropNewNote() throws {
    // Probe-proven defect class: a stale twin overwrote the disk without the
    // new note. With one instance per URL the note survives on disk and its
    // audio is never an orphan purge candidate.
    NoteStore.resetLiveInstancesForTesting()
    defer { NoteStore.resetLiveInstancesForTesting() }
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("NativeBolabol-stale-\(UUID().uuidString)", isDirectory: true)
    let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try fileManager.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }
    let notesURL = root.appendingPathComponent("notes.json")

    let store = NoteStore.live(notesFileURL: notesURL)
    // S11: live() roots the ledger at the owning store, so the factory
    // ledger — not a late replacement — is asserted and exercised.
    #expect(store.ledger?.ledgerURL == root.appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("session-ledger.log"))
    let audioURL = recordings.appendingPathComponent("session-1.caf")
    try Data("audio".utf8).write(to: audioURL)
    let recording = AudioRecording(
        fileURL: audioURL,
        createdAt: Date(timeIntervalSince1970: 1_775_030_000),
        duration: 5,
        sampleRate: 48_000,
        channelCount: 1,
        fileSizeBytes: 5,
        suggestedTitle: "Session 1"
    )
    let note = store.addRecordedNote(recording: recording, maxRecordingsLimit: 50)

    // A second live() call is the same writer, not a stale twin.
    let twin = NoteStore.live(notesFileURL: notesURL)
    #expect(twin === store)

    // Reload straight from disk: the new note is present…
    let reloaded = NoteStore(notes: nil, fileManager: fileManager, notesFileURL: notesURL, isPersistenceEnabled: true)
    #expect(reloaded.note(withID: note.id) != nil)
    // …and its audio is referenced, therefore not orphan-eligible.
    #expect(fileManager.fileExists(atPath: audioURL.path))
    #expect(reloaded.purgeOrphanedRecordings(olderThan: 0) == 0)
}

@MainActor
@Test
func noteStoreCap50FIFO80SessionsWithRetentionNotification() async throws {
    // S11.O2: 80 sessions at cap 50 with a mid-transcription retention
    // notification. Oldest evicted first; disk reload matches memory.
    NoteStore.resetLiveInstancesForTesting()
    defer { NoteStore.resetLiveInstancesForTesting() }
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("NativeBolabol-fifo-\(UUID().uuidString)", isDirectory: true)
    let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try fileManager.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }
    let notesURL = root.appendingPathComponent("notes.json")

    let store = NoteStore.live(notesFileURL: notesURL)
    #expect(store.ledger?.ledgerURL == root.appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("session-ledger.log"))
    store.observeRetentionSettings()
    var firstIDs: [BolabolNote.ID] = []
    for session in 0..<80 {
        let audioURL = recordings.appendingPathComponent("session-\(session).caf")
        try Data("audio-\(session)".utf8).write(to: audioURL)
        let recording = AudioRecording(
            fileURL: audioURL,
            createdAt: Date(timeIntervalSince1970: 1_775_040_000 + Double(session)),
            duration: 5,
            sampleRate: 48_000,
            channelCount: 1,
            fileSizeBytes: 8,
            suggestedTitle: "Session \(session)"
        )
        let note = store.addRecordedNote(recording: recording, maxRecordingsLimit: 50)
        if session == 0 { firstIDs.append(note.id) }
        if session == 40 {
            // Mid-transcription retention notification with the same pair:
            // must not disturb the cap window.
            NotificationCenter.default.post(
                name: .didChangeAudioRetentionSettings,
                object: GeneralSettings(isAutoArchiveCleanupEnabled: true, maxSavedAudioRecordings: 50)
            )
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    let audioNotes = store.notes.filter { $0.audioRecording != nil }
    #expect(audioNotes.count == 50)
    #expect(store.notes.first?.title == "Session 79")
    #expect(store.notes.last?.title == "Session 30")
    #expect(!audioNotes.map(\.id).contains(firstIDs[0]), "oldest session must be evicted first")

    let reloaded = NoteStore(notes: nil, fileManager: fileManager, notesFileURL: notesURL, isPersistenceEnabled: true)
    #expect(reloaded.notes.count == store.notes.count)
    #expect(reloaded.notes.map(\.id) == store.notes.map(\.id))
}

@Test
func noteStoreCap50FIFO80CompletionsReleaseDeferredOldestAudio() async throws {
    // The insertion-only 80-session test never completes protected work.
    // Keep session 0 decoding across the boundary, then prove completion
    // removes only that deferred oldest file without increasing the saved cap.
    NoteStore.resetLiveInstancesForTesting()
    defer { NoteStore.resetLiveInstancesForTesting() }
    let manager = FileManager.default
    let root = manager.temporaryDirectory
        .appendingPathComponent("NativeBolabol-fifo-completion-\(UUID().uuidString)", isDirectory: true)
    let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try manager.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let notesURL = root.appendingPathComponent("notes.json")
    let suiteName = "bolabol-s11-fifo-completion-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    defaults.set(
        try JSONEncoder().encode(GeneralSettings(isAutoArchiveCleanupEnabled: true, maxSavedAudioRecordings: 50)),
        forKey: "general.settings"
    )
    let store = NoteStore.live(notesFileURL: notesURL, userDefaults: defaults)
    var ids: [UUID] = []
    var urls: [URL] = []
    for session in 0..<80 {
        let url = recordings.appendingPathComponent("session-\(session).caf")
        try Data("audio-\(session)".utf8).write(to: url)
        urls.append(url)
        let note = store.addRecordedNote(
            recording: AudioRecording(fileURL: url, duration: 1, sampleRate: 48_000, channelCount: 1)
        )
        ids.append(note.id)
        store.markTranscriptionStarted(for: note.id)
        if session == 50 {
            let twin = NoteStore.live(notesFileURL: notesURL, userDefaults: defaults)
            #expect(twin === store)
            twin.updateRawText(for: note.id, text: "shared writer at cap")
            NotificationCenter.default.post(
                name: .didChangeAudioRetentionSettings,
                object: GeneralSettings(isAutoArchiveCleanupEnabled: true, maxSavedAudioRecordings: 50)
            )
            try await Task.sleep(nanoseconds: 200_000_000)
            let reloaded = NoteStore(notes: nil, notesFileURL: notesURL, isPersistenceEnabled: true)
            #expect(reloaded.note(withID: note.id)?.rawText == "shared writer at cap")
            #expect(reloaded.purgeOrphanedRecordings(olderThan: 0) == 0)
        }
        if session != 0 {
            store.applyTranscriptionResult(
                for: note.id,
                result: TranscriptionResult(text: "Session \(session)", diagnostics: EngineDiagnostics(backendName: "QA"))
            )
        }
        #expect(store.notes.count == (session < 50 ? session + 1 : 51))
        #expect(manager.fileExists(atPath: urls[0].path), "active oldest session must survive every cap/completion pass")
        #expect(manager.fileExists(atPath: url.path), "newest session must survive")
    }
    #expect(store.note(withID: ids[0])?.transcriptionStatus.phase == .transcribing)
    store.applyTranscriptionResult(
        for: ids[0],
        result: TranscriptionResult(text: "Oldest finished", diagnostics: EngineDiagnostics(backendName: "QA"))
    )
    #expect(store.notes.map(\.id) == Array(ids.suffix(50).reversed()))
    #expect(store.notes.allSatisfy { $0.transcriptionStatus.phase == .completed })
    for session in 0..<80 {
        #expect(manager.fileExists(atPath: urls[session].path) == (session >= 30))
    }
    let reloaded = NoteStore(notes: nil, notesFileURL: notesURL, isPersistenceEnabled: true)
    #expect(reloaded.notes == store.notes)
    #expect(reloaded.purgeOrphanedRecordings(olderThan: 0) == 0)
}

@MainActor
@Test
func noteStoreRetentionNotificationIgnoresNonRetentionChanges() async throws {
    NoteStore.resetLiveInstancesForTesting()
    defer { NoteStore.resetLiveInstancesForTesting() }
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("NativeBolabol-retention-\(UUID().uuidString)", isDirectory: true)
    let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try fileManager.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }
    let notesURL = root.appendingPathComponent("notes.json")

    let store = NoteStore.live(notesFileURL: notesURL)
    #expect(store.ledger?.ledgerURL == root.appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("session-ledger.log"))
    store.observeRetentionSettings()
    for session in 0..<5 {
        let audioURL = recordings.appendingPathComponent("r-\(session).caf")
        try Data("a".utf8).write(to: audioURL)
        _ = store.addRecordedNote(
            recording: AudioRecording(
                fileURL: audioURL,
                createdAt: Date(timeIntervalSince1970: 1_775_050_000 + Double(session)),
                duration: 5,
                sampleRate: 48_000,
                channelCount: 1,
                fileSizeBytes: 1,
                suggestedTitle: "R \(session)"
            ),
            maxRecordingsLimit: 50
        )
    }
    #expect(store.notes.count == 5)

    // Same (enabled, cap) pair with other settings changed: no enforcement.
    NotificationCenter.default.post(
        name: .didChangeAudioRetentionSettings,
        object: GeneralSettings(theme: .light, isAutoArchiveCleanupEnabled: true, maxSavedAudioRecordings: 50)
    )
    try await Task.sleep(nanoseconds: 200_000_000)
    #expect(store.notes.count == 5)

    // An actual cap change is honored.
    NotificationCenter.default.post(
        name: .didChangeAudioRetentionSettings,
        object: GeneralSettings(isAutoArchiveCleanupEnabled: true, maxSavedAudioRecordings: 3)
    )
    try await Task.sleep(nanoseconds: 200_000_000)
    #expect(store.notes.filter { $0.audioRecording != nil }.count == 3)
}

@MainActor
@Test
func oldNotesJSONWithoutOutputLanguageStillDecodes() throws {
    // ADR-029: `outputLanguage` is optional; pre-S11 notes.json files that
    // lack it must decode with a nil record.
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("NativeBolabol-legacy-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }
    let notesURL = root.appendingPathComponent("notes.json")

    // Encode a real note, then strip `outputLanguage` to simulate pre-S11 disk.
    let legacyNote = BolabolNote(title: "Old", rawText: "hello")
    var noteObject = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(legacyNote)
    ) as! [String: Any]
    noteObject.removeValue(forKey: "outputLanguage")
    #expect(noteObject["outputLanguage"] == nil)
    let container: [String: Any] = [
        "notes": [noteObject],
        "selection": NSNull(),
        "protectedImportedAudioPaths": [],
    ]
    try JSONSerialization.data(withJSONObject: container).write(to: notesURL, options: .atomic)

    let store = NoteStore(notes: nil, fileManager: fileManager, notesFileURL: notesURL, isPersistenceEnabled: true)
    #expect(store.loadState == .loaded)
    #expect(store.notes.count == 1)
    #expect(store.notes.first?.outputLanguage == nil)

    // …and a new record round-trips.
    let id = store.notes.first!.id
    store.setOutputLanguage(
        for: id,
        record: NoteOutputLanguage(targetCode: "en", verifiedCode: "ru", translated: false, reason: "translation-error")
    )
    #expect(store.note(withID: id)?.outputLanguage?.translated == false)
    let reloaded = NoteStore(notes: nil, fileManager: fileManager, notesFileURL: notesURL, isPersistenceEnabled: true)
    #expect(reloaded.note(withID: id)?.outputLanguage?.targetCode == "en")
}
}

@MainActor
@Test
func s11ReloadedInFlightTranscriptionIsNotExemptFromCap() throws {
    // S11 J3: a `.transcribing` phase left on disk is stale work from a
    // previous launch — nothing resumes it — so the cap applies after reload.
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("bolabol-s11-reload-\(UUID().uuidString)")
    let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try manager.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let notesURL = root.appendingPathComponent("notes.json")
    let store = NoteStore(notes: [], notesFileURL: notesURL, isPersistenceEnabled: true)
    let olderURL = recordings.appendingPathComponent("older.caf")
    let newerURL = recordings.appendingPathComponent("newer.caf")
    try Data("older".utf8).write(to: olderURL)
    try Data("newer".utf8).write(to: newerURL)
    let older = store.addRecordedNote(
        recording: AudioRecording(fileURL: olderURL, duration: 1, sampleRate: 48_000, channelCount: 1),
        maxRecordingsLimit: 50
    )
    store.markTranscriptionStarted(for: older.id)
    let newer = store.addRecordedNote(
        recording: AudioRecording(fileURL: newerURL, duration: 1, sampleRate: 48_000, channelCount: 1),
        maxRecordingsLimit: 50
    )

    // Simulate relaunch: the persisted `.transcribing` phase is failed on
    // load instead of staying exempt.
    let reloaded = NoteStore(notes: nil, fileManager: manager, notesFileURL: notesURL, isPersistenceEnabled: true)
    #expect(reloaded.note(withID: older.id) != nil)
    #expect(reloaded.note(withID: older.id)?.transcriptionStatus.phase == .failed)
    reloaded.enforceAudioArchiveLimit(maxRecordings: 1)
    #expect(reloaded.note(withID: newer.id) != nil)
    #expect(reloaded.note(withID: older.id) == nil, "stale in-flight work from a previous launch must not dodge the cap")
}

@MainActor
@Test
func s11CompletionAfterCleanupDisabledDeletesNothing() throws {
    // S11 J3: once the user turns auto cleanup off, finishing a
    // transcription must not trim down to the earlier cap.
    // S11 isolation: policy lives in a private suite injected into the
    // store — UserDefaults.standard is never touched.
    let suiteName = "bolabol-s11-cleanup-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    defaults.set(
        try JSONEncoder().encode(GeneralSettings(isAutoArchiveCleanupEnabled: true, maxSavedAudioRecordings: 50)),
        forKey: "general.settings"
    )
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("bolabol-s11-cleanup-\(UUID().uuidString)")
    let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try manager.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let notesURL = root.appendingPathComponent("notes.json")
    let store = NoteStore(notes: [], notesFileURL: notesURL, isPersistenceEnabled: true, userDefaults: defaults)
    let firstURL = recordings.appendingPathComponent("first.caf")
    let secondURL = recordings.appendingPathComponent("second.caf")
    try Data("first".utf8).write(to: firstURL)
    try Data("second".utf8).write(to: secondURL)
    let first = store.addRecordedNote(
        recording: AudioRecording(fileURL: firstURL, duration: 1, sampleRate: 48_000, channelCount: 1),
        maxRecordingsLimit: 50
    )
    store.markTranscriptionStarted(for: first.id)
    let second = store.addRecordedNote(
        recording: AudioRecording(fileURL: secondURL, duration: 1, sampleRate: 48_000, channelCount: 1),
        maxRecordingsLimit: 50
    )
    store.enforceAudioArchiveLimit(maxRecordings: 1)
    #expect(store.note(withID: first.id) != nil)
    #expect(store.note(withID: second.id) != nil)

    // The user turns cleanup off; a later completion deletes nothing.
    defaults.set(
        try JSONEncoder().encode(GeneralSettings(isAutoArchiveCleanupEnabled: false, maxSavedAudioRecordings: 50)),
        forKey: "general.settings"
    )
    store.applyTranscriptionResult(
        for: first.id,
        result: TranscriptionResult(text: "done", diagnostics: EngineDiagnostics(backendName: "QA"))
    )
    #expect(store.note(withID: first.id) != nil)
    #expect(store.note(withID: second.id) != nil, "disabling cleanup must stop completion-time trimming")
}
