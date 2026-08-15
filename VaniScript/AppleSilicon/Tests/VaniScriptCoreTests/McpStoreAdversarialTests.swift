import Foundation
import Testing
@testable import VaniScriptCore

@Suite("MCP audit/cache/confirmation adversarial boundaries")
struct McpStoreAdversarialTests {
    @Test("audit store keeps newest-first order and trims to configured capacity")
    @MainActor
    func auditCapacityAndOrder() {
        let store = McpAuditStore(capacity: 10)
        for index in 0..<15 {
            store.record(
                toolName: "tool-\(index)",
                requestID: "req-\(index)",
                previousRevision: "r\(index)",
                projectRevision: "r\(index + 1)"
            )
        }
        let page = store.list(cursor: 0, limit: 100)
        #expect(page["total"] as? Int == 10)
        let changes = page["changes"] as? [[String: Any]]
        #expect(changes?.count == 10)
        #expect(changes?.first?["toolName"] as? String == "tool-14")
        #expect(changes?.last?["toolName"] as? String == "tool-5")
    }

    @Test("audit capacity below ten is deliberately clamped to ten")
    @MainActor
    func auditMinimumCapacity() {
        let store = McpAuditStore(capacity: 1)
        for index in 0..<11 {
            store.record(toolName: "t\(index)", requestID: nil, previousRevision: "a", projectRevision: "b")
        }
        #expect(store.list(cursor: 0, limit: 100)["total"] as? Int == 10)
    }

    @Test("audit pagination clamps negative cursor, minimum limit, and maximum limit")
    @MainActor
    func auditPaginationClamps() {
        let store = McpAuditStore(capacity: 200)
        for index in 0..<150 {
            store.record(toolName: "t\(index)", requestID: nil, previousRevision: "a", projectRevision: "b")
        }

        let negative = store.list(cursor: -9, limit: 0)
        #expect(negative["cursor"] as? Int == 0)
        #expect((negative["changes"] as? [[String: Any]])?.count == 1)
        #expect(negative["nextCursor"] as? Int == 1)
        #expect(negative["hasMore"] as? Bool == true)

        let huge = store.list(cursor: 0, limit: 999)
        #expect((huge["changes"] as? [[String: Any]])?.count == 100)
        #expect(huge["nextCursor"] as? Int == 100)
        #expect(huge["hasMore"] as? Bool == true)
    }

    @Test("audit page beyond end is empty and stable")
    @MainActor
    func auditBeyondEnd() {
        let store = McpAuditStore()
        store.record(toolName: "one", requestID: nil, previousRevision: "a", projectRevision: "b")
        let page = store.list(cursor: 100, limit: 20)
        #expect((page["changes"] as? [[String: Any]])?.isEmpty == true)
        #expect(page["cursor"] as? Int == 100)
        #expect(page["nextCursor"] as? Int == 100)
        #expect(page["hasMore"] as? Bool == false)
    }

    @Test("audit dictionary never leaks nil requestID as null")
    @MainActor
    func auditNilRequestIDIsEmptyString() {
        let store = McpAuditStore()
        let record = store.record(toolName: "tool", requestID: nil, previousRevision: "a", projectRevision: "b")
        #expect(record.dictionary["requestId"] as? String == "")
        #expect(!record.id.isEmpty)
        #expect(record.id == record.id.lowercased())
    }

    @Test("request cache fingerprint ignores requestId and dictionary insertion order")
    @MainActor
    func fingerprintCanonicalization() {
        let first: [String: Any] = ["requestId": "one", "z": 2, "a": "x"]
        let second: [String: Any] = ["a": "x", "z": 2, "requestId": "two"]
        #expect(McpRequestCache.fingerprint(arguments: first) == McpRequestCache.fingerprint(arguments: second))
    }

    @Test("request cache exact replay marks result idempotent without mutating stored result")
    @MainActor
    func requestReplay() throws {
        let cache = McpRequestCache(lifetime: 60)
        cache.store(requestID: "r", toolName: "tool", fingerprint: "fp", result: ["value": 7])
        let firstResult = try cache.result(requestID: "r", toolName: "tool", fingerprint: "fp")
        let first = try #require(firstResult)
        #expect(first["value"] as? Int == 7)
        #expect(first["idempotentReplay"] as? Bool == true)
        let secondResult = try cache.result(requestID: "r", toolName: "tool", fingerprint: "fp")
        let second = try #require(secondResult)
        #expect(second["idempotentReplay"] as? Bool == true)
    }

    @Test("request ID reuse with another tool or fingerprint is rejected")
    @MainActor
    func requestIDConflict() {
        let cache = McpRequestCache(lifetime: 60)
        cache.store(requestID: "r", toolName: "tool", fingerprint: "fp", result: ["ok": true])
        #expect(throws: Error.self) {
            _ = try cache.result(requestID: "r", toolName: "other", fingerprint: "fp")
        }
        #expect(throws: Error.self) {
            _ = try cache.result(requestID: "r", toolName: "tool", fingerprint: "different")
        }
    }

    @Test("expired request cache entry disappears without conflict")
    @MainActor
    func expiredRequestCache() throws {
        let cache = McpRequestCache(lifetime: -1)
        cache.store(requestID: "r", toolName: "tool", fingerprint: "fp", result: ["ok": true])
        #expect(try cache.result(requestID: "r", toolName: "tool", fingerprint: "fp") == nil)
        #expect(try cache.result(requestID: "r", toolName: "other", fingerprint: "different") == nil)
    }

    @Test("confirmation token is single-use")
    @MainActor
    func confirmationSingleUse() {
        let store = McpConfirmationStore(lifetime: 60)
        let token = store.issue(operation: "delete", fingerprint: "fp", projectRevision: "r1")
        #expect(store.consume(token: token, operation: "delete", fingerprint: "fp", projectRevision: "r1"))
        #expect(!store.consume(token: token, operation: "delete", fingerprint: "fp", projectRevision: "r1"))
    }

    @Test("confirmation mismatch consumes the token fail-closed")
    @MainActor
    func confirmationMismatchBurnsToken() {
        let store = McpConfirmationStore(lifetime: 60)
        let token = store.issue(operation: "delete", fingerprint: "fp", projectRevision: "r1")
        #expect(!store.consume(token: token, operation: "delete", fingerprint: "WRONG", projectRevision: "r1"))
        #expect(!store.consume(token: token, operation: "delete", fingerprint: "fp", projectRevision: "r1"))
    }

    @Test("confirmation binds operation and project revision")
    @MainActor
    func confirmationBinding() {
        let store = McpConfirmationStore(lifetime: 60)
        let operationToken = store.issue(operation: "delete", fingerprint: "fp", projectRevision: "r1")
        #expect(!store.consume(token: operationToken, operation: "rename", fingerprint: "fp", projectRevision: "r1"))

        let revisionToken = store.issue(operation: "delete", fingerprint: "fp", projectRevision: "r1")
        #expect(!store.consume(token: revisionToken, operation: "delete", fingerprint: "fp", projectRevision: "r2"))
    }

    @Test("expired confirmation is rejected")
    @MainActor
    func expiredConfirmation() {
        let store = McpConfirmationStore(lifetime: -1)
        let token = store.issue(operation: "delete", fingerprint: "fp", projectRevision: "r1")
        #expect(!store.consume(token: token, operation: "delete", fingerprint: "fp", projectRevision: "r1"))
    }

    @Test("independently issued confirmations are unique")
    @MainActor
    func confirmationTokensUnique() {
        let store = McpConfirmationStore(lifetime: 60)
        let first = store.issue(operation: "op", fingerprint: "fp", projectRevision: "r")
        let second = store.issue(operation: "op", fingerprint: "fp", projectRevision: "r")
        #expect(first != second)
        #expect(first == first.lowercased())
        #expect(second == second.lowercased())
    }
}
