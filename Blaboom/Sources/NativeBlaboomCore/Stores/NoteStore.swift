import Combine
import Foundation

@MainActor
public final class NoteStore: ObservableObject {
    @Published public private(set) var notes: [BlaboomNote] {
        didSet {
            saveNotes()
        }
    }
    @Published public private(set) var selection: BlaboomNote.ID? {
        didSet {
            saveNotes()
        }
    }

    private let fileManager: FileManager
    private let notesFileURL: URL
    private let isPersistenceEnabled: Bool
    private var isSavingEnabled = false

    public init(
        notes: [BlaboomNote]? = nil,
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

    public var selectedNote: BlaboomNote? {
        guard let selection else { return nil }
        return notes.first { $0.id == selection }
    }

    public var audioArchiveStats: (count: Int, totalBytes: Int64) {
        var count = 0
        var totalBytes: Int64 = 0
        for note in notes {
            guard let recording = note.audioRecording else { continue }
            count += 1
            if let size = recording.fileSizeBytes, size > 0 {
                totalBytes += size
            } else if fileManager.fileExists(atPath: recording.fileURL.path),
                      let attributes = try? fileManager.attributesOfItem(atPath: recording.fileURL.path),
                      let size = attributes[.size] as? Int64 {
                totalBytes += size
            }
        }
        return (count, totalBytes)
    }

    public static func formattedByteSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    public func note(withID noteID: BlaboomNote.ID) -> BlaboomNote? {
        notes.first { $0.id == noteID }
    }

    public func select(_ id: BlaboomNote.ID?) {
        selection = id
    }

    public func deleteNote(_ id: BlaboomNote.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes[index]
        notes.remove(at: index)

        if selection == id {
            selection = notes[safe: min(index, notes.count - 1)]?.id
        }

        removeManagedAudioFile(note.audioRecording)
    }

    public func clearAll() {
        for note in notes {
            removeManagedAudioFile(note.audioRecording)
        }
        notes.removeAll()
        selection = nil
        // Always empty the mic Recordings folder so orphans left by failed
        // sessions / lost note links cannot accumulate (was ~GBs of .caf junk).
        // Permanent delete via FileManager — not the Finder Trash.
        purgeAllFiles(in: recordingsDirectoryURL)
    }

    /// Deletes microphone recordings under Application Support that are no longer
    /// referenced by any note. Safe to call on launch after loading notes.
    @discardableResult
    public func purgeOrphanedRecordings() -> Int {
        let referenced = Set(
            notes.compactMap { note -> String? in
                guard let url = note.audioRecording?.fileURL else { return nil }
                return url.standardizedFileURL.resolvingSymlinksInPath().path
            }
        )
        return purgeUnreferencedFiles(in: recordingsDirectoryURL, referencedPaths: referenced)
    }

    @discardableResult
    public func addEmptyNote(
        title: String = "Untitled Note",
        now: Date = .now
    ) -> BlaboomNote {
        let note = BlaboomNote(
            title: title,
            createdAt: now,
            rawText: ""
        )
        notes.insert(note, at: 0)
        selection = note.id
        return note
    }

    public var recordingsDirectory: URL {
        recordingsDirectoryURL
    }

    public func enforceAudioArchiveLimit(maxRecordings: Int) {
        guard maxRecordings > 0 else { return }
        
        if notes.count > maxRecordings {
            let overflowCount = notes.count - maxRecordings
            // Oldest notes are at the end of the notes array
            let oldestNotes = notes.suffix(overflowCount)
            for oldNote in oldestNotes {
                deleteNote(oldNote.id)
            }
        }
    }

    private func loadSavedRetentionLimit() -> Int? {
        let userDefaults = UserDefaults.standard
        guard let data = userDefaults.data(forKey: "general.settings"),
              let settings = try? JSONDecoder().decode(GeneralSettings.self, from: data),
              settings.isAutoArchiveCleanupEnabled else {
            return nil
        }
        return settings.maxSavedAudioRecordings
    }

    @discardableResult
    public func addRecordedNote(
        recording: AudioRecording,
        rawText: String = "",
        now: Date = .now,
        maxRecordingsLimit: Int? = nil
    ) -> BlaboomNote {
        let note = BlaboomNote(
            title: recording.suggestedTitle,
            createdAt: now,
            rawText: rawText,
            audioRecording: recording,
            transcriptionStatus: .pending
        )
        notes.insert(note, at: 0)
        selection = note.id

        if let maxRecordingsLimit {
            enforceAudioArchiveLimit(maxRecordings: maxRecordingsLimit)
        } else if let savedLimit = loadSavedRetentionLimit() {
            enforceAudioArchiveLimit(maxRecordings: savedLimit)
        }
        return note
    }

    public func markTranscriptionStarted(
        for noteID: BlaboomNote.ID,
        backendName: String? = nil
    ) {
        updateNote(noteID) { note in
            note.transcriptionStatus = .transcribing(backendName: backendName)
        }
    }

    public func applyTranscriptionResult(
        for noteID: BlaboomNote.ID,
        result: TranscriptionResult
    ) {
        updateNote(noteID) { note in
            note.rawText = result.text
            note.transcriptionStatus = .completed(backendName: result.diagnostics.backendName)
        }
    }

    public func updateRawText(for noteID: BlaboomNote.ID, text: String) {
        updateNote(noteID) { note in
            note.rawText = text
        }
    }

    public func updateText(
        for noteID: BlaboomNote.ID,
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
        for noteID: BlaboomNote.ID,
        message: String,
        backendName: String? = nil
    ) {
        updateNote(noteID) { note in
            note.transcriptionStatus = .failed(message: message, backendName: backendName)
        }
    }

    public func markPolishingStarted(
        for noteID: BlaboomNote.ID,
        variant: ProcessingVariant,
        backendName: String? = nil
    ) {
        updateNote(noteID) { note in
            note.polishingStatuses[variant] = .polishing(backendName: backendName)
        }
    }

    public func applyPolishingResult(
        for noteID: BlaboomNote.ID,
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
        for noteID: BlaboomNote.ID,
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
        _ noteID: BlaboomNote.ID,
        mutation: (inout BlaboomNote) -> Void
    ) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        var note = notes[index]
        mutation(&note)
        notes[index] = note
    }

    private var retentionSubscription: AnyCancellable?

    public func observeRetentionSettings() {
        retentionSubscription = NotificationCenter.default.publisher(for: Notification.Name("didChangeAudioRetentionSettings"))
            .compactMap { $0.object as? GeneralSettings }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self else { return }
                if settings.isAutoArchiveCleanupEnabled {
                    self.enforceAudioArchiveLimit(maxRecordings: settings.maxSavedAudioRecordings)
                }
            }
    }

    public static let preview: NoteStore = NoteStore(notes: .preview)

    public static func live() -> NoteStore {
        let fileManager = FileManager.default
        let url = defaultNotesFileURL(fileManager: fileManager)
        let store = NoteStore(notes: nil, fileManager: fileManager, notesFileURL: url, isPersistenceEnabled: true)
        // One-shot hygiene: drop microphone .caf files no note still points at.
        let removed = store.purgeOrphanedRecordings()
        if removed > 0 {
            // Logging stays optional in Core; no Logger dependency here.
        }
        if let limit = store.loadSavedRetentionLimit() {
            store.enforceAudioArchiveLimit(maxRecordings: limit)
        }
        store.observeRetentionSettings()
        return store
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

    public static var defaultRecordingsDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("NativeBlaboom", isDirectory: true).appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var applicationSupportRootURL: URL {
        notesFileURL.deletingLastPathComponent()
    }

    private var recordingsDirectoryURL: URL {
        applicationSupportRootURL.appendingPathComponent("Recordings", isDirectory: true)
    }

    private func removeManagedAudioFile(_ recording: AudioRecording?) {
        guard let recording else { return }
        let url = recording.fileURL.standardizedFileURL.resolvingSymlinksInPath()
        guard isManagedAudioPath(url) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func isManagedAudioPath(_ url: URL) -> Bool {
        let path = url.path
        let supportRoot = applicationSupportRootURL.standardizedFileURL.resolvingSymlinksInPath().path
        // Only delete files we own under this store's Application Support root.
        return path.hasPrefix(supportRoot + "/") || path == supportRoot
    }

    private func purgeAllFiles(in directory: URL) {
        guard fileManager.fileExists(atPath: directory.path),
              let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              )
        else {
            return
        }
        for item in contents {
            try? fileManager.removeItem(at: item)
        }
    }

    @discardableResult
    private func purgeUnreferencedFiles(
        in directory: URL,
        referencedPaths: Set<String>
    ) -> Int {
        guard fileManager.fileExists(atPath: directory.path),
              let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              )
        else {
            return 0
        }

        var removed = 0
        for item in contents {
            let path = item.standardizedFileURL.resolvingSymlinksInPath().path
            guard !referencedPaths.contains(path) else { continue }
            do {
                try fileManager.removeItem(at: item)
                removed += 1
            } catch {
                continue
            }
        }
        return removed
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
            .appendingPathComponent("NativeBlaboom", isDirectory: true)
            .appendingPathComponent("notes.json", isDirectory: false)
    }
}

private struct NoteStorePersistenceContainer: Codable {
    let notes: [BlaboomNote]
    let selection: UUID?
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
