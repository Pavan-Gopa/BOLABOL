import Foundation
import NativeBolabolCore

actor MLXSwiftPolishingEngine: PolishingEngine {
    nonisolated let id: String
    nonisolated let displayName: String
    nonisolated let preparationModelDirectory: URL

    private let model: PolishingModelDescriptor
    private let localModelDirectory: URL?
    private var snapshot: ModelPreparationSnapshot

    init(
        model: PolishingModelDescriptor,
        localModelDirectory: URL? = nil,
        preparationModelDirectory: URL = MLXSwiftPolishingEngine.defaultModelDirectory(fileManager: .default)
    ) {
        self.model = model
        self.id = "mlx-swift-\(model.id)"
        self.displayName = "MLX Swift \(model.displayName)"
        self.localModelDirectory = localModelDirectory
        self.preparationModelDirectory = preparationModelDirectory
        self.snapshot = .notReady(
            modelDirectory: localModelDirectory ?? preparationModelDirectory,
            message: String(
                format: AppText.localized(.modelDownloadedLoadsOnFirstUse, language: .english),
                model.displayName
            )
        )
    }

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        guard let localModelDirectory else {
            throw MLXSwiftPolishingError.modelNotReady(
                String(
                    format: AppText.localized(.downloadModelBeforePolishing, language: .english),
                    model.displayName
                )
            )
        }

        let startedAt = Date()
        updateSnapshot(
            .loading(
                modelDirectory: localModelDirectory,
                message: String(
                    format: AppText.localized(.modelRunningInWorker, language: .english),
                    model.displayName
                )
            ),
            progress: { _ in }
        )

        let workerResponse = try await MLXPolishWorkerClient(
            workerURL: try workerExecutableURL()
        ).polish(
            request: MLXPolishWorkerRequest(
                model: model,
                localModelDirectoryPath: localModelDirectory.path,
                rawText: request.rawText,
                variant: request.variant,
                templateID: request.template.id,
                templateTitle: request.template.title,
                templateBody: request.template.body,
                humorLevel: request.humorLevel
            )
        )

        let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
        updateSnapshot(
            .ready(
                modelDirectory: localModelDirectory,
                diagnostics: EngineDiagnostics(
                    backendName: displayName,
                    loadTimeMilliseconds: elapsedMilliseconds
                ),
                message: String(
                    format: AppText.localized(.modelCompletedInWorker, language: .english),
                    model.displayName
                )
            ),
            progress: { _ in }
        )

        return PolishingResult(
            text: workerResponse.text,
            diagnostics: EngineDiagnostics(
                backendName: workerResponse.backendName,
                loadTimeMilliseconds: workerResponse.loadTimeMilliseconds ?? elapsedMilliseconds
            )
        )
    }

    func preparationSnapshot() async -> ModelPreparationSnapshot {
        snapshot
    }

    func prepareModel(
        progress: @Sendable @escaping (ModelPreparationSnapshot) -> Void = { _ in }
    ) async -> ModelPreparationSnapshot {
        guard let localModelDirectory else {
            let failed = ModelPreparationSnapshot.failed(
                message: String(
                    format: AppText.localized(.downloadModelBeforeLoading, language: .english),
                    model.displayName
                ),
                modelDirectory: preparationModelDirectory
            )
            updateSnapshot(failed, progress: progress)
            return failed
        }

        let ready = ModelPreparationSnapshot.ready(
            modelDirectory: localModelDirectory,
            diagnostics: EngineDiagnostics(backendName: displayName),
            message: String(
                format: AppText.localized(.modelDownloadedLoadsOnFirstUse, language: .english),
                model.displayName
            )
        )
        updateSnapshot(ready, progress: progress)
        return ready
    }

    private func updateSnapshot(
        _ snapshot: ModelPreparationSnapshot,
        progress: @Sendable (ModelPreparationSnapshot) -> Void
    ) {
        self.snapshot = snapshot
        progress(snapshot)
    }

    private func workerExecutableURL() throws -> URL {
        guard let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() else {
            throw MLXSwiftPolishingError.workerUnavailable("Could not locate app executable directory.")
        }

        let workerURL = executableDirectory.appendingPathComponent("NativeBolabolPolishWorker")
        guard FileManager.default.isExecutableFile(atPath: workerURL.path) else {
            throw MLXSwiftPolishingError.workerUnavailable(
                "MLX polish worker is missing from the app bundle."
            )
        }

        return workerURL
    }

    static func defaultModelDirectory(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        let legacyURL = baseURL
            .appendingPathComponent("NativeBolabol", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("Polishing", isDirectory: true)
            .appendingPathComponent("HuggingFace", isDirectory: true)

        return (try? SharedModelsRoot.modelsDirectory(
            for: .mlx,
            legacyRoot: legacyURL,
            fileManager: fileManager
        )) ?? legacyURL
    }
}

extension MLXSwiftPolishingEngine: ModelPreparingPolishingEngine {}

struct MLXPolishWorkerRequest: Codable, Sendable {
    let model: PolishingModelDescriptor
    let localModelDirectoryPath: String
    let rawText: String
    let variant: ProcessingVariant
    let templateID: String
    let templateTitle: String
    let templateBody: String
    let humorLevel: Int?
}

struct MLXPolishWorkerResponse: Codable, Sendable {
    let text: String
    let backendName: String
    let loadTimeMilliseconds: Int?
}

private struct MLXPolishWorkerClient {
    let workerURL: URL
    private let timeoutNanoseconds: UInt64 = 300 * 1_000_000_000

    func polish(request: MLXPolishWorkerRequest) async throws -> MLXPolishWorkerResponse {
        let process = Process()
        process.executableURL = workerURL

        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        let termination = WorkerProcessTermination()
        process.terminationHandler = { _ in
            termination.finish()
        }

        try process.run()
        let payload = try JSONEncoder().encode(request)
        standardInput.fileHandleForWriting.write(payload)
        try standardInput.fileHandleForWriting.close()

        try await withTaskCancellationHandler {
            try await waitForWorker(termination, process: process)
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        let errorMessage = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw MLXSwiftPolishingError.workerFailed(
                readableWorkerError(
                    errorMessage,
                    terminationStatus: process.terminationStatus
                )
            )
        }

        do {
            return try JSONDecoder().decode(MLXPolishWorkerResponse.self, from: outputData)
        } catch {
            throw MLXSwiftPolishingError.workerFailed(
                "Worker returned an invalid response: \(error.localizedDescription)"
            )
        }
    }

    private func waitForWorker(
        _ termination: WorkerProcessTermination,
        process: Process
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await termination.wait()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                if process.isRunning {
                    process.terminate()
                }
                throw MLXSwiftPolishingError.workerFailed(
                    "MLX worker timed out after 300 seconds."
                )
            }

            try await group.next()
            group.cancelAll()
        }
    }

    private func readableWorkerError(
        _ message: String?,
        terminationStatus: Int32
    ) -> String {
        guard let message, !message.isEmpty else {
            return "MLX worker exited with status \(terminationStatus)."
        }

        if message.contains("NSRangeException"),
           message.contains("load_device") || message.contains("default_gpu") {
            return "MLX could not open a Metal GPU device in the worker process."
        }

        if message.count > 600 {
            return String(message.prefix(600)) + "..."
        }

        return message
    }
}

private final class WorkerProcessTermination: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isFinished = false

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResumeNow = lock.withLock {
                if isFinished {
                    return true
                }

                self.continuation = continuation
                return false
            }

            if shouldResumeNow {
                continuation.resume()
            }
        }
    }

    func finish() {
        let continuation = lock.withLock {
            isFinished = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }

        continuation?.resume()
    }
}

private enum MLXSwiftPolishingError: LocalizedError {
    case modelNotReady(String)
    case workerUnavailable(String)
    case workerFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotReady(let message),
             .workerUnavailable(let message),
             .workerFailed(let message):
            message
        }
    }
}
