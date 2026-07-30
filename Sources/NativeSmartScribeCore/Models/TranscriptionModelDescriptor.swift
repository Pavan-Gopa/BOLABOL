import Foundation

public struct TranscriptionModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    public enum Backend: String, Codable, Equatable, Sendable {
        case whisperKitCoreML
    }

    public enum LanguageSupport: String, Codable, Equatable, Sendable {
        case english
        case multilingual

        public var defaultLanguageCode: String {
            switch self {
            case .english:
                "en"
            case .multilingual:
                "auto"
            }
        }

        public var displayName: String {
            switch self {
            case .english:
                "English"
            case .multilingual:
                "Multi"
            }
        }
    }

    public var id: String
    public var displayName: String
    public var modelName: String
    public var modelRepositoryID: String
    public var snapshotGlob: String
    public var backend: Backend
    public var languageSupport: LanguageSupport
    public var downloadSize: String
    public var badge: String?
    public var description: String
    public var accuracy: Int
    public var speed: Int
    public var isRecommended: Bool

    public var modelFolderName: String {
        "openai_whisper-\(modelName)"
    }

    public init(
        id: String,
        displayName: String,
        modelName: String,
        modelRepositoryID: String = "argmaxinc/whisperkit-coreml",
        snapshotGlob: String? = nil,
        backend: Backend,
        languageSupport: LanguageSupport,
        downloadSize: String,
        badge: String? = nil,
        description: String,
        accuracy: Int,
        speed: Int,
        isRecommended: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.modelName = modelName
        self.modelRepositoryID = modelRepositoryID
        self.snapshotGlob = snapshotGlob ?? "openai_whisper-\(modelName)/**"
        self.backend = backend
        self.languageSupport = languageSupport
        self.downloadSize = downloadSize
        self.badge = badge
        self.description = description
        self.accuracy = Self.clampRating(accuracy)
        self.speed = Self.clampRating(speed)
        self.isRecommended = isRecommended
    }

    private static func clampRating(_ rating: Int) -> Int {
        min(max(rating, 1), 5)
    }
}

public enum TranscriptionModelCatalogError: Error, Equatable, Sendable {
    case duplicateModelID(String)
}

public struct TranscriptionModelCatalog: Equatable, Sendable {
    public var models: [TranscriptionModelDescriptor]

    public init(models: [TranscriptionModelDescriptor]) throws {
        var seenIDs = Set<String>()
        for model in models {
            guard seenIDs.insert(model.id).inserted else {
                throw TranscriptionModelCatalogError.duplicateModelID(model.id)
            }
        }

        self.models = models
    }

    public var defaultModel: TranscriptionModelDescriptor? {
        models.first { $0.isRecommended } ?? models.first
    }

    public func model(withID id: String?) -> TranscriptionModelDescriptor? {
        guard let id else { return nil }
        return models.first { $0.id == id }
    }
}

public extension TranscriptionModelCatalog {
    static let nativeWhisperKit = try! TranscriptionModelCatalog(
        models: [
            TranscriptionModelDescriptor(
                id: "whisperkit-small-en",
                displayName: "Whisper Small English",
                modelName: "small.en",
                backend: .whisperKitCoreML,
                languageSupport: .english,
                downloadSize: "~487 MB",
                badge: "Fast",
                description: "Compact English-only Whisper model for quick local transcription on Apple Silicon.",
                accuracy: 3,
                speed: 5
            ),
            TranscriptionModelDescriptor(
                id: "whisperkit-small-multilingual",
                displayName: "Whisper Small Multi",
                modelName: "small",
                backend: .whisperKitCoreML,
                languageSupport: .multilingual,
                downloadSize: "~486 MB",
                badge: "Fast",
                description: "Compact multilingual Whisper model for lightweight local transcription across languages.",
                accuracy: 3,
                speed: 5
            ),
            TranscriptionModelDescriptor(
                id: "whisperkit-medium-en",
                displayName: "Whisper Medium English",
                modelName: "medium.en",
                backend: .whisperKitCoreML,
                languageSupport: .english,
                downloadSize: "~1.53 GB",
                badge: "Balanced",
                description: "Higher-accuracy English-only Whisper model with a strong quality-to-speed balance.",
                accuracy: 4,
                speed: 4
            ),
            TranscriptionModelDescriptor(
                id: "whisperkit-medium-multilingual",
                displayName: "Whisper Medium Multi",
                modelName: "medium",
                backend: .whisperKitCoreML,
                languageSupport: .multilingual,
                downloadSize: "~1.53 GB",
                badge: "Balanced",
                description: "Higher-accuracy multilingual Whisper model for broad language coverage on-device.",
                accuracy: 4,
                speed: 4
            ),
            TranscriptionModelDescriptor(
                id: "whisperkit-large-v3-turbo",
                displayName: "Whisper Large v3 Turbo",
                modelName: "large-v3-v20240930_turbo",
                backend: .whisperKitCoreML,
                languageSupport: .multilingual,
                downloadSize: "~1.6 GB",
                badge: "Fast large",
                description: "OpenAI Large v3 Turbo (~809M parameters). Faster than full Large v3 with strong multilingual quality on Apple Silicon.",
                accuracy: 4,
                speed: 5
            ),
            TranscriptionModelDescriptor(
                id: "whisperkit-large-v3-full",
                displayName: "Whisper Large v3 Full",
                modelName: "large-v3",
                backend: .whisperKitCoreML,
                languageSupport: .multilingual,
                downloadSize: "~3 GB",
                badge: "Best quality",
                description: "Complete Whisper Large v3 Core ML model. Highest accuracy and the most complete multilingual capabilities on-device.",
                accuracy: 5,
                speed: 2,
                isRecommended: true
            )
        ]
    )
}
