import CoreML
import Foundation
@testable import NativeBolabol
import NativeBolabolCore
import Testing

struct S9RuntimeSmokeTests {
    @Test
    func canary1BDecoderPositionUsesRankOneProductInput() throws {
        let position = 9
        let input = try CanaryCoreMLEngine.pathBDecoderPositionArray(position: position)

        #expect(input.dataType == .int32)
        #expect(input.shape.map(\.intValue) == [1])
        #expect(input[0].intValue == position)
    }

    @Test
    func canaryFlashOfflineDictationProducesTextWhenScratchIsEnabled() async throws {
        guard let paths = scratchPaths(
            model: "canary-flash-spike/models/CanaryFlash",
            audio: "canary-flash-spike/audio/en_short.wav"
        ) else { return }
        let model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-180m-flash-coreml")
        )
        let engine = CanaryCoreMLEngine(model: model, modelFolderURL: paths.model)
        let result = try await engine.transcribe(
            TranscriptionRequest(audioFileURL: paths.audio, forcedLanguageCode: "en")
        )
        print("SMOKE Canary Flash: \(result.text)")
        #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func canary1BOfflineDictationProducesTextWhenScratchIsEnabled() async throws {
        guard let paths = scratchPaths(
            model: "canary-1b-fix/package/bolabol-canary-1b-v2-coreml-r1",
            audio: "canary-flash-spike/audio/en_short.wav"
        ) else { return }
        let model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-1b-v2-coreml")
        )
        let engine = CanaryCoreMLEngine(model: model, modelFolderURL: paths.model)
        let result = try await engine.transcribe(
            TranscriptionRequest(audioFileURL: paths.audio, forcedLanguageCode: "en")
        )
        print("SMOKE Canary 1B: \(result.text)")
        #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func gigaAMOfflineDictationProducesTextWhenScratchIsEnabled() async throws {
        guard let paths = scratchPaths(
            model: "gigaam-spike/models",
            audio: "gigaam-spike/audio/ru_short.wav"
        ) else { return }
        let model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "gigaam-v3-rnnt-coreml")
        )
        let engine = GigaAMCoreMLEngine(model: model, modelFolderURL: paths.model)
        let result = try await engine.transcribe(
            TranscriptionRequest(audioFileURL: paths.audio, forcedLanguageCode: "ru")
        )
        print("SMOKE GigaAM: \(result.text)")
        #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func scratchPaths(model: String, audio: String) -> (model: URL, audio: URL)? {
        guard ProcessInfo.processInfo.environment["BOLABOL_S9_RUNTIME_SMOKE"] == "1" else {
            print("UNAVAILABLE: set BOLABOL_S9_RUNTIME_SMOKE=1 to run offline S9 smoke")
            return nil
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let modelURL = root.appendingPathComponent("scratch/\(model)", isDirectory: true)
        let audioURL = root.appendingPathComponent("scratch/\(audio)")
        guard FileManager.default.fileExists(atPath: modelURL.path),
              FileManager.default.fileExists(atPath: audioURL.path) else {
            print("UNAVAILABLE: missing scratch model or audio for \(model)")
            return nil
        }
        return (modelURL, audioURL)
    }
}
