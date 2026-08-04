import Foundation

public struct ASRModelCapabilities: Codable, Equatable, Sendable {
    public var supportsAutoLanguageDetect: Bool
    public var supportedLanguageCodes: [String]
    public var supportsSpeechTranslation: Bool
    public var maxChunkSeconds: Double
    public var minOSVersion: OSVersion?
    public var approxDownloadBytes: Int64
    public var isRecommendedForPrimaryRU: Bool
    public var isRecommendedForEnDeFrEs: Bool

    public struct OSVersion: Codable, Equatable, Sendable, Comparable {
        public var majorVersion: Int
        public var minorVersion: Int
        public var patchVersion: Int

        public init(majorVersion: Int, minorVersion: Int = 0, patchVersion: Int = 0) {
            self.majorVersion = majorVersion
            self.minorVersion = minorVersion
            self.patchVersion = patchVersion
        }

        public static func < (lhs: OSVersion, rhs: OSVersion) -> Bool {
            if lhs.majorVersion != rhs.majorVersion {
                return lhs.majorVersion < rhs.majorVersion
            }
            if lhs.minorVersion != rhs.minorVersion {
                return lhs.minorVersion < rhs.minorVersion
            }
            return lhs.patchVersion < rhs.patchVersion
        }

        public var foundationVersion: OperatingSystemVersion {
            OperatingSystemVersion(
                majorVersion: majorVersion,
                minorVersion: minorVersion,
                patchVersion: patchVersion
            )
        }
    }

    public init(
        supportsAutoLanguageDetect: Bool,
        supportedLanguageCodes: [String],
        supportsSpeechTranslation: Bool,
        maxChunkSeconds: Double,
        minOSVersion: OSVersion? = nil,
        approxDownloadBytes: Int64,
        isRecommendedForPrimaryRU: Bool = false,
        isRecommendedForEnDeFrEs: Bool = false
    ) {
        self.supportsAutoLanguageDetect = supportsAutoLanguageDetect
        self.supportedLanguageCodes = supportedLanguageCodes
        self.supportsSpeechTranslation = supportsSpeechTranslation
        self.maxChunkSeconds = maxChunkSeconds
        self.minOSVersion = minOSVersion
        self.approxDownloadBytes = approxDownloadBytes
        self.isRecommendedForPrimaryRU = isRecommendedForPrimaryRU
        self.isRecommendedForEnDeFrEs = isRecommendedForEnDeFrEs
    }
}

public struct TranscriptionModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    public enum Backend: String, Codable, Equatable, Sendable {
        case whisperKitCoreML
        case fluidAudioCoreML
        case canaryCoreML
        case gigaAMCoreML

        public var runtimeBadge: String {
            switch self {
            case .whisperKitCoreML:
                "WhisperKit · Core ML"
            case .fluidAudioCoreML:
                "FluidAudio · Core ML/ANE"
            case .canaryCoreML:
                "Canary · Core ML/ANE"
            case .gigaAMCoreML:
                "GigaAM · Core ML/ANE"
            }
        }
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
    public var capabilities: ASRModelCapabilities

    public var modelFolderName: String {
        switch backend {
        case .whisperKitCoreML:
            "openai_whisper-\(modelName)"
        case .fluidAudioCoreML, .canaryCoreML, .gigaAMCoreML:
            modelName
        }
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
        isRecommended: Bool = false,
        capabilities: ASRModelCapabilities? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.modelName = modelName
        self.modelRepositoryID = modelRepositoryID
        self.snapshotGlob = snapshotGlob ?? (backend == .whisperKitCoreML ? "openai_whisper-\(modelName)/**" : "**")
        self.backend = backend
        self.languageSupport = languageSupport
        self.downloadSize = downloadSize
        self.badge = badge
        self.description = description
        self.accuracy = Self.clampRating(accuracy)
        self.speed = Self.clampRating(speed)
        self.isRecommended = isRecommended
        self.capabilities = capabilities ?? Self.defaultCapabilities(
            backend: backend,
            languageSupport: languageSupport,
            downloadSize: downloadSize
        )
    }

    private static func defaultCapabilities(
        backend: Backend,
        languageSupport: LanguageSupport,
        downloadSize: String
    ) -> ASRModelCapabilities {
        switch backend {
        case .whisperKitCoreML:
            let isMulti = languageSupport == .multilingual
            return ASRModelCapabilities(
                supportsAutoLanguageDetect: isMulti,
                supportedLanguageCodes: isMulti ? ["auto", "en", "de", "fr", "es", "ru"] : ["en"],
                supportsSpeechTranslation: false,
                maxChunkSeconds: 30.0,
                approxDownloadBytes: estimateBytes(from: downloadSize),
                isRecommendedForPrimaryRU: false,
                isRecommendedForEnDeFrEs: false
            )
        case .fluidAudioCoreML:
            return ASRModelCapabilities(
                supportsAutoLanguageDetect: true,
                supportedLanguageCodes: ["auto", "en", "de", "fr", "es", "nl", "ru", "uk"],
                supportsSpeechTranslation: false,
                maxChunkSeconds: 30.0,
                approxDownloadBytes: estimateBytes(from: downloadSize),
                isRecommendedForPrimaryRU: false,
                isRecommendedForEnDeFrEs: false
            )
        case .canaryCoreML:
            return ASRModelCapabilities(
                supportsAutoLanguageDetect: false,
                supportedLanguageCodes: ["en", "de", "fr", "es"],
                supportsSpeechTranslation: true,
                maxChunkSeconds: 15.0,
                approxDownloadBytes: estimateBytes(from: downloadSize),
                isRecommendedForPrimaryRU: false,
                isRecommendedForEnDeFrEs: false
            )
        case .gigaAMCoreML:
            return ASRModelCapabilities(
                supportsAutoLanguageDetect: false,
                supportedLanguageCodes: ["ru"],
                supportsSpeechTranslation: false,
                maxChunkSeconds: 30.0,
                approxDownloadBytes: estimateBytes(from: downloadSize),
                isRecommendedForPrimaryRU: true,
                isRecommendedForEnDeFrEs: false
            )
        }
    }

    private static func estimateBytes(from downloadSize: String) -> Int64 {
        let cleaned = downloadSize.replacingOccurrences(of: "~", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.components(separatedBy: " ")
        guard parts.count >= 2, let value = Double(parts[0]) else { return 500_000_000 }
        let unit = parts[1].uppercased()
        if unit.contains("GB") {
            return Int64(value * 1_000_000_000)
        } else if unit.contains("MB") {
            return Int64(value * 1_000_000)
        }
        return Int64(value)
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
    static let nativeWhisperKit: TranscriptionModelCatalog = {
        do { return try TranscriptionModelCatalog(
        models: [
            TranscriptionModelDescriptor(
                id: "parakeet-tdt-06b-v3",
                displayName: "Parakeet TDT 0.6B v3",
                modelName: "parakeet-tdt-0.6b-v3",
                modelRepositoryID: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
                snapshotGlob: "**",
                backend: .fluidAudioCoreML,
                languageSupport: .multilingual,
                downloadSize: "~482 MB",
                badge: "Fastest",
                description: "High-throughput Parakeet v3 for 25 European languages, including English, Dutch, Russian, and Ukrainian. Runs locally through Core ML on Apple Neural Engine.",
                accuracy: 4,
                speed: 5
            ),
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
            ),
            TranscriptionModelDescriptor(
                id: "canary-180m-flash-coreml",
                displayName: "Canary Flash (EN/DE/FR/ES)",
                modelName: "canary-180m-flash-coreml",
                modelRepositoryID: "nvidia/canary-180m-flash",
                snapshotGlob: "**",
                backend: .canaryCoreML,
                languageSupport: .multilingual,
                downloadSize: "~180 MB",
                badge: "Compact · 4 languages",
                description: "Compact fast Canary Flash model (~182M parameters) for English, German, French, and Spanish speech recognition and translation on Core ML.",
                accuracy: 4,
                speed: 5,
                capabilities: ASRModelCapabilities(
                    supportsAutoLanguageDetect: false,
                    supportedLanguageCodes: ["en", "de", "fr", "es"],
                    supportsSpeechTranslation: true,
                    maxChunkSeconds: 10.0,
                    minOSVersion: nil,
                    approxDownloadBytes: 180_000_000,
                    isRecommendedForPrimaryRU: false,
                    isRecommendedForEnDeFrEs: true
                )
            ),
            TranscriptionModelDescriptor(
                id: "canary-1b-v2-coreml",
                displayName: "Canary 1B v2",
                modelName: "canary-1b-v2-coreml",
                modelRepositoryID: "bolabol-canary-1b-v2-coreml-r1",
                snapshotGlob: "**",
                backend: .canaryCoreML,
                languageSupport: .multilingual,
                downloadSize: "~573 MB",
                badge: "Multilingual · macOS 15+",
                description: "Canary 1B v2 Core ML int4 package for Apple Neural Engine on macOS 15+. Verified English ASR and speech translation.",
                accuracy: 4,
                speed: 4,
                capabilities: ASRModelCapabilities(
                    supportsAutoLanguageDetect: false,
                    supportedLanguageCodes: ["en", "fr"],
                    supportsSpeechTranslation: true,
                    maxChunkSeconds: 15.0,
                    minOSVersion: ASRModelCapabilities.OSVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0),
                    approxDownloadBytes: 573_000_000,
                    isRecommendedForPrimaryRU: false,
                    isRecommendedForEnDeFrEs: false
                )
            ),
            TranscriptionModelDescriptor(
                id: "gigaam-v3-rnnt-coreml",
                displayName: "GigaAM v3 (Russian)",
                modelName: "gigaam-v3-rnnt-coreml",
                modelRepositoryID: "salute-developers/gigaam-v3",
                snapshotGlob: "**",
                backend: .gigaAMCoreML,
                languageSupport: .multilingual,
                downloadSize: "~450 MB",
                badge: "RU recommended",
                description: "High-accuracy offline Russian ASR model based on GigaAM v3 RNNT architecture on Apple Neural Engine.",
                accuracy: 5,
                speed: 5,
                capabilities: ASRModelCapabilities(
                    supportsAutoLanguageDetect: false,
                    supportedLanguageCodes: ["ru"],
                    supportsSpeechTranslation: false,
                    maxChunkSeconds: 30.0,
                    minOSVersion: nil,
                    approxDownloadBytes: 450_000_000,
                    isRecommendedForPrimaryRU: true,
                    isRecommendedForEnDeFrEs: false
                )
            )
        ]
    )
    } catch {
        fatalError("Native WhisperKit catalog has duplicate model IDs: \(error)")
    }
}()
}
