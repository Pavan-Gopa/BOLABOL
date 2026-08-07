import Foundation

public struct ActiveTranscriptionModel: Equatable, Sendable {
    public var model: TranscriptionModelDescriptor
    public var modelFolderURL: URL

    public init(
        model: TranscriptionModelDescriptor,
        modelFolderURL: URL
    ) {
        self.model = model
        self.modelFolderURL = modelFolderURL
    }
}

public struct TranscriptionModelSettings: Codable, Equatable, Sendable {
    public var activeModelID: String?
    public var languagePreference: TranscriptionLanguagePreference
    public var installationStates: [String: TranscriptionModelInstallationState]
    /// Local speech models vs Cloud Gemini. Never falls back to Apple Speech.
    public var backend: TranscriptionBackend

    public init(
        activeModelID: String? = nil,
        languagePreference: TranscriptionLanguagePreference = .auto,
        installationStates: [String: TranscriptionModelInstallationState] = [:],
        backend: TranscriptionBackend = .localWhisper
    ) {
        self.activeModelID = activeModelID
        self.languagePreference = languagePreference
        self.installationStates = installationStates
        self.backend = backend
    }

    public func installationState(
        for modelID: String
    ) -> TranscriptionModelInstallationState {
        installationStates[modelID] ?? .notDownloaded()
    }

    public mutating func markDownloading(
        modelID: String,
        progressFraction: Double?
    ) {
        installationStates[modelID] = .downloading(progressFraction: progressFraction)
    }

    public mutating func markDownloaded(
        modelID: String,
        localURL: URL? = nil
    ) {
        installationStates[modelID] = .downloaded(localURL: localURL)
    }

    public mutating func markFailed(
        modelID: String,
        errorMessage: String
    ) {
        installationStates[modelID] = .failed(errorMessage)
        if activeModelID == modelID {
            activeModelID = nil
        }
    }

    public mutating func remove(modelID: String) {
        installationStates[modelID] = .notDownloaded()
        if activeModelID == modelID {
            activeModelID = nil
        }
    }

    public mutating func resetInterruptedDownloads() {
        for (modelID, state) in installationStates where state.status == .downloading {
            installationStates[modelID] = .notDownloaded()
        }
    }

    @discardableResult
    public mutating func activate(
        modelID: String,
        catalog: TranscriptionModelCatalog
    ) -> Bool {
        guard catalog.model(withID: modelID) != nil else { return false }
        guard installationState(for: modelID).isDownloaded else { return false }

        activeModelID = modelID
        return true
    }

    public mutating func deactivate() {
        activeModelID = nil
    }

    public func activeModel(
        catalog: TranscriptionModelCatalog
    ) -> TranscriptionModelDescriptor? {
        catalog.model(withID: activeModelID)
    }

    public func activeDownloadedModel(
        catalog: TranscriptionModelCatalog,
        fileManager: FileManager = .default
    ) -> ActiveTranscriptionModel? {
        guard let model = activeModel(catalog: catalog) else { return nil }

        let state = installationState(for: model.id)
        guard state.isDownloaded, let localURL = state.localURL else {
            return nil
        }

        // Prefer the recorded URL when it already points at a complete WhisperKit
        // bundle (AudioEncoder/TextDecoder/MelSpectrogram). This covers both the
        // nested Argmax download layout and flat local folders.
        if LocalModelPresence.isCompleteWhisperKitModel(at: localURL, fileManager: fileManager) {
            return ActiveTranscriptionModel(
                model: model,
                modelFolderURL: localURL
            )
        }

        // Nested layout: .../<downloadRoot>/openai_whisper-<variant>/
        var modelFolderURL = localURL.lastPathComponent == model.modelFolderName
            ? localURL
            : localURL.appendingPathComponent(model.modelFolderName, isDirectory: true)

        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: modelFolderURL.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            if let foundURL = findModelFolder(named: model.modelFolderName, in: localURL, fileManager: fileManager) {
                modelFolderURL = foundURL
            } else {
                return nil
            }
        }

        guard LocalModelPresence.isCompleteWhisperKitModel(at: modelFolderURL, fileManager: fileManager) else {
            return nil
        }

        return ActiveTranscriptionModel(
            model: model,
            modelFolderURL: modelFolderURL
        )
    }

    private func findModelFolder(
        named folderName: String,
        in baseURL: URL,
        fileManager: FileManager
    ) -> URL? {
        // Search up to 3 levels deep for the model folder
        let searchDepth = 3
        return searchForFolder(named: folderName, at: baseURL, depth: 0, maxDepth: searchDepth, fileManager: fileManager)
    }

    private func searchForFolder(
        named folderName: String,
        at url: URL,
        depth: Int,
        maxDepth: Int,
        fileManager: FileManager
    ) -> URL? {
        guard depth < maxDepth else { return nil }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return nil
        }

        for item in contents {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            if item.lastPathComponent == folderName {
                return item
            }

            // Recursively search subdirectories
            if let found = searchForFolder(named: folderName, at: item, depth: depth + 1, maxDepth: maxDepth, fileManager: fileManager) {
                return found
            }
        }

        return nil
    }

    public func resolvedLanguageCode(
        catalog: TranscriptionModelCatalog
    ) -> String {
        let defaultCode = activeModel(catalog: catalog)?.languageSupport.defaultLanguageCode ?? "auto"
        return languagePreference.resolvedCode(defaultCode: defaultCode)
    }

    private enum CodingKeys: String, CodingKey {
        case activeModelID
        case languagePreference
        case installationStates
        case backend
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeModelID = try container.decodeIfPresent(String.self, forKey: .activeModelID)
        languagePreference = try container.decodeIfPresent(
            TranscriptionLanguagePreference.self,
            forKey: .languagePreference
        ) ?? .auto
        installationStates = try container.decodeIfPresent(
            [String: TranscriptionModelInstallationState].self,
            forKey: .installationStates
        ) ?? [:]
        backend = try container.decodeIfPresent(TranscriptionBackend.self, forKey: .backend) ?? .localWhisper
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(activeModelID, forKey: .activeModelID)
        try container.encode(languagePreference, forKey: .languagePreference)
        try container.encode(installationStates, forKey: .installationStates)
        try container.encode(backend, forKey: .backend)
    }
}
