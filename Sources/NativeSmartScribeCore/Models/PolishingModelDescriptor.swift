import Foundation

public struct PolishingModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    public enum Backend: String, Codable, Equatable, Sendable {
        case mlxSwiftLLM
    }

    public var id: String
    public var displayName: String
    public var repositoryID: String
    public var revision: String
    public var backend: Backend
    public var downloadSize: String
    public var badge: String?
    public var description: String
    public var quality: Int
    public var speed: Int
    public var isRecommended: Bool
    public var extraEOSTokens: [String]
    public var isCustom: Bool
    public var localDirectoryURL: URL?

    public var huggingFaceCacheFolderName: String {
        "models--\(repositoryID.replacingOccurrences(of: "/", with: "--"))"
    }

    /// True when the model is a "thinking"/reasoning fine-tune (e.g. Qwopus,
    /// Opus distills). These models emit a chain-of-thought that can leak into
    /// the polished result and make them slower and less reliable for the
    /// short, deterministic polishing task. The UI uses this to warn the user
    /// and recommend a non-reasoning instruct model instead. Mirrors the
    /// detection in the MLX polish worker and LocalMLXModelCompatibility.
    public var isReasoningModel: Bool {
        let haystack = [displayName, repositoryID, description]
            .joined(separator: " ")
            .lowercased()

        return haystack.contains("qwopus")
            || haystack.contains("gemopus")
            || haystack.contains("reasoning")
            || haystack.contains("opus")
            || (haystack.contains("qwen") && haystack.contains("think"))
    }

    public init(
        id: String,
        displayName: String,
        repositoryID: String,
        revision: String = "main",
        backend: Backend,
        downloadSize: String,
        badge: String? = nil,
        description: String,
        quality: Int,
        speed: Int,
        isRecommended: Bool = false,
        extraEOSTokens: [String] = [],
        isCustom: Bool = false,
        localDirectoryURL: URL? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.repositoryID = repositoryID
        self.revision = revision
        self.backend = backend
        self.downloadSize = downloadSize
        self.badge = badge
        self.description = description
        self.quality = Self.clampRating(quality)
        self.speed = Self.clampRating(speed)
        self.isRecommended = isRecommended
        self.extraEOSTokens = extraEOSTokens
        self.isCustom = isCustom
        self.localDirectoryURL = localDirectoryURL
    }

    private static func clampRating(_ rating: Int) -> Int {
        min(max(rating, 1), 5)
    }
}

public enum PolishingModelCatalogError: Error, Equatable, Sendable {
    case duplicateModelID(String)
}

public struct PolishingModelCatalog: Equatable, Sendable {
    public var models: [PolishingModelDescriptor]

    public init(models: [PolishingModelDescriptor]) throws {
        var seenIDs = Set<String>()
        for model in models {
            guard seenIDs.insert(model.id).inserted else {
                throw PolishingModelCatalogError.duplicateModelID(model.id)
            }
        }

        self.models = models
    }

    public var defaultModel: PolishingModelDescriptor? {
        models.first { $0.isRecommended } ?? models.first
    }

    public func model(withID id: String?) -> PolishingModelDescriptor? {
        guard let id else { return nil }
        return models.first { $0.id == id }
    }
}

public extension PolishingModelCatalog {
    static let nativeMLX = try! PolishingModelCatalog(
        models: [
            PolishingModelDescriptor(
                id: "qwen35-08b-4bit",
                displayName: "Qwen 3.5 0.8B 4-bit",
                repositoryID: "mlx-community/Qwen3.5-0.8B-4bit",
                backend: .mlxSwiftLLM,
                downloadSize: "~0.65 GB",
                badge: "Tiny",
                description: "Ultra-light Qwen 3.5 for quick tests and low-memory Macs.",
                quality: 2,
                speed: 5
            ),
            PolishingModelDescriptor(
                id: "qwen35-2b-4bit",
                displayName: "Qwen 3.5 2B 4-bit",
                repositoryID: "mlx-community/Qwen3.5-2B-4bit",
                backend: .mlxSwiftLLM,
                downloadSize: "~1.72 GB",
                badge: "Fast",
                description: "Fast, light Qwen 3.5 for quick polishing passes.",
                quality: 3,
                speed: 5
            ),
            PolishingModelDescriptor(
                id: "qwen35-4b-4bit",
                displayName: "Qwen 3.5 4B 4-bit",
                repositoryID: "mlx-community/Qwen3.5-4B-4bit",
                backend: .mlxSwiftLLM,
                downloadSize: "~3.03 GB",
                badge: "Recommended",
                description: "Balanced default for Russian/English polishing on Apple Silicon.",
                quality: 4,
                speed: 4,
                isRecommended: true
            ),
            PolishingModelDescriptor(
                id: "qwen35-9b-4bit",
                displayName: "Qwen 3.5 9B 4-bit",
                repositoryID: "mlx-community/Qwen3.5-9B-4bit",
                backend: .mlxSwiftLLM,
                downloadSize: "~5.95 GB",
                badge: "Quality",
                description: "Highest-quality option within the 9B cap.",
                quality: 5,
                speed: 2
            ),
            PolishingModelDescriptor(
                id: "nemotron3-nano-4b-4bit",
                displayName: "NVIDIA Nemotron-3 Nano 4B",
                repositoryID: "mlx-community/NVIDIA-Nemotron-3-Nano-4B-4bit",
                backend: .mlxSwiftLLM,
                downloadSize: "~2.24 GB",
                badge: "NVIDIA",
                description: "Strong compact NVIDIA model. Verified working via local scan.",
                quality: 4,
                speed: 4
            )
        ]
    )
}
