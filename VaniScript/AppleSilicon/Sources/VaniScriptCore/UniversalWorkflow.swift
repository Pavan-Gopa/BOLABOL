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
    case apiKeys
    case models
    case appearance
    case glossary
    case chunking
    case transcription
    case prompts
    case statistics

    public var title: String {
        switch self {
        case .apiKeys:
            "API Keys"
        case .models:
            "Models"
        case .appearance:
            "Appearance"
        case .glossary:
            "Glossary"
        case .chunking:
            "Chunking"
        case .transcription:
            "Transcription"
        case .prompts:
            "Prompts"
        case .statistics:
            "Statistics"
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
