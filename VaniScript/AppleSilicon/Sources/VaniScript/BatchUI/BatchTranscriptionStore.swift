import AppKit
import Foundation
import UserNotifications
import VaniScriptCore
import VaniScriptRuntime

@MainActor
final class BatchTranscriptionStore: ObservableObject {
    typealias NotificationSender = @Sendable (String, String) async -> Void
    typealias WorkspaceOpener = @Sendable (URL) -> Bool

    struct RuntimeConfiguration {
        let configuration: BatchTranscriptionConfiguration
        let providerDisplayName: String
        let transcriber: any BatchAudioTranscribing
        let requireCanonicalNames: Bool
        let startBlockMessage: String?

        init(
            configuration: BatchTranscriptionConfiguration,
            providerDisplayName: String,
            transcriber: any BatchAudioTranscribing,
            requireCanonicalNames: Bool = true,
            startBlockMessage: String? = nil
        ) {
            self.configuration = configuration
            self.providerDisplayName = providerDisplayName
            self.transcriber = transcriber
            self.requireCanonicalNames = requireCanonicalNames
            self.startBlockMessage = startBlockMessage
        }
    }

    typealias ConfigurationProvider = @MainActor () -> RuntimeConfiguration
    @Published private(set) var profiles: [BatchFolderProfile] = []
    @Published private(set) var jobs: [BatchJob] = []
    @Published private(set) var watchStatuses: [ProfileWatchSnapshot] = []
    @Published private(set) var issues: [BatchReconciliationIssue] = []
    @Published var selectedProfileID: String?
    @Published var selectedJobID: UUID?
    @Published private(set) var isRunning = false
    @Published private(set) var isReconciling = false
    @Published private(set) var isAvailable = true
    @Published private(set) var statusMessage = "Batch transcription is stopped."
    @Published private(set) var errorMessage: String?
    @Published private(set) var configuration: BatchTranscriptionConfiguration
    @Published private(set) var providerDisplayName: String
    @Published private(set) var requireCanonicalNames: Bool
    @Published private(set) var startBlockMessage: String?
    private let profileStore: SecurityScopedFolderStore?
    private let repository: SQLiteBatchJobRepository?
    private let watcher: WatchedFolderService?
    private let coordinator: BatchTranscriptionCoordinator?
    private let configurationProvider: ConfigurationProvider?
    private let notify: NotificationSender
    private let workspaceOpener: WorkspaceOpener
    private var processingTask: Task<Void, Never>?
    private var processingRunToken: UUID?
    private var processingRequested = false
    private var lifecycleGeneration: UInt64 = 0
    var activeWatcherGeneration: UInt64?
    private var startTransitionToken: UInt64?
    private var hasRecoveredAtLaunch = false
    private var isReconfiguring = false
    private var reconfigureAgain = false
    init(
        profileStore: SecurityScopedFolderStore,
        repository: SQLiteBatchJobRepository,
        watcher: WatchedFolderService,
        coordinator: BatchTranscriptionCoordinator,
        configuration: BatchTranscriptionConfiguration,
        providerDisplayName: String,
        requireCanonicalNames: Bool = true,
        startBlockMessage: String? = nil,
        configurationProvider: ConfigurationProvider? = nil,
        notify: @escaping NotificationSender = BatchTranscriptionStore.sendNotification,
        workspaceOpener: @escaping WorkspaceOpener = { NSWorkspace.shared.open($0) }
    ) {
        self.profileStore = profileStore
        self.repository = repository
        self.watcher = watcher
        self.coordinator = coordinator
        self.configuration = configuration
        self.providerDisplayName = providerDisplayName
        self.requireCanonicalNames = requireCanonicalNames
        self.startBlockMessage = startBlockMessage
        self.configurationProvider = configurationProvider
        self.notify = notify
        self.workspaceOpener = workspaceOpener
        reloadProfiles()
        refreshJobs()
    }

    private init(disabledMessage: String) {
        isAvailable = false
        statusMessage = disabledMessage
        errorMessage = disabledMessage
        configuration = BatchTranscriptionConfiguration(identifier: "unavailable", sourceLanguage: "—")
        startBlockMessage = nil
        providerDisplayName = "Unavailable"
        requireCanonicalNames = true
        profileStore = nil
        repository = nil
        watcher = nil
        coordinator = nil
        configurationProvider = nil
        notify = { _, _ in }
        workspaceOpener = { _ in false }
    }

    static func disabled(message: String) -> BatchTranscriptionStore {
        BatchTranscriptionStore(disabledMessage: message)
    }

    var selectedProfile: BatchFolderProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    var selectedJob: BatchJob? {
        jobs.first { $0.id == selectedJobID }
    }

    var isProcessing: Bool {
        jobs.contains(where: { $0.state == .processing })
    }

    var activeProcessingJob: BatchJob? {
        jobs.first(where: { $0.state == .processing })
    }

    func reconfigure() async {
        guard isAvailable,
              configurationProvider != nil,
              watcher != nil,
              coordinator != nil
        else { return }
        reconfigureAgain = true
        guard !isReconfiguring else { return }
        isReconfiguring = true
        defer { isReconfiguring = false }

        repeat {
            reconfigureAgain = false
            let wasRunning = isRunning
            let token = advanceLifecycle()
            isRunning = false
            processingRequested = false
            let task = processingTask

            if wasRunning, let coordinator {
                await coordinator.drainAfterCurrent()
                await task?.value
            }
            processingTask = nil
            processingRunToken = nil

            if let watcher, let generation = activeWatcherGeneration {
                activeWatcherGeneration = nil
                await watcher.stop(generation: generation)
            }
            guard lifecycleGeneration == token else { continue }
            if let coordinator {
                await coordinator.unregisterAllFolders()
            }
            watchStatuses = []

            if wasRunning {
                await start()
            } else {
                await restore()
            }
        } while reconfigureAgain
    }
    func addFolder(_ url: URL, recursive: Bool = false) {
        guard isAvailable, let profileStore else { return }
        do {
            var updated = try profileStore.load()
            let profile = try profileStore.profile(
                id: UUID().uuidString,
                name: url.lastPathComponent,
                folderURL: url,
                recursive: recursive
            )
            updated.append(profile)
            try profileStore.save(updated)
            profiles = updated
            selectedProfileID = profile.id
            isReconciling = true
            statusMessage = "Scanning watched folders…"
            Task { [weak self] in
                guard let self else { return }
                await self.restore()
                // restore starts the watcher and schedules its automatic pass. Await
                // one explicit reconciliation as well so a newly added folder is
                // visible in the job list before the user has to toggle anything.
                await self.scan()
            }
        } catch {
            fail("The selected folder could not be saved.")
        }
    }

    func updateProfile(_ profile: BatchFolderProfile) {
        guard isAvailable, let profileStore else { return }
        do {
            var updated = try profileStore.load()
            guard let index = updated.firstIndex(where: { $0.id == profile.id }) else { return }
            updated[index] = profile
            try profileStore.save(updated)
            profiles = updated
            Task { [weak self] in
                await self?.restore()
            }
        } catch {
            fail("The folder profile could not be updated.")
        }
    }

    func removeProfile(id: String) {
        guard isAvailable, let profileStore, let repository else { return }
        guard !jobs.contains(where: { $0.state == .processing }) else { return }
        Task { [weak self] in
            guard let self else { return }
            guard !self.jobs.contains(where: { $0.state == .processing }) else { return }
            let resumeWatching = self.isRunning
            if resumeWatching { await self.stop() }
            do {
                var updated = try profileStore.load()
                updated.removeAll { $0.id == id }
                try await repository.delete(profileID: id)
                try profileStore.save(updated)
                self.profiles = updated
                self.jobs.removeAll { $0.profileID == id }
                self.issues.removeAll()
                if self.jobs.first(where: { $0.id == self.selectedJobID }) == nil { self.selectedJobID = nil }
                if self.selectedProfileID == id { self.selectedProfileID = updated.first?.id }
                if resumeWatching {
                    await self.start()
                } else {
                    await self.restore()
                }
            } catch {
                self.fail("The folder profile could not be removed.")
            }
        }
    }

    func restore() async {
        guard isAvailable,
              let repository,
              let watcher,
              let coordinator
        else { return }

        let token = advanceLifecycle()
        guard await recoverInterruptedIfNeeded(), lifecycleGeneration == token else {
            isReconciling = false
            return
        }
        _ = readRuntimeConfiguration()
        guard (configurationProvider == nil || startBlockMessage == nil),
              lifecycleGeneration == token
        else {
            isReconciling = false
            return
        }

        if let previousGeneration = activeWatcherGeneration {
            activeWatcherGeneration = nil
            await watcher.stop(generation: previousGeneration)
            guard lifecycleGeneration == token else { return }
        }
        await coordinator.unregisterAllFolders()
        guard lifecycleGeneration == token else { return }

        while lifecycleGeneration == token {
            let runtime = readRuntimeConfiguration()
            guard (configurationProvider == nil || runtime != nil),
                  lifecycleGeneration == token
            else { return }
            guard await applyRuntimeConfiguration(runtime, lifecycleToken: token) else { return }

            var activation: WatchedFolderActivation?
            do {
                let created = try await watcher.activate()
                activation = created
                guard lifecycleGeneration == token else {
                    await watcher.stop(generation: created.generation)
                    return
                }
                watchStatuses = created.statuses

                _ = try await repository.supersedePending(
                    exceptConfigurationID: runtime?.configuration.identifier ?? configuration.identifier
                )
                guard lifecycleGeneration == token else {
                    await watcher.stop(generation: created.generation)
                    return
                }
                for (profileID, url) in created.activeFolderURLs.sorted(by: { $0.key < $1.key }) {
                    guard lifecycleGeneration == token else {
                        await watcher.stop(generation: created.generation)
                        return
                    }
                    await coordinator.registerFolder(profileID: profileID, url: url)
                }
                guard lifecycleGeneration == token else {
                    await watcher.stop(generation: created.generation)
                    return
                }

                guard runtimeIsCurrent(runtime) else {
                    await watcher.stop(generation: created.generation)
                    guard lifecycleGeneration == token else { return }
                    await coordinator.unregisterAllFolders()
                    guard lifecycleGeneration == token else { return }
                    continue
                }

                activeWatcherGeneration = created.generation
                isReconciling = true
                if !isRunning {
                    statusMessage = "Scanning watched folders…"
                }
                await watcher.beginReconciliation(generation: created.generation)
                guard lifecycleGeneration == token else { return }
                refreshJobs()
                return
            } catch {
                if let activation {
                    await watcher.stop(generation: activation.generation)
                }
                if lifecycleGeneration == token {
                    isReconciling = false
                    await coordinator.unregisterAllFolders()
                    fail("Batch folder watching could not be restored.")
                }
                return
            }
        }
    }

    func start() async {
        guard isAvailable,
              let repository,
              let watcher,
              let coordinator,
              !isRunning,
              startTransitionToken == nil
        else { return }

        let token = advanceLifecycle()
        startTransitionToken = token
        defer {
            if startTransitionToken == token {
                startTransitionToken = nil
            }
        }
        guard await recoverInterruptedIfNeeded(), lifecycleGeneration == token else { return }
        while lifecycleGeneration == token {
            let runtime = readRuntimeConfiguration()
            guard (configurationProvider == nil || runtime != nil),
                  lifecycleGeneration == token
            else { return }

            if let previousGeneration = activeWatcherGeneration {
                activeWatcherGeneration = nil
                await watcher.stop(generation: previousGeneration)
                guard lifecycleGeneration == token else { return }
            }
            await coordinator.unregisterAllFolders()
            guard lifecycleGeneration == token else { return }
            guard await applyRuntimeConfiguration(runtime, lifecycleToken: token) else { return }

            var activation: WatchedFolderActivation?
            do {
                let created = try await watcher.activate()
                activation = created
                guard lifecycleGeneration == token else {
                    await watcher.stop(generation: created.generation)
                    return
                }
                watchStatuses = created.statuses

                _ = try await repository.supersedePending(
                    exceptConfigurationID: runtime?.configuration.identifier ?? configuration.identifier
                )
                guard lifecycleGeneration == token else {
                    await watcher.stop(generation: created.generation)
                    return
                }
                for (profileID, url) in created.activeFolderURLs.sorted(by: { $0.key < $1.key }) {
                    guard lifecycleGeneration == token else {
                        await watcher.stop(generation: created.generation)
                        return
                    }
                    await coordinator.registerFolder(profileID: profileID, url: url)
                }
                guard lifecycleGeneration == token else {
                    await watcher.stop(generation: created.generation)
                    return
                }

                guard runtimeIsCurrent(runtime) else {
                    await watcher.stop(generation: created.generation)
                    guard lifecycleGeneration == token else { return }
                    await coordinator.unregisterAllFolders()
                    guard lifecycleGeneration == token else { return }
                    continue
                }

                activeWatcherGeneration = created.generation
                isRunning = true
                isReconciling = true
                statusMessage = created.activeFolderURLs.isEmpty
                    ? "No enabled folder is available."
                    : "Watching \(created.activeFolderURLs.count) folder\(created.activeFolderURLs.count == 1 ? "" : "s")."
                requestProcessing()
                await watcher.beginReconciliation(generation: created.generation)
                guard lifecycleGeneration == token else { return }
                refreshJobs()
                return
            } catch {
                if let activation {
                    await watcher.stop(generation: activation.generation)
                }
                if lifecycleGeneration == token {
                    await coordinator.unregisterAllFolders()
                    fail("Batch transcription could not start.")
                }
                return
            }
        }
    }

    func stop() async {
        await tearDown(cancelProcessingTask: true)
    }

    private func tearDown(cancelProcessingTask: Bool) async {
        guard isAvailable, let coordinator else { return }
        let token = advanceLifecycle()
        isRunning = false
        isReconciling = false
        processingRequested = false
        let task = processingTask
        processingTask = nil
        processingRunToken = nil
        startTransitionToken = nil
        if cancelProcessingTask {
            task?.cancel()
        }
        let watcherGeneration = activeWatcherGeneration
        activeWatcherGeneration = nil

        await coordinator.cancelAllAndWait()

        if let watcher, let watcherGeneration {
            await watcher.stop(generation: watcherGeneration)
        }
        guard lifecycleGeneration == token else { return }
        await coordinator.unregisterAllFolders()
        watchStatuses = []
        isReconciling = false
        statusMessage = "Batch transcription is stopped."
        refreshJobs()
    }

    func scan() async {
        guard isAvailable, let watcher else { return }
        _ = readRuntimeConfiguration()
        guard configurationProvider == nil || startBlockMessage == nil else { return }
        do {
            issues.removeAll()
            var queuedCount = 0
            var duplicateCount = 0
            for profile in profiles where profile.enabled {
                if let result = try await watcher.reconcile(
                    profileID: profile.id,
                    requireCanonicalNames: requireCanonicalNames
                ) {
                    queuedCount += result.enqueued.count
                    duplicateCount += result.duplicateCount
                    issues.append(contentsOf: result.issues)
                }
            }
            refreshJobs()
            statusMessage = "Scan complete: queued \(queuedCount), rejected \(issues.count), already queued \(duplicateCount)."
        } catch {
            fail("The watched folders could not be scanned.")
        }
    }

    func retry(jobID: UUID) async {
        guard isAvailable, let coordinator else { return }
        do {
            try await coordinator.retry(jobID: jobID)
            refreshJobs()
            requestProcessing()
        } catch {
            fail("The batch job could not be retried.")
        }
    }

    func cancel(jobID: UUID) async {
        guard isAvailable, let coordinator else { return }
        do {
            try await coordinator.cancel(jobID: jobID)
            refreshJobs()
        } catch {
            fail("The batch job could not be cancelled.")
        }
    }

    func refreshJobs() {
        guard isAvailable, repository != nil else { return }
        Task { [weak self] in
            await self?.refreshJobsAndApplyStatus()
        }
    }

    private func refreshJobsAndApplyStatus() async {
        guard isAvailable, let repository else { return }
        let values = (try? await repository.list()) ?? []
        let activeProfileIDs = Set(profiles.map(\.id))
        jobs = values.filter { activeProfileIDs.contains($0.profileID) }
        if let startBlockMessage {
            statusMessage = startBlockMessage
        } else if let processing = jobs.first(where: { $0.state == .processing }) {
            statusMessage = processingStatus(for: processing)
        } else if isRunning {
            let hasIncompleteJobs = jobs.contains(where: { $0.state == .pending || $0.state == .processing })
            if !hasIncompleteJobs && !isReconciling {
                Task { [weak self] in await self?.stop() }
                statusMessage = "Batch transcription is stopped."
            } else {
                let activeCount = profiles.filter(\.enabled).count
                statusMessage = activeCount == 0 ? "No enabled folder is available." : "Watching \(activeCount) folder\(activeCount == 1 ? "" : "s")."
            }
        } else {
            statusMessage = "Batch transcription is stopped."
        }
    }

    func recordReconciliation(_ event: WatchedFolderReconciliationEvent) {
        // Always refresh job list regardless of generation so that newly
        // reconciled jobs are visible even when a concurrent reconfigure()
        // advanced the watcher generation.
        refreshJobs()
        guard event.generation == activeWatcherGeneration else { return }
        switch event.outcome {
        case let .completed(result):
            let requireCanonicalNames = configurationProvider?().requireCanonicalNames ?? self.requireCanonicalNames
            if requireCanonicalNames {
                issues = result.issues
            } else {
                issues = result.issues.filter { issue in
                    if case .invalidName = issue { return false }
                    return true
                }
            }
            refreshJobs()
            requestProcessing()
            isReconciling = false
        case .failed:
            isReconciling = false
            fail("The watched folders could not be scanned.")
        }
    }

    func record(_ event: BatchProcessingEvent) async {
        await refreshJobsAndApplyStatus()
        switch event {
        case let .updated(jobID):
            if let job = jobs.first(where: { $0.id == jobID }) {
                statusMessage = processingStatus(for: job)
            }
        case .completed:
            Task { await notify("Batch transcription completed", "A companion transcript is ready.") }
        case let .failed(_, message):
            Task { await notify("Batch transcription failed", message) }
        case let .blockedOutputCollision(_, message):
            Task { await notify("Batch output conflict", message) }
        }
    }

    private func processingStatus(for job: BatchJob) -> String {
        let stage = job.progressStageText
        if stage.hasSuffix("…") || stage.hasSuffix("%") {
            return "\(job.relativeSourcePath) — \(stage)"
        }
        return "\(job.relativeSourcePath) — \(stage)."
    }

    private func requestProcessing() {
        guard isRunning, let coordinator, let repository else { return }
        processingRequested = true
        guard processingTask == nil else { return }

        let lifecycleToken = lifecycleGeneration
        let runToken = UUID()
        processingRunToken = runToken
        processingTask = Task { [weak self, coordinator, repository] in
            var shouldAutoStop = false
            while !Task.isCancelled {
                guard let self else { return }
                self.processingRequested = false
                await coordinator.processPending()
                self.refreshJobs()

                if let activeJobs = try? await repository.list(states: [.pending, .processing]) {
                    let activeProfileIDs = Set(self.profiles.map(\.id))
                    shouldAutoStop = !activeJobs.contains {
                        activeProfileIDs.contains($0.profileID)
                            && $0.configuration.identifier == self.configuration.identifier
                    }
                    if shouldAutoStop { break }
                }

                guard !Task.isCancelled,
                      self.lifecycleGeneration == lifecycleToken,
                      self.isRunning,
                      self.processingRequested
                else { break }
            }

            guard let self, self.processingRunToken == runToken else { return }
            self.processingTask = nil
            self.processingRunToken = nil
            if shouldAutoStop, self.isRunning {
                await self.tearDown(cancelProcessingTask: false)
            } else if self.isRunning, self.processingRequested {
                self.requestProcessing()
            }
        }
    }

    func companionURL(for job: BatchJob) -> URL? {
        guard let profile = profiles.first(where: { $0.id == job.profileID }) else { return nil }
        let folderURL: URL
        if let profileStore {
            switch profileStore.resolve(profile) {
            case let .active(url), let .stale(url):
                folderURL = url
            case .revoked, .unavailable:
                folderURL = URL(fileURLWithPath: profile.displayPath)
            }
        } else {
            folderURL = URL(fileURLWithPath: profile.displayPath)
        }
        return folderURL.appendingPathComponent(job.relativeOutputPath)
    }

    @discardableResult
    func openCompanion(for job: BatchJob) -> Bool {
        guard job.state == .completed else { return false }
        guard let url = companionURL(for: job) else { return false }
        return workspaceOpener(url)
    }

    private func reloadProfiles() {
        guard isAvailable, let profileStore else { return }
        do {
            profiles = try profileStore.load()
            selectedProfileID = selectedProfileID ?? profiles.first?.id
        } catch {
            fail("Folder profiles could not be loaded.")
        }
    }

    private func recoverInterruptedIfNeeded() async -> Bool {
        guard !hasRecoveredAtLaunch else { return true }
        guard let repository else {
            fail("Interrupted batch jobs could not be recovered.")
            return false
        }
        do {
            _ = try await repository.recoverInterrupted()
            hasRecoveredAtLaunch = true
            refreshJobs()
            return true
        } catch {
            fail("Interrupted batch jobs could not be recovered.")
            return false
        }
    }

    private func advanceLifecycle() -> UInt64 {
        lifecycleGeneration &+= 1
        return lifecycleGeneration
    }

    private func readRuntimeConfiguration() -> RuntimeConfiguration? {
        guard let configurationProvider else {
            startBlockMessage = nil
            errorMessage = nil
            return nil
        }
        let current = configurationProvider()
        configuration = current.configuration
        providerDisplayName = current.providerDisplayName
        requireCanonicalNames = current.requireCanonicalNames
        startBlockMessage = current.startBlockMessage
        guard current.startBlockMessage == nil else {
            errorMessage = nil
            statusMessage = current.startBlockMessage!
            return nil
        }
        errorMessage = nil
        return current
    }

    private func applyRuntimeConfiguration(
        _ runtime: RuntimeConfiguration?,
        lifecycleToken: UInt64
    ) async -> Bool {
        guard lifecycleGeneration == lifecycleToken else { return false }
        guard let runtime, let watcher, let coordinator else { return true }
        await watcher.updateConfiguration(
            runtime.configuration,
            requireCanonicalNames: runtime.requireCanonicalNames
        )
        guard lifecycleGeneration == lifecycleToken else { return false }
        await coordinator.updateTranscriber(runtime.transcriber, for: runtime.configuration)
        return lifecycleGeneration == lifecycleToken
    }

    private func runtimeIsCurrent(_ runtime: RuntimeConfiguration?) -> Bool {
        guard let configurationProvider else { return true }
        guard let runtime else { return false }
        let latest = configurationProvider()
        return latest.configuration.identifier == runtime.configuration.identifier
            && latest.requireCanonicalNames == runtime.requireCanonicalNames
            && latest.startBlockMessage == nil
    }
    private func fail(_ message: String) {
        errorMessage = message
        statusMessage = message
    }

    private static func sendNotification(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let status: UNAuthorizationStatus = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
