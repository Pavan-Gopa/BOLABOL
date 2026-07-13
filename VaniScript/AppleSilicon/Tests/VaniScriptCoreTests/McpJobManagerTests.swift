import Foundation
import Testing
@testable import VaniScriptCore

@MainActor
@Suite("VaniScript MCP jobs")
struct McpJobManagerTests {
    @Test("reports progress and stores a successful result")
    func successfulJob() async throws {
        let manager = McpJobManager()
        let jobID = manager.start(kind: "test", message: "Starting") { reporter in
            reporter.update(progress: 0.5, stage: "Halfway", message: "Working")
            try await Task.sleep(for: .milliseconds(10))
            return ["value": 42]
        }

        try await waitUntilFinished(manager: manager, jobID: jobID)
        let job = try #require(manager.get(id: jobID))
        #expect(job["status"] as? String == McpJobStatus.succeeded.rawValue)
        #expect(job["progress"] as? Double == 1)
        #expect((job["result"] as? [String: Any])?["value"] as? Int == 42)
    }

    @Test("cancels a running cancellable job")
    func cancelledJob() async throws {
        let manager = McpJobManager()
        let jobID = manager.start(kind: "test", message: "Waiting") { reporter in
            reporter.update(progress: 0.1, stage: "Waiting")
            try await Task.sleep(for: .seconds(5))
            return [:]
        }

        await Task.yield()
        #expect(manager.cancel(id: jobID))
        let job = try #require(manager.get(id: jobID))
        #expect(job["status"] as? String == McpJobStatus.cancelled.rawValue)
        #expect(job["cancellable"] as? Bool == false)
    }
}

private extension McpJobManagerTests {
    func waitUntilFinished(manager: McpJobManager, jobID: String) async throws {
        for _ in 0..<100 {
            let status = manager.get(id: jobID)?["status"] as? String
            if status == McpJobStatus.succeeded.rawValue
                || status == McpJobStatus.failed.rawValue
                || status == McpJobStatus.cancelled.rawValue {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Job did not finish in time")
    }
}
