import Combine
import CryptoKit
import Darwin
import Foundation
import HuggingFace
import NativeSmartScribeCore

@MainActor
final class PolishingEngineStore: ObservableObject {
    static let disabledEngineID = "polishing-disabled"
    static let mlxSwiftEngineID = "mlx-swift-local-model"

    private static let selectedEngineDefaultsKey = "polishing.selectedEngineID"
    private static let lastNonDisabledEngineDefaultsKey = "polishing.lastNonDisabledEngineID"
    private static let lastActiveModelDefaultsKey = "polishing.lastActiveModelID"
    private static let modelSettingsDefaultsKey = "polishing.modelSettings"
    private static let apiSettingsDefaultsKey = "polishing.apiProviderSettings"

    let catalog: PolishingModelCatalog

    private let ruleEngine: any PolishingEngine
    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let modelsDirectory: URL
    private let ggufModelsDirectory: URL
    private let scanner: LocalModelScanner
    private let credentialStore: any APIProviderCredentialStoring
    private var mlxEngines: [String: MLXSwiftPolishingEngine] = [:]
    private var cloudEngines: [String: CloudTextPolishingEngine] = [:]

    @Published private(set) var settings: PolishingModelSettings {
        didSet {
            saveModelSettings()
        }
    }
    @Published private(set) var apiSettings: APIProviderSettings {
        didSet {
            saveAPISettings()
            cloudEngines.removeAll()
        }
    }
    @Published private(set) var preparationSnapshot: ModelPreparationSnapshot
    @Published private(set) var preparingModelIDs: Set<String> = []
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var lastScanResultCount: Int?
    @Published private(set) var lastScanSkippedUnsupportedCount: Int?

    @Published var selectedEngineID: String {
        didSet {
            if !Self.validEngineIDs(apiSettings: apiSettings).contains(selectedEngineID) {
                selectedEngineID = Self.defaultEngineID
                return
            }

            userDefaults.set(selectedEngineID, forKey: Self.selectedEngineDefaultsKey)
            if selectedEngineID != Self.disabledEngineID {
                userDefaults.set(selectedEngineID, forKey: Self.lastNonDisabledEngineDefaultsKey)
            }
            refreshPreparationSnapshot()
        }
    }

    init(
        catalog: PolishingModelCatalog = .nativeMLX,
        ruleEngine: any PolishingEngine = LocalRuleBasedPolishingEngine(),
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        modelsDirectory: URL? = nil,
        ggufModelsDirectory: URL? = nil,
        credentialStore: any APIProviderCredentialStoring = KeychainAPIProviderCredentialStore()
    ) {
        self.catalog = catalog
        self.ruleEngine = ruleEngine
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.credentialStore = credentialStore
        let resolvedModelsDirectory = modelsDirectory ?? MLXSwiftPolishingEngine.defaultModelDirectory(
            fileManager: fileManager
        )
        self.modelsDirectory = resolvedModelsDirectory
        self.ggufModelsDirectory = ggufModelsDirectory
            ?? (modelsDirectory == nil
                ? Self.defaultGGUFModelsDirectory(fileManager: fileManager)
                : resolvedModelsDirectory)
        self.scanner = LocalModelScanner()
        self.settings = Self.loadModelSettings(from: userDefaults)
        let loadedAPISettings = Self.hydratedAPISettings(
            Self.loadAPISettings(from: userDefaults),
            credentialStore: credentialStore
        )
        self.apiSettings = loadedAPISettings

        let storedEngineID = userDefaults.string(forKey: Self.selectedEngineDefaultsKey)
        self.selectedEngineID = Self.validEngineIDs(apiSettings: loadedAPISettings).contains(storedEngineID ?? "")
            ? storedEngineID!
            : Self.defaultEngineID
        self.preparationSnapshot = .notReady(
            message: AppText.localized(.modelStatusUnavailable, language: .english)
        )

        if storedEngineID == nil {
            userDefaults.set(Self.defaultEngineID, forKey: Self.selectedEngineDefaultsKey)
        }

        reconcileModelStates(refreshSnapshot: false)
        pruneStaleCustomModels()
        refreshPreparationSnapshot()
        saveAPISettings()
        Task { @MainActor [weak self] in
            await self?.scanForLocalModels()
        }
    }

    static func live() -> PolishingEngineStore {
        PolishingEngineStore()
    }

    var activeEngine: any PolishingEngine {
        engine(for: selectedEngineID)
    }

    func engine(for engineID: String) -> any PolishingEngine {
        if engineID == Self.disabledEngineID {
            return MissingPolishingModelEngine()
        }

        if let providerKind = APIProviderKind(polishingEngineID: engineID) {
            let cacheKey = providerKind.polishingEngineID
            if let cached = cloudEngines[cacheKey] {
                return cached
            }
            let engine = CloudTextPolishingEngine(
                kind: providerKind,
                configuration: apiSettings.configuration(for: providerKind)
            )
            cloudEngines[cacheKey] = engine
            return engine
        }

        guard engineID == Self.mlxSwiftEngineID else { return ruleEngine }

        reconcileModelStates()
        guard let activeModel = settings.activeDownloadedModel(catalog: catalog) else {
            return MissingPolishingModelEngine()
        }

        let localURL = activeModel.localURL ?? activeModel.model.localDirectoryURL
        return cachedMLXEngine(
            for: activeModel.model,
            localURL: localURL
        )
    }

    /// Returns an MLX engine for the given model, regardless of which model
    /// is currently "active" in polishing settings. Used by the Translation modal
    /// so users can pick any downloaded model independently.
    func engine(forLocalMLXModel model: PolishingModelDescriptor) -> any PolishingEngine {
        reconcileModelStates()
        guard settings.installationState(for: model.id).isDownloaded else {
            return MissingPolishingModelEngine()
        }
        let localURL = settings.installationState(for: model.id).localURL ?? model.localDirectoryURL
        return cachedMLXEngine(for: model, localURL: localURL)
    }

    var descriptors: [PolishingEngineDescriptor] {
        let localDescriptors = [
            PolishingEngineDescriptor(
                id: Self.disabledEngineID,
                displayName: "Polishing Disabled",
                isActive: selectedEngineID == Self.disabledEngineID
            ),
            PolishingEngineDescriptor(
                id: ruleEngine.id,
                displayName: ruleEngine.displayName,
                isActive: selectedEngineID == ruleEngine.id
            ),
            PolishingEngineDescriptor(
                id: Self.mlxSwiftEngineID,
                displayName: "Local MLX Model",
                isActive: selectedEngineID == Self.mlxSwiftEngineID
            )
        ]
        let cloudDescriptors = apiSettings.availablePolishingProviders.map { provider in
            PolishingEngineDescriptor(
                id: provider.kind.polishingEngineID,
                displayName: provider.displayName,
                isActive: selectedEngineID == provider.kind.polishingEngineID
            )
        }

        return localDescriptors + cloudDescriptors
    }

    var models: [PolishingModelDescriptor] {
        catalog.models
    }

    var customModels: [PolishingModelDescriptor] {
        settings.customModels
    }

    var allModels: [PolishingModelDescriptor] {
        catalog.models + settings.customModels
    }

    var activeModel: PolishingModelDescriptor? {
        settings.activeModel(catalog: catalog)
    }

    var isPreparingAnyModel: Bool {
        !preparingModelIDs.isEmpty
    }

    var canAutoPolishAfterTranscription: Bool {
        guard selectedEngineID != Self.disabledEngineID else {
            return false
        }

        if let providerKind = APIProviderKind(polishingEngineID: selectedEngineID) {
            return apiSettings.availablePolishingProviders.contains { $0.kind == providerKind }
        }

        reconcileModelStates()
        return selectedEngineID != Self.mlxSwiftEngineID || settings.activeDownloadedModel(catalog: catalog) != nil
    }

    func updateAPIConfiguration(
        _ configuration: APIProviderConfiguration,
        for kind: APIProviderKind
    ) {
        apiSettings.setConfiguration(configuration, for: kind)

        if !Self.validEngineIDs(apiSettings: apiSettings).contains(selectedEngineID) {
            selectedEngineID = Self.defaultEngineID
        } else {
            refreshPreparationSnapshot()
        }
    }

    func selectAPIProvider(_ kind: APIProviderKind) {
        guard apiSettings.availablePolishingProviders.contains(where: { $0.kind == kind }) else {
            return
        }

        selectedEngineID = kind.polishingEngineID
    }

    func isPreparing(_ model: PolishingModelDescriptor) -> Bool {
        preparingModelIDs.contains(model.id)
    }

    func installationState(
        for model: PolishingModelDescriptor
    ) -> PolishingModelInstallationState {
        settings.installationState(for: model.id)
    }

    func activate(_ model: PolishingModelDescriptor) {
        reconcileModelStates()
        guard settings.installationState(for: model.id).isDownloaded else { return }
        guard settings.activate(modelID: model.id, catalog: catalog) else { return }
        userDefaults.set(model.id, forKey: Self.lastActiveModelDefaultsKey)
        selectedEngineID = Self.mlxSwiftEngineID
        refreshPreparationSnapshot()
    }

    /// Automatically enables the polishing engine and activates the last used
    /// or available downloaded model when the user selects Variant 1 or 2 via the HUD widget.
    func ensurePolishingEnabledForWidgetTarget() {
        if selectedEngineID == Self.disabledEngineID {
            let lastEngine = userDefaults.string(forKey: Self.lastNonDisabledEngineDefaultsKey)
            let valid = Self.validEngineIDs(apiSettings: apiSettings)
            if let lastEngine, valid.contains(lastEngine), lastEngine != Self.disabledEngineID {
                selectedEngineID = lastEngine
            } else {
                selectedEngineID = Self.mlxSwiftEngineID
            }
        }

        reconcileModelStates()
        if selectedEngineID == Self.mlxSwiftEngineID && settings.activeDownloadedModel(catalog: catalog) == nil {
            let availableDownloaded = allModels.filter { settings.installationState(for: $0.id).isDownloaded }
            let lastModelID = userDefaults.string(forKey: Self.lastActiveModelDefaultsKey)
            if let lastModelID, let targetModel = availableDownloaded.first(where: { $0.id == lastModelID }) {
                activate(targetModel)
            } else if let firstDownloaded = availableDownloaded.first {
                activate(firstDownloaded)
            }
        }
    }

    func remove(_ model: PolishingModelDescriptor) {
        if model.isCustom {
            removeCustomModel(model)
            return
        }
        try? fileManager.removeItem(at: cacheDirectory(for: model))
        if let localURL = settings.installationState(for: model.id).localURL,
           localURL.path.hasPrefix(modelsDirectory.path)
            || localURL.path.hasPrefix(ggufModelsDirectory.path) {
            try? fileManager.removeItem(at: localURL)
        }

        mlxEngines[model.id] = nil
        settings.remove(modelID: model.id)
        refreshPreparationSnapshot()
    }

    // MARK: - Local Model Scanning

    func scanForLocalModels() async {
        guard !isScanning else { return }
        isScanning = true
        lastScanResultCount = nil
        lastScanSkippedUnsupportedCount = nil

        let scannerCopy = scanner
        let scanResult = await Task.detached(priority: .userInitiated) {
            scannerCopy.scanAll()
        }.value

        // Filter out models already in catalog (by repositoryID)
        let catalogRepoIDs = Set(catalog.models.map(\.repositoryID))
        let newModels = scanResult.models.filter { !catalogRepoIDs.contains($0.repositoryID) }

        settings.addCustomModels(newModels)

        // Mark all custom models as downloaded with their local URL
        for model in settings.customModels {
            if let dirURL = model.localDirectoryURL {
                settings.markDownloaded(modelID: model.id, localURL: dirURL)
            }
        }

        lastScanResultCount = newModels.count
        lastScanSkippedUnsupportedCount = scanResult.skippedUnsupportedCount
        isScanning = false
        reconcileModelStates(refreshSnapshot: false)
        refreshPreparationSnapshot()
    }

    func reconcileModelStates() {
        reconcileModelStates(refreshSnapshot: true)
    }

    func removeCustomModel(_ model: PolishingModelDescriptor) {
        // Only remove from list, do NOT delete files from disk
        mlxEngines.removeValue(forKey: model.id)
        settings.removeCustomModel(id: model.id)
        refreshPreparationSnapshot()
    }

    func prepare(_ model: PolishingModelDescriptor) async {
        guard preparingModelIDs.isEmpty else { return }
        let preparationDirectory = model.backend == .llamaCppGGUF
            ? ggufModelsDirectory
            : modelsDirectory

        preparingModelIDs.insert(model.id)
        settings.markDownloading(modelID: model.id, progressFraction: nil)
        selectedEngineID = Self.mlxSwiftEngineID
        preparationSnapshot = .downloading(
            progressFraction: nil,
            modelDirectory: preparationDirectory,
            message: "Downloading \(model.displayName)."
        )

        defer {
            preparingModelIDs.remove(model.id)
        }

        do {
            let snapshotURL: URL
            let progressHandler: @MainActor @Sendable (Progress) -> Void = { [weak self] progress in
                let fraction: Double?
                if progress.totalUnitCount > 0 {
                    fraction = progress.fractionCompleted
                } else {
                    fraction = nil
                }

                self?.settings.markDownloading(
                    modelID: model.id,
                    progressFraction: fraction
                )
                self?.preparationSnapshot = .downloading(
                    progressFraction: fraction,
                    modelDirectory: preparationDirectory,
                    message: "Downloading \(model.displayName)."
                )
            }
            switch model.backend {
            case .mlxSwiftLLM:
                snapshotURL = try await downloadSnapshot(
                    for: model,
                    progress: progressHandler
                )
            case .llamaCppGGUF:
                snapshotURL = try await downloadGGUFBundle(
                    for: model,
                    progress: progressHandler
                )
            }

            settings.markDownloaded(
                modelID: model.id,
                localURL: snapshotURL
            )
            _ = settings.activate(modelID: model.id, catalog: catalog)
            preparationSnapshot = .ready(
                modelDirectory: snapshotURL,
                message: String(
                    format: AppText.localized(.modelDownloadedLoadsOnFirstUse, language: .english),
                    model.displayName
                )
            )
        } catch {
            settings.markFailed(
                modelID: model.id,
                errorMessage: error.localizedDescription
            )
            preparationSnapshot = .failed(
                message: error.localizedDescription,
                modelDirectory: preparationDirectory
            )
        }

        refreshPreparationSnapshot()
    }

    func refreshPreparationSnapshot() {
        guard selectedEngineID != Self.disabledEngineID else {
            preparationSnapshot = .notReady(
                message: AppText.localized(.polishingDisabledStatus, language: .english)
            )
            return
        }

        if let providerKind = APIProviderKind(polishingEngineID: selectedEngineID) {
            let configuration = apiSettings.configuration(for: providerKind)
            preparationSnapshot = .ready(
                message: "\(providerKind.displayName) \(configuration.textModel) is configured."
            )
            return
        }

        guard selectedEngineID == Self.mlxSwiftEngineID else {
            preparationSnapshot = .ready(
                message: AppText.localized(.noPreparationRequired, language: .english)
            )
            return
        }

        guard let activeModel = settings.activeDownloadedModel(catalog: catalog)?.model else {
            preparationSnapshot = .notReady(
                modelDirectory: modelsDirectory,
                message: AppText.localized(.chooseLocalPolishingModelShort, language: .english)
            )
            return
        }

        let localURL = settings.installationState(for: activeModel.id).localURL
        let engine = cachedMLXEngine(for: activeModel, localURL: localURL)
        Task { @MainActor [weak self] in
            let snapshot = await engine.preparationSnapshot()
            guard self?.settings.activeModelID == activeModel.id else { return }
            self?.preparationSnapshot = snapshot
        }
    }

    private func cachedMLXEngine(
        for model: PolishingModelDescriptor,
        localURL: URL?
    ) -> MLXSwiftPolishingEngine {
        let cacheKey = [model.id, localURL?.path].compactMap(\.self).joined(separator: "|")
        if let cachedEngine = mlxEngines[cacheKey] {
            return cachedEngine
        }

        let engine = MLXSwiftPolishingEngine(
            model: model,
            localModelDirectory: localURL,
            preparationModelDirectory: model.backend == .llamaCppGGUF
                ? ggufModelsDirectory
                : modelsDirectory
        )
        mlxEngines[cacheKey] = engine
        return engine
    }

    private func downloadGGUFBundle(
        for model: PolishingModelDescriptor,
        progress progressHandler: @MainActor @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let modelFileName = model.modelFileName else {
            throw PolishingModelDownloadError.missingModelFileName(model.displayName)
        }
        guard let entry = try await directTreeEntries(for: model).first(where: {
            $0.type == "file" && $0.path == modelFileName
        }) else {
            throw PolishingModelDownloadError.missingRemoteFile(modelFileName)
        }

        let modelDirectory = cacheDirectory(for: model)
        let modelURL = modelDirectory.appendingPathComponent(modelFileName)
        let runtimeDirectory = llamaRuntimeDirectory()
        let runtimeURL = runtimeDirectory.appendingPathComponent("llama-cli")
        let archiveDirectory = runtimeDirectory.deletingLastPathComponent()
        let archiveURL = archiveDirectory.appendingPathComponent(Self.llamaRuntimeArchiveName)
        let totalBytes = max(entry.size ?? 1, 1) + Self.llamaRuntimeArchiveSize
        let progress = Progress(totalUnitCount: totalBytes)
        progressHandler(progress)

        try fileManager.createDirectory(
            at: modelDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: archiveDirectory,
            withIntermediateDirectories: true
        )

        var completedBytes: Int64 = 0
        if isCompleteDownloadedFile(at: modelURL, expectedBytes: entry.size) {
            completedBytes += max(entry.size ?? 1, 1)
            progress.completedUnitCount = completedBytes
            progressHandler(progress)
        } else {
            let sourceURL = try directResolveURL(
                repositoryID: model.repositoryID,
                revision: model.revision,
                path: modelFileName
            )
            try await downloadDirectFile(
                from: sourceURL,
                to: modelURL,
                expectedBytes: entry.size,
                completedBytesBeforeFile: completedBytes,
                progress: progress,
                progressHandler: progressHandler
            )
            completedBytes += max(entry.size ?? fileSize(at: modelURL) ?? 1, 1)
            progress.completedUnitCount = min(completedBytes, totalBytes)
            progressHandler(progress)
        }

        if fileManager.isExecutableFile(atPath: runtimeURL.path) {
            progress.completedUnitCount = totalBytes
            progressHandler(progress)
            return modelDirectory
        }

        var archiveIsReady = isCompleteDownloadedFile(
            at: archiveURL,
            expectedBytes: Self.llamaRuntimeArchiveSize
        )
        if archiveIsReady,
           try sha256(at: archiveURL) != Self.llamaRuntimeArchiveSHA256 {
            try fileManager.removeItem(at: archiveURL)
            archiveIsReady = false
        }

        if !archiveIsReady {
            guard let runtimeSourceURL = URL(string: Self.llamaRuntimeArchiveURL) else {
                throw PolishingModelDownloadError.invalidDownloadResponse(
                    Self.llamaRuntimeArchiveName
                )
            }
            try await downloadDirectFile(
                from: runtimeSourceURL,
                to: archiveURL,
                expectedBytes: Self.llamaRuntimeArchiveSize,
                completedBytesBeforeFile: completedBytes,
                progress: progress,
                progressHandler: progressHandler
            )
        }

        let checksum = try sha256(at: archiveURL)
        guard checksum == Self.llamaRuntimeArchiveSHA256 else {
            try? fileManager.removeItem(at: archiveURL)
            throw PolishingModelDownloadError.runtimeChecksumMismatch
        }

        try await extractLlamaRuntime(
            archiveURL: archiveURL,
            destination: runtimeDirectory
        )
        guard fileManager.isExecutableFile(atPath: runtimeURL.path) else {
            throw PolishingModelDownloadError.runtimeExecutableMissing
        }

        progress.completedUnitCount = totalBytes
        progressHandler(progress)
        return modelDirectory
    }

    private func downloadSnapshot(
        for model: PolishingModelDescriptor,
        progress: @MainActor @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        if Self.directSnapshotDownloadModelIDs.contains(model.id) {
            NativeSmartScribeLog.models.info(
                "Using direct snapshot download for \(model.repositoryID, privacy: .public)."
            )
            return try await downloadSnapshotDirectly(for: model, progress: progress)
        }

        guard let repoID = Repo.ID(rawValue: model.repositoryID) else {
            throw PolishingModelDownloadError.invalidRepositoryID(model.repositoryID)
        }

        try fileManager.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )

        let hubCache = HubCache(cacheDirectory: modelsDirectory)
        let hubClient = HubClient(cache: hubCache)

        do {
            return try await hubClient.downloadSnapshot(
                of: repoID,
                revision: model.revision,
                matching: Self.mlxModelDownloadPatterns,
                maxConcurrentDownloads: 1,
                progressHandler: progress
            )
        } catch {
            NativeSmartScribeLog.models.error(
                "Hub snapshot download failed for \(model.repositoryID, privacy: .public): \(error.localizedDescription, privacy: .public). Falling back to direct snapshot download."
            )
            return try await downloadSnapshotDirectly(for: model, progress: progress)
        }
    }

    private func downloadSnapshotDirectly(
        for model: PolishingModelDescriptor,
        progress progressHandler: @MainActor @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let entries = try await directSnapshotEntries(for: model)
        let snapshotURL = modelsDirectory
            .appendingPathComponent("Direct", isDirectory: true)
            .appendingPathComponent(model.huggingFaceCacheFolderName, isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(model.revision, isDirectory: true)

        try fileManager.createDirectory(
            at: snapshotURL,
            withIntermediateDirectories: true
        )

        let totalBytes = entries.reduce(Int64(0)) { partial, entry in
            partial + max(entry.size ?? 1, 1)
        }
        let progress = Progress(totalUnitCount: max(totalBytes, 1))
        progressHandler(progress)

        var completedBytes: Int64 = 0
        for entry in entries {
            let destination = snapshotURL.appendingPathComponent(entry.path)
            let expectedBytes = entry.size
            if isCompleteDownloadedFile(at: destination, expectedBytes: expectedBytes) {
                completedBytes += max(expectedBytes ?? 1, 1)
                progress.completedUnitCount = min(completedBytes, progress.totalUnitCount)
                progressHandler(progress)
                continue
            }

            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let sourceURL = try directResolveURL(
                repositoryID: model.repositoryID,
                revision: model.revision,
                path: entry.path
            )
            try await downloadDirectFile(
                from: sourceURL,
                to: destination,
                expectedBytes: expectedBytes,
                completedBytesBeforeFile: completedBytes,
                progress: progress,
                progressHandler: progressHandler
            )

            completedBytes += max(expectedBytes ?? fileSize(at: destination) ?? 1, 1)
            progress.completedUnitCount = min(completedBytes, progress.totalUnitCount)
            progressHandler(progress)
        }

        guard snapshotHasCompleteWeights(snapshotURL) else {
            throw PolishingModelDownloadError.incompleteSnapshot(model.repositoryID)
        }

        return snapshotURL
    }

    private func directSnapshotEntries(
        for model: PolishingModelDescriptor
    ) async throws -> [DirectHuggingFaceTreeEntry] {
        try await directTreeEntries(for: model)
            .filter { $0.type == "file" }
            .filter { entry in
                Self.mlxModelDownloadPatterns.contains { pattern in
                    fnmatch(pattern, entry.path, 0) == 0
                }
            }
            .sorted { $0.path < $1.path }
    }

    private func directTreeEntries(
        for model: PolishingModelDescriptor
    ) async throws -> [DirectHuggingFaceTreeEntry] {
        let urlString = "https://huggingface.co/api/models/\(model.repositoryID)/tree/\(model.revision)?recursive=1&expand=1"
        guard let url = URL(string: urlString) else {
            throw PolishingModelDownloadError.invalidRepositoryID(model.repositoryID)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw PolishingModelDownloadError.invalidDownloadResponse(model.repositoryID)
        }

        return try JSONDecoder().decode([DirectHuggingFaceTreeEntry].self, from: data)
    }

    private func directResolveURL(
        repositoryID: String,
        revision: String,
        path: String
    ) throws -> URL {
        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://huggingface.co/\(repositoryID)/resolve/\(revision)/\(encodedPath)")
        else {
            throw PolishingModelDownloadError.invalidDownloadResponse(path)
        }

        return url
    }

    private func isCompleteDownloadedFile(
        at url: URL,
        expectedBytes: Int64?
    ) -> Bool {
        guard let actualBytes = fileSize(at: url) else { return false }
        guard let expectedBytes else { return true }
        return actualBytes == expectedBytes
    }

    private func downloadDirectFile(
        from sourceURL: URL,
        to destination: URL,
        expectedBytes: Int64?,
        completedBytesBeforeFile: Int64,
        progress: Progress,
        progressHandler: @MainActor @Sendable @escaping (Progress) -> Void
    ) async throws {
        let partialDestination = destination.appendingPathExtension("download")
        if let expectedBytes, let actualBytes = fileSize(at: partialDestination), actualBytes > expectedBytes {
            try? fileManager.removeItem(at: partialDestination)
        }
        if isCompleteDownloadedFile(at: partialDestination, expectedBytes: expectedBytes) {
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: partialDestination, to: destination)
            return
        }

        try await CurlDownloadTask(
            sourceURL: sourceURL,
            partialDestination: partialDestination,
            finalDestination: destination,
            expectedBytes: expectedBytes,
            completedBytesBeforeFile: completedBytesBeforeFile,
            progress: progress,
            progressHandler: progressHandler
        ).run()
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else {
            return nil
        }
        return size.int64Value
    }

    private func sha256(at url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func extractLlamaRuntime(
        archiveURL: URL,
        destination: URL
    ) async throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-xzf", archiveURL.path,
            "-C", destination.path,
            "--strip-components", "1"
        ]
        let standardError = Pipe()
        process.standardError = standardError
        let termination = ProcessTermination()
        process.terminationHandler = { _ in
            termination.finish()
        }

        try process.run()
        await withTaskCancellationHandler {
            await termination.wait()
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        guard process.terminationStatus == 0 else {
            let data = try? standardError.fileHandleForReading.readToEnd()
            let message = data.flatMap { String(data: $0, encoding: .utf8) }
                ?? "Unknown tar error."
            throw PolishingModelDownloadError.runtimeExtractionFailed(message)
        }
    }

    private func llamaRuntimeDirectory() -> URL {
        ggufModelsDirectory
            .appendingPathComponent(".runtime", isDirectory: true)
            .appendingPathComponent(Self.llamaRuntimeVersion, isDirectory: true)
    }

    private func applyPreparationSnapshot(
        _ snapshot: ModelPreparationSnapshot,
        for modelID: String
    ) {
        preparationSnapshot = snapshot

        switch snapshot.phase {
        case .downloading:
            settings.markDownloading(
                modelID: modelID,
                progressFraction: snapshot.progressFraction
            )
        case .loading:
            settings.markDownloading(
                modelID: modelID,
                progressFraction: snapshot.progressFraction ?? 1
            )
        case .notReady, .ready, .failed:
            break
        }
    }

    private func cacheDirectory(
        for model: PolishingModelDescriptor
    ) -> URL {
        switch model.backend {
        case .mlxSwiftLLM:
            modelsDirectory.appendingPathComponent(
                model.huggingFaceCacheFolderName,
                isDirectory: true
            )
        case .llamaCppGGUF:
            ggufModelsDirectory.appendingPathComponent(model.id, isDirectory: true)
        }
    }

    private func directCacheDirectory(
        for model: PolishingModelDescriptor
    ) -> URL {
        modelsDirectory
            .appendingPathComponent("Direct", isDirectory: true)
            .appendingPathComponent(model.huggingFaceCacheFolderName, isDirectory: true)
    }

    private func reconcileModelStates(refreshSnapshot: Bool) {
        settings.resetInterruptedDownloads()

        for model in catalog.models {
            let state = settings.installationState(for: model.id)
            guard state.status != .downloading else { continue }

            if let snapshotURL = cachedSnapshotURL(for: model) {
                settings.markDownloaded(
                    modelID: model.id,
                    localURL: snapshotURL
                )
            } else if state.status == .downloaded || state.status == .failed {
                mlxEngines = mlxEngines.filter { key, _ in
                    key != model.id && !key.hasPrefix("\(model.id)|")
                }
                settings.remove(modelID: model.id)
            }
        }

        pruneStaleCustomModels()
        if refreshSnapshot {
            refreshPreparationSnapshot()
        }
    }

    /// Removes custom models whose directories no longer exist on disk.
    /// Re-marks surviving custom models as downloaded so they always appear
    /// in the polishing dropdown.
    private func pruneStaleCustomModels() {
        let staleIDs = settings.customModels
            .filter { model in
                guard let dirURL = model.localDirectoryURL else { return true }
                return !scanner.validate(dirURL)
            }
            .map(\.id)

        for id in staleIDs {
            settings.removeCustomModel(id: id)
        }

        // Ensure all surviving custom models are marked as downloaded
        for model in settings.customModels {
            if let dirURL = model.localDirectoryURL {
                settings.markDownloaded(modelID: model.id, localURL: dirURL)
            }
        }
    }

    private func cachedSnapshotURL(
        for model: PolishingModelDescriptor
    ) -> URL? {
        if model.backend == .llamaCppGGUF {
            guard let modelFileName = model.modelFileName else { return nil }
            let modelDirectory = cacheDirectory(for: model)
            let modelURL = modelDirectory.appendingPathComponent(modelFileName)
            let runtimeURL = llamaRuntimeDirectory().appendingPathComponent("llama-cli")
            guard (fileSize(at: modelURL) ?? 0) > 0,
                  fileManager.isExecutableFile(atPath: runtimeURL.path)
            else {
                return nil
            }
            return modelDirectory
        }

        return cachedSnapshotURL(
            in: cacheDirectory(for: model)
                .appendingPathComponent("snapshots", isDirectory: true)
        ) ?? cachedSnapshotURL(
            in: directCacheDirectory(for: model)
                .appendingPathComponent("snapshots", isDirectory: true)
        )
    }

    private func cachedSnapshotURL(in snapshotsDirectory: URL) -> URL? {
        guard let snapshots = try? fileManager.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        return snapshots.first { snapshotURL in
            Self.requiredCachedMetadataFiles.allSatisfy { filename in
                fileManager.fileExists(atPath: snapshotURL.appendingPathComponent(filename).path)
            } && snapshotHasCompleteWeights(snapshotURL)
        }
    }

    private func snapshotHasCompleteWeights(_ snapshotURL: URL) -> Bool {
        let hasMetadata = Self.requiredCachedMetadataFiles.allSatisfy { name in
            fileManager.fileExists(atPath: snapshotURL.appendingPathComponent(name).path)
        }
        guard hasMetadata else { return false }

        let singleWeightsURL = snapshotURL.appendingPathComponent("model.safetensors")
        if let size = fileSize(at: singleWeightsURL), size > 0 {
            return true
        }

        let indexURL = snapshotURL.appendingPathComponent("model.safetensors.index.json")
        guard fileManager.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let weightMap = root["weight_map"] as? [String: String]
        else {
            return false
        }

        let weightFiles = Set(weightMap.values)
        guard !weightFiles.isEmpty else { return false }

        return weightFiles.allSatisfy { filename in
            (fileSize(at: snapshotURL.appendingPathComponent(filename)) ?? 0) > 0
        }
    }

    private func saveModelSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: Self.modelSettingsDefaultsKey)
    }

    private func saveAPISettings() {
        for kind in APIProviderKind.allCases {
            let keys = apiSettings.configuration(for: kind).apiKeys
            try? credentialStore.saveKeys(keys, for: kind)
        }

        var redactedSettings = apiSettings
        for kind in APIProviderKind.allCases {
            var configuration = redactedSettings.configuration(for: kind)
            configuration.apiKeys = []
            redactedSettings.setConfiguration(configuration, for: kind)
        }

        guard let data = try? JSONEncoder().encode(redactedSettings) else { return }
        userDefaults.set(data, forKey: Self.apiSettingsDefaultsKey)
    }

    private static func hydratedAPISettings(
        _ storedSettings: APIProviderSettings,
        credentialStore: any APIProviderCredentialStoring
    ) -> APIProviderSettings {
        var hydratedSettings = storedSettings

        for kind in APIProviderKind.allCases {
            var configuration = hydratedSettings.configuration(for: kind)
            let keychainKeys = credentialStore.loadKeys(for: kind)

            if !keychainKeys.isEmpty {
                configuration.apiKeys = keychainKeys
            } else if !configuration.apiKeys.isEmpty {
                try? credentialStore.saveKeys(configuration.apiKeys, for: kind)
            }

            hydratedSettings.setConfiguration(configuration, for: kind)
        }

        return hydratedSettings
    }

    private static func loadModelSettings(
        from userDefaults: UserDefaults
    ) -> PolishingModelSettings {
        guard let data = userDefaults.data(forKey: modelSettingsDefaultsKey),
              let settings = try? JSONDecoder().decode(PolishingModelSettings.self, from: data)
        else {
            return PolishingModelSettings()
        }

        return settings
    }

    private static func loadAPISettings(
        from userDefaults: UserDefaults
    ) -> APIProviderSettings {
        guard let data = userDefaults.data(forKey: apiSettingsDefaultsKey),
              let settings = try? JSONDecoder().decode(APIProviderSettings.self, from: data)
        else {
            return APIProviderSettings()
        }

        return settings
    }

    private static var defaultEngineID: String {
        disabledEngineID
    }

    private static func defaultGGUFModelsDirectory(fileManager: FileManager) -> URL {
        (try? SharedModelsRoot.modelsDirectory(
            for: .gguf,
            fileManager: fileManager
        )) ?? fileManager.temporaryDirectory
            .appendingPathComponent("NativeSmartScribe-GGUF", isDirectory: true)
    }

    private static func validEngineIDs(apiSettings: APIProviderSettings) -> Set<String> {
        Set([disabledEngineID, LocalRuleBasedPolishingEngine().id, mlxSwiftEngineID] + apiSettings.availablePolishingProviders.map {
            $0.kind.polishingEngineID
        })
    }

    private static let mlxModelDownloadPatterns = [
        "*.safetensors",
        "*.json",
        "*.jinja",
        "*.txt",
        "*.model",
        "*.py"
    ]

    private static let requiredCachedMetadataFiles = [
        "config.json",
        "tokenizer.json"
    ]

    private static let directSnapshotDownloadModelIDs: Set<String> = [
        "qwen35-08b-4bit",
        "qwen35-2b-4bit",
        "qwen35-4b-4bit",
        "qwen35-9b-4bit",
        "nemotron3-nano-4b-4bit"
    ]

    private static let directDownloadProgressStepBytes: Int64 = 512 * 1024

    private static let llamaRuntimeVersion = "llama-b10189"
    private static let llamaRuntimeArchiveName = "llama-b10189-bin-macos-arm64.tar.gz"
    private static let llamaRuntimeArchiveURL =
        "https://github.com/ggml-org/llama.cpp/releases/download/b10189/llama-b10189-bin-macos-arm64.tar.gz"
    private static let llamaRuntimeArchiveSize: Int64 = 10_938_444
    private static let llamaRuntimeArchiveSHA256 =
        "2534f61b16013786b3bb8b8f4eb86326b9614733a3670c721e99a608285a8017"
}

private struct MissingPolishingModelEngine: PolishingEngine {
    let id = "missing-polishing-model"
    let displayName = "MLX Swift Local Model"

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        throw MissingPolishingModelError.noPreparedModel
    }
}

private enum MissingPolishingModelError: LocalizedError {
    case noPreparedModel

    var errorDescription: String? {
        AppText.localized(.chooseLocalPolishingModel, language: .english)
    }
}

private struct DirectHuggingFaceTreeEntry: Decodable {
    let path: String
    let type: String
    let size: Int64?
}

private final class ProcessTermination: @unchecked Sendable {
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

private struct CurlDownloadTask {
    private let sourceURL: URL
    private let partialDestination: URL
    private let finalDestination: URL
    private let expectedBytes: Int64?
    private let completedBytesBeforeFile: Int64
    private let progress: Progress
    private let progressHandler: @MainActor @Sendable (Progress) -> Void

    init(
        sourceURL: URL,
        partialDestination: URL,
        finalDestination: URL,
        expectedBytes: Int64?,
        completedBytesBeforeFile: Int64,
        progress: Progress,
        progressHandler: @MainActor @Sendable @escaping (Progress) -> Void
    ) {
        self.sourceURL = sourceURL
        self.partialDestination = partialDestination
        self.finalDestination = finalDestination
        self.expectedBytes = expectedBytes
        self.completedBytesBeforeFile = completedBytesBeforeFile
        self.progress = progress
        self.progressHandler = progressHandler
    }

    func run() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "--location",
            "--fail",
            "--silent",
            "--show-error",
            "--retry", "3",
            "--retry-delay", "1",
            "--continue-at", "-",
            "--output", partialDestination.path,
            sourceURL.absoluteString
        ]
        let stderr = Pipe()
        process.standardError = stderr
        let termination = ProcessTermination()
        process.terminationHandler = { _ in
            termination.finish()
        }

        try process.run()
        let monitor = Task {
            await monitorProgress(until: process)
        }
        defer {
            monitor.cancel()
            if process.isRunning {
                process.terminate()
            }
        }

        await reportProgress(force: true)
        await withTaskCancellationHandler {
            await termination.wait()
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
        await monitor.value

        guard process.terminationStatus == 0 else {
            let actualBytes = Self.fileSize(at: partialDestination) ?? 0
            if let expectedBytes, actualBytes > expectedBytes {
                try? FileManager.default.removeItem(at: partialDestination)
            }
            let data = try? stderr.fileHandleForReading.readToEnd()
            let message = data.flatMap { String(data: $0, encoding: .utf8) }
                ?? sourceURL.lastPathComponent
            throw PolishingModelDownloadError.curlFailed(message)
        }

        let actualBytes = Self.fileSize(at: partialDestination) ?? 0
        if let expectedBytes, actualBytes != expectedBytes {
            try? FileManager.default.removeItem(at: partialDestination)
            throw PolishingModelDownloadError.incompleteFile(
                finalDestination.lastPathComponent,
                expected: expectedBytes,
                actual: actualBytes
            )
        }

        try? FileManager.default.removeItem(at: finalDestination)
        try FileManager.default.moveItem(at: partialDestination, to: finalDestination)
        await reportProgress(force: true)
    }

    private func monitorProgress(until process: Process) async {
        while process.isRunning && !Task.isCancelled {
            await reportProgress(force: false)
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    @MainActor
    private func reportProgress(force: Bool) {
        let downloadedBytes = Self.fileSize(at: partialDestination) ?? 0
        let completedUnitCount = min(
            progress.totalUnitCount,
            completedBytesBeforeFile + downloadedBytes
        )
        guard force || completedUnitCount != progress.completedUnitCount else {
            return
        }
        progress.completedUnitCount = completedUnitCount
        progressHandler(progress)
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else {
            return nil
        }
        return size.int64Value
    }
}

private enum PolishingModelDownloadError: LocalizedError {
    case invalidRepositoryID(String)
    case invalidDownloadResponse(String)
    case curlFailed(String)
    case incompleteFile(String, expected: Int64, actual: Int64)
    case incompleteSnapshot(String)
    case missingModelFileName(String)
    case missingRemoteFile(String)
    case runtimeChecksumMismatch
    case runtimeExtractionFailed(String)
    case runtimeExecutableMissing

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryID(let repositoryID):
            "Invalid Hugging Face repository ID: \(repositoryID)"
        case .invalidDownloadResponse(let path):
            "Invalid Hugging Face download response for \(path)"
        case .curlFailed(let message):
            "Hugging Face download failed: \(message)"
        case .incompleteFile(let filename, let expected, let actual):
            "Downloaded \(filename) is incomplete: \(actual) of \(expected) bytes."
        case .incompleteSnapshot(let repositoryID):
            "Downloaded snapshot for \(repositoryID) is incomplete."
        case .missingModelFileName(let modelName):
            "\(modelName) does not define a GGUF model filename."
        case .missingRemoteFile(let filename):
            "The required Hugging Face file \(filename) was not found."
        case .runtimeChecksumMismatch:
            "The downloaded llama.cpp runtime failed checksum verification."
        case .runtimeExtractionFailed(let message):
            "Could not install the llama.cpp runtime: \(message)"
        case .runtimeExecutableMissing:
            "The llama.cpp runtime archive did not contain llama-cli."
        }
    }
}
