import CryptoKit
import Foundation
import VaniScriptCore

public struct RemoteModelPackageProgress: Equatable, Sendable {
    public var bytesReceived: Int64
    public var totalBytes: Int64?

    public init(bytesReceived: Int64, totalBytes: Int64?) {
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
    }

    public var fractionCompleted: Double {
        guard let totalBytes, totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(bytesReceived) / Double(totalBytes)))
    }
}

public enum RemoteModelPackageInstallerError: LocalizedError, Equatable, Sendable {
    case sourceNotConfigured
    case invalidURL(String)
    case localSourceInvalid(String)
    case insecureRedirect(String)
    case httpStatus(Int)
    case htmlResponse
    case invalidArchiveMagic
    case archiveStructureInvalid(String)
    case encryptedArchive(String)
    case symlinkEntry(String)
    case unsafeArchivePath(String)
    case duplicateArchivePath(String)
    case archiveSizeMismatch(expected: Int64, actual: Int64)
    case archiveHashMismatch
    case uncompressedSizeMismatch(expected: Int64, actual: Int64)
    case invalidReleaseManifest
    case unexpectedFile(String)
    case missingFile(String)
    case fileSizeMismatch(path: String, expected: Int64, actual: Int64)
    case fileHashMismatch(String)
    case insufficientDiskSpace(required: Int64, available: Int64)
    case extractionFailed(String)
    case destinationInvalid(String)
    case destinationReplacementFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sourceNotConfigured:
            "The remote model package source is not configured."
        case .invalidURL(let value):
            "The remote model package URL is invalid or is not HTTPS: \(value)"
        case .localSourceInvalid(let reason):
            "The local model package source is invalid: \(reason)"
        case .insecureRedirect(let value):
            "The remote model package redirected to a non-HTTPS URL: \(value)"
        case .httpStatus(let status):
            "The remote model package server returned HTTP status \(status)."
        case .htmlResponse:
            "The remote model package response is HTML, not an archive."
        case .invalidArchiveMagic:
            "The remote model package is not a supported ZIP archive."
        case .archiveStructureInvalid(let reason):
            "The remote model package ZIP structure is invalid: \(reason)"
        case .encryptedArchive(let path):
            "Encrypted archive entries are not supported: \(path)"
        case .symlinkEntry(let path):
            "Symlink archive entries are not allowed: \(path)"
        case .unsafeArchivePath(let path):
            "Unsafe archive path rejected: \(path)"
        case .duplicateArchivePath(let path):
            "Duplicate archive path rejected: \(path)"
        case .archiveSizeMismatch(let expected, let actual):
            "Archive size mismatch. Expected \(expected), received \(actual)."
        case .archiveHashMismatch:
            "Archive SHA-256 verification failed."
        case .uncompressedSizeMismatch(let expected, let actual):
            "Uncompressed size mismatch. Expected \(expected), extracted \(actual)."
        case .invalidReleaseManifest:
            "The remote model package release manifest is incomplete or invalid."
        case .unexpectedFile(let path):
            "Archive contains a file outside the trusted allowlist: \(path)"
        case .missingFile(let path):
            "Archive is missing an allowlisted file: \(path)"
        case .fileSizeMismatch(let path, let expected, let actual):
            "File \(path) has \(actual) bytes; expected \(expected)."
        case .fileHashMismatch(let path):
            "File SHA-256 verification failed: \(path)"
        case .insufficientDiskSpace(let required, let available):
            "Insufficient disk space. Required \(required) bytes, available \(available)."
        case .extractionFailed(let reason):
            "Archive extraction failed: \(reason)"
        case .destinationInvalid(let path):
            "The model destination is not a safe directory: \(path)"
        case .destinationReplacementFailed(let reason):
            "Could not atomically replace the model destination: \(reason)"
        }
    }
}

/// Installs an app-owned, integrity-pinned archive. It never accepts arbitrary
/// user URLs: source resolution is limited to release-configured environment
/// keys or test/in-process release overrides, and extraction happens off the
/// final destination until every file has passed validation.
/// FileManager is internally thread-safe; each install uses unique staging
/// paths and immutable release metadata, so concurrent installs do not share
/// mutable model state.
public final class RemoteModelPackageInstaller: @unchecked Sendable {
    private static let destinationInstallCoordinator = ModelDestinationInstallCoordinator()

    private let session: URLSession
    private let fileManager: FileManager
    private let configuredRoot: URL?
    private let environment: [String: String]
    private let availableDiskSpace: @Sendable (URL) -> Int64?

    public init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        configuredRoot: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        availableDiskSpace: (@Sendable (URL) -> Int64?)? = nil
    ) {
        self.session = session
        self.fileManager = fileManager
        self.configuredRoot = configuredRoot
        self.environment = environment
        self.availableDiskSpace = availableDiskSpace ?? Self.defaultAvailableDiskSpace
    }

    public func install(
        release: RemoteModelPackageRelease,
        requiredRelativePaths: [String] = [],
        destination: URL,
        directURL: URL? = nil,
        baseURL: URL? = nil,
        progress: @escaping @Sendable (RemoteModelPackageProgress) -> Void = { _ in }
    ) async throws -> URL {
        await Self.destinationInstallCoordinator.acquire(destination)
        do {
            let result = try await installUnlocked(
                release: release,
                requiredRelativePaths: requiredRelativePaths,
                destination: destination,
                directURL: directURL,
                baseURL: baseURL,
                progress: progress
            )
            await Self.destinationInstallCoordinator.release(destination)
            return result
        } catch {
            await Self.destinationInstallCoordinator.release(destination)
            throw error
        }
    }

    private func installUnlocked(
        release: RemoteModelPackageRelease,
        requiredRelativePaths: [String] = [],
        destination: URL,
        directURL: URL? = nil,
        baseURL: URL? = nil,
        progress: @escaping @Sendable (RemoteModelPackageProgress) -> Void = { _ in }
    ) async throws -> URL {
        try validateRelease(
            release,
            requiredRelativePaths: requiredRelativePaths,
            directURL: directURL,
            baseURL: baseURL
        )
        let sourceURL = try resolveSourceURL(
            release: release,
            directURL: directURL,
            baseURL: baseURL
        )
        try validateSourceURL(sourceURL)

        let canonicalDestination = try canonicalDestination(for: destination)
        let parent = canonicalDestination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        if isSymbolicLink(canonicalDestination) {
            throw RemoteModelPackageInstallerError.destinationInvalid(canonicalDestination.path)
        }

        let compressedSize = release.expectedCompressedSizeBytes ?? 0
        let uncompressedSize = release.expectedUncompressedSizeBytes ?? 0
        let requiredDisk = compressedSize + uncompressedSize + uncompressedSize
        if let available = availableDiskSpace(parent), available < requiredDisk {
            throw RemoteModelPackageInstallerError.insufficientDiskSpace(
                required: requiredDisk,
                available: available
            )
        }

        let stagingRoot = parent.appendingPathComponent(
            ".vaniscript-remote-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        let archiveURL = stagingRoot.appendingPathComponent("package.archive")
        let downloadedBytes: Int64
        if sourceURL.scheme?.lowercased() == "file" {
            downloadedBytes = try copyLocalArchive(
                from: sourceURL,
                to: archiveURL,
                expectedBytes: compressedSize,
                progress: progress
            )
            try validateArchiveMagic(at: archiveURL)
        } else {
            let (response, bytes) = try await downloadArchive(
                from: sourceURL,
                to: archiveURL,
                expectedBytes: compressedSize,
                progress: progress
            )
            try validateArchiveResponse(response, archiveURL: archiveURL)
            downloadedBytes = bytes
        }

        let actualArchiveSize = try fileSize(archiveURL)
        guard actualArchiveSize == compressedSize else {
            throw RemoteModelPackageInstallerError.archiveSizeMismatch(
                expected: compressedSize,
                actual: actualArchiveSize
            )
        }
        guard downloadedBytes == actualArchiveSize else {
            throw RemoteModelPackageInstallerError.archiveSizeMismatch(
                expected: actualArchiveSize,
                actual: downloadedBytes
            )
        }
        progress(
            RemoteModelPackageProgress(
                bytesReceived: actualArchiveSize,
                totalBytes: compressedSize
            )
        )
        let archiveHash = try sha256(archiveURL)
        guard archiveHash.caseInsensitiveCompare(release.expectedArchiveSHA256 ?? "") == .orderedSame else {
            throw RemoteModelPackageInstallerError.archiveHashMismatch
        }
        try Task.checkCancellation()

        let entries = try inspectZipArchive(at: archiveURL)
        let archiveFileEntries = entries.filter { !$0.isDirectory }
        let archiveUncompressedSize = archiveFileEntries.reduce(Int64(0)) { $0 + $1.uncompressedSize }
        guard archiveUncompressedSize == uncompressedSize else {
            throw RemoteModelPackageInstallerError.uncompressedSizeMismatch(
                expected: uncompressedSize,
                actual: archiveUncompressedSize
            )
        }
        try validateArchiveEntries(
            entries,
            release: release,
            requiredRelativePaths: requiredRelativePaths
        )

        let extractedRoot = stagingRoot.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractedRoot, withIntermediateDirectories: true)
        try extractArchive(archiveURL, to: extractedRoot)
        try Task.checkCancellation()
        try validateExtractedFiles(
            at: extractedRoot,
            release: release,
            requiredRelativePaths: requiredRelativePaths
        )

        let manifest = RemoteModelPackageInstallationManifest(
            packageID: release.packageID,
            layoutVersion: release.layoutVersion,
            archiveSHA256: archiveHash,
            archiveSizeBytes: actualArchiveSize,
            uncompressedSizeBytes: archiveUncompressedSize,
            files: release.allowlistedFiles
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(
            to: LocalASRPresencePolicy.installationManifestURL(at: extractedRoot),
            options: [.atomic]
        )

        return try replaceDestination(extractedRoot, with: canonicalDestination)
    }

    private func validateRelease(
        _ release: RemoteModelPackageRelease,
        requiredRelativePaths: [String],
        directURL: URL?,
        baseURL: URL?
    ) throws {
        let hasSourceOverride = directURL != nil || baseURL != nil
        guard !release.packageID.isEmpty,
              !release.layoutVersion.isEmpty,
              (hasSourceOverride || release.isBound),
              isSHA256(release.expectedArchiveSHA256),
              (release.expectedCompressedSizeBytes ?? 0) > 0,
              (release.expectedUncompressedSizeBytes ?? 0) > 0,
              !release.allowlistedFiles.isEmpty
        else {
            throw RemoteModelPackageInstallerError.invalidReleaseManifest
        }

        var seen = Set<String>()
        for file in release.allowlistedFiles {
            guard let path = NativeModelPathPolicy.normalizedRelativePath(file.relativePath),
                  path == file.relativePath,
                  let byteCount = file.expectedByteCount,
                  byteCount >= 0,
                  isSHA256(file.expectedSHA256),
                  seen.insert(path).inserted
            else {
                throw RemoteModelPackageInstallerError.invalidReleaseManifest
            }
        }
        for requiredPath in requiredRelativePaths {
            guard let normalized = NativeModelPathPolicy.normalizedRelativePath(requiredPath) else {
                throw RemoteModelPackageInstallerError.unsafeArchivePath(requiredPath)
            }
            guard release.allowlistedFiles.contains(where: { file in
                guard let filePath = NativeModelPathPolicy.normalizedRelativePath(file.relativePath) else { return false }
                return filePath == normalized || filePath.hasPrefix(normalized + "/")
            }) else {
                throw RemoteModelPackageInstallerError.missingFile(normalized)
            }
        }
    }

    private func validateSourceURL(_ url: URL) throws {
        switch url.scheme?.lowercased() {
        case "https":
            try validateHTTPS(url)
        case "file":
            try validateLocalArchiveSource(url)
        default:
            throw RemoteModelPackageInstallerError.invalidURL(url.absoluteString)
        }
    }

    private func validateLocalArchiveSource(_ url: URL) throws {
        let path = url.path
        guard !path.isEmpty else {
            throw RemoteModelPackageInstallerError.localSourceInvalid("missing path")
        }
        guard !isSymbolicLink(url) else {
            throw RemoteModelPackageInstallerError.localSourceInvalid("symbolic link: \(path)")
        }
        guard fileManager.fileExists(atPath: path) else {
            throw RemoteModelPackageInstallerError.localSourceInvalid("missing file: \(path)")
        }
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
            throw RemoteModelPackageInstallerError.localSourceInvalid("unreadable file: \(path)")
        }
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw RemoteModelPackageInstallerError.localSourceInvalid("directory or non-regular file: \(path)")
        }
    }

    
    private func resolveSourceURL(
        release: RemoteModelPackageRelease,
        directURL: URL?,
        baseURL: URL?
    ) throws -> URL {
        if let directURL { return directURL }
        if let directKey = release.directURLOverrideEnvironmentKey,
           let raw = environment[directKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }

        let resolvedBase: URL?
        if let baseURL {
            resolvedBase = baseURL
        } else if let baseKey = release.baseURLEnvironmentKey,
                  let rawBase = environment[baseKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawBase.isEmpty {
            resolvedBase = URL(string: rawBase)
        } else {
            resolvedBase = nil
        }

        guard let resolvedBase,
              let relativePath = release.relativeArchivePath,
              let normalized = NativeModelPathPolicy.normalizedRelativePath(relativePath)
        else {
            throw RemoteModelPackageInstallerError.sourceNotConfigured
        }
        return resolvedBase.appendingPathComponent(normalized)
    }

    private func downloadArchive(
        from sourceURL: URL,
        to destination: URL,
        expectedBytes: Int64,
        progress: @escaping @Sendable (RemoteModelPackageProgress) -> Void
    ) async throws -> (HTTPURLResponse, Int64) {
        let delegate = RemoteArchiveDownloadDelegate { received, expected in
            let total = expected > 0 ? expected : expectedBytes > 0 ? expectedBytes : nil
            progress(RemoteModelPackageProgress(bytesReceived: received, totalBytes: total))
        }
        let request = URLRequest(url: sourceURL)
        let (temporaryURL, response) = try await session.download(for: request, delegate: delegate)
        guard let httpResponse = response as? HTTPURLResponse else {
            try? fileManager.removeItem(at: temporaryURL)
            throw RemoteModelPackageInstallerError.httpStatus(-1)
        }
        let size = try fileSize(temporaryURL)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return (httpResponse, size)
    }

    private func copyLocalArchive(
        from sourceURL: URL,
        to destination: URL,
        expectedBytes: Int64,
        progress: @escaping @Sendable (RemoteModelPackageProgress) -> Void
    ) throws -> Int64 {
        guard let input = InputStream(url: sourceURL),
              let output = OutputStream(url: destination, append: false)
        else {
            throw RemoteModelPackageInstallerError.extractionFailed("could not stage local archive")
        }

        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }

        let totalBytes = expectedBytes > 0 ? expectedBytes : nil
        progress(RemoteModelPackageProgress(bytesReceived: 0, totalBytes: totalBytes))

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var copiedBytes: Int64 = 0
        while true {
            try Task.checkCancellation()
            let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
                input.read(
                    rawBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    maxLength: rawBuffer.count
                )
            }
            guard bytesRead >= 0 else {
                throw RemoteModelPackageInstallerError.extractionFailed("could not read local archive")
            }
            if bytesRead == 0 {
                break
            }

            var offset = 0
            while offset < bytesRead {
                try Task.checkCancellation()
                let bytesWritten = buffer.withUnsafeBytes { rawBuffer in
                    output.write(
                        rawBuffer.bindMemory(to: UInt8.self).baseAddress!.advanced(by: offset),
                        maxLength: bytesRead - offset
                    )
                }
                guard bytesWritten > 0 else {
                    throw RemoteModelPackageInstallerError.extractionFailed("could not stage local archive")
                }
                offset += bytesWritten
                copiedBytes += Int64(bytesWritten)
                progress(
                    RemoteModelPackageProgress(
                        bytesReceived: copiedBytes,
                        totalBytes: totalBytes
                    )
                )
            }
        }
        try Task.checkCancellation()
        return copiedBytes
    }

    private func validateArchiveResponse(_ response: HTTPURLResponse, archiveURL: URL) throws {
        guard (200...299).contains(response.statusCode) else {
            throw RemoteModelPackageInstallerError.httpStatus(response.statusCode)
        }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("text/html") || contentType.contains("application/xhtml") {
            throw RemoteModelPackageInstallerError.htmlResponse
        }
        try validateArchiveMagic(at: archiveURL)
    }
    
    private func validateArchiveMagic(at archiveURL: URL) throws {
        let magic = try Data(contentsOf: archiveURL, options: [.mappedIfSafe]).prefix(4)
        guard isZipMagic(magic) else {
            throw RemoteModelPackageInstallerError.invalidArchiveMagic
        }
    }

    private struct ZipEntry: Sendable {
        let path: String
        let isDirectory: Bool
        let isSymlink: Bool
        let encrypted: Bool
        let uncompressedSize: Int64
    }

    private func inspectZipArchive(at archiveURL: URL) throws -> [ZipEntry] {
        let archiveSize = try fileSize(archiveURL)
        guard archiveSize >= 22 else {
            throw RemoteModelPackageInstallerError.archiveStructureInvalid("archive is too small")
        }
        let handle = try FileHandle(forReadingFrom: archiveURL)
        defer { try? handle.close() }

        let tailLength = min(archiveSize, 65_557)
        try handle.seek(toOffset: UInt64(archiveSize - tailLength))
        guard let tail = try handle.read(upToCount: Int(tailLength)) else {
            throw RemoteModelPackageInstallerError.archiveStructureInvalid("missing end record")
        }
        let eocdSignature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        guard let eocdIndex = lastSignature(eocdSignature, in: tail), eocdIndex + 22 <= tail.count else {
            throw RemoteModelPackageInstallerError.archiveStructureInvalid("missing end record")
        }
        let eocd = Data(tail[eocdIndex...])
        guard uint16(eocd, offset: 4) == 0,
              uint16(eocd, offset: 6) == 0,
              uint32(eocd, offset: 12) != UInt32.max,
              uint32(eocd, offset: 16) != UInt32.max
        else {
            throw RemoteModelPackageInstallerError.archiveStructureInvalid("multi-disk or ZIP64 archive")
        }

        let centralSize = Int64(uint32(eocd, offset: 12))
        let centralOffset = Int64(uint32(eocd, offset: 16))
        guard centralSize <= 64 * 1024 * 1024,
              centralOffset >= 0,
              centralOffset + centralSize <= archiveSize
        else {
            throw RemoteModelPackageInstallerError.archiveStructureInvalid("central directory bounds")
        }

        try handle.seek(toOffset: UInt64(centralOffset))
        guard let central = try handle.read(upToCount: Int(centralSize)), Int64(central.count) == centralSize else {
            throw RemoteModelPackageInstallerError.archiveStructureInvalid("truncated central directory")
        }

        var entries: [ZipEntry] = []
        var offset = 0
        var normalizedPaths = Set<String>()
        while offset < central.count {
            guard offset + 46 <= central.count,
                  uint32(central, offset: offset) == 0x0201_4b50
            else {
                throw RemoteModelPackageInstallerError.archiveStructureInvalid("invalid central directory record")
            }

            let flags = uint16(central, offset: offset + 8)
            let uncompressedSize = Int64(uint32(central, offset: offset + 24))
            let nameLength = Int(uint16(central, offset: offset + 28))
            let extraLength = Int(uint16(central, offset: offset + 30))
            let commentLength = Int(uint16(central, offset: offset + 32))
            let recordLength = 46 + nameLength + extraLength + commentLength
            guard offset + recordLength <= central.count else {
                throw RemoteModelPackageInstallerError.archiveStructureInvalid("truncated central directory record")
            }

            let nameData = central.subdata(in: (offset + 46)..<(offset + 46 + nameLength))
            guard let rawPath = String(data: nameData, encoding: .utf8),
                  let normalizedPath = NativeModelPathPolicy.normalizedRelativePath(rawPath)
            else {
                throw RemoteModelPackageInstallerError.unsafeArchivePath("invalid UTF-8 path")
            }
            guard normalizedPaths.insert(normalizedPath).inserted else {
                throw RemoteModelPackageInstallerError.duplicateArchivePath(normalizedPath)
            }

            let externalAttributes = uint32(central, offset: offset + 38)
            let unixType = (externalAttributes >> 16) & 0xf000
            let isSymlink = unixType == 0xa000
            if isSymlink {
                throw RemoteModelPackageInstallerError.symlinkEntry(normalizedPath)
            }
            let isDirectory = rawPath.hasSuffix("/") || unixType == 0x4000
            if flags & 0x0001 != 0 {
                throw RemoteModelPackageInstallerError.encryptedArchive(normalizedPath)
            }

            entries.append(
                ZipEntry(
                    path: normalizedPath,
                    isDirectory: isDirectory,
                    isSymlink: isSymlink,
                    encrypted: flags & 0x0001 != 0,
                    uncompressedSize: uncompressedSize
                )
            )
            offset += recordLength
        }

        guard !entries.isEmpty else {
            throw RemoteModelPackageInstallerError.archiveStructureInvalid("empty archive")
        }
        return entries
    }

    private func validateArchiveEntries(
        _ entries: [ZipEntry],
        release: RemoteModelPackageRelease,
        requiredRelativePaths: [String]
    ) throws {
        let allowlisted = Set(release.allowlistedFiles.compactMap {
            NativeModelPathPolicy.normalizedRelativePath($0.relativePath)
        })
        let fileEntries = Set(entries.filter { !$0.isDirectory }.map(\.path))
        for entry in entries {
            if entry.isDirectory {
                let isTrustedParent = allowlisted.contains {
                    $0.hasPrefix(entry.path + "/")
                }
                guard isTrustedParent else {
                    throw RemoteModelPackageInstallerError.unexpectedFile(entry.path)
                }
            } else {
                guard allowlisted.contains(entry.path) else {
                    throw RemoteModelPackageInstallerError.unexpectedFile(entry.path)
                }
            }
        }
        for path in allowlisted {
            guard fileEntries.contains(path) else {
                throw RemoteModelPackageInstallerError.missingFile(path)
            }
        }
        for requiredPath in requiredRelativePaths {
            guard let normalized = NativeModelPathPolicy.normalizedRelativePath(requiredPath),
                  fileEntries.contains(where: { $0 == normalized || $0.hasPrefix(normalized + "/") })
            else {
                throw RemoteModelPackageInstallerError.missingFile(requiredPath)
            }
        }
    }

    private func extractArchive(_ archiveURL: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", "-o", archiveURL.path, "-d", destination.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw RemoteModelPackageInstallerError.extractionFailed(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let detail = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "unzip exited with status \(process.terminationStatus)"
            throw RemoteModelPackageInstallerError.extractionFailed(detail)
        }
    }

    private func validateExtractedFiles(
        at root: URL,
        release: RemoteModelPackageRelease,
        requiredRelativePaths: [String]
    ) throws {
        guard !containsSymbolicLink(at: root) else {
            throw RemoteModelPackageInstallerError.symlinkEntry(root.path)
        }
        let expected = Dictionary(uniqueKeysWithValues: release.allowlistedFiles.compactMap { file -> (String, RemoteModelPackageFile)? in
            guard let path = NativeModelPathPolicy.normalizedRelativePath(file.relativePath) else { return nil }
            return (path, file)
        })
        for (path, file) in expected {
            let fileURL = root.appendingPathComponent(path)
            guard isCanonicalChild(fileURL, of: root),
                  let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular
            else {
                throw RemoteModelPackageInstallerError.missingFile(path)
            }
            let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard let expectedSize = file.expectedByteCount, actualSize == expectedSize else {
                throw RemoteModelPackageInstallerError.fileSizeMismatch(
                    path: path,
                    expected: file.expectedByteCount ?? -1,
                    actual: actualSize
                )
            }
            guard let expectedHash = file.expectedSHA256 else {
                throw RemoteModelPackageInstallerError.fileHashMismatch(path)
            }
            let actualHash = try sha256(fileURL)
            guard actualHash.caseInsensitiveCompare(expectedHash) == .orderedSame else {
                throw RemoteModelPackageInstallerError.fileHashMismatch(path)
            }
        }

        let actualFiles = extractedRegularFiles(at: root)
        guard actualFiles == Set(expected.keys) else {
            if let extra = actualFiles.subtracting(expected.keys).sorted().first {
                throw RemoteModelPackageInstallerError.unexpectedFile(extra)
            }
            if let missing = Set(expected.keys).subtracting(actualFiles).sorted().first {
                throw RemoteModelPackageInstallerError.missingFile(missing)
            }
            throw RemoteModelPackageInstallerError.extractionFailed("extracted file set mismatch")
        }

        for requiredPath in requiredRelativePaths {
            guard let normalized = NativeModelPathPolicy.normalizedRelativePath(requiredPath) else {
                throw RemoteModelPackageInstallerError.unsafeArchivePath(requiredPath)
            }
            let itemURL = root.appendingPathComponent(normalized, isDirectory: normalized.hasSuffix(".mlmodelc"))
            guard isCanonicalChild(itemURL, of: root),
                  fileManager.fileExists(atPath: itemURL.path)
            else {
                throw RemoteModelPackageInstallerError.missingFile(normalized)
            }
            if normalized.hasSuffix(".mlmodelc") {
                guard isDirectory(itemURL) else {
                    throw RemoteModelPackageInstallerError.missingFile(normalized)
                }
            } else {
                guard !isDirectory(itemURL) else {
                    throw RemoteModelPackageInstallerError.missingFile(normalized)
                }
            }
        }
    }

    private func replaceDestination(_ staged: URL, with destination: URL) throws -> URL {
        let parent = destination.deletingLastPathComponent()
        let backup = parent.appendingPathComponent(
            ".vaniscript-remote-backup-\(UUID().uuidString)",
            isDirectory: true
        )
        let hadDestination = fileManager.fileExists(atPath: destination.path)
        do {
            if hadDestination {
                try fileManager.moveItem(at: destination, to: backup)
            }
            try fileManager.moveItem(at: staged, to: destination)
            if hadDestination {
                try? fileManager.removeItem(at: backup)
            }
            return destination
        } catch {
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            if hadDestination, fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw RemoteModelPackageInstallerError.destinationReplacementFailed(error.localizedDescription)
        }
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func canonicalDestination(for destination: URL) throws -> URL {
        let root = SharedModelsRoot.resolve(
            configuredRoot: configuredRoot,
            environment: environment,
            fileManager: fileManager
        )
        guard let canonical = SharedModelsRoot.canonicalRootRelativeURL(
            candidate: destination,
            root: root,
            fileManager: fileManager
        ) else {
            throw RemoteModelPackageInstallerError.destinationInvalid(destination.path)
        }
        return canonical
    }

    private func sha256(_ url: URL) throws -> String {
        guard let stream = InputStream(url: url) else {
            throw RemoteModelPackageInstallerError.archiveStructureInvalid("cannot read \(url.path)")
        }
        stream.open()
        defer { stream.close() }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                stream.read(rawBuffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: rawBuffer.count)
            }
            guard count >= 0 else {
                throw RemoteModelPackageInstallerError.archiveStructureInvalid("hash read failed")
            }
            if count == 0 { break }
            hasher.update(data: Data(buffer.prefix(count)))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func extractedRegularFiles(at root: URL) -> Set<String> {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [], options: []) else {
            return []
        }
        let rootPath = root.standardizedFileURL.path.hasSuffix("/")
            ? root.standardizedFileURL.path
            : root.standardizedFileURL.path + "/"
        var result = Set<String>()
        for case let itemURL as URL in enumerator {
            if itemURL.lastPathComponent == LocalASRPresencePolicy.remoteManifestFilename {
                continue
            }
            guard !isSymbolicLink(itemURL),
                  let attributes = try? fileManager.attributesOfItem(atPath: itemURL.path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular,
                  itemURL.standardizedFileURL.path.hasPrefix(rootPath)
            else {
                continue
            }
            let relative = String(itemURL.standardizedFileURL.path.dropFirst(rootPath.count))
            if let normalized = NativeModelPathPolicy.normalizedRelativePath(relative) {
                result.insert(normalized)
            }
        }
        return result
    }

    private func containsSymbolicLink(at root: URL) -> Bool {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [], options: []) else {
            return false
        }
        for case let itemURL as URL in enumerator where isSymbolicLink(itemURL) {
            return true
        }
        return false
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
        return (attributes[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func isCanonicalChild(_ url: URL, of root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let canonicalPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return canonicalPath.hasPrefix(prefix)
    }

    private func validateHTTPS(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            throw RemoteModelPackageInstallerError.invalidURL(url.absoluteString)
        }
    }

    private func isSHA256(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.count == 64 && normalized.allSatisfy(\.isHexDigit)
    }

    private static func defaultAvailableDiskSpace(_ url: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init)
    }

    private func isZipMagic(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let bytes = Array(data.prefix(4))
        return bytes == [0x50, 0x4b, 0x03, 0x04]
            || bytes == [0x50, 0x4b, 0x05, 0x06]
            || bytes == [0x50, 0x4b, 0x07, 0x08]
    }

    private func lastSignature(_ signature: [UInt8], in data: Data) -> Int? {
        guard data.count >= signature.count else { return nil }
        for index in stride(from: data.count - signature.count, through: 0, by: -1) {
            if Array(data[index..<(index + signature.count)]) == signature {
                return index
            }
        }
        return nil
    }

    private func uint16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func uint32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

actor ModelDestinationInstallCoordinator {
    private var lockedKeys = Set<String>()
    private var waiters = [String: [CheckedContinuation<Void, Never>]]()

    func acquire(_ destination: URL) async {
        let key = destination.standardizedFileURL.path
        if lockedKeys.insert(key).inserted {
            return
        }

        await withCheckedContinuation { continuation in
            waiters[key, default: []].append(continuation)
        }
    }

    func release(_ destination: URL) {
        let key = destination.standardizedFileURL.path
        guard var pending = waiters[key], !pending.isEmpty else {
            lockedKeys.remove(key)
            waiters[key] = nil
            return
        }

        let next = pending.removeFirst()
        waiters[key] = pending.isEmpty ? nil : pending
        next.resume()
    }
}

private final class RemoteArchiveDownloadDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    private let onProgress: @Sendable (Int64, Int64) -> Void

    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The async URLSession API returns the temporary file directly.
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard request.url?.scheme?.lowercased() == "https" else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
