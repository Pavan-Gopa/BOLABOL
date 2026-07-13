import Foundation

public enum McpJobStatus: String, Equatable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
}

@MainActor
public final class McpJobReporter {
    private weak var manager: McpJobManager?
    private let jobID: String

    fileprivate init(manager: McpJobManager, jobID: String) {
        self.manager = manager
        self.jobID = jobID
    }

    public func update(progress: Double, stage: String, message: String = "") {
        manager?.update(jobID: jobID, progress: progress, stage: stage, message: message)
    }

    public func checkCancellation() throws {
        try Task.checkCancellation()
    }
}

@MainActor
public final class McpJobManager {
    private struct JobRecord {
        let id: String
        let kind: String
        let createdAt: Date
        let cancellable: Bool
        var status: McpJobStatus
        var progress: Double
        var stage: String
        var message: String
        var updatedAt: Date
        var finishedAt: Date?
        var result: [String: Any]?
        var error: String?
    }

    private var records = [String: JobRecord]()
    private var orderedIDs = [String]()
    private var tasks = [String: Task<Void, Never>]()
    private let maximumRetainedJobs: Int

    public init(maximumRetainedJobs: Int = 100) {
        self.maximumRetainedJobs = max(10, maximumRetainedJobs)
    }

    @discardableResult
    public func start(
        kind: String,
        message: String,
        cancellable: Bool = true,
        operation: @escaping @MainActor (McpJobReporter) async throws -> [String: Any]
    ) -> String {
        pruneIfNeeded()
        let id = "job-\(UUID().uuidString.lowercased())"
        let now = Date()
        records[id] = JobRecord(
            id: id,
            kind: kind,
            createdAt: now,
            cancellable: cancellable,
            status: .queued,
            progress: 0,
            stage: "Queued",
            message: message,
            updatedAt: now,
            finishedAt: nil,
            result: nil,
            error: nil
        )
        orderedIDs.insert(id, at: 0)
        let reporter = McpJobReporter(manager: self, jobID: id)
        tasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            self.markRunning(id)
            do {
                let result = try await operation(reporter)
                try Task.checkCancellation()
                self.finish(id, status: .succeeded, result: result, error: nil)
            } catch is CancellationError {
                self.finish(id, status: .cancelled, result: nil, error: nil)
            } catch {
                self.finish(id, status: .failed, result: nil, error: error.localizedDescription)
            }
        }
        return id
    }

    public func list(limit: Int = 20) -> [[String: Any]] {
        orderedIDs.prefix(max(1, min(100, limit))).compactMap { id in
            records[id].map(dictionary)
        }
    }

    public func get(id: String) -> [String: Any]? {
        records[id].map(dictionary)
    }

    @discardableResult
    public func cancel(id: String) -> Bool {
        guard let record = records[id],
              record.cancellable,
              record.status == .queued || record.status == .running else {
            return false
        }
        tasks[id]?.cancel()
        finish(id, status: .cancelled, result: nil, error: nil)
        return true
    }

    fileprivate func update(jobID: String, progress: Double, stage: String, message: String) {
        guard var record = records[jobID], record.status == .running else { return }
        record.progress = max(0, min(1, progress.isFinite ? progress : 0))
        record.stage = stage
        if !message.isEmpty {
            record.message = message
        }
        record.updatedAt = Date()
        records[jobID] = record
    }
}

private extension McpJobManager {
    private func markRunning(_ id: String) {
        guard var record = records[id] else { return }
        record.status = .running
        record.stage = "Running"
        record.updatedAt = Date()
        records[id] = record
    }

    private func finish(
        _ id: String,
        status: McpJobStatus,
        result: [String: Any]?,
        error: String?
    ) {
        guard var record = records[id] else { return }
        record.status = status
        record.progress = status == .succeeded ? 1 : record.progress
        record.stage = status.rawValue.capitalized
        record.updatedAt = Date()
        record.finishedAt = record.updatedAt
        record.result = result
        record.error = error
        records[id] = record
        tasks[id] = nil
    }

    private func dictionary(_ record: JobRecord) -> [String: Any] {
        var result: [String: Any] = [
            "jobId": record.id,
            "kind": record.kind,
            "status": record.status.rawValue,
            "progress": record.progress,
            "stage": record.stage,
            "message": record.message,
            "cancellable": record.cancellable && (record.status == .queued || record.status == .running),
            "createdAt": isoString(record.createdAt),
            "updatedAt": isoString(record.updatedAt),
        ]
        if let finishedAt = record.finishedAt {
            result["finishedAt"] = isoString(finishedAt)
        }
        if let jobResult = record.result {
            result["result"] = jobResult
        }
        if let error = record.error {
            result["error"] = error
        }
        return result
    }

    private func pruneIfNeeded() {
        guard orderedIDs.count >= maximumRetainedJobs else { return }
        let removable = orderedIDs.reversed().filter { id in
            guard let status = records[id]?.status else { return true }
            return status == .succeeded || status == .failed || status == .cancelled
        }
        for id in removable.prefix(orderedIDs.count - maximumRetainedJobs + 1) {
            records[id] = nil
            tasks[id] = nil
            orderedIDs.removeAll { $0 == id }
        }
    }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
