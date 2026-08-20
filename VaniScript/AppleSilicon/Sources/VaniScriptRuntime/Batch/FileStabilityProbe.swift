import AVFoundation
import Darwin
import Foundation

public struct FileStabilitySnapshot: Equatable, Sendable {
    public let byteCount: Int64
    public let modificationTimeNanoseconds: Int64

    public init(byteCount: Int64, modificationTimeNanoseconds: Int64) {
        self.byteCount = byteCount
        self.modificationTimeNanoseconds = modificationTimeNanoseconds
    }
}

public actor FileStabilityProbe {
    public typealias Snapshot = @Sendable (URL) throws -> FileStabilitySnapshot?
    public typealias Sleep = @Sendable (Duration) async throws -> Void
    public typealias AudioReadability = @Sendable (URL) async throws -> Bool

    private let delay: Duration
    private let snapshot: Snapshot
    private let sleep: Sleep
    private let audioReadable: AudioReadability

    public init(
        delay: Duration = .seconds(2),
        snapshot: @escaping Snapshot = FileStabilityProbe.fileSnapshot,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        audioReadable: @escaping AudioReadability = FileStabilityProbe.audioReadable
    ) {
        self.delay = delay
        self.snapshot = snapshot
        self.sleep = sleep
        self.audioReadable = audioReadable
    }

    public func isStableAudio(at url: URL) async -> Bool {
        !(await stableAudioSnapshots(at: [url])).isEmpty
    }

    public func stableAudioSnapshots(at urls: [URL]) async -> [URL: FileStabilitySnapshot] {
        guard !urls.isEmpty else { return [:] }

        var firstSnapshots: [URL: FileStabilitySnapshot] = [:]
        firstSnapshots.reserveCapacity(urls.count)
        for url in urls {
            do {
                if let value = try snapshot(url) {
                    firstSnapshots[url] = value
                }
            } catch {
                continue
            }
        }
        guard !firstSnapshots.isEmpty else { return [:] }

        do {
            try await sleep(delay)
        } catch {
            return [:]
        }

        var stableSnapshots: [URL: FileStabilitySnapshot] = [:]
        stableSnapshots.reserveCapacity(firstSnapshots.count)
        for url in urls where firstSnapshots[url] != nil {
            do {
                guard let first = firstSnapshots[url],
                      let second = try snapshot(url),
                      first == second
                else { continue }
                stableSnapshots[url] = second
            } catch {
                continue
            }
        }

        var readableSnapshots: [URL: FileStabilitySnapshot] = [:]
        readableSnapshots.reserveCapacity(stableSnapshots.count)
        for url in urls {
            guard let stable = stableSnapshots[url] else { continue }
            do {
                guard try await audioReadable(url) else { continue }
                readableSnapshots[url] = stable
            } catch {
                continue
            }
        }
        return readableSnapshots
    }

    public static func fileSnapshot(_ url: URL) throws -> FileStabilitySnapshot? {
        var metadata = stat()
        guard url.withUnsafeFileSystemRepresentation({ lstat($0, &metadata) }) == 0,
              metadata.st_mode & S_IFMT == S_IFREG
        else { return nil }
        return FileStabilitySnapshot(
            byteCount: metadata.st_size,
            modificationTimeNanoseconds: Int64(metadata.st_mtimespec.tv_sec) * 1_000_000_000
                + Int64(metadata.st_mtimespec.tv_nsec)
        )
    }

    public static func audioReadable(_ url: URL) async throws -> Bool {
        do {
            let asset = AVURLAsset(url: url)
            async let tracks = asset.loadTracks(withMediaType: .audio)
            async let duration = asset.load(.duration)
            async let readable = asset.load(.isReadable)
            let (audioTracks, loadedDuration, isReadable) = try await (tracks, duration, readable)
            let seconds = loadedDuration.seconds
            return isReadable && !audioTracks.isEmpty && seconds.isFinite && seconds > 0
        } catch {
            return false
        }
    }
}
