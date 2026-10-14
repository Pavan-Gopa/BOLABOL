import AVFoundation
import Foundation
import NativeBolabolCore
@testable import NativeBolabol
import Testing

@MainActor
@Test
func s11RetentionExactly50Then51KeepsNewestAudioAndDiskInSync() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("bolabol-s11-cap-\(UUID().uuidString)")
    let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try manager.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let notesURL = root.appendingPathComponent("notes.json")
    let store = NoteStore(notes: [], notesFileURL: notesURL, isPersistenceEnabled: true)
    var ids: [UUID] = []
    var urls: [URL] = []
    for session in 0..<51 {
        let url = recordings.appendingPathComponent("session-\(session).caf")
        try Data("audio".utf8).write(to: url)
        urls.append(url)
        let note = store.addRecordedNote(
            recording: AudioRecording(fileURL: url, duration: 1, sampleRate: 48_000, channelCount: 1),
            maxRecordingsLimit: 50
        )
        ids.append(note.id)
        store.markTranscriptionStarted(for: note.id)
        store.applyTranscriptionResult(
            for: note.id,
            result: TranscriptionResult(text: "Session \(session)", diagnostics: EngineDiagnostics(backendName: "QA"))
        )
        if session == 49 {
            #expect(store.notes.count == 50)
            #expect(urls.allSatisfy { manager.fileExists(atPath: $0.path) })
        }
    }
    #expect(store.notes.count == 50)
    #expect(store.note(withID: ids[0]) == nil)
    #expect(store.notes.first?.id == ids[50])
    #expect(!manager.fileExists(atPath: urls[0].path))
    #expect(urls.dropFirst().allSatisfy { manager.fileExists(atPath: $0.path) })
    let reloaded = NoteStore(notes: nil, notesFileURL: notesURL, isPersistenceEnabled: true)
    #expect(reloaded.notes.map(\.id) == store.notes.map(\.id))
    #expect(reloaded.purgeOrphanedRecordings(olderThan: 0) == 0)
}

@MainActor
@Test
func s11RetentionLoweredCapCannotTrashOlderInFlightTranscription() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("bolabol-s11-inflight-\(UUID().uuidString)")
    let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try manager.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let notesURL = root.appendingPathComponent("notes.json")
    let olderURL = recordings.appendingPathComponent("older.caf")
    let newestURL = recordings.appendingPathComponent("newest.caf")
    try Data("older".utf8).write(to: olderURL)
    try Data("newest".utf8).write(to: newestURL)
    let store = NoteStore(notes: [], notesFileURL: notesURL, isPersistenceEnabled: true)
    let older = store.addRecordedNote(
        recording: AudioRecording(fileURL: olderURL, duration: 1, sampleRate: 48_000, channelCount: 1),
        maxRecordingsLimit: 50
    )
    store.markTranscriptionStarted(for: older.id)
    let newest = store.addRecordedNote(
        recording: AudioRecording(fileURL: newestURL, duration: 1, sampleRate: 48_000, channelCount: 1),
        maxRecordingsLimit: 50
    )
    store.markTranscriptionStarted(for: newest.id)

    // Settings may lower the cap while an earlier session is still decoding.
    // Both the newest and the in-flight recording must survive this pass.
    store.enforceAudioArchiveLimit(maxRecordings: 1)
    #expect(store.note(withID: older.id) != nil)
    #expect(store.note(withID: newest.id) != nil)
    #expect(manager.fileExists(atPath: olderURL.path))
    #expect(manager.fileExists(atPath: newestURL.path))
    let reloaded = NoteStore(notes: nil, notesFileURL: notesURL, isPersistenceEnabled: true)
    #expect(reloaded.note(withID: older.id) != nil, "in-flight protection must also survive disk reload")
}

// MARK: - S11 storage isolation regression (2026-10-14 10:44 incident)

/// Redirects Application Support into a synthetic temp root while every other
/// filesystem operation stays real. Directory redirection, not mocked deletion.
private final class S11RedirectedFileManager: FileManager {
    private let redirectedBase: URL

    init(redirectedBase: URL) {
        self.redirectedBase = redirectedBase
        super.init()
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        if directory == .applicationSupportDirectory {
            return [redirectedBase]
        }
        return super.urls(for: directory, in: domainMask)
    }
}

private func s11SineBuffer(frameCount: AVAudioFrameCount, frequency: Float = 440) throws -> AVAudioPCMBuffer {
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 1,
        interleaved: false
    ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
    else {
        throw NSError(domain: "BolabolS11Isolation", code: 1, userInfo: nil)
    }
    buffer.frameLength = frameCount
    guard let channel = buffer.floatChannelData?[0] else {
        throw NSError(domain: "BolabolS11Isolation", code: 2, userInfo: nil)
    }
    for index in 0..<Int(frameCount) {
        channel[index] = sin(Float(index) * frequency / 48_000 * 2 * .pi) * 0.4
    }
    return buffer
}

/// Writes a valid 48 kHz mono CAF with real AVAudioFile. The returned writer
/// is left open so callers can simulate an in-progress recording.
private func s11WriteValidCAF(at url: URL, frameCount: AVAudioFrameCount = 48_000) throws -> AVAudioFile {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 48_000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    try file.write(from: s11SineBuffer(frameCount: frameCount))
    return file
}

@MainActor
@Test
func s11ImplicitNonpersistentStoreCannotTouchSyntheticDefaultAudio() throws {
    // S11 CRITICAL regression: the default nonpersistent clearAll path
    // enumerated the live production Recordings directory with olderThan:0 and
    // trashed the active CAF. Application Support is redirected into synthetic
    // temp root B, so this test fails pre-fix without ever touching the real
    // user root. Explicit same-root and symlink-alias stores stay unauthorized;
    // an explicitly owned root A still cleans itself.
    let manager = FileManager.default
    let realSupport = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

    let scratch = manager.temporaryDirectory
        .appendingPathComponent("bolabol-s11-isolation-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: scratch) }

    // B: synthetic "default application data".
    let syntheticSupport = scratch.appendingPathComponent("SyntheticAppSupport", isDirectory: true)
    let bRoot = syntheticSupport.appendingPathComponent("NativeBolabol", isDirectory: true)
    let bRecordings = bRoot.appendingPathComponent("Recordings", isDirectory: true)
    try manager.createDirectory(at: bRecordings, withIntermediateDirectories: true)
    #expect(syntheticSupport.standardizedFileURL.path != realSupport.standardizedFileURL.path)

    let fm = S11RedirectedFileManager(redirectedBase: syntheticSupport)

    // Valid synthetic 48 kHz mono CAFs: one old orphan-eligible file and one
    // fresh file whose writer stays open like an in-progress recording.
    let oldCAF = bRecordings.appendingPathComponent("recording-old.caf")
    _ = try s11WriteValidCAF(at: oldCAF)
    try manager.setAttributes(
        [.modificationDate: Date.now.addingTimeInterval(-3600)],
        ofItemAtPath: oldCAF.path
    )

    let activeCAF = bRecordings.appendingPathComponent("recording-active.caf")
    var activeWriter: AVAudioFile? = try s11WriteValidCAF(at: activeCAF, frameCount: 24_000)

    // Synthetic notes metadata referencing neither CAF, mirroring the
    // text-only fixture whose empty reference set exposed every live file.
    let bNotesURL = bRoot.appendingPathComponent("notes.json")
    try Data(#"{"notes":[],"selection":null,"protectedImportedAudioPaths":[]}"#.utf8)
        .write(to: bNotesURL, options: .atomic)

    func s11SnapshotB() throws -> [String: Int] {
        var manifest: [String: Int] = [:]
        for url in [oldCAF, activeCAF, bNotesURL] {
            manifest[url.path] = try Data(contentsOf: url).count
        }
        return manifest
    }
    let baseline = try s11SnapshotB()

    // 1. Original incident shape: implicit default nonpersistent text-only clearAll.
    let textOnly = NoteStore(
        notes: [BolabolNote(title: "One", rawText: "One")],
        fileManager: fm
    )
    textOnly.clearAll()
    #expect(textOnly.notes.isEmpty)
    #expect(try s11SnapshotB() == baseline, "implicit clearAll must not touch synthetic default audio")

    // 2. Per-note delete of a B-referencing note, retention trim, explicit purge.
    let oldRef = AudioRecording(fileURL: oldCAF, duration: 1, sampleRate: 48_000, channelCount: 1)
    let deleteStore = NoteStore(
        notes: [BolabolNote(title: "Voice", rawText: "", audioRecording: oldRef)],
        fileManager: fm
    )
    deleteStore.deleteNote(deleteStore.notes[0].id)
    #expect(deleteStore.notes.isEmpty)
    #expect(try s11SnapshotB() == baseline, "implicit delete must not trash synthetic default audio")

    let activeRef = AudioRecording(fileURL: activeCAF, duration: 1, sampleRate: 48_000, channelCount: 1)
    let retentionStore = NoteStore(
        notes: [
            BolabolNote(title: "New", rawText: "", audioRecording: activeRef),
            BolabolNote(title: "Old", rawText: "", audioRecording: oldRef),
        ],
        fileManager: fm
    )
    retentionStore.enforceAudioArchiveLimit(maxRecordings: 1)
    #expect(retentionStore.notes.count == 1, "memory retention still trims")
    #expect(retentionStore.notes.first?.title == "New")
    #expect(try s11SnapshotB() == baseline, "implicit retention must not trash synthetic default audio")

    let purgeStore = NoteStore(
        notes: [BolabolNote(title: "Text", rawText: "text")],
        fileManager: fm
    )
    #expect(purgeStore.purgeOrphanedRecordings(olderThan: 0) == 0)
    #expect(try s11SnapshotB() == baseline, "implicit purge(olderThan:0) must trash nothing")

    // 3. Explicit nonpersistent stores at the same default root — an alternate
    // metadata filename or a symlink alias — gain no authority either.
    let altJSONStore = NoteStore(
        notes: [BolabolNote(title: "Text", rawText: "text")],
        fileManager: fm,
        notesFileURL: bRoot.appendingPathComponent("alt-metadata.json")
    )
    altJSONStore.clearAll()
    #expect(altJSONStore.notes.isEmpty)
    #expect(altJSONStore.purgeOrphanedRecordings(olderThan: 0) == 0)
    #expect(try s11SnapshotB() == baseline, "alternate filename in the default root grants no authority")

    let aliasDir = scratch.appendingPathComponent("AliasSupport", isDirectory: true)
    try manager.createSymbolicLink(at: aliasDir, withDestinationURL: syntheticSupport)
    let aliasFM = S11RedirectedFileManager(redirectedBase: aliasDir)
    let aliasStore = NoteStore(
        notes: [BolabolNote(title: "Text", rawText: "text")],
        fileManager: aliasFM,
        notesFileURL: aliasDir.appendingPathComponent("NativeBolabol", isDirectory: true)
            .appendingPathComponent("notes.json")
    )
    aliasStore.clearAll()
    #expect(aliasStore.purgeOrphanedRecordings(olderThan: 0) == 0)
    #expect(try s11SnapshotB() == baseline, "symlink alias of the default root grants no authority")

    // 4. Positive control: an explicitly owned root A still cleans itself.
    let aRoot = scratch.appendingPathComponent("OwnedA", isDirectory: true)
    let aRecordings = aRoot.appendingPathComponent("Recordings", isDirectory: true)
    try manager.createDirectory(at: aRecordings, withIntermediateDirectories: true)
    let aLinked = aRecordings.appendingPathComponent("linked.caf")
    let aOrphan = aRecordings.appendingPathComponent("orphan.caf")
    _ = try s11WriteValidCAF(at: aLinked, frameCount: 4800)
    _ = try s11WriteValidCAF(at: aOrphan, frameCount: 4800)
    try manager.setAttributes(
        [.modificationDate: Date.now.addingTimeInterval(-3600)],
        ofItemAtPath: aOrphan.path
    )
    let ownedStore = NoteStore(
        notes: [BolabolNote(
            title: "Owned",
            rawText: "",
            audioRecording: AudioRecording(fileURL: aLinked, duration: 1, sampleRate: 48_000, channelCount: 1)
        )],
        fileManager: fm,
        notesFileURL: aRoot.appendingPathComponent("notes.json")
    )
    #expect(ownedStore.purgeOrphanedRecordings() == 1)
    #expect(manager.fileExists(atPath: aLinked.path))
    #expect(!manager.fileExists(atPath: aOrphan.path))
    ownedStore.clearAll()
    #expect(ownedStore.notes.isEmpty)
    #expect(!manager.fileExists(atPath: aLinked.path))
    #expect(try s11SnapshotB() == baseline, "owned-root cleanup must not spill into B")

    // 5. Live path still works: keep writing through the open handle, close,
    // reopen with AVAudioFile, and run the real production 16 kHz conversion.
    try activeWriter?.write(from: s11SineBuffer(frameCount: 24_000, frequency: 660))
    activeWriter = nil
    let reopened = try AVAudioFile(forReading: activeCAF)
    #expect(reopened.processingFormat.sampleRate == 48_000)
    #expect(reopened.processingFormat.channelCount == 1)
    #expect(reopened.length >= 48_000)
    let wavOut = scratch.appendingPathComponent("active-16k.wav")
    try GeminiCloudDictationEngine.convertTo16kMonoWAV(source: activeCAF, destination: wavOut)
    #expect((try manager.attributesOfItem(atPath: wavOut.path)[.size] as? Int ?? 0) > 0)
    let wavFile = try AVAudioFile(forReading: wavOut)
    #expect(wavFile.processingFormat.sampleRate == 16_000)
    #expect(wavFile.processingFormat.channelCount == 1)
    #expect(wavFile.length > 0)

    // 6. B byte-identical apart from the live writer's own growth.
    let afterLive = try s11SnapshotB()
    #expect(afterLive[oldCAF.path] == baseline[oldCAF.path])
    #expect(afterLive[bNotesURL.path] == baseline[bNotesURL.path])
    #expect(
        (afterLive[activeCAF.path] ?? 0) > (baseline[activeCAF.path] ?? 0),
        "active CAF must have grown via the open writer"
    )
}

@MainActor
@Test
func s11InjectedRetentionPolicyAppliesOnlyToItsStore() throws {
    // Constructor preferences are injected; nil means no ambient saved policy.
    // Nothing here reads or writes UserDefaults.standard.
    let manager = FileManager.default
    let root = manager.temporaryDirectory
        .appendingPathComponent("bolabol-s11-prefs-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }

    let enabledSuite = "bolabol-s11-prefs-enabled-\(UUID().uuidString)"
    let enabledDefaults = try #require(UserDefaults(suiteName: enabledSuite))
    defer { UserDefaults.standard.removePersistentDomain(forName: enabledSuite) }
    enabledDefaults.set(
        try JSONEncoder().encode(GeneralSettings(isAutoArchiveCleanupEnabled: true, maxSavedAudioRecordings: 2)),
        forKey: "general.settings"
    )

    // A store with the injected enabled cap-2 policy trims on plain insertion.
    // (The cap floor is 2: GeneralSettings.normalize clamps lower values.)
    let policyRoot = root.appendingPathComponent("Policy", isDirectory: true)
    let policyRecordings = policyRoot.appendingPathComponent("Recordings", isDirectory: true)
    try manager.createDirectory(at: policyRecordings, withIntermediateDirectories: true)
    let policyStore = NoteStore(
        notes: [],
        notesFileURL: policyRoot.appendingPathComponent("notes.json"),
        isPersistenceEnabled: true,
        userDefaults: enabledDefaults
    )
    let p1URL = policyRecordings.appendingPathComponent("p1.caf")
    let p2URL = policyRecordings.appendingPathComponent("p2.caf")
    let p3URL = policyRecordings.appendingPathComponent("p3.caf")
    try Data("p1".utf8).write(to: p1URL)
    try Data("p2".utf8).write(to: p2URL)
    try Data("p3".utf8).write(to: p3URL)
    let p1 = policyStore.addRecordedNote(
        recording: AudioRecording(fileURL: p1URL, duration: 1, sampleRate: 48_000, channelCount: 1)
    )
    let p2 = policyStore.addRecordedNote(
        recording: AudioRecording(fileURL: p2URL, duration: 1, sampleRate: 48_000, channelCount: 1)
    )
    let p3 = policyStore.addRecordedNote(
        recording: AudioRecording(fileURL: p3URL, duration: 1, sampleRate: 48_000, channelCount: 1)
    )
    #expect(policyStore.note(withID: p3.id) != nil)
    #expect(policyStore.note(withID: p2.id) != nil)
    #expect(policyStore.note(withID: p1.id) == nil, "injected enabled cap-2 policy must evict the oldest on insert")
    #expect(!manager.fileExists(atPath: p1URL.path))
    #expect(manager.fileExists(atPath: p2URL.path))
    #expect(manager.fileExists(atPath: p3URL.path))

    // The same shape without injected policy keeps everything, including
    // across completion-time re-enforcement.
    let plainRecordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try manager.createDirectory(at: plainRecordings, withIntermediateDirectories: true)
    let plainStore = NoteStore(
        notes: [],
        notesFileURL: root.appendingPathComponent("plain-notes.json"),
        isPersistenceEnabled: true
    )
    let q1URL = plainRecordings.appendingPathComponent("q1.caf")
    let q2URL = plainRecordings.appendingPathComponent("q2.caf")
    try Data("q1".utf8).write(to: q1URL)
    try Data("q2".utf8).write(to: q2URL)
    let q1 = plainStore.addRecordedNote(
        recording: AudioRecording(fileURL: q1URL, duration: 1, sampleRate: 48_000, channelCount: 1)
    )
    let q2 = plainStore.addRecordedNote(
        recording: AudioRecording(fileURL: q2URL, duration: 1, sampleRate: 48_000, channelCount: 1)
    )
    plainStore.markTranscriptionStarted(for: q1.id)
    plainStore.applyTranscriptionResult(
        for: q1.id,
        result: TranscriptionResult(text: "done", diagnostics: EngineDiagnostics(backendName: "QA"))
    )
    #expect(plainStore.note(withID: q1.id) != nil)
    #expect(plainStore.note(withID: q2.id) != nil, "nil policy must skip completion-time trimming")
    #expect(manager.fileExists(atPath: q1URL.path))
    #expect(manager.fileExists(atPath: q2URL.path))
}

@MainActor
@Test
func s11CustomRootLiveStoreKeepsLedgerLocal() throws {
    // Custom-root live() wires <notes-root>/Logs/session-ledger.log and takes
    // only explicitly passed preferences — never the production log or the
    // process-standard policy.
    NoteStore.resetLiveInstancesForTesting()
    defer { NoteStore.resetLiveInstancesForTesting() }
    let manager = FileManager.default
    let root = manager.temporaryDirectory
        .appendingPathComponent("bolabol-s11-ledger-\(UUID().uuidString)", isDirectory: true)
    let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    try manager.createDirectory(at: recordings, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let notesURL = root.appendingPathComponent("notes.json")

    let suiteName = "bolabol-s11-ledger-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    let store = NoteStore.live(notesFileURL: notesURL, userDefaults: defaults)
    let expectedLedger = root.appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("session-ledger.log")
    #expect(store.ledger?.ledgerURL == expectedLedger)
    #expect(store.ledger?.ledgerURL.path.hasPrefix(root.path) == true)

    let audioURL = recordings.appendingPathComponent("session.caf")
    try Data("audio".utf8).write(to: audioURL)
    _ = store.addRecordedNote(
        recording: AudioRecording(fileURL: audioURL, duration: 1, sampleRate: 48_000, channelCount: 1),
        maxRecordingsLimit: 50
    )
    #expect(manager.fileExists(atPath: expectedLedger.path), "factory ledger must append inside the owning root")
    #expect(try String(contentsOf: expectedLedger, encoding: .utf8).contains("event=note.add"))
}
