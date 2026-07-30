import Combine
import FluidAudio
import Foundation
import NativeSmartScribeCore
import WhisperKit

@MainActor
final class TranscriptionModelStore: ObservableObject {
    private static let settingsDefaultsKey = "transcription.modelSettings"

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
            modelsDirectory.appendingPathComponent(model.id, isDirectory: true)
        case .fluidAudioCoreML:
            parakeetModelsDirectory.appendingPathComponent(
                model.modelFolderName,
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
            .appendingPathComponent("NativeSmartScribe", isDirectory: true)
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
            .appendingPathComponent("NativeSmartScribe-Parakeet", isDirectory: true)
    }
}
