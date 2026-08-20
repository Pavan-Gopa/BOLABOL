import CryptoKit
import Darwin
import Foundation
import VaniScriptCore

public struct AtomicCompanionWriter: Sendable {
    public static let temporaryPrefix = ".vaniscript-companion-"

    private let beforeCommit: @Sendable () -> Void
    private let createTemporary: @Sendable (URL) -> Int32
    private let synchronize: @Sendable (Int32) -> Int32

    public init() {
        self.init(beforeCommit: {}, createTemporary: nil, synchronize: nil)
    }

    init(
        beforeCommit: @escaping @Sendable () -> Void = {},
        createTemporary: (@Sendable (URL) -> Int32)? = nil,
        synchronize: (@Sendable (Int32) -> Int32)? = nil
    ) {
        self.beforeCommit = beforeCommit
        self.createTemporary = createTemporary ?? { url in
            Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        }
        self.synchronize = synchronize ?? Darwin.fsync
    }

    public static func fingerprint(sourceURL: URL) throws -> SourceFileFingerprint {
        var metadata = stat()
        guard sourceURL.withUnsafeFileSystemRepresentation({ lstat($0, &metadata) }) == 0 else {
            throw AtomicCompanionWriterError.sourceUnavailable
        }
        let data: Data
        do {
            data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        } catch {
            throw AtomicCompanionWriterError.sourceUnavailable
        }
        var verifiedMetadata = stat()
        guard sourceURL.withUnsafeFileSystemRepresentation({ lstat($0, &verifiedMetadata) }) == 0,
              metadata.st_size == verifiedMetadata.st_size,
              metadata.st_mtimespec.tv_sec == verifiedMetadata.st_mtimespec.tv_sec,
              metadata.st_mtimespec.tv_nsec == verifiedMetadata.st_mtimespec.tv_nsec
        else {
            throw AtomicCompanionWriterError.sourceChanged
        }
        return SourceFileFingerprint(
            byteCount: metadata.st_size,
            modificationTimeNanoseconds: Int64(metadata.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(metadata.st_mtimespec.tv_nsec),
            sha256: sha256(data)
        )
    }

    public func write(
        _ data: Data,
        request: CompanionWriteRequest
    ) throws -> CompanionWriteResult {
        let directory = request.outputURL.deletingLastPathComponent()
        let outputName = request.outputURL.lastPathComponent
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw Self.mapFilesystemError(error, fallback: .directoryReadFailed)
        }

        let ownedPrefix = Self.temporaryPrefix + outputName + "."
        for entry in entries where entry.lastPathComponent.hasPrefix(ownedPrefix) {
            try? FileManager.default.removeItem(at: entry)
        }
        if let collision = entries.first(where: {
            $0.lastPathComponent.caseInsensitiveCompare(outputName) == .orderedSame &&
            $0.lastPathComponent != outputName
        }) {
            throw AtomicCompanionWriterError.caseInsensitiveCollision(existingName: collision.lastPathComponent)
        }

        var initialMetadata = stat()
        let initialInspection = request.outputURL.withUnsafeFileSystemRepresentation {
            lstat($0, &initialMetadata)
        }
        let disposition: CompanionWriteDisposition
        let authorizedOutput: FileIdentity?
        if initialInspection == 0 {
            guard Self.isRegularFile(initialMetadata),
                  let known = request.knownGeneratedOutput
            else {
                throw AtomicCompanionWriterError.existingOutputNotKnownGenerated
            }
            authorizedOutput = try Self.authorizeKnownGeneratedOutput(
                at: request.outputURL,
                known: known,
                requiredIdentity: Self.identity(of: initialMetadata)
            )
            disposition = .replacedGenerated
        } else if errno == ENOENT {
            authorizedOutput = nil
            disposition = .created
        } else if errno == EACCES || errno == EPERM {
            throw AtomicCompanionWriterError.permissionDenied
        } else {
            throw AtomicCompanionWriterError.directoryReadFailed
        }

        guard try Self.fingerprint(sourceURL: request.sourceURL) == request.expectedSourceFingerprint else {
            throw AtomicCompanionWriterError.sourceChanged
        }

        let tempURL = directory.appendingPathComponent(ownedPrefix + UUID().uuidString)
        let descriptor = createTemporary(tempURL)
        guard descriptor >= 0 else {
            throw Self.posixError(errno, operation: .create)
        }
        var descriptorIsOpen = true
        defer {
            if descriptorIsOpen { _ = Darwin.close(descriptor) }
            try? FileManager.default.removeItem(at: tempURL)
        }

        var writeError: AtomicCompanionWriterError?
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 {
                    writeError = Self.posixError(errno, operation: .write)
                    return
                }
                offset += count
            }
        }
        if let writeError { throw writeError }
        guard synchronize(descriptor) == 0 else {
            throw Self.posixError(errno, operation: .sync)
        }
        guard Darwin.close(descriptor) == 0 else {
            descriptorIsOpen = false
            throw Self.posixError(errno, operation: .close)
        }
        descriptorIsOpen = false

        beforeCommit()
        guard try Self.fingerprint(sourceURL: request.sourceURL) == request.expectedSourceFingerprint else {
            throw AtomicCompanionWriterError.sourceChanged
        }
        if let authorizedOutput, let known = request.knownGeneratedOutput {
            _ = try Self.authorizeKnownGeneratedOutput(
                at: request.outputURL,
                known: known,
                requiredIdentity: authorizedOutput
            )
            guard Darwin.rename(tempURL.path, request.outputURL.path) == 0 else {
                throw Self.posixError(errno, operation: .rename)
            }
        } else {
            guard Darwin.renamex_np(tempURL.path, request.outputURL.path, UInt32(RENAME_EXCL)) == 0 else {
                if errno == EEXIST {
                    throw AtomicCompanionWriterError.existingOutputNotKnownGenerated
                }
                throw Self.posixError(errno, operation: .rename)
            }
        }

        return CompanionWriteResult(
            outputURL: request.outputURL,
            outputFingerprint: GeneratedOutputFingerprint(sha256: Self.sha256(data)),
            disposition: disposition
        )
    }

    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private static func identity(of metadata: stat) -> FileIdentity {
        FileIdentity(device: metadata.st_dev, inode: metadata.st_ino)
    }

    private static func sameVersion(_ lhs: stat, _ rhs: stat) -> Bool {
        identity(of: lhs) == identity(of: rhs) &&
        lhs.st_size == rhs.st_size &&
        lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec &&
        lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec &&
        lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec &&
        lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private static func isRegularFile(_ metadata: stat) -> Bool {
        metadata.st_mode & S_IFMT == S_IFREG
    }

    private static func authorizeKnownGeneratedOutput(
        at url: URL,
        known: GeneratedOutputFingerprint,
        requiredIdentity: FileIdentity
    ) throws -> FileIdentity {
        var metadata = stat()
        guard url.withUnsafeFileSystemRepresentation({ lstat($0, &metadata) }) == 0,
              isRegularFile(metadata),
              identity(of: metadata) == requiredIdentity
        else {
            throw AtomicCompanionWriterError.existingOutputModified
        }
        let existing: Data
        do {
            existing = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw mapFilesystemError(error, fallback: .existingOutputModified)
        }
        var verifiedMetadata = stat()
        guard url.withUnsafeFileSystemRepresentation({ lstat($0, &verifiedMetadata) }) == 0,
              isRegularFile(verifiedMetadata),
              sameVersion(metadata, verifiedMetadata),
              identity(of: verifiedMetadata) == requiredIdentity,
              sha256(existing).caseInsensitiveCompare(known.sha256) == .orderedSame
        else {
            throw AtomicCompanionWriterError.existingOutputModified
        }
        return requiredIdentity
    }

    private enum POSIXOperation { case create, write, sync, close, rename }

    private static func posixError(_ code: Int32, operation: POSIXOperation) -> AtomicCompanionWriterError {
        if code == EACCES || code == EPERM { return .permissionDenied }
        switch operation {
        case .create: return .temporaryCreateFailed(code: code)
        case .write: return .writeFailed(code: code)
        case .sync: return .syncFailed(code: code)
        case .close: return .closeFailed(code: code)
        case .rename: return .renameFailed(code: code)
        }
    }

    private static func mapFilesystemError(
        _ error: Error,
        fallback: AtomicCompanionWriterError
    ) -> AtomicCompanionWriterError {
        let code = (error as NSError).code
        if code == NSFileWriteNoPermissionError || code == NSFileReadNoPermissionError {
            return .permissionDenied
        }
        return fallback
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
