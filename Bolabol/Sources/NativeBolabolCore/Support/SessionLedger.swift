import Foundation

/// Persistent privacy-safe per-session event log (ADR-030).
///
/// File: ~/Library/Application Support/NativeBolabol/Logs/session-ledger.log,
/// rotated at 2 MB to `.1`. Never records transcript text or API keys —
/// only lengths, counts, language codes, key indices, error classes, timings.
public final class SessionLedger: @unchecked Sendable {
    /// Process-wide ledger used by the shipped app (ADR-030).
    public static let shared = SessionLedger()

    public static let maxBytes: Int = 2 * 1024 * 1024

    private let lock = NSLock()
    private let fileURL: URL
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.fileURL = base
                .appendingPathComponent("NativeBolabol", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("session-ledger.log", isDirectory: false)
        }
        self.now = now
    }

    public var ledgerURL: URL { fileURL }

    /// Appends one privacy-safe event line. `fields` must contain counts,
    /// codes, indices, error classes, timings — never text or secrets.
    public func record(sessionID: String = "-", event: String, fields: [String: String] = [:]) {
        let sanitized = fields.mapValues { Self.sanitize($0) }
        var parts = ["ts=\(ISO8601DateFormatter().string(from: now()))", "session=\(Self.sanitize(sessionID))", "event=\(Self.sanitize(event))"]
        for key in sanitized.keys.sorted() {
            parts.append("\(key)=\(sanitized[key] ?? "")")
        }
        append(parts.joined(separator: " ") + "\n")
    }

    private func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            rotateIfNeeded()
            let data = Data(line.utf8)
            if fileManager.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            // Ledger must never break the session path.
        }
    }

    private func rotateIfNeeded() {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? Int, size >= Self.maxBytes
        else { return }
        let backup = fileURL.appendingPathExtension("1")
        try? fileManager.removeItem(at: backup)
        try? fileManager.moveItem(at: fileURL, to: backup)
    }

    /// Strips anything that could carry transcript text or secrets: keeps only
    /// a safe token charset, truncates to 64 chars.
    static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.:/+%@")
        let filtered = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        return String(filtered.prefix(64))
    }
}
