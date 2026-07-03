import NativeSmartScribeCore
import Testing

@Test
func localMLXCompatibilityAcceptsTextOnlyCausalLMModels() {
    let metadata = LocalMLXModelMetadata(
        directoryName: "Qwen3.5-4B-4bit",
        repositoryID: "mlx-community/Qwen3.5-4B-4bit",
        architectures: ["Qwen3_5ForCausalLM"],
        modelType: "qwen3_5",
        modelName: nil,
        nameOrPath: nil,
        hasTextConfig: false,
        hasVisionConfig: false,
        processorClass: nil,
        tokenizerClass: "TokenizersBackend",
        eosToken: "<|im_end|>",
        padToken: "<|endoftext|>",
        hasChatTemplate: false,
        chatTemplateStartsThinking: false
    )

    let result = LocalMLXModelCompatibility.evaluate(metadata)
    #expect(result.isSupported)
    #expect(result.profile == .standardTextGeneration)
}

@Test
func localMLXCompatibilityAcceptsKnownQwen35ConditionalModelsWithPlainPadding() {
    let metadata = LocalMLXModelMetadata(
        directoryName: "Qwen3.5-2B-4bit",
        repositoryID: "mlx-community/Qwen3.5-2B-4bit",
        architectures: ["Qwen3_5ForConditionalGeneration"],
        modelType: "qwen3_5",
        modelName: nil,
        nameOrPath: nil,
        hasTextConfig: true,
        hasVisionConfig: true,
        processorClass: "Qwen3VLProcessor",
        tokenizerClass: "TokenizersBackend",
        eosToken: "<|im_end|>",
        padToken: "<|endoftext|>",
        hasChatTemplate: false,
        chatTemplateStartsThinking: false
    )

    let result = LocalMLXModelCompatibility.evaluate(metadata)
    #expect(result.isSupported)
    #expect(result.profile == .standardChatTemplate)
}

@Test
func localMLXCompatibilityAcceptsQwopusConversionsAsReasoningModels() {
    let metadata = LocalMLXModelMetadata(
        directoryName: "Qwopus3.5-4B-v3-mlx-6Bit",
        repositoryID: nil,
        architectures: ["Qwen3_5ForConditionalGeneration"],
        modelType: "qwen3_5",
        modelName: "unsloth/Qwen3.5-4B",
        nameOrPath: nil,
        hasTextConfig: true,
        hasVisionConfig: false,
        processorClass: "Qwen3VLProcessor",
        tokenizerClass: "TokenizersBackend",
        eosToken: "<|im_end|>",
        padToken: "<|vision_pad|>",
        hasChatTemplate: false,
        chatTemplateStartsThinking: false
    )

    let result = LocalMLXModelCompatibility.evaluate(metadata)
    #expect(result.isSupported)
    #expect(result.profile == .reasoningChatTemplate)
}

@Test
func localMLXCompatibilityAcceptsThinkingGenerationTemplatesAsReasoningModels() {
    let metadata = LocalMLXModelMetadata(
        directoryName: "Qwopus3.5-9B-v3.5-oQ8-mtp",
        repositoryID: nil,
        architectures: ["Qwen3_5ForConditionalGeneration"],
        modelType: "qwen3_5",
        modelName: "unsloth/Qwen3.5-9B",
        nameOrPath: nil,
        hasTextConfig: true,
        hasVisionConfig: true,
        processorClass: "Qwen3VLProcessor",
        tokenizerClass: "TokenizersBackend",
        eosToken: "<|im_end|>",
        padToken: "<|vision_pad|>",
        hasChatTemplate: true,
        chatTemplateStartsThinking: true
    )

    let result = LocalMLXModelCompatibility.evaluate(metadata)
    #expect(result.isSupported)
    #expect(result.profile == .reasoningChatTemplate)
}

@Test
func localMLXCompatibilityRejectsUnknownNonCausalArchitectures() {
    let metadata = LocalMLXModelMetadata(
        directoryName: "custom-model",
        repositoryID: nil,
        architectures: ["SomeModelForSequenceClassification"],
        modelType: "some_model",
        modelName: nil,
        nameOrPath: nil,
        hasTextConfig: false,
        hasVisionConfig: false,
        processorClass: nil,
        tokenizerClass: "TokenizersBackend",
        eosToken: nil,
        padToken: nil,
        hasChatTemplate: false,
        chatTemplateStartsThinking: false
    )

    #expect(!LocalMLXModelCompatibility.evaluate(metadata).isSupported)
}

@Test
func localMLXCompatibilityRejectsUnsupportedQuantizationGroupSizes() {
    // 16 is unsupported
    let metadata16 = LocalMLXModelMetadata(
        directoryName: "custom-model-q16",
        repositoryID: nil,
        architectures: ["Qwen3_5ForCausalLM"],
        modelType: "qwen3_5",
        modelName: nil,
        nameOrPath: nil,
        hasTextConfig: false,
        hasVisionConfig: false,
        processorClass: nil,
        tokenizerClass: "TokenizersBackend",
        eosToken: nil,
        padToken: nil,
        hasChatTemplate: false,
        chatTemplateStartsThinking: false,
        quantizationGroupSize: 16
    )
    let result16 = LocalMLXModelCompatibility.evaluate(metadata16)
    #expect(!result16.isSupported)
    #expect(result16.reason?.contains("quantization group sizes") == true)

    // 64 is supported
    let metadata64 = LocalMLXModelMetadata(
        directoryName: "custom-model-q64",
        repositoryID: nil,
        architectures: ["Qwen3_5ForCausalLM"],
        modelType: "qwen3_5",
        modelName: nil,
        nameOrPath: nil,
        hasTextConfig: false,
        hasVisionConfig: false,
        processorClass: nil,
        tokenizerClass: "TokenizersBackend",
        eosToken: nil,
        padToken: nil,
        hasChatTemplate: false,
        chatTemplateStartsThinking: false,
        quantizationGroupSize: 64
    )
    let result64 = LocalMLXModelCompatibility.evaluate(metadata64)
    #expect(result64.isSupported)
}

