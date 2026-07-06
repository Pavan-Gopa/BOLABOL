import Combine
import Foundation

@MainActor
public final class NoteStore: ObservableObject {
    @Published public private(set) var notes: [SmartScribeNote] {
        didSet {
            saveNotes()
        }
    }
    @Published public private(set) var selection: SmartScribeNote.ID? {
        didSet {
            saveNotes()
        }
    }

    private let fileManager: FileManager
    private let notesFileURL: URL
    private let isPersistenceEnabled: Bool
    private var isSavingEnabled = false

    public init(
        notes: [SmartScribeNote]? = nil,
        fileManager: FileManager = .default,
        notesFileURL: URL? = nil,
        isPersistenceEnabled: Bool = false
    ) {
        self.fileManager = fileManager
        self.notesFileURL = notesFileURL ?? Self.defaultNotesFileURL(fileManager: fileManager)
        self.isPersistenceEnabled = isPersistenceEnabled
        self.isSavingEnabled = false

        if let notes = notes {
            self.notes = notes
            self.selection = notes.first?.id
        } else {
            self.notes = []
            self.selection = nil
            if isPersistenceEnabled {
                if let container = Self.loadNotes(from: self.notesFileURL, fileManager: fileManager) {
                    self.notes = container.notes
                    self.selection = container.selection
                }
            }
        }
        self.isSavingEnabled = true
    }

    public var selectedNote: SmartScribeNote? {
        guard let selection else { return nil }
        return notes.first { $0.id == selection }
    }

    public func note(withID noteID: SmartScribeNote.ID) -> SmartScribeNote? {
        notes.first { $0.id == noteID }
    }

    public func select(_ id: SmartScribeNote.ID?) {
        selection = id
    }

    public func deleteNote(_ id: SmartScribeNote.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes[index]
        notes.remove(at: index)

        if selection == id {
            selection = notes[safe: min(index, notes.count - 1)]?.id
        }

        if let audioRecording = note.audioRecording, audioRecording.source == .microphone {
            try? fileManager.removeItem(at: audioRecording.fileURL)
        }
    }

    public func clearAll() {
        for note in notes {
            if let audioRecording = note.audioRecording, audioRecording.source == .microphone {
                try? fileManager.removeItem(at: audioRecording.fileURL)
            }
        }
        notes.removeAll()
        selection = nil
    }

    @discardableResult
    public func addEmptyNote(
        title: String = "Untitled Note",
        now: Date = .now
    ) -> SmartScribeNote {
        let note = SmartScribeNote(
            title: title,
            createdAt: now,
            rawText: ""
        )
        notes.insert(note, at: 0)
        selection = note.id
        return note
    }

    @discardableResult
    public func addRecordedNote(
        recording: AudioRecording,
        rawText: String = "",
        now: Date = .now
    ) -> SmartScribeNote {
        let note = SmartScribeNote(
            title: recording.suggestedTitle,
            createdAt: now,
            rawText: rawText,
            audioRecording: recording,
            transcriptionStatus: .pending
        )
        notes.insert(note, at: 0)
        selection = note.id
        return note
    }

    public func markTranscriptionStarted(
        for noteID: SmartScribeNote.ID,
        backendName: String? = nil
    ) {
        updateNote(noteID) { note in
            note.transcriptionStatus = .transcribing(backendName: backendName)
        }
    }

    public func applyTranscriptionResult(
        for noteID: SmartScribeNote.ID,
        result: TranscriptionResult
    ) {
        updateNote(noteID) { note in
            note.rawText = result.text
            note.transcriptionStatus = .completed(backendName: result.diagnostics.backendName)
        }
    }

    public func updateRawText(for noteID: SmartScribeNote.ID, text: String) {
        updateNote(noteID) { note in
            note.rawText = text
        }
    }

    public func updateText(
        for noteID: SmartScribeNote.ID,
        variant: ProcessingVariant,
        text: String
    ) {
        updateNote(noteID) { note in
            switch variant {
            case .raw:
                note.rawText = text
            case .variantOne:
                note.polishedVariantOne = text
            case .variantTwo:
                note.polishedVariantTwo = text
            }
        }
    }

    public func markTranscriptionFailed(
        for noteID: SmartScribeNote.ID,
        message: String,
        backendName: String? = nil
    ) {
        updateNote(noteID) { note in
            note.transcriptionStatus = .failed(message: message, backendName: backendName)
        }
    }

    public func markPolishingStarted(
        for noteID: SmartScribeNote.ID,
        variant: ProcessingVariant,
        backendName: String? = nil
    ) {
        updateNote(noteID) { note in
            note.polishingStatuses[variant] = .polishing(backendName: backendName)
        }
    }

    public func applyPolishingResult(
        for noteID: SmartScribeNote.ID,
        variant: ProcessingVariant,
        result: PolishingResult
    ) {
        updateNote(noteID) { note in
            switch variant {
            case .raw:
                note.rawText = result.text
            case .variantOne:
                note.polishedVariantOne = result.text
            case .variantTwo:
                note.polishedVariantTwo = result.text
            }

            note.polishingStatuses[variant] = .completed(
                backendName: result.diagnostics.backendName
            )
        }
    }

    public func markPolishingFailed(
        for noteID: SmartScribeNote.ID,
        variant: ProcessingVariant,
        message: String,
        backendName: String? = nil
    ) {
        updateNote(noteID) { note in
            note.polishingStatuses[variant] = .failed(
                message: message,
                backendName: backendName
            )
        }
    }

    private func updateNote(
        _ noteID: SmartScribeNote.ID,
        mutation: (inout SmartScribeNote) -> Void
    ) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        var note = notes[index]
        mutation(&note)
        notes[index] = note
    }

    public static var preview: NoteStore {
        NoteStore(notes: .preview)
    }

    public static func live() -> NoteStore {
        let fileManager = FileManager.default
        let url = defaultNotesFileURL(fileManager: fileManager)
        return NoteStore(notes: nil, fileManager: fileManager, notesFileURL: url, isPersistenceEnabled: true)
    }

    private func saveNotes() {
        guard isSavingEnabled, isPersistenceEnabled else { return }
        let container = NoteStorePersistenceContainer(notes: notes, selection: selection)
        do {
            let directory = notesFileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(container)
            try data.write(to: notesFileURL, options: .atomic)
        } catch {
            // Silently ignore
        }
    }

    private static func loadNotes(
        from url: URL,
        fileManager: FileManager
    ) -> NoteStorePersistenceContainer? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let container = try? JSONDecoder().decode(NoteStorePersistenceContainer.self, from: data)
        else {
            return nil
        }
        return container
    }

    private static func defaultNotesFileURL(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return baseURL
            .appendingPathComponent("NativeSmartScribe", isDirectory: true)
            .appendingPathComponent("notes.json", isDirectory: false)
    }
}

private struct NoteStorePersistenceContainer: Codable {
    let notes: [SmartScribeNote]
    let selection: UUID?
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
