import Foundation

public enum SharedModelRuntime: String, CaseIterable, Codable, Equatable, Sendable {
    case mlx
    case gguf
    case ggml
    case whisperkit
    case parakeet
    case canary
}

public struct SharedModelLocation: Codable, Equatable, Sendable {
    public var runtime: SharedModelRuntime
    public var name: String

    public init(runtime: SharedModelRuntime, name: String) {
        self.runtime = runtime
        self.name = name
    }
}

public enum SharedModelsRoot {
    public static func resolve(
        configuredRoot: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        defaultRoot: URL? = nil,
        legacyRoot: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let configRoot = readConfigRoot(
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
        let envRoot = environment["AI_LOCAL_MODELS_DIR"].flatMap {
            expandedURL($0, homeDirectory: homeDirectory)
        }
        let defaultRoot = defaultRoot ?? homeDirectory.appendingPathComponent(
            "AI_LOCAL_MODELS",
            isDirectory: true
        )

        return [
            configuredRoot,
            envRoot,
            configRoot,
            defaultRoot,
            legacyRoot
        ]
        .compactMap { $0 }
        .first { isUsableRoot($0, fileManager: fileManager) }
        ?? defaultRoot
    }

    public static func modelsDirectory(
        for runtime: SharedModelRuntime,
        configuredRoot: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        defaultRoot: URL? = nil,
        legacyRoot: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let root = resolve(
            configuredRoot: configuredRoot,
            environment: environment,
            homeDirectory: homeDirectory,
            defaultRoot: defaultRoot,
            legacyRoot: legacyRoot,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for runtime in SharedModelRuntime.allCases {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(runtime.rawValue, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return root.appendingPathComponent(runtime.rawValue, isDirectory: true)
    }

    public static func modelURL(
        for location: SharedModelLocation,
        configuredRoot: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        defaultRoot: URL? = nil,
        legacyRoot: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        resolve(
            configuredRoot: configuredRoot,
            environment: environment,
            homeDirectory: homeDirectory,
            defaultRoot: defaultRoot,
            legacyRoot: legacyRoot,
            fileManager: fileManager
        )
        .appendingPathComponent(location.runtime.rawValue, isDirectory: true)
        .appendingPathComponent(location.name)
    }

    /// Resolves a descriptor's canonical destination without creating it.
    /// The relative path is part of the descriptor so each installer can later
    /// use the same destination as settings, presence and provider lookup.
    public static func modelURL(
        for descriptor: LocalASRModelDescriptor,
        configuredRoot: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        defaultRoot: URL? = nil,
        legacyRoot: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        resolve(
            configuredRoot: configuredRoot,
            environment: environment,
            homeDirectory: homeDirectory,
            defaultRoot: defaultRoot,
            legacyRoot: legacyRoot,
            fileManager: fileManager
        )
        .appendingPathComponent(descriptor.relativeStorageSubpath, isDirectory: true)
    }

    public static func location(
        for modelURL: URL,
        configuredRoot: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        defaultRoot: URL? = nil,
        legacyRoot: URL? = nil,
        fileManager: FileManager = .default
    ) -> SharedModelLocation? {
        let root = resolve(
            configuredRoot: configuredRoot,
            environment: environment,
            homeDirectory: homeDirectory,
            defaultRoot: defaultRoot,
            legacyRoot: legacyRoot,
            fileManager: fileManager
        ).standardizedFileURL.resolvingSymlinksInPath()

        let standardizedURL = modelURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard standardizedURL.path.hasPrefix(rootPath) else { return nil }

        let relativePath = String(standardizedURL.path.dropFirst(rootPath.count))
        guard let slashIndex = relativePath.firstIndex(of: "/") else { return nil }
        let runtimeName = String(relativePath[..<slashIndex])
        let nameStart = relativePath.index(after: slashIndex)
        let name = String(relativePath[nameStart...])

        guard !name.isEmpty,
              let runtime = SharedModelRuntime(rawValue: runtimeName)
        else {
            return nil
        }

        return SharedModelLocation(runtime: runtime, name: name)
    }

    private static func readConfigRoot(
        homeDirectory: URL,
        fileManager: FileManager
    ) -> URL? {
        let configURL = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("AILocalModels", isDirectory: true)
            .appendingPathComponent("config.json")

        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let root = object["root"] as? String
        else {
            return nil
        }

        return expandedURL(root, homeDirectory: homeDirectory)
    }

    private static func expandedURL(
        _ rawPath: String,
        homeDirectory: URL
    ) -> URL? {
        guard !rawPath.isEmpty else { return nil }
        if rawPath == "~" {
            return homeDirectory
        }
        if rawPath.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(rawPath.dropFirst(2)))
        }
        return URL(fileURLWithPath: rawPath, isDirectory: true)
    }

    private static func isUsableRoot(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue
        }
        return true
    }
}

public enum LocalModelPickerDefaults {
    public static func directory(
        for runtime: SharedModelRuntime,
        configuredRoot: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        defaultRoot: URL? = nil,
        legacyRoot: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        try SharedModelsRoot.modelsDirectory(
            for: runtime,
            configuredRoot: configuredRoot,
            environment: environment,
            homeDirectory: homeDirectory,
            defaultRoot: defaultRoot,
            legacyRoot: legacyRoot,
            fileManager: fileManager
        )
    }
}
