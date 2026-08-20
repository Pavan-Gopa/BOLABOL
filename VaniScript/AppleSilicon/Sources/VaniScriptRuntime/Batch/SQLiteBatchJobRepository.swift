import Foundation
import SQLite3
import VaniScriptCore

public enum BatchRepositoryError: Error, Equatable, Sendable {
    case openFailed(String)
    case sqlite(String)
    case outputCollision
    case jobNotFound
    case illegalTransition(from: BatchJobState, to: BatchJobState)
}

public enum BatchEnqueueResult: Equatable, Sendable {
    case inserted(BatchJob)
    case duplicate(BatchJob)
    case outputCollision
}

public actor SQLiteBatchJobRepository {
    private static let busyTimeoutMilliseconds: Int32 = 5_000

    nonisolated(unsafe) private var database: OpaquePointer?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    public init(url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let db
        else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open SQLite database"
            if let db { sqlite3_close(db) }
            throw BatchRepositoryError.openFailed(message)
        }
        database = db
        sqlite3_extended_result_codes(db, 1)
        guard sqlite3_busy_timeout(db, Self.busyTimeoutMilliseconds) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            database = nil
            throw BatchRepositoryError.sqlite(message)
        }
        do {
            try Self.execute("PRAGMA journal_mode=WAL", on: db)
            try Self.execute("PRAGMA foreign_keys=ON", on: db)
            try Self.execute("PRAGMA user_version=1", on: db)
            try Self.execute("""
                CREATE TABLE IF NOT EXISTS batch_jobs (
                    id TEXT PRIMARY KEY,
                    profile_id TEXT NOT NULL,
                    source_path TEXT NOT NULL,
                    output_path TEXT NOT NULL,
                    source_fingerprint BLOB NOT NULL,
                    config BLOB NOT NULL,
                    config_id TEXT NOT NULL,
                    generation INTEGER NOT NULL,
                    state TEXT NOT NULL,
                    attempt INTEGER NOT NULL,
                    progress REAL NOT NULL,
                    checkpoints BLOB NOT NULL,
                    output_hash TEXT,
                    last_error TEXT,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    started_at REAL,
                    finished_at REAL,
                    total_chunks INTEGER,
                    progress_detail BLOB,
                    UNIQUE(profile_id, source_path, source_fingerprint, config_id)
                )
                """, on: db)
            try Self.migrateSchema(on: db)
            try Self.execute("CREATE INDEX IF NOT EXISTS batch_jobs_state_idx ON batch_jobs(state, created_at)", on: db)
            try Self.execute("DROP INDEX IF EXISTS batch_jobs_active_output_idx", on: db)
            try Self.execute("""
                CREATE INDEX IF NOT EXISTS batch_jobs_output_idx
                ON batch_jobs(profile_id, output_path COLLATE NOCASE, state)
                """, on: db)
        } catch {
            sqlite3_close(db)
            database = nil
            throw error
        }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    public func enqueue(_ proposed: BatchJob) throws -> BatchEnqueueResult {
        try validateRelativePath(proposed.relativeSourcePath)
        try validateRelativePath(proposed.relativeOutputPath)
        return try transaction {
            if let duplicate = try findDuplicate(proposed) { return .duplicate(duplicate) }
            try supersedePendingForSource(proposed)
            if let completed = try findCompletedSource(proposed) { return .duplicate(completed) }

            var job = proposed
            job.generation = try nextGeneration(profileID: job.profileID, sourcePath: job.relativeSourcePath)
            if let owner = try outputOwner(for: job) {
                guard owner.relativeSourcePath == job.relativeSourcePath,
                      owner.state == .completed,
                      let outputFingerprint = owner.outputFingerprint
                else { return .outputCollision }
                job.outputFingerprint = outputFingerprint
            }
            do {
                try insert(job)
                return .inserted(job)
            } catch let error as BatchRepositoryError {
                guard case .sqlite = error else { throw error }
                let extendedCode = sqlite3_extended_errcode(database)
                guard extendedCode & 0xFF == SQLITE_CONSTRAINT else { throw error }
                if let duplicate = try findDuplicate(proposed) { return .duplicate(duplicate) }
                throw error
            }
        }
    }

    public func list(states: Set<BatchJobState>? = nil) throws -> [BatchJob] {
        let jobs = try query("SELECT * FROM batch_jobs ORDER BY created_at, id", bindings: [])
        guard let states else { return jobs }
        return jobs.filter { states.contains($0.state) }
    }

    public func job(id: UUID) throws -> BatchJob? {
        try query("SELECT * FROM batch_jobs WHERE id = ?", bindings: [.text(id.uuidString)]).first
    }

    public func delete(profileID: String) throws {
        try run("DELETE FROM batch_jobs WHERE profile_id = ?", bindings: [.text(profileID)])
    }

    public func supersedePending(
        exceptConfigurationID configurationID: String,
        at date: Date = Date()
    ) throws -> Int {
        try transaction {
            let stale = try query(
                "SELECT * FROM batch_jobs WHERE state = ? AND config_id <> ? ORDER BY created_at, id",
                bindings: [.text(BatchJobState.pending.rawValue), .text(configurationID)]
            )
            for var job in stale {
                try transition(&job, to: .cancelled)
                job.finishedAt = date
                job.updatedAt = date
                job.lastError = Self.supersededMessage(existing: job.lastError)
                job.progressDetail = nil
                if job.totalChunks == nil {
                    job.totalChunks = max(1, job.checkpoints.count)
                }
                try update(job, expectedState: .pending)
            }
            return stale.count
        }
    }

    public func claimNext(configurationID: String) throws -> BatchJob? {
        try transaction {
            guard var job = try query(
                "SELECT * FROM batch_jobs WHERE state = ? AND config_id = ? ORDER BY created_at, id LIMIT 1",
                bindings: [.text(BatchJobState.pending.rawValue), .text(configurationID)]
            ).first else { return nil }
            try transition(&job, to: .processing)
            job.attempt += 1
            let now = Date()
            if job.startedAt == nil {
                job.startedAt = now
            }
            job.updatedAt = now
            try update(job, expectedState: .pending)
            return job
        }
    }

    public func checkpoint(
        id: UUID,
        checkpoints: [BatchChunkCheckpoint],
        progress: Double,
        totalChunks: Int? = nil,
        detail: BatchProgressDetail? = nil
    ) throws {
        try transaction {
            var job = try requiredJob(id)
            guard job.state == .processing else { throw BatchRepositoryError.illegalTransition(from: job.state, to: .processing) }
            job.checkpoints = checkpoints
            let clampedProgress = min(max(progress, 0), 1)
            job.progress = max(job.progress, clampedProgress)
            if let totalChunks {
                job.totalChunks = max(job.totalChunks ?? 0, totalChunks)
            } else if progress > 0 {
                let estimated = max(checkpoints.count, Int((Double(checkpoints.count) / progress).rounded()))
                job.totalChunks = max(job.totalChunks ?? 0, estimated)
            }
            job.progressDetail = detail
            let now = Date()
            if job.startedAt == nil {
                job.startedAt = now
            }
            job.updatedAt = now
            try update(job, expectedState: .processing)
        }
    }

    public func complete(id: UUID, outputFingerprint: GeneratedOutputFingerprint) throws {
        let now = Date()
        try transition(id: id, from: .processing, to: .completed) {
            $0.progress = 1
            $0.progressDetail = nil
            $0.outputFingerprint = outputFingerprint
            $0.lastError = nil
            $0.finishedAt = now
            $0.updatedAt = now
            $0.totalChunks = max($0.checkpoints.count, 1)
        }
    }

    public func fail(id: UUID, error: String) throws {
        let now = Date()
        try transition(id: id, from: .processing, to: .failed) {
            $0.lastError = error
            $0.finishedAt = now
            $0.updatedAt = now
            $0.progressDetail = nil
            if $0.totalChunks == nil {
                $0.totalChunks = max(1, $0.checkpoints.count)
            }
        }
    }

    public func blockOutputCollision(id: UUID, error: String) throws {
        let now = Date()
        try transition(id: id, from: .processing, to: .blockedOutputCollision) {
            $0.lastError = error
            $0.finishedAt = now
            $0.updatedAt = now
            $0.progressDetail = nil
            if $0.totalChunks == nil {
                $0.totalChunks = max(1, $0.checkpoints.count)
            }
        }
    }

    public func cancel(id: UUID) throws {
        try transaction {
            var job = try requiredJob(id)
            guard job.state == .pending || job.state == .processing else {
                throw BatchRepositoryError.illegalTransition(from: job.state, to: .cancelled)
            }
            let expected = job.state
            try transition(&job, to: .cancelled)
            let now = Date()
            job.finishedAt = now
            job.updatedAt = now
            job.progressDetail = nil
            if job.totalChunks == nil {
                job.totalChunks = max(1, job.checkpoints.count)
            }
            try update(job, expectedState: expected)
        }
    }

    public func retry(id: UUID) throws {
        try transaction {
            var job = try requiredJob(id)
            let expected = job.state
            try transition(&job, to: .pending)
            job.attempt = 0
            job.startedAt = nil
            job.finishedAt = nil
            job.progressDetail = nil
            job.updatedAt = Date()
            try update(job, expectedState: expected)
        }
    }

    @discardableResult
    public func recoverInterrupted() throws -> Int {
        try transaction {
            let interrupted = try query("SELECT * FROM batch_jobs WHERE state = ?", bindings: [.text(BatchJobState.processing.rawValue)])
            for var job in interrupted {
                try transition(&job, to: .pending)
                job.lastError = "Recovered after interruption"
                job.startedAt = nil
                job.finishedAt = nil
                job.progressDetail = nil
                job.updatedAt = Date()
                try update(job, expectedState: .processing)
            }
            return interrupted.count
        }
    }

    private func requiredJob(_ id: UUID) throws -> BatchJob {
        guard let job = try job(id: id) else { throw BatchRepositoryError.jobNotFound }
        return job
    }

    private func transition(_ job: inout BatchJob, to state: BatchJobState) throws {
        do { try BatchJobStateMachine.transition(&job, to: state) }
        catch let error as BatchJobTransitionError {
            switch error { case let .illegalTransition(from, to): throw BatchRepositoryError.illegalTransition(from: from, to: to) }
        }
    }

    private func transition(
        id: UUID,
        from expectedState: BatchJobState,
        to state: BatchJobState,
        mutate: (inout BatchJob) -> Void
    ) throws {
        try transaction {
            var job = try requiredJob(id)
            guard job.state == expectedState else {
                throw BatchRepositoryError.illegalTransition(from: job.state, to: state)
            }
            try transition(&job, to: state)
            mutate(&job)
            try update(job, expectedState: expectedState)
        }
    }

    private func validateRelativePath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !NSString(string: path).isAbsolutePath,
              !path.contains("\\"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw BatchRepositoryError.sqlite("Invalid relative path: \(path)") }
    }

    private func outputOwner(for job: BatchJob) throws -> BatchJob? {
        try query(
            "SELECT * FROM batch_jobs WHERE profile_id = ? AND output_path = ? COLLATE NOCASE AND state IN (?, ?, ?) ORDER BY generation DESC, created_at DESC LIMIT 1",
            bindings: [
                .text(job.profileID), .text(job.relativeOutputPath),
                .text(BatchJobState.pending.rawValue), .text(BatchJobState.processing.rawValue), .text(BatchJobState.completed.rawValue)
            ]
        ).first
    }

    private func findCompletedSource(_ job: BatchJob) throws -> BatchJob? {
        let fingerprint = try encoder.encode(job.sourceFingerprint)
        return try query(
            "SELECT * FROM batch_jobs WHERE profile_id = ? AND source_path = ? AND source_fingerprint = ? AND state = ? ORDER BY generation DESC, created_at DESC LIMIT 1",
            bindings: [
                .text(job.profileID), .text(job.relativeSourcePath), .blob(fingerprint),
                .text(BatchJobState.completed.rawValue)
            ]
        ).first
    }

    private func supersedePendingForSource(_ proposed: BatchJob) throws {
        let pending = try query(
            "SELECT * FROM batch_jobs WHERE profile_id = ? AND source_path = ? AND state = ? ORDER BY generation DESC, created_at DESC",
            bindings: [
                .text(proposed.profileID), .text(proposed.relativeSourcePath),
                .text(BatchJobState.pending.rawValue)
            ]
        )
        for var job in pending {
            guard job.sourceFingerprint != proposed.sourceFingerprint
                    || job.configuration.identifier != proposed.configuration.identifier
            else { continue }
            try transition(&job, to: .cancelled)
            job.finishedAt = Date()
            job.updatedAt = job.finishedAt ?? Date()
            job.lastError = Self.supersededMessage(existing: job.lastError)
            job.progressDetail = nil
            if job.totalChunks == nil {
                job.totalChunks = max(1, job.checkpoints.count)
            }
            try update(job, expectedState: .pending)
        }
    }

    private static func supersededMessage(existing: String?) -> String {
        let reason = "Superseded by a newer Batch transcription configuration"
        guard let existing, !existing.isEmpty else { return reason }
        return "\(existing) — \(reason)"
    }

    private func findDuplicate(_ job: BatchJob) throws -> BatchJob? {
        let fingerprint = try encoder.encode(job.sourceFingerprint)
        return try query(
            "SELECT * FROM batch_jobs WHERE profile_id = ? AND source_path = ? AND source_fingerprint = ? AND config_id = ? LIMIT 1",
            bindings: [.text(job.profileID), .text(job.relativeSourcePath), .blob(fingerprint), .text(job.configuration.identifier)]
        ).first
    }

    private func nextGeneration(profileID: String, sourcePath: String) throws -> Int {
        let statement = try prepare("SELECT COALESCE(MAX(generation), 0) + 1 FROM batch_jobs WHERE profile_id = ? AND source_path = ?")
        defer { sqlite3_finalize(statement) }
        try bind([.text(profileID), .text(sourcePath)], to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw error() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func migrateSchema(on db: OpaquePointer) throws {
        var existingColumns = Set<String>()
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(batch_jobs)", -1, &statement, nil) == SQLITE_OK, let statement {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let name = sqlite3_column_text(statement, 1) {
                    existingColumns.insert(String(cString: name))
                }
            }
            sqlite3_finalize(statement)
        }
        if !existingColumns.isEmpty {
            if !existingColumns.contains("started_at") {
                try execute("ALTER TABLE batch_jobs ADD COLUMN started_at REAL", on: db)
            }
            if !existingColumns.contains("finished_at") {
                try execute("ALTER TABLE batch_jobs ADD COLUMN finished_at REAL", on: db)
            }
            if !existingColumns.contains("total_chunks") {
                try execute("ALTER TABLE batch_jobs ADD COLUMN total_chunks INTEGER", on: db)
            }
            if !existingColumns.contains("progress_detail") {
                try execute("ALTER TABLE batch_jobs ADD COLUMN progress_detail BLOB", on: db)
            }
        }
    }

    private func insert(_ job: BatchJob) throws {
        let sql = """
            INSERT INTO batch_jobs
            (id, profile_id, source_path, output_path, source_fingerprint, config, config_id, generation, state,
             attempt, progress, checkpoints, output_hash, last_error, created_at, updated_at,
             started_at, finished_at, total_chunks, progress_detail)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        try run(sql, bindings: try bindings(for: job))
    }

    private func update(_ job: BatchJob) throws {
        let values = try bindings(for: job)
        try run(
            "UPDATE batch_jobs SET profile_id=?, source_path=?, output_path=?, source_fingerprint=?, config=?, config_id=?, generation=?, state=?, attempt=?, progress=?, checkpoints=?, output_hash=?, last_error=?, created_at=?, updated_at=?, started_at=?, finished_at=?, total_chunks=?, progress_detail=? WHERE id=?",
            bindings: Array(values.dropFirst()) + [values[0]]
        )
    }

    private func update(_ job: BatchJob, expectedState: BatchJobState) throws {
        let values = try bindings(for: job)
        try run(
            "UPDATE batch_jobs SET profile_id=?, source_path=?, output_path=?, source_fingerprint=?, config=?, config_id=?, generation=?, state=?, attempt=?, progress=?, checkpoints=?, output_hash=?, last_error=?, created_at=?, updated_at=?, started_at=?, finished_at=?, total_chunks=?, progress_detail=? WHERE id=? AND state=?",
            bindings: Array(values.dropFirst()) + [values[0], .text(expectedState.rawValue)]
        )
        guard sqlite3_changes(database) == 1 else {
            let current = try requiredJob(job.id)
            throw BatchRepositoryError.illegalTransition(from: current.state, to: job.state)
        }
    }

    private func bindings(for job: BatchJob) throws -> [Binding] {
        [
            .text(job.id.uuidString), .text(job.profileID), .text(job.relativeSourcePath), .text(job.relativeOutputPath),
            .blob(try encoder.encode(job.sourceFingerprint)), .blob(try encoder.encode(job.configuration)),
            .text(job.configuration.identifier), .integer(Int64(job.generation)), .text(job.state.rawValue),
            .integer(Int64(job.attempt)), .real(job.progress), .blob(try encoder.encode(job.checkpoints)),
            job.outputFingerprint.map { .text($0.sha256) } ?? .null, job.lastError.map(Binding.text) ?? .null,
            .real(job.createdAt.timeIntervalSince1970), .real(job.updatedAt.timeIntervalSince1970),
            job.startedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
            job.finishedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
            job.totalChunks.map { .integer(Int64($0)) } ?? .null,
            job.progressDetail.flatMap { try? encoder.encode($0) }.map(Binding.blob) ?? .null
        ]
    }

    private func query(_ sql: String, bindings: [Binding]) throws -> [BatchJob] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var jobs: [BatchJob] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0)),
                  let state = BatchJobState(rawValue: text(statement, 8))
            else { throw BatchRepositoryError.sqlite("Invalid batch job row") }
            let columnCount = sqlite3_column_count(statement)
            let startedAt: Date?
            if columnCount > 16, sqlite3_column_type(statement, 16) != SQLITE_NULL {
                startedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 16))
            } else {
                startedAt = nil
            }
            let finishedAt: Date?
            if columnCount > 17, sqlite3_column_type(statement, 17) != SQLITE_NULL {
                finishedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 17))
            } else {
                finishedAt = nil
            }
            let totalChunks: Int?
            if columnCount > 18, sqlite3_column_type(statement, 18) != SQLITE_NULL {
                totalChunks = Int(sqlite3_column_int64(statement, 18))
            } else {
                totalChunks = nil
            }
            let progressDetail: BatchProgressDetail?
            if columnCount > 19, sqlite3_column_type(statement, 19) != SQLITE_NULL {
                progressDetail = try? decoder.decode(BatchProgressDetail.self, from: blob(statement, 19))
            } else {
                progressDetail = nil
            }
            jobs.append(BatchJob(
                id: id, profileID: text(statement, 1), relativeSourcePath: text(statement, 2), relativeOutputPath: text(statement, 3),
                sourceFingerprint: try decoder.decode(SourceFileFingerprint.self, from: blob(statement, 4)),
                configuration: try decoder.decode(BatchTranscriptionConfiguration.self, from: blob(statement, 5)),
                generation: Int(sqlite3_column_int64(statement, 7)), state: state,
                attempt: Int(sqlite3_column_int64(statement, 9)), progress: sqlite3_column_double(statement, 10),
                checkpoints: try decoder.decode([BatchChunkCheckpoint].self, from: blob(statement, 11)),
                outputFingerprint: optionalText(statement, 12).map { GeneratedOutputFingerprint(sha256: $0) },
                lastError: optionalText(statement, 13),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 14)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 15)),
                startedAt: startedAt,
                finishedAt: finishedAt,
                totalChunks: totalChunks,
                progressDetail: progressDetail
            ))
        }
        let code = sqlite3_errcode(database)
        guard code == SQLITE_OK || code == SQLITE_DONE else { throw error() }
        return jobs
    }

    private enum Binding { case text(String), blob(Data), integer(Int64), real(Double), null }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error() }
        return statement
    }

    private func bind(_ bindings: [Binding], to statement: OpaquePointer) throws {
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case let .text(value): code = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case let .blob(value): code = value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), SQLITE_TRANSIENT) }
            case let .integer(value): code = sqlite3_bind_int64(statement, index, value)
            case let .real(value): code = sqlite3_bind_double(statement, index, value)
            case .null: code = sqlite3_bind_null(statement, index)
            }
            guard code == SQLITE_OK else { throw error() }
        }
    }

    private func run(_ sql: String, bindings: [Binding]) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw BatchRepositoryError.sqlite("Database closed") }
        try Self.execute(sql, on: database)
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &message) == SQLITE_OK else {
            let value = message.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(message)
            throw BatchRepositoryError.sqlite(value)
        }
    }

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result = try body(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }

    private func error() -> BatchRepositoryError { .sqlite(String(cString: sqlite3_errmsg(database))) }
    private func text(_ statement: OpaquePointer, _ column: Int32) -> String { String(cString: sqlite3_column_text(statement, column)) }
    private func optionalText(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : text(statement, column)
    }
    private func blob(_ statement: OpaquePointer, _ column: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: count)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
