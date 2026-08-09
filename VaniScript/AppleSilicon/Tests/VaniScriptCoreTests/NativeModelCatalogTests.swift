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

    @Test("contains exactly the three LASR-01 additions")
    func containsExactlyLASR01Models() {
        let expected = [
            "parakeet-tdt-06b-v3",
            "canary-180m-flash-coreml",
            "canary-1b-v2-coreml"
        ]
        let actual = NativeModelCatalog.newLocalASRModelDescriptors.map(\.id)

        #expect(actual == expected)
        #expect(Set(actual).count == actual.count)
        #expect(!NativeModelCatalog.localASRModelDescriptors.contains { $0.id.contains("giga") })
    }

    @Test("locks ASR capabilities, language policy and OS gate")
    func locksCapabilitiesAndLanguagePolicy() {
        let descriptors = Dictionary(
            uniqueKeysWithValues: NativeModelCatalog.newLocalASRModelDescriptors.map { ($0.id, $0) }
        )
        let parakeet = descriptors["parakeet-tdt-06b-v3"]!
        let flash = descriptors["canary-180m-flash-coreml"]!
        let oneB = descriptors["canary-1b-v2-coreml"]!

        #expect(parakeet.backend == .fluidAudioCoreML)
        #expect(parakeet.capabilities.supportsAutoLanguageDetect)
        #expect(parakeet.capabilities.supportedLanguageCodes.count == 25)
        #expect(parakeet.capabilities.supportedLanguageCodes.contains("ru"))
        #expect(parakeet.capabilities.supportsSourceLanguage("auto"))

        #expect(flash.backend == .canaryCoreML)
        #expect(!flash.capabilities.supportsAutoLanguageDetect)
        #expect(flash.capabilities.supportedLanguageCodes == ["en", "de", "fr", "es"])
        #expect(!flash.capabilities.supportsSourceLanguage("auto"))

        #expect(!oneB.capabilities.supportsAutoLanguageDetect)
        #expect(oneB.capabilities.supportedLanguageCodes.count == 25)
        #expect(oneB.capabilities.supportedLanguageCodes.contains("ru"))
        #expect(oneB.capabilities.supportedLanguageCodes.contains("uk"))
        #expect(oneB.capabilities.minimumMacOSMajor == 15)
        #expect(!oneB.capabilities.isAvailable(onMacOSMajor: 14))
        #expect(oneB.capabilities.isAvailable(onMacOSMajor: 15))
    }

    @Test("keeps install-source kinds and required layouts descriptor-driven")
    func installSourcesAndLayouts() throws {
        let descriptors = Dictionary(
            uniqueKeysWithValues: NativeModelCatalog.newLocalASRModelDescriptors.map { ($0.id, $0) }
        )

        guard let parakeet = descriptors["parakeet-tdt-06b-v3"],
              let flash = descriptors["canary-180m-flash-coreml"],
              let oneB = descriptors["canary-1b-v2-coreml"]
        else {
            Issue.record("LASR-01 descriptors are missing")
            return
        }

        guard case let .fluidAudio(version, precision) = parakeet.installSource else {
            Issue.record("Parakeet must use FluidAudio")
            return
        }
        #expect(parakeet.installSource.kind == .fluidAudio)
        #expect(version == "v3")
        #expect(precision == "int8")
        #expect(parakeet.requiredLayout.isSDKManaged)

        guard case let .huggingFace(repositoryID, revision) = flash.installSource else {
            Issue.record("Canary Flash must use Hugging Face")
            return
        }
        #expect(flash.installSource.kind == .huggingFace)
        #expect(repositoryID == "aufklarer/Canary-180M-Flash-CoreML")
        #expect(revision == "ca44e0f5d816a2362cf01f7316e4932c86aafef6")
        #expect(flash.requiredLayout.requiredFiles == [
            "CanaryEncoder.mlmodelc",
            "CanaryPrefill.mlmodelc",
            "CanaryDecoder.mlmodelc",
            "config.json",
            "vocab.json"
        ])

        guard case let .remotePackage(release) = oneB.installSource else {
            Issue.record("Canary 1B must use a generic remote package")
            return
        }
        #expect(oneB.installSource.kind == .remotePackage)
        #expect(release.packageID == "canary-1b-v2-coreml")
        #expect(release.relativeArchivePath == nil)
        #expect(release.expectedArchiveSHA256 == nil)
        #expect(release.directURLOverrideEnvironmentKey == "VANISCRIPT_CANARY_1B_PACKAGE_URL")
        #expect(oneB.relativeStorageSubpath == "canary/1b-v2")
        #expect(oneB.requiredLayout.requiredFiles == [
            "canary_encoder.mlmodelc",
            "canary_cross_kv.mlmodelc",
            "canary_decoder_kv.mlmodelc",
            "canary_spe.model"
        ])
    }

    @Test("round-trips the new runtime and descriptor contracts through Codable")
    func codableMigration() throws {
        #expect(LocalModelRuntime(rawValue: "parakeet") == .parakeet)
        #expect(LocalModelRuntime(rawValue: "canary") == .canary)

        let descriptor = NativeModelCatalog.localASRModel(for: "canary-1b-v2-coreml")!
        let data = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(LocalASRModelDescriptor.self, from: data)
        #expect(decoded == descriptor)

        let state = LocalModelState(
            status: .downloaded,
            label: "Parakeet",
            path: "/tmp/parakeet",
            runtime: .parakeet
        )
        let stateData = try JSONEncoder().encode(state)
        let decodedState = try JSONDecoder().decode(LocalModelState.self, from: stateData)
        #expect(decodedState.runtime == .parakeet)
        #expect(decodedState.path == "/tmp/parakeet")
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
