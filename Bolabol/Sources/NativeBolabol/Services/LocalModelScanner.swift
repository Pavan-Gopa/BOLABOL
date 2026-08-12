import Foundation
import NativeBolabolCore

/// Scans well-known directories on the user's Mac for MLX-compatible model folders.
///
/// A valid MLX model directory must contain:
/// - `config.json` and `tokenizer.json` (metadata)
/// - At least one `.safetensors` weight file (single or sharded via `model.safetensors.index.json`)
struct LocalModelScanner: Sendable {
    private let excludedPrefixes: [String]

    /// Maximum directory depth when scanning Documents / Downloads.
    private static let maxScanDepth = 3

    init(excludedDirectories: [URL] = []) {
        self.excludedPrefixes = excludedDirectories.map(\.path)
    }

    struct ScanResult: Sendable {
        var models: [PolishingModelDescriptor] = []
        var skippedUnsupportedCount: Int = 0

        mutating func append(contentsOf result: ScanResult) {
            models.append(contentsOf: result.models)
            skippedUnsupportedCount += result.skippedUnsupportedCount
        }
    }

    // MARK: - Public API

    /// Scans all well-known locations and returns discovered models.
    /// This performs synchronous disk I/O — call from a background context.
    func scanAll() -> ScanResult {
        let fm = FileManager.default
        var results = ScanResult()
        var seenPaths = Set<String>()

        // 1. Shared app root (drop-ins and downloads from every app)
        if let sharedMLXDir = try? SharedModelsRoot.modelsDirectory(for: .mlx),
           fm.fileExists(atPath: sharedMLXDir.path) {
            let sharedResult = scanDirectory(sharedMLXDir, maxDepth: Self.maxScanDepth, fm: fm)
            results.skippedUnsupportedCount += sharedResult.skippedUnsupportedCount
            for model in sharedResult.models where seenPaths.insert(model.localDirectoryURL!.path).inserted {
                results.models.append(model)
            }
        }

        // 2. HuggingFace cache (most likely to have MLX models)
        let hfCacheDir = Self.huggingFaceCacheDirectory
        if fm.fileExists(atPath: hfCacheDir.path) {
            let hfResult = scanHuggingFaceCache(hfCacheDir, fm: fm)
            results.skippedUnsupportedCount += hfResult.skippedUnsupportedCount
            for model in hfResult.models where seenPaths.insert(model.localDirectoryURL!.path).inserted {
                results.models.append(model)
            }
        }

        // 3. ~/Documents
        let documentsDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
        if fm.fileExists(atPath: documentsDir.path) {
            let docResult = scanDirectory(documentsDir, maxDepth: Self.maxScanDepth, fm: fm)
            results.skippedUnsupportedCount += docResult.skippedUnsupportedCount
            for model in docResult.models where seenPaths.insert(model.localDirectoryURL!.path).inserted {
                results.models.append(model)
            }
        }

        // 4. ~/Downloads
        let downloadsDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
        if fm.fileExists(atPath: downloadsDir.path) {
            let dlResult = scanDirectory(downloadsDir, maxDepth: Self.maxScanDepth, fm: fm)
            results.skippedUnsupportedCount += dlResult.skippedUnsupportedCount
            for model in dlResult.models where seenPaths.insert(model.localDirectoryURL!.path).inserted {
                results.models.append(model)
            }
        }

        return results
    }

    /// Validates that a specific model directory still exists and is valid.
    func validate(_ modelURL: URL) -> Bool {
        isValidMLXModelDirectory(modelURL, fm: FileManager.default)
    }

    // MARK: - HuggingFace Cache Scanner

    /// The standard HuggingFace cache path: `~/.cache/huggingface/hub/`.
    private static var huggingFaceCacheDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("hub", isDirectory: true)
    }

    /// Scans the HuggingFace hub cache for model snapshots.
    /// Structure: `~/.cache/huggingface/hub/models--{org}--{name}/snapshots/{hash}/`
    private func scanHuggingFaceCache(_ cacheDir: URL, fm: FileManager) -> ScanResult {
        var results = ScanResult()

        guard let modelDirs = try? fm.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return results
        }

        for modelDir in modelDirs {
            let dirName = modelDir.lastPathComponent
            guard dirName.hasPrefix("models--") else { continue }
            guard !isExcluded(modelDir) else { continue }

            let snapshotsDir = modelDir.appendingPathComponent("snapshots", isDirectory: true)
            guard let snapshots = try? fm.contentsOfDirectory(
                at: snapshotsDir,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) else {
                continue
            }

            for snapshot in snapshots {
                // Derive repository ID from cache folder name: models--org--name → org/name
                let repoID = deriveRepositoryID(from: dirName)
                switch inspectModelDirectory(snapshot, repositoryID: repoID, fm: fm) {
                case .notModel:
                    continue
                case .unsupported:
                    results.skippedUnsupportedCount += 1
                    continue
                case .supported:
                    break
                }

                let descriptor = makeDescriptor(
                    directoryURL: snapshot,
                    repositoryID: repoID,
                    badge: "HF Cache",
                    fm: fm
                )
                results.models.append(descriptor)
            }
        }

        return results
    }

    // MARK: - Generic Directory Scanner

    /// Recursively scans a directory for valid MLX model folders up to `maxDepth` levels.
    private func scanDirectory(
        _ directory: URL,
        maxDepth: Int,
        currentDepth: Int = 0,
        fm: FileManager
    ) -> ScanResult {
        guard currentDepth < maxDepth else { return ScanResult() }
        guard !isExcluded(directory) else { return ScanResult() }

        var results = ScanResult()

        guard let children = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return results
        }

        for child in children {
            guard isDirectory(child, fm: fm) else { continue }

            let childName = child.lastPathComponent
            // Skip hidden directories and common non-model directories
            guard !childName.hasPrefix(".") else { continue }
            guard !Self.skipDirectoryNames.contains(childName) else { continue }

            switch inspectModelDirectory(child, repositoryID: nil, fm: fm) {
            case .supported:
                let descriptor = makeDescriptor(
                    directoryURL: child,
                    repositoryID: nil,
                    badge: "Local",
                    fm: fm
                )
                results.models.append(descriptor)
            case .unsupported:
                results.skippedUnsupportedCount += 1
            case .notModel:
                let subResults = scanDirectory(child, maxDepth: maxDepth, currentDepth: currentDepth + 1, fm: fm)
                results.append(contentsOf: subResults)
            }
        }

        return results
    }

    // MARK: - Validation

    private func isValidMLXModelDirectory(_ directory: URL, fm: FileManager) -> Bool {
        if case .supported = inspectModelDirectory(directory, repositoryID: nil, fm: fm) {
            return true
        }
        return false
    }

    private enum ModelDirectoryInspection {
        case notModel
        case unsupported
        case supported
    }

    private func inspectModelDirectory(
        _ directory: URL,
        repositoryID: String?,
        fm: FileManager
    ) -> ModelDirectoryInspection {
        let configPath = directory.appendingPathComponent("config.json").path
        let tokenizerJsonPath = directory.appendingPathComponent("tokenizer.json").path
        let tokenizerModelPath = directory.appendingPathComponent("tokenizer.model").path
        let tokenizerConfigPath = directory.appendingPathComponent("tokenizer_config.json").path

        guard fm.fileExists(atPath: configPath),
              (fm.fileExists(atPath: tokenizerJsonPath) || fm.fileExists(atPath: tokenizerModelPath) || fm.fileExists(atPath: tokenizerConfigPath))
        else {
            return .notModel
        }

        guard hasCompleteWeights(directory, fm: fm) else {
            return .notModel
        }

        let metadata = parseMetadata(
            at: directory,
            repositoryID: repositoryID
        )
        let compatibility = LocalMLXModelCompatibility.evaluate(metadata)
        return compatibility.isSupported ? .supported : .unsupported
    }

    private func hasCompleteWeights(_ directory: URL, fm: FileManager) -> Bool {
        // Single weight file
        let singleWeights = directory.appendingPathComponent("model.safetensors")
        if fm.fileExists(atPath: singleWeights.path) {
            return true
        }

        // Sharded weights
        let indexFile = directory.appendingPathComponent("model.safetensors.index.json")
        guard fm.fileExists(atPath: indexFile.path),
              let data = try? Data(contentsOf: indexFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let weightMap = root["weight_map"] as? [String: String]
        else {
            // Also check for any .safetensors file as a fallback (some models use non-standard names)
            if let files = try? fm.contentsOfDirectory(atPath: directory.path) {
                for file in files where file.hasSuffix(".safetensors") {
                    if fm.fileExists(atPath: directory.appendingPathComponent(file).path) {
                        return true
                    }
                }
            }
            return false
        }

        let weightFiles = Set(weightMap.values)
        guard !weightFiles.isEmpty else { return false }

        return weightFiles.allSatisfy { filename in
            fm.fileExists(atPath: directory.appendingPathComponent(filename).path)
        }
    }

    // MARK: - Descriptor Construction

    private func makeDescriptor(
        directoryURL: URL,
        repositoryID: String?,
        badge: String,
        fm: FileManager
    ) -> PolishingModelDescriptor {
        let config = parseConfig(at: directoryURL)
        let modelType = config.modelType ?? "unknown"
        let displayName = deriveDisplayName(
            directoryURL: directoryURL,
            config: config,
            repositoryID: repositoryID
        )
        let sizeString = formatSize(computeTotalSafetensorsSize(in: directoryURL, fm: fm))
        let idHash = stableID(for: directoryURL.path)
        let extraTokens = detectExtraEOSTokens(from: config, directory: directoryURL)

        return PolishingModelDescriptor(
            id: "custom-\(idHash)",
            displayName: displayName,
            repositoryID: repositoryID ?? directoryURL.path,
            backend: .mlxSwiftLLM,
            downloadSize: sizeString,
            badge: badge,
            description: "Local \(modelType) model at \(abbreviatePath(directoryURL.path))",
            quality: 3,
            speed: 3,
            isRecommended: false,
            extraEOSTokens: extraTokens,
            isCustom: true,
            localDirectoryURL: directoryURL
        )
    }

    private func deriveDisplayName(
        directoryURL: URL,
        config: ModelConfig,
        repositoryID: String?
    ) -> String {
        // Try _name_or_path from config
        if let nameOrPath = config.nameOrPath, !nameOrPath.isEmpty {
            let name = URL(fileURLWithPath: nameOrPath).lastPathComponent
            if !name.isEmpty && name != "." {
                return name
            }
        }

        // Try repository ID
        if let repoID = repositoryID {
            let parts = repoID.split(separator: "/")
            if parts.count >= 2 {
                return String(parts.last!)
            }
        }

        // Fall back to directory name
        return directoryURL.lastPathComponent
    }

    private func deriveRepositoryID(from cacheFolderName: String) -> String {
        // models--org--name → org/name
        let stripped = cacheFolderName
            .replacingOccurrences(of: "models--", with: "")
        let parts = stripped.split(separator: "--", maxSplits: 1)
        if parts.count == 2 {
            return "\(parts[0])/\(parts[1])"
        }
        return stripped
    }

    // MARK: - Config Parsing

    private struct ModelConfig {
        var architectures: [String] = []
        var modelType: String?
        var modelName: String?
        var nameOrPath: String?
        var hasTextConfig: Bool = false
        var hasVisionConfig: Bool = false
        var quantizationGroupSize: Int?
    }

    private struct TokenizerConfig {
        var processorClass: String?
        var tokenizerClass: String?
        var eosToken: String?
        var padToken: String?
        var chatTemplate: String?
    }

    private func parseMetadata(
        at directory: URL,
        repositoryID: String?
    ) -> LocalMLXModelMetadata {
        let config = parseConfig(at: directory)
        let tokenizer = parseTokenizerConfig(at: directory)
        let chatTemplate = tokenizer.chatTemplate ?? ""

        return LocalMLXModelMetadata(
            directoryName: directory.lastPathComponent,
            repositoryID: repositoryID,
            architectures: config.architectures,
            modelType: config.modelType,
            modelName: config.modelName,
            nameOrPath: config.nameOrPath,
            hasTextConfig: config.hasTextConfig,
            hasVisionConfig: config.hasVisionConfig,
            processorClass: tokenizer.processorClass,
            tokenizerClass: tokenizer.tokenizerClass,
            eosToken: tokenizer.eosToken,
            padToken: tokenizer.padToken,
            hasChatTemplate: !chatTemplate.isEmpty,
            chatTemplateStartsThinking: chatTemplate.contains("<think>")
                && chatTemplate.contains("add_generation_prompt"),
            quantizationGroupSize: config.quantizationGroupSize
        )
    }

    private func parseConfig(at directory: URL) -> ModelConfig {
        let configURL = directory.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ModelConfig()
        }

        let quantization = root["quantization"] as? [String: Any]
        let quantizationConfig = root["quantization_config"] as? [String: Any]
        let groupSize = (quantization?["group_size"] as? Int) ?? (quantizationConfig?["group_size"] as? Int)

        return ModelConfig(
            architectures: stringArrayValue(root["architectures"]),
            modelType: root["model_type"] as? String,
            modelName: root["model_name"] as? String,
            nameOrPath: root["_name_or_path"] as? String,
            hasTextConfig: root["text_config"] != nil,
            hasVisionConfig: root["vision_config"] != nil,
            quantizationGroupSize: groupSize
        )
    }

    private func parseTokenizerConfig(at directory: URL) -> TokenizerConfig {
        let configURL = directory.appendingPathComponent("tokenizer_config.json")
        guard let data = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return TokenizerConfig()
        }

        return TokenizerConfig(
            processorClass: root["processor_class"] as? String,
            tokenizerClass: root["tokenizer_class"] as? String,
            eosToken: stringValue(root["eos_token"]),
            padToken: stringValue(root["pad_token"]),
            chatTemplate: root["chat_template"] as? String
        )
    }

    private func stringArrayValue(_ value: Any?) -> [String] {
        if let strings = value as? [String] {
            return strings
        }
        if let string = value as? String {
            return [string]
        }
        return []
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let token = value as? [String: Any],
           let content = token["content"] as? String {
            return content
        }
        return nil
    }

    /// Detects the model family from config.json to set appropriate extraEOSTokens.
    /// Qwen models need <|im_end|>, Gemma4 needs <turn|>, etc.
    private func detectExtraEOSTokens(from config: ModelConfig, directory: URL) -> [String] {
        // First try model_type from config.json
        if let modelType = config.modelType?.lowercased() {
            // Qwen family (qwen2, qwen2_5, qwen3, qwen3_5, qwen3.5, qwopus, etc.)
            if modelType.contains("qwen") || modelType.contains("qwopus") {
                return ["<|im_end|>"]
            }

            // Gemma4 models need <turn|> token
            if modelType.contains("gemma") && (modelType.contains("4") || modelType.contains("recurrent")) {
                return ["<turn|>"]
            }

            // Gemma3 and earlier (like Gemma 2 / 1.1 / 1) need <end_of_turn> stop token
            if modelType.contains("gemma") {
                return ["<end_of_turn>"]
            }

            // Llama family
            if modelType.contains("llama") || modelType.contains("mistral") {
                return ["<|eot_id|>", "<|end_of_text|>"]
            }
        }

        // Fallback: check directory name for common patterns
        let dirName = directory.lastPathComponent.lowercased()

        // Qwen variants: qwen, qwopus, qwen3.5, qwen3, qwen2, etc.
        if dirName.contains("qwen") || dirName.contains("qwopus") {
            return ["<|im_end|>"]
        }

        // Gemma4 variants
        if dirName.contains("gemma4") || dirName.contains("gemma-4") || dirName.contains("e2b") || dirName.contains("e4b") {
            return ["<turn|>"]
        }

        // Generic Gemma / Gemma2 / Gemma3 variants
        if dirName.contains("gemma") {
            return ["<end_of_turn>"]
        }

        // Check for thinking/reasoning model patterns
        if dirName.contains("reasoning") || dirName.contains("think") || dirName.contains("chain") {
            // Reasoning models may need special handling
        }

        return []
    }

    // MARK: - Helpers

    private func computeTotalSafetensorsSize(in directory: URL, fm: FileManager) -> Int64 {
        guard let files = try? fm.contentsOfDirectory(atPath: directory.path) else {
            return 0
        }
        var total: Int64 = 0
        // Check for .safetensors files
        for file in files where file.hasSuffix(".safetensors") {
            let filePath = directory.appendingPathComponent(file).path
            if let attrs = try? fm.attributesOfItem(atPath: filePath),
               let size = attrs[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        // Also check for .bin files (GGUF/GGML models)
        for file in files where file.hasSuffix(".bin") {
            let filePath = directory.appendingPathComponent(file).path
            if let attrs = try? fm.attributesOfItem(atPath: filePath),
               let size = attrs[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        // Also check for .gguf files
        for file in files where file.hasSuffix(".gguf") {
            let filePath = directory.appendingPathComponent(file).path
            if let attrs = try? fm.attributesOfItem(atPath: filePath),
               let size = attrs[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes == 0 { return "Unknown size" }
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1 {
            return String(format: "~%.1f GB", gb)
        }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "~%.0f MB", mb)
    }

    private func stableID(for path: String) -> String {
        // Simple hash from the path for a stable, unique ID
        var hash: UInt64 = 5381
        for byte in path.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func isDirectory(_ url: URL, fm: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func isExcluded(_ url: URL) -> Bool {
        excludedPrefixes.contains { url.path.hasPrefix($0) }
    }

    private static let skipDirectoryNames: Set<String> = [
        "node_modules", ".git", ".svn", "Library", ".Trash",
        "Applications", "Music", "Movies", "Pictures",
        "__pycache__", ".venv", "venv", "env",
        ".build", "build", "dist", "DerivedData"
    ]
}
