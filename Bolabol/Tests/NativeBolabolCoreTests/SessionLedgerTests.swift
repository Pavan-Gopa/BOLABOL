import Foundation
import NativeBolabolCore
import Testing

// ADR-030: persistent privacy-safe session ledger at
// ~/Library/Application Support/NativeBolabol/Logs/session-ledger.log,
// rotated at 2 MB to `.1`. Never transcript text or API keys.

private func ledgerTempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("bolabol-ledger-\(UUID().uuidString)")
        .appendingPathComponent("session-ledger.log")
}

private func ledgerContents(_ ledger: SessionLedger) throws -> String {
    try String(contentsOf: ledger.ledgerURL, encoding: .utf8)
}

@Test
func sessionLedgerAppendsPrivacySafeEventLines() throws {
    let ledger = SessionLedger(fileURL: ledgerTempURL())
    ledger.record(sessionID: "abc", event: "note.add", fields: ["count": "3", "limit": "50"])
    ledger.record(sessionID: "abc", event: "polish", fields: ["engine": "Google", "ms": "1200"])

    let contents = try ledgerContents(ledger)
    #expect(contents.contains("event=note.add"))
    #expect(contents.contains("count=3"))
    #expect(contents.contains("event=polish"))
}
@Test
func sessionLedgerNeverKeepsTextOrSecrets() throws {
    let ledger = SessionLedger(fileURL: ledgerTempURL())
    ledger.record(
        sessionID: "s1",
        event: "transcription.done",
        fields: [
            "transcript": "Привет secret text here",
            "chars": "21",
        ]
    )

    let contents = try ledgerContents(ledger)
    // Cyrillic transcript text cannot survive the safe-token charset.
    #expect(!contents.contains("Привет"))
    // Separators are the only spaces; values use the safe charset.
    #expect(contents.contains("transcript=_______secret_text_here"))
    #expect(contents.contains("chars=21"))
}

@Test
func sessionLedgerRotatesAtSizeCap() throws {
    let url = ledgerTempURL()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // Prefill past the 2 MB cap, then one record must rotate to `.1`.
    let filler = Data(repeating: 0x41, count: SessionLedger.maxBytes + 16)
    try filler.write(to: url, options: .atomic)

    let ledger = SessionLedger(fileURL: url)
    ledger.record(sessionID: "s", event: "finish", fields: ["cue": "Bottle"])

    let backup = url.appendingPathExtension("1")
    #expect(FileManager.default.fileExists(atPath: backup.path), "oversized ledger must rotate to .1")
    let current = try String(contentsOf: url, encoding: .utf8)
    #expect(current.contains("event=finish"))
    #expect(current.count < SessionLedger.maxBytes)
}

@Test
func sessionLedgerDefaultURLIsShippedPath() {
    let ledger = SessionLedger()
    let path = ledger.ledgerURL.path
    #expect(path.hasSuffix("NativeBolabol/Logs/session-ledger.log"))
}

@Test
func sessionLedgerRotatesExactlyAtTwoMegabytesAndReplacesOldBackup() throws {
    let url = ledgerTempURL()
    let manager = FileManager.default
    try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: url.deletingLastPathComponent()) }
    let backup = url.appendingPathExtension("1")
    try Data("previous backup".utf8).write(to: backup)
    let boundary = Data(repeating: 0x42, count: SessionLedger.maxBytes)
    try boundary.write(to: url)

    SessionLedger(fileURL: url).record(event: "finish", fields: ["cue": "Funk"])

    #expect(try Data(contentsOf: backup) == boundary)
    let current = try String(contentsOf: url, encoding: .utf8)
    #expect(current.contains("event=finish"))
    #expect(current.contains("cue=Funk"))
}

@MainActor
@Test
func sessionLedgerNotePersistenceDoesNotRecordEnglishTranscriptOrTitle() throws {
    let url = ledgerTempURL()
    let root = url.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = NoteStore(
        notes: [],
        notesFileURL: root.appendingPathComponent("notes.json"),
        isPersistenceEnabled: true
    )
    let ledger = SessionLedger(fileURL: url)
    store.ledger = ledger
    let note = store.addEmptyNote(title: "ConfidentialCustomerTitle")
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "ConfidentialCustomerTranscript",
            diagnostics: EngineDiagnostics(backendName: "QA")
        )
    )
    let contents = try ledgerContents(ledger)
    #expect(contents.contains("event=note.add"))
    #expect(contents.contains("event=notes.save"))
    #expect(!contents.contains("ConfidentialCustomerTitle"))
    #expect(!contents.contains("ConfidentialCustomerTranscript"))
}
