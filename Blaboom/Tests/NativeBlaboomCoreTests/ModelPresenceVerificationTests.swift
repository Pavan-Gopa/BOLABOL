import Foundation
import NativeBlaboomCore
import Testing

@Test
func modelPresenceRequiresCompleteMLXMetadataAndWeights() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("NativeBlaboomPresence-\(UUID().uuidString)", isDirectory: true)
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
        .appendingPathComponent("NativeBlaboomShards-\(UUID().uuidString)", isDirectory: true)
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
        .appendingPathComponent("NativeBlaboomWhisperKit-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let compiledModel = root.appendingPathComponent("AudioEncoder.mlmodelc", isDirectory: true)
    try FileManager.default.createDirectory(at: compiledModel, withIntermediateDirectories: true)
    try #"{}"#.write(to: root.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

    #expect(LocalModelPresence.isCompleteWhisperKitModel(at: root))

    try FileManager.default.removeItem(at: root.appendingPathComponent("config.json"))
    #expect(!LocalModelPresence.isCompleteWhisperKitModel(at: root))
}
