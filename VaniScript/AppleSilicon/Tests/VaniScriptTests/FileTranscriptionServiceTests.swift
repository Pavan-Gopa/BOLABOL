import Foundation
import Testing
import VaniScriptCore
@testable import VaniScriptRuntime

@Suite("File transcription service")
struct FileTranscriptionServiceTests {
    @Test("preserves words, offsets timing once, checkpoints in order, and cleans workspace")
    func transcribesASROnlyInOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileTranscription-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let log = ServiceLog()
        let processor = AudioChunkProcessingService(
            export: { _, chunk, workspace in
                let url = workspace.appendingPathComponent("\(chunk.index).wav")
                try Data([1]).write(to: url)
                return url
            },
            transcribe: { url, _ in
                let index = Int(url.deletingPathExtension().lastPathComponent) ?? 0
                await log.transcribed(index)
                return RelativeTranscription(
                    text: "chunk \(index)",
                    cues: [TranscriptCue(
                        startSec: 1,
                        endSec: 2,
                        text: "chunk \(index)",
                        words: [TranscriptWord(startSec: 1.25, endSec: 1.75, text: "chunk")]
                    )]
                )
            }
        )
        let service = FileTranscriptionService(
            scheduler: TranscriptionScheduler(),
            chunkProcessor: processor,
            workspaceOwner: TranscriptionWorkspaceOwner(rootURL: root)
        )
        let source = root.appendingPathComponent("source.wav")
        let result = try await service.transcribe(
            FileTranscriptionRequest(
                sourceURL: source,
                chunks: [
                    FileTranscriptionChunk(index: 0, startSec: 0, endSec: 10),
                    FileTranscriptionChunk(index: 1, startSec: 10, endSec: 20),
                ],
                workspaceID: "job-1",
                priority: .background
            ),
            checkpoint: { await log.checkpoint($0.completedChunks.map(\.index)) }
        )

        #expect(result.text == "chunk 0\nchunk 1")
        #expect(result.cues.map(\.startSec) == [1, 11])
        #expect(result.cues.map(\.endSec) == [2, 12])
        #expect(result.cues[1].words?.first?.startSec == 11.25)
        #expect(result.cues[1].words?.first?.endSec == 11.75)
        #expect(await log.transcribedIndices == [0, 1])
        #expect(await log.checkpoints == [[0], [0, 1]])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("job-1").path))
    }

    @Test("rejects nonempty text without model cues and cleans workspace")
    func rejectsMissingModelCues() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileTranscriptionMissingCues-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FileTranscriptionService(
            scheduler: TranscriptionScheduler(),
            chunkProcessor: AudioChunkProcessingService(
                export: { _, _, workspace in workspace.appendingPathComponent("chunk.wav") },
                transcribe: { _, _ in RelativeTranscription(text: "model text", cues: nil) }
            ),
            workspaceOwner: TranscriptionWorkspaceOwner(rootURL: root)
        )
        let request = FileTranscriptionRequest(
            sourceURL: root.appendingPathComponent("source.wav"),
            chunks: [FileTranscriptionChunk(index: 0, startSec: 5, endSec: 10)],
            workspaceID: "missing-cues",
            priority: .background
        )

        await #expect(throws: AudioChunkProcessingError.missingModelCues) {
            _ = try await service.transcribe(request)
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("missing-cues").path))
    }

    @Test("preserves authoritative empty model cues")
    func preservesEmptyModelCues() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileTranscriptionEmptyCues-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FileTranscriptionService(
            scheduler: TranscriptionScheduler(),
            chunkProcessor: AudioChunkProcessingService(
                export: { _, _, workspace in workspace.appendingPathComponent("chunk.wav") },
                transcribe: { _, _ in RelativeTranscription(text: "model text", cues: []) }
            ),
            workspaceOwner: TranscriptionWorkspaceOwner(rootURL: root)
        )

        let result = try await service.transcribe(FileTranscriptionRequest(
            sourceURL: root.appendingPathComponent("source.wav"),
            chunks: [FileTranscriptionChunk(index: 0, startSec: 5, endSec: 10)],
            workspaceID: "empty-cues",
            priority: .background
        ))

        #expect(result.text == "model text")
        #expect(result.cues.isEmpty)
    }

    @Test("accepts empty text without model cues")
    func acceptsEmptyTextWithoutModelCues() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileTranscriptionEmptyText-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FileTranscriptionService(
            scheduler: TranscriptionScheduler(),
            chunkProcessor: AudioChunkProcessingService(
                export: { _, _, workspace in workspace.appendingPathComponent("chunk.wav") },
                transcribe: { _, _ in RelativeTranscription(text: " \n\t", cues: nil) }
            ),
            workspaceOwner: TranscriptionWorkspaceOwner(rootURL: root)
        )

        let result = try await service.transcribe(FileTranscriptionRequest(
            sourceURL: root.appendingPathComponent("source.wav"),
            chunks: [FileTranscriptionChunk(index: 0, startSec: 0, endSec: 1)],
            workspaceID: "empty-text",
            priority: .background
        ))

        #expect(result.text.isEmpty)
        #expect(result.cues.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("empty-text").path))
    }

    @Test("rejects duplicate and descending chunk indices before creating a workspace")
    func rejectsInvalidChunkIndices() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileTranscriptionIndices-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FileTranscriptionService(
            scheduler: TranscriptionScheduler(),
            chunkProcessor: AudioChunkProcessingService(
                export: { _, _, workspace in workspace.appendingPathComponent("chunk.wav") },
                transcribe: { _, _ in RelativeTranscription(text: "", cues: nil) }
            ),
            workspaceOwner: TranscriptionWorkspaceOwner(rootURL: root)
        )
        let source = root.appendingPathComponent("source.wav")

        for (workspaceID, indices) in [("duplicate", [0, 0]), ("descending", [1, 0])] {
            let request = FileTranscriptionRequest(
                sourceURL: source,
                chunks: indices.enumerated().map { position, index in
                    FileTranscriptionChunk(index: index, startSec: Double(position), endSec: Double(position + 1))
                },
                workspaceID: workspaceID,
                priority: .background
            )
            await #expect(throws: CocoaError.self) {
                _ = try await service.transcribe(request)
            }
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(workspaceID).path))
        }
    }

    @Test("distinct workspace IDs cannot alias or delete each other's files")
    func isolatesSanitizedWorkspaceIDs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileTranscriptionIsolation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = TranscriptionWorkspaceOwner(rootURL: root)
        let first = try owner.workspace(for: "job/a")
        let marker = first.appendingPathComponent("active")
        try Data([1]).write(to: marker)
        #expect(throws: CocoaError.self) {
            _ = try owner.workspace(for: "job/a")
        }
        #expect(FileManager.default.fileExists(atPath: marker.path))

        let second = try owner.workspace(for: "job?a")
        let secondMarker = second.appendingPathComponent("active")
        try Data([2]).write(to: secondMarker)

        try owner.remove(first)

        #expect(first != second)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(FileManager.default.fileExists(atPath: secondMarker.path))
        #expect(throws: CocoaError.self) {
            try owner.remove(root.deletingLastPathComponent().appendingPathComponent(first.lastPathComponent))
        }
        #expect(FileManager.default.fileExists(atPath: secondMarker.path))
    }

    @Test("cleans deterministic workspace on error and cancellation")
    func cleansFailures() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileTranscriptionCleanup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        struct Failure: Error {}
        let failing = FileTranscriptionService(
            scheduler: TranscriptionScheduler(),
            chunkProcessor: AudioChunkProcessingService(
                export: { _, _, workspace in workspace.appendingPathComponent("chunk.wav") },
                transcribe: { _, _ in throw Failure() }
            ),
            workspaceOwner: TranscriptionWorkspaceOwner(rootURL: root)
        )
        let request = FileTranscriptionRequest(
            sourceURL: root.appendingPathComponent("source.wav"),
            chunks: [FileTranscriptionChunk(index: 0, startSec: 0, endSec: 1)],
            workspaceID: "failure",
            priority: .background
        )
        await #expect(throws: Failure.self) { _ = try await failing.transcribe(request) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("failure").path))

        let started = AsyncStream<Void>.makeStream()
        let cancelling = FileTranscriptionService(
            scheduler: TranscriptionScheduler(),
            chunkProcessor: AudioChunkProcessingService(
                export: { _, _, workspace in workspace.appendingPathComponent("chunk.wav") },
                transcribe: { _, _ in
                    started.continuation.yield()
                    try await Task.sleep(for: .seconds(60))
                    return RelativeTranscription(text: "unreachable")
                }
            ),
            workspaceOwner: TranscriptionWorkspaceOwner(rootURL: root)
        )
        let cancelledRequest = FileTranscriptionRequest(
            sourceURL: request.sourceURL,
            chunks: request.chunks,
            workspaceID: "cancelled",
            priority: .background
        )
        let task = Task { try await cancelling.transcribe(cancelledRequest) }
        for await _ in started.stream { break }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("cancelled").path))
    }

    @Test("ordered progress events are delivered in sequence and awaited")
    func orderedProgressEventsDeliveredInSequence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileTranscriptionProgressOrder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let eventLog = ProgressOrderLog()
        let processor = AudioChunkProcessingService(
            export: { _, chunk, workspace in
                let url = workspace.appendingPathComponent("\(chunk.index).wav")
                try Data([1]).write(to: url)
                return url
            },
            transcribe: { url, _ in
                let index = Int(url.deletingPathExtension().lastPathComponent) ?? 0
                await eventLog.record("process-\(index)")
                return RelativeTranscription(
                    text: "chunk \(index)",
                    cues: [TranscriptCue(startSec: 0, endSec: 1, text: "chunk \(index)")]
                )
            }
        )
        let service = FileTranscriptionService(
            scheduler: TranscriptionScheduler(),
            chunkProcessor: processor,
            workspaceOwner: TranscriptionWorkspaceOwner(rootURL: root)
        )
        let source = root.appendingPathComponent("source.wav")
        _ = try await service.transcribe(
            FileTranscriptionRequest(
                sourceURL: source,
                chunks: [
                    FileTranscriptionChunk(index: 0, startSec: 0, endSec: 5),
                    FileTranscriptionChunk(index: 1, startSec: 5, endSec: 10)
                ],
                workspaceID: "progress-order",
                priority: .background
            ),
            progress: { event in
                switch event {
                case .started(let total):
                    await eventLog.record("started-\(total)")
                case .transcribing(let index, let total):
                    await eventLog.record("transcribing-\(index)-\(total)")
                case .completed(let index, let total):
                    await eventLog.record("completed-\(index)-\(total)")
                }
            },
            checkpoint: { _ in
                await eventLog.record("checkpoint")
            }
        )

        let recorded = await eventLog.events
        #expect(recorded == [
            "started-2",
            "transcribing-0-2",
            "process-0",
            "checkpoint",
            "completed-0-2",
            "transcribing-1-2",
            "process-1",
            "checkpoint",
            "completed-1-2"
        ])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("progress-order").path))
    }

    @Test("progress error aborts transcription and cleans workspace")
    func progressErrorAbortsTranscriptionAndCleansWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileTranscriptionProgressError-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        struct CustomProgressError: Error, LocalizedError {
            var errorDescription: String? { "Progress failed" }
        }
        let processedIndices = LockedValue<[Int]>([])
        let processor = AudioChunkProcessingService(
            export: { _, chunk, workspace in
                let url = workspace.appendingPathComponent("\(chunk.index).wav")
                try Data([1]).write(to: url)
                return url
            },
            transcribe: { url, _ in
                let index = Int(url.deletingPathExtension().lastPathComponent) ?? 0
                processedIndices.set(processedIndices.get() + [index])
                return RelativeTranscription(text: "chunk", cues: [])
            }
        )
        let service = FileTranscriptionService(
            scheduler: TranscriptionScheduler(),
            chunkProcessor: processor,
            workspaceOwner: TranscriptionWorkspaceOwner(rootURL: root)
        )
        let source = root.appendingPathComponent("source.wav")
        let request = FileTranscriptionRequest(
            sourceURL: source,
            chunks: [
                FileTranscriptionChunk(index: 0, startSec: 0, endSec: 5),
                FileTranscriptionChunk(index: 1, startSec: 5, endSec: 10)
            ],
            workspaceID: "progress-err",
            priority: .background
        )

        await #expect(throws: CustomProgressError.self) {
            _ = try await service.transcribe(
                request,
                progress: { event in
                    if case .transcribing(let index, _) = event, index == 1 {
                        throw CustomProgressError()
                    }
                }
            )
        }

        #expect(processedIndices.get() == [0])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("progress-err").path))
    }
}

private actor ServiceLog {
    private(set) var transcribedIndices: [Int] = []
    private(set) var checkpoints: [[Int]] = []
    func transcribed(_ index: Int) { transcribedIndices.append(index) }
    func checkpoint(_ indices: [Int]) { checkpoints.append(indices) }
}

private actor ProgressOrderLog {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

private final class LockedValue<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.withLock { value } }
    func set(_ newValue: T) { lock.withLock { value = newValue } }
}
