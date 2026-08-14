import Foundation
import VaniScriptCore
import WhisperKit

extension WhisperKit: @unchecked @retroactive Sendable {}

/// Factory seams keep router lifecycle tests independent of Core ML weights and SDK downloads.
struct LocalASREngineRouterFactories: Sendable {
    let whisperKit: @Sendable (ActiveLocalASRModel) async throws -> any LocalASREngine
    let parakeet: @Sendable (ActiveLocalASRModel) async throws -> any LocalASREngine
    let canary: @Sendable (ActiveLocalASRModel) async throws -> any LocalASREngine

    init(
        whisperKit: @escaping @Sendable (ActiveLocalASRModel) async throws -> any LocalASREngine,
        parakeet: @escaping @Sendable (ActiveLocalASRModel) async throws -> any LocalASREngine,
        canary: @escaping @Sendable (ActiveLocalASRModel) async throws -> any LocalASREngine
    ) {
        self.whisperKit = whisperKit
        self.parakeet = parakeet
        self.canary = canary
    }

    static let live = LocalASREngineRouterFactories(
        whisperKit: { model in
            guard model.descriptor.backend == .whisperKitCoreML,
                  let variant = NativeModelCatalog.whisperKitVariant(for: model.id)
            else {
                throw LocalASREngineError.unsupportedModel(
                    "expected a catalog WhisperKit descriptor and variant"
                )
            }
            return WhisperKitLocalASREngine(
                model: model,
                variant: variant
            )
        },
        parakeet: { model in
            guard model.descriptor.backend == .fluidAudioCoreML else {
                throw LocalASREngineError.unsupportedModel(
                    "expected a catalog Parakeet descriptor"
                )
            }
            return ParakeetTranscriptionEngine(
                model: model.descriptor,
                modelFolderURL: URL(fileURLWithPath: model.path, isDirectory: true)
            )
        },
        canary: { model in
            guard model.descriptor.backend == .canaryCoreML else {
                throw LocalASREngineError.unsupportedModel(
                    "expected a catalog Canary descriptor"
                )
            }
            return CanaryCoreMLEngine(
                model: model.descriptor,
                modelFolderURL: URL(fileURLWithPath: model.path, isDirectory: true)
            )
        }
    )
}

/// One resident local ASR binding shared by batch, current-chunk, and dictation paths.
///
/// The catalog is the only source of active model truth. A binding is the selected
/// descriptor id plus its canonical verified path; changing either unloads the old
/// engine before constructing the replacement.
actor LocalASREngineRouter {
    private struct BindingKey: Equatable, Sendable {
        let descriptorID: String
        let canonicalPath: String
    }

    private struct ResidentEngine {
        let key: BindingKey
        let engine: any LocalASREngine
    }

    private let factories: LocalASREngineRouterFactories
    private var resident: ResidentEngine?

    init(factories: LocalASREngineRouterFactories = .live) {
        self.factories = factories
    }

    func transcribe(
        settings: AppSettings,
        providerID: String,
        request: LocalASRRequest
    ) async throws -> LocalASRResult {
        guard let activeModel = NativeModelCatalog.activeLocalASRModel(
            settings: settings,
            providerID: providerID
        ) else {
            throw LocalASREngineError.unsupportedModel(
                "no complete active local ASR binding for provider '\(providerID)'"
            )
        }

        let boundModel = Self.canonicalized(activeModel)
        let engine = try await resolve(boundModel)
        return try await engine.transcribe(request)
    }

    /// Resolve a binding without performing inference. Tests and lifecycle callers
    /// use this to prove exact backend routing and resident reuse.
    func resolveActive(
        settings: AppSettings,
        providerID: String
    ) async throws -> any LocalASREngine {
        guard let activeModel = NativeModelCatalog.activeLocalASRModel(
            settings: settings,
            providerID: providerID
        ) else {
            throw LocalASREngineError.unsupportedModel(
                "no complete active local ASR binding for provider '\(providerID)'"
            )
        }
        return try await resolve(Self.canonicalized(activeModel))
    }

    func unloadBeforeHeavyLocalModel() async {
        await unload()
    }

    func unload() async {
        guard let resident else { return }
        self.resident = nil
        await resident.engine.unload()
    }

    private func resolve(_ model: ActiveLocalASRModel) async throws -> any LocalASREngine {
        let key = BindingKey(
            descriptorID: model.id,
            canonicalPath: model.path
        )
        if let resident, resident.key == key {
            return resident.engine
        }

        await unload()

        let engine: any LocalASREngine
        switch model.descriptor.backend {
        case .whisperKitCoreML:
            engine = try await factories.whisperKit(model)
        case .fluidAudioCoreML:
            engine = try await factories.parakeet(model)
        case .canaryCoreML:
            engine = try await factories.canary(model)
        }

        guard engine.descriptor.id == model.descriptor.id,
              engine.descriptor.backend == model.descriptor.backend
        else {
            await engine.unload()
            throw LocalASREngineError.unsupportedModel(
                "factory returned a descriptor that does not match '\(model.id)'"
            )
        }

        resident = ResidentEngine(key: key, engine: engine)
        return engine
    }

    private static func canonicalized(_ model: ActiveLocalASRModel) -> ActiveLocalASRModel {
        var copy = model
        copy.path = URL(fileURLWithPath: model.path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return copy
    }
}

/// WhisperKit/Core ML adapted to the common ASR-only engine contract.
actor WhisperKitLocalASREngine: LocalASREngine {
    nonisolated let descriptor: LocalASRModelDescriptor

    private let model: ActiveLocalASRModel
    private let variant: String
    private let loader: @Sendable (ActiveLocalASRModel) async throws -> WhisperKit
    private var pipeline: WhisperKit?

    init(
        model: ActiveLocalASRModel,
        variant: String,
        loader: @escaping @Sendable (ActiveLocalASRModel) async throws -> WhisperKit = WhisperKitLocalASREngine.defaultLoader
    ) {
        self.descriptor = model.descriptor
        self.model = model
        self.variant = variant
        self.loader = loader
    }

    func transcribe(_ request: LocalASRRequest) async throws -> LocalASRResult {
        try Task.checkCancellation()
        guard descriptor.backend == .whisperKitCoreML,
              NativeModelCatalog.whisperKitVariant(for: model.id) == variant
        else {
            throw LocalASREngineError.unsupportedModel(
                "expected a catalog WhisperKit descriptor and variant"
            )
        }
        guard request.audioFileURL != nil else {
            throw LocalASREngineError.missingAudioFile
        }
        guard !request.translateToEnglish else {
            throw LocalASREngineError.translationUnsupported
        }

        let pipeline = try await loadedPipeline()
        let results: [TranscriptionResult]
        do {
            results = try await pipeline.transcribe(
                audioPath: request.audioFileURL!.path,
                decodeOptions: decodeOptions(for: request)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LocalASREngineError {
            throw error
        } catch {
            throw LocalASREngineError.inferenceFailed(error.localizedDescription)
        }

        try Task.checkCancellation()
        let text = results.map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw LocalASREngineError.emptyResult
        }

        let cues = Self.timedCues(from: results)
        return LocalASRResult(text: text, cues: cues.isEmpty ? nil : cues)
    }

    func unload() async {
        guard let pipeline else { return }
        self.pipeline = nil
        await pipeline.unloadModels()
    }

    private func loadedPipeline() async throws -> WhisperKit {
        if let pipeline {
            return pipeline
        }
        do {
            let loaded = try await loader(model)
            pipeline = loaded
            return loaded
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LocalASREngineError {
            throw error
        } catch {
            throw LocalASREngineError.inferenceFailed(
                "Could not load the WhisperKit model: \(error.localizedDescription)"
            )
        }
    }

    private func decodeOptions(for request: LocalASRRequest) -> DecodingOptions {
        let languageCode = NativeLanguagePolicy.canonicalCode(request.languageHint ?? "auto")
        let language = languageCode == NativeLanguagePolicy.autoCode
            || languageCode == NativeLanguagePolicy.keepOriginalCode
            ? nil
            : languageCode
        return DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true
        )
    }

    private static func timedCues(from results: [TranscriptionResult]) -> [TranscriptCue] {
        results
            .flatMap(\.segments)
            .compactMap { segment in
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let start = max(0, Double(segment.start))
                let end = max(start + 0.25, Double(segment.end))
                let words = (segment.words ?? []).compactMap { word -> TranscriptWord? in
                    let wordText = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !wordText.isEmpty else { return nil }
                    let wordStart = max(start, Double(word.start))
                    let wordEnd = max(wordStart + 0.05, Double(word.end))
                    return TranscriptWord(
                        startSec: wordStart,
                        endSec: wordEnd,
                        text: wordText
                    )
                }
                return TranscriptCue(
                    startSec: start,
                    endSec: end,
                    text: text,
                    words: words.isEmpty ? nil : words
                )
            }
    }

    private static let defaultLoader: @Sendable (ActiveLocalASRModel) async throws -> WhisperKit = { model in
        guard let variant = NativeModelCatalog.whisperKitVariant(for: model.id) else {
            throw LocalASREngineError.unsupportedModel(
                "expected a catalog WhisperKit descriptor and variant"
            )
        }
        let config = WhisperKitConfig(
            model: variant,
            modelFolder: model.path,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )
        return try await WhisperKit(config)
    }
}
