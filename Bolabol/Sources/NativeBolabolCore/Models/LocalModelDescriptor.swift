import Foundation

public struct LocalModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case transcription
        case polishing
        case translation
    }

    public enum Backend: String, Codable, Sendable {
        case mlxSwift
        case coreML
        case foundationModels
        case whisper
        case parakeet
        case cloud
    }

    public var id: String
    public var displayName: String
    public var role: Role
    public var backend: Backend
    public var minimumMemoryGB: Int

    public init(
        id: String,
        displayName: String,
        role: Role,
        backend: Backend,
        minimumMemoryGB: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.backend = backend
        self.minimumMemoryGB = minimumMemoryGB
    }
}
