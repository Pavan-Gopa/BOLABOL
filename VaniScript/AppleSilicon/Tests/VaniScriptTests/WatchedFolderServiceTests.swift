import Foundation
import Testing
import VaniScriptCore
@testable import VaniScriptRuntime

@Suite("Watched folder service")
struct WatchedFolderServiceTests {
    @Test("Startup scan filters files and duplicate signals stay deduplicated")
    func startupAndDuplicateSignals() async throws {
        let fixture = try Fixture(recursive: false)
        try Data("audio".utf8).write(to: fixture.root.appendingPathComponent("2026_note_story_city_us.wav"))
        try Data("text".utf8).write(to: fixture.root.appendingPathComponent("notes.txt"))
        try Data("temp".utf8).write(to: fixture.root.appendingPathComponent("copy.tmp"))
        try Data("hidden".utf8).write(to: fixture.root.appendingPathComponent(".2026_hidden_story_city_us.wav"))
        let activation = try await fixture.service.activate()
        await fixture.service.beginReconciliation(generation: activation.generation)
        _ = try await fixture.service.reconcile(profileID: "profile")
        #expect(try await fixture.repository.list().count == 1)
        await fixture.service.signal(profileID: "profile")
        await fixture.service.signal(profileID: "profile")
        try await Task.sleep(for: .milliseconds(30))
        #expect(try await fixture.repository.list().count == 1)
        await fixture.service.stop()
        #expect(fixture.access.values == (1, 1))
    }

    @Test("OFF-mode startup queues arbitrary names with exact-stem companions")
    func offModeStartupQueuesArbitraryName() async throws {
        let fixture = try Fixture(recursive: false)
        try Data("audio".utf8).write(to: fixture.root.appendingPathComponent("My Lecture.mp3"))

        await fixture.service.updateConfiguration(
            .init(identifier: "config", sourceLanguage: "en"),
            requireCanonicalNames: false
        )
        let activation = try await fixture.service.activate()
        await fixture.service.beginReconciliation(generation: activation.generation)
        _ = try await fixture.service.reconcile(profileID: "profile")

        let jobs = try await fixture.repository.list()
        #expect(jobs.count == 1)
        #expect(jobs.first?.state == .pending)
        #expect(jobs.first?.relativeSourcePath == "My Lecture.mp3")
        #expect(jobs.first?.relativeOutputPath == "My Lecture.txt")
        let repeated = try await fixture.service.reconcile(profileID: "profile")
        #expect(repeated?.issues.isEmpty == true)
        await fixture.service.stop()
    }

    @Test("Recursive option and symlink exclusion")
    func recursiveAndSymlink() async throws {
        let fixture = try Fixture(recursive: true)
        let nested = fixture.root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let audio = nested.appendingPathComponent("2026_nested_story_city_us.wav")
        try Data("audio".utf8).write(to: audio)
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("2026_link_story_city_us.wav"),
            withDestinationURL: audio
        )
        let outside = fixture.root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outside.appendingPathComponent("2026_escape_story_city_us.wav"))
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("escaped"),
            withDestinationURL: outside
        )
        let activation = try await fixture.service.activate()
        await fixture.service.beginReconciliation(generation: activation.generation)
        _ = try await fixture.service.reconcile(profileID: "profile")
        let jobs = try await fixture.repository.list()
        #expect(jobs.map(\.relativeSourcePath) == ["nested/2026_nested_story_city_us.wav"])
        #expect(jobs.map(\.relativeOutputPath) == ["nested/2026_nested_story_city_us.txt"])
        await fixture.service.stop()
    }

    @Test("Recursive off ignores nested audio and unreadable audio")
    func recursiveOffAndUnreadable() async throws {
        let fixture = try Fixture(recursive: false, readable: false)
        let nested = fixture.root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: nested.appendingPathComponent("2026_nested_story_city_us.wav"))
        try Data("bad".utf8).write(to: fixture.root.appendingPathComponent("2026_bad_story_city_us.wav"))
        let activation = try await fixture.service.activate()
        await fixture.service.beginReconciliation(generation: activation.generation)
        _ = try await fixture.service.reconcile(profileID: "profile")
        #expect(try await fixture.repository.list().isEmpty)
        await fixture.service.stop()
    }

    @Test("Recursive off rejects a top-level audio symlink")
    func nonrecursiveSymlink() async throws {
        let fixture = try Fixture(recursive: false)
        let outside = fixture.root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("2026_escape_story_city_us.wav"),
            withDestinationURL: outside
        )
        let activation = try await fixture.service.activate()
        await fixture.service.beginReconciliation(generation: activation.generation)
        _ = try await fixture.service.reconcile(profileID: "profile")
        #expect(try await fixture.repository.list().isEmpty)
        await fixture.service.stop()
    }

    @Test("Startup exposes unavailable, revoked, access denied, and watch failure")
    func failureStatuses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let profiles = [
            BatchFolderProfile(id: "unavailable", name: "Unavailable"),
            BatchFolderProfile(id: "revoked", name: "Revoked", bookmarkData: Data([1])),
            BatchFolderProfile(id: "denied", name: "Denied", bookmarkData: Data([2])),
            BatchFolderProfile(id: "watch", name: "Watch", bookmarkData: Data([3]))
        ]
        let store = SecurityScopedFolderStore(
            profilesURL: root.appendingPathComponent("profiles.json"),
            resolveBookmark: { data in
                if data == Data([1]) { throw CocoaError(.fileReadNoPermission) }
                let name = data == Data([2]) ? "denied" : "watch"
                return (root.appendingPathComponent(name), false)
            },
            startAccess: { !$0.lastPathComponent.elementsEqual("denied") }
        )
        try store.save(profiles)
        let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
        let stops = AccessCounts()
        let service = WatchedFolderService(
            store: store,
            repository: repository,
            configuration: .init(identifier: "config", sourceLanguage: "en"),
            stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true }),
            startWatching: { path, _ in
                guard !path.hasSuffix("watch") else { return nil }
                return { stops.stop() }
            }
        )
        let activation = try await service.activate()
        await service.beginReconciliation(generation: activation.generation)
        let statuses = activation.statuses
        #expect(statuses.contains(.init(profileID: "unavailable", status: .unavailable)))
        #expect(statuses.contains(.init(profileID: "revoked", status: .revoked)))
        #expect(statuses.contains(.init(profileID: "watch", status: .watchFailed)))
        #expect(statuses.contains(.init(profileID: "denied", status: .accessDenied)))
        await service.stop()
    }

    @Test("Watcher signals coalesce and stop cancels pending reconciliation")
    func coalescingAndStop() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
        let store = SecurityScopedFolderStore(
            profilesURL: root.appendingPathComponent("profiles.json"),
            resolveBookmark: { _ in (root, false) },
            startAccess: { _ in true }
        )
        try store.save([BatchFolderProfile(id: "profile", name: "Watched", bookmarkData: Data([1]))])
        let signals = WatchSignalCapture()
        let snapshots = SnapshotCallCounter()
        let probe = FileStabilityProbe(
            delay: .zero,
            snapshot: { url in
                snapshots.increment()
                return try FileStabilityProbe.fileSnapshot(url)
            },
            sleep: { _ in },
            audioReadable: { _ in true }
        )
        let service = WatchedFolderService(
            store: store,
            repository: repository,
            configuration: .init(identifier: "config", sourceLanguage: "en"),
            stabilityProbe: probe,
            coalescingDelay: .milliseconds(20),
            startWatching: { _, signal in signals.store(signal); return {} }
        )
        let activation = try await service.activate()
        await service.beginReconciliation(generation: activation.generation)
        try Data("audio".utf8).write(to: root.appendingPathComponent("2026_first_story_city_us.wav"))
        signals.fire()
        signals.fire()
        for _ in 0..<200 where (try await repository.list()).count != 1 || snapshots.value != 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(try await repository.list().count == 1)
        #expect(snapshots.value == 2)

        try Data("audio".utf8).write(to: root.appendingPathComponent("2026_second_story_city_us.wav"))
        signals.fire()
        await service.stop()
        try await Task.sleep(for: .milliseconds(60))
        #expect(try await repository.list().count == 1)
        #expect(snapshots.value == 2)
    }

    @Test("Stale bookmark refresh is observed and access remains balanced")
    func staleRefreshStatus() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let counts = AccessCounts()
        let store = SecurityScopedFolderStore(
            profilesURL: root.appendingPathComponent("profiles.json"),
            createBookmark: { _ in Data([2]) },
            resolveBookmark: { _ in (root, true) },
            startAccess: { _ in counts.start(); return true },
            stopAccess: { _ in counts.stop() }
        )
        try store.save([BatchFolderProfile(id: "stale", name: "Stale", bookmarkData: Data([1]), recursive: true)])
        let service = WatchedFolderService(
            store: store,
            repository: try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite")),
            configuration: .init(identifier: "config", sourceLanguage: "en"),
            stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true }),
            startWatching: { _, _ in {} }
        )
        let activation = try await service.activate()
        await service.beginReconciliation(generation: activation.generation)
        let statuses = activation.statuses
        #expect(try #require(store.load().first).bookmarkData == Data([2]))
        await service.stop()
        #expect(counts.values == (1, 1))
    }
}

private struct Fixture {
    let root: URL
    let repository: SQLiteBatchJobRepository
    let service: WatchedFolderService
    let access: AccessCounts

    init(recursive: Bool, readable: Bool = true) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
        let access = AccessCounts()
        self.root = root
        self.repository = repository
        self.access = access
        let profile = BatchFolderProfile(
            id: "profile", name: "Watched", bookmarkData: Data([1]),
            displayPath: root.path, enabled: true, recursive: recursive
        )
        let profilesURL = root.appendingPathComponent("profiles.json")
        let store = SecurityScopedFolderStore(
            profilesURL: profilesURL,
            resolveBookmark: { _ in (root, false) },
            startAccess: { _ in access.start(); return true },
            stopAccess: { _ in access.stop() }
        )
        try store.save([profile])
        let probe = FileStabilityProbe(
            delay: .zero,
            sleep: { _ in },
            audioReadable: { _ in readable }
        )
        service = WatchedFolderService(
            store: store,
            repository: repository,
            configuration: BatchTranscriptionConfiguration(identifier: "config", sourceLanguage: "en"),
            stabilityProbe: probe,
            coalescingDelay: .milliseconds(5)
        )
    }
}

private final class AccessCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    var values: (Int, Int) { lock.withLock { (starts, stops) } }
    func start() { lock.withLock { starts += 1 } }
    func stop() { lock.withLock { stops += 1 } }
}

private final class WatchSignalCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var signal: (@Sendable () -> Void)?

    func store(_ signal: @escaping @Sendable () -> Void) { lock.withLock { self.signal = signal } }
    func fire() { lock.withLock { signal }?() }
}

private final class SnapshotCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
