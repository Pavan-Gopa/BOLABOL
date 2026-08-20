import Foundation
import Testing
import VaniScriptCore
@testable import VaniScriptRuntime

@Suite("Security scoped folder store")
struct SecurityScopedFolderStoreTests {
    @Test("Persists profiles and decodes legacy defaults")
    func persistenceAndCompatibility() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("profiles.json")
        let store = SecurityScopedFolderStore(
            profilesURL: url,
            createBookmark: { Data($0.path.utf8) },
            resolveBookmark: { (URL(fileURLWithPath: String(decoding: $0, as: UTF8.self)), false) }
        )
        let profile = try store.profile(id: "one", name: "Inbox", folderURL: root, recursive: true)
        try store.save([profile])
        #expect(try store.load() == [profile])

        let legacy = Data(#"[{"id":"old","name":"Legacy"}]"#.utf8)
        try legacy.write(to: url, options: .atomic)
        let decoded = try #require(store.load().first)
        #expect(decoded.enabled)
        #expect(!decoded.recursive)
        #expect(decoded.displayPath.isEmpty)
    }

    @Test("Reports stale, revoked, and unavailable bookmarks")
    func statuses() {
        let profile = BatchFolderProfile(id: "p", name: "P", bookmarkData: Data([1]))
        let stale = SecurityScopedFolderStore(
            profilesURL: URL(fileURLWithPath: "/unused"),
            resolveBookmark: { _ in (URL(fileURLWithPath: "/folder"), true) }
        )
        #expect(stale.resolve(profile) == .stale(URL(fileURLWithPath: "/folder")))

        let revoked = SecurityScopedFolderStore(
            profilesURL: URL(fileURLWithPath: "/unused"),
            resolveBookmark: { _ in throw CocoaError(.fileReadNoPermission) }
        )
        #expect(revoked.resolve(profile) == .revoked)
        #expect(revoked.resolve(BatchFolderProfile(id: "none", name: "None")) == .unavailable)
    }

    @Test("Refreshes a stale bookmark atomically without changing profile fields")
    func staleRefresh() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profilesURL = root.appendingPathComponent("profiles.json")
        let refreshedBookmark = Data([9, 8, 7])
        let store = SecurityScopedFolderStore(
            profilesURL: profilesURL,
            createBookmark: { _ in refreshedBookmark }
        )
        let original = BatchFolderProfile(
            id: "profile", name: "Inbox", bookmarkData: Data([1]),
            displayPath: "/original", enabled: false, recursive: true
        )
        var profiles = [original]
        try store.save(profiles)

        let refreshed = try store.refresh(original, at: root, in: &profiles)

        #expect(refreshed.bookmarkData == refreshedBookmark)
        #expect(refreshed.name == original.name)
        #expect(refreshed.displayPath == original.displayPath)
        #expect(refreshed.enabled == original.enabled)
        #expect(refreshed.recursive == original.recursive)
        #expect(try store.load() == profiles)
    }

    @Test("Balances successful access exactly once")
    func balancedAccess() {
        let counter = LockedCounter()
        let store = SecurityScopedFolderStore(
            profilesURL: URL(fileURLWithPath: "/unused"),
            startAccess: { _ in counter.incrementStart(); return true },
            stopAccess: { _ in counter.incrementStop() }
        )
        let lease = store.beginAccess(to: URL(fileURLWithPath: "/folder"))
        #expect(lease != nil)
        lease?.close()
        lease?.close()
        #expect(counter.values == (1, 1))
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    var values: (Int, Int) { lock.withLock { (starts, stops) } }
    func incrementStart() { lock.withLock { starts += 1 } }
    func incrementStop() { lock.withLock { stops += 1 } }
}
