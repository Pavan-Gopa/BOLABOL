import NativeBolabolCore
import Testing

@Test
func nativePolishingCatalogUsesQwen35FourBRecommendedModelByDefault() throws {
    let catalog = PolishingModelCatalog.nativeMLX
    let defaultModel = try #require(catalog.defaultModel)

    #expect(defaultModel.id == "qwen35-4b-4bit")
    #expect(defaultModel.backend == .mlxSwiftLLM)
    #expect(defaultModel.repositoryID == "mlx-community/Qwen3.5-4B-4bit")
    #expect(defaultModel.isRecommended)
}

@Test
func nativePolishingCatalogIncludesQwenLadderAndNemotronOption() {
    let catalog = PolishingModelCatalog.nativeMLX
    let modelIDs = Set(catalog.models.map(\.id))

    #expect(modelIDs.contains("qwen35-08b-4bit"))
    #expect(modelIDs.contains("qwen35-2b-4bit"))
    #expect(modelIDs.contains("qwen35-4b-4bit"))
    #expect(modelIDs.contains("qwen35-9b-4bit"))
    #expect(modelIDs.contains("nemotron3-nano-4b-4bit"))
    #expect(!modelIDs.contains("gemma4-e2b-it-4bit"))
    #expect(!modelIDs.contains("gemma4-e4b-it-4bit"))
}

@Test
func nativePolishingCatalogIncludesLiquidLFM25ExperimentModels() throws {
    let catalog = PolishingModelCatalog.nativeMLX
    let modelIDs = Set(catalog.models.map(\.id))

    #expect(modelIDs.contains("lfm25-12b-instruct-4bit"))
    #expect(modelIDs.contains("lfm25-26b-4bit"))

    let small = try #require(catalog.model(withID: "lfm25-12b-instruct-4bit"))
    #expect(small.repositoryID == "mlx-community/LFM2.5-1.2B-Instruct-4bit")
    #expect(small.backend == .mlxSwiftLLM)
    #expect(!small.isReasoningModel)

    let large = try #require(catalog.model(withID: "lfm25-26b-4bit"))
    #expect(large.repositoryID == "LiquidAI/LFM2.5-2.6B-MLX-4bit")
    #expect(large.backend == .mlxSwiftLLM)
    #expect(!large.isReasoningModel)
}

@Test
func nativePolishingCatalogRejectsDuplicateModelIDs() {
    let model = PolishingModelDescriptor(
        id: "duplicate",
        displayName: "Duplicate",
        repositoryID: "mlx-community/duplicate",
        backend: .mlxSwiftLLM,
        downloadSize: "1 GB",
        badge: nil,
        description: "Duplicate test model.",
        quality: 3,
        speed: 3
    )

    #expect(throws: PolishingModelCatalogError.duplicateModelID("duplicate")) {
        try PolishingModelCatalog(models: [model, model])
    }
}

@Test
func polishingModelDescriptorBuildsHuggingFaceCacheFolderName() throws {
    let catalog = PolishingModelCatalog.nativeMLX
    let model = try #require(catalog.model(withID: "qwen35-2b-4bit"))

    #expect(model.huggingFaceCacheFolderName == "models--mlx-community--Qwen3.5-2B-4bit")
}
