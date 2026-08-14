import Foundation

/// Multi-key Gemini credential bank with BOLABOL-compatible disable markers.
///
/// Storage is intentionally simple: each entry is either a raw key or
/// `#DISABLED#` + key. The first enabled key remains the primary key used by
/// model listing / validation. Runtime generation iterates `enabledKeys` and
/// rotates only on quota/rate-limit failures.
public struct GeminiAPIKeyBank: Codable, Equatable, Sendable {
    public static let maxKeys = 10
    public static let disabledPrefix = "#DISABLED#"

    public var entries: [String]

    public init(entries: [String] = []) {
        self.entries = Self.normalize(entries)
    }

    public init(primaryKey: String) {
        let trimmed = primaryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.entries = trimmed.isEmpty ? [] : [trimmed]
    }

    /// Backward-compatible primary key used by existing single-key call sites.
    public var primaryKey: String {
        get { enabledKeys.first ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if entries.isEmpty {
                entries = trimmed.isEmpty ? [] : [trimmed]
                return
            }
            // Prefer the first currently enabled slot so disabling key #1 does not
            // overwrite a disabled entry when syncing the legacy primary key.
            let target = entries.firstIndex { entry in
                let value = entry.trimmingCharacters(in: .whitespacesAndNewlines)
                return !value.isEmpty && !value.hasPrefix(Self.disabledPrefix)
            } ?? 0
            let disabled = isDisabled(at: target)
            let clean = Self.clean(trimmed)
            if clean.isEmpty && !disabled {
                entries[target] = ""
            } else if clean.isEmpty {
                entries[target] = Self.disabledPrefix
            } else {
                entries[target] = disabled ? "\(Self.disabledPrefix)\(clean)" : clean
            }
            entries = Self.normalize(entries)
        }
    }

    public var configuredCount: Int {
        entries
            .map(Self.clean)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    public var enabledKeys: [String] {
        entries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix(Self.disabledPrefix) }
            .map(Self.clean)
            .filter { !$0.isEmpty }
    }

    public var hasEnabledKey: Bool {
        !enabledKeys.isEmpty
    }

    public func cleanKey(at index: Int) -> String {
        guard entries.indices.contains(index) else { return "" }
        return Self.clean(entries[index])
    }

    public func isDisabled(at index: Int) -> Bool {
        guard entries.indices.contains(index) else { return false }
        return entries[index]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix(Self.disabledPrefix)
    }

    public mutating func addKey(_ key: String = "") {
        guard entries.count < Self.maxKeys else { return }
        entries.append(key.trimmingCharacters(in: .whitespacesAndNewlines))
        entries = Self.normalize(entries)
    }

    public mutating func removeKey(at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries.remove(at: index)
        entries = Self.normalize(entries)
    }

    public mutating func updateKey(_ key: String, at index: Int) {
        guard entries.indices.contains(index) else { return }
        let clean = Self.clean(key)
        entries[index] = isDisabled(at: index) && !clean.isEmpty
            ? "\(Self.disabledPrefix)\(clean)"
            : clean
        entries = Self.normalize(entries)
    }

    public mutating func toggleDisabled(at index: Int) {
        guard entries.indices.contains(index) else { return }
        let clean = Self.clean(entries[index])
        guard !clean.isEmpty else { return }
        entries[index] = isDisabled(at: index) ? clean : "\(Self.disabledPrefix)\(clean)"
    }

    public mutating func enableAll() {
        entries = entries.map(Self.clean)
        entries = Self.normalize(entries)
    }

    public mutating func disableAllExcept(at targetIndex: Int) {
        guard entries.indices.contains(targetIndex) else { return }
        for index in entries.indices {
            let clean = Self.clean(entries[index])
            guard !clean.isEmpty else { continue }
            entries[index] = index == targetIndex ? clean : "\(Self.disabledPrefix)\(clean)"
        }
        entries = Self.normalize(entries)
    }

    /// Hard quota / rate-limit signals. These almost always mean "this key is spent
    /// for now" and should rotate immediately to the next enabled key.
    public static func isQuotaFailure(status: Int, body: String) -> Bool {
        if status == 429 { return true }
        let lowered = body.lowercased()
        return lowered.contains("resource_exhausted")
            || lowered.contains("quota")
            || lowered.contains("rate limit")
            || lowered.contains("ratelimit")
            || lowered.contains("too many requests")
    }

    /// Transient capacity / availability failures (e.g. Gemini HTTP 503
    /// "high demand" / UNAVAILABLE). Not a bad key — try the next key, and/or
    /// retry after a short backoff.
    public static func isCapacityFailure(status: Int, body: String) -> Bool {
        if status == 502 || status == 503 || status == 504 { return true }
        let lowered = body.lowercased()
        return lowered.contains("\"status\": \"unavailable\"")
            || lowered.contains("\"status\":\"unavailable\"")
            || lowered.contains("high demand")
            || lowered.contains("try again later")
            || lowered.contains("overloaded")
            || lowered.contains("temporarily unavailable")
            || lowered.contains("service unavailable")
    }

    /// Any Gemini failure that should rotate to another enabled key instead of
    /// failing the whole job on the first attempt.
    public static func isRotatableFailure(status: Int, body: String) -> Bool {
        isQuotaFailure(status: status, body: body)
            || isCapacityFailure(status: status, body: body)
    }

    /// Short pause before retrying a capacity failure. Quota failures skip delay.
    public static func retryDelayNanoseconds(status: Int, body: String, attempt: Int) -> UInt64? {
        guard isCapacityFailure(status: status, body: body) else { return nil }
        // 0.4s, 0.8s, 1.2s… capped at 2.0s
        let steps = max(1, min(attempt + 1, 5))
        return UInt64(steps) * 400_000_000
    }

    public static func clean(_ raw: String) -> String {
        var key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.hasPrefix(disabledPrefix) {
            key = String(key.dropFirst(disabledPrefix.count))
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(_ entries: [String]) -> [String] {
        var normalized: [String] = []
        for entry in entries.prefix(maxKeys) {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                normalized.append("")
                continue
            }
            let disabled = trimmed.hasPrefix(disabledPrefix)
            let clean = clean(trimmed)
            if clean.isEmpty {
                normalized.append("")
            } else {
                normalized.append(disabled ? "\(disabledPrefix)\(clean)" : clean)
            }
        }
        // Keep a single empty slot only when the bank itself is empty.
        if normalized.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return normalized.isEmpty ? [] : [""]
        }
        return normalized
    }
}
