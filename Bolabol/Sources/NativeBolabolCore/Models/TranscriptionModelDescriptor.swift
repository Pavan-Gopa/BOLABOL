import Foundation

public enum CanaryLanguageCatalog {
    /// NVIDIA Canary 1B v2 ASR language set from the upstream model card.
    public static let oneBV2LanguageCodes = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de",
        "el", "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro", "sk",
        "sl", "es", "sv", "ru", "uk"
    ]

    public static let flashLanguageCodes = ["en", "de", "fr", "es"]

}

public struct ASRModelCapabilities: Codable, Equatable, Sendable {
    public var supportsAutoLanguageDetect: Bool
    public var supportedLanguageCodes: [String]
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
        maxChunkSeconds: Double,
        minOSVersion: OSVersion? = nil,
        approxDownloadBytes: Int64,
        isRecommendedForPrimaryRU: Bool = false,
        isRecommendedForEnDeFrEs: Bool = false
    ) {
        self.supportsAutoLanguageDetect = supportsAutoLanguageDetect
        self.supportedLanguageCodes = supportedLanguageCodes
        self.maxChunkSeconds = maxChunkSeconds
        self.minOSVersion = minOSVersion
        self.approxDownloadBytes = approxDownloadBytes
        self.isRecommendedForPrimaryRU = isRecommendedForPrimaryRU
        self.isRecommendedForEnDeFrEs = isRecommendedForEnDeFrEs
    }

    private enum CodingKeys: String, CodingKey {
        case supportsAutoLanguageDetect
        case supportedLanguageCodes
        case maxChunkSeconds
        case minOSVersion
        case approxDownloadBytes
        case isRecommendedForPrimaryRU
        case isRecommendedForEnDeFrEs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            supportsAutoLanguageDetect: try container.decode(Bool.self, forKey: .supportsAutoLanguageDetect),
            supportedLanguageCodes: try container.decode([String].self, forKey: .supportedLanguageCodes),
            maxChunkSeconds: try container.decode(Double.self, forKey: .maxChunkSeconds),
            minOSVersion: try container.decodeIfPresent(OSVersion.self, forKey: .minOSVersion),
            approxDownloadBytes: try container.decode(Int64.self, forKey: .approxDownloadBytes),
            isRecommendedForPrimaryRU: try container.decodeIfPresent(Bool.self, forKey: .isRecommendedForPrimaryRU) ?? false,
            isRecommendedForEnDeFrEs: try container.decodeIfPresent(Bool.self, forKey: .isRecommendedForEnDeFrEs) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(supportsAutoLanguageDetect, forKey: .supportsAutoLanguageDetect)
        try container.encode(supportedLanguageCodes, forKey: .supportedLanguageCodes)
        try container.encode(maxChunkSeconds, forKey: .maxChunkSeconds)
        try container.encodeIfPresent(minOSVersion, forKey: .minOSVersion)
        try container.encode(approxDownloadBytes, forKey: .approxDownloadBytes)
        try container.encode(isRecommendedForPrimaryRU, forKey: .isRecommendedForPrimaryRU)
        try container.encode(isRecommendedForEnDeFrEs, forKey: .isRecommendedForEnDeFrEs)
    }
}

public extension ASRModelCapabilities {
    /// Evaluates the capability gate against an explicitly supplied OS version.
    /// The result is computed only and is never part of persisted model state.
    func isAvailable(on osVersion: OSVersion) -> Bool {
        guard let minOSVersion else { return true }
        return osVersion >= minOSVersion
    }

    /// Explicit source-language tokens, excluding the legacy `auto` token.
    var explicitSupportedLanguageCodes: [String] {
        var seen = Set<String>()
        return supportedLanguageCodes.compactMap { rawCode in
            let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !code.isEmpty, code != "auto", seen.insert(code).inserted else {
                return nil
            }
            return code
        }
    }

    /// Whether this descriptor can transcribe an explicitly selected input
    /// language. The legacy `auto` token is intentionally not treated as a
    /// concrete language capability.
    func supportsInputLanguage(_ languageCode: String) -> Bool {
        let normalized = languageCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }
        return explicitSupportedLanguageCodes.contains(normalized)
    }

}

/// Non-persisted source-language projection used by the S10 Local Models UI.
public struct ASRSourceLanguageProjection: Equatable, Sendable {
    public let effectiveChoices: [String]
    public let unsupportedConfiguredLanguages: [String]
    public let hasMissingConfiguredLanguage: Bool

    public var isHardBlocked: Bool {
        effectiveChoices.isEmpty
    }

    public var isClamped: Bool {
        effectiveChoices.count == 1
            && (!unsupportedConfiguredLanguages.isEmpty || hasMissingConfiguredLanguage)
    }

    public init(
        verifiedSourceChoices: [String],
        primary: String?,
        additional: String?
    ) {
        let verified = Set(verifiedSourceChoices.map(Self.normalize))
        var effective = [String]()
        var unsupported = [String]()
        let primaryCode = Self.normalizeOptional(primary)
        let additionalCode = Self.normalizeOptional(additional)

        if let primaryCode {
            if verified.contains(primaryCode) {
                effective = [primaryCode]
            } else {
                unsupported = [primaryCode]
            }
        } else if let additionalCode {
            unsupported = [additionalCode]
        }

        self.effectiveChoices = effective
        self.unsupportedConfiguredLanguages = unsupported
        self.hasMissingConfiguredLanguage = primaryCode == nil || additionalCode == nil
    }

    private static func normalizeOptional(_ code: String?) -> String? {
        guard let code else { return nil }
        let normalized = normalize(code)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

/// Explicit install source for transcription models (ADR-018 requirement).
/// Decouples download origins from upstream metadata repository IDs.
/// Google Drive file IDs for the Canary 1B v2 Core ML package hosted on the
/// user's shared Drive folder. Every path from the package MANIFEST.json maps
/// to a Drive file ID; downloads use the binary direct endpoint
/// (drive.usercontent.google.com), which skips the HTML virus-scan page for
/// large files.
    public enum Canary1BDriveFileIDs: Sendable {
        public static let table: [String: String] = [
            "MANIFEST.json": "14VIGcqZijS70HXnLrdvUJqRDRika6R0E",
            "metadata.json": "1Qo6Q2kq7-QhNWivD-y45cXGhlWP8aTW4",
            "FRONTEND.md": "1ipZQcYPwftb5pJTeJhhhnE8-GtVlgX_E",
            "LICENSE.txt": "1HIOaWXWXV46nG8PCB6VpsnnJ72_aLfUa",
            "canary_spe.model": "1BWzdWKht4Q4RYokkZHT8bdkvjDEpVamZ",
            "canary_encoder.mlmodelc/metadata.json": "1juR_Sn8oMwGtByK2Zfow1WtiAw_fY2KG",
            "canary_encoder.mlmodelc/model.mil": "1NZSPOtMT-8HbVQbQcn6NSz2sU5JZQIpU",
            "canary_encoder.mlmodelc/coremldata.bin": "1RlT2vAhdV_8SYCaROOzHqksNEwUp_tn4",
            "canary_encoder.mlmodelc/analytics/coremldata.bin": "1UvRRwsvb4KE0K8NVCch_V0oibRVWHIg7",
            "canary_encoder.mlmodelc/weights/weight.bin": "1qk0pioVzir39oyvJ-v09X1bFAQFuJ-Qw",
            "canary_decoder_kv.mlmodelc/metadata.json": "1LSaiXo6p8Y_h_nLC8f8uGG4x2EtrA3wY",
            "canary_decoder_kv.mlmodelc/model.mil": "13BEr3nnM1jV-FN3s96rAxMsyfl-TJ6Kl",
            "canary_decoder_kv.mlmodelc/coremldata.bin": "1-Zj-p7jkQeLs1rGaTSBUvHTnN4czkqkv",
            "canary_decoder_kv.mlmodelc/analytics/coremldata.bin": "1jqTfjWSnpYZ4Cw69KubgDm5gIyNmE-dB",
            "canary_decoder_kv.mlmodelc/weights/weight.bin": "1HLVbnd7zb0qrPMn_NDmpio3NRCO1nF72",
            "canary_cross_kv.mlmodelc/metadata.json": "1di4vhBimV8o6uJWvex4mBT7waAI_o02P",
            "canary_cross_kv.mlmodelc/model.mil": "1MNtC0ZsOEs1rDxeeCHjTdUBDicXf569o",
            "canary_cross_kv.mlmodelc/coremldata.bin": "1beAi3pOArWpCPnG33mKUbuz2lYA40_rV",
            "canary_cross_kv.mlmodelc/analytics/coremldata.bin": "1LgdqjHKkL8w2rTmJgd3snocsq4xWVG85",
            "canary_cross_kv.mlmodelc/weights/weight.bin": "1qmRo_FUiN6c9H3xRvwMWVkEJAHopq2Hv",
        ]
    }

public enum ModelInstallSource: Equatable, Sendable, Codable {
    case huggingFace(repositoryID: String)
    case bolabolCDN(packageID: String, baseURL: URL)
    case googleDrive(packageID: String, fileIDs: [String: String])
    case fluidAudio(version: String)
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

    /// Explicit ASR source choices from the model capability contract.
    public var verifiedASRSourceChoices: [String] {
        capabilities.explicitSupportedLanguageCodes
    }

    public func sourceLanguageProjection(
        primary: String?,
        additional: String?
    ) -> ASRSourceLanguageProjection {
        ASRSourceLanguageProjection(
            verifiedSourceChoices: verifiedASRSourceChoices,
            primary: primary,
            additional: additional
        )
    }

    public func effectiveCanarySourceChoices(
        primary: String?,
        additional: String?
    ) -> [String] {
        sourceLanguageProjection(primary: primary, additional: additional).effectiveChoices
    }

    public var modelFolderName: String {
        switch backend {
        case .whisperKitCoreML:
            "openai_whisper-\(modelName)"
        case .fluidAudioCoreML, .canaryCoreML, .gigaAMCoreML:
            modelName
        }
    }

    /// Configurable base URL for Bolabol CDN hosted packages.
    public static let defaultBolabolCDNBaseURL: URL = {
        if let envURLString = ProcessInfo.processInfo.environment["BOLABOL_CDN_BASE_URL"],
           let url = URL(string: envURLString) {
            return url
        }
        return URL(string: "https://cdn.bolabol.app/models/")!
    }()

    /// Resolved install source mapping per ADR-018 §2.3.
    public var installSource: ModelInstallSource {
        switch id {
        case "canary-180m-flash-coreml":
            return .huggingFace(repositoryID: "aufklarer/Canary-180M-Flash-CoreML")
        case "gigaam-v3-rnnt-coreml":
            return .huggingFace(repositoryID: "huggingfinger0/gigaam-v3-coreml")
        case "canary-1b-v2-coreml":
            return .googleDrive(
                packageID: "bolabol-canary-1b-v2-coreml-r1",
                fileIDs: Canary1BDriveFileIDs.table
            )
        default:
            if backend == .fluidAudioCoreML {
                return .fluidAudio(version: "v3")
            } else {
                return .huggingFace(repositoryID: modelRepositoryID)
            }
        }
    }

    /// Relative storage subpath under SharedModelsRoot per plan §2.3.
    public var relativeStorageSubpath: String {
        switch id {
        case "canary-1b-v2-coreml":
            return "canary/1b-v2"
        case "canary-180m-flash-coreml":
            return "canary/180m-flash"
        case "gigaam-v3-rnnt-coreml":
            return "gigaam/v3-rnnt"
        default:
            return modelFolderName
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
                supportedLanguageCodes: isMulti
                    ? ["auto"] + LanguagePickerOrder.orderedSpeechCodes
                    : ["en"],
                maxChunkSeconds: 30.0,
                approxDownloadBytes: estimateBytes(from: downloadSize),
                isRecommendedForPrimaryRU: false,
                isRecommendedForEnDeFrEs: false
            )
        case .fluidAudioCoreML:
            return ASRModelCapabilities(
                supportsAutoLanguageDetect: true,
                supportedLanguageCodes: ["auto"] + CanaryLanguageCatalog.oneBV2LanguageCodes,
                maxChunkSeconds: 30.0,
                approxDownloadBytes: estimateBytes(from: downloadSize),
                isRecommendedForPrimaryRU: false,
                isRecommendedForEnDeFrEs: false
            )
        case .canaryCoreML:
            return ASRModelCapabilities(
                supportsAutoLanguageDetect: false,
                supportedLanguageCodes: CanaryLanguageCatalog.flashLanguageCodes,
                maxChunkSeconds: 15.0,
                approxDownloadBytes: estimateBytes(from: downloadSize),
                isRecommendedForPrimaryRU: false,
                isRecommendedForEnDeFrEs: false
            )
        case .gigaAMCoreML:
            return ASRModelCapabilities(
                supportsAutoLanguageDetect: false,
                supportedLanguageCodes: ["ru"],
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
                description: "Compact fast Canary Flash model (~182M parameters) for English, German, French, and Spanish speech recognition on Core ML.",
                accuracy: 4,
                speed: 5,
                capabilities: ASRModelCapabilities(
                    supportsAutoLanguageDetect: false,
                    supportedLanguageCodes: ["en", "de", "fr", "es"],
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
                downloadSize: "~1.88 GB",
                badge: "Multilingual · macOS 15+",
                 description: "Canary 1B v2 Core ML int4 package for Apple Neural Engine on macOS 15+. Multilingual speech recognition across 25 languages with explicit source language.",
                accuracy: 4,
                speed: 4,
                capabilities: ASRModelCapabilities(
                    supportsAutoLanguageDetect: false,
                    supportedLanguageCodes: CanaryLanguageCatalog.oneBV2LanguageCodes,
                    maxChunkSeconds: 15.0,
                    minOSVersion: ASRModelCapabilities.OSVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0),
                    approxDownloadBytes: 1_884_267_035,
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
