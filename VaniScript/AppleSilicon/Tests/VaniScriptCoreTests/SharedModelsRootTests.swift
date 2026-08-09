import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Shared local models root")
struct SharedModelsRootTests {
    @Test("resolves configured, env, config, default, then legacy roots")
    func resolvesConfiguredEnvConfigDefaultThenLegacy() throws {
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

    @Test("creates runtime directories")
    func createsRuntimeDirectories() throws {
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

    @Test("model picker starts in runtime-specific shared directory")
    func modelPickerStartsInRuntimeSpecificSharedDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let mlx = try LocalModelPickerDefaults.directory(
            for: .mlx,
            configuredRoot: root
        )
        let whisperkit = try LocalModelPickerDefaults.directory(
            for: .whisperkit,
            configuredRoot: root
        )

        #expect(mlx == root.appendingPathComponent("mlx", isDirectory: true))
        #expect(whisperkit == root.appendingPathComponent("whisperkit", isDirectory: true))
    }

    @Test("resolves canonical Parakeet and Canary model paths")
    func resolvesCanonicalASRModelPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let parakeet = try SharedModelsRoot.modelsDirectory(
            for: .parakeet,
            configuredRoot: root
        )
        let canary = try SharedModelsRoot.modelsDirectory(
            for: .canary,
            configuredRoot: root
        )

        #expect(parakeet == root.appendingPathComponent("parakeet", isDirectory: true))
        #expect(canary == root.appendingPathComponent("canary", isDirectory: true))

        let parakeetDescriptor = NativeModelCatalog.localASRModel(for: "parakeet-tdt-06b-v3")!
        let flashDescriptor = NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")!
        let oneBDescriptor = NativeModelCatalog.localASRModel(for: "canary-1b-v2-coreml")!

        #expect(SharedModelsRoot.modelURL(for: parakeetDescriptor, configuredRoot: root).path
            == root.appendingPathComponent("parakeet/parakeet-tdt-0.6b-v3").path)
        #expect(SharedModelsRoot.modelURL(for: flashDescriptor, configuredRoot: root).path
            == root.appendingPathComponent("canary/180m-flash").path)
        #expect(SharedModelsRoot.modelURL(for: oneBDescriptor, configuredRoot: root).path
            == root.appendingPathComponent("canary/1b-v2").path)

        let parakeetLocation = SharedModelLocation(
            runtime: .parakeet,
            name: "parakeet-tdt-0.6b-v3"
        )
        let canaryLocation = SharedModelLocation(runtime: .canary, name: "180m-flash")
        #expect(SharedModelsRoot.modelURL(for: parakeetLocation, configuredRoot: root).path
            == root.appendingPathComponent("parakeet/parakeet-tdt-0.6b-v3").path)
        #expect(SharedModelsRoot.modelURL(for: canaryLocation, configuredRoot: root).path
            == root.appendingPathComponent("canary/180m-flash").path)
    }

    @Test("local model settings encode shared paths as relative locations")
    func localModelStateEncodesSharedPathAsRelativeLocation() throws {
        let sharedPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AI_LOCAL_MODELS", isDirectory: true)
            .appendingPathComponent("mlx", isDirectory: true)
            .appendingPathComponent("Qwopus3.5-4B-v3-mlx-6Bit", isDirectory: true)
            .path
        let state = LocalModelState(
            status: .downloaded,
            label: "Qwopus",
            path: sharedPath,
            runtime: .mlx
        )

        let data = try JSONEncoder().encode(state)
        let json = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder().decode(LocalModelState.self, from: data)

        #expect(json.contains("\"location\""))
        #expect(!json.contains("\"path\""))
        #expect(!json.contains("AI_LOCAL_MODELS"))
        #expect(decoded.location == SharedModelLocation(runtime: .mlx, name: "Qwopus3.5-4B-v3-mlx-6Bit"))
        #expect(decoded.path == sharedPath)
    }

    @Test("scanner ignores arbitrary MLX folders that are not catalog models")
    func scannerIgnoresArbitraryMLXFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptSharedRoot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func createMLXModel(named name: String) throws -> URL {
            let modelRoot = root
                .appendingPathComponent("mlx", isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
            try #"{"model_type":"qwen2"}"#.write(to: modelRoot.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
            try #"{}"#.write(to: modelRoot.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)
            try Data([0, 1, 2, 3]).write(to: modelRoot.appendingPathComponent("model.safetensors"))
            return modelRoot
        }

        let catalogModel = try createMLXModel(named: "Qwen3.5-4B-4bit")
        let legacyFlavor = "Opt" + "iQ"
        _ = try createMLXModel(named: "Qwen3.5-0.8B-\(legacyFlavor)-4bit")
        _ = try createMLXModel(named: "main")
        _ = try createMLXModel(named: "15fed4eafb456c6fcb2a1165f19ac609670ed14b")

        let found = LocalModelScanner.scanForLocalModels(searchPaths: [root])
        let expectedPath = catalogModel.standardizedFileURL.resolvingSymlinksInPath().path

        #expect(found.contains {
            $0.id == "qwen35-4b-4bit"
                && $0.isTranslation
                && URL(fileURLWithPath: $0.path).standardizedFileURL.resolvingSymlinksInPath().path == expectedPath
        })
        #expect(!found.contains { $0.id.hasPrefix("custom-") })
        #expect(!found.contains { $0.path.lowercased().contains(("opt" + "iq")) })
        #expect(!found.contains { $0.label == "main" })
        #expect(!found.contains { $0.label == "15fed4eafb456c6fcb2a1165f19ac609670ed14b" })
    }
}
