import Foundation

public enum LocalModelPresence {
    public static func isCompleteMLXModel(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard isDirectory(directory, fileManager: fileManager) else { return false }
        guard fileExists(directory.appendingPathComponent("config.json"), fileManager: fileManager),
              fileExists(directory.appendingPathComponent("tokenizer.json"), fileManager: fileManager)
        else {
            return false
        }

        let singleWeightsURL = directory.appendingPathComponent("model.safetensors")
        if fileExists(singleWeightsURL, fileManager: fileManager, requireNonEmpty: true) {
            return true
        }

        let indexURL = directory.appendingPathComponent("model.safetensors.index.json")
        guard fileExists(indexURL, fileManager: fileManager),
              let data = try? Data(contentsOf: indexURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let weightMap = root["weight_map"] as? [String: String]
        else {
            return false
        }

        let weightFiles = Set(weightMap.values)
        guard !weightFiles.isEmpty else { return false }
        return weightFiles.allSatisfy { fileName in
            fileExists(
                directory.appendingPathComponent(fileName),
                fileManager: fileManager,
                requireNonEmpty: true
            )
        }
    }

    public static func isCompleteWhisperKitModel(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard isDirectory(directory, fileManager: fileManager),
              let contents = try? fileManager.contentsOfDirectory(atPath: directory.path)
        else {
            return false
        }

        let visible = contents.filter { !$0.hasPrefix(".") }
        let hasCompiledModel = visible.contains { name in
            isDirectory(
                directory.appendingPathComponent(name, isDirectory: true),
                fileManager: fileManager
            ) && name.hasSuffix(".mlmodelc")
        }
        guard hasCompiledModel else { return false }

        return visible.contains { name in
            let lower = name.lowercased()
            return lower == "config.json"
                || lower == "generation_config.json"
                || lower == "tokenizer.json"
                || lower == "tokenizer_config.json"
        }
    }

    public static func isCompleteGGUFModelFile(
        at fileURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        fileURL.pathExtension.lowercased() == "gguf"
            && fileExists(fileURL, fileManager: fileManager, requireNonEmpty: true)
    }

    public static func isCompleteGGMLModelFile(
        at fileURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        fileURL.lastPathComponent.lowercased().hasPrefix("ggml-")
            && fileURL.pathExtension.lowercased() == "bin"
            && fileExists(fileURL, fileManager: fileManager, requireNonEmpty: true)
    }

    private static func isDirectory(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func fileExists(
        _ url: URL,
        fileManager: FileManager,
        requireNonEmpty: Bool = false
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            return false
        }
        guard requireNonEmpty else { return true }
        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return size > 0
    }
}
