import CoreServices
import Foundation
import VaniScriptCore

private final class FSEventWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?

    func start(path: String, signal: @escaping @Sendable () -> Void) -> Bool {
        let retained = Unmanaged.passRetained(SignalBox(signal))
        var context = FSEventStreamContext(
            version: 0,
            info: retained.toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<SignalBox>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<SignalBox>.fromOpaque(info).takeUnretainedValue().signal()
        }
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        ) else {
            retained.release()
            return false
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        guard FSEventStreamStart(stream) else {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        self.stream = stream
        return true
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}

private final class SignalBox: @unchecked Sendable {
    let signal: @Sendable () -> Void
    init(_ signal: @escaping @Sendable () -> Void) { self.signal = signal }
}

public enum ProfileWatchStatus: Equatable, Sendable {
    case active
    case staleRefreshed
    case revoked
    case unavailable
    case accessDenied
    case watchFailed
}

public struct ProfileWatchSnapshot: Equatable, Sendable {
    public let profileID: String
    public let status: ProfileWatchStatus

    public init(profileID: String, status: ProfileWatchStatus) {
        self.profileID = profileID
        self.status = status
    }
}

public struct WatchedFolderActivation: Sendable {
    public let generation: UInt64
    public let statuses: [ProfileWatchSnapshot]
    public let activeFolderURLs: [String: URL]

    public init(
        generation: UInt64,
        statuses: [ProfileWatchSnapshot],
        activeFolderURLs: [String: URL]
    ) {
        self.generation = generation
        self.statuses = statuses
        self.activeFolderURLs = activeFolderURLs
    }
}

public enum WatchedFolderReconciliationOutcome: Sendable {
    case completed(BatchReconciliationResult)
    case failed
}

public struct WatchedFolderReconciliationEvent: Sendable {
    public let generation: UInt64
    public let profileID: String
    public let folderURL: URL
    public let outcome: WatchedFolderReconciliationOutcome

    public init(
        generation: UInt64,
        profileID: String,
        folderURL: URL,
        outcome: WatchedFolderReconciliationOutcome
    ) {
        self.generation = generation
        self.profileID = profileID
        self.folderURL = folderURL
        self.outcome = outcome
    }
}

public actor WatchedFolderService {
    public typealias WatchStop = @Sendable () -> Void
    public typealias WatchStarter = @Sendable (String, @escaping @Sendable () -> Void) -> WatchStop?

    private struct ActiveWatch {
        let profile: BatchFolderProfile
        let url: URL
        let lease: SecurityScopedAccessLease
        let stopWatching: WatchStop
    }

    private struct ActiveGeneration {
        let generation: UInt64
        let configuration: BatchTranscriptionConfiguration
        let requireCanonicalNames: Bool
        var admissionEnabled: Bool
    }

    private struct ReconciliationRequest {
        let generation: UInt64
        let profileID: String
        let requireCanonicalNames: Bool
        let automatic: Bool
        var waiterIDs: [UUID]
    }

    private struct PendingDebounce {
        let generation: UInt64
        let token: UUID
        let task: Task<Void, Never>
    }

    private struct ReconciliationExecution {
        let folderURL: URL
        let outcome: WatchedFolderReconciliationOutcome
    }

    private let store: SecurityScopedFolderStore
    private let repository: SQLiteBatchJobRepository
    private var configuration: BatchTranscriptionConfiguration
    private var requireCanonicalNames: Bool
    private let stabilityProbe: FileStabilityProbe
    private let reconciler: FolderReconciler
    private let coalescingDelay: Duration
    private let startWatching: WatchStarter
    private let didReconcile: @Sendable (WatchedFolderReconciliationEvent) async -> Void
    private var watches: [String: ActiveWatch] = [:]
    private var statusByProfileID: [String: ProfileWatchStatus] = [:]

    private var generationCounter: UInt64 = 0
    private var activeGeneration: ActiveGeneration?
    private var pending: [String: PendingDebounce] = [:]
    private var deferredDirty: Set<String> = []
    private var requests: [ReconciliationRequest] = []
    private var queuedAutomaticProfileIDs: Set<String> = []
    private var workerTask: Task<Void, Never>?
    private var workerToken: UUID?
    private var explicitWaiters: [UUID: CheckedContinuation<BatchReconciliationResult?, Error>] = [:]

    private var activationInProgress = false
    private var activationWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        store: SecurityScopedFolderStore,
        repository: SQLiteBatchJobRepository,
        configuration: BatchTranscriptionConfiguration,
        stabilityProbe: FileStabilityProbe,
        reconciler: FolderReconciler = FolderReconciler(),
        coalescingDelay: Duration = .milliseconds(300),
        requireCanonicalNames: Bool = true,
        startWatching: @escaping WatchStarter = WatchedFolderService.platformStartWatching,
        didReconcile: @escaping @Sendable (WatchedFolderReconciliationEvent) async -> Void = { _ in }
    ) {
        self.store = store
        self.repository = repository
        self.configuration = configuration
        self.reconciler = reconciler
        self.stabilityProbe = stabilityProbe
        self.coalescingDelay = coalescingDelay
        self.requireCanonicalNames = requireCanonicalNames
        self.startWatching = startWatching
        self.didReconcile = didReconcile
    }

    public func updateConfiguration(
        _ configuration: BatchTranscriptionConfiguration,
        requireCanonicalNames: Bool = true
    ) {
        self.configuration = configuration
        self.requireCanonicalNames = requireCanonicalNames
    }

    public func activate() async throws -> WatchedFolderActivation {
        while activationInProgress {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                activationWaiters.append(continuation)
            }
        }
        activationInProgress = true
        defer {
            activationInProgress = false
            let waiters = activationWaiters
            activationWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        if let previousGeneration = activeGeneration?.generation {
            await stop(generation: previousGeneration)
        }

        generationCounter &+= 1
        let generation = generationCounter
        var profiles = try store.load()
        var newWatches: [String: ActiveWatch] = [:]
        var newStatuses: [String: ProfileWatchStatus] = [:]
        let generationConfiguration = configuration
        let generationRequiresCanonicalNames = requireCanonicalNames

        for originalProfile in profiles where originalProfile.enabled {
            var resolvedProfile: BatchFolderProfile?
            var resolvedURL: URL?
            var resolvedLease: SecurityScopedAccessLease?
            var successStatus: ProfileWatchStatus?

            switch store.resolve(originalProfile) {
            case let .active(url):
                guard let lease = store.beginAccess(to: url) else {
                    newStatuses[originalProfile.id] = .accessDenied
                    continue
                }
                resolvedProfile = originalProfile
                resolvedURL = url
                resolvedLease = lease
                successStatus = .active
            case let .stale(url):
                guard let lease = store.beginAccess(to: url) else {
                    newStatuses[originalProfile.id] = .accessDenied
                    continue
                }
                do {
                    resolvedProfile = try store.refresh(originalProfile, at: url, in: &profiles)
                } catch {
                    lease.close()
                    newStatuses[originalProfile.id] = .unavailable
                    continue
                }
                resolvedURL = url
                resolvedLease = lease
                successStatus = .staleRefreshed
            case .revoked:
                newStatuses[originalProfile.id] = .revoked
                continue
            case .unavailable:
                newStatuses[originalProfile.id] = .unavailable
                continue
            }

            guard let profile = resolvedProfile,
                  let url = resolvedURL,
                  let lease = resolvedLease,
                  let successStatus
            else {
                continue
            }
            guard let stopWatching = startWatching(url.path, { [weak self] in
                Task { await self?.signal(profileID: profile.id, generation: generation) }
            }) else {
                lease.close()
                newStatuses[profile.id] = .watchFailed
                continue
            }
            newWatches[profile.id] = ActiveWatch(
                profile: profile,
                url: url,
                lease: lease,
                stopWatching: stopWatching
            )
            newStatuses[profile.id] = successStatus
        }

        watches = newWatches
        statusByProfileID = newStatuses
        activeGeneration = ActiveGeneration(
            generation: generation,
            configuration: generationConfiguration,
            requireCanonicalNames: generationRequiresCanonicalNames,
            admissionEnabled: false
        )

        return WatchedFolderActivation(
            generation: generation,
            statuses: newStatuses
                .map(ProfileWatchSnapshot.init(profileID:status:))
                .sorted { $0.profileID < $1.profileID },
            activeFolderURLs: newWatches.mapValues(\.url)
        )
    }

    public func beginReconciliation(generation: UInt64) {
        guard var context = activeGeneration, context.generation == generation else { return }
        let wasEnabled = context.admissionEnabled
        context.admissionEnabled = true
        activeGeneration = context
        guard !wasEnabled else { return }

        let deferred = deferredDirty
        deferredDirty.removeAll()
        for profileID in watches.keys.sorted() {
            enqueueAutomatic(
                profileID: profileID,
                generation: generation,
                requireCanonicalNames: context.requireCanonicalNames
            )
        }
        for profileID in deferred.sorted() {
            enqueueAutomatic(
                profileID: profileID,
                generation: generation,
                requireCanonicalNames: context.requireCanonicalNames
            )
        }
        startWorkerIfNeeded()
    }

    public func stop(generation: UInt64? = nil) async {
        guard let context = activeGeneration,
              generation == nil || generation == context.generation
        else { return }

        activeGeneration = nil
        let retiredGeneration = context.generation
        let retiringWatches = watches
        watches.removeAll()

        for watch in retiringWatches.values {
            watch.stopWatching()
        }

        let debounceTasks = pending.values.map(\.task)
        pending.removeAll()
        debounceTasks.forEach { $0.cancel() }

        let detachedWorker = workerTask
        workerTask = nil
        workerToken = nil
        requests.removeAll()
        queuedAutomaticProfileIDs.removeAll()
        deferredDirty.removeAll()

        let waiters = Array(explicitWaiters.values)
        explicitWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: CancellationError()) }

        detachedWorker?.cancel()

        if let detachedWorker {
            await detachedWorker.value
        }
        for task in debounceTasks {
            await task.value
        }
        for watch in retiringWatches.values {
            watch.lease.close()
        }

        if activeGeneration == nil {
            statusByProfileID.removeAll()
        } else if activeGeneration?.generation == retiredGeneration {
            statusByProfileID.removeAll()
        }
    }

    public func signal(profileID: String) {
        guard let generation = activeGeneration?.generation else { return }
        signal(profileID: profileID, generation: generation)
    }

    public func signal(profileID: String, generation: UInt64) {
        guard let context = activeGeneration,
              context.generation == generation,
              watches[profileID] != nil
        else { return }
        guard context.admissionEnabled else {
            deferredDirty.insert(profileID)
            return
        }

        pending[profileID]?.task.cancel()
        let token = UUID()
        let delay = coalescingDelay
        let task = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
                await self?.debounceElapsed(
                    profileID: profileID,
                    generation: generation,
                    token: token
                )
            } catch { }
        }
        pending[profileID] = PendingDebounce(generation: generation, token: token, task: task)
    }

    @discardableResult
    public func reconcile(
        profileID: String,
        requireCanonicalNames: Bool? = nil
    ) async throws -> BatchReconciliationResult? {
        guard let context = activeGeneration, watches[profileID] != nil else { return nil }
        let waiterID = UUID()
        let effectiveCanonical = requireCanonicalNames ?? context.requireCanonicalNames

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<BatchReconciliationResult?, Error>) in
                explicitWaiters[waiterID] = continuation
                requests.append(
                    ReconciliationRequest(
                        generation: context.generation,
                        profileID: profileID,
                        requireCanonicalNames: effectiveCanonical,
                        automatic: false,
                        waiterIDs: [waiterID]
                    )
                )
                startWorkerIfNeeded()
            }
        } onCancel: {
            Task { await self.cancelExplicit(waiterID) }
        }
    }

    public static func platformStartWatching(
        path: String,
        signal: @escaping @Sendable () -> Void
    ) -> WatchStop? {
        let watcher = FSEventWatcher()
        guard watcher.start(path: path, signal: signal) else { return nil }
        return { watcher.stop() }
    }

    private func enqueueAutomatic(
        profileID: String,
        generation: UInt64,
        requireCanonicalNames: Bool
    ) {
        guard let context = activeGeneration,
              context.generation == generation,
              context.admissionEnabled,
              watches[profileID] != nil
        else { return }
        guard queuedAutomaticProfileIDs.insert(profileID).inserted else { return }
        requests.append(
            ReconciliationRequest(
                generation: generation,
                profileID: profileID,
                requireCanonicalNames: requireCanonicalNames,
                automatic: true,
                waiterIDs: []
            )
        )
        startWorkerIfNeeded()
    }

    private func debounceElapsed(profileID: String, generation: UInt64, token: UUID) {
        guard let current = pending[profileID],
              current.generation == generation,
              current.token == token
        else { return }
        pending[profileID] = nil
        guard let context = activeGeneration,
              context.generation == generation
        else { return }
        enqueueAutomatic(
            profileID: profileID,
            generation: generation,
            requireCanonicalNames: context.requireCanonicalNames
        )
    }

    private func startWorkerIfNeeded() {
        guard workerTask == nil, !requests.isEmpty else { return }
        let token = UUID()
        workerToken = token
        workerTask = Task { [weak self] in
            await self?.runWorker(token: token)
        }
    }

    private func runWorker(token: UUID) async {
        while !Task.isCancelled {
            guard workerToken == token, !requests.isEmpty else { break }
            let request = requests.removeFirst()
            if request.automatic {
                queuedAutomaticProfileIDs.remove(request.profileID)
            }

            var execution: ReconciliationExecution?
            var failure: Error?
            let watch = watches[request.profileID]
            do {
                guard let context = activeGeneration,
                      context.generation == request.generation,
                      let watch
                else { throw CancellationError() }
                try Task.checkCancellation()
                let result = try await reconciler.reconcile(
                    folderURL: watch.url,
                    profile: watch.profile,
                    configuration: context.configuration,
                    repository: repository,
                    stabilityProbe: stabilityProbe,
                    requireCanonicalNames: request.requireCanonicalNames
                )
                try Task.checkCancellation()
                guard activeGeneration?.generation == request.generation else {
                    throw CancellationError()
                }
                execution = ReconciliationExecution(
                    folderURL: watch.url,
                    outcome: .completed(result)
                )
            } catch is CancellationError {
                execution = nil
            } catch {
                failure = error
                if !Task.isCancelled,
                   activeGeneration?.generation == request.generation,
                   let watch {
                    execution = ReconciliationExecution(
                        folderURL: watch.url,
                        outcome: .failed
                    )
                }
            }

            guard workerToken == token else {
                resolve(request, result: nil, error: CancellationError())
                break
            }
            guard let execution else {
                resolve(request, result: nil, error: CancellationError())
                continue
            }

            if activeGeneration?.generation == request.generation, !Task.isCancelled {
                await didReconcile(
                    WatchedFolderReconciliationEvent(
                        generation: request.generation,
                        profileID: request.profileID,
                        folderURL: execution.folderURL,
                        outcome: execution.outcome
                    )
                )
            }
            switch execution.outcome {
            case let .completed(result):
                resolve(request, result: result, error: nil)
            case .failed:
                resolve(request, result: nil, error: failure ?? CocoaError(.fileReadUnknown))
            }
        }
        finishWorker(token: token)
    }

    private func finishWorker(token: UUID) {
        guard workerToken == token else { return }
        workerToken = nil
        workerTask = nil
        startWorkerIfNeeded()
    }

    private func resolve(
        _ request: ReconciliationRequest,
        result: BatchReconciliationResult?,
        error: Error?
    ) {
        for waiterID in request.waiterIDs {
            guard let continuation = explicitWaiters.removeValue(forKey: waiterID) else { continue }
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: result)
            }
        }
    }

    private func cancelExplicit(_ waiterID: UUID) {
        guard let continuation = explicitWaiters.removeValue(forKey: waiterID) else { return }
        for index in requests.indices {
            requests[index].waiterIDs.removeAll { $0 == waiterID }
        }
        continuation.resume(throwing: CancellationError())
    }
}
