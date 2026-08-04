import Foundation
import NativeBolabolCore
import Testing

@Test
func modelPresenceRequiresCompleteMLXMetadataAndWeights() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("NativeBolabolPresence-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try #"{"model_type":"qwen2"}"#.write(to: root.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
    try #"{}"#.write(to: root.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)
    try Data([1]).write(to: root.appendingPathComponent("model.safetensors"))

    #expect(LocalModelPresence.isCompleteMLXModel(at: root))

    try FileManager.default.removeItem(at: root.appendingPathComponent("tokenizer.json"))
    #expect(!LocalModelPresence.isCompleteMLXModel(at: root))
}

@Test
func modelPresenceRejectsIncompleteMLXShardSets() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("NativeBolabolShards-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try #"{"model_type":"qwen2"}"#.write(to: root.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
    try #"{}"#.write(to: root.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)
    try #"{"weight_map":{"a":"model-00001-of-00002.safetensors","b":"model-00002-of-00002.safetensors"}}"#
        .write(to: root.appendingPathComponent("model.safetensors.index.json"), atomically: true, encoding: .utf8)
    try Data([1]).write(to: root.appendingPathComponent("model-00001-of-00002.safetensors"))

    #expect(!LocalModelPresence.isCompleteMLXModel(at: root))

    try Data([2]).write(to: root.appendingPathComponent("model-00002-of-00002.safetensors"))
    #expect(LocalModelPresence.isCompleteMLXModel(at: root))
}

@Test
func modelPresenceRequiresWhisperKitCompiledModelAndMetadata() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("NativeBolabolWhisperKit-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let compiledModel = root.appendingPathComponent("AudioEncoder.mlmodelc", isDirectory: true)
    try FileManager.default.createDirectory(at: compiledModel, withIntermediateDirectories: true)
    try #"{}"#.write(to: root.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

    #expect(LocalModelPresence.isCompleteWhisperKitModel(at: root))

    try FileManager.default.removeItem(at: root.appendingPathComponent("config.json"))
    #expect(!LocalModelPresence.isCompleteWhisperKitModel(at: root))
}

@Test
func s8PresenceFixturesRejectEmptyFoldersAndIncompleteModelAssets() throws {
    let whisperRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("NativeBolabolS8WhisperPresence-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: whisperRoot) }

    try FileManager.default.createDirectory(at: whisperRoot, withIntermediateDirectories: true)
    #expect(!LocalModelPresence.isCompleteWhisperKitModel(at: whisperRoot))

    try #"{}"#.write(
        to: whisperRoot.appendingPathComponent("config.json"),
        atomically: true,
        encoding: .utf8
    )
    #expect(!LocalModelPresence.isCompleteWhisperKitModel(at: whisperRoot))

    try FileManager.default.createDirectory(
        at: whisperRoot.appendingPathComponent("AudioEncoder.mlmodelc", isDirectory: true),
        withIntermediateDirectories: true
    )
    #expect(LocalModelPresence.isCompleteWhisperKitModel(at: whisperRoot))

    let mlxRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("NativeBolabolS8MLXPresence-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: mlxRoot) }

    try FileManager.default.createDirectory(at: mlxRoot, withIntermediateDirectories: true)
    try #"{"model_type":"qwen2"}"#.write(
        to: mlxRoot.appendingPathComponent("config.json"),
        atomically: true,
        encoding: .utf8
    )
    try Data([1]).write(to: mlxRoot.appendingPathComponent("model.safetensors"))
    #expect(!LocalModelPresence.isCompleteMLXModel(at: mlxRoot))

    try #"{}"#.write(
        to: mlxRoot.appendingPathComponent("tokenizer.json"),
        atomically: true,
        encoding: .utf8
    )
    #expect(LocalModelPresence.isCompleteMLXModel(at: mlxRoot))
}

@Test
func sharedModelsRootResolvesADR018GoModelSubpaths() throws {
    let catalog = TranscriptionModelCatalog.nativeWhisperKit

    let flash = try #require(catalog.model(withID: "canary-180m-flash-coreml"))
    #expect(flash.relativeStorageSubpath == "canary/180m-flash")

    let gigaAM = try #require(catalog.model(withID: "gigaam-v3-rnnt-coreml"))
    #expect(gigaAM.relativeStorageSubpath == "gigaam/v3-rnnt")

    let canary1B = try #require(catalog.model(withID: "canary-1b-v2-coreml"))
    #expect(canary1B.relativeStorageSubpath == "canary/1b-v2")
}
