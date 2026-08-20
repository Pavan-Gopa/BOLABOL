import CryptoKit
import Darwin
import Foundation
import VaniScriptCore

public struct FolderReconciler: Sendable {
    public static let supportedExtensions: Set<String> = ["aac", "aif", "aiff", "flac", "m4a", "mp3", "wav"]

    public init() {}

    public func reconcile(
        folderURL: URL,
        profile: BatchFolderProfile,
        configuration: BatchTranscriptionConfiguration,
        repository: SQLiteBatchJobRepository,
        stabilityProbe: FileStabilityProbe? = nil,
        requireCanonicalNames: Bool = true
    ) async throws -> BatchReconciliationResult {
        let root = folderURL.resolvingSymlinksInPath().standardizedFileURL
        let entries = try Self.entries(in: root, recursive: profile.recursive)
        var candidates: [Candidate] = []
        candidates.reserveCapacity(entries.count)
        for rawURL in entries.sorted(by: { $0.path < $1.path }) {
            let sourceURL = rawURL.standardizedFileURL
            var metadata = stat()
            guard sourceURL.withUnsafeFileSystemRepresentation({ lstat($0, &metadata) }) == 0,
                  metadata.st_mode & S_IFMT == S_IFREG,
                  Self.supportedExtensions.contains(sourceURL.pathExtension.lowercased()),
                  !sourceURL.lastPathComponent.hasPrefix("."),
                  let relativePath = Self.descendantRelativePath(from: root, to: sourceURL)
            else { continue }
            candidates.append(
                Candidate(
                    url: sourceURL,
                    relativePath: relativePath,
                    initialSnapshot: FileStabilitySnapshot(
                        byteCount: metadata.st_size,
                        modificationTimeNanoseconds: Int64(metadata.st_mtimespec.tv_sec) * 1_000_000_000
                            + Int64(metadata.st_mtimespec.tv_nsec)
                    )
                )
            )
        }

        let stableSnapshots: [URL: FileStabilitySnapshot]
        if let stabilityProbe {
            stableSnapshots = await stabilityProbe.stableAudioSnapshots(at: candidates.map(\.url))
            try Task.checkCancellation()
        } else {
            stableSnapshots = [:]
        }

        var enqueued: [BatchJob] = []
        var duplicateCount = 0
        var issues: [BatchReconciliationIssue] = []
        for candidate in candidates {
            let expectedSnapshot: FileStabilitySnapshot?
            if stabilityProbe == nil {
                expectedSnapshot = candidate.initialSnapshot
            } else {
                expectedSnapshot = stableSnapshots[candidate.url]
            }
            guard let expectedSnapshot else { continue }
            let relativeOutputPath: String
            if requireCanonicalNames {
                let parsed = MediaNamingConvention.parse(candidate.url.lastPathComponent, mode: .safeNormalize)
                guard parsed.isAccepted, let canonical = parsed.name else {
                    issues.append(.invalidName(relativePath: candidate.relativePath, violations: parsed.violations))
                    continue
                }
                let outputName = canonical.companionURL(for: candidate.url).lastPathComponent
                let relativeDirectory = (candidate.relativePath as NSString).deletingLastPathComponent
                relativeOutputPath = relativeDirectory.isEmpty ? outputName : relativeDirectory + "/" + outputName
            } else {
                let outputName = candidate.url.deletingPathExtension().lastPathComponent + ".txt"
                let relativeDirectory = (candidate.relativePath as NSString).deletingLastPathComponent
                relativeOutputPath = relativeDirectory.isEmpty ? outputName : relativeDirectory + "/" + outputName
            }

            try Task.checkCancellation()
            let fingerprint: SourceFileFingerprint
            do {
                fingerprint = try Self.fingerprint(candidate.url, expected: expectedSnapshot)
            } catch {
                continue
            }
            let job = BatchJob(
                profileID: profile.id,
                relativeSourcePath: candidate.relativePath,
                relativeOutputPath: relativeOutputPath,
                sourceFingerprint: fingerprint,
                configuration: configuration
            )
            try Task.checkCancellation()
            switch try await repository.enqueue(job) {
            case let .inserted(value): enqueued.append(value)
            case .duplicate: duplicateCount += 1
            case .outputCollision:
                issues.append(.outputCollision(relativePath: candidate.relativePath, existingName: relativeOutputPath))
            }
        }
        return BatchReconciliationResult(enqueued: enqueued, duplicateCount: duplicateCount, issues: issues)

    }

    private struct Candidate: Sendable {
        let url: URL
        let relativePath: String
        let initialSnapshot: FileStabilitySnapshot
    }

    private static func entries(in folderURL: URL, recursive: Bool) throws -> [URL] {
        guard recursive else {
            return try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var entries: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values.isDirectory != true { entries.append(url) }
        }
        return entries
    }

    private static func descendantRelativePath(from root: URL, to child: URL) -> String? {
        let rootComponents = root.pathComponents
        let childComponents = child.pathComponents
        guard childComponents.count > rootComponents.count,
              childComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
        else { return nil }
        return childComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private static func fingerprint(_ url: URL, expected: FileStabilitySnapshot) throws -> SourceFileFingerprint {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard let verified = try FileStabilityProbe.fileSnapshot(url), verified == expected else {
            throw CocoaError(.fileReadUnknown)
        }
        return SourceFileFingerprint(
            byteCount: expected.byteCount,
            modificationTimeNanoseconds: expected.modificationTimeNanoseconds,
            sha256: hash
        )
    }
}
