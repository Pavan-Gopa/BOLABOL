import Foundation

public struct McpChangeRecord: Equatable, Sendable {
    public let id: String
    public let toolName: String
    public let requestID: String?
    public let previousRevision: String
    public let projectRevision: String
    public let createdAt: String

    public var dictionary: [String: Any] {
        [
            "changeSetId": id,
            "toolName": toolName,
            "requestId": requestID ?? "",
            "previousRevision": previousRevision,
            "projectRevision": projectRevision,
            "createdAt": createdAt,
        ]
    }
}

@MainActor
public final class McpAuditStore {
    private var records: [McpChangeRecord] = []
    private let capacity: Int

    public init(capacity: Int = 500) {
        self.capacity = max(10, capacity)
    }

    @discardableResult
    public func record(
        toolName: String,
        requestID: String?,
        previousRevision: String,
        projectRevision: String
    ) -> McpChangeRecord {
        let record = McpChangeRecord(
            id: UUID().uuidString.lowercased(),
            toolName: toolName,
            requestID: requestID,
            previousRevision: previousRevision,
            projectRevision: projectRevision,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        records.insert(record, at: 0)
        if records.count > capacity { records.removeLast(records.count - capacity) }
        return record
    }

    public func list(cursor: Int, limit: Int) -> [String: Any] {
        let offset = max(0, cursor)
        let pageSize = max(1, min(100, limit))
        let page = Array(records.dropFirst(offset).prefix(pageSize))
        return [
            "changes": page.map(\.dictionary),
            "cursor": offset,
            "nextCursor": offset + page.count,
            "hasMore": offset + page.count < records.count,
            "total": records.count,
        ]
    }
}

@MainActor
public final class McpRequestCache {
    private struct Entry {
        let toolName: String
        let fingerprint: String
        let result: [String: Any]
        let createdAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let lifetime: TimeInterval

    public init(lifetime: TimeInterval = 900) {
        self.lifetime = lifetime
    }

    public func result(requestID: String, toolName: String, fingerprint: String) throws -> [String: Any]? {
        removeExpired()
        guard let entry = entries[requestID] else { return nil }
        guard entry.toolName == toolName, entry.fingerprint == fingerprint else {
            throw NSError(
                domain: "McpRequestCache",
                code: -8,
                userInfo: [NSLocalizedDescriptionKey: "REQUEST_ID_CONFLICT: requestId was already used with different arguments"]
            )
        }
        var replay = entry.result
        replay["idempotentReplay"] = true
        return replay
    }

    public func store(requestID: String, toolName: String, fingerprint: String, result: [String: Any]) {
        removeExpired()
        entries[requestID] = Entry(toolName: toolName, fingerprint: fingerprint, result: result, createdAt: Date())
    }

    public static func fingerprint(arguments: [String: Any]) -> String {
        let normalized = arguments.filter { $0.key != "requestId" }
        guard JSONSerialization.isValidJSONObject(normalized),
              let data = try? JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys]) else {
            return String(describing: normalized)
        }
        return data.base64EncodedString()
    }

    private func removeExpired() {
        let cutoff = Date().addingTimeInterval(-lifetime)
        entries = entries.filter { $0.value.createdAt > cutoff }
    }
}
