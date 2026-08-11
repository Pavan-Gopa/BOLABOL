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
        #expect(oneB.capabilities.approximateDownloadBytes == 1_735_607_621)
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
        #expect(parakeet.requiredLayout.requiredFiles == [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecisionv3.mlmodelc",
            "parakeet_vocab.json"
        ])

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
        #expect(release == NativeModelCatalog.canaryOneBRelease)
        #expect(release.packageID == "bolabol-canary-1b-v2-coreml-r1")
        #expect(release.layoutVersion == "path-b-v1")
        #expect(release.directURLOverrideEnvironmentKey == "VANISCRIPT_CANARY_1B_PACKAGE_URL")
        #expect(release.baseURLEnvironmentKey == nil)
        #expect(release.relativeArchivePath == nil)
        #expect(release.expectedArchiveSHA256 == "5aa3cd51d0cc7b807e7a7b0eb9620c33cd81e64a06775edc0496f3019ed91c48")
        #expect(release.expectedCompressedSizeBytes == 1_735_607_621)
        #expect(release.expectedUncompressedSizeBytes == 1_885_801_434)
        #expect(release.isBound)
        #expect(release.allowlistedFiles == [
            RemoteModelPackageFile(
                relativePath: "canary_cross_kv.mlmodelc/analytics/coremldata.bin",
                expectedByteCount: 243,
                expectedSHA256: "3553add8e4c4f4351f2e127d0a9c4b9f0ee7885503db507603fdfcb35f395250"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_cross_kv.mlmodelc/coremldata.bin",
                expectedByteCount: 470,
                expectedSHA256: "21cceed24d63e235b0d7a1bc93fbce5c040e9c6a3e4485bc6525ec874086baa7"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_cross_kv.mlmodelc/metadata.json",
                expectedByteCount: 2171,
                expectedSHA256: "f9069ae0272fbe7022dc8bcde6ecb1d723fb9c4b4bbddd755c646eb745b86f69"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_cross_kv.mlmodelc/model.mil",
                expectedByteCount: 26105,
                expectedSHA256: "a6682677e1f8312e3ae814c2a076acfcf161529d26066555b517cefb10ddde01"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_cross_kv.mlmodelc/weights/weight.bin",
                expectedByteCount: 33_589_312,
                expectedSHA256: "02bf8060427056b229b8406434f4ffd00748a7ecf4c22b463ddb87f33de510d2"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_decoder_kv.mlmodelc/analytics/coremldata.bin",
                expectedByteCount: 243,
                expectedSHA256: "d986857aada35955d23c8451f035387b7aadcf7d1ef59b6fa40d4e042650457b"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_decoder_kv.mlmodelc/coremldata.bin",
                expectedByteCount: 957,
                expectedSHA256: "0d6b71c6182ec837f211caed7fa42ae60faf82cd30e55312fa48ef6fef24b141"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_decoder_kv.mlmodelc/metadata.json",
                expectedByteCount: 7702,
                expectedSHA256: "87f539ea9c64fb10fe3f6858a7b426948235a7c1b184a2ff7394714834da136b"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_decoder_kv.mlmodelc/model.mil",
                expectedByteCount: 190_311,
                expectedSHA256: "c8510b97c57c5cc72312301d2c7aaa1ec3b8d2d16007d16bf8478e59c9ec1b1c"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_decoder_kv.mlmodelc/weights/weight.bin",
                expectedByteCount: 270_864_448,
                expectedSHA256: "b1e1ca6a08e0ba5c8bae40847faf728fe77920245a163fe30a52cdd9f9f7dd02"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_encoder.mlmodelc/analytics/coremldata.bin",
                expectedByteCount: 243,
                expectedSHA256: "dbfd16062a736f344edce2c16c2fcb84e9a55ce5979fb1d26192c8846a902b24"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_encoder.mlmodelc/coremldata.bin",
                expectedByteCount: 488,
                expectedSHA256: "4d912b07f00d4fd24bd9b577faa8692c2075a65e560bfebcc649d68b691f5151"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_encoder.mlmodelc/metadata.json",
                expectedByteCount: 2842,
                expectedSHA256: "cb42b036f98dd7fbcedaabb501e5470e29d4de7cba1dfef94448da3a44314758"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_encoder.mlmodelc/model.mil",
                expectedByteCount: 1_227_185,
                expectedSHA256: "54b1155214e3726d01a45d6ff28fbec71be09c9c143c80ed81c3d9cc40211f54"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_encoder.mlmodelc/weights/weight.bin",
                expectedByteCount: 1_579_377_472,
                expectedSHA256: "a23ab46649b973c30598b5340f4740101dea8ec6aabfe7f3b336ad3e4c5d71c8"
            ),
            RemoteModelPackageFile(
                relativePath: "canary_spe.model",
                expectedByteCount: 503_803,
                expectedSHA256: "c36395c4fc6074512648baa557586c535f92b9d9682f66bf967bf4cc3ab749b8"
            ),
            RemoteModelPackageFile(
                relativePath: "FRONTEND.md",
                expectedByteCount: 2298,
                expectedSHA256: "fcf748399547af47872f48d2436b988e72664673419a9c8d38c2db11687f513a"
            ),
            RemoteModelPackageFile(
                relativePath: "LICENSE.txt",
                expectedByteCount: 964,
                expectedSHA256: "944212da165ee581a024c9d51bd21ef7badbf72ad4d00b23a731706ae1ce3c98"
            ),
            RemoteModelPackageFile(
                relativePath: "metadata.json",
                expectedByteCount: 1005,
                expectedSHA256: "1d98e1cceaf4ab9fc69e9178b1a3dedf46e11d835e006f9e88b00f77cc722be7"
            ),
            RemoteModelPackageFile(
                relativePath: "MANIFEST.json",
                expectedByteCount: 3172,
                expectedSHA256: "3a258e36b6a71b95e538656569c455a76c302cd7ca69724b3a7075f0f20202a5"
            )
        ])
        #expect(oneB.relativeStorageSubpath == "canary/1b-v2")
        #expect(oneB.requiredLayout.requiredFiles == [
            "canary_encoder.mlmodelc",
            "canary_cross_kv.mlmodelc",
            "canary_decoder_kv.mlmodelc",
            "canary_spe.model"
        ])
    }

    @Test("preserves the exact existing Nemotron MLX repository")
    func preservesNemotronRepository() throws {
        let descriptor = try #require(
            NativeModelCatalog.installDescriptor(for: "nemotron3-nano-4b-4bit")
        )
        guard case let .huggingFace(repositoryID, revision) = descriptor.installSource else {
            Issue.record("Nemotron must use its existing Hugging Face source")
            return
        }

        #expect(repositoryID == "mlx-community/NVIDIA-Nemotron-3-Nano-4B-4bit")
        #expect(revision == "main")
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

    @Test("presence policy rejects partial Canary folders and accepts exact layout")
    func exactPresencePolicy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptPresence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let descriptor = try #require(
            NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")
        )
        let partial = root.appendingPathComponent("partial", isDirectory: true)
        try FileManager.default.createDirectory(
            at: partial.appendingPathComponent("CanaryEncoder.mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )
        #expect(!NativeModelCatalog.isModelPresent(descriptor, at: partial))

        let complete = root.appendingPathComponent("complete", isDirectory: true)
        for relativePath in descriptor.requiredLayout.requiredFiles {
            let url = complete.appendingPathComponent(relativePath, isDirectory: relativePath.hasSuffix(".mlmodelc"))
            if relativePath.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data([1]).write(to: url)
            }
        }
        #expect(NativeModelCatalog.isModelPresent(descriptor, at: complete))
    }

    @Test("scanner exposes a Canary install only after exact presence validation")
    func scannerRequiresExactASRPresence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptASRScanner-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let descriptor = try #require(
            NativeModelCatalog.localASRModel(for: "canary-180m-flash-coreml")
        )
        let installation = root.appendingPathComponent(
            descriptor.relativeStorageSubpath,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: installation.appendingPathComponent("CanaryEncoder.mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )

        #expect(
            !LocalModelScanner.scanForLocalModels(searchPaths: [root]).contains {
                $0.id == descriptor.id && !$0.isTranslation
            }
        )

        for relativePath in descriptor.requiredLayout.requiredFiles {
            let url = installation.appendingPathComponent(
                relativePath,
                isDirectory: relativePath.hasSuffix(".mlmodelc")
            )
            if relativePath.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data([1]).write(to: url)
            }
        }

        let expectedPath = installation.standardizedFileURL.resolvingSymlinksInPath().path
        #expect(
            LocalModelScanner.scanForLocalModels(searchPaths: [root]).contains {
                $0.id == descriptor.id && !$0.isTranslation && $0.path == expectedPath
            }
        )
    }

    @Test("binds Canary 1B to the verified Path B release")
    func canaryOneBReleaseIsBound() throws {
        let descriptor = try #require(
            NativeModelCatalog.localASRModel(for: "canary-1b-v2-coreml")
        )
        guard case let .remotePackage(release) = descriptor.installSource else {
            Issue.record("Canary 1B must use the remote package source")
            return
        }

        #expect(release == NativeModelCatalog.canaryOneBRelease)
        #expect(release.isBound)
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

    @Test("does not route native ASR folders through the legacy Whisper provider")
    func nativeASRDoesNotBecomeWhisperKit() {
        var settings = AppSettings.defaults
        settings.localAsrModels["parakeet-tdt-06b-v3"]?.status = .downloaded
        settings.localAsrModels["parakeet-tdt-06b-v3"]?.path = "/models/parakeet"

        #expect(
            NativeModelCatalog.activeWhisperKitModel(
                settings: settings,
                providerID: "coreml-whisperkit"
            ) == nil
        )
        #expect(
            NativeModelCatalog.activeLocalASRModel(
                settings: settings,
                providerID: "coreml-whisperkit",
                onMacOSMajor: 14
            ) == nil
        )
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
