import Foundation

public struct PolishingEngineDescriptor: Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var isActive: Bool

    public init(id: String, displayName: String, isActive: Bool) {
        self.id = id
        self.displayName = displayName
        self.isActive = isActive
    }
}

public enum PolishingEngineRegistryError: Error, Equatable, Sendable {
    case duplicateEngineID(String)
    case noEnginesRegistered
}

public struct PolishingEngineRegistry: Sendable {
    private let enginesByID: [String: any PolishingEngine]
    private let engineOrder: [String]
    public let activeEngineID: String

    public init(
        engines: [any PolishingEngine],
        preferredEngineID: String? = nil
    ) throws {
        var enginesByID: [String: any PolishingEngine] = [:]
        var engineOrder: [String] = []

        for engine in engines {
            guard enginesByID[engine.id] == nil else {
                throw PolishingEngineRegistryError.duplicateEngineID(engine.id)
            }
            enginesByID[engine.id] = engine
            engineOrder.append(engine.id)
        }

        guard let fallbackEngineID = engineOrder.first else {
            throw PolishingEngineRegistryError.noEnginesRegistered
        }

        self.enginesByID = enginesByID
        self.engineOrder = engineOrder
        self.activeEngineID = preferredEngineID.flatMap { enginesByID[$0]?.id } ?? fallbackEngineID
    }

    public var activeEngine: any PolishingEngine {
        enginesByID[activeEngineID]!
    }

    public var descriptors: [PolishingEngineDescriptor] {
        engineOrder.compactMap { id in
            guard let engine = enginesByID[id] else { return nil }
            return PolishingEngineDescriptor(
                id: engine.id,
                displayName: engine.displayName,
                isActive: engine.id == activeEngineID
            )
        }
    }
}
