import Combine
import Foundation
import os
@MainActor
public final class NoteStore: ObservableObject {
    public enum LoadState: Equatable, Sendable {
        case freshInstall
        case loaded
        case failed(errorDescription: String)

        public var isLoaded: Bool {
            if case .loaded = self { return true }
            return false
        }

        public var isGuarded: Bool {
            if case .failed = self { return true }
            return false
        }
    }

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
    @Published public private(set) var loadState: LoadState = .freshInstall

    public var loadErrorDescription: String? {
        if case .failed(let description) = loadState {
            return description
        }
        return nil
    }

    public var isDestructiveMaintenanceGuarded: Bool {
        loadState.isGuarded
    }

    public static let minimumOrphanAge: TimeInterval = 15 * 60

    private let fileManager: FileManager
    private let notesFileURL: URL
    private let isPersistenceEnabled: Bool
    private var isSavingEnabled = false
    private var protectedImportedAudioPaths: Set<String> = []
    private let now: () -> Date

    public init(
        notes: [BolabolNote]? = nil,
        fileManager: FileManager = .default,
        notesFileURL: URL? = nil,
        isPersistenceEnabled: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.notesFileURL = notesFileURL ?? Self.defaultNotesFileURL(fileManager: fileManager)
        self.isPersistenceEnabled = isPersistenceEnabled
        self.isSavingEnabled = false
        self.now = now

        if let notes = notes {
            self.notes = notes
            self.selection = notes.first?.id
            self.loadState = .loaded
            self.protectedImportedAudioPaths = Set(
                notes.compactMap { note in
                    guard note.audioRecording?.source == .importedFile,
                          let fileURL = note.audioRecording?.fileURL else {
                        return nil
                    }
                    return fileURL.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
                }
            )
            self.isSavingEnabled = true
        } else {
            self.notes = []
            self.selection = nil
            if isPersistenceEnabled {
                if !fileManager.fileExists(atPath: self.notesFileURL.path) {
                    self.loadState = .freshInstall
                    self.isSavingEnabled = true
                    NativeBolabolLog.audio.info("NoteStore init: fresh install (no metadata file at \(self.notesFileURL.path, privacy: .public))")
                } else {
                    do {
                        let container = try Self.loadNotes(from: self.notesFileURL, fileManager: fileManager)
                        self.notes = container.notes
                        self.selection = container.selection
                        self.protectedImportedAudioPaths = Set(container.protectedImportedAudioPaths)
                        self.loadState = .loaded
                        self.isSavingEnabled = true
                        NativeBolabolLog.audio.info("NoteStore init: loaded \(container.notes.count) note(s) from \(self.notesFileURL.path, privacy: .public)")
                    } catch {
                        let errorDescription = error.localizedDescription
                        self.loadState = .failed(errorDescription: errorDescription)
                        self.isSavingEnabled = false
                        NativeBolabolLog.audio.error("NoteStore init: failed to read or decode notes metadata at \(self.notesFileURL.path, privacy: .public): \(errorDescription, privacy: .public). Destructive maintenance disabled.")
                    }
                }
            } else {
                self.loadState = .freshInstall
                self.isSavingEnabled = true
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
        guard !loadState.isGuarded else {
            NativeBolabolLog.audio.warning("clearAll skipped: NoteStore is in guarded failure state.")
            return
        }
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
            referencedPaths: protectedImportedAudioPaths,
            olderThan: 0
        )
    }

    /// Moves microphone recordings under Application Support that are no longer
    /// referenced by any note to Trash. Skips in-flight recordings modified within
    /// the minimum orphan age (15 minutes). Safe to call on launch after loading notes.
    @discardableResult
    public func purgeOrphanedRecordings(
        olderThan ageThreshold: TimeInterval? = nil,
        asOf referenceDate: Date? = nil
    ) -> Int {
        guard !loadState.isGuarded else {
            NativeBolabolLog.audio.warning("purgeOrphanedRecordings skipped: NoteStore is in guarded failure state.")
            return 0
        }
        var referenced = protectedImportedAudioPaths
        referenced.formUnion(
            notes.compactMap { note -> String? in
                guard let url = note.audioRecording?.fileURL else { return nil }
                return canonicalFilePath(url)
            }
        )
        return purgeUnreferencedFiles(
            in: recordingsDirectoryURL,
            referencedPaths: referenced,
            olderThan: ageThreshold ?? Self.minimumOrphanAge,
            asOf: referenceDate ?? now()
        )
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
        guard !loadState.isGuarded else {
            NativeBolabolLog.audio.warning("enforceAudioArchiveLimit skipped: NoteStore is in guarded failure state.")
            return
        }
        let limit = max(0, maxRecordings)
        let audioNoteIDs = notes.compactMap { note in
            note.audioRecording == nil ? nil : note.id
        }
        guard audioNoteIDs.count > limit else { return }

        let excessNotes = audioNoteIDs.dropFirst(limit)
        NativeBolabolLog.audio.info("enforceAudioArchiveLimit: removing \(excessNotes.count) excess audio note(s) (limit=\(limit), count=\(audioNoteIDs.count))")

        // `notes` is the persisted newest-first ordering. Keeping its order
        // makes equal timestamps deterministic and avoids deleting text notes.
        for noteID in excessNotes {
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
        // One-shot hygiene: drop microphone .caf files no note still points at,
        // executed ONLY when the metadata load fully succeeded.
        if store.loadState == .loaded {
            let removed = store.purgeOrphanedRecordings()
            if removed > 0 {
                NativeBolabolLog.audio.info("live() startup hygiene: trashed \(removed) orphaned audio recording(s).")
            }
            if let limit = store.loadSavedRetentionLimit() {
                store.enforceAudioArchiveLimit(maxRecordings: limit)
            }
        } else if case .failed(let errorDescription) = store.loadState {
            NativeBolabolLog.audio.error("live() startup hygiene skipped: NoteStore load failed (\(errorDescription, privacy: .public)).")
        } else if store.loadState == .freshInstall {
            NativeBolabolLog.audio.info("live() startup hygiene skipped: fresh install (no metadata file).")
        }
        store.observeRetentionSettings()
        return store
    }

    private func saveNotes() {
        guard isSavingEnabled, isPersistenceEnabled, !loadState.isGuarded else { return }
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
            NativeBolabolLog.audio.error("NoteStore saveNotes failed for \(self.notesFileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
        guard !loadState.isGuarded else { return }
        let url = canonicalFileURL(recording.fileURL)
        guard isManagedAudioPath(url) else { return }
        let path = url.path
        let stillReferenced = notes.contains { note in
            guard let otherURL = note.audioRecording?.fileURL else { return false }
            return canonicalFilePath(otherURL) == path
        }
        guard !stillReferenced,
              !protectedImportedAudioPaths.contains(path) else { return }
        do {
            var resultingURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
            NativeBolabolLog.audio.info("removeManagedAudioFile trashed: \(url.lastPathComponent, privacy: .public)")
        } catch {
            NativeBolabolLog.audio.warning("removeManagedAudioFile failed to trash \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
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
        referencedPaths: Set<String>,
        olderThan ageThreshold: TimeInterval = minimumOrphanAge,
        asOf referenceDate: Date? = nil
    ) -> Int {
        guard !loadState.isGuarded else {
            NativeBolabolLog.audio.warning("purgeUnreferencedFiles skipped: NoteStore is in guarded failure state.")
            return 0
        }
        guard fileManager.fileExists(atPath: directory.path),
              let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return 0
        }

        let clockNow = referenceDate ?? now()
        var removed = 0
        var skippedReferenced = 0
        var skippedTooYoung = 0
        var skippedErrors = 0

        for item in contents {
            let path = canonicalFilePath(item)
            if referencedPaths.contains(path) {
                skippedReferenced += 1
                continue
            }

            guard let attributes = try? fileManager.attributesOfItem(atPath: item.path) else {
                NativeBolabolLog.audio.warning("purgeUnreferencedFiles skipped \(item.lastPathComponent, privacy: .public): unable to read attributes")
                skippedErrors += 1
                continue
            }

            let modificationDate = (attributes[.modificationDate] as? Date) ?? (attributes[.creationDate] as? Date)
            guard let modificationDate else {
                NativeBolabolLog.audio.warning("purgeUnreferencedFiles skipped \(item.lastPathComponent, privacy: .public): missing modification date")
                skippedErrors += 1
                continue
            }

            let age = clockNow.timeIntervalSince(modificationDate)
            if age < ageThreshold {
                NativeBolabolLog.audio.info("purgeUnreferencedFiles skipped recent file \(item.lastPathComponent, privacy: .public): age=\(Int(age))s < threshold=\(Int(ageThreshold))s")
                skippedTooYoung += 1
                continue
            }

            do {
                var resultingURL: NSURL?
                try fileManager.trashItem(at: item, resultingItemURL: &resultingURL)
                removed += 1
                let trashPath = resultingURL?.path ?? "Trash"
                NativeBolabolLog.audio.info("purgeUnreferencedFiles trashed orphan \(item.lastPathComponent, privacy: .public) -> \(trashPath, privacy: .public) age=\(Int(age))s")
            } catch {
                NativeBolabolLog.audio.warning("purgeUnreferencedFiles failed to trash \(item.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public). Skipping deletion.")
                skippedErrors += 1
                continue
            }
        }

        NativeBolabolLog.audio.info("purgeUnreferencedFiles summary: directory=\(directory.lastPathComponent, privacy: .public) trashed=\(removed) skippedReferenced=\(skippedReferenced) skippedTooYoung=\(skippedTooYoung) skippedErrors=\(skippedErrors)")
        return removed
    }

    private static func loadNotes(
        from url: URL,
        fileManager: FileManager
    ) throws -> NoteStorePersistenceContainer {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(NoteStorePersistenceContainer.self, from: data)
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
