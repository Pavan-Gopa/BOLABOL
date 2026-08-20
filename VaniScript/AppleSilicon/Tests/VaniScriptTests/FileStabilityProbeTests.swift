import Foundation
import Testing
@testable import VaniScriptRuntime

@Suite("File stability probe")
struct FileStabilityProbeTests {
    @Test("Rejects partial copy and renamed file until stable")
    func partialCopyAndRename() async {
        let snapshots = SnapshotSequence([
            .init(byteCount: 10, modificationTimeNanoseconds: 1),
            .init(byteCount: 20, modificationTimeNanoseconds: 2),
            .init(byteCount: 20, modificationTimeNanoseconds: 2),
            .init(byteCount: 20, modificationTimeNanoseconds: 2)
        ])
        let probe = FileStabilityProbe(
            delay: .zero,
            snapshot: { _ in snapshots.next() },
            sleep: { _ in },
            audioReadable: { _ in true }
        )
        let url = URL(fileURLWithPath: "/recording.wav")
        #expect(!(await probe.isStableAudio(at: url)))
        #expect(await probe.isStableAudio(at: url))
    }

    @Test("Rejects unreadable audio after stable snapshots")
    func unreadableAudio() async {
        let stable = FileStabilitySnapshot(byteCount: 10, modificationTimeNanoseconds: 1)
        let probe = FileStabilityProbe(
            delay: .zero,
            snapshot: { _ in stable },
            sleep: { _ in },
            audioReadable: { _ in false }
        )
        #expect(!(await probe.isStableAudio(at: URL(fileURLWithPath: "/bad.wav"))))
    }

    @Test("Batch observation sleeps once and preserves sorted candidate safety")
    func batchObservationSleepsOnceAndPreservesInputOrder() async {
        let urls = (0..<14).map { URL(fileURLWithPath: "/candidate-\($0).wav") }
        let counters = StabilityCounters()
        let probe = FileStabilityProbe(
            delay: .zero,
            snapshot: { url in
                counters.snapshot()
                return FileStabilitySnapshot(
                    byteCount: Int64(url.lastPathComponent.hashValue),
                    modificationTimeNanoseconds: 1
                )
            },
            sleep: { _ in counters.sleep() },
            audioReadable: { _ in
                counters.readabilityStarted()
                counters.readabilityFinished()
                return true
            }
        )

        let stable = await probe.stableAudioSnapshots(at: urls)
        #expect(counters.sleepCount == 1)
        #expect(counters.snapshotCount == urls.count * 2)
        #expect(urls.filter { stable[$0] != nil } == urls)
        #expect(counters.maximumReadability == 1)
    }

    @Test("Production snapshot rejects symlinks")
    func symlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("audio.wav")
        let link = root.appendingPathComponent("link.wav")
        try Data([1]).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(try FileStabilityProbe.fileSnapshot(file) != nil)
        #expect(try FileStabilityProbe.fileSnapshot(link) == nil)
    }

    @Test("Production readability fails closed for invalid audio")
    func productionReadabilityRejectsInvalidAudio() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        try Data("not audio".utf8).write(to: url)
        #expect(try await !FileStabilityProbe.audioReadable(url))
    }
}

private final class SnapshotSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [FileStabilitySnapshot]
    init(_ values: [FileStabilitySnapshot]) { self.values = values }
    func next() -> FileStabilitySnapshot? { lock.withLock { values.isEmpty ? nil : values.removeFirst() } }
}

private final class StabilityCounters: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var sleepCount = 0
    private(set) var snapshotCount = 0
    private(set) var maximumReadability = 0
    private var activeReadability = 0

    func snapshot() { lock.withLock { snapshotCount += 1 } }
    func sleep() { lock.withLock { sleepCount += 1 } }
    func readabilityStarted() {
        lock.withLock {
            activeReadability += 1
            maximumReadability = max(maximumReadability, activeReadability)
        }
    }
    func readabilityFinished() { lock.withLock { activeReadability -= 1 } }
}
