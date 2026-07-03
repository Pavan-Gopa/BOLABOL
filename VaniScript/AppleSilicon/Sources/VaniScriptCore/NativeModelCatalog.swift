import Foundation

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
