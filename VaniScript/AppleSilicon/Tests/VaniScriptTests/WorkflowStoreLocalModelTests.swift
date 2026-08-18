import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("WorkflowStore local model operations", .serialized)
struct WorkflowStoreLocalModelTests {
    init() {
        LocalModelVerification.skipVerificationForTesting = true
    }

    private static let isolatedSettingsPersistence: @Sendable (AppSettings) throws -> Void = { _ in }

    private static let isolatedProjectsPersistence: @Sendable ([ProjectRecord]) throws -> Void = { _ in }

    @Test("the newest scan alone publishes results and clears scanning")
    @MainActor
    func olderScanCompletionCannotOverwriteNewerScan() async {

        let scanGate = ScanGate()
        let completionEvents = BoolEvents()
        let oldPath = "/tmp/old-qwen35-08b-4bit"
        let newPath = "/tmp/new-qwen35-08b-4bit"
        let modelID = "qwen35-08b-4bit"
        let store = WorkflowStore(
            settings: settingsWithTranslationModel(id: modelID),
            projects: [],
            settingsPersistence: Self.isolatedSettingsPersistence,
            projectsPersistence: Self.isolatedProjectsPersistence,
            localModelScanner: { generation in await scanGate.next(generation: generation) },
            localModelScanCompletion: { applied in
                Task { await completionEvents.append(applied) }
            },
            startInitialModelScan: false
        )

        store.scanForLocalModels()
        store.scanForLocalModels()
        await scanGate.waitUntilStarted(2)

        await scanGate.release(
            generation: 2,
            result: [LocalModelScanner.ScannedModel(id: modelID, path: newPath, isTranslation: true)]
        )
        #expect(await completionEvents.next() == true)
        #expect(store.settings.localTranslationModels[modelID]?.path == newPath)
        #expect(store.settings.localTranslationModels[modelID]?.label == "Qwen 3.5 0.8B 4-bit")
        #expect(store.isScanning == false)

        await scanGate.release(
            generation: 1,
            result: [LocalModelScanner.ScannedModel(id: modelID, path: oldPath, isTranslation: true)]
        )
        #expect(await completionEvents.next() == false)
        #expect(store.settings.localTranslationModels[modelID]?.path == newPath)
        #expect(store.isScanning == false)
    }

    @Test("a scan finishing after Locate cannot replace the newer selected path")
    @MainActor
    func scanRejectsModelChangedByLocate() async {

        let scanGate = ScanGate()
        let validationGate = ValidationGate()
        let completionEvents = BoolEvents()
        let operationEvents = BoolEvents()
        let selectedPath = "/tmp/located-qwen35-08b-4bit"
        let picker = URLPicker(urls: [URL(fileURLWithPath: selectedPath)])
        let modelID = "qwen35-08b-4bit"
        let store = WorkflowStore(
            settings: settingsWithTranslationModel(id: modelID),
            projects: [],
            settingsPersistence: Self.isolatedSettingsPersistence,
            projectsPersistence: Self.isolatedProjectsPersistence,
            localModelScanner: { generation in await scanGate.next(generation: generation) },
            localModelPicker: { _, _, _ in picker.next() },
            localModelValidator: { _, _, path in
                await validationGate.wait(path: path)
                return (true, path)
            },
            localModelScanCompletion: { applied in
                Task { await completionEvents.append(applied) }
            },
            localModelOperationCompletion: { _, applied in
                Task { await operationEvents.append(applied) }
            },
            startInitialModelScan: false
        )

        store.scanForLocalModels()
        await scanGate.waitUntilStarted(1)
        store.locateLocalTranslationModel(id: modelID)
        #expect(store.settings.localTranslationModels[modelID]?.status == .downloading)
        #expect(store.settings.localTranslationModels[modelID]?.path == selectedPath)
        await validationGate.waitUntilStarted(path: selectedPath)

        await scanGate.release(
            generation: 1,
            result: [LocalModelScanner.ScannedModel(
                id: modelID,
                path: "/tmp/stale-scan-qwen35-08b-4bit",
                isTranslation: true
            )]
        )
        #expect(await completionEvents.next() == true)
        #expect(store.settings.localTranslationModels[modelID]?.status == .downloading)
        #expect(store.settings.localTranslationModels[modelID]?.path == selectedPath)

        await validationGate.release(path: selectedPath)
        #expect(await operationEvents.next() == true)
        #expect(store.settings.localTranslationModels[modelID]?.status == .downloaded)
        #expect(store.settings.localTranslationModels[modelID]?.path == selectedPath)
    }

    @Test("a stale MCP Locate completion cannot overwrite a newer direct Locate operation")
    @MainActor
    func staleMcpLocateCompletionIsIgnored() async throws {
        let validationGate = ValidationGate()
        let completionEvents = BoolEvents()
        let firstPath = "/tmp/first-qwen35-08b-4bit"
        let secondPath = "/tmp/second-qwen35-08b-4bit"
        let canonicalSecondPath = "/tmp/canonical-second-qwen35-08b-4bit"
        let picker = URLPicker(urls: [
            URL(fileURLWithPath: firstPath),
            URL(fileURLWithPath: secondPath),
        ])
        let modelID = "qwen35-08b-4bit"
        let store = WorkflowStore(
            settings: settingsWithTranslationModel(id: modelID),
            projects: [],
            settingsPersistence: Self.isolatedSettingsPersistence,
            projectsPersistence: Self.isolatedProjectsPersistence,
            localModelPicker: { _, _, _ in picker.next() },
            localModelValidator: { _, _, path in
                await validationGate.wait(path: path)
                return (true, path == secondPath ? canonicalSecondPath : path)
            },
            localModelOperationCompletion: { _, applied in
                Task { await completionEvents.append(applied) }
            },
            startInitialModelScan: false
        )

        let queued = try await store.executeMcpTool(
            name: "locate_model",
            arguments: ["modelId": modelID]
        )
        #expect(queued["status"] as? String == "queued")
        #expect(store.settings.localTranslationModels[modelID]?.status == .downloading)
        #expect(store.settings.localTranslationModels[modelID]?.path == firstPath)
        await validationGate.waitUntilStarted(path: firstPath)

        store.locateLocalTranslationModel(id: modelID)
        #expect(store.settings.localTranslationModels[modelID]?.status == .downloading)
        #expect(store.settings.localTranslationModels[modelID]?.path == secondPath)
        await validationGate.waitUntilStarted(path: secondPath)

        await validationGate.release(path: secondPath)
        #expect(await completionEvents.next() == true)
        #expect(store.settings.localTranslationModels[modelID]?.status == .downloaded)
        #expect(store.settings.localTranslationModels[modelID]?.path == canonicalSecondPath)

        await validationGate.release(path: firstPath)
        #expect(await completionEvents.next() == false)
        #expect(store.settings.localTranslationModels[modelID]?.status == .downloaded)
        #expect(store.settings.localTranslationModels[modelID]?.path == canonicalSecondPath)
    }

    @Test("direct Locate marks an invalid translation model failed after validation")
    @MainActor
    func invalidDirectLocateWaitsForValidationBeforeFailing() async {
        let validationGate = ValidationGate()
        let operationEvents = BoolEvents()
        let selectedPath = "/tmp/invalid-qwen35-08b-4bit"
        let modelID = "qwen35-08b-4bit"
        let store = WorkflowStore(
            settings: settingsWithTranslationModel(id: modelID),
            projects: [],
            settingsPersistence: Self.isolatedSettingsPersistence,
            projectsPersistence: Self.isolatedProjectsPersistence,
            localModelPicker: { _, _, _ in URL(fileURLWithPath: selectedPath) },
            localModelValidator: { _, _, path in
                await validationGate.wait(path: path)
                return (false, nil)
            },
            localModelOperationCompletion: { _, applied in
                Task { await operationEvents.append(applied) }
            },
            startInitialModelScan: false
        )

        store.locateLocalTranslationModel(id: modelID)
        #expect(store.settings.localTranslationModels[modelID]?.status == .downloading)
        #expect(store.settings.localTranslationModels[modelID]?.path == selectedPath)
        await validationGate.waitUntilStarted(path: selectedPath)
        #expect(store.settings.localTranslationModels[modelID]?.status == .downloading)

        await validationGate.release(path: selectedPath)
        #expect(await operationEvents.next() == true)
        #expect(store.settings.localTranslationModels[modelID]?.status == .failed)
        #expect(store.settings.localTranslationModels[modelID]?.path == selectedPath)
        #expect(store.settings.localTranslationModels[modelID]?.progressLabel == "Validation failed")
        #expect(store.settings.localTranslationModels[modelID]?.error == "Selected location is incomplete or failed integrity validation.")
    }
    @Test("loading repairs stale local model metadata without losing selection or install state")
    func loadingRepairsStaleLocalModelMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptSettings-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileManager = IsolatedSettingsFileManager(root: root)
        let modelID = "qwen35-4b-4bit"
        let modelPath = root
            .appendingPathComponent("mlx", isDirectory: true)
            .appendingPathComponent("models--mlx-community--Qwen3.5-4B-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: modelPath, withIntermediateDirectories: true)

        var persisted = AppSettings.defaults
        persisted.translationProvider = modelID
        persisted.localTranslationModels[modelID] = LocalModelState(
            status: .downloaded,
            progress: 0.42,
            progressLabel: "Fixture progress",
            label: "Fixture MLX",
            path: modelPath.path,
            error: "Fixture warning",
            runtime: .whisper
        )
        try SettingsDiskStore.save(persisted, fileManager: fileManager)

        let loaded = SettingsDiskStore.load(fileManager: fileManager)
        let repaired = try #require(loaded.localTranslationModels[modelID])
        #expect(repaired.label == "Qwen 3.5 4B 4-bit")
        #expect(repaired.runtime == .mlx)
        #expect(repaired.status == .downloaded)
        #expect(repaired.progress == 0.42)
        #expect(repaired.progressLabel == "Fixture progress")
        #expect(repaired.path == modelPath.path)
        #expect(repaired.error == "Fixture warning")
        #expect(loaded.translationProvider == modelID)

        let repairedData = try Data(contentsOf: AppStoragePaths.settingsURL(fileManager: fileManager))
        let repairedOnDisk = try JSONDecoder().decode(AppSettings.self, from: repairedData)
        #expect(repairedOnDisk.localTranslationModels[modelID]?.label == "Qwen 3.5 4B 4-bit")
        #expect(repairedOnDisk.localTranslationModels[modelID]?.runtime == .mlx)
    }

    @Test("injected WorkflowStore settings persistence is isolated and observable")
    @MainActor
    func injectedSettingsPersistenceIsIsolatedAndObservable() async {
        let recorder = SettingsSaveRecorder()
        let store = WorkflowStore(
            settings: AppSettings.defaults,
            projects: [],
            settingsPersistence: { settings in
                Task { await recorder.append(settings) }
            },
            projectsPersistence: Self.isolatedProjectsPersistence,
            startInitialModelScan: false
        )

        store.updateSettings { settings in
            settings.defaultTargetLang = "Spanish"
        }

        let saved = await recorder.first()
        #expect(saved.defaultTargetLang == "Spanish")
        #expect(saved.translationProvider == AppSettings.defaults.translationProvider)
    }

    @Test("processing failure does not open review screen or announce review readiness")
    @MainActor
    func processingFailureDoesNotOpenReviewScreenOrAnnounceReadiness() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptStoreFailure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let asrID = "whisper-small-multilingual"
        let mlxID = "qwen35-4b-4bit"
        let asrDescriptor = try #require(NativeModelCatalog.descriptor(for: asrID))
        let asrPath = root.appendingPathComponent("asr", isDirectory: true)
        let mlxPath = root.appendingPathComponent("mlx", isDirectory: true)
        try FileManager.default.createDirectory(at: asrPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mlxPath, withIntermediateDirectories: true)

        var settings = AppSettings.defaults
        settings.defaultSourceLang = "en"
        settings.defaultTargetLang = "ru"
        settings.transcriptionProvider = asrID
        settings.translationProvider = mlxID
        settings.localAsrModels[asrID] = LocalModelState(
            status: .downloaded,
            label: asrDescriptor.displayName,
            path: asrPath.path,
            runtime: asrDescriptor.settingsRuntime
        )
        settings.localTranslationModels[mlxID] = LocalModelState(
            status: .downloaded,
            label: "Qwen 2.5 3B",
            path: mlxPath.path,
            runtime: .mlx
        )
        let audioURL = root.appendingPathComponent("test.wav")
        try Data([1, 2, 3, 4]).write(to: audioURL)

        let events = LifecycleEventLog()
        let factories = LocalASREngineRouterFactories(
            whisperKit: { model in
                LifecycleASREngine(descriptor: model.descriptor, events: events)
            },
            parakeet: { model in
                LifecycleASREngine(descriptor: model.descriptor, events: events)
            },
            canary: { model in
                LifecycleASREngine(descriptor: model.descriptor, events: events)
            }
        )

        let failingMLXEngine = MLXTextGenerationEngine(generationOverride: { _, _, _, _ in
            throw CueBatchTranslationError.emptyOutput
        })

        let pipeline = NativeProcessingPipeline(
            localASRRouter: LocalASREngineRouter(factories: factories),
            mlxEngine: failingMLXEngine
        )

        let store = WorkflowStore(
            settings: settings,
            projects: [],
            settingsPersistence: Self.isolatedSettingsPersistence,
            projectsPersistence: Self.isolatedProjectsPersistence,
            startInitialModelScan: false,
            processingPipeline: pipeline
        )

        store.workflow.sourceFile = audioURL.path
        store.workflow.sourceFileName = audioURL.lastPathComponent
        store.workflow.durationSec = 2.0
        store.workflow.sourceLang = "en"
        store.workflow.targetLang = "ru"
        store.workflow.transcriptionProvider = asrID
        store.workflow.translationProvider = mlxID

        store.startSession()

        while store.isProcessingSegment {
            await Task.yield()
        }

        #expect(store.workflow.screen == .config)
        #expect(store.isErrorAlertPresented == true)
        #expect(store.statusMessage.contains("Segment processing failed"))
        #expect(!store.statusMessage.contains("ready for review"))
    }

    @Test("selection updates settings, workflow, active session, and persisted project")
    @MainActor
    func selectionUpdatesSettingsWorkflowSessionAndProject() async {
        let canaryID = "canary-180m-flash-coreml"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("VaniScriptTestCanary-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var settings = AppSettings.defaults
        settings.localAsrModels[canaryID] = LocalModelState(
            status: .downloaded,
            label: "Canary 180M Flash",
            path: tempDir.path,
            runtime: .canary
        )
        settings.transcriptionProvider = "coreml-whisperkit"

        let session = SessionState(
            sourceFile: "/audio/test.wav",
            sourceFileName: "test.wav",
            durationSec: 60,
            metadata: AudioMetadata.empty,
            sourceLang: "en",
            targetLang: "Russian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "none",
            outputFormats: [.txt],
            chunks: [],
            currentChunkIndex: 0
        )

        let projectRecord = ProjectRecord(
            id: "test-proj-1",
            createdAt: "2026-05-25T10:05:00Z",
            updatedAt: "2026-05-25T10:05:00Z",
            session: session
        )

        let store = WorkflowStore(
            settings: settings,
            projects: [projectRecord],
            settingsPersistence: Self.isolatedSettingsPersistence,
            projectsPersistence: Self.isolatedProjectsPersistence,
            startInitialModelScan: false
        )

        store.openProject(id: "test-proj-1")
        store.setTranscriptionProvider(canaryID)

        #expect(store.settings.transcriptionProvider == canaryID)
        #expect(store.workflow.transcriptionProvider == canaryID)
        #expect(store.workflow.session?.transcriptionProvider == canaryID)
        #expect(store.projects.first(where: { $0.id == "test-proj-1" })?.session.transcriptionProvider == canaryID)
    }

    @Test("opening archived Whisper while available Canary selected uses and persists Canary")
    @MainActor
    func openArchivedWhisperProjectWithCanarySelectedUsesCanary() async {
        let canaryID = "canary-180m-flash-coreml"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("VaniScriptTestCanary-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var settings = AppSettings.defaults
        settings.localAsrModels[canaryID] = LocalModelState(
            status: .downloaded,
            label: "Canary 180M Flash",
            path: tempDir.path,
            runtime: .canary
        )
        settings.transcriptionProvider = canaryID

        let session = SessionState(
            sourceFile: "/audio/test.wav",
            sourceFileName: "test.wav",
            durationSec: 60,
            metadata: AudioMetadata.empty,
            sourceLang: "en",
            targetLang: "Russian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "none",
            outputFormats: [.txt],
            chunks: [],
            currentChunkIndex: 0
        )

        let projectRecord = ProjectRecord(
            id: "test-proj-2",
            createdAt: "2026-05-25T10:05:00Z",
            updatedAt: "2026-05-25T10:05:00Z",
            session: session
        )

        let store = WorkflowStore(
            settings: settings,
            projects: [projectRecord],
            settingsPersistence: Self.isolatedSettingsPersistence,
            projectsPersistence: Self.isolatedProjectsPersistence,
            startInitialModelScan: false
        )

        store.openProject(id: "test-proj-2")

        #expect(store.workflow.transcriptionProvider == canaryID)
        #expect(store.workflow.session?.transcriptionProvider == canaryID)
        #expect(store.projects.first(where: { $0.id == "test-proj-2" })?.session.transcriptionProvider == canaryID)
    }

    @Test("stale async refresh does not rollback selected provider")
    @MainActor
    func asyncRefreshDoesNotRollbackSelectedProvider() async throws {
        let canaryID = "canary-180m-flash-coreml"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("VaniScriptTestCanary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        for directoryName in ["CanaryEncoder.mlmodelc", "CanaryPrefill.mlmodelc", "CanaryDecoder.mlmodelc"] {
            try FileManager.default.createDirectory(
                at: tempDir.appendingPathComponent(directoryName, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        for fileName in ["config.json", "vocab.json"] {
            try Data("fixture".utf8).write(to: tempDir.appendingPathComponent(fileName))
        }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var settings = AppSettings.defaults
        settings.localAsrModels[canaryID] = LocalModelState(
            status: .downloaded,
            label: "Canary 180M Flash",
            path: tempDir.path,
            runtime: .canary
        )
        settings.transcriptionProvider = canaryID

        let session = SessionState(
            sourceFile: "/audio/test.wav",
            sourceFileName: "test.wav",
            durationSec: 60,
            metadata: AudioMetadata.empty,
            sourceLang: "en",
            targetLang: "Russian",
            transcriptionProvider: canaryID,
            translationProvider: "none",
            outputFormats: [.txt],
            chunks: [],
            currentChunkIndex: 0
        )

        let projectRecord = ProjectRecord(
            id: "test-proj-3",
            createdAt: "2026-05-25T10:05:00Z",
            updatedAt: "2026-05-25T10:05:00Z",
            session: session
        )

        let store = WorkflowStore(
            settings: settings,
            projects: [projectRecord],
            settingsPersistence: Self.isolatedSettingsPersistence,
            projectsPersistence: Self.isolatedProjectsPersistence,
            startInitialModelScan: false
        )

        store.openProject(id: "test-proj-3")
        store.reconcileLocalModelStates()

        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.workflow.transcriptionProvider == canaryID)
        #expect(store.workflow.session?.transcriptionProvider == canaryID)
    }

    @Test("local MLX workloads release resident ASR before review, documents, and Shorts")
    @MainActor
    func localMLXWorkloadsReleaseResidentASR() async throws {

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptLifecycle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let asrPath = root.appendingPathComponent("asr", isDirectory: true)
        let alternateASRPath = root.appendingPathComponent("asr-second", isDirectory: true)
        let mlxPath = root.appendingPathComponent("mlx", isDirectory: true)
        try FileManager.default.createDirectory(at: asrPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: alternateASRPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mlxPath, withIntermediateDirectories: true)

        let events = LifecycleEventLog()
        let asrID = "whisper-small-multilingual"
        let mlxID = "qwen35-4b-4bit"
        let descriptor = try #require(NativeModelCatalog.descriptor(for: asrID))
        var settings = AppSettings.defaults
        settings.transcriptionProvider = asrID
        settings.translationProvider = mlxID
        settings.localAsrModels[asrID] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            path: asrPath.path,
            runtime: descriptor.settingsRuntime
        )
        settings.localTranslationModels[mlxID] = LocalModelState(
            status: .downloaded,
            label: "Fixture MLX",
            path: mlxPath.path,
            runtime: .mlx
        )

        let factories = LocalASREngineRouterFactories(
            whisperKit: { model in
                await events.append("asr-create")
                return LifecycleASREngine(descriptor: model.descriptor, events: events)
            },
            parakeet: { model in
                await events.append("asr-create")
                return LifecycleASREngine(descriptor: model.descriptor, events: events)
            },
            canary: { model in
                await events.append("asr-create")
                return LifecycleASREngine(descriptor: model.descriptor, events: events)
            }
        )
        let mlx = LifecycleMLXEngine(events: events)
        let pipeline = NativeProcessingPipeline(
            localASRRouter: LocalASREngineRouter(factories: factories),
            mlxEngine: mlx
        )
        let audioURL = root.appendingPathComponent("dictation.wav")
        try Data([1]).write(to: audioURL)

        _ = try await pipeline.transcribeLocalASR(
            audioURL: audioURL,
            sourceLang: "en",
            settings: settings,
            providerID: asrID
        )

        let cue = TranscriptCue(startSec: 0, endSec: 1, text: "hello")
        let chunk = ChunkData(
            index: 0,
            filePath: audioURL.path,
            durationSec: 1,
            startSec: 0,
            endSec: 1,
            original: "hello",
            translated: "привет",
            originalCues: [cue],
            status: .done,
            approved: false
        )
        let session = SessionState(
            sourceFile: audioURL.path,
            sourceFileName: audioURL.lastPathComponent,
            durationSec: 1,
            metadata: AudioMetadata.empty,
            sourceLang: "en",
            targetLang: "Russian",
            transcriptionProvider: asrID,
            translationProvider: mlxID,
            outputFormats: [.txt],
            chunks: [chunk],
            currentChunkIndex: 0,
            activeTranslationLanguage: "Russian",
            shortsPlans: [
                ShortsClipPlan(
                    start: "00:00:00",
                    end: "00:00:01",
                    title: "Existing",
                    summary: "Existing",
                    hook: "Existing",
                    category: "clip"
                )
            ]
        )
        let store = WorkflowStore(
            settings: settings,
            projects: [],
            settingsPersistence: Self.isolatedSettingsPersistence,
            projectsPersistence: Self.isolatedProjectsPersistence,
            startInitialModelScan: false,
            processingPipeline: pipeline,
            reviewMLXEngine: mlx,
            documentMLXEngine: mlx,
            shortsMLXEngine: mlx
        )
        store.workflow.session = session
        store.workflow.transcriptionProvider = asrID
        store.workflow.translationProvider = mlxID

        store.retranslateCue(cue.id)
        await events.waitFor("review-translate")
        #expect((await events.snapshot()).suffix(2).elementsEqual(["asr-unload", "review-translate"]))

        _ = try await pipeline.transcribeLocalASR(
            audioURL: audioURL,
            sourceLang: "en",
            settings: store.settings,
            providerID: asrID
        )
        let mlxModel = try #require(NativeModelCatalog.activeMLXModel(settings: store.settings, providerID: mlxID))
        _ = try await store.formatDocumentWithLocalMLX(
            format: .srt,
            targetLanguage: "Russian",
            text: "hello",
            model: mlxModel
        )
        await events.waitFor("document-format")
        #expect((await events.snapshot()).suffix(2).elementsEqual(["asr-unload", "document-format"]))

        _ = try await pipeline.transcribeLocalASR(
            audioURL: audioURL,
            sourceLang: "en",
            settings: store.settings,
            providerID: asrID
        )
        store.generateShortsPlan(count: 1, minDurationSec: 1, maxDurationSec: 2, mode: .source)
        await events.waitFor("shorts-plan")
        #expect((await events.snapshot()).suffix(2).elementsEqual(["asr-unload", "shorts-plan"]))

        _ = try await pipeline.transcribeLocalASR(
            audioURL: audioURL,
            sourceLang: "en",
            settings: store.settings,
            providerID: asrID
        )
        let unloadsBeforeMutation = await events.count("asr-unload")
        store.updateSettings { settings in
            settings.localAsrModels[asrID]?.path = alternateASRPath.path
        }
        await events.waitForCount("asr-unload", unloadsBeforeMutation + 1)
    }

    private func settingsWithTranslationModel(id: String) -> AppSettings {
        var settings = AppSettings.defaults
        settings.localTranslationModels[id] = LocalModelState(
            status: .notDownloaded,
            label: "Fixture translation model",
            runtime: .mlx
        )
        return settings
    }
}
private final class IsolatedSettingsFileManager: FileManager {
    private let root: URL

    init(root: URL) {
        self.root = root
        super.init()
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        if directory == .applicationSupportDirectory,
           domainMask.contains(.userDomainMask) {
            return [root]
        }
        return super.urls(for: directory, in: domainMask)
    }
}

private actor SettingsSaveRecorder {
    private var values: [AppSettings] = []

    func append(_ settings: AppSettings) {
        values.append(settings)
    }

    func first() async -> AppSettings {
        while values.isEmpty {
            await Task.yield()
        }
        return values[0]
    }
}


@MainActor
private final class URLPicker {
    private var urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
    }

    func next() -> URL? {
        guard !urls.isEmpty else { return nil }
        return urls.removeFirst()
    }
}

private actor BoolEvents {
    private var values: [Bool] = []
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    func append(_ value: Bool) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: value)
        } else {
            values.append(value)
        }
    }

    func next() async -> Bool {
        if !values.isEmpty {
            return values.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor ScanGate {
    private var continuations: [Int: CheckedContinuation<[LocalModelScanner.ScannedModel], Never>] = [:]
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func next(generation: Int) async -> [LocalModelScanner.ScannedModel] {
        await withCheckedContinuation { continuation in
            continuations[generation] = continuation
            let ready = startWaiters.filter { $0.0 <= continuations.count }
            startWaiters.removeAll { $0.0 <= continuations.count }
            for (_, waiter) in ready {
                waiter.resume()
            }
        }
    }

    func waitUntilStarted(_ count: Int) async {
        guard continuations.count < count else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func release(generation: Int, result: [LocalModelScanner.ScannedModel]) {
        guard let continuation = continuations.removeValue(forKey: generation) else { return }
        continuation.resume(returning: result)
    }
}

private actor ValidationGate {
    private var continuations: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var pendingReleases: [String: Int] = [:]
    private var startedPaths: Set<String> = []
    private var startWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func wait(path: String) async {
        startedPaths.insert(path)
        let waiters = startWaiters.removeValue(forKey: path) ?? []
        for waiter in waiters {
            waiter.resume()
        }

        if let pending = pendingReleases[path], pending > 0 {
            if pending == 1 {
                pendingReleases.removeValue(forKey: path)
            } else {
                pendingReleases[path] = pending - 1
            }
            return
        }

        await withCheckedContinuation { continuation in
            continuations[path, default: []].append(continuation)
        }
    }

    func waitUntilStarted(path: String) async {
        guard !startedPaths.contains(path) else { return }
        await withCheckedContinuation { continuation in
            startWaiters[path, default: []].append(continuation)
        }
    }

    func release(path: String) {
        if var pathContinuations = continuations[path], !pathContinuations.isEmpty {
            let continuation = pathContinuations.removeFirst()
            if pathContinuations.isEmpty {
                continuations.removeValue(forKey: path)
            } else {
                continuations[path] = pathContinuations
            }
            continuation.resume()
        } else {
            pendingReleases[path, default: 0] += 1
        }
    }
}
private actor LifecycleEventLog {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }

    func count(_ value: String) -> Int {
        values.filter { $0 == value }.count
    }

    func waitFor(_ value: String) async {
        while !values.contains(value) {
            await Task.yield()
        }
    }

    func waitForCount(_ value: String, _ expected: Int) async {
        while values.filter({ $0 == value }).count < expected {
            await Task.yield()
        }
    }
}

private struct LifecycleASREngine: LocalASREngine {
    let descriptor: LocalASRModelDescriptor
    let events: LifecycleEventLog

    func transcribe(_ request: LocalASRRequest) async throws -> LocalASRResult {
        await events.append("asr-transcribe")
        return LocalASRResult(text: "hello")
    }

    func unload() async {
        await events.append("asr-unload")
    }
}

private actor LifecycleMLXEngine: NativeLocalMLXEngine {
    let events: LifecycleEventLog

    init(events: LifecycleEventLog) {
        self.events = events
    }

    func translate(
        text: String,
        targetLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        model: ActiveMLXModel,
        promptPresets: [String: PromptPresetSettings]
    ) async throws -> String {
        await events.append("review-translate")
        return "translated"
    }

    func translateCues(
        _ cues: [TranscriptCue],
        targetLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        model: ActiveMLXModel,
        promptPresets: [String: PromptPresetSettings]
    ) async throws -> [TranscriptCue] {
        await events.append("review-cues")
        return []
    }

    func polish(
        text: String,
        targetLang: String,
        model: ActiveMLXModel,
        lecturer: String,
        glossary: [GlossaryEntry],
        promptPresets: [String: PromptPresetSettings]
    ) async throws -> String {
        await events.append("review-polish")
        return text
    }

    func formatDocument(
        format: OutputFormat,
        targetLang: String,
        text: String,
        model: ActiveMLXModel
    ) async throws -> String {
        await events.append("document-format")
        return text
    }

    func planShorts(
        transcript: String,
        count: Int,
        minDurationSec: Int,
        maxDurationSec: Int,
        outputLanguage: String,
        speakerName: String?,
        mode: ShortsPlanLanguageMode,
        existingClips: [ShortsClipPlan],
        model: ActiveMLXModel
    ) async throws -> [ShortsClipPlan] {
        await events.append("shorts-plan")
        return []
    }

    func translateShortsPlan(
        _ plan: ShortsClipPlan,
        targetLanguage: String,
        model: ActiveMLXModel
    ) async throws -> ShortsClipTranslation {
        await events.append("shorts-translate")
        return ShortsClipTranslation(language: targetLanguage, title: plan.title, summary: plan.summary, hook: plan.hook)
    }
}
