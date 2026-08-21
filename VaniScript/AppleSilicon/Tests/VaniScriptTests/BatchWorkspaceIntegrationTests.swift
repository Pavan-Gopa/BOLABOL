import Foundation
import Combine
import Testing
import VaniScriptCore
import VaniScriptRuntime
@testable import VaniScript

@Suite("Batch workspace integration")
struct BatchWorkspaceIntegrationTests {
    @Test("folder fixture creates exact-stem timed companion without project artifacts and deduplicates")
    func exactStemTimedCompanion() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("2026_field_story_berlin_de.wav")
        try Data("audio".utf8).write(to: source)
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profile = BatchFolderProfile(id: "folder", name: "Folder")
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")
        let reconciler = FolderReconciler()

        let first = try await reconciler.reconcile(folderURL: fixture.root, profile: profile, configuration: configuration, repository: repository)
        #expect(first.enqueued.count == 1)
        let coordinator = BatchTranscriptionCoordinator(repository: repository, configuration: configuration, transcriber: FixtureTranscriber(), writer: AtomicCompanionWriter())
        await coordinator.processPending(in: fixture.root)

        let output = fixture.root.appendingPathComponent("2026_field_story_berlin_de.txt")
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(try String(contentsOf: output, encoding: .utf8) == "[00:00:00.000 - 00:00:01.250] first\n\n[00:00:01.250 - 00:00:02.000] second\n")
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("projects.json").path))
        let repeated = try await reconciler.reconcile(folderURL: fixture.root, profile: profile, configuration: configuration, repository: repository)
        #expect(repeated.enqueued.isEmpty)
        #expect(repeated.duplicateCount == 1)
    }

    @Test("archive names enqueue with exact-stem companions while spaces remain visible issues")
    func archiveNamingAndIssues() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let names = [
            "2023-01-16_KKS-CC-Raghunatha-das-goswami_Amsterdam_nl.wav",
            "2023-02-16_KKS-SB-Prabhupada_Amsterdam_nl.mp3",
            "2026_KKS_Lecture_Paris_fr.wav",
            "2022-01-15_KKS-nterview preview_Vrindavan_in.mp3"
        ]
        for name in names {
            try Data(name.utf8).write(to: fixture.root.appendingPathComponent(name))
        }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let result = try await FolderReconciler().reconcile(
            folderURL: fixture.root,
            profile: BatchFolderProfile(id: "folder", name: "Folder"),
            configuration: BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en"),
            repository: repository
        )

        #expect(result.enqueued.map(\.relativeOutputPath).sorted() == [
            "2023-01-16_KKS-CC-Raghunatha-das-goswami_Amsterdam_nl.txt",
            "2023-02-16_KKS-SB-Prabhupada_Amsterdam_nl.txt",
            "2026_KKS_Lecture_Paris_fr.txt"
        ])
        #expect(result.issues.count == 1)
        #expect(result.issues[0].relativePath == "2022-01-15_KKS-nterview preview_Vrindavan_in.mp3")
        #expect(result.issues[0].reason.contains("spaces are not allowed"))
    }

    @Test("toggle off enqueues My Lecture.mp3 to My Lecture.txt with no issue while toggle on rejects spaces")
    func canonicalNamesToggleEnqueuesNonCanonicalFiles() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let file = fixture.root.appendingPathComponent("My Lecture.mp3")
        try Data("audio".utf8).write(to: file)

        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let reconciler = FolderReconciler()
        let profile = BatchFolderProfile(id: "folder", name: "Folder")
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")

        // Toggle off (requireCanonicalNames: false)
        let offResult = try await reconciler.reconcile(
            folderURL: fixture.root,
            profile: profile,
            configuration: configuration,
            repository: repository,
            requireCanonicalNames: false
        )
        #expect(offResult.enqueued.count == 1)
        #expect(offResult.enqueued[0].relativeSourcePath == "My Lecture.mp3")
        #expect(offResult.enqueued[0].relativeOutputPath == "My Lecture.txt")
        #expect(offResult.issues.isEmpty)

        // New database for toggle on
        let fixtureOn = try BatchFixture()
        defer { fixtureOn.remove() }
        let fileOn = fixtureOn.root.appendingPathComponent("My Lecture.mp3")
        try Data("audio".utf8).write(to: fileOn)
        let repositoryOn = try SQLiteBatchJobRepository(url: fixtureOn.database)

        // Toggle on (requireCanonicalNames: true)
        let onResult = try await reconciler.reconcile(
            folderURL: fixtureOn.root,
            profile: profile,
            configuration: configuration,
            repository: repositoryOn,
            requireCanonicalNames: true
        )
        #expect(onResult.enqueued.isEmpty)
        #expect(onResult.issues.count == 1)
        #expect(onResult.issues[0].relativePath == "My Lecture.mp3")
        #expect(onResult.issues[0].reason.contains("spaces are not allowed"))
    }

    @Test("store scan reads live canonical-name policy and preserves arbitrary filename stems")
    @MainActor
    func storeScanUsesLiveCanonicalNamePolicy() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profileStore = SecurityScopedFolderStore(
            profilesURL: fixture.root.appendingPathComponent("profiles.json"),
            resolveBookmark: { _ in (fixture.root, false) },
            startAccess: { _ in true },
            stopAccess: { _ in }
        )
        let profile = BatchFolderProfile(
            id: "folder",
            name: "Folder",
            bookmarkData: Data([1]),
            displayPath: fixture.root.path
        )
        try profileStore.save([profile])
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")
        let transcriber = FixtureTranscriber()
        let canonicalNamePolicy = CanonicalNamePolicyBox(true)
        let watcher = WatchedFolderService(
            store: profileStore,
            repository: repository,
            configuration: configuration,
            stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true }),
            startWatching: { _, _ in
                return {}
            }
        )
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: configuration,
            transcriber: transcriber,
            writer: AtomicCompanionWriter()
        )
        let store = BatchTranscriptionStore(
            profileStore: profileStore,
            repository: repository,
            watcher: watcher,
            coordinator: coordinator,
            configuration: configuration,
            providerDisplayName: "Fixture",
            requireCanonicalNames: true,
            configurationProvider: {
                BatchTranscriptionStore.RuntimeConfiguration(
                    configuration: configuration,
                    providerDisplayName: "Fixture",
                    transcriber: transcriber,
                    requireCanonicalNames: canonicalNamePolicy.requireCanonicalNames
                )
            },
            notify: { _, _ in }
        )
        let sourceName = "My Lecture.mp3"
        try Data("audio".utf8).write(to: fixture.root.appendingPathComponent(sourceName))

        await store.restore()
        await store.scan()
        #expect(store.issues.count == 1)
        #expect(store.issues.first?.relativePath == sourceName)
        #expect(store.issues.first?.reason.contains("spaces are not allowed") == true)
        #expect(try await repository.list().isEmpty)

        canonicalNamePolicy.requireCanonicalNames = false
        await store.scan()
        #expect(store.issues.isEmpty)
        let jobs = try await repository.list()
        #expect(jobs.count == 1)
        #expect(jobs.first?.state == .pending)
        #expect(jobs.first?.relativeSourcePath == sourceName)
        #expect(jobs.first?.relativeOutputPath == "My Lecture.txt")
    }

    @Test("late strict reconciliation respects live canonical-name policy")
    @MainActor
    func lateStrictReconciliationRespectsLiveCanonicalNamePolicy() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profileStore = SecurityScopedFolderStore(
            profilesURL: fixture.root.appendingPathComponent("profiles.json"),
            resolveBookmark: { _ in (fixture.root, false) },
            startAccess: { _ in true },
            stopAccess: { _ in }
        )
        try profileStore.save([
            BatchFolderProfile(
                id: "folder",
                name: "Folder",
                bookmarkData: Data([1]),
                displayPath: fixture.root.path
            )
        ])
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")
        let transcriber = FixtureTranscriber()
        let canonicalNamePolicy = CanonicalNamePolicyBox(true)
        let watcher = WatchedFolderService(
            store: profileStore,
            repository: repository,
            configuration: configuration,
            stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true }),
            startWatching: { _, _ in {} }
        )
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: configuration,
            transcriber: transcriber,
            writer: AtomicCompanionWriter()
        )
        let store = BatchTranscriptionStore(
            profileStore: profileStore,
            repository: repository,
            watcher: watcher,
            coordinator: coordinator,
            configuration: configuration,
            providerDisplayName: "Fixture",
            requireCanonicalNames: true,
            configurationProvider: {
                BatchTranscriptionStore.RuntimeConfiguration(
                    configuration: configuration,
                    providerDisplayName: "Fixture",
                    transcriber: transcriber,
                    requireCanonicalNames: canonicalNamePolicy.requireCanonicalNames
                )
            },
            notify: { _, _ in }
        )
        let collision = BatchReconciliationIssue.outputCollision(
            relativePath: "2026_story.wav",
            existingName: "2026_story.txt"
        )
        let strictResult = BatchReconciliationResult(
            enqueued: [],
            duplicateCount: 0,
            issues: [
                .invalidName(relativePath: "My Lecture.mp3", violations: [.spaceNotAllowed]),
                collision
            ]
        )
        await store.restore()
        let generation = try #require(store.activeWatcherGeneration)
        let event = WatchedFolderReconciliationEvent(
            generation: generation,
            profileID: "folder",
            folderURL: fixture.root,
            outcome: .completed(strictResult)
        )
        store.recordReconciliation(event)
        #expect(store.issues == strictResult.issues)

        canonicalNamePolicy.requireCanonicalNames = false
        store.recordReconciliation(event)
        #expect(store.issues == [collision])
    }

    @Test("restart recovery, invalid names, user edits, and one-file failure remain isolated")
    func recoveryAndIsolation() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profile = BatchFolderProfile(id: "folder", name: "Folder")
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")
        for name in ["2026_good_story_rome_it.wav", "2026_zbad_story_rome_it.wav", "not canonical.wav"] {
            try Data(name.utf8).write(to: fixture.root.appendingPathComponent(name))
        }
        let scan = try await FolderReconciler().reconcile(folderURL: fixture.root, profile: profile, configuration: configuration, repository: repository)
        #expect(scan.enqueued.count == 2)
        #expect(scan.issues.count == 1)
        guard let interrupted = scan.enqueued.first(where: { $0.relativeSourcePath.contains("good") }) else { return }
        _ = try await repository.claimNext(configurationID: configuration.identifier)
        #expect(try await repository.recoverInterrupted() == 1)
        #expect(try await repository.job(id: interrupted.id)?.state == .pending)

        let coordinator = BatchTranscriptionCoordinator(repository: repository, configuration: configuration, transcriber: FailingFixtureTranscriber(), writer: AtomicCompanionWriter())
        await coordinator.processPending(in: fixture.root)
        let jobs = try await repository.list()
        #expect(jobs.filter { $0.state == .completed }.count == 1)
        #expect(jobs.filter { $0.state == .failed }.count == 1)

        let output = fixture.root.appendingPathComponent("2026_good_story_rome_it.txt")
        try Data("changed audio".utf8).write(to: fixture.root.appendingPathComponent("2026_good_story_rome_it.wav"))
        let nextScan = try await FolderReconciler().reconcile(folderURL: fixture.root, profile: profile, configuration: configuration, repository: repository)
        guard let regenerated = nextScan.enqueued.first(where: { $0.relativeSourcePath.contains("good") }) else { return }
        try Data("user edit".utf8).write(to: output)
        await coordinator.processPending(in: fixture.root)
        #expect(try String(contentsOf: output, encoding: .utf8) != "user edit")
        #expect(try await repository.job(id: regenerated.id)?.state == .completed)
    }
    @Test("watch signal enqueues pending work and store start processes to completion")
    @MainActor
    func watchSignalAutomaticallyProcessesWork() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profileStore = SecurityScopedFolderStore(
            profilesURL: fixture.root.appendingPathComponent("profiles.json"),
            resolveBookmark: { _ in (fixture.root, false) },
            startAccess: { _ in true },
            stopAccess: { _ in }
        )
        try profileStore.save([
            BatchFolderProfile(
                id: "folder",
                name: "Folder",
                bookmarkData: Data([1]),
                displayPath: fixture.root.path
            )
        ])
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")
        let signal = BatchWatchSignal()
        let bridge = BatchStoreBridge()
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: configuration,
            transcriber: FixtureTranscriber(),
            writer: AtomicCompanionWriter()
        )
        let watcher = WatchedFolderService(
            store: profileStore,
            repository: repository,
            configuration: configuration,
            stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true }),
            coalescingDelay: .zero,
            startWatching: { _, callback in
                signal.store(callback)
                return {}
            },
            didReconcile: { event in
                await MainActor.run { bridge.store?.recordReconciliation(event) }
            }
        )
        let store = BatchTranscriptionStore(
            profileStore: profileStore,
            repository: repository,
            watcher: watcher,
            coordinator: coordinator,
            configuration: configuration,
            providerDisplayName: "Fixture",
            notify: { _, _ in }
        )
        bridge.store = store
        await store.restore()

        let source = fixture.root.appendingPathComponent("2026_signal_story_london_gb.wav")
        try Data("audio".utf8).write(to: source)
        signal.fire()
        let output = fixture.root.appendingPathComponent("2026_signal_story_london_gb.txt")

        for _ in 0..<100 where store.jobs.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.jobs.map(\.state) == [.pending])
        #expect(!FileManager.default.fileExists(atPath: output.path))

        await store.start()
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: output.path) {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(try await repository.list().map(\.state) == [.completed])
        for _ in 0..<100 where store.isRunning || store.isReconciling {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!store.isRunning)
        #expect(!store.isReconciling)
        await store.stop()
    }

    @Test("add folder and scan enqueues pending jobs without transcribing until Start")
    @MainActor
    func addFolderAndScanEnqueuesPendingWithoutTranscribingUntilStart() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profileStore = SecurityScopedFolderStore(
            profilesURL: fixture.root.appendingPathComponent("profiles.json"),
            resolveBookmark: { _ in (fixture.root, false) },
            startAccess: { _ in true },
            stopAccess: { _ in }
        )
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")
        let bridge = BatchStoreBridge()
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: configuration,
            transcriber: FixtureTranscriber(),
            writer: AtomicCompanionWriter()
        )
        let watcher = WatchedFolderService(
            store: profileStore,
            repository: repository,
            configuration: configuration,
            stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true }),
            didReconcile: { event in
                await MainActor.run { bridge.store?.recordReconciliation(event) }
            }
        )
        let store = BatchTranscriptionStore(
            profileStore: profileStore,
            repository: repository,
            watcher: watcher,
            coordinator: coordinator,
            configuration: configuration,
            providerDisplayName: "Fixture",
            notify: { _, _ in }
        )
        bridge.store = store

        let source = fixture.root.appendingPathComponent("2026_add_story_london_gb.wav")
        try Data("audio".utf8).write(to: source)
        let output = fixture.root.appendingPathComponent("2026_add_story_london_gb.txt")

        store.addFolder(fixture.root)
        for _ in 0..<100 where store.jobs.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(store.profiles.count == 1)
        #expect(store.jobs.count == 1)
        #expect(store.jobs.first?.state == .pending)
        #expect(!store.isRunning)
        #expect(!FileManager.default.fileExists(atPath: output.path))

        await store.scan()
        #expect(store.jobs.first?.state == .pending)
        #expect(!store.isRunning)
        #expect(!FileManager.default.fileExists(atPath: output.path))

        await store.start()
        #expect(store.isRunning)
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: output.path) {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(store.jobs.first?.state == .completed)
        await store.stop()
    }

    @Test("stop cancels in-flight work and leaves jobs in list for restart")
    @MainActor
    func stopCancelsInFlightAndLeavesJobs() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profileStore = SecurityScopedFolderStore(
            profilesURL: fixture.root.appendingPathComponent("profiles.json"),
            resolveBookmark: { _ in (fixture.root, false) },
            startAccess: { _ in true },
            stopAccess: { _ in }
        )
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")
        let transcriber = PausingFixtureTranscriber()
        let bridge = BatchStoreBridge()
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: configuration,
            transcriber: transcriber,
            writer: AtomicCompanionWriter(),
            eventHandler: { event in await bridge.store?.record(event) }
        )
        let watcher = WatchedFolderService(
            store: profileStore,
            repository: repository,
            configuration: configuration,
            stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true }),
            didReconcile: { event in
                await MainActor.run { bridge.store?.recordReconciliation(event) }
            }
        )
        let store = BatchTranscriptionStore(
            profileStore: profileStore,
            repository: repository,
            watcher: watcher,
            coordinator: coordinator,
            configuration: configuration,
            providerDisplayName: "Fixture",
            notify: { _, _ in }
        )
        bridge.store = store

        let source1 = fixture.root.appendingPathComponent("2026_stop1_story_rome_it.wav")
        let source2 = fixture.root.appendingPathComponent("2026_stop2_story_rome_it.wav")
        try Data("audio 1".utf8).write(to: source1)
        try Data("audio 2".utf8).write(to: source2)

        store.addFolder(fixture.root)
        for _ in 0..<100 where store.jobs.count < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.jobs.count == 2)

        await store.start()
        await transcriber.waitUntilCheckpointed()
        for _ in 0..<100 where !store.jobs.contains(where: { $0.state == .processing }) {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.isProcessing)

        await store.stop()
        #expect(!store.isRunning)
        #expect(!store.isReconciling)
        for _ in 0..<100 where store.jobs.first(where: { $0.state == .cancelled }) == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.jobs.count == 2)
        #expect(store.profiles.count == 1)
        let cancelledJob = store.jobs.first { $0.state == .cancelled }
        #expect(cancelledJob != nil)
        if let id = cancelledJob?.id {
            await store.retry(jobID: id)
        }
        await transcriber.resume()
        await store.start()
        for _ in 0..<200 where store.jobs.filter({ $0.state == .completed }).count < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.jobs.filter({ $0.state == .completed }).count == 2)
        await store.stop()
    }

    @Test("remove profile disabled and no-ops while processing")
    @MainActor
    func removeProfileDisabledWhileProcessing() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profileStore = SecurityScopedFolderStore(
            profilesURL: fixture.root.appendingPathComponent("profiles.json"),
            resolveBookmark: { _ in (fixture.root, false) },
            startAccess: { _ in true },
            stopAccess: { _ in }
        )
        let profile = BatchFolderProfile(id: "folder", name: "Folder", bookmarkData: Data([1]), displayPath: fixture.root.path)
        try profileStore.save([profile])
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")
        let transcriber = PausingFixtureTranscriber()
        let bridge = BatchStoreBridge()
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: configuration,
            transcriber: transcriber,
            writer: AtomicCompanionWriter(),
            eventHandler: { event in await bridge.store?.record(event) }
        )
        let watcher = WatchedFolderService(
            store: profileStore,
            repository: repository,
            configuration: configuration,
            stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true })
        )
        let store = BatchTranscriptionStore(
            profileStore: profileStore,
            repository: repository,
            watcher: watcher,
            coordinator: coordinator,
            configuration: configuration,
            providerDisplayName: "Fixture",
            notify: { _, _ in }
        )
        bridge.store = store

        let source = fixture.root.appendingPathComponent("2026_remove_story_rome_it.wav")
        try Data("audio".utf8).write(to: source)
        _ = try await repository.enqueue(BatchJob(
            profileID: profile.id,
            relativeSourcePath: source.lastPathComponent,
            relativeOutputPath: "2026_remove_story_rome_it.txt",
            sourceFingerprint: try AtomicCompanionWriter.fingerprint(sourceURL: source),
            configuration: configuration
        ))
        store.refreshJobs()
        for _ in 0..<100 where store.jobs.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }

        await store.start()
        await transcriber.waitUntilCheckpointed()
        for _ in 0..<100 where !store.isProcessing {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.isProcessing)

        // Attempt remove while processing -> must no-op
        store.removeProfile(id: profile.id)
        try await Task.sleep(for: .milliseconds(20))
        #expect(store.profiles.count == 1)
        #expect(try await repository.list().count == 1)

        // Resume and complete
        await transcriber.resume()
        for _ in 0..<100 where store.isProcessing {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!store.isProcessing)

        // Remove now succeeds
        store.removeProfile(id: profile.id)
        for _ in 0..<100 where !store.profiles.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.profiles.isEmpty)
        #expect(try await repository.list().isEmpty)
        await store.stop()
    }

    @Test("detail pane falls back to processing job when unselected")
    @MainActor
    func detailFallsBackToProcessingJob() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profileStore = SecurityScopedFolderStore(
            profilesURL: fixture.root.appendingPathComponent("profiles.json"),
            resolveBookmark: { _ in (fixture.root, false) },
            startAccess: { _ in true },
            stopAccess: { _ in }
        )
        let profile = BatchFolderProfile(id: "folder", name: "Folder", bookmarkData: Data([1]), displayPath: fixture.root.path)
        try profileStore.save([profile])
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")
        let transcriber = PausingFixtureTranscriber()
        let bridge = BatchStoreBridge()
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: configuration,
            transcriber: transcriber,
            writer: AtomicCompanionWriter(),
            eventHandler: { event in await bridge.store?.record(event) }
        )
        let watcher = WatchedFolderService(
            store: profileStore,
            repository: repository,
            configuration: configuration,
            stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true })
        )
        let store = BatchTranscriptionStore(
            profileStore: profileStore,
            repository: repository,
            watcher: watcher,
            coordinator: coordinator,
            configuration: configuration,
            providerDisplayName: "Fixture",
            notify: { _, _ in }
        )
        bridge.store = store

        let source = fixture.root.appendingPathComponent("2026_detail_story_rome_it.wav")
        try Data("audio".utf8).write(to: source)
        guard case let .inserted(job) = try await repository.enqueue(BatchJob(
            profileID: profile.id,
            relativeSourcePath: source.lastPathComponent,
            relativeOutputPath: "2026_detail_story_rome_it.txt",
            sourceFingerprint: try AtomicCompanionWriter.fingerprint(sourceURL: source),
            configuration: configuration
        )) else { return }

        store.refreshJobs()
        for _ in 0..<100 where store.jobs.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }

        store.selectedJobID = nil
        #expect(store.selectedJob == nil)
        #expect(store.activeProcessingJob == nil)

        await store.start()
        await transcriber.waitUntilCheckpointed()
        for _ in 0..<100 where store.activeProcessingJob == nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        // Unselected detail pane resolves active processing job
        #expect(store.selectedJob == nil)
        #expect(store.activeProcessingJob?.id == job.id)
        #expect(store.activeProcessingJob?.state == .processing)

        // Explicit selection overrides fallback
        let otherID = UUID()
        store.selectedJobID = otherID
        #expect(store.selectedJobID == otherID)

        store.selectedJobID = nil
        #expect(store.activeProcessingJob?.id == job.id)

        await transcriber.resume()
        for _ in 0..<100 where store.isProcessing {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.activeProcessingJob == nil)
        await store.stop()
    }

    @Test("completed job open uses exact-stem TXT URL and non-completed does nothing")
    @MainActor
    func completedJobOpenUsesExactStemTxtURL() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profileStore = SecurityScopedFolderStore(
            profilesURL: fixture.root.appendingPathComponent("profiles.json"),
            resolveBookmark: { _ in (fixture.root, false) },
            startAccess: { _ in true },
            stopAccess: { _ in }
        )
        let profile = BatchFolderProfile(id: "folder", name: "Folder", bookmarkData: Data([1]), displayPath: fixture.root.path)
        try profileStore.save([profile])
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")
        let watcher = WatchedFolderService(
            store: profileStore,
            repository: repository,
            configuration: configuration,
            stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true })
        )
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: configuration,
            transcriber: FixtureTranscriber(),
            writer: AtomicCompanionWriter()
        )

        let opened = OpenURLBox()
        let store = BatchTranscriptionStore(
            profileStore: profileStore,
            repository: repository,
            watcher: watcher,
            coordinator: coordinator,
            configuration: configuration,
            providerDisplayName: "Fixture",
            notify: { _, _ in },
            workspaceOpener: { url in
                opened.record(url)
                return true
            }
        )

        let pendingJob = BatchJob(
            profileID: profile.id,
            relativeSourcePath: "pending.wav",
            relativeOutputPath: "pending.txt",
            sourceFingerprint: .init(byteCount: 1, modificationTimeNanoseconds: 1, sha256: "h"),
            configuration: configuration,
            state: .pending
        )
        let processingJob = BatchJob(
            profileID: profile.id,
            relativeSourcePath: "processing.wav",
            relativeOutputPath: "processing.txt",
            sourceFingerprint: .init(byteCount: 1, modificationTimeNanoseconds: 1, sha256: "h"),
            configuration: configuration,
            state: .processing
        )
        let completedJob = BatchJob(
            profileID: profile.id,
            relativeSourcePath: "nested/2026_completed_story_rome_it.wav",
            relativeOutputPath: "nested/2026_completed_story_rome_it.txt",
            sourceFingerprint: .init(byteCount: 1, modificationTimeNanoseconds: 1, sha256: "h"),
            configuration: configuration,
            state: .completed
        )

        #expect(!store.openCompanion(for: pendingJob))
        #expect(!store.openCompanion(for: processingJob))
        #expect(opened.urls.isEmpty)

        #expect(store.openCompanion(for: completedJob))
        let expectedURL = fixture.root.appendingPathComponent("nested/2026_completed_story_rome_it.txt")
        #expect(opened.urls == [expectedURL])
    }

    @Test("removing a profile deletes its persisted jobs and clears the store")
    @MainActor
    func removeProfileDeletesJobs() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profileStore = SecurityScopedFolderStore(profilesURL: fixture.root.appendingPathComponent("profiles.json"))
        let profile = BatchFolderProfile(id: "folder", name: "Folder")
        try profileStore.save([profile])
        let source = fixture.root.appendingPathComponent("2026_remove_story_rome_it.wav")
        try Data("audio".utf8).write(to: source)
        _ = try await repository.enqueue(BatchJob(
            profileID: profile.id,
            relativeSourcePath: source.lastPathComponent,
            relativeOutputPath: "2026_remove_story_rome_it.txt",
            sourceFingerprint: try AtomicCompanionWriter.fingerprint(sourceURL: source),
            configuration: .init(identifier: "fixture", sourceLanguage: "en")
        ))
        let watcher = WatchedFolderService(store: profileStore, repository: repository, configuration: .init(identifier: "fixture", sourceLanguage: "en"), stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true }))
        let coordinator = BatchTranscriptionCoordinator(repository: repository, configuration: .init(identifier: "fixture", sourceLanguage: "en"), transcriber: FixtureTranscriber(), writer: AtomicCompanionWriter())
        let store = BatchTranscriptionStore(profileStore: profileStore, repository: repository, watcher: watcher, coordinator: coordinator, configuration: .init(identifier: "fixture", sourceLanguage: "en"), providerDisplayName: "Fixture", notify: { _, _ in })
        store.removeProfile(id: profile.id)
        for _ in 0..<100 where !(try await repository.list()).isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(try await repository.list().isEmpty)
        #expect(store.jobs.isEmpty)
        #expect(store.profiles.isEmpty)
    }

    @Test("checkpoint events refresh live store progress and file status")
    @MainActor
    func checkpointRefreshesStore() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)

        let profileStore = SecurityScopedFolderStore(profilesURL: fixture.root.appendingPathComponent("profiles.json"))
        let sourceName = "2026_progress_story_rome_it.wav"
        let source = fixture.root.appendingPathComponent(sourceName)
        try Data("audio".utf8).write(to: source)
        let profile = BatchFolderProfile(id: "folder", name: "Folder")
        try profileStore.save([profile])
        guard case let .inserted(job) = try await repository.enqueue(BatchJob(profileID: profile.id, relativeSourcePath: sourceName, relativeOutputPath: "2026_progress_story_rome_it.txt", sourceFingerprint: try AtomicCompanionWriter.fingerprint(sourceURL: source), configuration: .init(identifier: "fixture", sourceLanguage: "en"))) else { return }
        let watcher = WatchedFolderService(store: profileStore, repository: repository, configuration: job.configuration, stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true }))
        let bridge = BatchStoreBridge()
        let transcriber = PausingFixtureTranscriber()
        let coordinator = BatchTranscriptionCoordinator(repository: repository, configuration: job.configuration, transcriber: transcriber, writer: AtomicCompanionWriter(), eventHandler: { event in await bridge.store?.record(event) })
        let store = BatchTranscriptionStore(profileStore: profileStore, repository: repository, watcher: watcher, coordinator: coordinator, configuration: job.configuration, providerDisplayName: "Fixture", notify: { _, _ in })
        bridge.store = store
        let processing = Task { await coordinator.processPending(in: fixture.root) }
        await transcriber.waitUntilCheckpointed()
        for _ in 0..<100 where store.jobs.first?.checkpoints.isEmpty != false {
            try await Task.sleep(for: .milliseconds(5))
        }
        for _ in 0..<100 where abs((store.jobs.first?.progress ?? 0) - 0.42) > 0.001 {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(store.jobs.first?.state == .processing)
        #expect(store.jobs.first?.checkpoints.count == 1)
        #expect(abs((store.jobs.first?.progress ?? 0) - 0.42) < 0.001)
        #expect(store.jobs.first?.progressStageText.contains("42%") == true)
        #expect(store.statusMessage.contains(sourceName))
        await transcriber.resume()
        await processing.value
        store.refreshJobs()
        for _ in 0..<100 where store.jobs.first?.state != .completed {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.jobs.first?.state == .completed)
        #expect(store.jobs.first?.chunkProgressLabel == "chunk 1 of 1")
        #expect(store.jobs.first?.formattedDuration != nil)
        #expect(store.statusMessage.contains("Watching 1 folder") || store.statusMessage.contains("stopped"))
    }

    @Test("completed and failed rows provide frozen duration and chunk counts")
    @MainActor
    func frozenDurationAndChunkCounts() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 1_000_075) // 75 seconds = 1m 15s
        let completedJob = BatchJob(
            profileID: "p",
            relativeSourcePath: "completed.wav",
            relativeOutputPath: "completed.txt",
            sourceFingerprint: .init(byteCount: 10, modificationTimeNanoseconds: 20, sha256: "h1"),
            configuration: .init(identifier: "fix", sourceLanguage: "en"),
            state: .completed,
            progress: 1.0,
            checkpoints: [
                .init(index: 0, text: "t0", cues: []),
                .init(index: 1, text: "t1", cues: [])
            ],
            createdAt: start,
            updatedAt: end,
            startedAt: start,
            finishedAt: end,
            totalChunks: 2
        )
        #expect(completedJob.chunkProgressLabel == "chunk 2 of 2")
        #expect(completedJob.formattedDuration == "1m 15s")

        let failedJob = BatchJob(
            profileID: "p",
            relativeSourcePath: "failed.wav",
            relativeOutputPath: "failed.txt",
            sourceFingerprint: .init(byteCount: 10, modificationTimeNanoseconds: 20, sha256: "h2"),
            configuration: .init(identifier: "fix", sourceLanguage: "en"),
            state: .failed,
            attempt: 3,
            progress: 0.5,
            checkpoints: [.init(index: 0, text: "t0", cues: [])],
            lastError: "Provider failed",
            createdAt: start,
            updatedAt: end,
            startedAt: start,
            finishedAt: end,
            totalChunks: 2
        )
        #expect(failedJob.chunkProgressLabel == "chunk 2 of 2")
        #expect(failedJob.formattedDuration == "1m 15s")

        // Verify persisted and retrieved jobs preserve timestamps, duration, and chunk count
        _ = try await repository.enqueue(completedJob)
        let loaded = try await repository.job(id: completedJob.id)
        #expect(loaded?.formattedDuration == "1m 15s")
        #expect(loaded?.chunkProgressLabel == "chunk 2 of 2")
        #expect(failedJob.lastError == "Provider failed")
    }

    @Test("current pending starts before blocked reconciliation and new admission wakes processing")
    @MainActor
    func existingCurrentPendingStartsBeforeReconciliationAndNewAdmissionWakesProcessing() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profileStore = SecurityScopedFolderStore(
            profilesURL: fixture.root.appendingPathComponent("profiles.json"),
            resolveBookmark: { _ in (fixture.root, false) },
            startAccess: { _ in true },
            stopAccess: { _ in }
        )
        try profileStore.save([
            BatchFolderProfile(id: "folder", name: "Folder", bookmarkData: Data([1]), displayPath: fixture.root.path)
        ])
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")
        let first = fixture.root.appendingPathComponent("2026_first_story_rome_it.wav")
        let second = fixture.root.appendingPathComponent("2026_second_story_rome_it.wav")
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)
        let fingerprint = try AtomicCompanionWriter.fingerprint(sourceURL: first)
        _ = try await repository.enqueue(BatchJob(
            profileID: "folder",
            relativeSourcePath: first.lastPathComponent,
            relativeOutputPath: "2026_first_story_rome_it.txt",
            sourceFingerprint: fingerprint,
            configuration: configuration
        ))

        let stability = ImmediateClaimGate()
        let transcriber = ImmediateClaimTranscriber()
        let bridge = BatchStoreBridge()
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: configuration,
            transcriber: transcriber,
            writer: AtomicCompanionWriter()
        )
        let watcher = WatchedFolderService(
            store: profileStore,
            repository: repository,
            configuration: configuration,
            stabilityProbe: FileStabilityProbe(
                delay: .zero,
                sleep: { _ in
                    await stability.enter()
                    try await stability.waitUntilReleased()
                },
                audioReadable: { _ in true }
            ),
            startWatching: { _, _ in {} },
            didReconcile: { event in
                await MainActor.run { bridge.store?.recordReconciliation(event) }
            }
        )
        let store = BatchTranscriptionStore(
            profileStore: profileStore,
            repository: repository,
            watcher: watcher,
            coordinator: coordinator,
            configuration: configuration,
            providerDisplayName: "Fixture",
            notify: { _, _ in }
        )
        bridge.store = store

        let started = Task { await store.start() }
        await transcriber.waitUntilStarted(first.lastPathComponent)
        let firstJob = try #require(try await repository.list().first { $0.relativeSourcePath == first.lastPathComponent })
        #expect(try await repository.job(id: firstJob.id)?.state == .processing)
        #expect(try await repository.list().contains(where: { $0.relativeSourcePath == second.lastPathComponent }) == false)
        await stability.waitUntilEntered()

        await transcriber.allow(first.lastPathComponent)
        await transcriber.waitUntilFinished(first.lastPathComponent)
        await stability.release()
        await transcriber.waitUntilStarted(second.lastPathComponent)
        await transcriber.allow(second.lastPathComponent)
        await started.value
        await transcriber.waitUntilFinished(second.lastPathComponent)
        var states = Set<BatchJobState>()
        for _ in 0..<200 {
            let jobs = try await repository.list()
            states = Set(jobs.map(\.state))
            if jobs.count == 2, states == [.completed] { break }
            await Task.yield()
        }
        #expect(await transcriber.calls() == [first.lastPathComponent, second.lastPathComponent])
        #expect(await transcriber.maximumConcurrency() == 1)
        #expect(try await repository.list().count == 2)
        #expect(states == [.completed])
        await store.stop()
    }

    @Test("two queued jobs keep exactly one processing then auto-stop to idle")
    @MainActor
    func twoQueuedJobsKeepExactlyOneProcessingThenAutoStop() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profileStore = SecurityScopedFolderStore(
            profilesURL: fixture.root.appendingPathComponent("profiles.json"),
            resolveBookmark: { _ in (fixture.root, false) },
            startAccess: { _ in true },
            stopAccess: { _ in }
        )
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")
        let transcriber = ImmediateClaimTranscriber()
        let bridge = BatchStoreBridge()
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: configuration,
            transcriber: transcriber,
            writer: AtomicCompanionWriter(),
            eventHandler: { event in await bridge.store?.record(event) }
        )
        let watcher = WatchedFolderService(
            store: profileStore,
            repository: repository,
            configuration: configuration,
            stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true }),
            didReconcile: { event in
                await MainActor.run { bridge.store?.recordReconciliation(event) }
            }
        )
        let store = BatchTranscriptionStore(
            profileStore: profileStore,
            repository: repository,
            watcher: watcher,
            coordinator: coordinator,
            configuration: configuration,
            providerDisplayName: "Fixture",
            notify: { _, _ in }
        )
        bridge.store = store

        let source1 = fixture.root.appendingPathComponent("2026_seq1_story_rome_it.wav")
        let source2 = fixture.root.appendingPathComponent("2026_seq2_story_rome_it.wav")
        try Data("audio 1".utf8).write(to: source1)
        try Data("audio 2".utf8).write(to: source2)

        store.addFolder(fixture.root)
        for _ in 0..<100 where store.jobs.count < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.jobs.count == 2)
        #expect(store.jobs.allSatisfy { $0.state == .pending })
        let originalJobIDs = store.jobs.map(\.id)

        let started = Task { await store.start() }
        for _ in 0..<100 where store.jobs.filter({ $0.state == .processing }).count != 1 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.jobs.filter({ $0.state == .processing }).count == 1)
        #expect(store.jobs.filter({ $0.state == .pending }).count == 1)
        #expect(store.jobs.map(\.id) == originalJobIDs)
        let first = try #require(store.jobs.first { $0.state == .processing })
        await transcriber.waitUntilStarted(first.relativeSourcePath)
        #expect(await transcriber.maximumConcurrency() == 1)

        await transcriber.allow(first.relativeSourcePath)
        await transcriber.waitUntilFinished(first.relativeSourcePath)

        for _ in 0..<100 {
            let firstDone = store.jobs.first(where: { $0.id == first.id })?.state == .completed
            let processingCount = store.jobs.filter({ $0.state == .processing }).count
            if firstDone && processingCount == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.jobs.first(where: { $0.id == first.id })?.state == .completed)
        #expect(store.jobs.filter({ $0.state == .processing }).count == 1)
        #expect(store.jobs.filter({ $0.state == .pending }).count == 0)
        #expect(store.jobs.map(\.id) == originalJobIDs)
        #expect(await transcriber.maximumConcurrency() == 1)

        let second = try #require(store.jobs.first { $0.state == .processing })
        #expect(second.id != first.id)
        await transcriber.waitUntilStarted(second.relativeSourcePath)
        await transcriber.allow(second.relativeSourcePath)

        for _ in 0..<200 where store.jobs.filter({ $0.state == .completed }).count < 2 || store.isRunning {
            try await Task.sleep(for: .milliseconds(5))
        }
        await started.value
        #expect(store.jobs.allSatisfy { $0.state == .completed })
        #expect(store.jobs.map(\.id) == originalJobIDs)
        #expect(store.jobs.filter({ $0.state == .processing }).isEmpty)
        #expect(!store.isRunning)
        #expect(!store.isProcessing)
        #expect(await transcriber.maximumConcurrency() == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("2026_seq1_story_rome_it.txt").path))
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("2026_seq2_story_rome_it.txt").path))
        await store.stop()
    }

    @Test("three queued jobs publish each sequential handoff before advancing")
    @MainActor
    func threeQueuedJobsPublishEachSequentialHandoffBeforeAdvancing() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let profileStore = SecurityScopedFolderStore(
            profilesURL: fixture.root.appendingPathComponent("profiles.json"),
            resolveBookmark: { _ in (fixture.root, false) },
            startAccess: { _ in true },
            stopAccess: { _ in }
        )
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")
        let transcriber = ImmediateClaimTranscriber()
        let bridge = BatchStoreBridge()
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: configuration,
            transcriber: transcriber,
            writer: AtomicCompanionWriter(),
            eventHandler: { event in await bridge.store?.record(event) }
        )
        let watcher = WatchedFolderService(
            store: profileStore,
            repository: repository,
            configuration: configuration,
            stabilityProbe: FileStabilityProbe(delay: .zero, sleep: { _ in }, audioReadable: { _ in true }),
            didReconcile: { event in
                await MainActor.run { bridge.store?.recordReconciliation(event) }
            }
        )
        let store = BatchTranscriptionStore(
            profileStore: profileStore,
            repository: repository,
            watcher: watcher,
            coordinator: coordinator,
            configuration: configuration,
            providerDisplayName: "Fixture",
            notify: { _, _ in }
        )
        bridge.store = store

        for (index, name) in [
            "2026_seq1_story_rome_it.wav",
            "2026_seq2_story_rome_it.wav",
            "2026_seq3_story_rome_it.wav"
        ].enumerated() {
            try Data("audio \(index)".utf8).write(to: fixture.root.appendingPathComponent(name))
        }

        store.addFolder(fixture.root)
        for _ in 0..<100 where store.jobs.count < 3 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.jobs.count == 3)
        #expect(store.jobs.allSatisfy { $0.state == .pending })
        let originalJobIDs = store.jobs.map(\.id)
        let orderedSourceNames = store.jobs.map(\.relativeSourcePath)

        var publications: [([UUID], [BatchJobState])] = []
        let subscription = store.$jobs
            .dropFirst()
            .sink { jobs in
                guard jobs.count == originalJobIDs.count else { return }
                let states = jobs.map(\.state)
                guard publications.last?.1 != states else { return }
                publications.append((jobs.map(\.id), states))
            }
        defer { subscription.cancel() }

        func waitForPublication(_ expected: [BatchJobState]) async throws {
            for _ in 0..<200 {
                if publications.contains(where: { $0.1 == expected }) { return }
                try await Task.sleep(for: .milliseconds(5))
            }
        }

        let started = Task { await store.start() }
        for _ in 0..<100 where store.jobs.filter({ $0.state == .processing }).count != 1 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.jobs.filter({ $0.state == .processing }).count == 1)
        #expect(store.jobs.map(\.id) == originalJobIDs)

        await transcriber.waitUntilStarted(orderedSourceNames[0])
        await transcriber.allow(orderedSourceNames[0])
        await transcriber.waitUntilFinished(orderedSourceNames[0])
        try await waitForPublication([.completed, .pending, .pending])
        try await waitForPublication([.completed, .processing, .pending])

        await transcriber.waitUntilStarted(orderedSourceNames[1])
        await transcriber.allow(orderedSourceNames[1])
        await transcriber.waitUntilFinished(orderedSourceNames[1])
        try await waitForPublication([.completed, .completed, .pending])
        try await waitForPublication([.completed, .completed, .processing])

        await transcriber.waitUntilStarted(orderedSourceNames[2])
        await transcriber.allow(orderedSourceNames[2])
        await transcriber.waitUntilFinished(orderedSourceNames[2])
        try await waitForPublication([.completed, .completed, .completed])
        for _ in 0..<200 where store.isRunning {
            try await Task.sleep(for: .milliseconds(5))
        }
        await started.value

        let expectedStates: [[BatchJobState]] = [
            [.processing, .pending, .pending],
            [.completed, .pending, .pending],
            [.completed, .processing, .pending],
            [.completed, .completed, .pending],
            [.completed, .completed, .processing],
            [.completed, .completed, .completed]
        ]
        var matched = 0
        for publication in publications where matched < expectedStates.count {
            if publication.1 == expectedStates[matched] {
                matched += 1
            }
        }
        #expect(matched == expectedStates.count)
        #expect(publications.allSatisfy { $0.0 == originalJobIDs })
        #expect(publications.allSatisfy {
            $0.1.filter { $0 == .processing }.count <= 1
        })
        #expect(publications.filter { $0.1.contains(.processing) }.allSatisfy {
            $0.1.filter { $0 == .processing }.count == 1
        })
        #expect(store.jobs.map(\.id) == originalJobIDs)
        #expect(store.jobs.allSatisfy { $0.state == .completed })
        #expect(!store.isRunning)
        #expect(!store.isProcessing)
        #expect(await transcriber.maximumConcurrency() == 1)
        await store.stop()
    }

    @Test("stop cancels blocked startup reconciliation and balances its lease")
    @MainActor
    func stopCancelsBlockedStartupReconciliationAndBalancesLease() async throws {
        let fixture = try BatchFixture()
        defer { fixture.remove() }
        let repository = try SQLiteBatchJobRepository(url: fixture.database)
        let access = ScopedAccessCounter()
        let profileStore = SecurityScopedFolderStore(
            profilesURL: fixture.root.appendingPathComponent("profiles.json"),
            resolveBookmark: { _ in (fixture.root, false) },
            startAccess: { _ in access.start(); return true },
            stopAccess: { _ in access.stop() }
        )
        try profileStore.save([
            BatchFolderProfile(id: "folder", name: "Folder", bookmarkData: Data([1]), displayPath: fixture.root.path)
        ])
        try Data("audio".utf8).write(to: fixture.root.appendingPathComponent("2026_blocked_story_rome_it.wav"))
        let configuration = BatchTranscriptionConfiguration(identifier: "provider|en", sourceLanguage: "en")
        let stability = ImmediateClaimGate()
        let transcriber = ImmediateClaimTranscriber()
        let bridge = BatchStoreBridge()
        let coordinator = BatchTranscriptionCoordinator(
            repository: repository,
            configuration: configuration,
            transcriber: transcriber,
            writer: AtomicCompanionWriter()
        )
        let watcher = WatchedFolderService(
            store: profileStore,
            repository: repository,
            configuration: configuration,
            stabilityProbe: FileStabilityProbe(
                delay: .zero,
                sleep: { _ in
                    await stability.enter()
                    try await stability.waitUntilReleased()
                },
                audioReadable: { _ in true }
            ),
            startWatching: { _, _ in {} },
            didReconcile: { event in
                await MainActor.run { bridge.store?.recordReconciliation(event) }
            }
        )
        let store = BatchTranscriptionStore(
            profileStore: profileStore,
            repository: repository,
            watcher: watcher,
            coordinator: coordinator,
            configuration: configuration,
            providerDisplayName: "Fixture",
            notify: { _, _ in }
        )
        bridge.store = store

        let started = Task { await store.start() }
        await stability.waitUntilEntered()
        await store.stop()
        await started.value
        #expect(store.isRunning == false)
        #expect(try await repository.list().isEmpty)
        #expect(await transcriber.calls().isEmpty)
        #expect(access.values() == (1, 1))
    }

}

private final class ScopedAccessCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0

    func start() { lock.withLock { starts += 1 } }
    func stop() { lock.withLock { stops += 1 } }
    func values() -> (Int, Int) { lock.withLock { (starts, stops) } }
}

private actor ImmediateClaimGate {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Error>] = []

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func waitUntilReleased() async throws {
        if released { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if released {
                    continuation.resume()
                } else if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    releaseWaiters.append(continuation)
                }
            }
        } onCancel: {
            Task { await self.cancelWaiters() }
        }
    }

    func enter() {
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }

    private func cancelWaiters() {
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: CancellationError()) }
    }
}

private actor ImmediateClaimTranscriber: BatchAudioTranscribing {
    private var recordedCalls: [String] = []
    private var finished: Set<String> = []
    private var inFlight = 0
    private var maximumInFlight = 0
    private var allowed: Set<String> = []
    private var startedWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var finishedWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var allowedWaiters: [String: [CheckedContinuation<Void, Error>]] = [:]

    func transcribe(
        sourceURL: URL,
        resumedCheckpoints: [BatchChunkCheckpoint],
        progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void,
        checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void
    ) async throws -> BatchTranscriptionResult {
        let name = sourceURL.lastPathComponent
        recordedCalls.append(name)
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        defer { inFlight -= 1 }
        startedWaiters[name, default: []].forEach { $0.resume() }
        startedWaiters[name] = nil
        if !allowed.contains(name) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                allowedWaiters[name, default: []].append(continuation)
            }
        }
        let checkpointValue = BatchChunkCheckpoint(index: 0, text: name, cues: [TranscriptCue(startSec: 0, endSec: 1, text: name)])
        try await checkpoint([checkpointValue])
        try await progress(BatchTranscriptionProgress(fraction: 1, totalChunks: 1, detail: BatchProgressDetail(phase: .transcribing)))
        finished.insert(name)
        finishedWaiters[name, default: []].forEach { $0.resume() }
        finishedWaiters[name] = nil
        return BatchTranscriptionResult(duration: 1, checkpoints: [checkpointValue])
    }

    func waitUntilStarted(_ sourceName: String) async {
        if recordedCalls.contains(sourceName) { return }
        await withCheckedContinuation { startedWaiters[sourceName, default: []].append($0) }
    }

    func waitUntilFinished(_ sourceName: String) async {
        if finished.contains(sourceName) { return }
        await withCheckedContinuation { finishedWaiters[sourceName, default: []].append($0) }
    }

    func allow(_ sourceName: String) {
        allowed.insert(sourceName)
        allowedWaiters[sourceName, default: []].forEach { $0.resume() }
        allowedWaiters[sourceName] = nil
    }

    func calls() -> [String] { recordedCalls }
    func maximumConcurrency() -> Int { maximumInFlight }
}
private final class CanonicalNamePolicyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    var requireCanonicalNames: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private final class BatchWatchSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable () -> Void)?

    func store(_ callback: @escaping @Sendable () -> Void) {
        lock.withLock { self.callback = callback }
    }

    func fire() {
        lock.withLock { callback }?()
    }
}

@MainActor
private final class BatchStoreBridge: @unchecked Sendable {
    weak var store: BatchTranscriptionStore?
}
private actor PausingFixtureTranscriber: BatchAudioTranscribing {
    private var checkpointed = false
    private var shouldPause = true
    private var checkpointWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeWaiters: [CheckedContinuation<Void, Never>] = []

    func transcribe(sourceURL: URL, resumedCheckpoints: [BatchChunkCheckpoint], progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void, checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void) async throws -> BatchTranscriptionResult {
        let value = BatchChunkCheckpoint(index: 0, text: "first", cues: [TranscriptCue(startSec: 0, endSec: 1, text: "first")])
        try await checkpoint([value])
        checkpointed = true
        checkpointWaiters.forEach { $0.resume() }
        checkpointWaiters.removeAll()
        try await progress(BatchTranscriptionProgress(
            fraction: 0.42,
            totalChunks: 1,
            detail: BatchProgressDetail(
                phase: .transcribing,
                currentChunkAudioPositionSec: 0.42,
                currentChunkDurationSec: 1
            )
        ))
        if shouldPause {
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if Task.isCancelled {
                        continuation.resume()
                    } else {
                        resumeWaiters.append(continuation)
                    }
                }
            } onCancel: {
                Task { await self.resume() }
            }
        }
        try Task.checkCancellation()
        try await progress(BatchTranscriptionProgress(fraction: 1, totalChunks: 1, detail: BatchProgressDetail(phase: .transcribing)))
        return BatchTranscriptionResult(duration: 1, checkpoints: [value])
    }

    func waitUntilCheckpointed() async {
        if checkpointed { return }
        await withCheckedContinuation { checkpointWaiters.append($0) }
    }

    func resume() {
        shouldPause = false
        resumeWaiters.forEach { $0.resume() }
        resumeWaiters.removeAll()
    }
}

private actor FixtureTranscriber: BatchAudioTranscribing {
    func transcribe(sourceURL: URL, resumedCheckpoints: [BatchChunkCheckpoint], progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void, checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void) async throws -> BatchTranscriptionResult {
        let cues = [TranscriptCue(startSec: 0, endSec: 1.25, text: "first"), TranscriptCue(startSec: 1.25, endSec: 2, text: "second")]
        let result = [BatchChunkCheckpoint(index: 0, text: "first second", cues: cues)]
        try await checkpoint(result)
        try await progress(BatchTranscriptionProgress(fraction: 1, totalChunks: 1, detail: BatchProgressDetail(phase: .transcribing)))
        return BatchTranscriptionResult(duration: 2, checkpoints: result)
    }
}

private actor FailingFixtureTranscriber: BatchAudioTranscribing {
    func transcribe(sourceURL: URL, resumedCheckpoints: [BatchChunkCheckpoint], progress: @escaping @Sendable (BatchTranscriptionProgress) async throws -> Void, checkpoint: @escaping @Sendable ([BatchChunkCheckpoint]) async throws -> Void) async throws -> BatchTranscriptionResult {
        if sourceURL.lastPathComponent.contains("bad") { throw CocoaError(.fileReadCorruptFile) }
        return try await FixtureTranscriber().transcribe(sourceURL: sourceURL, resumedCheckpoints: resumedCheckpoints, progress: progress, checkpoint: checkpoint)
    }
}

private struct BatchFixture {
    let root: URL
    let database: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        database = root.appendingPathComponent("jobs.sqlite")
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class OpenURLBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var urls: [URL] = []

    func record(_ url: URL) {
        lock.withLock { urls.append(url) }
    }
}
