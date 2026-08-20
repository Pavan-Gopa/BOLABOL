import Foundation
import Testing
import VaniScriptCore
import VaniScriptRuntime

@Suite("SQLite batch repository")
struct SQLiteBatchJobRepositoryTests {
    @Test("reopen recovery dedupe checkpoints generations and output collision")
    func durableLifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var repository: SQLiteBatchJobRepository? = try SQLiteBatchJobRepository(url: fixture.database)
        let first = fixture.job(source: "2026_person_story_city_us.wav", output: "2026_person_story_city_us.txt", hash: "one")
        guard case let .inserted(inserted) = try await repository!.enqueue(first) else { Issue.record("expected insert"); return }
        guard case .duplicate = try await repository!.enqueue(first) else { Issue.record("expected duplicate"); return }
        let collision = fixture.job(source: "2026_other_story_city_us.wav", output: inserted.relativeOutputPath.uppercased(), hash: "two")
        #expect(try await repository!.enqueue(collision) == .outputCollision)

        let claimed = try #require(try await repository!.claimNext(configurationID: "config"))
        let checkpoint = BatchChunkCheckpoint(index: 0, text: "hello", cues: [TranscriptCue(startSec: 0, endSec: 1, text: "hello")])
        try await repository!.checkpoint(id: claimed.id, checkpoints: [checkpoint], progress: 0.5)
        repository = nil

        let reopened = try SQLiteBatchJobRepository(url: fixture.database)
        #expect(try await reopened.recoverInterrupted() == 1)
        let recovered = try #require(try await reopened.job(id: claimed.id))
        #expect(recovered.state == .pending)
        #expect(recovered.checkpoints == [checkpoint])
        #expect(recovered.attempt == 1)
        guard let reclaimed = try await reopened.claimNext(configurationID: "config") else { Issue.record("expected reclaim"); return }
        try await reopened.complete(id: reclaimed.id, outputFingerprint: GeneratedOutputFingerprint(sha256: "output"))

        let changed = fixture.job(source: first.relativeSourcePath, output: first.relativeOutputPath, hash: "changed")
        guard case let .inserted(generationTwo) = try await reopened.enqueue(changed) else { Issue.record("expected generation two"); return }
        #expect(generationTwo.generation == 2)
        #expect(generationTwo.outputFingerprint == GeneratedOutputFingerprint(sha256: "output"))
        let completedCollision = fixture.job(source: "2026_other_story_city_us.wav", output: inserted.relativeOutputPath.uppercased(), hash: "other")
        #expect(try await reopened.enqueue(completedCollision) == .outputCollision)
    }

    @Test("configuration takeover releases stale pending and filters claims")
    func configurationTakeoverAndFilteredClaims() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let failed = fixture.job(source: "2026_failed_story_city_us.wav", output: "2026_failed_story_city_us.txt", hash: "failed", configurationID: "old")
        guard case let .inserted(failedJob) = try await repository.enqueue(failed) else {
            Issue.record("expected failed job")
            return
        }
        let failedClaim = try #require(try await repository.claimNext(configurationID: "old"))
        #expect(failedClaim.id == failedJob.id)
        #expect(failedClaim.configuration == failed.configuration)
        #expect(failedClaim.relativeSourcePath == failed.relativeSourcePath)
        #expect(failedClaim.relativeOutputPath == failed.relativeOutputPath)
        try await repository.fail(id: failedClaim.id, error: "old failure")

        let stale = fixture.job(source: "2026_stale_story_city_us.wav", output: "2026_stale_story_city_us.txt", hash: "same", configurationID: "old")
        guard case let .inserted(staleJob) = try await repository.enqueue(stale) else {
            Issue.record("expected stale job")
            return
        }

        let current = fixture.job(source: stale.relativeSourcePath, output: stale.relativeOutputPath, hash: "same", configurationID: "current")
        #expect(try await repository.job(id: staleJob.id)?.state == .pending)
        guard case let .inserted(currentJob) = try await repository.enqueue(current) else {
            Issue.record("expected current generation")
            return
        }
        #expect(currentJob.generation == staleJob.generation + 1)
        #expect(try await repository.job(id: failedJob.id)?.state == .failed)
        #expect(try await repository.job(id: failedJob.id)?.lastError == "old failure")
        #expect(try await repository.job(id: failedJob.id)?.configuration == failed.configuration)
        #expect(try await repository.job(id: failedJob.id)?.relativeSourcePath == failed.relativeSourcePath)
        #expect(try await repository.job(id: failedJob.id)?.relativeOutputPath == failed.relativeOutputPath)
        #expect(try await repository.job(id: staleJob.id)?.state == .cancelled)
        #expect(try await repository.job(id: staleJob.id)?.configuration == stale.configuration)
        #expect(try await repository.job(id: staleJob.id)?.relativeSourcePath == stale.relativeSourcePath)
        #expect(try await repository.job(id: staleJob.id)?.relativeOutputPath == stale.relativeOutputPath)
        #expect(try await repository.claimNext(configurationID: "old") == nil)
        let currentClaim = try #require(try await repository.claimNext(configurationID: "current"))
        #expect(currentClaim.id == currentJob.id)
        #expect(currentClaim.generation == currentJob.generation)
        #expect(currentClaim.configuration == current.configuration)
        #expect(currentClaim.relativeSourcePath == current.relativeSourcePath)
        #expect(currentClaim.relativeOutputPath == current.relativeOutputPath)
    }

    @Test("accepts normalized nested paths and rejects unsafe paths and stale terminal transitions")
    func validationAndCAS() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let nested = fixture.job(
            source: "interviews/day-one/2026_person_story_city_us.wav",
            output: "interviews/day-one/2026_person_story_city_us.txt",
            hash: "nested"
        )
        guard case let .inserted(nestedJob) = try await repository.enqueue(nested) else {
            Issue.record("expected nested insert")
            return
        }
        #expect(nestedJob.relativeSourcePath == nested.relativeSourcePath)
        #expect(nestedJob.relativeOutputPath == nested.relativeOutputPath)
        let otherDirectory = fixture.job(
            source: "other/2026_other_story_city_us.wav",
            output: "other/2026_person_story_city_us.txt",
            hash: "other-directory"
        )
        guard case .inserted = try await repository.enqueue(otherDirectory) else {
            Issue.record("same output name in another directory should be independent")
            return
        }
        let nestedCollision = fixture.job(
            source: "interviews/day-one/2026_other_story_city_us.wav",
            output: nested.relativeOutputPath.uppercased(),
            hash: "nested-collision"
        )
        #expect(try await repository.enqueue(nestedCollision) == .outputCollision)

        for path in [
            "", ".", "..", "../escape.wav", "nested/../escape.wav", "nested/./file.wav",
            "/tmp/file.wav", "nested//file.wav", "nested/file.wav/", "nested\\file.wav"
        ] {
            do {
                _ = try await repository.enqueue(fixture.job(source: path, output: "safe.txt", hash: path))
                Issue.record("expected invalid path: \(path)")
            } catch BatchRepositoryError.sqlite {}
        }
        for path in ["/tmp/file.txt", "nested/../escape.txt", "nested//file.txt", "nested\\file.txt"] {
            do {
                _ = try await repository.enqueue(fixture.job(source: "safe.wav", output: path, hash: path))
                Issue.record("expected invalid output path: \(path)")
            } catch BatchRepositoryError.sqlite {}
        }


        let job = fixture.job(source: "2026_person_story_city_us.wav", output: "2026_person_story_city_us.txt", hash: "one")
        guard case let .inserted(inserted) = try await repository.enqueue(job) else { Issue.record("expected insert"); return }
        _ = try #require(try await repository.claimNext(configurationID: "config"))
        try await repository.cancel(id: inserted.id)
        do {
            try await repository.complete(id: inserted.id, outputFingerprint: GeneratedOutputFingerprint(sha256: "late"))
            Issue.record("cancelled work completed")
        } catch BatchRepositoryError.illegalTransition(from: .cancelled, to: .completed) {}
        #expect(try await repository.job(id: inserted.id)?.state == .cancelled)
    }

    @Test("concurrent connections deduplicate enqueue and claim each job once")
    func concurrentEnqueueAndClaim() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try SQLiteBatchJobRepository(url: fixture.database)
        let second = try SQLiteBatchJobRepository(url: fixture.database)
        let proposed = fixture.job(source: "2026_person_story_city_us.wav", output: "2026_person_story_city_us.txt", hash: "one")
        let enqueueBarrier = Barrier(participants: 2)

        async let left: BatchEnqueueResult = {
            await enqueueBarrier.arrive()
            return try await first.enqueue(proposed)
        }()
        async let right: BatchEnqueueResult = {
            await enqueueBarrier.arrive()
            return try await second.enqueue(proposed)
        }()
        let enqueueResults = try await [left, right]
        #expect(enqueueResults.filter { if case .inserted = $0 { true } else { false } }.count == 1)
        #expect(enqueueResults.filter { if case .duplicate = $0 { true } else { false } }.count == 1)

        let other = fixture.job(source: "2026_other_story_city_us.wav", output: "2026_other_story_city_us.txt", hash: "two")
        guard case let .inserted(insertedOther) = try await first.enqueue(other) else { Issue.record("expected second insert"); return }
        let claimBarrier = Barrier(participants: 2)
        async let firstClaim: BatchJob? = {
            await claimBarrier.arrive()
            return try await first.claimNext(configurationID: "config")
        }()
        async let secondClaim: BatchJob? = {
            await claimBarrier.arrive()
            return try await second.claimNext(configurationID: "config")
        }()
        let claimed = try await [firstClaim, secondClaim].compactMap { $0 }
        #expect(Set(claimed.map(\.id)).count == 2)
        #expect(Set(claimed.map(\.id)).contains(insertedOther.id))
    }
    @Test("checkpoint persists progressDetail, totalChunks, and enforces progress monotonicity")
    func progressDetailAndMonotonicity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let job = fixture.job(source: "2026_test_story_city_us.wav", output: "2026_test_story_city_us.txt", hash: "hash1")
        guard case let .inserted(inserted) = try await repository.enqueue(job) else {
            Issue.record("expected insert")
            return
        }
        let claimed = try #require(try await repository.claimNext(configurationID: "config"))
        #expect(claimed.id == inserted.id)
        #expect(claimed.progressDetail == nil)

        // 1. Stage-only planning: totalChunks is nil, fraction is 0.0, detail is .planning
        try await repository.checkpoint(
            id: claimed.id,
            checkpoints: [],
            progress: 0.0,
            totalChunks: nil,
            detail: BatchProgressDetail(phase: .planning)
        )
        let planningJob = try #require(try await repository.job(id: claimed.id))
        #expect(planningJob.progressDetail?.phase == .planning)
        #expect(planningJob.totalChunks == nil)
        #expect(planningJob.progress == 0.0)

        // 2. Transcribing with sub-chunk audio position
        let detailTranscribing = BatchProgressDetail(
            phase: .transcribing,
            currentChunkAudioPositionSec: 15.0,
            currentChunkDurationSec: 60.0
        )
        try await repository.checkpoint(
            id: claimed.id,
            checkpoints: [],
            progress: 0.25,
            totalChunks: 1,
            detail: detailTranscribing
        )
        let transcribingJob = try #require(try await repository.job(id: claimed.id))
        #expect(transcribingJob.progressDetail?.phase == .transcribing)
        #expect(transcribingJob.progressDetail?.currentChunkAudioPositionSec == 15.0)
        #expect(transcribingJob.progressDetail?.currentChunkDurationSec == 60.0)
        #expect(transcribingJob.progress == 0.25)
        #expect(transcribingJob.totalChunks == 1)

        // 3. Monotonicity: lower progress value does NOT regress progress
        try await repository.checkpoint(
            id: claimed.id,
            checkpoints: [],
            progress: 0.10,
            totalChunks: 1,
            detail: detailTranscribing
        )
        let monotonicJob = try #require(try await repository.job(id: claimed.id))
        #expect(monotonicJob.progress == 0.25) // preserved 0.25

        // 4. blockOutputCollision transitions to .blockedOutputCollision, clears progressDetail, preserves progress & checkpoints
        let cue = TranscriptCue(startSec: 0, endSec: 10, text: "part 1")
        let cp = BatchChunkCheckpoint(index: 0, text: "part 1", cues: [cue])
        try await repository.checkpoint(
            id: claimed.id,
            checkpoints: [cp],
            progress: 1.0,
            totalChunks: 1,
            detail: BatchProgressDetail(phase: .finalizing)
        )
        try await repository.blockOutputCollision(id: claimed.id, error: "Output conflict: companion file already exists.")
        let blocked = try #require(try await repository.job(id: claimed.id))
        #expect(blocked.state == .blockedOutputCollision)
        #expect(blocked.progressDetail == nil)
        #expect(blocked.checkpoints == [cp])
        #expect(blocked.progress == 1.0)
        #expect(blocked.finishedAt != nil)
        #expect(blocked.lastError?.contains("Output conflict") == true)

        // 5. Retry from blockedOutputCollision transitions back to pending, clears progressDetail, preserves checkpoints
        try await repository.retry(id: claimed.id)
        let retried = try #require(try await repository.job(id: claimed.id))
        #expect(retried.state == .pending)
        #expect(retried.checkpoints == [cp])
        #expect(retried.progressDetail == nil)
    }

    private actor Barrier {
        private let participants: Int
        private var arrivals = 0
        private var continuations: [CheckedContinuation<Void, Never>] = []

        init(participants: Int) { self.participants = participants }

        func arrive() async {
            arrivals += 1
            if arrivals == participants {
                continuations.forEach { $0.resume() }
                continuations.removeAll()
                return
            }
            await withCheckedContinuation { continuations.append($0) }
        }
    }

    private struct Fixture {
        let root: URL
        let database: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            database = root.appendingPathComponent("jobs.sqlite")
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
        func job(
            source: String,
            output: String,
            hash: String,
            configurationID: String = "config"
        ) -> BatchJob {
            BatchJob(
                profileID: "profile",
                relativeSourcePath: source,
                relativeOutputPath: output,
                sourceFingerprint: SourceFileFingerprint(byteCount: 1, modificationTimeNanoseconds: 2, sha256: hash),
                configuration: BatchTranscriptionConfiguration(identifier: configurationID, sourceLanguage: "en")
            )
        }
    }
}
