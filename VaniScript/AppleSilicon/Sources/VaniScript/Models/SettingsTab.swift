import Foundation

public enum SettingsTab: String, CaseIterable, Codable, Equatable, Sendable {
    case apiKeys
    case models
    case appearance
    case glossary
    case chunking
    case transcription
    case prompts
}
