import Foundation

public enum SettingsTab: String, CaseIterable, Codable, Equatable, Sendable {
    case agents
    case apiKeys
    case appearance
    case chunking
    case glossary
    case models
    case prompts
    case transcription
    case updates

    public static let alphabetized: [SettingsTab] = [
        .agents,
        .apiKeys,
        .appearance,
        .chunking,
        .glossary,
        .models,
        .prompts,
        .transcription,
        .updates,
    ]
}
