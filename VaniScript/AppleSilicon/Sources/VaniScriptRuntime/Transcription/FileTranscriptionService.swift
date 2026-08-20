import CryptoKit
import Darwin
import Foundation
import VaniScriptCore

public struct FileTranscriptionRequest: Sendable, Equatable {
    public let sourceURL: URL
    public let chunks: [FileTranscriptionChunk]
    public let workspaceID: String
    public let priority: TranscriptionPriority

    public init(
        sourceURL: URL,
        chunks: [FileTranscriptionChunk],
        workspaceID: String,
        priority: TranscriptionPriority
    ) {
        self.sourceURL = sourceURL
        self.chunks = chunks
        self.workspaceID = workspaceID
        self.priority = priority
    }
}

public struct FileTranscriptionResult: Sendable, Equatable {
    public let chunks: [ChunkTranscription]

    public var text: String { chunks.map(\.text).joined(separator: "\n") }
    public var cues: [TranscriptCue] { chunks.flatMap(\.cues) }

    public init(chunks: [ChunkTranscription]) {
        self.chunks = chunks
    }
}

public enum FileTranscriptionProgress: Sendable, Equatable {
    case started(totalChunks: Int)
    case transcribing(index: Int, totalChunks: Int)
    case completed(index: Int, totalChunks: Int)
}

public struct FileTranscriptionCheckpoint: Sendable, Equatable {
    public let completedChunks: [ChunkTranscription]

    public init(completedChunks: [ChunkTranscription]) {
        self.completedChunks = completedChunks
    }
}

public struct TranscriptionWorkspaceOwner: @unchecked Sendable {
    public let rootURL: URL
    private let fileManager: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    public func workspace(for id: String) throws -> URL {
        guard !id.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let component = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        let url = try directChildURL(component: component)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let result = url.withUnsafeFileSystemRepresentation { path in
            path.map { mkdir($0, S_IRWXU) } ?? -1
        }
        guard result == 0 else {
            if errno == EEXIST { throw CocoaError(.fileWriteFileExists) }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return url
    }

    public func remove(_ workspaceURL: URL) throws {
        _ = try directChildURL(component: workspaceURL.lastPathComponent, candidate: workspaceURL)
        if fileManager.fileExists(atPath: workspaceURL.path) { try fileManager.removeItem(at: workspaceURL) }
    }

    private func directChildURL(component: String, candidate: URL? = nil) throws -> URL {
        guard component.utf8.count == 64,
              component.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) })
        else { throw CocoaError(.fileWriteInvalidFileName) }
        let url = candidate ?? rootURL.appendingPathComponent(component, isDirectory: true)
        guard url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
                == rootURL.resolvingSymlinksInPath().standardizedFileURL
        else { throw CocoaError(.fileWriteInvalidFileName) }
        return url
    }
}

public struct FileTranscriptionService: Sendable {
    public typealias Progress = @Sendable (FileTranscriptionProgress) async throws -> Void
    public typealias Checkpoint = @Sendable (FileTranscriptionCheckpoint) async throws -> Void

    private let scheduler: TranscriptionScheduler
    private let chunkProcessor: AudioChunkProcessingService
    private let workspaceOwner: TranscriptionWorkspaceOwner

    public init(
        scheduler: TranscriptionScheduler,
        chunkProcessor: AudioChunkProcessingService,
        workspaceOwner: TranscriptionWorkspaceOwner
    ) {
        self.scheduler = scheduler
        self.chunkProcessor = chunkProcessor
        self.workspaceOwner = workspaceOwner
    }

    public func transcribe(
        _ request: FileTranscriptionRequest,
        progress: @escaping Progress = { _ in },
        checkpoint: @escaping Checkpoint = { _ in }
    ) async throws -> FileTranscriptionResult {
        try validate(request)
        let workspaceURL = try workspaceOwner.workspace(for: request.workspaceID)
        do {
            let result = try await scheduler.run(priority: request.priority) {
                try await progress(.started(totalChunks: request.chunks.count))
                var completed: [ChunkTranscription] = []
                completed.reserveCapacity(request.chunks.count)
                for chunk in request.chunks {
                    try Task.checkCancellation()
                    try await progress(.transcribing(index: chunk.index, totalChunks: request.chunks.count))
                    let result = try await chunkProcessor.process(
                        sourceURL: request.sourceURL,
                        chunk: chunk,
                        workspaceURL: workspaceURL
                    )
                    completed.append(result)
                    try await checkpoint(FileTranscriptionCheckpoint(completedChunks: completed))
                    try await progress(.completed(index: chunk.index, totalChunks: request.chunks.count))
                }
                return FileTranscriptionResult(chunks: completed)
            }
            try workspaceOwner.remove(workspaceURL)
            return result
        } catch {
            try? workspaceOwner.remove(workspaceURL)
            throw error
        }
    }

    private func validate(_ request: FileTranscriptionRequest) throws {
        guard request.sourceURL.isFileURL, !request.workspaceID.isEmpty else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        var previousEnd = 0.0
        var previousIndex: Int?
        for chunk in request.chunks {
            guard chunk.index >= 0,
                  previousIndex.map({ chunk.index > $0 }) ?? true,
                  chunk.startSec.isFinite,
                  chunk.endSec.isFinite,
                  chunk.startSec >= previousEnd,
                  chunk.endSec > chunk.startSec
            else { throw CocoaError(.fileReadCorruptFile) }
            previousIndex = chunk.index
            previousEnd = chunk.endSec
        }
    }
}
