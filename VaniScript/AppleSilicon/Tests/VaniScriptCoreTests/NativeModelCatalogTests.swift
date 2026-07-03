import Testing
import Foundation
@testable import VaniScriptCore

@Suite("Native model catalog")
struct NativeModelCatalogTests {
    init() {
        LocalModelVerification.skipVerificationForTesting = true
    }

    @Test("maps Universal ASR model ids to WhisperKit variants")
    func mapsASRModelIDs() {
        #expect(NativeModelCatalog.whisperKitVariant(for: "whisper-medium-en") == "medium.en")
        #expect(NativeModelCatalog.whisperKitVariant(for: "whisper-large-v3") == "large-v3-v20240930_626MB")
    }

    @Test("chooses a downloaded Whisper model for Core ML transcription")
    func choosesDownloadedWhisperModel() {
        var settings = AppSettings.defaults
        settings.localAsrModels["whisper-large-v3"]?.status = .downloaded
        settings.localAsrModels["whisper-large-v3"]?.path = "/models/large"

        let selection = NativeModelCatalog.activeWhisperKitModel(settings: settings, providerID: "coreml-whisperkit")

        #expect(selection?.id == "whisper-large-v3")
        #expect(selection?.variant == "large-v3-v20240930_626MB")
        #expect(selection?.path == "/models/large")
    }

    @Test("chooses a downloaded MLX model for the generic native provider")
    func choosesDownloadedMLXModelForGenericProvider() {
        var settings = AppSettings.defaults
        settings.localTranslationModels["qwen35-4b-4bit"]?.status = .downloaded
        settings.localTranslationModels["qwen35-4b-4bit"]?.path = "/models/qwen35-4b"

        let selection = NativeModelCatalog.activeMLXModel(settings: settings, providerID: "mlx-native")

        #expect(selection?.id == "qwen35-4b-4bit")
        #expect(selection?.path == "/models/qwen35-4b")
    }

    @Test("maps medium multilingual WhisperKit model")
    func mapsMediumMultilingualModel() {
        #expect(NativeModelCatalog.whisperKitVariant(for: "whisper-medium-multilingual") == "medium")
    }

    @Test("recursively scans NativeSmartScribe WhisperKit folders and stores canonical Core ML model folder")
    func scansNestedWhisperKitFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptScannerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let modelRoot = root
            .appendingPathComponent("Library/Application Support/NativeSmartScribe/Models/Transcription/WhisperKit/whisperkit-large-v3-v20240930-626mb", isDirectory: true)
        let canonical = modelRoot
            .appendingPathComponent("openai_whisper-large-v3-v20240930_626MB", isDirectory: true)
        try FileManager.default.createDirectory(
            at: canonical.appendingPathComponent("AudioEncoder.mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "{}".write(to: canonical.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        let canonicalPath = canonical.standardizedFileURL.resolvingSymlinksInPath().path

        #expect(LocalModelVerification.canonicalWhisperKitModelPath(modelRoot.path) == canonicalPath)

        let found = LocalModelScanner.scanForLocalModels(searchPaths: [root])

        #expect(found.contains {
            $0.id == "whisper-large-v3"
                && !$0.isTranslation
                && $0.path == canonicalPath
        })
    }
}
