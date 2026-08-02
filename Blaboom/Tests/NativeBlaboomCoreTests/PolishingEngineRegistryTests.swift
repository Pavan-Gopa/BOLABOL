import NativeBlaboomCore
import Testing

@Test
func polishingEngineRegistryUsesSelectedEngine() throws {
    let fallback = TestRegistryPolishingEngine(id: "fallback", displayName: "Fallback")
    let mlx = TestRegistryPolishingEngine(id: "mlx", displayName: "MLX")
    let registry = try PolishingEngineRegistry(
        engines: [fallback, mlx],
        preferredEngineID: "mlx"
    )

    #expect(registry.activeEngine.id == "mlx")
    #expect(registry.descriptors.map(\.id) == ["fallback", "mlx"])
    #expect(registry.descriptors.first { $0.id == "mlx" }?.isActive == true)
}

@Test
func polishingEngineRegistryFallsBackWhenSelectedEngineIsMissing() throws {
    let fallback = TestRegistryPolishingEngine(id: "fallback", displayName: "Fallback")
    let registry = try PolishingEngineRegistry(
        engines: [fallback],
        preferredEngineID: "missing"
    )

    #expect(registry.activeEngine.id == "fallback")
    #expect(registry.activeEngineID == "fallback")
}

@Test
func polishingEngineRegistryRejectsDuplicateEngineIDs() {
    let first = TestRegistryPolishingEngine(id: "duplicate", displayName: "First")
    let second = TestRegistryPolishingEngine(id: "duplicate", displayName: "Second")

    #expect(throws: PolishingEngineRegistryError.duplicateEngineID("duplicate")) {
        _ = try PolishingEngineRegistry(engines: [first, second])
    }
}

private struct TestRegistryPolishingEngine: PolishingEngine {
    let id: String
    let displayName: String

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        PolishingResult(
            text: request.rawText,
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}
