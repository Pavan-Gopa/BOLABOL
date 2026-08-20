import Darwin
import Foundation
import VaniScriptCore

public struct BatchTranscriptionResult: Sendable, Equatable {
    public let duration: Double
    public let checkpoints: [BatchChunkCheckpoint]

    public init(duration: Double, checkpoints: [BatchChunkCheckpoint]) {
        self.duration = duration
        self.checkpoints = checkpoints
    }
}
public struct BatchTranscriptionProgress: Sendable, Equatable {
    public let fraction: Double
    public let totalChunks: Int?
    public let detail: BatchProgressDetail

    public init(fraction: Double, totalChunks: Int?, detail: BatchProgressDetail) {
        self.fraction = fraction
        self.totalChunks = totalChunks
        self.detail = detail
    }
}

public protocol BatchAudioTranscribing: Sendable {
    func transcribe(
        sourceURL: URL,
        resumedCheckpoints: [BatchChunkCheckpoint],
        progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void,
        checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void
    ) async throws -> BatchTranscriptionResult
}
public protocol BatchCompanionWriting: Sendable {
    func write(
        _ data: Data,
        sourceURL: URL,
        outputURL: URL,
        expectedSourceFingerprint: SourceFileFingerprint,
        knownGeneratedOutput: GeneratedOutputFingerprint?
    ) async throws -> GeneratedOutputFingerprint
}

public enum BatchProcessingEvent: Equatable, Sendable {
    case updated(jobID: UUID)
    case completed(jobID: UUID)
    case failed(jobID: UUID, message: String)
    case blockedOutputCollision(jobID: UUID, message: String)
}

public actor BatchTranscriptionCoordinator {
    private let repository: SQLiteBatchJobRepository
    private var activeConfigurationID: String
    private var activeTranscriber: any BatchAudioTranscribing
    private let writer: any BatchCompanionWriting
    private let maxAttempts: Int
    private let eventHandler: @Sendable (BatchProcessingEvent) async -> Void
    private var folderURLsByProfileID: [String: URL] = [:]
    private var running: [UUID: Task<Void, Never>] = [:]
    private var cancellationIntents: Set<UUID> = []
    private var isProcessingPending = false
    private var pauseAfterCurrent = false

    public init(
        repository: SQLiteBatchJobRepository,
        configuration: BatchTranscriptionConfiguration,
        transcriber: any BatchAudioTranscribing,
        writer: any BatchCompanionWriting,
        maxAttempts: Int = 3,
        eventHandler: @escaping @Sendable (BatchProcessingEvent) async -> Void = { _ in }
    ) {
        self.repository = repository
        self.activeConfigurationID = configuration.identifier
        self.activeTranscriber = transcriber
        self.writer = writer
        self.maxAttempts = max(1, maxAttempts)
        self.eventHandler = eventHandler
    }

    public func updateTranscriber(
        _ transcriber: any BatchAudioTranscribing,
        for configuration: BatchTranscriptionConfiguration
    ) {
        activeConfigurationID = configuration.identifier
        activeTranscriber = transcriber
    }

    public func drainAfterCurrent() async {
        guard isProcessingPending else { return }
        pauseAfterCurrent = true
        while isProcessingPending {
            await Task.yield()
        }
        pauseAfterCurrent = false
    }

    public func processPending(in folderURL: URL) async {
        await processPending(folderURLsByProfileID: [:], fallbackFolderURL: folderURL)
    }

    public func registerFolder(profileID: String, url: URL) {
        folderURLsByProfileID[profileID] = url
    }

    public func unregisterAllFolders() {
        folderURLsByProfileID.removeAll()
    }

    public func processPending() async {
        await processPending(folderURLsByProfileID: folderURLsByProfileID, fallbackFolderURL: nil)
    }

    public func processPending(folderURLsByProfileID: [String: URL]) async {
        await processPending(folderURLsByProfileID: folderURLsByProfileID, fallbackFolderURL: nil)
    }

    private func processPending(folderURLsByProfileID: [String: URL], fallbackFolderURL: URL?) async {
        guard !isProcessingPending else { return }
        isProcessingPending = true
        defer {
            isProcessingPending = false
        }
        while !Task.isCancelled {
            guard !pauseAfterCurrent else { return }
            let job: BatchJob
            do {
                guard let claimed = try await repository.claimNext(configurationID: activeConfigurationID) else { return }
                job = claimed
                if pauseAfterCurrent {
                    try? await repository.cancel(id: job.id)
                    return
                }
                await eventHandler(.updated(jobID: job.id))
            } catch { return }

            guard !Task.isCancelled else {
                try? await repository.cancel(id: job.id)
                return
            }

            if cancellationIntents.contains(job.id) {
                try? await repository.cancel(id: job.id)
                cancellationIntents.remove(job.id)
                continue
            }

            guard job.attempt <= maxAttempts else {
                let message = job.lastError ?? "Maximum batch attempts reached."
                try? await repository.fail(id: job.id, error: message)
                await eventHandler(.failed(jobID: job.id, message: message))
                continue
            }
            guard let folderURL = folderURLsByProfileID[job.profileID] ?? fallbackFolderURL else {
                let message = "Watched folder is unavailable."
                try? await repository.fail(id: job.id, error: message)
                await eventHandler(.failed(jobID: job.id, message: message))
                continue
            }

            let transcriber = activeTranscriber
            let task = Task { [repository, transcriber, writer, eventHandler] in
                var targetOutputURL: URL?
                do {
                    let (sourceURL, outputURL) = try Self.validatedURLs(for: job, in: folderURL)
                    targetOutputURL = outputURL
                    let result = try await transcriber.transcribe(
                        sourceURL: sourceURL,
                        resumedCheckpoints: job.checkpoints,
                        progress: { update in
                            let existingJob = try await repository.job(id: job.id)
                            try await repository.checkpoint(
                                id: job.id,
                                checkpoints: existingJob?.checkpoints ?? [],
                                progress: update.fraction,
                                totalChunks: update.totalChunks,
                                detail: update.detail
                            )
                            await eventHandler(.updated(jobID: job.id))
                        },
                        checkpoint: { checkpoints in
                            let existingJob = try await repository.job(id: job.id)
                            let total = existingJob?.totalChunks
                            let fraction = total.map { Double(checkpoints.count) / Double(max($0, 1)) } ?? (existingJob?.progress ?? 0)
                            try await repository.checkpoint(
                                id: job.id,
                                checkpoints: checkpoints,
                                progress: fraction,
                                totalChunks: total,
                                detail: existingJob?.progressDetail
                            )
                            await eventHandler(.updated(jobID: job.id))
                        }
                    )
                    try Task.checkCancellation()
                    let currentJob = try await repository.job(id: job.id)
                    let finalizingDetail = BatchProgressDetail(phase: .finalizing)
                    try await repository.checkpoint(
                        id: job.id,
                        checkpoints: result.checkpoints,
                        progress: 1.0,
                        totalChunks: currentJob?.totalChunks ?? result.checkpoints.count,
                        detail: finalizingDetail
                    )
                    await eventHandler(.updated(jobID: job.id))
                    let cues = result.checkpoints.flatMap(\.cues)
                    let rendered = try BatchTimedTextRenderer.render(duration: result.duration, cues: cues)
                    let output = try await writer.write(
                        Data(rendered.utf8),
                        sourceURL: sourceURL,
                        outputURL: outputURL,
                        expectedSourceFingerprint: job.sourceFingerprint,
                        knownGeneratedOutput: job.outputFingerprint
                    )
                    try Task.checkCancellation()
                    try await repository.complete(id: job.id, outputFingerprint: output)
                    await eventHandler(.completed(jobID: job.id))
                } catch is CancellationError {
                    try? await repository.cancel(id: job.id)
                } catch let writerError as AtomicCompanionWriterError where writerError.isOutputCollision {
                    let filename = targetOutputURL?.lastPathComponent ?? (job.relativeOutputPath as NSString).lastPathComponent
                    let message = writerError.actionableMessage(forOutputFilename: filename)
                    try? await repository.blockOutputCollision(id: job.id, error: message)
                    await eventHandler(.blockedOutputCollision(jobID: job.id, message: message))
                } catch {
                    let message = Self.safeErrorMessage(error)
                    try? await repository.fail(id: job.id, error: message)
                    await eventHandler(.failed(jobID: job.id, message: message))
                }
            }
            running[job.id] = task
            await task.value
            running[job.id] = nil
            cancellationIntents.remove(job.id)
        }
    }
    public func cancelAllAndWait() async {
        let active = running
        cancellationIntents.formUnion(active.keys)
        for task in active.values {
            task.cancel()
        }
        for task in active.values {
            await task.value
        }
        for jobID in active.keys {
            running[jobID] = nil
            cancellationIntents.remove(jobID)
        }
    }


    public func cancel(jobID: UUID) async throws {
        cancellationIntents.insert(jobID)
        running[jobID]?.cancel()
        if let job = try await repository.job(id: jobID), job.state == .pending || job.state == .processing {
            try await repository.cancel(id: jobID)
        }
    }

    private static func safeErrorMessage(_ error: Error) -> String {
        switch error {
        case is CancellationError:
            return "Batch transcription was cancelled."
        case let error as LocalizedError:
            return error.errorDescription ?? "Batch transcription failed."
        default:
            return "Batch transcription failed."
        }
    }

    private static func validatedURLs(for job: BatchJob, in folderURL: URL) throws -> (source: URL, output: URL) {
        let sourceComponents = try relativePathComponents(job.relativeSourcePath)
        let outputComponents = try relativePathComponents(job.relativeOutputPath)
        let folder = folderURL.resolvingSymlinksInPath().standardizedFileURL
        guard isDirectory(folder) else { throw CocoaError(.fileReadNoSuchFile) }

        let sourceParent = try resolvedDirectory(
            components: sourceComponents.dropLast(),
            under: folder,
            error: CocoaError(.fileReadNoPermission)
        )
        let source = sourceParent
            .appendingPathComponent(sourceComponents.last!)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard isDescendant(source, of: folder), isRegularFile(source) else {
            throw CocoaError(.fileReadNoPermission)
        }

        let outputParent = try resolvedDirectory(
            components: outputComponents.dropLast(),
            under: folder,
            error: CocoaError(.fileWriteNoPermission)
        )
        let output = outputParent.appendingPathComponent(outputComponents.last!).standardizedFileURL
        guard outputParent == source.deletingLastPathComponent(),
              output.deletingPathExtension().lastPathComponent == source.deletingPathExtension().lastPathComponent,
              output.pathExtension.lowercased() == "txt"
        else { throw CocoaError(.fileWriteNoPermission) }

        var outputMetadata = stat()
        let outputStatus = output.withUnsafeFileSystemRepresentation { lstat($0, &outputMetadata) }
        guard outputStatus != 0 || outputMetadata.st_mode & S_IFMT == S_IFREG else {
            throw CocoaError(.fileWriteNoPermission)
        }
        return (source, output)
    }

    private static func relativePathComponents(_ path: String) throws -> [String] {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !NSString(string: path).isAbsolutePath,
              !path.contains("\\"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw CocoaError(.fileReadNoPermission) }
        return components.map(String.init)
    }

    private static func resolvedDirectory(
        components: ArraySlice<String>,
        under folder: URL,
        error: Error
    ) throws -> URL {
        var directory = folder
        for component in components {
            directory = directory.appendingPathComponent(component).resolvingSymlinksInPath().standardizedFileURL
            guard isDescendant(directory, of: folder), isDirectory(directory) else { throw error }
        }
        return directory
    }

    private static func isDescendant(_ url: URL, of folder: URL) -> Bool {
        url == folder || url.path.hasPrefix(folder.path + "/")
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var metadata = stat()
        return url.withUnsafeFileSystemRepresentation({ lstat($0, &metadata) }) == 0
            && metadata.st_mode & S_IFMT == S_IFDIR
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        var metadata = stat()
        return url.withUnsafeFileSystemRepresentation({ lstat($0, &metadata) }) == 0
            && metadata.st_mode & S_IFMT == S_IFREG
    }

    public func retry(jobID: UUID) async throws {
        try await repository.retry(id: jobID)
    }
}
