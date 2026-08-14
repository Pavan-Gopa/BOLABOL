import CryptoKit
import Foundation

// The catalog owns native model metadata and the shared LASR-02 presence policy.
// Download, engine and UI layers consume these contracts without duplicating
// model-specific readiness rules in settings.
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

/// Relative paths accepted by model installers and scanners. A model archive is
/// never allowed to turn a relative path into an arbitrary filesystem path.
public enum NativeModelPathPolicy {
    public static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("\0"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            return false
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              !components.dropLast().contains(where: { $0.isEmpty }),
              !components.contains(where: { $0 == "." || $0 == ".." })
        else {
            return false
        }

        return components.last != ""
            || path.hasSuffix("/")
    }

    public static func normalizedRelativePath(_ path: String) -> String? {
        guard isSafeRelativePath(path) else { return nil }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
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

    /// A release is installable only when the Human-supplied integrity contract
    /// is complete. Environment keys alone intentionally do not bind Canary 1B.
    public var isBound: Bool {
        let directKey = directURLOverrideEnvironmentKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let baseKey = baseURLEnvironmentKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasSource = !directKey.isEmpty
            || (!baseKey.isEmpty && relativeArchivePath.flatMap(NativeModelPathPolicy.normalizedRelativePath) != nil)
        let hasArchiveHash = expectedArchiveSHA256.map(Self.isSHA256) ?? false
        let hasArchiveSizes = (expectedCompressedSizeBytes ?? 0) > 0
            && (expectedUncompressedSizeBytes ?? 0) > 0
        let normalizedManifestPaths = allowlistedFiles.compactMap {
            NativeModelPathPolicy.normalizedRelativePath($0.relativePath)
        }
        let hasManifest = !allowlistedFiles.isEmpty
            && normalizedManifestPaths.count == allowlistedFiles.count
            && Set(normalizedManifestPaths).count == allowlistedFiles.count
            && allowlistedFiles.allSatisfy {
                guard let normalized = NativeModelPathPolicy.normalizedRelativePath($0.relativePath) else {
                    return false
                }
                return normalized == $0.relativePath
                    && ($0.expectedByteCount ?? -1) >= 0
                    && $0.expectedSHA256.map(Self.isSHA256) == true
            }

        return !packageID.isEmpty
            && !layoutVersion.isEmpty
            && hasSource
            && hasArchiveHash
            && hasArchiveSizes
            && hasManifest
    }

    private static func isSHA256(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.count == 64 && normalized.allSatisfy(\.isHexDigit)
    }

    private static let canaryOneBAllowlistedFiles: [RemoteModelPackageFile] = [
        RemoteModelPackageFile(
            relativePath: "canary_cross_kv.mlmodelc/analytics/coremldata.bin",
            expectedByteCount: 243,
            expectedSHA256: "3553add8e4c4f4351f2e127d0a9c4b9f0ee7885503db507603fdfcb35f395250"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_cross_kv.mlmodelc/coremldata.bin",
            expectedByteCount: 470,
            expectedSHA256: "21cceed24d63e235b0d7a1bc93fbce5c040e9c6a3e4485bc6525ec874086baa7"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_cross_kv.mlmodelc/metadata.json",
            expectedByteCount: 2171,
            expectedSHA256: "f9069ae0272fbe7022dc8bcde6ecb1d723fb9c4b4bbddd755c646eb745b86f69"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_cross_kv.mlmodelc/model.mil",
            expectedByteCount: 26105,
            expectedSHA256: "a6682677e1f8312e3ae814c2a076acfcf161529d26066555b517cefb10ddde01"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_cross_kv.mlmodelc/weights/weight.bin",
            expectedByteCount: 33_589_312,
            expectedSHA256: "02bf8060427056b229b8406434f4ffd00748a7ecf4c22b463ddb87f33de510d2"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_decoder_kv.mlmodelc/analytics/coremldata.bin",
            expectedByteCount: 243,
            expectedSHA256: "d986857aada35955d23c8451f035387b7aadcf7d1ef59b6fa40d4e042650457b"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_decoder_kv.mlmodelc/coremldata.bin",
            expectedByteCount: 957,
            expectedSHA256: "0d6b71c6182ec837f211caed7fa42ae60faf82cd30e55312fa48ef6fef24b141"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_decoder_kv.mlmodelc/metadata.json",
            expectedByteCount: 7702,
            expectedSHA256: "87f539ea9c64fb10fe3f6858a7b426948235a7c1b184a2ff7394714834da136b"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_decoder_kv.mlmodelc/model.mil",
            expectedByteCount: 190_311,
            expectedSHA256: "c8510b97c57c5cc72312301d2c7aaa1ec3b8d2d16007d16bf8478e59c9ec1b1c"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_decoder_kv.mlmodelc/weights/weight.bin",
            expectedByteCount: 270_864_448,
            expectedSHA256: "b1e1ca6a08e0ba5c8bae40847faf728fe77920245a163fe30a52cdd9f9f7dd02"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_encoder.mlmodelc/analytics/coremldata.bin",
            expectedByteCount: 243,
            expectedSHA256: "dbfd16062a736f344edce2c16c2fcb84e9a55ce5979fb1d26192c8846a902b24"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_encoder.mlmodelc/coremldata.bin",
            expectedByteCount: 488,
            expectedSHA256: "4d912b07f00d4fd24bd9b577faa8692c2075a65e560bfebcc649d68b691f5151"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_encoder.mlmodelc/metadata.json",
            expectedByteCount: 2842,
            expectedSHA256: "cb42b036f98dd7fbcedaabb501e5470e29d4de7cba1dfef94448da3a44314758"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_encoder.mlmodelc/model.mil",
            expectedByteCount: 1_227_185,
            expectedSHA256: "54b1155214e3726d01a45d6ff28fbec71be09c9c143c80ed81c3d9cc40211f54"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_encoder.mlmodelc/weights/weight.bin",
            expectedByteCount: 1_579_377_472,
            expectedSHA256: "a23ab46649b973c30598b5340f4740101dea8ec6aabfe7f3b336ad3e4c5d71c8"
        ),
        RemoteModelPackageFile(
            relativePath: "canary_spe.model",
            expectedByteCount: 503_803,
            expectedSHA256: "c36395c4fc6074512648baa557586c535f92b9d9682f66bf967bf4cc3ab749b8"
        ),
        RemoteModelPackageFile(
            relativePath: "FRONTEND.md",
            expectedByteCount: 2298,
            expectedSHA256: "fcf748399547af47872f48d2436b988e72664673419a9c8d38c2db11687f513a"
        ),
        RemoteModelPackageFile(
            relativePath: "LICENSE.txt",
            expectedByteCount: 964,
            expectedSHA256: "944212da165ee581a024c9d51bd21ef7badbf72ad4d00b23a731706ae1ce3c98"
        ),
        RemoteModelPackageFile(
            relativePath: "metadata.json",
            expectedByteCount: 1005,
            expectedSHA256: "1d98e1cceaf4ab9fc69e9178b1a3dedf46e11d835e006f9e88b00f77cc722be7"
        ),
        RemoteModelPackageFile(
            relativePath: "MANIFEST.json",
            expectedByteCount: 3172,
            expectedSHA256: "3a258e36b6a71b95e538656569c455a76c302cd7ca69724b3a7075f0f20202a5"
        )
    ]

    public static let canaryOneBRelease = RemoteModelPackageRelease(
        packageID: "bolabol-canary-1b-v2-coreml-r1",
        layoutVersion: "path-b-v1",
        directURLOverrideEnvironmentKey: "VANISCRIPT_CANARY_1B_PACKAGE_URL",
        expectedArchiveSHA256: "5aa3cd51d0cc7b807e7a7b0eb9620c33cd81e64a06775edc0496f3019ed91c48",
        expectedCompressedSizeBytes: 1_735_607_621,
        expectedUncompressedSizeBytes: 1_885_801_434,
        allowlistedFiles: canaryOneBAllowlistedFiles
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

/// The trusted sidecar written after a remote package passes every integrity
/// check. Presence validation compares it with the catalog release, so a
/// downloaded package cannot become Ready by merely containing model-looking
/// files.
public struct RemoteModelPackageInstallationManifest: Codable, Equatable, Sendable {
    public var packageID: String
    public var layoutVersion: String
    public var archiveSHA256: String
    public var archiveSizeBytes: Int64
    public var uncompressedSizeBytes: Int64
    public var files: [RemoteModelPackageFile]

    public init(
        packageID: String,
        layoutVersion: String,
        archiveSHA256: String,
        archiveSizeBytes: Int64,
        uncompressedSizeBytes: Int64,
        files: [RemoteModelPackageFile]
    ) {
        self.packageID = packageID
        self.layoutVersion = layoutVersion
        self.archiveSHA256 = archiveSHA256
        self.archiveSizeBytes = archiveSizeBytes
        self.uncompressedSizeBytes = uncompressedSizeBytes
        self.files = files
    }
}

/// BOLABOL's package authenticity sidecar predates the VaniScript installer
/// manifest. It authenticates only the package identity and catalog file list;
/// the normal presence pass still hashes every catalog file afterward.
private struct LegacyRemoteModelPackageManifest: Decodable {
    struct File: Decodable {
        var path: String
        var sha256: String
        var sizeBytes: Int64
    }

    var packageID: String
    var files: [File]

    private enum CodingKeys: String, CodingKey {
        case packageID = "packageId"
        case files
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

    public var storageRuntime: SharedModelRuntime {
        switch backend {
        case .whisperKitCoreML:
            .whisperkit
        case .fluidAudioCoreML:
            .parakeet
        case .canaryCoreML:
            .canary
        }
    }

    public var settingsRuntime: LocalModelRuntime {
        switch backend {
        case .whisperKitCoreML:
            .whisper
        case .fluidAudioCoreML:
            .parakeet
        case .canaryCoreML:
            .canary
        }
    }
}

/// Catalog entry used by the app downloader for ASR and the pre-existing MLX
/// translation models. Keeping translation sources here removes the old
/// model-ID switch from the app target without adding them to the ASR catalog.
public struct NativeModelInstallDescriptor: Identifiable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var installSource: LocalASRInstallSource
    public var relativeStorageSubpath: String
    public var requiredLayout: LocalASRRequiredLayout
    public var storageRuntime: SharedModelRuntime

    public init(
        id: String,
        displayName: String,
        installSource: LocalASRInstallSource,
        relativeStorageSubpath: String,
        requiredLayout: LocalASRRequiredLayout = LocalASRRequiredLayout(),
        storageRuntime: SharedModelRuntime
    ) {
        self.id = id
        self.displayName = displayName
        self.installSource = installSource
        self.relativeStorageSubpath = relativeStorageSubpath
        self.requiredLayout = requiredLayout
        self.storageRuntime = storageRuntime
    }
}

public struct LocalModelVerification {
    public static nonisolated(unsafe) var skipVerificationForTesting: Bool = false

    public static func verifyModelPath(
        _ path: String?,
        isWhisper: Bool,
        allowTestingBypass: Bool = true
    ) -> Bool {
        if skipVerificationForTesting, allowTestingBypass {
            return true
        }
        guard let path = path, !path.isEmpty else { return false }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return false
        }
        if isWhisper {
            return verifyWhisperKitModelPath(path)
        }
        guard isDir.boolValue else { return false }
        return isMLXModelDirectory(path, fileManager: fm)
    }

    public static func verifyTranslationModelPath(
        _ path: String?,
        modelID: String,
        allowTestingBypass: Bool = true
    ) -> Bool {
        guard expectedMLXPathMarkers[modelID] != nil else { return false }
        if skipVerificationForTesting, allowTestingBypass {
            return !containsKnownUnsupportedMLXMarker(path)
        }
        guard let path, !path.isEmpty else { return false }
        guard !isKnownUnsupportedMLXPath(path) else { return false }
        guard verifyModelPath(
            path,
            isWhisper: false,
            allowTestingBypass: allowTestingBypass
        ) else { return false }
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

    public static func verifyWhisperKitModelPath(_ path: String?) -> Bool {
        if skipVerificationForTesting {
            return true
        }
        return canonicalWhisperKitModelPath(path) != nil
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

/// One model-specific readiness predicate shared by scan, Locate, settings
/// reconciliation and provider lookup. It deliberately does not infer
/// completeness from directory existence or a single marker file.
public enum LocalASRPresencePolicy {
    public static let remoteManifestFilename = ".vaniscript-package-manifest.json"

    public static func isPresent(
        _ descriptor: LocalASRModelDescriptor,
        at url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard isDirectory(url, fileManager: fileManager),
              !isSymbolicLink(url, fileManager: fileManager)
        else {
            return false
        }

        if descriptor.backend == .whisperKitCoreML {
            return LocalModelVerification.verifyWhisperKitModelPath(url.path)
        }

        guard requiredLayoutExists(
            descriptor.requiredLayout,
            at: url,
            fileManager: fileManager
        ) else {
            return false
        }

        if case let .remotePackage(release) = descriptor.installSource {
            return isRemotePackagePresent(
                release: release,
                descriptor: descriptor,
                at: url,
                fileManager: fileManager
            )
        }

        return !containsSymbolicLink(at: url, fileManager: fileManager)
    }

    public static func requiredLayoutExists(
        _ layout: LocalASRRequiredLayout,
        at url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        layout.requiredFiles.allSatisfy { relativePath in
            guard let normalized = NativeModelPathPolicy.normalizedRelativePath(relativePath) else {
                return false
            }
            let itemURL = url.appendingPathComponent(normalized, isDirectory: normalized.hasSuffix(".mlmodelc"))
            guard fileManager.fileExists(atPath: itemURL.path),
                  !isSymbolicLink(itemURL, fileManager: fileManager)
            else {
                return false
            }

            var isDir = ObjCBool(false)
            let existsAsDirectory = fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDir)
            if normalized.hasSuffix(".mlmodelc") {
                return existsAsDirectory && isDir.boolValue
            }
            return existsAsDirectory && !isDir.boolValue
        }
    }

    public static func installationManifestURL(at destination: URL) -> URL {
        destination.appendingPathComponent(remoteManifestFilename)
    }

    private static func isRemotePackagePresent(
        release: RemoteModelPackageRelease,
        descriptor: LocalASRModelDescriptor,
        at url: URL,
        fileManager: FileManager
    ) -> Bool {
        guard release.isBound,
              !containsSymbolicLink(at: url, fileManager: fileManager),
              hasAuthenticityManifest(
                  for: release,
                  at: url,
                  fileManager: fileManager
              )
        else {
            return false
        }

        guard requiredLayoutExists(descriptor.requiredLayout, at: url, fileManager: fileManager) else {
            return false
        }

        guard let expectedFiles = uniqueFiles(release.allowlistedFiles) else { return false }

        for (relativePath, file) in expectedFiles {
            let fileURL = url.appendingPathComponent(relativePath)
            guard fileManager.fileExists(atPath: fileURL.path),
                  !isSymbolicLink(fileURL, fileManager: fileManager),
                  let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular,
                  let expectedSize = file.expectedByteCount,
                  (attributes[.size] as? NSNumber)?.int64Value == expectedSize,
                  let expectedHash = file.expectedSHA256,
                  sha256(fileURL, fileManager: fileManager)?.caseInsensitiveCompare(expectedHash) == .orderedSame
            else {
                return false
            }
        }

        return extractedRegularFiles(at: url, fileManager: fileManager)
            .subtracting(expectedFiles.keys)
            .isEmpty
    }

    private static func hasAuthenticityManifest(
        for release: RemoteModelPackageRelease,
        at url: URL,
        fileManager: FileManager
    ) -> Bool {
        let installerManifestURL = installationManifestURL(at: url)
        if fileManager.fileExists(atPath: installerManifestURL.path) {
            guard let manifestData = try? Data(contentsOf: installerManifestURL),
                  let manifest = try? JSONDecoder().decode(
                      RemoteModelPackageInstallationManifest.self,
                      from: manifestData
                  )
            else {
                return false
            }

            return manifest.packageID == release.packageID
                && manifest.layoutVersion == release.layoutVersion
                && manifest.archiveSHA256.caseInsensitiveCompare(release.expectedArchiveSHA256 ?? "") == .orderedSame
                && manifest.archiveSizeBytes == release.expectedCompressedSizeBytes
                && manifest.uncompressedSizeBytes == release.expectedUncompressedSizeBytes
                && sameFiles(manifest.files, release.allowlistedFiles)
        }

        let legacyManifestURL = url.appendingPathComponent("MANIFEST.json")
        guard fileManager.fileExists(atPath: legacyManifestURL.path),
              let manifestData = try? Data(contentsOf: legacyManifestURL),
              let manifest = try? JSONDecoder().decode(
                  LegacyRemoteModelPackageManifest.self,
                  from: manifestData
              )
        else {
            return false
        }

        let legacyFiles = manifest.files.map {
            RemoteModelPackageFile(
                relativePath: $0.path,
                expectedByteCount: $0.sizeBytes,
                expectedSHA256: $0.sha256
            )
        }
        let catalogFiles = release.allowlistedFiles.filter { file in
            file.relativePath != "MANIFEST.json"
        }
        return manifest.packageID == release.packageID
            && sameFiles(legacyFiles, catalogFiles)
    }

    private static func sameFiles(
        _ lhs: [RemoteModelPackageFile],
        _ rhs: [RemoteModelPackageFile]
    ) -> Bool {
        guard let left = uniqueFiles(lhs),
              let right = uniqueFiles(rhs)
        else {
            return false
        }
        return left == right && left.count == lhs.count && right.count == rhs.count
    }

    private static func uniqueFiles(
        _ files: [RemoteModelPackageFile]
    ) -> [String: RemoteModelPackageFile]? {
        var result: [String: RemoteModelPackageFile] = [:]
        for file in files {
            guard let path = NativeModelPathPolicy.normalizedRelativePath(file.relativePath),
                  result.updateValue(file, forKey: path) == nil
            else {
                return nil
            }
        }
        return result
    }

    private static func extractedRegularFiles(at root: URL, fileManager: FileManager) -> Set<String> {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return []
        }

        var result = Set<String>()
        let rootPath = root.standardizedFileURL.path.hasSuffix("/")
            ? root.standardizedFileURL.path
            : root.standardizedFileURL.path + "/"
        let manifestPath = root.appendingPathComponent(remoteManifestFilename).standardizedFileURL.path
        for case let itemURL as URL in enumerator {
            if itemURL.standardizedFileURL.path == manifestPath {
                continue
            }
            if isSymbolicLink(itemURL, fileManager: fileManager) {
                continue
            }
            var isDir = ObjCBool(false)
            guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }
            // Finder may place this exact metadata file at any package depth.
            // Ignore no other regular file; manifest entries remain fully
            // checked above and symlinks are rejected before this filter.
            if itemURL.lastPathComponent == ".DS_Store" {
                continue
            }
            guard itemURL.standardizedFileURL.path.hasPrefix(rootPath) else { continue }
            let relative = String(itemURL.standardizedFileURL.path.dropFirst(rootPath.count))
            if let normalized = NativeModelPathPolicy.normalizedRelativePath(relative) {
                result.insert(normalized)
            }
        }
        return result
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDir = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func isSymbolicLink(_ url: URL, fileManager: FileManager) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
        return (attributes[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    private static func containsSymbolicLink(at url: URL, fileManager: FileManager) -> Bool {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [], options: []) else {
            return false
        }
        for case let itemURL as URL in enumerator where isSymbolicLink(itemURL, fileManager: fileManager) {
            return true
        }
        return false
    }

    private static func sha256(_ url: URL, fileManager: FileManager) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                stream.read(rawBuffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: rawBuffer.count)
            }
            guard count >= 0 else { return nil }
            if count == 0 { break }
            hasher.update(data: Data(buffer.prefix(count)))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct ActiveWhisperKitModel: Codable, Equatable, Sendable {
    public var id: String
    public var variant: String
    public var path: String
    public var label: String
}

public struct ActiveLocalASRModel: Codable, Equatable, Sendable {
    public var id: String
    public var path: String
    public var label: String
    public var descriptor: LocalASRModelDescriptor
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
            // FluidAudio v0.15.5 stores v3/int8 in this repo folder. These
            // names are frozen here so an SDK partial install cannot be Ready.
            requiredLayout: LocalASRRequiredLayout(
                requiredRelativePaths: [
                    "Preprocessor.mlmodelc",
                    "Encoder.mlmodelc",
                    "Decoder.mlmodelc",
                    "JointDecisionv3.mlmodelc",
                    "parakeet_vocab.json"
                ],
                isSDKManaged: true
            )
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
            installSource: .remotePackage(.canaryOneBRelease),
            relativeStorageSubpath: "canary/1b-v2",
            capabilities: LocalASRCapabilities(
                supportsAutoLanguageDetect: false,
                supportedLanguageCodes: parakeetLanguageCodes,
                maxEngineWindowSeconds: 15,
                minimumMacOSMajor: 15,
                approximateDownloadBytes: 1_735_607_621
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

    public static let localTranslationInstallDescriptors: [NativeModelInstallDescriptor] = [
        translationDescriptor(
            id: "qwen35-08b-4bit",
            displayName: "Qwen 3.5 0.8B 4-bit",
            repositoryID: "mlx-community/Qwen3.5-0.8B-4bit"
        ),
        translationDescriptor(
            id: "qwen35-2b-4bit",
            displayName: "Qwen 3.5 2B 4-bit",
            repositoryID: "mlx-community/Qwen3.5-2B-4bit"
        ),
        translationDescriptor(
            id: "qwen35-4b-4bit",
            displayName: "Qwen 3.5 4B 4-bit",
            repositoryID: "mlx-community/Qwen3.5-4B-4bit"
        ),
        translationDescriptor(
            id: "qwen35-9b-4bit",
            displayName: "Qwen 3.5 9B 4-bit",
            repositoryID: "mlx-community/Qwen3.5-9B-4bit"
        ),
        translationDescriptor(
            id: "nemotron3-nano-4b-4bit",
            displayName: "NVIDIA Nemotron-3 Nano 4B",
            repositoryID: "mlx-community/NVIDIA-Nemotron-3-Nano-4B-4bit"
        )
    ]

    public static func descriptor(for id: String) -> LocalASRModelDescriptor? {
        localASRModelDescriptors.first { $0.id == id }
    }

    public static func localASRModel(for id: String) -> LocalASRModelDescriptor? {
        descriptor(for: id)
    }

    public static func installDescriptor(for id: String) -> NativeModelInstallDescriptor? {
        if let descriptor = descriptor(for: id) {
            return NativeModelInstallDescriptor(
                id: descriptor.id,
                displayName: descriptor.displayName,
                installSource: descriptor.installSource,
                relativeStorageSubpath: descriptor.relativeStorageSubpath,
                requiredLayout: descriptor.requiredLayout,
                storageRuntime: descriptor.storageRuntime
            )
        }
        return localTranslationInstallDescriptors.first { $0.id == id }
    }
    public static func displayName(for id: String) -> String? {
        installDescriptor(for: id)?.displayName
    }

    public static func settingsRuntime(for id: String) -> LocalModelRuntime? {
        guard let descriptor = installDescriptor(for: id) else { return nil }
        switch descriptor.storageRuntime {
        case .whisperkit:
            return .whisper
        case .parakeet:
            return .parakeet
        case .canary:
            return .canary
        case .mlx:
            return .mlx
        case .gguf, .ggml:
            return nil
        }
    }


    public static func isModelPresent(
        _ descriptor: LocalASRModelDescriptor,
        at url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        LocalASRPresencePolicy.isPresent(descriptor, at: url, fileManager: fileManager)
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

    private static func translationDescriptor(
        id: String,
        displayName: String,
        repositoryID: String
    ) -> NativeModelInstallDescriptor {
        NativeModelInstallDescriptor(
            id: id,
            displayName: displayName,
            installSource: .huggingFace(repositoryID: repositoryID, revision: "main"),
            relativeStorageSubpath: "mlx/\(id)",
            storageRuntime: .mlx
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
            let whisperIDs = Set(whisperKitModelDescriptors.map(\.id))
            candidateIDs = settings.localAsrModels.keys.filter { whisperIDs.contains($0) }.sorted { lhs, rhs in
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
                  LocalModelVerification.verifyWhisperKitModelPath(path),
                  let variant = whisperKitVariant(for: id)
            else {
                continue
            }
            let resolvedPath = LocalModelVerification.canonicalWhisperKitModelPath(path) ?? path
            return ActiveWhisperKitModel(id: id, variant: variant, path: resolvedPath, label: model.label)
        }
        return nil
    }

    public static func activeLocalASRModel(
        settings: AppSettings,
        providerID: String,
        onMacOSMajor: Int? = nil,
        fileManager: FileManager = .default
    ) -> ActiveLocalASRModel? {
        let candidateIDs: [String]
        if providerID == "coreml-whisperkit" {
            let whisperIDs = Set(whisperKitModelDescriptors.map(\.id))
            candidateIDs = settings.localAsrModels.keys.filter { whisperIDs.contains($0) }.sorted { lhs, rhs in
                preferredRank(lhs) < preferredRank(rhs)
            }
        } else {
            candidateIDs = [providerID]
        }

        let osMajor = onMacOSMajor ?? ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        for id in candidateIDs {
            guard let descriptor = descriptor(for: id),
                  let model = settings.localAsrModels[id],
                  model.status == .downloaded,
                  model.runtime == descriptor.settingsRuntime,
                  let path = model.path,
                  !path.isEmpty,
                  descriptor.capabilities.isAvailable(onMacOSMajor: osMajor),
                  isModelPresent(descriptor, at: URL(fileURLWithPath: path), fileManager: fileManager)
            else {
                continue
            }
            let resolvedPath = descriptor.backend == .whisperKitCoreML
                ? (LocalModelVerification.canonicalWhisperKitModelPath(path) ?? path)
                : path
            return ActiveLocalASRModel(id: id, path: resolvedPath, label: model.label, descriptor: descriptor)
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
        scanForLocalModels(
            searchPaths: searchPaths,
            maxVisitedItems: maxVisitedItems,
            nativeASRModels: NativeModelCatalog.newLocalASRModelDescriptors
        )
    }

    /// Test seam for exercising scanner path discovery with a bounded fixture.
    /// Production callers always use the catalog's trusted descriptors above.
    static func scanForLocalModels(
        searchPaths: [URL],
        maxVisitedItems: Int,
        nativeASRModels: [LocalASRModelDescriptor]
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
                translationModels: translationModels,
                nativeASRModels: nativeASRModels,
                fileManager: fm
            ) {
                record(direct)
            }

            for descriptor in nativeASRModels {
                for candidate in nativeCandidateURLs(for: descriptor, under: searchPath, fileManager: fm) {
                    guard LocalASRPresencePolicy.isPresent(descriptor, at: candidate, fileManager: fm) else {
                        continue
                    }
                    record(
                        ScannedModel(
                            id: descriptor.id,
                            path: candidate.standardizedFileURL.resolvingSymlinksInPath().path,
                            isTranslation: false,
                            label: descriptor.displayName
                        )
                    )
                }
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
                    translationModels: translationModels,
                    nativeASRModels: nativeASRModels,
                    fileManager: fm
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

        return [SharedModelsRoot.resolve()] + sharedDirs + [
            // Keep the conventional user-local root discoverable even when a
            // prior configuration selected a different shared-model root.
            homeDir.appendingPathComponent("AI_LOCAL_MODELS", isDirectory: true),
            homeDir.appendingPathComponent("AI_LOCAL_MODELS/whisperkit", isDirectory: true),
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
        translationModels: [ModelPattern],
        nativeASRModels: [LocalASRModelDescriptor],
        fileManager: FileManager
    ) -> ScannedModel? {
        for descriptor in nativeASRModels {
            let expectedName = URL(fileURLWithPath: descriptor.relativeStorageSubpath).lastPathComponent
            guard url.lastPathComponent == expectedName,
                  LocalASRPresencePolicy.isPresent(descriptor, at: url, fileManager: fileManager)
            else {
                continue
            }
            return ScannedModel(
                id: descriptor.id,
                path: url.standardizedFileURL.resolvingSymlinksInPath().path,
                isTranslation: false,
                label: descriptor.displayName
            )
        }

        let haystack = [url.lastPathComponent, url.path]
            .joined(separator: " ")
            .lowercased()

        for model in asrModels where model.patterns.contains(where: { haystack.contains($0) }) {
            guard let canonical = LocalModelVerification.canonicalWhisperKitModelPath(url.path),
                  LocalModelVerification.verifyModelPath(canonical, isWhisper: true)
            else { continue }
            return ScannedModel(
                id: model.id,
                path: canonical,
                isTranslation: false,
                label: NativeModelCatalog.displayName(for: model.id)
            )
        }

        for model in translationModels where model.patterns.contains(where: { haystack.contains($0) }) {
            guard LocalModelVerification.verifyTranslationModelPath(
                url.path,
                modelID: model.id,
                allowTestingBypass: false
            ) else { continue }
            return ScannedModel(
                id: model.id,
                path: url.path,
                isTranslation: true,
                label: NativeModelCatalog.displayName(for: model.id)
            )
        }

        return nil
    }

    private static func nativeCandidateURLs(
        for descriptor: LocalASRModelDescriptor,
        under searchPath: URL,
        fileManager: FileManager
    ) -> [URL] {
        var candidates = [
            searchPath.appendingPathComponent(descriptor.relativeStorageSubpath, isDirectory: true),
            searchPath
                .appendingPathComponent("whisperkit", isDirectory: true)
                .appendingPathComponent(descriptor.relativeStorageSubpath, isDirectory: true)
        ]
        let runtimePrefix = descriptor.storageRuntime.rawValue + "/"
        if descriptor.relativeStorageSubpath.hasPrefix(runtimePrefix),
           searchPath.lastPathComponent == descriptor.storageRuntime.rawValue {
            let runtimeRelativePath = String(descriptor.relativeStorageSubpath.dropFirst(runtimePrefix.count))
            candidates.append(searchPath.appendingPathComponent(runtimeRelativePath, isDirectory: true))
        }

        var seen = Set<String>()
        return candidates.filter {
            let path = $0.standardizedFileURL.path
            return fileManager.fileExists(atPath: path) && seen.insert(path).inserted
        }
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
