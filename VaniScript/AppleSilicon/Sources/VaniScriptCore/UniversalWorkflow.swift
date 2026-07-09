public enum UniversalWorkflowScreen: String, CaseIterable, Codable, Equatable, Sendable {
    case upload
    case config
    case processing
    case review
    case export
    case visualEditor

    public var title: String {
        switch self {
        case .upload:
            "Upload"
        case .config:
            "Config"
        case .processing:
            "Processing"
        case .review:
            "Review"
        case .export:
            "Export"
        case .visualEditor:
            "Visual Editor"
        }
    }
}

public enum UniversalSettingsTab: String, CaseIterable, Codable, Equatable, Sendable {
    case agents
    case apiKeys
    case appearance
    case chunking
    case glossary
    case models
    case prompts
    case statistics
    case transcription

    public var title: String {
        switch self {
        case .agents:
            "Agents"
        case .apiKeys:
            "API Keys"
        case .appearance:
            "Appearance"
        case .chunking:
            "Chunking"
        case .glossary:
            "Glossary"
        case .models:
            "Models"
        case .prompts:
            "Prompts"
        case .statistics:
            "Statistics"
        case .transcription:
            "Transcription"
        }
    }
}

public enum UniversalArchitectureMap {
    public static let serviceModules = [
        "storage",
        "transcription",
        "chunk-queue",
        "structured-translation",
        "local-translation",
        "cloud-translation",
        "literary-polish",
        "audio-review",
        "document-export",
        "shorts-reels",
        "render-engine",
    ]
}
