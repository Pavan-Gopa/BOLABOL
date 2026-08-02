import Foundation
import NativeBlaboomCore
import Testing

@Test
func modelPreparationSnapshotClampsProgressFraction() {
    let low = ModelPreparationSnapshot.downloading(progressFraction: -1)
    let high = ModelPreparationSnapshot.downloading(progressFraction: 2)

    #expect(low.progressFraction == 0)
    #expect(high.progressFraction == 1)
}

@Test
func modelPreparationSnapshotStoresReadyDiagnostics() {
    let diagnostics = EngineDiagnostics(
        backendName: "MLX Test",
        loadTimeMilliseconds: 120,
        tokensPerSecond: 30
    )
    let directory = URL(fileURLWithPath: "/tmp/native-blaboom-model")

    let snapshot = ModelPreparationSnapshot.ready(
        modelDirectory: directory,
        diagnostics: diagnostics,
        message: "Smoke test passed."
    )

    #expect(snapshot.phase == .ready)
    #expect(snapshot.modelDirectory == directory)
    #expect(snapshot.diagnostics == diagnostics)
    #expect(snapshot.message == "Smoke test passed.")
}
