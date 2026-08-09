import Foundation

// LASR-01 owns model metadata only. Download, presence, engine and UI layers
// must consume these contracts later without moving metadata into settings.
/// Native ASR backend identity used by the catalog and future router.
public enum LocalASRBackend: String, Codable, Equatable, Sendable {
    case whisperKitCoreML
    case fluidAudioCoreML
    case canaryCoreML
}

/// Persist-free capability data used for language and OS preflight.
public struct LocalASRCapabilities: Codable, Equatable, Sendable {
    public var supportsAutoLanguageDetect: Bool
    public var supportedLanguageCodes: [String]
    public var maxEngineWindowSeconds: Double
    public var minimumMacOSMajor: Int?
    public var approximateDownloadBytes: Int64

    public init(
        supportsAutoLanguageDetect: Bool,
        supportedLanguageCodes: [String],
        maxEngineWindowSeconds: Double,
        minimumMacOSMajor: Int? = nil,
        approximateDownloadBytes: Int64
    ) {
        self.supportsAutoLanguageDetect = supportsAutoLanguageDetect
        self.supportedLanguageCodes = supportedLanguageCodes
        self.maxEngineWindowSeconds = maxEngineWindowSeconds
        self.minimumMacOSMajor = minimumMacOSMajor
        self.approximateDownloadBytes = approximateDownloadBytes
    }

    public func supportsSourceLanguage(_ languageCode: String) -> Bool {
        let normalized = languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if normalized == "auto" {
            return supportsAutoLanguageDetect
        }
        return supportedLanguageCodes.contains(normalized)
    }

    public func isAvailable(onMacOSMajor major: Int) -> Bool {
        guard let minimumMacOSMajor else { return true }
        return major >= minimumMacOSMajor
    }
}

/// Required model files or an SDK-owned completeness check for an install.
public struct LocalASRRequiredLayout: Codable, Equatable, Sendable {
    public var requiredRelativePaths: [String]
    public var isSDKManaged: Bool

    public init(
        requiredRelativePaths: [String] = [],
        isSDKManaged: Bool = false
    ) {
        self.requiredRelativePaths = requiredRelativePaths
        self.isSDKManaged = isSDKManaged
    }

    public var requiredFiles: [String] {
        requiredRelativePaths
    }
}

/// Optional integrity metadata for one file in a remote model package.
public struct RemoteModelPackageFile: Codable, Equatable, Sendable {
    public var relativePath: String
    public var expectedByteCount: Int64?
    public var expectedSHA256: String?

    public init(
        relativePath: String,
        expectedByteCount: Int64? = nil,
        expectedSHA256: String? = nil
    ) {
        self.relativePath = relativePath
        self.expectedByteCount = expectedByteCount
        self.expectedSHA256 = expectedSHA256
    }
}

/// Release metadata resolved by a later installer; LASR-01 may leave it unbound.
public struct RemoteModelPackageRelease: Codable, Equatable, Sendable {
    public var packageID: String
    public var layoutVersion: String
    public var directURLOverrideEnvironmentKey: String?
    public var baseURLEnvironmentKey: String?
    public var relativeArchivePath: String?
    public var expectedArchiveSHA256: String?
    public var expectedCompressedSizeBytes: Int64?
    public var expectedUncompressedSizeBytes: Int64?
    public var allowlistedFiles: [RemoteModelPackageFile]

    public init(
        packageID: String,
        layoutVersion: String,
        directURLOverrideEnvironmentKey: String? = nil,
        baseURLEnvironmentKey: String? = nil,
        relativeArchivePath: String? = nil,
        expectedArchiveSHA256: String? = nil,
        expectedCompressedSizeBytes: Int64? = nil,
        expectedUncompressedSizeBytes: Int64? = nil,
        allowlistedFiles: [RemoteModelPackageFile] = []
    ) {
        self.packageID = packageID
        self.layoutVersion = layoutVersion
        self.directURLOverrideEnvironmentKey = directURLOverrideEnvironmentKey
        self.baseURLEnvironmentKey = baseURLEnvironmentKey
        self.relativeArchivePath = relativeArchivePath
        self.expectedArchiveSHA256 = expectedArchiveSHA256
        self.expectedCompressedSizeBytes = expectedCompressedSizeBytes
        self.expectedUncompressedSizeBytes = expectedUncompressedSizeBytes
        self.allowlistedFiles = allowlistedFiles
    }

    // LASR-01 deliberately carries no concrete URL, digest or package manifest.
    public static let canaryOneBPlaceholder = RemoteModelPackageRelease(
        packageID: "canary-1b-v2-coreml",
        layoutVersion: "path-b-v1",
        directURLOverrideEnvironmentKey: "VANISCRIPT_CANARY_1B_PACKAGE_URL",
        baseURLEnvironmentKey: "VANISCRIPT_MODEL_PACKAGE_BASE_URL"
    )
}

/// Download origin contract kept separate from backend and persisted state.
public enum LocalASRInstallSource: Codable, Equatable, Sendable {
    case whisperKit(repositoryID: String, subfolder: String)
    case fluidAudio(version: String, encoderPrecision: String)
    case huggingFace(repositoryID: String, revision: String)
    case remotePackage(RemoteModelPackageRelease)

    public enum Kind: String, Codable, Equatable, Sendable {
        case whisperKit
        case fluidAudio
        case huggingFace
        case remotePackage
    }

    public var kind: Kind {
        switch self {
        case .whisperKit: .whisperKit
        case .fluidAudio: .fluidAudio
        case .huggingFace: .huggingFace
        case .remotePackage: .remotePackage
        }
    }
}

/// Single non-persisted source of local ASR metadata.
public struct LocalASRModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var backend: LocalASRBackend
    public var installSource: LocalASRInstallSource
    public var relativeStorageSubpath: String
    public var capabilities: LocalASRCapabilities
    public var requiredLayout: LocalASRRequiredLayout

    public init(
        id: String,
        displayName: String,
        backend: LocalASRBackend,
        installSource: LocalASRInstallSource,
        relativeStorageSubpath: String,
        capabilities: LocalASRCapabilities,
        requiredLayout: LocalASRRequiredLayout
    ) {
        self.id = id
        self.displayName = displayName
        self.backend = backend
        self.installSource = installSource
        self.relativeStorageSubpath = relativeStorageSubpath
        self.capabilities = capabilities
        self.requiredLayout = requiredLayout
    }
}

public struct LocalModelVerification {
    public static nonisolated(unsafe) var skipVerificationForTesting: Bool = false

    public static func verifyModelPath(_ path: String?, isWhisper: Bool) -> Bool {
        if skipVerificationForTesting {
            return true
        }
        guard let path = path, !path.isEmpty else { return false }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return false
        }
        if isWhisper {
            return canonicalWhisperKitModelPath(path) != nil
        }
        guard isDir.boolValue else { return false }
        return isMLXModelDirectory(path, fileManager: fm)
    }

    public static func verifyTranslationModelPath(_ path: String?, modelID: String) -> Bool {
        guard expectedMLXPathMarkers[modelID] != nil else { return false }
        if skipVerificationForTesting {
            return !containsKnownUnsupportedMLXMarker(path)
        }
        guard let path, !path.isEmpty else { return false }
        guard !isKnownUnsupportedMLXPath(path) else { return false }
        guard verifyModelPath(path, isWhisper: false) else { return false }
        return pathMatchesExpectedMLXModelID(path, modelID: modelID)
    }

    public static func canonicalWhisperKitModelPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        if isWhisperKitModelDirectory(path, fileManager: fm) {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
        }

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path, isDirectory: true),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard isLikelyWhisperKitModelFolderName(url.lastPathComponent) else { continue }
            if isWhisperKitModelDirectory(url.path, fileManager: fm) {
                return url.standardizedFileURL.resolvingSymlinksInPath().path
            }
        }
        return nil
    }

    private static func isWhisperKitModelDirectory(_ path: String, fileManager: FileManager) -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else { return false }
        let visible = contents.filter { !$0.hasPrefix(".") }
        guard !visible.isEmpty else { return false }

        let hasCompiledModel = visible.contains { $0.hasSuffix(".mlmodelc") }
        guard hasCompiledModel else { return false }

        let hasWhisperMetadata = visible.contains { name in
            let lower = name.lowercased()
            return lower == "config.json"
                || lower == "generation_config.json"
                || lower == "tokenizer.json"
                || lower == "tokenizer_config.json"
                || lower.hasSuffix(".json")
        }
        return hasWhisperMetadata || visible.filter { $0.hasSuffix(".mlmodelc") }.count >= 2
    }

    private static func isLikelyWhisperKitModelFolderName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("openai_whisper-")
            || lower.contains("whisperkit")
            || lower.contains("whisper")
    }

    private static func hasMLXFilesDeep(atPath path: String) -> Bool {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return false }
        for case let subpath as String in enumerator {
            let lower = subpath.lowercased()
            if lower.hasSuffix(".npz") || lower.hasSuffix(".safetensors") || lower.contains("weights") {
                return true
            }
        }
        return false
    }

    private static func isMLXModelDirectory(_ path: String, fileManager: FileManager) -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else { return false }
        let visible = contents.filter { !$0.hasPrefix(".") }.map { $0.lowercased() }
        guard !visible.isEmpty else { return false }

        let hasConfig = visible.contains("config.json")
        let hasTokenizer = visible.contains("tokenizer.json")
            || visible.contains("tokenizer_config.json")
            || visible.contains("tokenizer.model")
        let hasWeights = visible.contains {
            $0.hasSuffix(".safetensors")
                || $0.hasSuffix(".npz")
                || $0.hasSuffix(".bin")
                || $0 == "model.safetensors.index.json"
                || $0.contains("weights")
        } || hasMLXFilesDeep(atPath: path)

        return hasConfig && hasTokenizer && hasWeights
    }

    private static let expectedMLXPathMarkers: [String: [String]] = [
        "qwen35-08b-4bit": ["qwen35-08b-4bit", "qwen3.5-0.8b-4bit"],
        "qwen35-2b-4bit": ["qwen35-2b-4bit", "qwen3.5-2b-4bit"],
        "qwen35-4b-4bit": ["qwen35-4b-4bit", "qwen3.5-4b-4bit"],
        "qwen35-9b-4bit": ["qwen35-9b-4bit", "qwen3.5-9b-4bit"],
        "nemotron3-nano-4b-4bit": [
            "nemotron3-nano-4b-4bit",
            "nemotron-3-nano-4b-4bit",
            "nvidia-nemotron-3-nano-4b-4bit"
        ]
    ]

    private static func isKnownUnsupportedMLXPath(_ path: String) -> Bool {
        containsKnownUnsupportedMLXMarker(path)
    }

    private static func containsKnownUnsupportedMLXMarker(_ path: String?) -> Bool {
        guard let path else { return false }
        let normalized = path.lowercased()
        let unsupportedMarkers = ["opt" + "iq"]
        return unsupportedMarkers.contains { normalized.contains($0) }
    }

    private static func pathMatchesExpectedMLXModelID(_ path: String, modelID: String) -> Bool {
        let normalized = path.lowercased()
        return expectedMLXPathMarkers[modelID]?.contains { normalized.contains($0) } ?? false
    }
}

public struct ActiveWhisperKitModel: Codable, Equatable, Sendable {
    public var id: String
    public var variant: String
    public var path: String
    public var label: String
}

public struct ActiveMLXModel: Codable, Equatable, Sendable {
    public var id: String
    public var path: String
    public var label: String
}

public enum NativeModelCatalog {
    public static let parakeetLanguageCodes = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de",
        "el", "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro", "sk",
        "sl", "es", "sv", "ru", "uk"
    ]

    public static let canaryFlashLanguageCodes = ["en", "de", "fr", "es"]

    private static let canaryFlashRevision = "ca44e0f5d816a2362cf01f7316e4932c86aafef6"

    // These are the only new ASR descriptors in LASR-01. Whisper descriptors
    // below retain the existing six model IDs as regression-visible metadata.
    public static let newLocalASRModelDescriptors: [LocalASRModelDescriptor] = [
        LocalASRModelDescriptor(
            id: "parakeet-tdt-06b-v3",
            displayName: "Parakeet TDT 0.6B v3",
            backend: .fluidAudioCoreML,
            installSource: .fluidAudio(version: "v3", encoderPrecision: "int8"),
            relativeStorageSubpath: "parakeet/parakeet-tdt-0.6b-v3",
            capabilities: LocalASRCapabilities(
                supportsAutoLanguageDetect: true,
                supportedLanguageCodes: parakeetLanguageCodes,
                maxEngineWindowSeconds: 30,
                approximateDownloadBytes: 482_000_000
            ),
            requiredLayout: LocalASRRequiredLayout(isSDKManaged: true)
        ),
        LocalASRModelDescriptor(
            id: "canary-180m-flash-coreml",
            displayName: "Canary Flash 180M",
            backend: .canaryCoreML,
            installSource: .huggingFace(
                repositoryID: "aufklarer/Canary-180M-Flash-CoreML",
                revision: canaryFlashRevision
            ),
            relativeStorageSubpath: "canary/180m-flash",
            capabilities: LocalASRCapabilities(
                supportsAutoLanguageDetect: false,
                supportedLanguageCodes: canaryFlashLanguageCodes,
                maxEngineWindowSeconds: 10,
                approximateDownloadBytes: 180_000_000
            ),
            requiredLayout: LocalASRRequiredLayout(requiredRelativePaths: [
                "CanaryEncoder.mlmodelc",
                "CanaryPrefill.mlmodelc",
                "CanaryDecoder.mlmodelc",
                "config.json",
                "vocab.json"
            ])
        ),
        LocalASRModelDescriptor(
            id: "canary-1b-v2-coreml",
            displayName: "Canary 1B v2",
            backend: .canaryCoreML,
            installSource: .remotePackage(.canaryOneBPlaceholder),
            relativeStorageSubpath: "canary/1b-v2",
            capabilities: LocalASRCapabilities(
                supportsAutoLanguageDetect: false,
                supportedLanguageCodes: parakeetLanguageCodes,
                maxEngineWindowSeconds: 15,
                minimumMacOSMajor: 15,
                approximateDownloadBytes: 1_884_267_035
            ),
            requiredLayout: LocalASRRequiredLayout(requiredRelativePaths: [
                "canary_encoder.mlmodelc",
                "canary_cross_kv.mlmodelc",
                "canary_decoder_kv.mlmodelc",
                "canary_spe.model"
            ])
        )
    ]

    public static let whisperKitModelDescriptors: [LocalASRModelDescriptor] = [
        whisperDescriptor(
            id: "whisper-small-en",
            displayName: "Whisper Small English",
            subfolder: "openai_whisper-small.en/",
            supportsAutoLanguageDetect: false,
            supportedLanguageCodes: ["en"],
            approximateDownloadBytes: 487_000_000
        ),
        whisperDescriptor(
            id: "whisper-small-multilingual",
            displayName: "Whisper Small Multilingual",
            subfolder: "openai_whisper-small/",
            supportsAutoLanguageDetect: true,
            supportedLanguageCodes: parakeetLanguageCodes,
            approximateDownloadBytes: 486_000_000
        ),
        whisperDescriptor(
            id: "whisper-medium-en",
            displayName: "Whisper Medium English",
            subfolder: "openai_whisper-medium.en/",
            supportsAutoLanguageDetect: false,
            supportedLanguageCodes: ["en"],
            approximateDownloadBytes: 1_530_000_000
        ),
        whisperDescriptor(
            id: "whisper-medium-multilingual",
            displayName: "Whisper Medium Multilingual",
            subfolder: "openai_whisper-medium/",
            supportsAutoLanguageDetect: true,
            supportedLanguageCodes: parakeetLanguageCodes,
            approximateDownloadBytes: 1_530_000_000
        ),
        whisperDescriptor(
            id: "whisper-large-v3-turbo",
            displayName: "Whisper Large v3 Turbo",
            subfolder: "openai_whisper-large-v3-v20240930_turbo_632MB/",
            supportsAutoLanguageDetect: true,
            supportedLanguageCodes: parakeetLanguageCodes,
            approximateDownloadBytes: 1_600_000_000
        ),
        whisperDescriptor(
            id: "whisper-large-v3",
            displayName: "Whisper Large v3",
            subfolder: "openai_whisper-large-v3-v20240930_626MB/",
            supportsAutoLanguageDetect: true,
            supportedLanguageCodes: parakeetLanguageCodes,
            approximateDownloadBytes: 3_000_000_000
        )
    ]

    public static let localASRModelDescriptors = whisperKitModelDescriptors + newLocalASRModelDescriptors
    public static let localASRModels = localASRModelDescriptors

    public static func descriptor(for id: String) -> LocalASRModelDescriptor? {
        localASRModelDescriptors.first { $0.id == id }
    }

    public static func localASRModel(for id: String) -> LocalASRModelDescriptor? {
        descriptor(for: id)
    }

    private static func whisperDescriptor(
        id: String,
        displayName: String,
        subfolder: String,
        supportsAutoLanguageDetect: Bool,
        supportedLanguageCodes: [String],
        approximateDownloadBytes: Int64
    ) -> LocalASRModelDescriptor {
        LocalASRModelDescriptor(
            id: id,
            displayName: displayName,
            backend: .whisperKitCoreML,
            installSource: .whisperKit(
                repositoryID: "argmaxinc/whisperkit-coreml",
                subfolder: subfolder
            ),
            relativeStorageSubpath: "whisperkit/\(id)",
            capabilities: LocalASRCapabilities(
                supportsAutoLanguageDetect: supportsAutoLanguageDetect,
                supportedLanguageCodes: supportedLanguageCodes,
                maxEngineWindowSeconds: 30,
                approximateDownloadBytes: approximateDownloadBytes
            ),
            requiredLayout: LocalASRRequiredLayout()
        )
    }

    public static func whisperKitVariant(for id: String) -> String? {
        switch id {
        case "whisper-medium-en":
            "medium.en"
        case "whisper-medium-multilingual":
            "medium"
        case "whisper-large-v3":
            "large-v3-v20240930_626MB"
        case "whisper-large-v3-turbo":
            "large-v3-v20240930_turbo_632MB"
        case "whisper-small-en":
            "small.en"
        case "whisper-small-multilingual":
            "small"
        default:
            nil
        }
    }

    public static func activeWhisperKitModel(settings: AppSettings, providerID: String) -> ActiveWhisperKitModel? {
        let candidateIDs: [String]
        if providerID == "coreml-whisperkit" {
            candidateIDs = settings.localAsrModels.keys.sorted { lhs, rhs in
                preferredRank(lhs) < preferredRank(rhs)
            }
        } else {
            candidateIDs = [providerID]
        }

        for id in candidateIDs {
            guard let model = settings.localAsrModels[id],
                  model.status == .downloaded,
                  model.runtime == .whisper,
                  let path = model.path,
                  !path.isEmpty,
                  LocalModelVerification.verifyModelPath(path, isWhisper: true),
                  let variant = whisperKitVariant(for: id)
            else {
                continue
            }
            return ActiveWhisperKitModel(id: id, variant: variant, path: path, label: model.label)
        }
        return nil
    }

    public static func activeMLXModel(settings: AppSettings, providerID: String) -> ActiveMLXModel? {
        let candidateIDs: [String]
        if providerID == "mlx-native" || providerID.isEmpty {
            candidateIDs = settings.localTranslationModels.keys.sorted { lhs, rhs in
                preferredMLXRank(lhs) < preferredMLXRank(rhs)
            }
        } else {
            candidateIDs = [providerID]
        }

        for id in candidateIDs {
            guard let model = settings.localTranslationModels[id],
                  model.status == .downloaded,
                  model.runtime == .mlx,
                  let path = model.path,
                  !path.isEmpty,
                  LocalModelVerification.verifyTranslationModelPath(path, modelID: id)
            else {
                continue
            }
            return ActiveMLXModel(id: id, path: path, label: model.label)
        }
        return nil
    }

    private static func preferredRank(_ id: String) -> Int {
        switch id {
        case "whisper-large-v3":
            0
        case "whisper-large-v3-turbo":
            1
        case "whisper-medium-en":
            2
        case "whisper-medium-multilingual":
            3
        case "whisper-small-multilingual":
            4
        case "whisper-small-en":
            5
        default:
            10
        }
    }

    private static func preferredMLXRank(_ id: String) -> Int {
        switch id {
        case "qwen35-9b-4bit": 0
        case "qwen35-4b-4bit": 1
        case "nemotron3-nano-4b-4bit": 2
        case "qwen35-2b-4bit": 3
        case "qwen35-08b-4bit": 4
        default: 10
        }
    }
}

public struct LocalModelScanner: Sendable {
    public struct ScannedModel: Codable, Equatable, Sendable {
        public var id: String
        public var path: String
        public var isTranslation: Bool
        public var label: String?

        public init(id: String, path: String, isTranslation: Bool, label: String? = nil) {
            self.id = id
            self.path = path
            self.isTranslation = isTranslation
            self.label = label
        }
    }

    public static func scanForLocalModels() -> [ScannedModel] {
        scanForLocalModels(searchPaths: defaultSearchPaths())
    }

    public static func scanForLocalModels(
        searchPaths: [URL],
        maxVisitedItems: Int = 250_000
    ) -> [ScannedModel] {
        let fm = FileManager.default
        var resultsByKey: [String: ScannedModel] = [:]
        var visited = 0

        let asrModels = [
            ModelPattern(id: "whisper-large-v3-turbo", patterns: ["whisperkit-large-v3-turbo", "large-v3-turbo", "large-v3-v20240930_turbo_632mb"]),
            ModelPattern(id: "whisper-large-v3", patterns: ["whisperkit-large-v3-v20240930", "large-v3-v20240930_626mb", "whisper-large-v3"]),
            ModelPattern(id: "whisper-medium-en", patterns: ["whisperkit-medium-en", "medium.en", "whisper-medium.en", "whisper-medium-en"]),
            ModelPattern(id: "whisper-medium-multilingual", patterns: ["whisperkit-medium-multilingual", "openai_whisper-medium", "whisper-medium-multilingual", "whisper-medium"]),
            ModelPattern(id: "whisper-small-en", patterns: ["whisperkit-small-en", "small.en", "whisper-small.en", "whisper-small-en"]),
            ModelPattern(id: "whisper-small-multilingual", patterns: ["whisperkit-small-multilingual", "openai_whisper-small", "whisper-small-multilingual", "whisper-small"])
        ]

        let translationModels = [
            ModelPattern(id: "qwen35-9b-4bit", patterns: ["qwen3.5-9b"]),
            ModelPattern(id: "qwen35-4b-4bit", patterns: ["qwen3.5-4b"]),
            ModelPattern(id: "nemotron3-nano-4b-4bit", patterns: ["nemotron-3-nano-4b", "nemotron-3-nano"]),
            ModelPattern(id: "qwen35-2b-4bit", patterns: ["qwen3.5-2b"]),
            ModelPattern(id: "qwen35-08b-4bit", patterns: ["qwen3.5-0.8b"])
        ]

        func record(_ scanned: ScannedModel) {
            let key = "\(scanned.isTranslation ? "mlx" : "asr"):\(scanned.id)"
            if resultsByKey[key] == nil || scanned.path.count < resultsByKey[key]!.path.count {
                resultsByKey[key] = scanned
            }
        }

        for rawSearchPath in uniqueExistingSearchPaths(searchPaths, fileManager: fm) {
            if visited >= maxVisitedItems { break }
            let searchPath = rawSearchPath.standardizedFileURL

            if let direct = scannedModel(
                at: searchPath,
                asrModels: asrModels,
                translationModels: translationModels
            ) {
                record(direct)
            }

            guard let enumerator = fm.enumerator(
                at: searchPath,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let fileURL as URL in enumerator {
                visited += 1
                if visited >= maxVisitedItems { break }

                if shouldPrune(fileURL) {
                    enumerator.skipDescendants()
                    continue
                }

                if let scanned = scannedModel(
                    at: fileURL,
                    asrModels: asrModels,
                    translationModels: translationModels
                ) {
                    record(scanned)
                    if !scanned.isTranslation {
                        enumerator.skipDescendants()
                    }
                }
            }
        }

        return resultsByKey.values.sorted { lhs, rhs in
            if lhs.isTranslation != rhs.isTranslation {
                return !lhs.isTranslation
            }
            return lhs.id < rhs.id
        }
    }

    private struct ModelPattern {
        var id: String
        var patterns: [String]
    }

    static func defaultSearchPaths() -> [URL] {
        let fm = FileManager.default
        let libraryDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let documentsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        let homeDir = fm.homeDirectoryForCurrentUser
        let sharedDirs = SharedModelRuntime.allCases.compactMap {
            try? SharedModelsRoot.modelsDirectory(for: $0)
        }

        return sharedDirs + [
            libraryDir.appendingPathComponent("NativeSmartScribe/Models/Transcription/WhisperKit", isDirectory: true),
            libraryDir.appendingPathComponent("NativeSmartScribe/Models", isDirectory: true),
            libraryDir.appendingPathComponent("VaniScript/Models", isDirectory: true),
            libraryDir.appendingPathComponent("vaniscript/Models", isDirectory: true),
            libraryDir.appendingPathComponent("SmartScribe/Models", isDirectory: true),
            libraryDir.appendingPathComponent("smartscribe/Models", isDirectory: true),
            libraryDir.appendingPathComponent("smartscribe-app/Models", isDirectory: true),
            documentsDir.appendingPathComponent("VaniScript/Models", isDirectory: true),
            documentsDir.appendingPathComponent("huggingface/models/openai", isDirectory: true),
            documentsDir.appendingPathComponent("huggingface/models", isDirectory: true),
            documentsDir.appendingPathComponent("Models", isDirectory: true),
            homeDir.appendingPathComponent(".cache/huggingface/hub", isDirectory: true),
            homeDir.appendingPathComponent("Library/Application Support", isDirectory: true),
            documentsDir,
            URL(fileURLWithPath: "/Volumes", isDirectory: true)
        ]
    }

    private static func uniqueExistingSearchPaths(_ paths: [URL], fileManager: FileManager) -> [URL] {
        var seen = Set<String>()
        return paths.compactMap { url in
            let path = url.standardizedFileURL.path
            guard fileManager.fileExists(atPath: path), seen.insert(path).inserted else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    private static func scannedModel(
        at url: URL,
        asrModels: [ModelPattern],
        translationModels: [ModelPattern]
    ) -> ScannedModel? {
        let haystack = [url.lastPathComponent, url.path]
            .joined(separator: " ")
            .lowercased()

        for model in asrModels where model.patterns.contains(where: { haystack.contains($0) }) {
            guard let canonical = LocalModelVerification.canonicalWhisperKitModelPath(url.path),
                  LocalModelVerification.verifyModelPath(canonical, isWhisper: true)
            else { continue }
            return ScannedModel(id: model.id, path: canonical, isTranslation: false)
        }

        for model in translationModels where model.patterns.contains(where: { haystack.contains($0) }) {
            guard LocalModelVerification.verifyTranslationModelPath(url.path, modelID: model.id) else { continue }
            return ScannedModel(id: model.id, path: url.path, isTranslation: true)
        }

        return nil
    }

    private static func shouldPrune(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".mlmodelc") {
            return true
        }
        return [
            ".git",
            ".build",
            "node_modules",
            "deriveddata",
            "target",
            "tmp",
            "temp",
            "caches",
            "trash",
            "zoom.us",
            "mobile documents"
        ].contains(name)
    }
}
