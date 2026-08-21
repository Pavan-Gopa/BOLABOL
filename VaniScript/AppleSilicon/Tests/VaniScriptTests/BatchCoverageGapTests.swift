import Foundation
import Testing
import VaniScriptCore
import VaniScriptRuntime
@testable import VaniScript

// MARK: - Tests closing material Batch coverage gaps

@Suite("Batch coverage gaps")
struct BatchCoverageGapTests {

    // ──────────────────────────────────────────────────────────────────────
    // 1. Repository: retry preserves checkpoints, second retry is idempotent
    // ──────────────────────────────────────────────────────────────────────

    @Test("retry preserves checkpoints and a second retry on pending throws")
    func retryCheckpointPreservationAndIdempotency() async throws {
        let fixture = try RepoFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let job = fixture.job(source: "2026_person_story_city_us.wav", output: "2026_person_story_city_us.txt", hash: "h1")
        guard case .inserted = try await repository.enqueue(job) else {
            Issue.record("expected insert"); return
        }
        let claimed = try #require(try await repository.claimNext(configurationID: "config"))
        let cp = BatchChunkCheckpoint(
            index: 0,
            text: "hello world",
            cues: [TranscriptCue(startSec: 0, endSec: 5, text: "hello world")]
        )
        try await repository.checkpoint(id: claimed.id, checkpoints: [cp], progress: 0.5, totalChunks: 2)
        try await repository.fail(id: claimed.id, error: "Provider error")

        // First retry
        try await repository.retry(id: claimed.id)
        let afterRetry1 = try #require(try await repository.job(id: claimed.id))
        #expect(afterRetry1.state == .pending)
        #expect(afterRetry1.checkpoints == [cp])
        #expect(afterRetry1.attempt == 0)
        #expect(afterRetry1.lastError == "Provider error")
        #expect(afterRetry1.progressDetail == nil)
        #expect(afterRetry1.startedAt == nil)
        #expect(afterRetry1.finishedAt == nil)

        // Second retry from pending is illegal (pending→pending not in state machine)
        await #expect(throws: BatchRepositoryError.illegalTransition(from: .pending, to: .pending)) {
            try await repository.retry(id: claimed.id)
        }
        // State must be unchanged
        let afterAttemptedRetry = try #require(try await repository.job(id: claimed.id))
        #expect(afterAttemptedRetry.state == .pending)
        #expect(afterAttemptedRetry.checkpoints == [cp])
    }

    // ──────────────────────────────────────────────────────────────────────
    // 2. Repository: list ordering is stable by created_at, id
    // ──────────────────────────────────────────────────────────────────────

    @Test("list returns stable created_at then id order")
    func listStableOrder() async throws {
        let fixture = try RepoFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)

        var jobs: [BatchJob] = []
        for i in 1...5 {
            let name = "2026_file\(i)_story_city_us"
            let j = fixture.job(source: "\(name).wav", output: "\(name).txt", hash: "hash\(i)")
            guard case let .inserted(inserted) = try await repository.enqueue(j) else {
                Issue.record("expected insert \(i)"); return
            }
            jobs.append(inserted)
        }
        let listed = try await repository.list()
        #expect(listed.map(\.id) == jobs.map(\.id))

        // Re-list should be identical
        let relisted = try await repository.list()
        #expect(relisted.map(\.id) == listed.map(\.id))
    }

    // ──────────────────────────────────────────────────────────────────────
    // 3. Repository: supersedePending configuration isolation
    // ──────────────────────────────────────────────────────────────────────

    @Test("supersedePending cancels only stale configuration pending jobs and preserves current")
    func supersedePendingIsolation() async throws {
        let fixture = try RepoFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)

        let oldJob = fixture.job(source: "2026_old_story_city_us.wav", output: "2026_old_story_city_us.txt", hash: "h1", configurationID: "old-config")
        let currentJob = fixture.job(source: "2026_current_story_city_us.wav", output: "2026_current_story_city_us.txt", hash: "h2", configurationID: "current-config")
        guard case let .inserted(old) = try await repository.enqueue(oldJob) else { Issue.record("expected insert old"); return }
        guard case let .inserted(current) = try await repository.enqueue(currentJob) else { Issue.record("expected insert current"); return }

        let superseded = try await repository.supersedePending(exceptConfigurationID: "current-config")
        #expect(superseded == 1)

        let oldResult = try #require(try await repository.job(id: old.id))
        #expect(oldResult.state == .cancelled)
        #expect(oldResult.lastError?.contains("Superseded") == true)
        #expect(oldResult.progressDetail == nil)

        let currentResult = try #require(try await repository.job(id: current.id))
        #expect(currentResult.state == .pending)
    }

    // ──────────────────────────────────────────────────────────────────────
    // 4. Repository: recoverInterrupted preserves checkpoints
    // ──────────────────────────────────────────────────────────────────────

    @Test("recoverInterrupted preserves checkpoints and clears timing")
    func recoverInterruptedPreservesCheckpoints() async throws {
        let fixture = try RepoFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let job = fixture.job(source: "2026_recover_story_city_us.wav", output: "2026_recover_story_city_us.txt", hash: "h1")
        guard case .inserted = try await repository.enqueue(job) else {
            Issue.record("expected insert"); return
        }
        let claimed = try #require(try await repository.claimNext(configurationID: "config"))
        let cp = BatchChunkCheckpoint(index: 0, text: "partial", cues: [TranscriptCue(startSec: 0, endSec: 2, text: "partial")])
        try await repository.checkpoint(id: claimed.id, checkpoints: [cp], progress: 0.3, totalChunks: 3)
        #expect(try await repository.job(id: claimed.id)?.state == .processing)

        let count = try await repository.recoverInterrupted()
        #expect(count == 1)

        let recovered = try #require(try await repository.job(id: claimed.id))
        #expect(recovered.state == .pending)
        #expect(recovered.checkpoints == [cp])
        #expect(recovered.attempt == 1)
        #expect(recovered.lastError == "Recovered after interruption")
        #expect(recovered.startedAt == nil)
        #expect(recovered.finishedAt == nil)
        #expect(recovered.progressDetail == nil)
    }

    // ──────────────────────────────────────────────────────────────────────
    // 5. Coordinator: all-complete resumed checkpoints reach companion output
    // ──────────────────────────────────────────────────────────────────────

    @Test("all-complete resumed checkpoints produce companion output with one transcriber call")
    func allCompleteResumedCheckpointsToCompanion() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchGap-AllComplete-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sourceName = "2026_resumed_story_rome_it.wav"
        let source = root.appendingPathComponent(sourceName)
        try Data("audio data".utf8).write(to: source)

        let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
        let config = BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en")

        let checkpoint = BatchChunkCheckpoint(
            index: 0,
            text: "Fully completed text",
            cues: [TranscriptCue(startSec: 0, endSec: 1, text: "Fully completed text")]
        )
        let job = BatchJob(
            profileID: "p",
            relativeSourcePath: sourceName,
            relativeOutputPath: "2026_resumed_story_rome_it.txt",
            sourceFingerprint: try AtomicCompanionWriter.fingerprint(sourceURL: source),
            configuration: config,
            checkpoints: [checkpoint]
        )
        guard case let .inserted(inserted) = try await repository.enqueue(job) else {
            Issue.record("expected insert"); return
        }

        let calls = GapTranscriberCallCounter()
        let transcriber = AllCompleteResumedTranscriber(callCounter: calls)

        let events = GapEventLog()
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: config,
            transcriber: transcriber,
            writer: AtomicCompanionWriter(),
            eventHandler: { event in await events.record(event) }
        )
        await coordinator.processPending(in: root)

        #expect(await calls.value == 1)

        let output = root.appendingPathComponent("2026_resumed_story_rome_it.txt")
        #expect(FileManager.default.fileExists(atPath: output.path))
        let contents = try String(contentsOf: output, encoding: .utf8)
        #expect(contents.contains("Fully completed text"))

        let finalJob = try await repository.job(id: inserted.id)
        #expect(finalJob?.state == .completed)
        #expect(finalJob?.progress == 1.0)

        let completedEvents = await events.values.filter {
            if case .completed = $0 { return true }
            return false
        }
        #expect(completedEvents.count == 1)
    }

    // ──────────────────────────────────────────────────────────────────────
    // 6. Coordinator: max-attempt preserves original lastError
    // ──────────────────────────────────────────────────────────────────────

    @Test("max-attempt exceeded preserves original lastError instead of generic message")
    func maxAttemptPreservesOriginalError() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchGap-MaxAttempt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sourceName = "2026_maxerr_story_rome_it.wav"
        let source = root.appendingPathComponent(sourceName)
        try Data("audio".utf8).write(to: source)

        let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
        let config = BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en")
        let fingerprint = try AtomicCompanionWriter.fingerprint(sourceURL: source)

        var job = BatchJob(
            profileID: "p",
            relativeSourcePath: sourceName,
            relativeOutputPath: "2026_maxerr_story_rome_it.txt",
            sourceFingerprint: fingerprint,
            configuration: config
        )
        job.attempt = 2
        job.lastError = "Original cloud timeout"
        guard case .inserted = try await repository.enqueue(job) else {
            Issue.record("expected insert"); return
        }

        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: config,
            transcriber: NeverCalledTranscriber(),
            writer: AtomicCompanionWriter(),
            maxAttempts: 2
        )
        await coordinator.processPending(in: root)

        let result = try await repository.list().first
        #expect(result?.state == .failed)
        #expect(result?.lastError == "Original cloud timeout")
    }

    // ──────────────────────────────────────────────────────────────────────
    // 7. Coordinator: cancel individual job leaves other processable
    // ──────────────────────────────────────────────────────────────────────

    @Test("cancel individual job leaves other pending jobs processable")
    func cancelIndividualJob() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchGap-CancelOne-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
        let config = BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en")

        var insertedJobs: [BatchJob] = []
        for name in ["2026_cancel1_story_rome_it.wav", "2026_cancel2_story_rome_it.wav"] {
            let source = root.appendingPathComponent(name)
            try Data(name.utf8).write(to: source)
            let fingerprint = try AtomicCompanionWriter.fingerprint(sourceURL: source)
            let job = BatchJob(
                profileID: "p",
                relativeSourcePath: name,
                relativeOutputPath: name.replacingOccurrences(of: ".wav", with: ".txt"),
                sourceFingerprint: fingerprint,
                configuration: config
            )
            guard case let .inserted(inserted) = try await repository.enqueue(job) else {
                Issue.record("expected insert"); return
            }
            insertedJobs.append(inserted)
        }

        try await repository.cancel(id: insertedJobs[0].id)
        #expect(try await repository.job(id: insertedJobs[0].id)?.state == .cancelled)

        let calls = GapTranscriberCallCounter()
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: config,
            transcriber: GapStubTranscriber(callCounter: calls),
            writer: AtomicCompanionWriter()
        )
        await coordinator.processPending(in: root)

        #expect(await calls.value == 1)
        #expect(try await repository.job(id: insertedJobs[0].id)?.state == .cancelled)
        #expect(try await repository.job(id: insertedJobs[1].id)?.state == .completed)
    }

    // ──────────────────────────────────────────────────────────────────────
    // 8. State machine: all terminal states can retry to pending
    // ──────────────────────────────────────────────────────────────────────

    @Test("all retryable terminal states transition to pending; completed cannot")
    func allTerminalRetryTransitions() throws {
        let retryable: [BatchJobState] = [.failed, .cancelled, .blockedOutputCollision]
        for state in retryable {
            var job = stateMachineFixture(state: state)
            try BatchJobStateMachine.transition(&job, to: .pending)
            #expect(job.state == .pending)
        }
        var completed = stateMachineFixture(state: .completed)
        #expect(throws: BatchJobTransitionError.illegalTransition(from: .completed, to: .pending)) {
            try BatchJobStateMachine.transition(&completed, to: .pending)
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // 9. Timed text renderer: multiple distinct violations collected
    // ──────────────────────────────────────────────────────────────────────

    @Test("multiple distinct violations are collected in a single validation pass")
    func multipleViolationsCollected() {
        let cues = [
            TranscriptCue(startSec: .nan, endSec: 1, text: "nan-start"),
            TranscriptCue(startSec: 2, endSec: 1, text: "reversed"),
            TranscriptCue(startSec: 3, endSec: 5, text: "  "),
        ]
        let result = BatchTimedTextRenderer.validate(duration: 10, cues: cues)
        #expect(result.violations.contains(.nonFiniteTime(cueIndex: 0)))
        #expect(result.violations.contains(.invalidRange(cueIndex: 1)))
        #expect(result.violations.contains(.emptyText(cueIndex: 2)))
        #expect(!result.isValid)
    }

    // ──────────────────────────────────────────────────────────────────────
    // 10. BatchJob: elapsed duration for varied states
    // ──────────────────────────────────────────────────────────────────────

    @Test("elapsed duration computes correctly for each terminal state shape")
    func elapsedDurationShapes() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 1_003_600)

        let completed = BatchJob(
            profileID: "p", relativeSourcePath: "a.wav", relativeOutputPath: "a.txt",
            sourceFingerprint: .init(byteCount: 1, modificationTimeNanoseconds: 1, sha256: "h"),
            configuration: .init(identifier: "c", sourceLanguage: "en"),
            state: .completed, startedAt: start, finishedAt: end
        )
        #expect(completed.formattedDuration == "1h 0m 0s")

        let pending = BatchJob(
            profileID: "p", relativeSourcePath: "b.wav", relativeOutputPath: "b.txt",
            sourceFingerprint: .init(byteCount: 1, modificationTimeNanoseconds: 1, sha256: "h"),
            configuration: .init(identifier: "c", sourceLanguage: "en"),
            state: .pending
        )
        #expect(pending.elapsedDuration == nil)

        let cancelled = BatchJob(
            profileID: "p", relativeSourcePath: "c.wav", relativeOutputPath: "c.txt",
            sourceFingerprint: .init(byteCount: 1, modificationTimeNanoseconds: 1, sha256: "h"),
            configuration: .init(identifier: "c", sourceLanguage: "en"),
            state: .cancelled, createdAt: start, updatedAt: end, finishedAt: end
        )
        #expect(cancelled.formattedDuration == "1h 0m 0s")

        #expect(BatchJob.formatDuration(0) == "0s")
        #expect(BatchJob.formatDuration(59) == "59s")
        #expect(BatchJob.formatDuration(60) == "1m 0s")
    }

    // ──────────────────────────────────────────────────────────────────────
    // 11. AtomicCompanionWriterError: isOutputCollision classifications
    // ──────────────────────────────────────────────────────────────────────

    @Test("isOutputCollision returns true only for collision errors")
    func outputCollisionClassification() {
        let collisions: [AtomicCompanionWriterError] = [
            .existingOutputNotKnownGenerated,
            .existingOutputModified,
            .caseInsensitiveCollision(existingName: "test.TXT"),
        ]
        for err in collisions {
            #expect(err.isOutputCollision, "expected collision for \(err)")
        }
        let nonCollisions: [AtomicCompanionWriterError] = [
            .sourceUnavailable, .sourceChanged, .directoryReadFailed,
            .permissionDenied, .temporaryCreateFailed(code: 1),
            .writeFailed(code: 1), .syncFailed(code: 1),
            .closeFailed(code: 1), .renameFailed(code: 1),
        ]
        for err in nonCollisions {
            #expect(!err.isOutputCollision, "expected non-collision for \(err)")
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // 12. actionableMessage includes filename for collision errors
    // ──────────────────────────────────────────────────────────────────────

    @Test("actionableMessage includes the output filename for collision errors")
    func actionableMessageFilename() {
        let filename = "2026_story_city_us.txt"
        let msg1 = AtomicCompanionWriterError.existingOutputNotKnownGenerated.actionableMessage(forOutputFilename: filename)
        #expect(msg1.contains(filename))

        let msg2 = AtomicCompanionWriterError.existingOutputModified.actionableMessage(forOutputFilename: filename)
        #expect(msg2.contains(filename))

        let msg3 = AtomicCompanionWriterError.caseInsensitiveCollision(existingName: "2026_Story_City_US.TXT")
            .actionableMessage(forOutputFilename: filename)
        #expect(msg3.contains("2026_Story_City_US.TXT"))

        let msg4 = AtomicCompanionWriterError.permissionDenied.actionableMessage(forOutputFilename: filename)
        #expect(msg4.contains("Permission denied"))
    }

    // ──────────────────────────────────────────────────────────────────────
    // 13. Repository: delete by profileID isolates profiles
    // ──────────────────────────────────────────────────────────────────────

    @Test("delete by profileID removes all jobs for that profile and preserves others")
    func deleteByProfileID() async throws {
        let fixture = try RepoFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)

        let jobA = fixture.job(source: "2026_a_story_city_us.wav", output: "2026_a_story_city_us.txt", hash: "ha")
        let jobB = BatchJob(
            profileID: "other",
            relativeSourcePath: "2026_b_story_city_us.wav",
            relativeOutputPath: "2026_b_story_city_us.txt",
            sourceFingerprint: SourceFileFingerprint(byteCount: 1, modificationTimeNanoseconds: 2, sha256: "hb"),
            configuration: BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en")
        )
        _ = try await repository.enqueue(jobA)
        _ = try await repository.enqueue(jobB)
        #expect(try await repository.list().count == 2)

        try await repository.delete(profileID: "profile")
        let remaining = try await repository.list()
        #expect(remaining.count == 1)
        #expect(remaining.first?.profileID == "other")
    }

    // ──────────────────────────────────────────────────────────────────────
    // 14. Repository: checkpoint progress clamping at boundaries
    // ──────────────────────────────────────────────────────────────────────

    @Test("checkpoint clamps progress to 0-1 range")
    func checkpointProgressClamping() async throws {
        let fixture = try RepoFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let job = fixture.job(source: "2026_clamp_story_city_us.wav", output: "2026_clamp_story_city_us.txt", hash: "h1")
        guard case .inserted = try await repository.enqueue(job) else {
            Issue.record("expected insert"); return
        }
        let claimed = try #require(try await repository.claimNext(configurationID: "config"))

        // Negative progress → clamped to 0
        try await repository.checkpoint(id: claimed.id, checkpoints: [], progress: -0.5)
        #expect(try await repository.job(id: claimed.id)?.progress == 0)

        // Over-1 progress → clamped to 1
        try await repository.checkpoint(id: claimed.id, checkpoints: [], progress: 1.5)
        #expect(try await repository.job(id: claimed.id)?.progress == 1.0)
    }

    // ──────────────────────────────────────────────────────────────────────
    // 15. Coordinator: unavailable folder URL fails job
    // ──────────────────────────────────────────────────────────────────────

    @Test("unavailable folder URL fails job with descriptive message")
    func unavailableFolderFailsJob() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchGap-NoFolder-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
        let config = BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en")
        let sourceName = "2026_nofolder_story_rome_it.wav"
        let source = root.appendingPathComponent(sourceName)
        try Data("audio".utf8).write(to: source)
        let job = BatchJob(
            profileID: "unknown-profile",
            relativeSourcePath: sourceName,
            relativeOutputPath: "2026_nofolder_story_rome_it.txt",
            sourceFingerprint: try AtomicCompanionWriter.fingerprint(sourceURL: source),
            configuration: config
        )
        guard case let .inserted(inserted) = try await repository.enqueue(job) else {
            Issue.record("expected insert"); return
        }

        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: config,
            transcriber: NeverCalledTranscriber(),
            writer: AtomicCompanionWriter()
        )
        await coordinator.processPending()

        let result = try await repository.job(id: inserted.id)
        #expect(result?.state == .failed)
        #expect(result?.lastError?.contains("unavailable") == true)
    }

    // ──────────────────────────────────────────────────────────────────────
    // 16. BatchJob: progressStageText for every state
    // ──────────────────────────────────────────────────────────────────────

    @Test("progressStageText returns correct label for every state")
    func progressStageTextAllStates() {
        func makeJob(state: BatchJobState) -> BatchJob {
            BatchJob(
                profileID: "p", relativeSourcePath: "s.wav", relativeOutputPath: "s.txt",
                sourceFingerprint: .init(byteCount: 1, modificationTimeNanoseconds: 1, sha256: "h"),
                configuration: .init(identifier: "c", sourceLanguage: "en"),
                state: state
            )
        }
        #expect(makeJob(state: .pending).progressStageText == "Pending")
        #expect(makeJob(state: .completed).progressStageText == "Completed")
        #expect(makeJob(state: .failed).progressStageText == "Failed")
        #expect(makeJob(state: .cancelled).progressStageText == "Cancelled")
        #expect(makeJob(state: .blockedOutputCollision).progressStageText == "Output conflict")

        var processing = makeJob(state: .processing)
        #expect(processing.progressStageText == "Starting…")

        processing.progressDetail = BatchProgressDetail(phase: .loadingModel)
        #expect(processing.progressStageText == "Loading model…")

        processing.progressDetail = BatchProgressDetail(phase: .convertingAudio)
        #expect(processing.progressStageText == "Preparing audio…")

        processing.progressDetail = BatchProgressDetail(phase: .finalizing)
        #expect(processing.progressStageText == "Saving transcript…")
    }

    // ──────────────────────────────────────────────────────────────────────
    // 17. MediaNamingConvention: safeNormalize compound names
    // ──────────────────────────────────────────────────────────────────────

    @Test("safeNormalize mode accepts hyphenated WHAT component and preserves companion stem")
    func safeNormalizeHyphenatedWhat() throws {
        let result = MediaNamingConvention.parse("2023-01-16_KKS-CC-Raghunatha-das-goswami_Amsterdam_nl.wav", mode: .safeNormalize)
        #expect(result.isAccepted)
        #expect(result.name != nil)
        #expect(result.name?.who == "KKS")
        #expect(result.name?.what == "CC-Raghunatha-das-goswami")
        #expect(result.name?.whereToken == "Amsterdam")
        #expect(result.name?.country == "nl")
        // Companion URL preserves the original source stem, not the canonical stem
        let source = URL(fileURLWithPath: "/folder/2023-01-16_KKS-CC-Raghunatha-das-goswami_Amsterdam_nl.wav")
        let companion = result.name?.companionURL(for: source)
        #expect(companion?.lastPathComponent == "2023-01-16_KKS-CC-Raghunatha-das-goswami_Amsterdam_nl.txt")
    }

    // ──────────────────────────────────────────────────────────────────────
    // 18. BatchFolderProfile: defaults and Codable round-trip
    // ──────────────────────────────────────────────────────────────────────

    @Test("BatchFolderProfile defaults and Codable backward compatibility")
    func profileDefaultsAndCodable() throws {
        let profile = BatchFolderProfile(id: "test", name: "Test")
        #expect(profile.enabled == true)
        #expect(profile.recursive == false)
        #expect(profile.bookmarkData == nil)
        #expect(profile.displayPath == "")

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(BatchFolderProfile.self, from: data)
        #expect(decoded == profile)

        let minimalJSON = Data("""
        {"id":"x","name":"Minimal"}
        """.utf8)
        let minimal = try JSONDecoder().decode(BatchFolderProfile.self, from: minimalJSON)
        #expect(minimal.enabled == true)
        #expect(minimal.recursive == false)
    }

    // ──────────────────────────────────────────────────────────────────────
    // 19. Coordinator: processPending is non-reentrant
    // ──────────────────────────────────────────────────────────────────────

    @Test("processPending is non-reentrant: second concurrent call returns immediately")
    func processPendingNonReentrant() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchGap-Reentrant-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sourceName = "2026_reentrant_story_rome_it.wav"
        let source = root.appendingPathComponent(sourceName)
        try Data("audio".utf8).write(to: source)

        let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
        let config = BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en")
        let job = BatchJob(
            profileID: "p",
            relativeSourcePath: sourceName,
            relativeOutputPath: "2026_reentrant_story_rome_it.txt",
            sourceFingerprint: try AtomicCompanionWriter.fingerprint(sourceURL: source),
            configuration: config
        )
        _ = try await repository.enqueue(job)

        let calls = GapTranscriberCallCounter()
        let slow = SlowTranscriber(callCounter: calls)
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: config,
            transcriber: slow,
            writer: AtomicCompanionWriter()
        )

        let task1 = Task { await coordinator.processPending(in: root) }
        try await Task.sleep(for: .milliseconds(10))
        let task2 = Task { await coordinator.processPending(in: root) }

        await task1.value
        await task2.value

        #expect(await calls.value == 1)
    }

    // ──────────────────────────────────────────────────────────────────────
    // 20. Coordinator: events published for every terminal outcome
    // ──────────────────────────────────────────────────────────────────────

    @Test("coordinator publishes completed, failed, and blockedOutputCollision events")
    func coordinatorEventPublishing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchGap-Events-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
        let config = BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en")

        // Job 1: completes normally
        let source1 = root.appendingPathComponent("2026_evt1_story_rome_it.wav")
        try Data("audio1".utf8).write(to: source1)
        let job1 = BatchJob(
            profileID: "p", relativeSourcePath: source1.lastPathComponent,
            relativeOutputPath: "2026_evt1_story_rome_it.txt",
            sourceFingerprint: try AtomicCompanionWriter.fingerprint(sourceURL: source1),
            configuration: config
        )
        guard case let .inserted(inserted1) = try await repository.enqueue(job1) else { Issue.record("insert1"); return }

        // Job 2: will fail
        let source2 = root.appendingPathComponent("2026_evt2_story_rome_it.wav")
        try Data("audio2".utf8).write(to: source2)
        let job2 = BatchJob(
            profileID: "p", relativeSourcePath: source2.lastPathComponent,
            relativeOutputPath: "2026_evt2_story_rome_it.txt",
            sourceFingerprint: try AtomicCompanionWriter.fingerprint(sourceURL: source2),
            configuration: config
        )
        guard case let .inserted(inserted2) = try await repository.enqueue(job2) else { Issue.record("insert2"); return }

        let events = GapEventLog()
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: config,
            transcriber: SelectiveFailTranscriber(failingName: source2.lastPathComponent),
            writer: AtomicCompanionWriter(),
            eventHandler: { event in await events.record(event) }
        )
        await coordinator.processPending(in: root)

        let eventValues = await events.values
        let completedIDs = eventValues.compactMap { e -> UUID? in
            if case .completed(let id) = e { return id }
            return nil
        }
        let failedIDs = eventValues.compactMap { e -> UUID? in
            if case .failed(let id, _) = e { return id }
            return nil
        }
        let updatedIDs = eventValues.compactMap { e -> UUID? in
            if case .updated(let id) = e { return id }
            return nil
        }
        #expect(completedIDs.contains(inserted1.id))
        #expect(failedIDs.contains(inserted2.id))
        // Both jobs should have had .updated events
        #expect(updatedIDs.contains(inserted1.id))
        #expect(updatedIDs.contains(inserted2.id))
    }
}

// MARK: - Test Helpers

private struct RepoFixture {
    let root: URL
    let database: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        database = root.appendingPathComponent("jobs.sqlite")
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func job(source: String, output: String, hash: String, configurationID: String = "config") -> BatchJob {
        BatchJob(
            profileID: "profile",
            relativeSourcePath: source,
            relativeOutputPath: output,
            sourceFingerprint: SourceFileFingerprint(byteCount: 1, modificationTimeNanoseconds: 2, sha256: hash),
            configuration: BatchTranscriptionConfiguration(identifier: configurationID, sourceLanguage: "en")
        )
    }
}

private func stateMachineFixture(state: BatchJobState) -> BatchJob {
    BatchJob(
        profileID: "p",
        relativeSourcePath: "s.wav",
        relativeOutputPath: "s.txt",
        sourceFingerprint: .init(byteCount: 1, modificationTimeNanoseconds: 1, sha256: "h"),
        configuration: .init(identifier: "c", sourceLanguage: "en"),
        state: state
    )
}

private actor GapTranscriberCallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor GapEventLog {
    private(set) var values: [BatchProcessingEvent] = []
    func record(_ event: BatchProcessingEvent) { values.append(event) }
}

private actor AllCompleteResumedTranscriber: BatchAudioTranscribing {
    let callCounter: GapTranscriberCallCounter

    init(callCounter: GapTranscriberCallCounter) {
        self.callCounter = callCounter
    }

    func transcribe(
        sourceURL: URL,
        resumedCheckpoints: [BatchChunkCheckpoint],
        progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void,
        checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void
    ) async throws -> BatchTranscriptionResult {
        await callCounter.increment()
        try await checkpoint(resumedCheckpoints)
        try await progress(BatchTranscriptionProgress(
            fraction: 1.0,
            totalChunks: resumedCheckpoints.count,
            detail: BatchProgressDetail(phase: .transcribing)
        ))
        return BatchTranscriptionResult(
            duration: resumedCheckpoints.last?.cues.last?.endSec ?? 1,
            checkpoints: resumedCheckpoints
        )
    }
}

private actor NeverCalledTranscriber: BatchAudioTranscribing {
    func transcribe(
        sourceURL: URL,
        resumedCheckpoints: [BatchChunkCheckpoint],
        progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void,
        checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void
    ) async throws -> BatchTranscriptionResult {
        Issue.record("NeverCalledTranscriber should not be invoked")
        throw CocoaError(.fileReadCorruptFile)
    }
}

private actor GapStubTranscriber: BatchAudioTranscribing {
    let callCounter: GapTranscriberCallCounter

    init(callCounter: GapTranscriberCallCounter) {
        self.callCounter = callCounter
    }

    func transcribe(
        sourceURL: URL,
        resumedCheckpoints: [BatchChunkCheckpoint],
        progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void,
        checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void
    ) async throws -> BatchTranscriptionResult {
        await callCounter.increment()
        let item = BatchChunkCheckpoint(index: 0, text: "text", cues: [TranscriptCue(startSec: 0, endSec: 1, text: "text")])
        try await checkpoint([item])
        try await progress(BatchTranscriptionProgress(fraction: 1, totalChunks: 1, detail: BatchProgressDetail(phase: .transcribing)))
        return BatchTranscriptionResult(duration: 1, checkpoints: [item])
    }
}

private actor SlowTranscriber: BatchAudioTranscribing {
    let callCounter: GapTranscriberCallCounter

    init(callCounter: GapTranscriberCallCounter) {
        self.callCounter = callCounter
    }

    func transcribe(
        sourceURL: URL,
        resumedCheckpoints: [BatchChunkCheckpoint],
        progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void,
        checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void
    ) async throws -> BatchTranscriptionResult {
        await callCounter.increment()
        try await Task.sleep(for: .milliseconds(50))
        let item = BatchChunkCheckpoint(index: 0, text: "text", cues: [TranscriptCue(startSec: 0, endSec: 1, text: "text")])
        try await checkpoint([item])
        try await progress(BatchTranscriptionProgress(fraction: 1, totalChunks: 1, detail: BatchProgressDetail(phase: .transcribing)))
        return BatchTranscriptionResult(duration: 1, checkpoints: [item])
    }
}

private actor SelectiveFailTranscriber: BatchAudioTranscribing {
    let failingName: String

    init(failingName: String) {
        self.failingName = failingName
    }

    func transcribe(
        sourceURL: URL,
        resumedCheckpoints: [BatchChunkCheckpoint],
        progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void,
        checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void
    ) async throws -> BatchTranscriptionResult {
        if sourceURL.lastPathComponent == failingName {
            throw CocoaError(.fileReadCorruptFile)
        }
        let item = BatchChunkCheckpoint(index: 0, text: "text", cues: [TranscriptCue(startSec: 0, endSec: 1, text: "text")])
        try await checkpoint([item])
        try await progress(BatchTranscriptionProgress(fraction: 1, totalChunks: 1, detail: BatchProgressDetail(phase: .transcribing)))
        return BatchTranscriptionResult(duration: 1, checkpoints: [item])
    }
}
