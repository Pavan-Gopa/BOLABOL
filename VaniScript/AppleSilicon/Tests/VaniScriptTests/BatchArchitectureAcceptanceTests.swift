import AVFoundation
import Foundation
import Testing
import VaniScriptCore
import VaniScriptRuntime
@testable import VaniScript

@Suite("Batch architecture acceptance")
struct BatchArchitectureAcceptanceTests {
    @Test("manual scheduler work passes queued background work and concurrency stays one")
    func manualPriorityAndConcurrency() async throws {
        let scheduler = TranscriptionScheduler()
        let events = EventLog()
        let first = Task { try await scheduler.run(priority: .background) { await events.run("background-1", delay: .milliseconds(80)) } }
        try await Task.sleep(for: .milliseconds(10))
        let second = Task { try await scheduler.run(priority: .background) { await events.run("background-2") } }
        let manual = Task { try await scheduler.run(priority: .manual) { await events.run("manual") } }
        _ = try await (first.value, second.value, manual.value)
        #expect(await events.values == ["background-1", "manual", "background-2"])
        #expect(await events.maximumConcurrency == 1)
    }

    @Test("max-attempt guard fails without invoking provider and privacy-safe error omits source path")
    func attemptGuardAndSafeFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceName = "2026_guard_story_oslo_no.wav"
        let source = root.appendingPathComponent(sourceName)
        try Data("audio".utf8).write(to: source)
        let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
        let fingerprint = try AtomicCompanionWriter.fingerprint(sourceURL: source)
        var job = BatchJob(profileID: "p", relativeSourcePath: sourceName, relativeOutputPath: "2026_guard_story_oslo_no.txt", sourceFingerprint: fingerprint, configuration: .init(identifier: "c", sourceLanguage: "en"))
        job.attempt = 1
        guard case let .inserted(inserted) = try await repository.enqueue(job) else { return }
        let calls = CallCounter()
        let coordinator = BatchTranscriptionCoordinator(repository: repository, configuration: .init(identifier: "c", sourceLanguage: "en"), transcriber: CountingTranscriber(calls: calls), writer: AtomicCompanionWriter(), maxAttempts: 1)
        await coordinator.processPending(in: root)
        let result = try await repository.job(id: inserted.id)
        #expect(result?.state == .failed)
        #expect(result?.lastError == "Maximum batch attempts reached.")
        #expect(await calls.value == 0)
        #expect(result?.lastError?.contains(root.path) == false)
    }

    @Test("manual Upload Review Export state remains independent of batch profiles")
    @MainActor
    func manualWorkflowRegression() {
        let store = WorkflowStore(settings: .defaults, projects: [], settingsPersistence: { _ in }, projectsPersistence: { _ in }, startInitialModelScan: false)
        #expect(store.workflow.screen == .upload)
        store.workflow.screen = .review
        #expect(store.workflow.screen == .review)
        store.workflow.screen = .export
        #expect(store.workflow.screen == .export)
        #expect(store.projects.isEmpty)
    }

    @Test("disabled batch facade preserves manual workflow and no-ops operations")
    @MainActor
    func disabledBatchManualSurvival() async {
        let workflow = WorkflowStore(settings: .defaults, projects: [], settingsPersistence: { _ in }, projectsPersistence: { _ in }, startInitialModelScan: false)
        let store = BatchTranscriptionStore.disabled(message: "Batch storage failed.")

        await store.start()
        await store.scan()
        store.addFolder(URL(fileURLWithPath: "/unavailable"))
        await store.retry(jobID: UUID())
        await store.cancel(jobID: UUID())

        #expect(!store.isAvailable)
        #expect(!store.isRunning)
        #expect(store.profiles.isEmpty && store.jobs.isEmpty)
        #expect(store.errorMessage == "Batch storage failed.")
        workflow.workflow.screen = .review
        #expect(workflow.workflow.screen == .review)
    }

    @Test("watcher stamps new configuration while preserving existing jobs")
    func liveConfigurationStamping() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
        let profileStore = SecurityScopedFolderStore(
            profilesURL: root.appendingPathComponent("profiles.json"),
            resolveBookmark: { _ in (root, false) },
            startAccess: { _ in true },
            stopAccess: { _ in }
        )
        try profileStore.save([BatchFolderProfile(id: "p", name: "Folder", bookmarkData: Data([1]), displayPath: root.path)])
        let old = BatchTranscriptionConfiguration(identifier: "old-provider|en|5", sourceLanguage: "en")
        let new = BatchTranscriptionConfiguration(identifier: "new-provider|de|9", sourceLanguage: "de")
        let watcher = WatchedFolderService(
            store: profileStore,
            repository: repository,
            configuration: old,
            stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true }),
            startWatching: { _, _ in {} }
        )
        try Data("first".utf8).write(to: root.appendingPathComponent("2026_first_story_rome_it.wav"))
        let firstActivation = try await watcher.activate()
        _ = try await watcher.reconcile(profileID: "p")
        await watcher.stop(generation: firstActivation.generation)
        await watcher.updateConfiguration(new)
        try Data("second".utf8).write(to: root.appendingPathComponent("2026_second_story_rome_it.wav"))
        let secondActivation = try await watcher.activate()
        _ = try await watcher.reconcile(profileID: "p")
        let jobs = try await repository.list().sorted {
            if $0.relativeSourcePath != $1.relativeSourcePath {
                return $0.relativeSourcePath < $1.relativeSourcePath
            }
            return $0.generation < $1.generation
        }
        #expect(jobs.map(\.relativeSourcePath) == [
            "2026_first_story_rome_it.wav",
            "2026_first_story_rome_it.wav",
            "2026_second_story_rome_it.wav"
        ])
        #expect(jobs.map(\.relativeOutputPath) == [
            "2026_first_story_rome_it.txt",
            "2026_first_story_rome_it.txt",
            "2026_second_story_rome_it.txt"
        ])
        #expect(jobs.map(\.configuration) == [old, new, new])
        #expect(jobs.map(\.state) == [.cancelled, .pending, .pending])
        #expect(jobs.map(\.generation) == [1, 2, 1])
        await watcher.stop(generation: secondActivation.generation)
    }

    @Test("coordinator selects transcriber from each job stamped configuration")
    func stampedTranscriberRouting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
        let old = BatchTranscriptionConfiguration(identifier: "old-provider|en|5", sourceLanguage: "en")
        let new = BatchTranscriptionConfiguration(identifier: "new-provider|de|9", sourceLanguage: "de")
        for (name, configuration) in [("2026_first_story_rome_it.wav", old), ("2026_second_story_rome_it.wav", new)] {
            let source = root.appendingPathComponent(name)
            try Data(name.utf8).write(to: source)
            let fingerprint = try AtomicCompanionWriter.fingerprint(sourceURL: source)
            _ = try await repository.enqueue(BatchJob(
                profileID: "p",
                relativeSourcePath: name,
                relativeOutputPath: source.deletingPathExtension().appendingPathExtension("txt").lastPathComponent,
                sourceFingerprint: fingerprint,
                configuration: configuration
            ))
        }
        let calls = TranscriberCalls()
        let coordinator = BatchTranscriptionCoordinator(repository: repository, configuration: old, transcriber: LabeledTranscriber(label: "old", calls: calls), writer: AtomicCompanionWriter())
        await coordinator.updateTranscriber(LabeledTranscriber(label: "new", calls: calls), for: new)
        await coordinator.processPending(in: root)

        #expect(await calls.values == ["new"])
        let jobs = try await repository.list()
        #expect(jobs.first(where: { $0.configuration.identifier == old.identifier })?.state == .pending)
        #expect(jobs.first(where: { $0.configuration.identifier == new.identifier })?.state == .completed)
    }

    @Test("batch local route uses the shared local ASR engine and never calls cloud")
    func batchLocalRouteUsesSharedASREngine() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audioURL = root.appendingPathComponent("local.wav")
        try writeBatchRoutingTestWAV(to: audioURL)

        let descriptor = try #require(NativeModelCatalog.descriptor(for: "whisper-small-multilingual"))
        var settings = AppSettings.defaults
        settings.localAsrModels[descriptor.id] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            path: root.path,
            runtime: descriptor.settingsRuntime
        )
        settings.defaultSourceLang = "English"
        let batchKey = BatchConfigurationKey(settings: settings)
        #expect(batchKey.sourceLanguage == NativeLanguagePolicy.autoCode)
        #expect(
            BatchTranscriptionConfiguration(
                identifier: batchKey.identifier,
                sourceLanguage: batchKey.sourceLanguage
            ).sourceLanguage == NativeLanguagePolicy.autoCode
        )

        let previousVerificationBypass = LocalModelVerification.skipVerificationForTesting
        LocalModelVerification.skipVerificationForTesting = true
        defer { LocalModelVerification.skipVerificationForTesting = previousVerificationBypass }

        let localCalls = BatchRoutingASRCalls()
        let cloudCalls = BatchRoutingCloudCalls()
        let factories = LocalASREngineRouterFactories(
            whisperKit: { model in
                BatchRoutingLocalASREngine(
                    descriptor: model.descriptor,
                    calls: localCalls
                )
            },
            parakeet: { _ in
                throw LocalASREngineError.unsupportedModel("unexpected Parakeet route")
            },
            canary: { _ in
                throw LocalASREngineError.unsupportedModel("unexpected Canary route")
            }
        )
        let pipeline = NativeProcessingPipeline(
            localASRRouter: LocalASREngineRouter(factories: factories),
            cloudTranscriptionEngine: BatchRoutingCloudTranscriber(calls: cloudCalls)
        )
        let transcriber = pipeline.makeBatchAudioTranscriber(
            workspaceRoot: root.appendingPathComponent("work"),
            sourceLang: "English",
            settings: settings,
            providerID: descriptor.id
        )

        let result = try await transcriber.transcribe(
            sourceURL: audioURL,
            resumedCheckpoints: [],
            progress: { _ in },
            checkpoint: { _ in }
        )

        #expect(result.checkpoints.map(\.text) == ["local"])
        let requests = await localCalls.requests
        #expect(requests.count == 1)
        #expect(requests.first?.languageHint == "auto")
        #expect(requests.first?.translateToEnglish == false)
        #expect(await cloudCalls.value == 0)
    }

    @Test("reconfiguration drains old work once and routes the next job with its stamped configuration")
    func reconfigurationDrainsBeforeNewRouting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
        let old = BatchTranscriptionConfiguration(identifier: "old|en|5", sourceLanguage: "en")
        let new = BatchTranscriptionConfiguration(identifier: "new|de|9", sourceLanguage: "de")
        var inserted: [BatchJob] = []
        for (name, configuration) in [("2026_first_story_rome_it.wav", old), ("2026_second_story_rome_it.wav", new)] {
            let source = root.appendingPathComponent(name)
            try Data(name.utf8).write(to: source)
            let fingerprint = try AtomicCompanionWriter.fingerprint(sourceURL: source)
            guard case let .inserted(job) = try await repository.enqueue(BatchJob(
                profileID: "p",
                relativeSourcePath: name,
                relativeOutputPath: source.deletingPathExtension().appendingPathExtension("txt").lastPathComponent,
                sourceFingerprint: fingerprint,
                configuration: configuration
            )) else { return }
            inserted.append(job)
        }
        let calls = TranscriberCalls()
        let oldTranscriber = BlockingLabeledTranscriber(label: "old", calls: calls)
        let writes = WriteCounter()
        let coordinator = BatchTranscriptionCoordinator(repository: repository, configuration: old, transcriber: oldTranscriber, writer: CountingWriter(writes: writes))
        await coordinator.registerFolder(profileID: "p", url: root)
        let processing = Task { await coordinator.processPending() }
        await oldTranscriber.waitUntilStarted()

        processing.cancel()
        await coordinator.cancelAllAndWait()
        await processing.value
        await coordinator.updateTranscriber(LabeledTranscriber(label: "new", calls: calls), for: new)
        await coordinator.processPending()

        #expect(await calls.values == ["old", "new"])
        #expect(await writes.value == 1)
        #expect(try await repository.job(id: inserted[0].id)?.state == .cancelled)
        #expect(try await repository.job(id: inserted[1].id)?.state == .completed)
    }

    @Test("batch configuration key tracks requireCanonicalNames and ignores unrelated settings")
    @MainActor
    func batchConfigurationKeyScope() {
        var settings = AppSettings.defaults
        let initial = BatchConfigurationKey(settings: settings)
        settings.theme = settings.theme == .dark ? .light : .dark
        #expect(BatchConfigurationKey(settings: settings) == initial)
        settings.chunkDurationMin += 1
        #expect(BatchConfigurationKey(settings: settings) != initial)
        settings.chunkDurationMin -= 1
        #expect(BatchConfigurationKey(settings: settings) == initial)
        settings.defaultSourceLang = "English"
        #expect(BatchConfigurationKey(settings: settings) == initial)
        settings.requireCanonicalNames = false
        #expect(BatchConfigurationKey(settings: settings) != initial)
    }

    @Test("requireCanonicalNames defaults to true and round-trips in AppSettings")
    func requireCanonicalNamesSettingsRoundTrip() throws {
        let defaults = AppSettings.defaults
        #expect(defaults.requireCanonicalNames == true)

        var modified = defaults
        modified.requireCanonicalNames = false
        let data = try JSONEncoder().encode(modified)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.requireCanonicalNames == false)

        // Decoding JSON without requireCanonicalNames key defaults to true
        let emptyJSON = Data("{}".utf8)
        let decodedEmpty = try JSONDecoder().decode(AppSettings.self, from: emptyJSON)
        #expect(decodedEmpty.requireCanonicalNames == true)
    }

    @Test("setEditingProvider writes settings translationProvider like setTranslationProvider")
    @MainActor
    func setEditingProviderWritesSettings() async throws {
        let box = SettingsPersistenceBox()
        var initialSettings = AppSettings.defaults
        initialSettings.geminiKey = "test-gemini-key"
        let store = WorkflowStore(
            settings: initialSettings,
            projects: [],
            settingsPersistence: { box.saved = $0 },
            projectsPersistence: { _ in },
            startInitialModelScan: false
        )
        store.setEditingProvider("gemini-cloud")
        #expect(store.settings.translationProvider == "gemini-cloud")
        for _ in 0..<100 where box.saved?.translationProvider != "gemini-cloud" {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(box.saved?.translationProvider == "gemini-cloud")
    }

    @Test("retry after automatic failures keeps original error, resets attempt, and allows fresh run")
    func retryPreservesErrorAndResetsAttempt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceName = "2026_retry_story_oslo_no.wav"
        let source = root.appendingPathComponent(sourceName)
        try Data("audio".utf8).write(to: source)
        let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
        let fingerprint = try AtomicCompanionWriter.fingerprint(sourceURL: source)
        var job = BatchJob(
            profileID: "p",
            relativeSourcePath: sourceName,
            relativeOutputPath: "2026_retry_story_oslo_no.txt",
            sourceFingerprint: fingerprint,
            configuration: .init(identifier: "c", sourceLanguage: "en")
        )
        job.attempt = 3
        job.lastError = "Original provider error"
        guard case let .inserted(inserted) = try await repository.enqueue(job) else { return }

        let calls = CallCounter()
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: .init(identifier: "c", sourceLanguage: "en"),
            transcriber: CountingTranscriber(calls: calls),
            writer: AtomicCompanionWriter(),
            maxAttempts: 3
        )

        // Fourth automatic attempt should not process and must keep original lastError
        await coordinator.processPending(in: root)
        var result = try await repository.job(id: inserted.id)
        #expect(result?.state == .failed)
        #expect(result?.lastError == "Original provider error")
        #expect(await calls.value == 0)

        // Manual retry resets attempt budget and keeps lastError until new run
        try await repository.retry(id: inserted.id)
        result = try await repository.job(id: inserted.id)
        #expect(result?.state == .pending)
        #expect(result?.attempt == 0)
        #expect(result?.lastError == "Original provider error")
        // Coordinator now processes the retried job successfully with a working transcriber
        let successCalls = TranscriberCalls()
        await coordinator.updateTranscriber(
            LabeledTranscriber(label: "success", calls: successCalls),
            for: job.configuration
        )
        await coordinator.processPending(in: root)
        result = try await repository.job(id: inserted.id)
        #expect(result?.state == .completed)
        #expect(result?.attempt == 1)
        #expect(result?.lastError == nil)
        #expect(await successCalls.values == ["success"])
    }

    @Test("batch provider options are partitioned into cloud and local groups with no stubs")
    func batchProviderOptionsPartitioning() {
        var settings = AppSettings.defaults
        settings.geminiKey = "AIzaSyDummyGeminiKey"
        settings.geminiKeys = ["AIzaSyDummyGeminiKey"]

        let options = ProviderRegistry.availableTranscriptionProviders(settings: settings)
        let cloud = options.filter { $0.group == .cloud }
        let local = options.filter { $0.group == .local }

        #expect(cloud.contains(where: { $0.id == "gemini-cloud" }))
        #expect(!cloud.contains(where: { $0.id == "coreml-whisperkit" }))
        #expect(!local.contains(where: { $0.id == "coreml-whisperkit" }))
    }

    @Test("batch favorite model options include starred models for gemini and openrouter")
    @MainActor
    func batchFavoriteModelsSelection() {
        var settings = AppSettings.defaults
        settings.favoriteCloudModelIDs = ["gemini-2.5-pro", "openai/whisper-large-v3"]
        let store = WorkflowStore(settings: settings, projects: [], settingsPersistence: { _ in }, projectsPersistence: { _ in }, startInitialModelScan: false)

        let geminiModels = store.settings.favoriteModels(for: "gemini-cloud")
        #expect(geminiModels.contains("gemini-2.5-pro"))
        #expect(!geminiModels.contains("openai/whisper-large-v3"))

        let openrouterModels = store.settings.favoriteModels(for: "openrouter")
        #expect(openrouterModels.contains("openai/whisper-large-v3"))
        #expect(!openrouterModels.contains("gemini-2.5-pro"))
    }
    @Test("Canary Flash and 1B block Batch before queue, watch, or provider mutation")
    @MainActor
    func canaryBatchModelsBlockBeforeMutation() async throws {
        for modelID in ["canary-180m-flash-coreml", "canary-1b-v2-coreml"] {
            try await assertCanaryBatchStartBlocked(modelID: modelID)
        }
    }
}
@MainActor
private func assertCanaryBatchStartBlocked(modelID: String) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("VaniScriptBatchCanary-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repository = try SQLiteBatchJobRepository(url: root.appendingPathComponent("jobs.sqlite"))
    let oldConfiguration = BatchTranscriptionConfiguration(identifier: "old-config", sourceLanguage: NativeLanguagePolicy.autoCode)
    let interrupted = BatchJob(
        profileID: "profile",
        relativeSourcePath: "2026_interrupted_story_city_us.wav",
        relativeOutputPath: "2026_interrupted_story_city_us.txt",
        sourceFingerprint: SourceFileFingerprint(byteCount: 1, modificationTimeNanoseconds: 1, sha256: "interrupted"),
        configuration: oldConfiguration
    )
    guard case let .inserted(interruptedInserted) = try await repository.enqueue(interrupted) else {
        Issue.record("expected interrupted fixture")
        return
    }
    guard let claimed = try await repository.claimNext(configurationID: oldConfiguration.identifier),
          claimed.id == interruptedInserted.id
    else {
        Issue.record("expected interrupted fixture to be claimed")
        return
    }
    #expect(claimed.state == .processing)

    let pending = BatchJob(
        profileID: "profile",
        relativeSourcePath: "2026_pending_story_city_us.wav",
        relativeOutputPath: "2026_pending_story_city_us.txt",
        sourceFingerprint: SourceFileFingerprint(byteCount: 1, modificationTimeNanoseconds: 1, sha256: "pending"),
        configuration: oldConfiguration
    )
    guard case let .inserted(inserted) = try await repository.enqueue(pending) else {
        Issue.record("expected pending fixture")
        return
    }

    let descriptor = try #require(NativeModelCatalog.descriptor(for: modelID))
    #expect(!descriptor.capabilities.supportsAutoLanguageDetect)
    let message = "\(descriptor.displayName) cannot run mixed-language Batch because it requires an explicit source language. Batch uses Auto Detect; choose Whisper Large v3, Parakeet TDT 0.6B v3, or a cloud provider."
    let profilesURL = root.appendingPathComponent("profiles.json")
    let profileStore = SecurityScopedFolderStore(
        profilesURL: profilesURL,
        resolveBookmark: { _ in (root, false) },
        startAccess: { _ in true },
        stopAccess: { _ in }
    )
    try profileStore.save([
        BatchFolderProfile(
            id: "profile",
            name: "Fixture",
            bookmarkData: Data([1]),
            displayPath: root.path
        )
    ])
    let watchStarts = WatchStartCounter()
    let watcher = WatchedFolderService(
        store: profileStore,
        repository: repository,
        configuration: oldConfiguration,
        stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true }),
        startWatching: { _, _ in
            watchStarts.increment()
            return {}
        }
    )
    let providerCalls = CallCounter()
    let coordinator = BatchTranscriptionCoordinator(
        repository: repository,
        configuration: oldConfiguration,
        transcriber: CountingTranscriber(calls: providerCalls),
        writer: AtomicCompanionWriter()
    )
    let blockedConfiguration = BatchTranscriptionConfiguration(
        identifier: "blocked-\(modelID)",
        sourceLanguage: NativeLanguagePolicy.autoCode
    )
    let runtime = BatchTranscriptionStore.RuntimeConfiguration(
        configuration: blockedConfiguration,
        providerDisplayName: descriptor.displayName,
        transcriber: CountingTranscriber(calls: providerCalls),
        startBlockMessage: message
    )
    let store = BatchTranscriptionStore(
        profileStore: profileStore,
        repository: repository,
        watcher: watcher,
        coordinator: coordinator,
        configuration: oldConfiguration,
        providerDisplayName: "Old",
        configurationProvider: { runtime }
    )
    let before = try await repository.job(id: inserted.id)
    await store.restore()
    for _ in 0..<100 where store.jobs.first(where: { $0.id == interruptedInserted.id })?.state != .pending {
        try await Task.sleep(for: .milliseconds(5))
    }
    let recovered = try await repository.job(id: interruptedInserted.id)

    #expect(recovered?.state == .pending)
    #expect(recovered?.lastError == "Recovered after interruption")
    #expect(store.jobs.first(where: { $0.id == interruptedInserted.id })?.state == .pending)
    await store.start()
    let after = try await repository.job(id: inserted.id)

    #expect(after == before)
    #expect(!store.isProcessing)
    #expect(store.jobs.first(where: { $0.id == interruptedInserted.id })?.state == .pending)
    #expect(await providerCalls.value == 0)
    #expect(watchStarts.value == 0)
    #expect(!store.isRunning)
    #expect(store.statusMessage == message)
    #expect(store.startBlockMessage == message)
}


private actor EventLog {
    private(set) var values: [String] = []
    private var concurrency = 0
    private(set) var maximumConcurrency = 0
    func run(_ value: String, delay: Duration = .zero) async {
        concurrency += 1
        maximumConcurrency = max(maximumConcurrency, concurrency)
        if delay > .zero { try? await Task.sleep(for: delay) }
        values.append(value)
        concurrency -= 1
    }
}

private actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
private final class WatchStartCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private struct CountingTranscriber: BatchAudioTranscribing {
    let calls: CallCounter
    func transcribe(sourceURL: URL, resumedCheckpoints: [BatchChunkCheckpoint], progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void, checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void) async throws -> BatchTranscriptionResult {
        await calls.increment()
        throw CocoaError(.fileReadCorruptFile)
    }
}

private actor TranscriberCalls {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

private struct LabeledTranscriber: BatchAudioTranscribing {
    let label: String
    let calls: TranscriberCalls

    func transcribe(
        sourceURL: URL,
        resumedCheckpoints: [BatchChunkCheckpoint],
        progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void,
        checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void
    ) async throws -> BatchTranscriptionResult {
        await calls.append(label)
        let cue = TranscriptCue(startSec: 0, endSec: 1, text: label)
        let value = BatchChunkCheckpoint(index: 0, text: label, cues: [cue])
        try await checkpoint([value])
        try await progress(BatchTranscriptionProgress(fraction: 1, totalChunks: 1, detail: BatchProgressDetail(phase: .transcribing)))
        return BatchTranscriptionResult(duration: 1, checkpoints: [value])
    }
}

private actor BlockingLabeledTranscriber: BatchAudioTranscribing {
    let label: String
    let calls: TranscriberCalls
    private var started = false

    init(label: String, calls: TranscriberCalls) {
        self.label = label
        self.calls = calls
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func transcribe(
        sourceURL: URL,
        resumedCheckpoints: [BatchChunkCheckpoint],
        progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void,
        checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void
    ) async throws -> BatchTranscriptionResult {
        started = true
        await calls.append(label)
        try await Task.sleep(for: .seconds(60))
        return BatchTranscriptionResult(duration: 0, checkpoints: [])
    }
}

private actor WriteCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private struct CountingWriter: BatchCompanionWriting {
    let writes: WriteCounter

    func write(
        _ data: Data,
        sourceURL: URL,
        outputURL: URL,
        expectedSourceFingerprint: SourceFileFingerprint,
        knownGeneratedOutput: GeneratedOutputFingerprint?
    ) async throws -> GeneratedOutputFingerprint {
        await writes.increment()
        return try await AtomicCompanionWriter().write(
            data,
            sourceURL: sourceURL,
            outputURL: outputURL,
            expectedSourceFingerprint: expectedSourceFingerprint,
            knownGeneratedOutput: knownGeneratedOutput
        )
    }
}

private final class SettingsPersistenceBox: @unchecked Sendable {
    var saved: AppSettings?
}

private actor BatchRoutingASRCalls {
    private(set) var requests: [LocalASRRequest] = []

    func record(_ request: LocalASRRequest) {
        requests.append(request)
    }
}

private actor BatchRoutingCloudCalls {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private actor BatchRoutingLocalASREngine: LocalASREngine {
    nonisolated let descriptor: LocalASRModelDescriptor
    private let calls: BatchRoutingASRCalls

    init(descriptor: LocalASRModelDescriptor, calls: BatchRoutingASRCalls) {
        self.descriptor = descriptor
        self.calls = calls
    }
    func transcribe(
        _ request: LocalASRRequest,
        progress: @escaping LocalASRProgressObserver
    ) async throws -> LocalASRResult {
        await calls.record(request)
        return LocalASRResult(
            text: "local",
            cues: [TranscriptCue(startSec: 0, endSec: 1, text: "local")]
        )
    }

    func unload() async {}
}

private actor BatchRoutingCloudTranscriber: NativeCloudAudioTranscribing {
    private let calls: BatchRoutingCloudCalls

    init(calls: BatchRoutingCloudCalls) {
        self.calls = calls
    }

    func transcribe(
        audioURL: URL,
        sourceLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        provider: ActiveCloudTranscriptionProvider,
        promptPresets: [String: PromptPresetSettings],
        chunkStartSec: Double,
        chunkEndSec: Double
    ) async throws -> CloudAudioTranscriptionResult {
        await calls.increment()
        return CloudAudioTranscriptionResult(text: "cloud", cues: [])
    }
}

private enum BatchRoutingTestAudioError: Error {
    case cannotCreateBuffer
}

private func writeBatchRoutingTestWAV(to url: URL) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16_000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: true
    ]
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    ),
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000) else {
        throw BatchRoutingTestAudioError.cannotCreateBuffer
    }
    buffer.frameLength = 16_000
    let file = try AVAudioFile(
        forWriting: url,
        settings: settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )
    try file.write(from: buffer)
}
