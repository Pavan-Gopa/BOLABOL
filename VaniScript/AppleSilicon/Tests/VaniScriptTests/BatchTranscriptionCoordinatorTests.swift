import Foundation
import Testing
import VaniScriptCore
import VaniScriptRuntime
@testable import VaniScript

@Suite("Batch coordinator")
struct BatchTranscriptionCoordinatorTests {
    @Test("three-file one-shot repeat and failure isolation preserve user TXT")
    func endToEnd() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profile = BatchFolderProfile(id: "profile", name: "Fixture")
        let config = BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en")
        let reconciler = FolderReconciler()
        let firstScan = try await reconciler.reconcile(folderURL: fixture.root, profile: profile, configuration: config, repository: repository)
        #expect(firstScan.enqueued.count == 3)
        #expect(firstScan.issues.isEmpty)

        let coordinator = BatchTranscriptionCoordinator(repository: repository, configuration: config, transcriber: StubTranscriber(failingName: fixture.failureName), writer: RealWriter())
        await coordinator.processPending(in: fixture.root)

        let jobs = try await repository.list()
        #expect(jobs.filter { $0.state == .completed }.count == 2)
        #expect(jobs.filter { $0.state == .failed }.count == 1)
        #expect(try String(contentsOf: fixture.userTXT, encoding: .utf8) == "user work")
        let repeatScan = try await reconciler.reconcile(folderURL: fixture.root, profile: profile, configuration: config, repository: repository)
        #expect(repeatScan.enqueued.isEmpty)
        #expect(repeatScan.duplicateCount == 3)
    }

    @Test("refuses a source symlink escaping the watched folder")
    func sourceSymlinkEscape() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let outside = fixture.root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("outside".utf8).write(to: outside)
        let linkName = "2026_link_story_city_us.wav"
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent(linkName), withDestinationURL: outside)
        let job = BatchJob(
            profileID: "profile",
            relativeSourcePath: linkName,
            relativeOutputPath: "2026_link_story_city_us.txt",
            sourceFingerprint: SourceFileFingerprint(byteCount: 7, modificationTimeNanoseconds: 0, sha256: "outside"),
            configuration: BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en")
        )
        guard case let .inserted(inserted) = try await repository.enqueue(job) else { Issue.record("expected insert"); return }
        let coordinator = BatchTranscriptionCoordinator(repository: repository, configuration: job.configuration, transcriber: StubTranscriber(failingName: ""), writer: RealWriter())
        await coordinator.processPending(in: fixture.root)
        #expect(try await repository.job(id: inserted.id)?.state == .failed)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(job.relativeOutputPath).path))
    }

    @Test("early progress persists total chunks and alive fraction before completion")
    func earlyTotalChunksPersistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SingleJob-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("jobs.sqlite")
        let repository = try SQLiteBatchJobRepository(url: database)
        let profile = BatchFolderProfile(id: "profile", name: "Fixture")
        let config = BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en")
        let sourceURL = root.appendingPathComponent("2026_single_story_city_us.wav")
        try Data("audio data".utf8).write(to: sourceURL)

        let reconciler = FolderReconciler()
        let scan = try await reconciler.reconcile(folderURL: root, profile: profile, configuration: config, repository: repository)
        guard let inserted = scan.enqueued.first else {
            Issue.record("expected enqueued job")
            return
        }

        let observedTotalChunks = LockedValue<Int?>(nil)
        let observedProgress = LockedValue<Double?>(nil)

        let transcriber = InspectableProgressTranscriber(
            totalChunksToReport: 5,
            onEarlyProgress: {
                if let currentJob = try await repository.job(id: inserted.id) {
                    observedTotalChunks.set(currentJob.totalChunks)
                    observedProgress.set(currentJob.progress)
                }
            }
        )

        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: config,
            transcriber: transcriber,
            writer: RealWriter()
        )
        await coordinator.processPending(in: root)

        #expect(observedTotalChunks.get() == 5)
        #expect((observedProgress.get() ?? 0) >= 0.01)

        let completedJob = try await repository.job(id: inserted.id)
        #expect(completedJob?.state == .completed)
        #expect(completedJob?.progress == 1.0)
    }
    @Test("thrown progress error marks job failed")
    func progressFailureMarksJobFailed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let config = BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en")
        let sourceName = "2026_first_story_city_us.wav"
        let job = BatchJob(
            profileID: "profile",
            relativeSourcePath: sourceName,
            relativeOutputPath: "2026_first_story_city_us.txt",
            sourceFingerprint: SourceFileFingerprint(byteCount: 7, modificationTimeNanoseconds: 0, sha256: "hash"),
            configuration: config
        )
        guard case let .inserted(inserted) = try await repository.enqueue(job) else {
            Issue.record("expected insert")
            return
        }

        struct ProgressFailTranscriber: BatchAudioTranscribing {
            func transcribe(
                sourceURL: URL,
                resumedCheckpoints: [BatchChunkCheckpoint],
                progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void,
                checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void
            ) async throws -> BatchTranscriptionResult {
                struct TestProgressError: Error, LocalizedError {
                    var errorDescription: String? { "Progress persistence failed" }
                }
                throw TestProgressError()
            }
        }

        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: config,
            transcriber: ProgressFailTranscriber(),
            writer: RealWriter()
        )
        await coordinator.processPending(in: fixture.root)

        let failedJob = try await repository.job(id: inserted.id)
        #expect(failedJob?.state == .failed)
        #expect(failedJob?.lastError?.contains("Progress persistence failed") == true)
    }

    @Test("unknown existing output file routes to blockedOutputCollision and preserves checkpoints")
    func unknownExistingOutputRoutesToBlockedCollision() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let config = BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en")
        let sourceName = "2026_first_story_city_us.wav"
        let job = BatchJob(
            profileID: "profile",
            relativeSourcePath: sourceName,
            relativeOutputPath: "2026_first_story_city_us.txt",
            sourceFingerprint: SourceFileFingerprint(byteCount: 7, modificationTimeNanoseconds: 0, sha256: "hash"),
            configuration: config
        )
        guard case let .inserted(inserted) = try await repository.enqueue(job) else {
            Issue.record("expected insert")
            return
        }

        struct CollisionWriter: BatchCompanionWriting {
            func write(_ data: Data, sourceURL: URL, outputURL: URL, expectedSourceFingerprint: SourceFileFingerprint, knownGeneratedOutput: GeneratedOutputFingerprint?) async throws -> GeneratedOutputFingerprint {
                throw AtomicCompanionWriterError.existingOutputNotKnownGenerated
            }
        }

        let observedEvents = LockedValue<[BatchProcessingEvent]>([])
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: config,
            transcriber: StubTranscriber(failingName: ""),
            writer: CollisionWriter(),
            eventHandler: { event in
                observedEvents.set(observedEvents.get() + [event])
            }
        )
        await coordinator.processPending(in: fixture.root)

        let blockedJob = try await repository.job(id: inserted.id)
        #expect(blockedJob?.state == .blockedOutputCollision)
        #expect(blockedJob?.lastError?.contains("2026_first_story_city_us.txt") == true)
        #expect(blockedJob?.checkpoints.count == 1)
        #expect(blockedJob?.progressDetail == nil)

        let collisionEvent = observedEvents.get().contains { event in
            if case .blockedOutputCollision(let jobID, _) = event { return jobID == inserted.id }
            return false
        }
        #expect(collisionEvent)

        // Retry transitions back to pending and preserves checkpoints
        try await coordinator.retry(jobID: inserted.id)
        let retriedJob = try await repository.job(id: inserted.id)
        #expect(retriedJob?.state == .pending)
        #expect(retriedJob?.checkpoints.count == 1)
    }

    @Test("modified existing output file and case-insensitive collision route to blockedOutputCollision")
    func modifiedAndCaseInsensitiveCollisionRouting() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let config = BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en")
        let sourceName = "2026_first_story_city_us.wav"
        let job = BatchJob(
            profileID: "profile",
            relativeSourcePath: sourceName,
            relativeOutputPath: "2026_first_story_city_us.txt",
            sourceFingerprint: SourceFileFingerprint(byteCount: 7, modificationTimeNanoseconds: 0, sha256: "hash"),
            configuration: config
        )
        guard case let .inserted(inserted) = try await repository.enqueue(job) else {
            Issue.record("expected insert")
            return
        }

        struct CaseInsensitiveWriter: BatchCompanionWriting {
            func write(_ data: Data, sourceURL: URL, outputURL: URL, expectedSourceFingerprint: SourceFileFingerprint, knownGeneratedOutput: GeneratedOutputFingerprint?) async throws -> GeneratedOutputFingerprint {
                throw AtomicCompanionWriterError.caseInsensitiveCollision(existingName: "2026_First_Story_City_US.TXT")
            }
        }

        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: config,
            transcriber: StubTranscriber(failingName: ""),
            writer: CaseInsensitiveWriter()
        )
        await coordinator.processPending(in: fixture.root)

        let blockedJob = try await repository.job(id: inserted.id)
        #expect(blockedJob?.state == .blockedOutputCollision)
        #expect(blockedJob?.lastError?.contains("2026_First_Story_City_US.TXT") == true)
        #expect(blockedJob?.checkpoints.count == 1)
    }

    @Test("non-collision writer errors route to failed state")
    func nonCollisionWriterErrorRoutesToFailed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let config = BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en")
        let sourceName = "2026_first_story_city_us.wav"
        let job = BatchJob(
            profileID: "profile",
            relativeSourcePath: sourceName,
            relativeOutputPath: "2026_first_story_city_us.txt",
            sourceFingerprint: SourceFileFingerprint(byteCount: 7, modificationTimeNanoseconds: 0, sha256: "hash"),
            configuration: config
        )
        guard case let .inserted(inserted) = try await repository.enqueue(job) else {
            Issue.record("expected insert")
            return
        }

        struct PermissionDeniedWriter: BatchCompanionWriting {
            func write(_ data: Data, sourceURL: URL, outputURL: URL, expectedSourceFingerprint: SourceFileFingerprint, knownGeneratedOutput: GeneratedOutputFingerprint?) async throws -> GeneratedOutputFingerprint {
                throw AtomicCompanionWriterError.permissionDenied
            }
        }

        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: config,
            transcriber: StubTranscriber(failingName: ""),
            writer: PermissionDeniedWriter()
        )
        await coordinator.processPending(in: fixture.root)

        let failedJob = try await repository.job(id: inserted.id)
        #expect(failedJob?.state == .failed)
        #expect(failedJob?.lastError?.contains("Permission denied") == true)
    }
    private actor StubTranscriber: BatchAudioTranscribing {
        let failingName: String
        init(failingName: String) { self.failingName = failingName }
        func transcribe(sourceURL: URL, resumedCheckpoints: [BatchChunkCheckpoint], progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void, checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void) async throws -> BatchTranscriptionResult {
            if sourceURL.lastPathComponent == failingName { throw CocoaError(.fileReadCorruptFile) }
            let item = BatchChunkCheckpoint(index: 0, text: "text", cues: [TranscriptCue(startSec: 0, endSec: 1, text: "text")])
            try await checkpoint([item])
            try await progress(BatchTranscriptionProgress(fraction: 1, totalChunks: 1, detail: BatchProgressDetail(phase: .transcribing)))
            return BatchTranscriptionResult(duration: 1, checkpoints: [item])
        }
    }

    private struct InspectableProgressTranscriber: BatchAudioTranscribing {
        let totalChunksToReport: Int
        let onEarlyProgress: @Sendable () async throws -> Void

        func transcribe(
            sourceURL: URL,
            resumedCheckpoints: [BatchChunkCheckpoint],
            progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void,
            checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void
        ) async throws -> BatchTranscriptionResult {
            try await progress(BatchTranscriptionProgress(fraction: 0.01, totalChunks: totalChunksToReport, detail: BatchProgressDetail(phase: .transcribing)))
            try await onEarlyProgress()
            let item = BatchChunkCheckpoint(index: 0, text: "text", cues: [TranscriptCue(startSec: 0, endSec: 1, text: "text")])
            try await checkpoint([item])
            try await progress(BatchTranscriptionProgress(fraction: 1, totalChunks: totalChunksToReport, detail: BatchProgressDetail(phase: .transcribing)))
            return BatchTranscriptionResult(duration: 1, checkpoints: [item])
        }
    }

    private final class LockedValue<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T

        init(_ value: T) {
            self.value = value
        }

        func get() -> T {
            lock.withLock { value }
        }

        func set(_ newValue: T) {
            lock.withLock { value = newValue }
        }
    }

    private struct RealWriter: BatchCompanionWriting {
        func write(_ data: Data, sourceURL: URL, outputURL: URL, expectedSourceFingerprint: SourceFileFingerprint, knownGeneratedOutput: GeneratedOutputFingerprint?) async throws -> GeneratedOutputFingerprint {
            try AtomicCompanionWriter().write(data, request: CompanionWriteRequest(sourceURL: sourceURL, outputURL: outputURL, expectedSourceFingerprint: expectedSourceFingerprint, knownGeneratedOutput: knownGeneratedOutput)).outputFingerprint
        }
    }

    private struct Fixture {
        let root: URL
        let database: URL
        let failureName = "2026_failure_story_city_us.wav"
        let userTXT: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            database = root.appendingPathComponent("jobs.sqlite")
            for name in ["2026_first_story_city_us.wav", failureName, "2026_third_story_city_us.wav"] {
                try Data(name.utf8).write(to: root.appendingPathComponent(name))
            }
            userTXT = root.appendingPathComponent("notes.txt")
            try Data("user work".utf8).write(to: userTXT)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
