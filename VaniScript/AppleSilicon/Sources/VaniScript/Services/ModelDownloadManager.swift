import Foundation
import VaniScriptCore

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
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let tempDir = FileManager.default.temporaryDirectory
        let destination = tempDir.appendingPathComponent(UUID().uuidString + "_" + location.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
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
        if let error = error {
            continuation.resume(throwing: error)
        }
    }
}

public final class ModelDownloadManager: Sendable {
    public static let shared = ModelDownloadManager()

    private init() {}

    public func downloadModel(
        id: String,
        onProgress: @Sendable @escaping (Double, String) -> Void,
        onComplete: @Sendable @escaping (String) -> Void,
        onFailure: @Sendable @escaping (Error) -> Void
    ) {
        let (repo, subfolder) = modelRepoAndSubfolder(id: id)
        guard !repo.isEmpty else {
            onFailure(NSError(domain: "ModelDownloadManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unsupported model format"]))
            return
        }

        let fileManager = FileManager.default
        let modelDir = Self.destinationDirectory(for: id, fileManager: fileManager)

        do {
            try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)
        } catch {
            onFailure(error)
            return
        }

        Task {
            do {
                onProgress(0.02, "Fetching model metadata from Hugging Face...")
                let allFiles = try await fetchRepoFiles(repo: repo)

                // Filter files inside subfolder (if applicable) and keep essential model files
                let targetFiles: [String]
                if !subfolder.isEmpty {
                    targetFiles = allFiles.filter { $0.hasPrefix(subfolder) && isEssentialModelFile($0) }
                } else {
                    targetFiles = allFiles.filter { isEssentialModelFile($0) }
                }

                guard !targetFiles.isEmpty else {
                    throw NSError(domain: "ModelDownloadManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "No model files found in the Hugging Face repository"])
                }

                for (index, file) in targetFiles.enumerated() {
                    let fileUrlString = "https://huggingface.co/\(repo)/resolve/main/\(file)"
                    guard let downloadUrl = URL(string: fileUrlString) else { continue }

                    let filename = (file as NSString).lastPathComponent
                    let destFileUrl = modelDir.appendingPathComponent(filename)

                    let baseProgress = Double(index) / Double(targetFiles.count)
                    let stepWeight = 1.0 / Double(targetFiles.count)

                    // Simple skip mechanism if the file already exists and has a reasonable size (resume support)
                    if fileManager.fileExists(atPath: destFileUrl.path) {
                        let attrs = try? fileManager.attributesOfItem(atPath: destFileUrl.path)
                        let size = attrs?[.size] as? Int64 ?? 0
                        if size > 1024 { // If file exists and is not an empty stub/error file
                            onProgress(baseProgress + stepWeight, "Skipping \(filename) (already exists)...")
                            continue
                        }
                    }

                    let tempFileUrl = try await downloadFile(from: downloadUrl) { fileProgress in
                        let overallProgress = baseProgress + (fileProgress * stepWeight)
                        let percentStr = String(format: "%.0f%%", fileProgress * 100)
                        onProgress(overallProgress, "Downloading \(filename) (\(percentStr))...")
                    }

                    if fileManager.fileExists(atPath: destFileUrl.path) {
                        try? fileManager.removeItem(at: destFileUrl)
                    }
                    try fileManager.moveItem(at: tempFileUrl, to: destFileUrl)
                }

                onProgress(1.0, "Completed")
                onComplete(modelDir.path)
            } catch {
                onFailure(error)
            }
        }
    }

    static func destinationDirectory(for id: String, fileManager: FileManager = .default) -> URL {
        let runtime: SharedModelRuntime = id.hasPrefix("whisper-") ? .whisperkit : .mlx
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        let legacyURL = documents
            .appendingPathComponent("VaniScript", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)

        let runtimeDirectory = (try? SharedModelsRoot.modelsDirectory(
            for: runtime,
            legacyRoot: legacyURL,
            fileManager: fileManager
        )) ?? legacyURL

        return runtimeDirectory.appendingPathComponent(id, isDirectory: true)
    }

    private func fetchRepoFiles(repo: String) async throws -> [String] {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repo)") else {
            throw NSError(domain: "ModelDownloadManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Hugging Face repo URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "ModelDownloadManager", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Hugging Face returned status \(http.statusCode)"])
        }

        let manifest = try JSONDecoder().decode(HuggingFaceModelManifest.self, from: data)
        return manifest.files
    }

    private func isEssentialModelFile(_ path: String) -> Bool {
        let lowercasePath = path.lowercased()
        let filename = (path as NSString).lastPathComponent.lowercased()

        // Skip git, readme, gitattributes, gitignore, and other metadata files
        if lowercasePath.contains(".git") || lowercasePath.contains(".github") || filename == "readme.md" || filename == "license" || filename == "licence" || filename == ".gitattributes" || filename == ".gitignore" {
            return false
        }

        // Skip other text files unless they are tokenizer/configs
        if filename.hasSuffix(".md") || filename.hasSuffix(".pdf") {
            return false
        }

        if filename.hasSuffix(".txt") {
            if filename != "vocab.txt" && filename != "merges.txt" {
                return false
            }
        }

        return true
    }

    private func downloadFile(
        from url: URL,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let downloader = FileDownloader(onProgress: onProgress, continuation: continuation)
            let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            task.resume()
            // Ensure session is invalidated after completion to avoid memory leaks
            session.finishTasksAndInvalidate()
        }
    }

    private func modelRepoAndSubfolder(id: String) -> (repo: String, subfolder: String) {
        switch id {
        case "qwen35-08b-4bit":
            return ("mlx-community/Qwen3.5-0.8B-4bit", "")
        case "qwen35-2b-4bit":
            return ("mlx-community/Qwen3.5-2B-4bit", "")
        case "qwen35-4b-4bit":
            return ("mlx-community/Qwen3.5-4B-4bit", "")
        case "qwen35-9b-4bit":
            return ("mlx-community/Qwen3.5-9B-4bit", "")
        case "nemotron3-nano-4b-4bit":
            return ("mlx-community/NVIDIA-Nemotron-3-Nano-4B-4bit", "")

        case "whisper-small-en":
            return ("awni/whisperkit-coreml", "huggingface/models/apple/ml-whisper/small.en/")
        case "whisper-small-multilingual":
            return ("awni/whisperkit-coreml", "huggingface/models/apple/ml-whisper/small/")
        case "whisper-medium-en":
            return ("awni/whisperkit-coreml", "huggingface/models/apple/ml-whisper/medium.en/")
        case "whisper-medium-multilingual":
            return ("awni/whisperkit-coreml", "huggingface/models/apple/ml-whisper/medium/")
        case "whisper-large-v3-turbo":
            return ("awni/whisperkit-coreml", "huggingface/models/apple/ml-whisper/large-v3-turbo/")
        case "whisper-large-v3":
            return ("awni/whisperkit-coreml", "huggingface/models/apple/ml-whisper/large-v3/")
        default:
            return ("", "")
        }
    }
}
