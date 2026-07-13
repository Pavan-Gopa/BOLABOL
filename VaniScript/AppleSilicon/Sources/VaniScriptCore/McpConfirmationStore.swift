import Foundation

@MainActor
public final class McpConfirmationStore {
    private struct Entry {
        let operation: String
        let fingerprint: String
        let projectRevision: String
        let expiresAt: Date
    }

    private var entries = [String: Entry]()
    private let lifetime: TimeInterval

    public init(lifetime: TimeInterval = 120) {
        self.lifetime = lifetime
    }

    public func issue(operation: String, fingerprint: String, projectRevision: String) -> String {
        removeExpired()
        let token = UUID().uuidString.lowercased()
        entries[token] = Entry(
            operation: operation,
            fingerprint: fingerprint,
            projectRevision: projectRevision,
            expiresAt: Date().addingTimeInterval(lifetime)
        )
        return token
    }

    public func consume(
        token: String,
        operation: String,
        fingerprint: String,
        projectRevision: String
    ) -> Bool {
        removeExpired()
        guard let entry = entries.removeValue(forKey: token),
              entry.operation == operation,
              entry.fingerprint == fingerprint,
              entry.projectRevision == projectRevision,
              entry.expiresAt > Date()
        else {
            return false
        }
        return true
    }

    private func removeExpired() {
        let now = Date()
        entries = entries.filter { $0.value.expiresAt > now }
    }
}
