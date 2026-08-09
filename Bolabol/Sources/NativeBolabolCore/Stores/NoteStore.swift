import Combine
import Foundation

@MainActor
public final class NoteStore: ObservableObject {
    @Published public private(set) var notes: [BolabolNote] {
        didSet {
            saveNotes()
        }
    }
    @Published public private(set) var selection: BolabolNote.ID? {
        didSet {
            saveNotes()
        }
    }

    private let fileManager: FileManager
    private let notesFileURL: URL
    private let isPersistenceEnabled: Bool
    private var isSavingEnabled = false
    private var protectedImportedAudioPaths: Set<String> = []

    public init(
        notes: [BolabolNote]? = nil,
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
            self.protectedImportedAudioPaths = Set(
                notes.compactMap { note in
                    guard note.audioRecording?.source == .importedFile,
                          let fileURL = note.audioRecording?.fileURL else {
                        return nil
                    }
                    return fileURL.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
                }
            )
        } else {
            self.notes = []
            self.selection = nil
            if isPersistenceEnabled {
                if let container = Self.loadNotes(from: self.notesFileURL, fileManager: fileManager) {
                    self.notes = container.notes
                    self.selection = container.selection
                    self.protectedImportedAudioPaths = Set(container.protectedImportedAudioPaths)
                }
            }
        }
        self.protectedImportedAudioPaths.formUnion(
            self.notes.compactMap { note in
                guard note.audioRecording?.source == .importedFile,
                      let fileURL = note.audioRecording?.fileURL else {
                    return nil
                }
                return fileURL.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
            }
        )
        self.isSavingEnabled = true
    }

    public var selectedNote: BolabolNote? {
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

    public func note(withID noteID: BolabolNote.ID) -> BolabolNote? {
        notes.first { $0.id == noteID }
    }

    public func select(_ id: BolabolNote.ID?) {
        selection = id
    }

    public func deleteNote(_ id: BolabolNote.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes[index]
        if let recording = note.audioRecording,
           recording.source == .importedFile {
            protectedImportedAudioPaths.insert(canonicalFilePath(recording.fileURL))
        }
        notes.remove(at: index)

        if selection == id {
            selection = notes[safe: min(index, notes.count - 1)]?.id
        }

        removeManagedAudioFile(note.audioRecording)
    }

    public func clearAll() {
        let importedPaths = Set(
            notes.compactMap { note -> String? in
                guard note.audioRecording?.source == .importedFile,
                      let fileURL = note.audioRecording?.fileURL else {
                    return nil
                }
                return canonicalFilePath(fileURL)
            }
        )
        protectedImportedAudioPaths.formUnion(importedPaths)
        let ownedRecordings = notes.compactMap { note -> AudioRecording? in
            guard let recording = note.audioRecording,
                  recording.source == .microphone else {
                return nil
            }
            return recording
        }

        notes.removeAll()
        selection = nil

        // Imported paths remain protected even when they share the managed
        // directory with microphone recordings or duplicate note references.
        for recording in ownedRecordings
            where !importedPaths.contains(canonicalFilePath(recording.fileURL)) {
            removeManagedAudioFile(recording)
        }
        _ = purgeUnreferencedFiles(
            in: recordingsDirectoryURL,
            referencedPaths: protectedImportedAudioPaths
        )
    }

    /// Deletes microphone recordings under Application Support that are no longer
    /// referenced by any note. Safe to call on launch after loading notes.
    @discardableResult
    public func purgeOrphanedRecordings() -> Int {
        var referenced = protectedImportedAudioPaths
        referenced.formUnion(
            notes.compactMap { note -> String? in
                guard let url = note.audioRecording?.fileURL else { return nil }
                return canonicalFilePath(url)
            }
        )
        return purgeUnreferencedFiles(in: recordingsDirectoryURL, referencedPaths: referenced)
    }

    @discardableResult
    public func addEmptyNote(
        title: String = "Untitled Note",
        now: Date = .now
    ) -> BolabolNote {
        let note = BolabolNote(
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
        let limit = max(0, maxRecordings)
        let audioNoteIDs = notes.compactMap { note in
            note.audioRecording == nil ? nil : note.id
        }
        guard audioNoteIDs.count > limit else { return }

        // `notes` is the persisted newest-first ordering. Keeping its order
        // makes equal timestamps deterministic and avoids deleting text notes.
        for noteID in audioNoteIDs.dropFirst(limit) {
            deleteNote(noteID)
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
    ) -> BolabolNote {
        let note = BolabolNote(
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
        for noteID: BolabolNote.ID,
        backendName: String? = nil
    ) {
        updateNote(noteID) { note in
            note.transcriptionStatus = .transcribing(backendName: backendName)
        }
    }

    public func applyTranscriptionResult(
        for noteID: BolabolNote.ID,
        result: TranscriptionResult
    ) {
        updateNote(noteID) { note in
            note.rawText = result.text
            note.transcriptionStatus = .completed(backendName: result.diagnostics.backendName)
        }
    }

    public func updateRawText(for noteID: BolabolNote.ID, text: String) {
        updateNote(noteID) { note in
            note.rawText = text
        }
    }

    public func updateText(
        for noteID: BolabolNote.ID,
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
        for noteID: BolabolNote.ID,
        message: String,
        backendName: String? = nil
    ) {
        updateNote(noteID) { note in
            note.transcriptionStatus = .failed(message: message, backendName: backendName)
        }
    }

    public func markPolishingStarted(
        for noteID: BolabolNote.ID,
        variant: ProcessingVariant,
        backendName: String? = nil
    ) {
        updateNote(noteID) { note in
            note.polishingStatuses[variant] = .polishing(backendName: backendName)
        }
    }

    public func applyPolishingResult(
        for noteID: BolabolNote.ID,
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
        for noteID: BolabolNote.ID,
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
        _ noteID: BolabolNote.ID,
        mutation: (inout BolabolNote) -> Void
    ) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        var note = notes[index]
        mutation(&note)
        notes[index] = note
    }

    private var retentionSubscription: AnyCancellable?

    public func observeRetentionSettings() {
        retentionSubscription = NotificationCenter.default.publisher(for: .didChangeAudioRetentionSettings)
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
        let container = NoteStorePersistenceContainer(
            notes: notes,
            selection: selection,
            protectedImportedAudioPaths: Array(protectedImportedAudioPaths).sorted()
        )
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
        let directory = appSupport.appendingPathComponent("NativeBolabol", isDirectory: true).appendingPathComponent("Recordings", isDirectory: true)
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
        guard let recording, recording.source == .microphone else { return }
        let url = canonicalFileURL(recording.fileURL)
        guard isManagedAudioPath(url) else { return }
        let path = url.path
        let stillReferenced = notes.contains { note in
            guard let otherURL = note.audioRecording?.fileURL else { return false }
            return canonicalFilePath(otherURL) == path
        }
        guard !stillReferenced,
              !protectedImportedAudioPaths.contains(path) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func isManagedAudioPath(_ url: URL) -> Bool {
        let path = url.path
        let recordingsRoot = canonicalFilePath(recordingsDirectoryURL)
        // Source metadata proves app ownership; the resolved path must still
        // stay below the dedicated recordings directory. A support-root path
        // alone is not enough, and symlinks resolving outside this root fail.
        return path.hasPrefix(recordingsRoot + "/")
    }

    private func canonicalFilePath(_ url: URL) -> String {
        canonicalFileURL(url).path
    }

    private func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
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
            let path = canonicalFilePath(item)
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
            .appendingPathComponent("NativeBolabol", isDirectory: true)
            .appendingPathComponent("notes.json", isDirectory: false)
    }
}

private struct NoteStorePersistenceContainer: Codable {
    let notes: [BolabolNote]
    let selection: UUID?
    let protectedImportedAudioPaths: [String]

    init(
        notes: [BolabolNote],
        selection: UUID?,
        protectedImportedAudioPaths: [String] = []
    ) {
        self.notes = notes
        self.selection = selection
        self.protectedImportedAudioPaths = protectedImportedAudioPaths
    }

    private enum CodingKeys: String, CodingKey {
        case notes
        case selection
        case protectedImportedAudioPaths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notes = try container.decode([BolabolNote].self, forKey: .notes)
        selection = try container.decodeIfPresent(UUID.self, forKey: .selection)
        protectedImportedAudioPaths = try container.decodeIfPresent(
            [String].self,
            forKey: .protectedImportedAudioPaths
        ) ?? []
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
