import Foundation

public struct ActivePolishingModel: Equatable, Sendable {
    public var model: PolishingModelDescriptor
    public var localURL: URL?

    public init(
        model: PolishingModelDescriptor,
        localURL: URL? = nil
    ) {
        self.model = model
        self.localURL = localURL
    }
}

public struct PolishingModelSettings: Codable, Equatable, Sendable {
    public var activeModelID: String?
    public var installationStates: [String: PolishingModelInstallationState]
    public var customModels: [PolishingModelDescriptor]

    public init(
        activeModelID: String? = nil,
        installationStates: [String: PolishingModelInstallationState] = [:],
        customModels: [PolishingModelDescriptor] = []
    ) {
        self.activeModelID = activeModelID
        self.installationStates = installationStates
        self.customModels = customModels
    }

    public func installationState(
        for modelID: String
    ) -> PolishingModelInstallationState {
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
        catalog: PolishingModelCatalog
    ) -> Bool {
        let inCatalog = catalog.model(withID: modelID) != nil
        let inCustom = customModels.contains { $0.id == modelID }
        guard inCatalog || inCustom else { return false }
        guard installationState(for: modelID).isDownloaded else { return false }

        activeModelID = modelID
        return true
    }

    public mutating func addCustomModels(_ models: [PolishingModelDescriptor]) {
        let existingIDs = Set(customModels.map(\.id))
        for model in models where !existingIDs.contains(model.id) {
            customModels.append(model)
        }
    }

    public mutating func removeCustomModel(id: String) {
        customModels.removeAll { $0.id == id }
        installationStates.removeValue(forKey: id)
        if activeModelID == id {
            activeModelID = nil
        }
    }

    public func customModel(withID id: String?) -> PolishingModelDescriptor? {
        guard let id else { return nil }
        return customModels.first { $0.id == id }
    }

    public mutating func deactivate() {
        activeModelID = nil
    }

    public func activeModel(
        catalog: PolishingModelCatalog
    ) -> PolishingModelDescriptor? {
        catalog.model(withID: activeModelID) ?? customModel(withID: activeModelID)
    }

    public func activeDownloadedModel(
        catalog: PolishingModelCatalog
    ) -> ActivePolishingModel? {
        guard let model = activeModel(catalog: catalog) else { return nil }
        let state = installationState(for: model.id)
        guard state.isDownloaded else { return nil }

        return ActivePolishingModel(
            model: model,
            localURL: state.localURL ?? model.localDirectoryURL
        )
    }
}
