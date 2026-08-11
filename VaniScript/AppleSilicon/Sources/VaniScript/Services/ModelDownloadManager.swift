import FluidAudio
import Foundation
import VaniScriptCore

// Kept for the existing media importer, which uses the same app-target file
// downloader but is not part of LASR-02's model install path.
final class FileDownloader: NSObject, URLSessionDownloadDelegate, Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let continuation: CheckedContinuation<URL, Error>

    init(
        onProgress: @Sendable @escaping (Double) -> Void,
        continuation: CheckedContinuation<URL, Error>
    ) {
        self.onProgress = onProgress
        self.continuation = continuation
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + location.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            continuation.resume(returning: destination)
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            continuation.resume(throwing: error)
        }
    }
}

public enum ModelDownloadManagerError: LocalizedError, Equatable, Sendable {
    case unsupportedModel(String)
    case remotePackageNotBound(String)
    case invalidURL(String)
    case invalidResponse(Int)
    case htmlResponse(String)
    case unsafeRemotePath(String)
    case noModelFiles(String)
    case fileSizeMismatch(path: String, expected: Int64, actual: Int64)
    case presenceValidationFailed(String)
    case destinationReplacementFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedModel(let id):
            "No catalog install source exists for model \(id)."
        case .remotePackageNotBound(let id):
            "The release metadata for \(id) is not configured yet."
        case .invalidURL(let value):
            "The model download URL is invalid or is not HTTPS: \(value)"
        case .invalidResponse(let status):
            "The model server returned HTTP status \(status)."
        case .htmlResponse(let url):
            "The model server returned HTML instead of model bytes: \(url)"
        case .unsafeRemotePath(let path):
            "Refusing unsafe Hugging Face model path: \(path)"
        case .noModelFiles(let id):
            "No downloadable files were found for model \(id)."
        case .fileSizeMismatch(let path, let expected, let actual):
            "Downloaded file \(path) has \(actual) bytes; expected \(expected)."
        case .presenceValidationFailed(let id):
            "Downloaded model \(id) failed exact presence validation."
        case .destinationReplacementFailed(let reason):
            "Could not atomically replace the model destination: \(reason)"
        }
    }
}

/// Catalog-driven local model installer. It owns only temporary staging and
/// canonical shared-model destinations; engines and UI state remain elsewhere.
public final class ModelDownloadManager: @unchecked Sendable {
    public typealias ParakeetDownloader = @Sendable (
        _ destination: URL,
        _ progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL

    public static let shared = ModelDownloadManager()

    private static let destinationInstallCoordinator = ModelDestinationInstallCoordinator()

    private let fileManager: FileManager
    private let session: URLSession
    private let configuredRoot: URL?
    private let environment: [String: String]
    private let parakeetDownloader: ParakeetDownloader
    private let remotePackageInstaller: RemoteModelPackageInstaller

    public init(
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        configuredRoot: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        parakeetDownloader: ParakeetDownloader? = nil,
        remotePackageInstaller: RemoteModelPackageInstaller? = nil
    ) {
        self.fileManager = fileManager
        self.session = session
        self.configuredRoot = configuredRoot
        self.environment = environment
        self.parakeetDownloader = parakeetDownloader ?? Self.defaultParakeetDownloader
        self.remotePackageInstaller = remotePackageInstaller ?? RemoteModelPackageInstaller(
            session: session,
            fileManager: fileManager,
            configuredRoot: configuredRoot,
            environment: environment
        )
    }

    /// Compatibility callback API used by the existing Models UI and MCP
    /// bridge. The async implementation below is the single install path.
    public func downloadModel(
        id: String,
        onProgress: @Sendable @escaping (Double, String) -> Void,
        onComplete: @Sendable @escaping (String) -> Void,
        onFailure: @Sendable @escaping (Error) -> Void
    ) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await self.downloadModel(id: id) { fraction, label in
                    onProgress(fraction, label)
                }
                onComplete(url.path)
            } catch {
                onFailure(error)
            }
        }
    }

    /// Installs one catalog entry and returns a path only after the shared
    /// presence policy accepts the final destination.
    public func downloadModel(
        id: String,
        progress: @Sendable @escaping (Double, String) -> Void = { _, _ in }
    ) async throws -> URL {
        guard let descriptor = NativeModelCatalog.installDescriptor(for: id) else {
            throw ModelDownloadManagerError.unsupportedModel(id)
        }
        let destination = destinationDirectory(for: descriptor)
        if case .remotePackage = descriptor.installSource {
            // The package installer owns the shared remote destination lock.
            return try await downloadModelUnlocked(id: id, progress: progress)
        }
        await Self.destinationInstallCoordinator.acquire(destination)
        do {
            let result = try await downloadModelUnlocked(id: id, progress: progress)
            await Self.destinationInstallCoordinator.release(destination)
            return result
        } catch {
            await Self.destinationInstallCoordinator.release(destination)
            throw error
        }
    }

    private func downloadModelUnlocked(
        id: String,
        progress: @Sendable @escaping (Double, String) -> Void = { _, _ in }
    ) async throws -> URL {
        guard let descriptor = NativeModelCatalog.installDescriptor(for: id) else {
            throw ModelDownloadManagerError.unsupportedModel(id)
        }

        let destination = destinationDirectory(for: descriptor)

        if case let .remotePackage(release) = descriptor.installSource {
            guard let asrDescriptor = NativeModelCatalog.descriptor(for: id), release.isBound else {
                throw ModelDownloadManagerError.remotePackageNotBound(id)
            }

            progress(0, "Preparing verified remote package...")
            let installed = try await remotePackageInstaller.install(
                release: release,
                requiredRelativePaths: asrDescriptor.requiredLayout.requiredFiles,
                destination: destination
            ) { snapshot in
                progress(snapshot.fractionCompleted, "Downloading package (\(snapshot.bytesReceived) bytes)...")
            }
            guard NativeModelCatalog.isModelPresent(asrDescriptor, at: installed, fileManager: fileManager) else {
                throw ModelDownloadManagerError.presenceValidationFailed(id)
            }
            progress(1, "Completed")
            return installed
        }

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let stagingRoot = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".vaniscript-staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        progress(0, "Preparing \(descriptor.displayName)...")
        let stagedDestination: URL

        do {
            switch descriptor.installSource {
            case .fluidAudio:
                let stagedTarget = stagingRoot.appendingPathComponent(
                    destination.lastPathComponent,
                    isDirectory: true
                )
                try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
                let downloadedURL = try await parakeetDownloader(stagedTarget) { fraction in
                    progress(fraction, "Downloading Parakeet (\(Int(fraction * 100))%)...")
                }
                guard downloadedURL.standardizedFileURL.path == stagedTarget.standardizedFileURL.path,
                      let asrDescriptor = NativeModelCatalog.descriptor(for: id),
                      NativeModelCatalog.isModelPresent(asrDescriptor, at: stagedTarget, fileManager: fileManager)
                else {
                    throw ModelDownloadManagerError.presenceValidationFailed(id)
                }
                stagedDestination = stagedTarget

            case let .huggingFace(repositoryID, revision):
                stagedDestination = try await downloadHuggingFaceTree(
                    repositoryID: repositoryID,
                    revision: revision,
                    source: descriptor.installSource,
                    descriptor: descriptor,
                    stagingRoot: stagingRoot,
                    progress: progress
                )

            case .whisperKit:
                stagedDestination = try await downloadHuggingFaceTree(
                    repositoryID: repositoryID(from: descriptor.installSource),
                    revision: revision(from: descriptor.installSource),
                    source: descriptor.installSource,
                    descriptor: descriptor,
                    stagingRoot: stagingRoot,
                    progress: progress
                )

            case .remotePackage:
                throw ModelDownloadManagerError.remotePackageNotBound(id)
            }

            let finalURL = try replaceDestination(
                stagedDestination,
                with: destination
            )
            guard isPresent(descriptor, at: finalURL) else {
                throw ModelDownloadManagerError.presenceValidationFailed(id)
            }
            progress(1, "Completed")
            return finalURL
        } catch {
            throw error
        }
    }

    static func destinationDirectory(for id: String, fileManager: FileManager = .default) -> URL {
        guard let descriptor = NativeModelCatalog.installDescriptor(for: id) else {
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
            return documents
                .appendingPathComponent("VaniScript/Models", isDirectory: true)
                .appendingPathComponent(id, isDirectory: true)
        }

        let root = legacyModelsRoot(fileManager: fileManager)
        return SharedModelsRoot.resolve(legacyRoot: root, fileManager: fileManager)
            .appendingPathComponent(descriptor.relativeStorageSubpath, isDirectory: true)
    }

    private func isPresent(_ descriptor: NativeModelInstallDescriptor, at url: URL) -> Bool {
        if let asrDescriptor = NativeModelCatalog.descriptor(for: descriptor.id) {
            return NativeModelCatalog.isModelPresent(asrDescriptor, at: url, fileManager: fileManager)
        }
        return LocalModelVerification.verifyTranslationModelPath(url.path, modelID: descriptor.id)
    }

    private func downloadHuggingFaceTree(
        repositoryID: String,
        revision: String,
        source: LocalASRInstallSource,
        descriptor: NativeModelInstallDescriptor,
        stagingRoot: URL,
        progress: @Sendable @escaping (Double, String) -> Void
    ) async throws -> URL {
        let items = try await fetchHuggingFaceTree(repositoryID: repositoryID, revision: revision)
        let workingRoot = descriptor.storageRuntime == .mlx
            ? stagingRoot.appendingPathComponent(descriptor.id, isDirectory: true)
            : stagingRoot
        try fileManager.createDirectory(at: workingRoot, withIntermediateDirectories: true)
        let subfolder: String
        switch source {
        case let .whisperKit(_, value):
            subfolder = value
        default:
            subfolder = ""
        }

        let normalizedSubfolder = subfolder.isEmpty
            ? ""
            : (NativeModelPathPolicy.normalizedRelativePath(subfolder) ?? "") + "/"
        if !subfolder.isEmpty && normalizedSubfolder.isEmpty {
            throw ModelDownloadManagerError.unsafeRemotePath(subfolder)
        }

        let files = try items.compactMap { item -> (HuggingFaceTreeItem, String)? in
            guard NativeModelPathPolicy.isSafeRelativePath(item.path) else {
                throw ModelDownloadManagerError.unsafeRemotePath(item.path)
            }
            guard item.type == "file" else {
                guard item.type == "directory" else {
                    throw ModelDownloadManagerError.unsafeRemotePath(item.path)
                }
                return nil
            }

            guard normalizedSubfolder.isEmpty || item.path.hasPrefix(normalizedSubfolder) else {
                return nil
            }
            let relative = normalizedSubfolder.isEmpty
                ? item.path
                : String(item.path.dropFirst(normalizedSubfolder.count))
            guard NativeModelPathPolicy.normalizedRelativePath(relative) != nil else {
                throw ModelDownloadManagerError.unsafeRemotePath(item.path)
            }
            return (item, relative)
        }

        guard !files.isEmpty else {
            throw ModelDownloadManagerError.noModelFiles(descriptor.id)
        }
        guard Set(files.map(\.1)).count == files.count else {
            throw ModelDownloadManagerError.unsafeRemotePath("duplicate relative path")
        }

        let totalKnownBytes = files
            .compactMap { $0.0.size.map { max(0, $0) } }
            .reduce(0, +)
        var completedBytes: Int64 = 0
        var observedUnknownBytes: Int64 = 0
        let progressClamp = MonotonicProgressClamp()
        for (item, relativePath) in files {
            try Task.checkCancellation()
            let fileURL = workingRoot.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let baseBytes = completedBytes
            let priorUnknownBytes = observedUnknownBytes

            let remoteURL = try huggingFaceResolveURL(
                repositoryID: repositoryID,
                revision: revision,
                path: item.path
            )
            let tempURL = try await downloadFile(from: remoteURL) { received, expected in
                let receivedBytes = max(0, received)
                let currentUnknownBytes = item.size == nil
                    ? max(receivedBytes, max(0, expected))
                    : 0
                let denominator = max(
                    totalKnownBytes + priorUnknownBytes + currentUnknownBytes,
                    baseBytes + receivedBytes
                )
                let rawFraction = denominator > 0
                    ? Double(baseBytes + receivedBytes) / Double(denominator)
                    : 0
                let fraction = progressClamp.normalize(rawFraction)
                progress(fraction, "Downloading \(relativePath)...")
            }
            defer { try? fileManager.removeItem(at: tempURL) }

            let attributes = try fileManager.attributesOfItem(atPath: tempURL.path)
            let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            if let expectedSize = item.size, actualSize != expectedSize {
                throw ModelDownloadManagerError.fileSizeMismatch(
                    path: relativePath,
                    expected: expectedSize,
                    actual: actualSize
                )
            }
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            try fileManager.moveItem(at: tempURL, to: fileURL)
            completedBytes += actualSize
            if item.size == nil {
                observedUnknownBytes += actualSize
            }
            let denominator = max(totalKnownBytes + observedUnknownBytes, completedBytes)
            let rawFraction = denominator > 0
                ? Double(completedBytes) / Double(denominator)
                : 0
            let fraction = progressClamp.normalize(rawFraction)
            progress(fraction, "Downloaded \(relativePath)")
        }

        guard isPresent(descriptor, at: workingRoot) else {
            throw ModelDownloadManagerError.presenceValidationFailed(descriptor.id)
        }
        return workingRoot
    }

    private struct HuggingFaceTreeItem: Decodable, Sendable {
        let path: String
        let type: String
        let size: Int64?
    }

    private func fetchHuggingFaceTree(
        repositoryID: String,
        revision: String
    ) async throws -> [HuggingFaceTreeItem] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/api/models/\(repositoryID)/tree/\(revision)"
        components.query = "recursive=true"
        guard let url = components.url else {
            throw ModelDownloadManagerError.invalidURL(repositoryID)
        }
        let request = URLRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, url: url, data: data)
        return try JSONDecoder().decode([HuggingFaceTreeItem].self, from: data)
    }

    private func downloadFile(
        from url: URL,
        progress: @Sendable @escaping (Int64, Int64) -> Void
    ) async throws -> URL {
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            throw ModelDownloadManagerError.invalidURL(url.absoluteString)
        }
        let delegate = DownloadProgressDelegate { received, expected in
            progress(received, expected)
        }
        let request = URLRequest(url: url)
        let (temporaryURL, response) = try await session.download(for: request, delegate: delegate)
        guard let http = response as? HTTPURLResponse else {
            try? fileManager.removeItem(at: temporaryURL)
            throw ModelDownloadManagerError.invalidResponse(-1)
        }
        guard (200...299).contains(http.statusCode) else {
            try? fileManager.removeItem(at: temporaryURL)
            throw ModelDownloadManagerError.invalidResponse(http.statusCode)
        }
        if isHTMLResponse(http, url: url) {
            try? fileManager.removeItem(at: temporaryURL)
            throw ModelDownloadManagerError.htmlResponse(url.absoluteString)
        }
        return temporaryURL
    }

    private func validateResponse(_ response: URLResponse, url: URL, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ModelDownloadManagerError.invalidResponse(-1)
        }
        guard (200...299).contains(http.statusCode) else {
            throw ModelDownloadManagerError.invalidResponse(http.statusCode)
        }
        if isHTMLResponse(http, url: url) || data.prefix(256).lowercasedString.contains("<html") {
            throw ModelDownloadManagerError.htmlResponse(url.absoluteString)
        }
    }

    private func isHTMLResponse(_ response: HTTPURLResponse, url: URL) -> Bool {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        return contentType.contains("text/html") || contentType.contains("application/xhtml")
    }

    private func huggingFaceResolveURL(repositoryID: String, revision: String, path: String) throws -> URL {
        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://huggingface.co/\(repositoryID)/resolve/\(revision)/\(encodedPath)")
        else {
            throw ModelDownloadManagerError.invalidURL(path)
        }
        return url
    }

    private func repositoryID(from source: LocalASRInstallSource) -> String {
        if case let .whisperKit(repositoryID, _) = source { return repositoryID }
        return ""
    }

    private func revision(from source: LocalASRInstallSource) -> String {
        if case .whisperKit = source { return "main" }
        return "main"
    }

    private func replaceDestination(_ staged: URL, with destination: URL) throws -> URL {
        let parent = destination.deletingLastPathComponent()
        let backup = parent.appendingPathComponent(
            ".vaniscript-backup-\(UUID().uuidString)",
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
            throw ModelDownloadManagerError.destinationReplacementFailed(error.localizedDescription)
        }
    }

    private func destinationDirectory(for descriptor: NativeModelInstallDescriptor) -> URL {
        let root = SharedModelsRoot.resolve(
            configuredRoot: configuredRoot,
            environment: environment,
            fileManager: fileManager
        )
        return root.appendingPathComponent(descriptor.relativeStorageSubpath, isDirectory: true)
    }

    private static let defaultParakeetDownloader: ParakeetDownloader = { destination, progress in
        let downloaded = try await AsrModels.download(
            to: destination,
            version: .v3,
            encoderPrecision: .int8
        ) { snapshot in
            progress(snapshot.fractionCompleted)
        }
        guard AsrModels.modelsExist(
            at: downloaded,
            version: .v3,
            encoderPrecision: .int8
        ) else {
            throw ModelDownloadManagerError.presenceValidationFailed("parakeet-tdt-06b-v3")
        }
        return downloaded
    }

    private static func legacyModelsRoot(fileManager: FileManager) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        return documents
            .appendingPathComponent("VaniScript", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }
}

private final class MonotonicProgressClamp: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0

    func normalize(_ raw: Double) -> Double {
        let bounded = raw.isFinite ? min(1, max(0, raw)) : 0
        lock.lock()
        defer { lock.unlock() }
        value = max(value, bounded)
        return value
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
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
        // The async URLSession API owns the temporary file and returns it to
        // the caller; progress is the only delegate event needed here.
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

private extension Data {
    var lowercasedString: String {
        String(decoding: prefix(256), as: UTF8.self).lowercased()
    }
}
