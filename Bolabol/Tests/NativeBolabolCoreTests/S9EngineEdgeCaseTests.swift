import Foundation
@testable import NativeBolabol
import NativeBolabolCore
import Testing

private let s9GOModelIDs = [
    "canary-180m-flash-coreml",
    "canary-1b-v2-coreml",
    "gigaam-v3-rnnt-coreml",
]

private func s9RequiredItems(for modelID: String) -> [String] {
    switch modelID {
    case "canary-1b-v2-coreml":
        return [
            "canary_encoder.mlmodelc",
            "canary_cross_kv.mlmodelc",
            "canary_decoder_kv.mlmodelc",
            "canary_spe.model",
        ]
    case "canary-180m-flash-coreml":
        return [
            "CanaryEncoder.mlmodelc",
            "CanaryPrefill.mlmodelc",
            "CanaryDecoder.mlmodelc",
            "config.json",
            "vocab.json",
        ]
    case "gigaam-v3-rnnt-coreml":
        return [
            "Encoder.mlmodelc",
            "Predictor.mlmodelc",
            "JointDecision.mlmodelc",
            "vocab.txt",
        ]
    default:
        return []
    }
}

private func makeS9GOModelFolder(
    for model: TranscriptionModelDescriptor,
    under root: URL,
    omitting omittedItem: String? = nil
) throws -> URL {
    let fileManager = FileManager.default
    let modelFolder = root.appendingPathComponent(model.relativeStorageSubpath, isDirectory: true)
    try fileManager.createDirectory(at: modelFolder, withIntermediateDirectories: true)

    for item in s9RequiredItems(for: model.id) where item != omittedItem {
        let itemURL = modelFolder.appendingPathComponent(item, isDirectory: item.hasSuffix(".mlmodelc"))
        if item.hasSuffix(".mlmodelc") {
            try fileManager.createDirectory(at: itemURL, withIntermediateDirectories: true)
        } else if item == "canary_spe.model" {
            try Data([0]).write(to: itemURL)
        } else if item == "vocab.txt" {
            try "token 0\n".write(to: itemURL, atomically: true, encoding: .utf8)
        } else {
            try "{}".write(to: itemURL, atomically: true, encoding: .utf8)
        }
    }

    return modelFolder
}

private func makeS9TemporaryRoot(prefix: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeS9Defaults() -> (defaults: UserDefaults, suiteName: String) {
    let suiteName = "bolabol-s9-\(UUID().uuidString)"
    return (UserDefaults(suiteName: suiteName)!, suiteName)
}

private func setS9SpeechLanguages(
    _ speechLanguages: UserSpeechLanguages,
    in defaults: UserDefaults
) throws {
    let settings = GeneralSettings(speechLanguages: speechLanguages)
    defaults.set(
        try JSONEncoder().encode(settings),
        forKey: "general.settings"
    )
}

struct S9CanaryLanguageEdgeCaseTests {
    @Test
    func canary1BLanguageMatrixCoversExplicit25LanguageASRSources() async throws {
        let model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-1b-v2-coreml")
        )
        let engine = CanaryCoreMLEngine(
            model: model,
            modelFolderURL: URL(fileURLWithPath: "/tmp/bolabol-s9-canary-1b-language")
        )

        await #expect(throws: CanaryTranscriptionError.self) {
            try await engine.resolveLanguage(
                TranscriptionRequest(forcedLanguageCode: nil)
            )
        }
        await #expect(throws: CanaryTranscriptionError.self) {
            try await engine.resolveLanguage(
                TranscriptionRequest(forcedLanguageCode: "ko")
            )
        }

        for sourceLanguage in CanaryLanguageCatalog.oneBV2LanguageCodes {
            let resolved = try await engine.resolveLanguage(
                TranscriptionRequest(
                    forcedLanguageCode: sourceLanguage,
                    targetLanguageCode: sourceLanguage
                )
            )
            #expect(resolved == sourceLanguage)
        }

    }

    @Test
    func canaryFlashLanguageMatrixAcceptsAllASRSourceLanguages() async throws {
        let model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-180m-flash-coreml")
        )
        let engine = CanaryCoreMLEngine(
            model: model,
            modelFolderURL: URL(fileURLWithPath: "/tmp/bolabol-s9-canary-flash-language")
        )

        for sourceLanguage in ["en", "de", "fr", "es"] {
            let resolved = try await engine.resolveLanguage(
                TranscriptionRequest(
                    forcedLanguageCode: sourceLanguage
                )
            )
            #expect(resolved == sourceLanguage)
        }
    }
}

struct S9UnavailableEngineEdgeCaseTests {
    @Test
    func everyGOEngineRejectsAMissingModelDirectory() async throws {
        let catalog = TranscriptionModelCatalog.nativeWhisperKit
        let audioURL = URL(fileURLWithPath: "/tmp/bolabol-s9-missing-audio.wav")
        let request = TranscriptionRequest(audioFileURL: audioURL, forcedLanguageCode: "en")

        let canaryFlash = try #require(catalog.model(withID: "canary-180m-flash-coreml"))
        let flashEngine = CanaryCoreMLEngine(
            model: canaryFlash,
            modelFolderURL: URL(fileURLWithPath: "/tmp/bolabol-s9-missing-flash-\(UUID().uuidString)")
        )
        await #expect(throws: (any Error).self) {
            try await flashEngine.transcribe(request)
        }

        let canary1B = try #require(catalog.model(withID: "canary-1b-v2-coreml"))
        let oneBEngine = CanaryCoreMLEngine(
            model: canary1B,
            modelFolderURL: URL(fileURLWithPath: "/tmp/bolabol-s9-missing-1b-\(UUID().uuidString)")
        )
        await #expect(throws: (any Error).self) {
            try await oneBEngine.transcribe(
                TranscriptionRequest(audioFileURL: audioURL, forcedLanguageCode: "en")
            )
        }

        let gigaAM = try #require(catalog.model(withID: "gigaam-v3-rnnt-coreml"))
        let gigaAMEngine = GigaAMCoreMLEngine(
            model: gigaAM,
            modelFolderURL: URL(fileURLWithPath: "/tmp/bolabol-s9-missing-gigaam-\(UUID().uuidString)")
        )
        await #expect(throws: (any Error).self) {
            try await gigaAMEngine.transcribe(
                TranscriptionRequest(audioFileURL: audioURL, forcedLanguageCode: "ru")
            )
        }
    }

    @Test
    func canary1BUsesMacOS15GateBeforeLoadingTheModel() async throws {
        var model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-1b-v2-coreml")
        )
        let forcedRequiredVersion = ASRModelCapabilities.OSVersion(majorVersion: 99)
        model.capabilities.minOSVersion = forcedRequiredVersion
        let engine = CanaryCoreMLEngine(
            model: model,
            modelFolderURL: URL(fileURLWithPath: "/tmp/bolabol-s9-os-gate")
        )

        let current = ProcessInfo.processInfo.operatingSystemVersion
        let currentVersion = ASRModelCapabilities.OSVersion(
            majorVersion: current.majorVersion,
            minorVersion: current.minorVersion,
            patchVersion: current.patchVersion
        )

        do {
            _ = try await engine.transcribe(
                TranscriptionRequest(
                    audioFileURL: URL(fileURLWithPath: "/tmp/bolabol-s9-os-gate.wav"),
                    forcedLanguageCode: "en"
                )
            )
            Issue.record("The forced unsupported OS gate did not reject before model loading")
        } catch let error as CanaryTranscriptionError {
            #expect(error == .unsupportedOS(required: forcedRequiredVersion, current: currentVersion))
        } catch {
            Issue.record("Unexpected error from the OS gate: \(error)")
        }
    }
}

@MainActor
struct S9StorePresenceIntegrationTests {
    @Test
    func storeResolvesAllGOModelsFromS8StorageRoots() throws {
        let catalog = TranscriptionModelCatalog.nativeWhisperKit

        for modelID in s9GOModelIDs {
            let model = try #require(catalog.model(withID: modelID))
            let root = try makeS9TemporaryRoot(prefix: "bolabol-s9-complete")
            defer { try? FileManager.default.removeItem(at: root) }
            let expectedFolder = try makeS9GOModelFolder(for: model, under: root)

            let (defaults, suiteName) = makeS9Defaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let modelStore = TranscriptionModelStore(
                catalog: catalog,
                userDefaults: defaults,
                fileManager: .default,
                modelsDirectory: root
            )

            modelStore.activate(model)
            let activeModel = try #require(modelStore.activeDownloadedModel())
            #expect(activeModel.model.id == modelID)
            #expect(activeModel.modelFolderURL.standardizedFileURL == expectedFolder.standardizedFileURL)
            #expect(activeModel.modelFolderURL.path.hasSuffix(model.relativeStorageSubpath))
        }
    }

    @Test
    func storeRejectsEveryIncompleteGOModelFolder() throws {
        let catalog = TranscriptionModelCatalog.nativeWhisperKit

        for modelID in s9GOModelIDs {
            let model = try #require(catalog.model(withID: modelID))
            for omittedItem in s9RequiredItems(for: modelID) {
                let root = try makeS9TemporaryRoot(prefix: "bolabol-s9-incomplete")
                defer { try? FileManager.default.removeItem(at: root) }
                _ = try makeS9GOModelFolder(
                    for: model,
                    under: root,
                    omitting: omittedItem
                )

                let (defaults, suiteName) = makeS9Defaults()
                defer { defaults.removePersistentDomain(forName: suiteName) }
                let modelStore = TranscriptionModelStore(
                    catalog: catalog,
                    userDefaults: defaults,
                    fileManager: .default,
                    modelsDirectory: root
                )
                modelStore.activate(model)

                #expect(
                    modelStore.activeDownloadedModel() == nil,
                    "\(modelID) must be unavailable when \(omittedItem) is missing"
                )
                let engine = TranscriptionEngineStore.live().activeEngine(modelStore: modelStore)
                #expect(engine is UnavailableTranscriptionEngine)
            }
        }
    }

    @Test
    func storeSettingsActionsRespectCapabilityOSGateAndKeepDeleteAvailable() async throws {
        var model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-1b-v2-coreml")
        )
        model.capabilities.minOSVersion = ASRModelCapabilities.OSVersion(majorVersion: 99)
        let catalog = try TranscriptionModelCatalog(models: [model])
        let root = try makeS9TemporaryRoot(prefix: "bolabol-s10-os-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let expectedFolder = try makeS9GOModelFolder(for: model, under: root)

        let (defaults, suiteName) = makeS9Defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let modelStore = TranscriptionModelStore(
            catalog: catalog,
            userDefaults: defaults,
            fileManager: .default,
            modelsDirectory: root
        )

        #expect(modelStore.hasLocalFiles(for: model))
        #expect(modelStore.settings.installationState(for: model.id).status == .downloaded)
        modelStore.activate(model)
        #expect(modelStore.settings.activeModelID == nil)

        await modelStore.download(model)
        #expect(modelStore.settings.activeModelID == nil)
        #expect(modelStore.settings.installationState(for: model.id).status == .downloaded)

        modelStore.remove(model)
        #expect(!FileManager.default.fileExists(atPath: expectedFolder.path))
        #expect(modelStore.settings.installationState(for: model.id).status == .notDownloaded)
    }

    @Test
    func S10LanguageBlockKeepsRealDownloadProgressAndRetryActions() throws {
        let model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-180m-flash-coreml")
        )
        let catalog = try TranscriptionModelCatalog(models: [model])
        let root = try makeS9TemporaryRoot(prefix: "bolabol-s10-language-actions")
        defer { try? FileManager.default.removeItem(at: root) }

        let (defaults, suiteName) = makeS9Defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try setS9SpeechLanguages(
            UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "uk"),
            in: defaults
        )
        let modelStore = TranscriptionModelStore(
            catalog: catalog,
            userDefaults: defaults,
            fileManager: .default,
            modelsDirectory: root
        )
        let projection = model.sourceLanguageProjection(
            primary: modelStore.speechLanguages.primaryLanguageCode,
            additional: modelStore.speechLanguages.additionalLanguageCode
        )
        let isOSCompatible = modelStore.isModelAvailable(for: model)

        #expect(projection.isHardBlocked)
        #expect(isOSCompatible)
        #expect(modelStore.installationState(for: model).status == .notDownloaded)
        #expect(
            LocalModelsActionPolicy.action(
                for: modelStore.installationState(for: model),
                isOSCompatible: isOSCompatible,
                isLanguageBlocked: projection.isHardBlocked,
                isActive: false,
                isGOModel: true,
                hasCompleteLocalFiles: modelStore.hasLocalFiles(for: model)
            ) == .download
        )

        var settings = TranscriptionModelSettings()
        settings.markDownloading(modelID: model.id, progressFraction: 0.41)
        let knownProgress = settings.installationState(for: model.id)
        #expect(
            LocalModelsActionPolicy.action(
                for: knownProgress,
                isOSCompatible: isOSCompatible,
                isLanguageBlocked: projection.isHardBlocked,
                isActive: false,
                isGOModel: true,
                hasCompleteLocalFiles: false
            ) == .downloading(progressFraction: 0.41)
        )

        settings.markDownloading(modelID: model.id, progressFraction: nil)
        let indeterminateProgress = settings.installationState(for: model.id)
        #expect(
            LocalModelsActionPolicy.action(
                for: indeterminateProgress,
                isOSCompatible: isOSCompatible,
                isLanguageBlocked: projection.isHardBlocked,
                isActive: false,
                isGOModel: true,
                hasCompleteLocalFiles: false
            ) == .downloading(progressFraction: nil)
        )

        let errorMessage = "real download failed: connection reset"
        settings.markFailed(modelID: model.id, errorMessage: errorMessage)
        let failed = settings.installationState(for: model.id)
        #expect(
            LocalModelsActionPolicy.action(
                for: failed,
                isOSCompatible: isOSCompatible,
                isLanguageBlocked: projection.isHardBlocked,
                isActive: false,
                isGOModel: true,
                hasCompleteLocalFiles: false
            ) == .retry(errorMessage: errorMessage)
        )
    }

    @Test
    func S10LanguageBlockedCompletionDoesNotAutoSelectAndKeepsDelete() throws {
        let model = try #require(
            TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-180m-flash-coreml")
        )
        let catalog = try TranscriptionModelCatalog(models: [model])
        let root = try makeS9TemporaryRoot(prefix: "bolabol-s10-language-completion")
        defer { try? FileManager.default.removeItem(at: root) }

        let (defaults, suiteName) = makeS9Defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try setS9SpeechLanguages(
            UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "uk"),
            in: defaults
        )
        let modelStore = TranscriptionModelStore(
            catalog: catalog,
            userDefaults: defaults,
            fileManager: .default,
            modelsDirectory: root
        )
        #expect(modelStore.installationState(for: model).status == .notDownloaded)

        let completedFolder = try makeS9GOModelFolder(for: model, under: root)
        modelStore.finishDownload(model, localURL: completedFolder)

        let state = modelStore.installationState(for: model)
        let projection = model.sourceLanguageProjection(
            primary: modelStore.speechLanguages.primaryLanguageCode,
            additional: modelStore.speechLanguages.additionalLanguageCode
        )
        #expect(state.status == .downloaded)
        #expect(modelStore.hasLocalFiles(for: model))
        #expect(modelStore.settings.activeModelID == nil)
        #expect(modelStore.activeModel == nil)
        #expect(modelStore.activeModelForPresentation == nil)
        #expect(
            LocalModelsActionPolicy.action(
                for: state,
                isOSCompatible: modelStore.isModelAvailable(for: model),
                isLanguageBlocked: projection.isHardBlocked,
                isActive: false,
                isGOModel: true,
                hasCompleteLocalFiles: modelStore.hasLocalFiles(for: model)
            ) == .none
        )
        #expect(
            LocalModelsActionPolicy.canDelete(
                state: state,
                isGOModel: true,
                hasCompleteLocalFiles: modelStore.hasLocalFiles(for: model),
                hasAnyLocalFiles: modelStore.hasAnyLocalFiles(for: model)
            )
        )

        modelStore.remove(model)
        #expect(!FileManager.default.fileExists(atPath: completedFolder.path))
        #expect(modelStore.installationState(for: model).status == .notDownloaded)
    }
}
