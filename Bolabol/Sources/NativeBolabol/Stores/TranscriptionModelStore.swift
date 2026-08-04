import Combine
import CryptoKit
import FluidAudio
import Foundation
import NativeBolabolCore
import WhisperKit

@MainActor
final class TranscriptionModelStore: ObservableObject {
    /// Legacy transcription settings blob key. Internal so GeneralSettingsStore
    /// can seed the canonical speech-language pair from it during B1 migration.
    static let settingsDefaultsKey = "transcription.modelSettings"

    let catalog: TranscriptionModelCatalog
    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let modelsDirectory: URL
    private let parakeetModelsDirectory: URL

    @Published private(set) var settings: TranscriptionModelSettings {
        didSet {
            saveSettings()
        }
    }
    @Published private(set) var downloadingModelIDs: Set<String> = []

    init(
        catalog: TranscriptionModelCatalog = .nativeWhisperKit,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        modelsDirectory: URL? = nil,
        parakeetModelsDirectory: URL? = nil
    ) {
        self.catalog = catalog
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        let resolvedModelsDirectory = modelsDirectory ?? Self.defaultModelsDirectory(fileManager: fileManager)
        self.modelsDirectory = resolvedModelsDirectory
        self.parakeetModelsDirectory = parakeetModelsDirectory
            ?? (modelsDirectory == nil
                ? Self.defaultParakeetModelsDirectory(fileManager: fileManager)
                : resolvedModelsDirectory)
        
        var loadedSettings = Self.loadSettings(from: userDefaults)
        loadedSettings.resetInterruptedDownloads()
        self.settings = loadedSettings
        reconcileModelStates()
    }

    static func live() -> TranscriptionModelStore {
        TranscriptionModelStore()
    }

    var models: [TranscriptionModelDescriptor] {
        catalog.models
    }

    var activeModel: TranscriptionModelDescriptor? {
        settings.activeModel(catalog: catalog)
    }

    var resolvedLanguageCode: String {
        settings.resolvedLanguageCode(catalog: catalog)
    }

    var languageSelectionTag: String {
        switch settings.languagePreference {
        case .auto:
            "auto"
        case .language(let code):
            code
        case .custom:
            "custom"
        }
    }

    var customLanguageCode: String {
        guard case .custom(let code) = settings.languagePreference else {
            return ""
        }

        return code
    }

    /// Canonical speech-language pair (plan §3.3). The pair lives in the shared
    /// GeneralSettings blob; this store only *reads* it so the legacy
    /// `languagePreference` routing (auto-detect by default, §4.1) stays intact.
    var speechLanguages: UserSpeechLanguages {
        guard let data = userDefaults.data(forKey: GeneralSettingsStore.settingsDefaultsKey),
              let generalSettings = try? JSONDecoder().decode(GeneralSettings.self, from: data)
        else {
            return UserSpeechLanguages()
        }
        return generalSettings.speechLanguages
    }

    func installationState(
        for model: TranscriptionModelDescriptor
    ) -> TranscriptionModelInstallationState {
        settings.installationState(for: model.id)
    }

    func setLanguageSelectionTag(_ tag: String) {
        if tag == "auto" {
            settings.languagePreference = .auto
        } else if tag == "custom" {
            settings.languagePreference = .custom(customLanguageCode)
        } else {
            settings.languagePreference = .language(tag)
        }
    }

    func setCustomLanguageCode(_ code: String) {
        settings.languagePreference = .custom(code)
    }

    func activate(_ model: TranscriptionModelDescriptor) {
        reconcileModelStates()
        guard hasLocalFiles(for: model) else { return }
        _ = settings.activate(modelID: model.id, catalog: catalog)
        // Selecting any downloaded on-device model implies the local backend.
        settings.backend = .localWhisper
    }

    func deactivate() {
        settings.deactivate()
    }

    func setBackend(_ backend: TranscriptionBackend) {
        settings.backend = backend
        if backend == .geminiCloud {
            // Cloud dictation does not use an on-device Whisper selection.
            // Keep activeModelID if present so switching back is easy.
        }
    }

    var usesGeminiCloud: Bool {
        settings.backend == .geminiCloud
    }

    func remove(_ model: TranscriptionModelDescriptor) {
        if let localURL = settings.installationState(for: model.id).localURL {
            try? fileManager.removeItem(at: localURL)
        } else {
            try? fileManager.removeItem(at: destinationURL(for: model))
        }

        settings.remove(modelID: model.id)
    }

    func hasLocalFiles(for model: TranscriptionModelDescriptor) -> Bool {
        completeLocalURL(for: model) != nil
    }

    func reconcileModelStates() {
        settings.resetInterruptedDownloads()
        for model in catalog.models {
            let state = settings.installationState(for: model.id)
            guard state.status != .downloading else { continue }

            if let localURL = completeLocalURL(for: model) {
                settings.markDownloaded(modelID: model.id, localURL: localURL)
            } else if state.status == .downloaded || state.status == .failed {
                settings.remove(modelID: model.id)
            }
        }
    }

    func download(_ model: TranscriptionModelDescriptor) async {
        guard !downloadingModelIDs.contains(model.id) else { return }

        downloadingModelIDs.insert(model.id)
        defer {
            downloadingModelIDs.remove(model.id)
        }
        settings.markDownloading(modelID: model.id, progressFraction: nil)

        do {
            let downloadedURL: URL
            switch model.backend {
            case .whisperKitCoreML:
                let destination = destinationURL(for: model)
                try fileManager.createDirectory(
                    at: destination,
                    withIntermediateDirectories: true
                )
                let progressHandler: @Sendable (Progress) -> Void = { [weak self] progress in
                    let fraction = progress.totalUnitCount > 0
                        ? progress.fractionCompleted
                        : nil
                    Task { @MainActor [weak self] in
                        self?.settings.markDownloading(
                            modelID: model.id,
                            progressFraction: fraction
                        )
                    }
                }
                downloadedURL = try await WhisperKit.download(
                    variant: model.modelName,
                    downloadBase: destination,
                    useBackgroundSession: false,
                    from: model.modelRepositoryID,
                    progressCallback: progressHandler
                )

            case .fluidAudioCoreML:
                let destination = destinationURL(for: model)
                try fileManager.createDirectory(
                    at: destination,
                    withIntermediateDirectories: true
                )
                downloadedURL = try await AsrModels.download(
                    to: destination,
                    version: .v3,
                    encoderPrecision: .int8
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.settings.markDownloading(
                            modelID: model.id,
                            progressFraction: progress.fractionCompleted
                        )
                    }
                }

            case .canaryCoreML, .gigaAMCoreML:
                let destination = destinationURL(for: model)
                try fileManager.createDirectory(
                    at: destination,
                    withIntermediateDirectories: true
                )
                let progressHandler: @Sendable (Double) -> Void = { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        self?.settings.markDownloading(
                            modelID: model.id,
                            progressFraction: fraction
                        )
                    }
                }
                downloadedURL = try await performGOModelDownload(
                    model: model,
                    destination: destination,
                    progressHandler: progressHandler
                )
            }
            settings.markDownloaded(
                modelID: model.id,
                localURL: downloadedURL
            )
            _ = settings.activate(modelID: model.id, catalog: catalog)
        } catch {
            settings.markFailed(
                modelID: model.id,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func destinationURL(
        for model: TranscriptionModelDescriptor
    ) -> URL {
        switch model.backend {
        case .whisperKitCoreML:
            return modelsDirectory.appendingPathComponent(model.id, isDirectory: true)
        case .fluidAudioCoreML:
            return parakeetModelsDirectory.appendingPathComponent(
                model.modelFolderName,
                isDirectory: true
            )
        case .canaryCoreML, .gigaAMCoreML:
            let baseRoot = SharedModelsRoot.resolve(configuredRoot: modelsDirectory, fileManager: fileManager)
            return baseRoot.appendingPathComponent(
                model.relativeStorageSubpath,
                isDirectory: true
            )
        }
    }

    private func completeLocalURL(for model: TranscriptionModelDescriptor) -> URL? {
        let state = settings.installationState(for: model.id)
        let candidates = [
            state.localURL,
            destinationURL(for: model)
        ].compactMap(\.self)

        if model.backend == .fluidAudioCoreML {
            return candidates.first {
                AsrModels.modelsExist(
                    at: $0,
                    version: .v3,
                    encoderPrecision: .int8
                )
            }
        }

        if model.backend == .canaryCoreML || model.backend == .gigaAMCoreML {
            return candidates.first { isCompleteGOModelFolder(at: $0, for: model) }
        }

        for candidate in candidates {
            if LocalModelPresence.isCompleteWhisperKitModel(at: candidate, fileManager: fileManager) {
                return candidate
            }

            let nested = candidate.appendingPathComponent(model.modelFolderName, isDirectory: true)
            if LocalModelPresence.isCompleteWhisperKitModel(at: nested, fileManager: fileManager) {
                return nested
            }

            if let found = findCompleteWhisperKitModel(named: model.modelFolderName, in: candidate) {
                return found
            }
        }

        return nil
    }

    func activeDownloadedModel() -> ActiveTranscriptionModel? {
        guard let model = activeModel,
              let localURL = completeLocalURL(for: model)
        else {
            return nil
        }

        return ActiveTranscriptionModel(
            model: model,
            modelFolderURL: localURL
        )
    }

    private func findCompleteWhisperKitModel(named folderName: String, in baseURL: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard url.lastPathComponent == folderName else { continue }
            if LocalModelPresence.isCompleteWhisperKitModel(at: url, fileManager: fileManager) {
                return url
            }
        }

        return nil
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: Self.settingsDefaultsKey)
    }

    private static func loadSettings(
        from userDefaults: UserDefaults
    ) -> TranscriptionModelSettings {
        guard let data = userDefaults.data(forKey: settingsDefaultsKey),
              let settings = try? JSONDecoder().decode(TranscriptionModelSettings.self, from: data)
        else {
            return TranscriptionModelSettings()
        }

        return settings
    }

    private static func defaultModelsDirectory(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        let legacyURL = baseURL
            .appendingPathComponent("NativeBolabol", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("Transcription", isDirectory: true)
            .appendingPathComponent("WhisperKit", isDirectory: true)

        return (try? SharedModelsRoot.modelsDirectory(
            for: .whisperkit,
            legacyRoot: legacyURL,
            fileManager: fileManager
        )) ?? legacyURL
    }

    private static func defaultParakeetModelsDirectory(fileManager: FileManager) -> URL {
        (try? SharedModelsRoot.modelsDirectory(
            for: .parakeet,
            fileManager: fileManager
        )) ?? fileManager.temporaryDirectory
            .appendingPathComponent("NativeBolabol-Parakeet", isDirectory: true)
    }

    // MARK: - GO Model Downloads & Presence (ADR-018)

    private func isCompleteGOModelFolder(
        at directory: URL,
        for model: TranscriptionModelDescriptor
    ) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return false
        }
        let visible = Set(contents.filter { !$0.hasPrefix(".") })

        let hasCompiledModel = visible.contains { name in
            var itemIsDir: ObjCBool = false
            let itemURL = directory.appendingPathComponent(name, isDirectory: true)
            return fileManager.fileExists(atPath: itemURL.path, isDirectory: &itemIsDir)
                && itemIsDir.boolValue
                && name.hasSuffix(".mlmodelc")
        }
        guard hasCompiledModel else { return false }

        // Complete layout requirements for GO models (ADR-018):
        // Supported layout metadata markers: manifest.json, tokenizer.json
        let requiredItems: Set<String>
        switch model.id {
        case "canary-1b-v2-coreml":
            requiredItems = [
                "canary_encoder.mlmodelc",
                "canary_cross_kv.mlmodelc",
                "canary_decoder_kv.mlmodelc",
                "canary_spe.model"
            ]
        case "canary-180m-flash-coreml":
            requiredItems = [
                "CanaryEncoder.mlmodelc",
                "CanaryPrefill.mlmodelc",
                "CanaryDecoder.mlmodelc",
                "config.json",
                "vocab.json"
            ]
        case "gigaam-v3-rnnt-coreml":
            requiredItems = [
                "Encoder.mlmodelc",
                "Predictor.mlmodelc",
                "JointDecision.mlmodelc",
                "vocab.txt"
            ]
        default:
            return true
        }

        return requiredItems.isSubset(of: visible)
    }

    private func performGOModelDownload(
        model: TranscriptionModelDescriptor,
        destination: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        switch model.installSource {
        case .huggingFace(let repoID):
            return try await downloadHuggingFaceModel(
                repoID: repoID,
                destination: destination,
                progressHandler: progressHandler
            )
        case .bolabolCDN(let packageID, let baseURL):
            return try await downloadBolabolCDNPackage(
                packageID: packageID,
                baseURL: baseURL,
                destination: destination,
                progressHandler: progressHandler
            )
        case .fluidAudio:
            throw NSError(
                domain: "TranscriptionModelStore",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "FluidAudio install source handled via fluidAudioCoreML backend."]
            )
        }
    }

    private func downloadHuggingFaceModel(
        repoID: String,
        destination: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let apiURLString = "https://huggingface.co/api/models/\(repoID)/tree/main?recursive=true"
        guard let apiURL = URL(string: apiURLString) else {
            throw NSError(
                domain: "TranscriptionModelStore",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Hugging Face API URL for repo \(repoID)"]
            )
        }

        struct HFItem: Codable {
            let path: String
            let type: String
            let size: Int64?
        }

        let (data, response) = try await URLSession.shared.data(from: apiURL)
        guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            throw NSError(
                domain: "TranscriptionModelStore",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch file list for Hugging Face model \(repoID)"]
            )
        }

        let items = try JSONDecoder().decode([HFItem].self, from: data)
        let fileItems = items.filter { $0.type == "file" }
        let totalBytes = fileItems.compactMap(\.size).reduce(0, +)
        var downloadedBytes: Int64 = 0

        for item in fileItems {
            let localFileURL = destination.appendingPathComponent(item.path)
            try fileManager.createDirectory(at: localFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            let expectedSize = item.size ?? 0
            if fileManager.fileExists(atPath: localFileURL.path),
               let attrs = try? fileManager.attributesOfItem(atPath: localFileURL.path),
               let currentSize = attrs[.size] as? Int64,
               expectedSize > 0 && currentSize == expectedSize {
                downloadedBytes += expectedSize
                let fraction = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 1.0
                progressHandler(fraction)
                continue
            }

            let downloadURLString = "https://huggingface.co/\(repoID)/resolve/main/\(item.path)"
            guard let fileRemoteURL = URL(string: downloadURLString) else { continue }

            let (tempURL, fileRes) = try await URLSession.shared.download(from: fileRemoteURL)
            guard let fileHTTPRes = fileRes as? HTTPURLResponse, (200...299).contains(fileHTTPRes.statusCode) else {
                throw NSError(
                    domain: "TranscriptionModelStore",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to download \(item.path) for Hugging Face model \(repoID)"]
                )
            }

            if fileManager.fileExists(atPath: localFileURL.path) {
                try fileManager.removeItem(at: localFileURL)
            }
            try fileManager.moveItem(at: tempURL, to: localFileURL)

            downloadedBytes += expectedSize
            let fraction = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 1.0
            progressHandler(fraction)
        }

        return destination
    }

    private func downloadBolabolCDNPackage(
        packageID: String,
        baseURL: URL,
        destination: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let manifestURL = baseURL.appendingPathComponent("\(packageID)/MANIFEST.json")
        let (manifestData, manifestRes) = try await URLSession.shared.data(from: manifestURL)
        guard let httpRes = manifestRes as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            throw NSError(
                domain: "TranscriptionModelStore",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Failed to download MANIFEST.json from Bolabol CDN for package \(packageID)"]
            )
        }

        let localManifestURL = destination.appendingPathComponent("MANIFEST.json")
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try manifestData.write(to: localManifestURL, options: .atomic)

        struct BolabolPackageManifest: Codable {
            let packageId: String?
            let files: [BolabolPackageManifestFile]
        }
        struct BolabolPackageManifestFile: Codable {
            let path: String
            let sha256: String
            let sizeBytes: Int64
        }

        let manifest = try JSONDecoder().decode(BolabolPackageManifest.self, from: manifestData)
        let totalBytes = manifest.files.reduce(0) { $0 + $1.sizeBytes }
        var downloadedBytes: Int64 = 0

        for file in manifest.files {
            let localFileURL = destination.appendingPathComponent(file.path)
            try fileManager.createDirectory(at: localFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: localFileURL.path),
               verifyFileSHA256(localFileURL, expectedHash: file.sha256) {
                downloadedBytes += file.sizeBytes
                let fraction = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 1.0
                progressHandler(fraction)
                continue
            }

            let fileRemoteURL = baseURL.appendingPathComponent("\(packageID)/\(file.path)")
            let (tempURL, fileRes) = try await URLSession.shared.download(from: fileRemoteURL)
            guard let fileHTTPRes = fileRes as? HTTPURLResponse, (200...299).contains(fileHTTPRes.statusCode) else {
                throw NSError(
                    domain: "TranscriptionModelStore",
                    code: 8,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to download \(file.path) for Bolabol CDN package \(packageID)"]
                )
            }

            if fileManager.fileExists(atPath: localFileURL.path) {
                try fileManager.removeItem(at: localFileURL)
            }
            try fileManager.moveItem(at: tempURL, to: localFileURL)

            guard verifyFileSHA256(localFileURL, expectedHash: file.sha256) else {
                try? fileManager.removeItem(at: localFileURL)
                throw NSError(
                    domain: "TranscriptionModelStore",
                    code: 9,
                    userInfo: [NSLocalizedDescriptionKey: "SHA-256 integrity verification failed for \(file.path)"]
                )
            }

            downloadedBytes += file.sizeBytes
            let fraction = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 1.0
            progressHandler(fraction)
        }

        return destination
    }

    private func verifyFileSHA256(_ fileURL: URL, expectedHash: String) -> Bool {
        guard let computed = computeSHA256(for: fileURL) else { return false }
        return computed.lowercased() == expectedHash.lowercased()
    }

    private func computeSHA256(for fileURL: URL) -> String? {
        guard let stream = InputStream(url: fileURL) else { return nil }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 65536
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 { return nil }
            if bytesRead == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: bytesRead))
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
