import Foundation
import NativeBlaboomCore
import Testing

@Test
func sharedModelsRootResolvesConfiguredEnvConfigDefaultThenLegacy() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let home = root.appendingPathComponent("home", isDirectory: true)
    let configured = root.appendingPathComponent("Configured", isDirectory: true)
    let environment = root.appendingPathComponent("Environment", isDirectory: true)
    let configRoot = root.appendingPathComponent("Config", isDirectory: true)
    let legacy = root.appendingPathComponent("Legacy", isDirectory: true)

    for url in [home, configured, environment, configRoot, legacy] {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    let configURL = home
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("AILocalModels", isDirectory: true)
        .appendingPathComponent("config.json")
    try FileManager.default.createDirectory(
        at: configURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try #"{"root":"\#(configRoot.path)"}"#.write(to: configURL, atomically: true, encoding: .utf8)

    #expect(SharedModelsRoot.resolve(configuredRoot: configured, environment: ["AI_LOCAL_MODELS_DIR": environment.path], homeDirectory: home, legacyRoot: legacy) == configured)
    #expect(SharedModelsRoot.resolve(environment: ["AI_LOCAL_MODELS_DIR": environment.path], homeDirectory: home, legacyRoot: legacy) == environment)
    #expect(SharedModelsRoot.resolve(environment: [:], homeDirectory: home, legacyRoot: legacy) == configRoot)

    try FileManager.default.removeItem(at: configURL)
    #expect(SharedModelsRoot.resolve(environment: [:], homeDirectory: home, legacyRoot: legacy) == home.appendingPathComponent("AI_LOCAL_MODELS", isDirectory: true))

    let blockedDefault = root.appendingPathComponent("blocked-default")
    try "not a directory".write(to: blockedDefault, atomically: true, encoding: .utf8)
    #expect(SharedModelsRoot.resolve(environment: [:], homeDirectory: home, defaultRoot: blockedDefault, legacyRoot: legacy) == legacy)
}

@Test
func sharedModelsRootCreatesRuntimeDirectories() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let mlx = try SharedModelsRoot.modelsDirectory(
        for: .mlx,
        configuredRoot: root
    )

    #expect(mlx == root.appendingPathComponent("mlx", isDirectory: true))

    for runtime in SharedModelRuntime.allCases {
        var isDirectory: ObjCBool = false
        let path = root.appendingPathComponent(runtime.rawValue, isDirectory: true).path
        #expect(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}

@Test
func sharedModelLocationRoundTripsUnderConfiguredRoot() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let modelURL = root
        .appendingPathComponent("mlx", isDirectory: true)
        .appendingPathComponent("Model Name", isDirectory: true)
        .appendingPathComponent("snapshots/main", isDirectory: true)

    let location = SharedModelsRoot.location(for: modelURL, configuredRoot: root)

    #expect(location == SharedModelLocation(runtime: .mlx, name: "Model Name/snapshots/main"))
    #expect(SharedModelsRoot.modelURL(for: location!, configuredRoot: root).path == modelURL.path)
}

@Test
func installationStatesEncodeSharedRootURLsAsRelativeLocations() throws {
    let sharedURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("AI_LOCAL_MODELS", isDirectory: true)
        .appendingPathComponent("mlx", isDirectory: true)
        .appendingPathComponent("Qwopus3.5-4B-v3-mlx-6Bit", isDirectory: true)
        .appendingPathComponent("snapshots/main", isDirectory: true)
    let state = PolishingModelInstallationState.downloaded(localURL: sharedURL)

    let data = try JSONEncoder().encode(state)
    let json = String(decoding: data, as: UTF8.self)
    let decoded = try JSONDecoder().decode(PolishingModelInstallationState.self, from: data)

    #expect(json.contains("\"location\""))
    #expect(!json.contains("\"localURL\""))
    #expect(!json.contains("AI_LOCAL_MODELS"))
    #expect(decoded.location == SharedModelLocation(runtime: .mlx, name: "Qwopus3.5-4B-v3-mlx-6Bit/snapshots/main"))
    #expect(decoded.localURL?.path == sharedURL.path)
}
