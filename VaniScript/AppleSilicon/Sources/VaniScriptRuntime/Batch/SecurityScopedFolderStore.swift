import Foundation
import VaniScriptCore

public enum SecurityScopedFolderStatus: Equatable, Sendable {
    case active(URL)
    case stale(URL)
    case revoked
    case unavailable
}

public final class SecurityScopedAccessLease: @unchecked Sendable {
    public let url: URL
    private let stop: @Sendable (URL) -> Void
    private let lock = NSLock()
    private var isActive = true

    fileprivate init(url: URL, stop: @escaping @Sendable (URL) -> Void) {
        self.url = url
        self.stop = stop
    }

    public func close() {
        lock.lock()
        guard isActive else { lock.unlock(); return }
        isActive = false
        lock.unlock()
        stop(url)
    }

    deinit { close() }
}

public struct SecurityScopedFolderStore: Sendable {
    public typealias BookmarkCreator = @Sendable (URL) throws -> Data
    public typealias BookmarkResolver = @Sendable (Data) throws -> (url: URL, isStale: Bool)
    public typealias AccessStarter = @Sendable (URL) -> Bool
    public typealias AccessStopper = @Sendable (URL) -> Void

    private let profilesURL: URL
    private let createBookmark: BookmarkCreator
    private let resolveBookmark: BookmarkResolver
    private let startAccess: AccessStarter
    private let stopAccess: AccessStopper

    public init(
        profilesURL: URL,
        createBookmark: @escaping BookmarkCreator = SecurityScopedFolderStore.platformCreateBookmark,
        resolveBookmark: @escaping BookmarkResolver = SecurityScopedFolderStore.platformResolveBookmark,
        startAccess: @escaping AccessStarter = { $0.startAccessingSecurityScopedResource() },
        stopAccess: @escaping AccessStopper = { $0.stopAccessingSecurityScopedResource() }
    ) {
        self.profilesURL = profilesURL
        self.createBookmark = createBookmark
        self.resolveBookmark = resolveBookmark
        self.startAccess = startAccess
        self.stopAccess = stopAccess
    }

    public func load() throws -> [BatchFolderProfile] {
        guard FileManager.default.fileExists(atPath: profilesURL.path) else { return [] }
        return try JSONDecoder().decode([BatchFolderProfile].self, from: Data(contentsOf: profilesURL))
    }

    public func save(_ profiles: [BatchFolderProfile]) throws {
        try FileManager.default.createDirectory(
            at: profilesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(profiles)
        try data.write(to: profilesURL, options: [.atomic])
    }

    public func profile(id: String, name: String, folderURL: URL, recursive: Bool = false) throws -> BatchFolderProfile {
        BatchFolderProfile(
            id: id,
            name: name,
            bookmarkData: try createBookmark(folderURL),
            displayPath: folderURL.path,
            enabled: true,
            recursive: recursive
        )
    }

    public func refresh(
        _ profile: BatchFolderProfile,
        at url: URL,
        in profiles: inout [BatchFolderProfile]
    ) throws -> BatchFolderProfile {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        var updatedProfiles = profiles
        var refreshed = updatedProfiles[index]
        refreshed.bookmarkData = try createBookmark(url)
        updatedProfiles[index] = refreshed
        try save(updatedProfiles)
        profiles = updatedProfiles
        return refreshed
    }

    public func resolve(_ profile: BatchFolderProfile) -> SecurityScopedFolderStatus {
        guard let bookmark = profile.bookmarkData else { return .unavailable }
        do {
            let resolved = try resolveBookmark(bookmark)
            return resolved.isStale ? .stale(resolved.url) : .active(resolved.url)
        } catch let error as CocoaError where error.code == .fileReadNoPermission || error.code == .fileNoSuchFile {
            return .revoked
        } catch {
            return .unavailable
        }
    }

    public func beginAccess(to url: URL) -> SecurityScopedAccessLease? {
        guard startAccess(url) else { return nil }
        return SecurityScopedAccessLease(url: url, stop: stopAccess)
    }

    public static func platformCreateBookmark(_ url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public static func platformResolveBookmark(_ data: Data) throws -> (URL, Bool) {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return (url, stale)
    }
}
