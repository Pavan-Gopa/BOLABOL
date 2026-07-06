import NativeSmartScribeCore
import Testing

private func makeModel(
    displayName: String,
    repositoryID: String = "owner/repo",
    description: String = "A local MLX polishing model."
) -> PolishingModelDescriptor {
    PolishingModelDescriptor(
        id: displayName,
        displayName: displayName,
        repositoryID: repositoryID,
        backend: .mlxSwiftLLM,
        downloadSize: "1 GB",
        description: description,
        quality: 4,
        speed: 4
    )
}

@Test
func reasoningModelDetectedByQwopusName() {
    #expect(makeModel(displayName: "Qwopus3.5-4B-v3-mlx-6Bit").isReasoningModel)
}

@Test
func reasoningModelDetectedByOpusName() {
    #expect(makeModel(displayName: "MyOpus-Distill-9B").isReasoningModel)
}

@Test
func reasoningModelDetectedByReasoningKeywordInDescription() {
    #expect(
        makeModel(
            displayName: "Local-3B",
            description: "A reasoning fine-tune with chain-of-thought."
        ).isReasoningModel
    )
}

@Test
func nonReasoningInstructModelNotFlagged() {
    #expect(!makeModel(displayName: "Qwen2.5-3B-Instruct-mlx-4Bit").isReasoningModel)
}
