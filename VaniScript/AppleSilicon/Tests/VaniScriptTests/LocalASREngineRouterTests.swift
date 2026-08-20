import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Local ASR router", .serialized)
struct LocalASREngineRouterTests {
    init() {
        LocalModelVerification.skipVerificationForTesting = true
    }

    @Test("routes each exact backend and reuses or unloads resident bindings")
    func routesAndManagesResidentBindings() async throws {
        let root = try makeFixtureRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let whisper = try #require(NativeModelCatalog.descriptor(for: "whisper-small-multilingual"))
        let parakeet = try #require(NativeModelCatalog.descriptor(for: "parakeet-tdt-06b-v3"))
        let canary = try #require(NativeModelCatalog.descriptor(for: "canary-180m-flash-coreml"))
        let whisperSettings = try settings(for: whisper, under: root.appendingPathComponent("whisper-a"))
        let whisperSettingsWithNewPath = try settings(for: whisper, under: root.appendingPathComponent("whisper-b"))
        let parakeetSettings = try settings(for: parakeet, under: root.appendingPathComponent("parakeet"))
        let canarySettings = try settings(for: canary, under: root.appendingPathComponent("canary"))
        let audioURL = root.appendingPathComponent("dictation.wav")
        try Data([1]).write(to: audioURL)

        let whisperLog = RouterEventLog()
        let parakeetLog = RouterEventLog()
        let canaryLog = RouterEventLog()
        let factories = LocalASREngineRouterFactories(
            whisperKit: { model in
                await whisperLog.created(model.id)
                return SpyLocalASREngine(descriptor: model.descriptor, log: whisperLog)
            },
            parakeet: { model in
                await parakeetLog.created(model.id)
                return SpyLocalASREngine(descriptor: model.descriptor, log: parakeetLog)
            },
            canary: { model in
                await canaryLog.created(model.id)
                return SpyLocalASREngine(descriptor: model.descriptor, log: canaryLog)
            }
        )
        let router = LocalASREngineRouter(factories: factories)
        let request = LocalASRRequest(audioFileURL: audioURL, languageHint: "Russian")

        _ = try await router.transcribe(
            settings: whisperSettings,
            providerID: whisper.id,
            request: request,
            progress: { _ in }
        )
        _ = try await router.transcribe(
            settings: whisperSettings,
            providerID: whisper.id,
            request: request,
            progress: { _ in }
        )
        _ = try await router.transcribe(
            settings: parakeetSettings,
            providerID: parakeet.id,
            request: request,
            progress: { _ in }
        )
        _ = try await router.transcribe(
            settings: canarySettings,
            providerID: canary.id,
            request: request,
            progress: { _ in }
        )
        _ = try await router.transcribe(
            settings: whisperSettingsWithNewPath,
            providerID: whisper.id,
            request: request,
            progress: { _ in }
        )
        await router.unload()

        #expect(await whisperLog.createdIDs == [whisper.id, whisper.id])
        #expect(await whisperLog.transcriptionCount == 3)
        #expect(await whisperLog.unloadCount == 2)
        #expect(await parakeetLog.createdIDs == [parakeet.id])
        #expect(await parakeetLog.unloadCount == 1)
        #expect(await canaryLog.createdIDs == [canary.id])
        #expect(await canaryLog.unloadCount == 1)
    }

    @Test("unknown and incomplete catalog bindings fail before a factory is called")
    func rejectsUnknownAndIncompleteBindings() async throws {
        let root = try makeFixtureRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let canary = try #require(NativeModelCatalog.descriptor(for: "canary-180m-flash-coreml"))
        var incomplete = AppSettings.defaults
        let incompletePath = root.appendingPathComponent("incomplete", isDirectory: true)
        try FileManager.default.createDirectory(at: incompletePath, withIntermediateDirectories: true)
        incomplete.localAsrModels[canary.id] = LocalModelState(
            status: .downloaded,
            label: canary.displayName,
            path: incompletePath.path,
            runtime: canary.settingsRuntime
        )

        let factoryCalls = RouterEventLog()
        let factories = LocalASREngineRouterFactories(
            whisperKit: { model in
                await factoryCalls.created(model.id)
                return SpyLocalASREngine(descriptor: model.descriptor, log: factoryCalls)
            },
            parakeet: { model in
                await factoryCalls.created(model.id)
                return SpyLocalASREngine(descriptor: model.descriptor, log: factoryCalls)
            },
            canary: { model in
                await factoryCalls.created(model.id)
                return SpyLocalASREngine(descriptor: model.descriptor, log: factoryCalls)
            }
        )
        let router = LocalASREngineRouter(factories: factories)

        await expectUnsupportedModel {
            _ = try await router.resolveActive(
                settings: .defaults,
                providerID: "unknown-model"
            )
        }
        await expectUnsupportedModel {
            _ = try await router.resolveActive(
                settings: incomplete,
                providerID: canary.id
            )
        }
        #expect(await factoryCalls.createdIDs.isEmpty)
    }
    @Test("WhisperKit local engine reports loadingModel on first load and skips on second resident call")
    func whisperKitProgressLoadingAndResidentReuse() async throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let whisper = try #require(NativeModelCatalog.descriptor(for: "whisper-small-multilingual"))
        let whisperSettings = try settings(for: whisper, under: root.appendingPathComponent("whisper-resident"))
        let audioURL = root.appendingPathComponent("dictation.wav")
        try Data([1]).write(to: audioURL)

        let progressEvents = LockedValue<[LocalASRProgress]>([])
        let engineLog = RouterEventLog()

        // Custom spy engine that simulates loading and transcription progress
        actor ProgressEmittingEngine: LocalASREngine {
            nonisolated let descriptor: LocalASRModelDescriptor
            private var isLoaded = false
            init(descriptor: LocalASRModelDescriptor) { self.descriptor = descriptor }
            func transcribe(_ request: LocalASRRequest, progress: @escaping LocalASRProgressObserver) async throws -> LocalASRResult {
                if !isLoaded {
                    try await progress(.loadingModel)
                    isLoaded = true
                }
                try await progress(.convertingAudio)
                try await progress(.transcribing(audioPositionSec: 0.0))
                try await progress(.transcribing(audioPositionSec: 30.0))
                return LocalASRResult(text: "transcribed text")
            }
            func unload() async { isLoaded = false }
        }

        let factories = LocalASREngineRouterFactories(
            whisperKit: { model in
                await engineLog.created(model.id)
                return ProgressEmittingEngine(descriptor: model.descriptor)
            },
            parakeet: { model in SpyLocalASREngine(descriptor: model.descriptor, log: engineLog) },
            canary: { model in SpyLocalASREngine(descriptor: model.descriptor, log: engineLog) }
        )
        let router = LocalASREngineRouter(factories: factories)
        let request = LocalASRRequest(audioFileURL: audioURL, languageHint: "en")

        // First call: should emit loadingModel -> convertingAudio -> transcribing(0) -> transcribing(30)
        let firstResult = try await router.transcribe(
            settings: whisperSettings,
            providerID: whisper.id,
            request: request,
            progress: { event in
                progressEvents.set(progressEvents.get() + [event])
            }
        )
        #expect(firstResult.text == "transcribed text")
        #expect(progressEvents.get() == [
            .loadingModel,
            .convertingAudio,
            .transcribing(audioPositionSec: 0.0),
            .transcribing(audioPositionSec: 30.0)
        ])

        // Second call: resident reuse skips loadingModel
        progressEvents.set([])
        let secondResult = try await router.transcribe(
            settings: whisperSettings,
            providerID: whisper.id,
            request: request,
            progress: { event in
                progressEvents.set(progressEvents.get() + [event])
            }
        )
        #expect(secondResult.text == "transcribed text")
        #expect(progressEvents.get() == [
            .convertingAudio,
            .transcribing(audioPositionSec: 0.0),
            .transcribing(audioPositionSec: 30.0)
        ])
    }

    private func makeFixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptRouter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func settings(
        for descriptor: LocalASRModelDescriptor,
        under root: URL
    ) throws -> AppSettings {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for relativePath in descriptor.requiredLayout.requiredFiles {
            let item = root.appendingPathComponent(relativePath)
            if relativePath.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true)
            } else {
                try Data([1]).write(to: item)
            }
        }

        var settings = AppSettings.defaults
        settings.localAsrModels[descriptor.id] = LocalModelState(
            status: .downloaded,
            label: descriptor.displayName,
            path: root.path,
            runtime: descriptor.settingsRuntime
        )
        return settings
    }

    private func expectUnsupportedModel(
        _ operation: () async throws -> Any
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected an incomplete local binding to fail")
        } catch let error as LocalASREngineError {
            guard case .unsupportedModel = error else {
                Issue.record("Unexpected local ASR error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private actor RouterEventLog {
    private(set) var createdIDs: [String] = []
    private(set) var transcriptionCount = 0
    private(set) var unloadCount = 0

    func created(_ id: String) {
        createdIDs.append(id)
    }

    func transcribed() {
        transcriptionCount += 1
    }

    func unloaded() {
        unloadCount += 1
    }
}

private actor SpyLocalASREngine: LocalASREngine {
    nonisolated let descriptor: LocalASRModelDescriptor
    private let log: RouterEventLog

    init(descriptor: LocalASRModelDescriptor, log: RouterEventLog) {
        self.descriptor = descriptor
        self.log = log
    }

    func transcribe(
        _ request: LocalASRRequest,
        progress: @escaping LocalASRProgressObserver
    ) async throws -> LocalASRResult {
        await log.transcribed()
        return LocalASRResult(text: descriptor.id)
    }
    func unload() async {
        await log.unloaded()
    }
}

private final class LockedValue<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.withLock { value } }
    func set(_ newValue: T) { lock.withLock { value = newValue } }
}
