import Foundation
import NativeBolabolCore

@MainActor
struct TranscriptionEngineSession {
    let engine: any TranscriptionEngine
    let plan: TranscriptionSessionPlan

    func replacing(plan: TranscriptionSessionPlan) -> TranscriptionEngineSession {
        TranscriptionEngineSession(engine: engine, plan: plan)
    }
}

@MainActor
enum TranscriptionEngineSessionResolution {
    case available(TranscriptionEngineSession)
    case unavailable(TranscriptionSessionUnavailableReason)
}

@MainActor
final class TranscriptionEngineStore: ObservableObject {
    /// Apple Speech is intentionally never used as a fallback.

    static func live() -> TranscriptionEngineStore {
        TranscriptionEngineStore()
    }

    /// Resolves the active local transcription engine when backend is local and
    /// a model is active. For Gemini cloud, callers must use
    /// `GeminiCloudDictationEngine` instead.
    func activeEngine(
        modelStore: TranscriptionModelStore
    ) -> any TranscriptionEngine {
        switch modelStore.settings.backend {
        case .geminiCloud:
            // Cloud path is handled separately; return unavailable if misrouted.
            return UnavailableTranscriptionEngine()
        case .localWhisper:
            guard let activeModel = modelStore.activeDownloadedModel() else {
                return UnavailableTranscriptionEngine()
            }

            return engine(for: activeModel)
        }
    }

    /// Resolves the engine and immutable route from the same active model
    /// snapshot. No caller may pair a route from a newer model with this
    /// engine after the session begins.
    func makeSession(
        modelStore: TranscriptionModelStore,
        operation: TranscriptionSessionOperation,
        legacyLanguageCode: String? = nil
    ) -> TranscriptionEngineSessionResolution {
        guard modelStore.settings.backend == .localWhisper else {
            return .unavailable(.noActiveModel)
        }

        guard let activeModel = modelStore.activeModel else {
            return .unavailable(.noActiveModel)
        }

        let hasCompleteModel = modelStore.hasLocalFiles(for: activeModel)
        guard modelStore.isModelAvailable(for: activeModel),
              hasCompleteModel,
              let downloadedModel = modelStore.activeDownloadedModel()
        else {
            return unavailableResolution(
                for: activeModel,
                modelStore: modelStore,
                operation: operation,
                legacyLanguageCode: legacyLanguageCode,
                hasCompleteModel: hasCompleteModel
            )
        }

        let preflight = TranscriptionSessionResolver.resolve(
            activeModel: downloadedModel.model,
            modelFolderURL: downloadedModel.modelFolderURL,
            currentOSVersion: modelStore.currentSessionOSVersion,
            hasCompleteModel: true,
            primaryLanguageCode: modelStore.speechLanguages.primaryLanguageCode,
            additionalLanguageCode: modelStore.speechLanguages.additionalLanguageCode,
            operation: operation,
            legacyLanguageCode: legacyLanguageCode
        )

        guard case .available = preflight else {
            if case .unavailable(let reason) = preflight {
                return .unavailable(reason)
            }
            return .unavailable(.unsupportedOperation(modelID: downloadedModel.model.id))
        }

        let engine = engine(for: downloadedModel)
        let resolution = TranscriptionSessionResolver.resolve(
            activeModel: downloadedModel.model,
            modelFolderURL: downloadedModel.modelFolderURL,
            engineIdentity: engine.id,
            currentOSVersion: modelStore.currentSessionOSVersion,
            hasCompleteModel: true,
            primaryLanguageCode: modelStore.speechLanguages.primaryLanguageCode,
            additionalLanguageCode: modelStore.speechLanguages.additionalLanguageCode,
            operation: operation,
            legacyLanguageCode: legacyLanguageCode
        )

        switch resolution {
        case .available(let plan):
            return .available(TranscriptionEngineSession(engine: engine, plan: plan))
        case .unavailable(let reason):
            return .unavailable(reason)
        }
    }

    private var whisperKitEngines: [String: WhisperKitTranscriptionEngine] = [:]
    private var parakeetEngines: [String: ParakeetTranscriptionEngine] = [:]
    private var canaryEngines: [String: CanaryCoreMLEngine] = [:]
    private var gigaAMEngines: [String: GigaAMCoreMLEngine] = [:]

    private func engine(
        for activeModel: ActiveTranscriptionModel
    ) -> any TranscriptionEngine {
        switch activeModel.model.backend {
        case .whisperKitCoreML:
            cachedWhisperKitEngine(for: activeModel)
        case .fluidAudioCoreML:
            cachedParakeetEngine(for: activeModel)
        case .canaryCoreML:
            cachedCanaryEngine(for: activeModel)
        case .gigaAMCoreML:
            cachedGigaAMEngine(for: activeModel)
        }
    }

    private func unavailableResolution(
        for model: TranscriptionModelDescriptor,
        modelStore: TranscriptionModelStore,
        operation: TranscriptionSessionOperation,
        legacyLanguageCode: String?,
        hasCompleteModel: Bool
    ) -> TranscriptionEngineSessionResolution {
        let resolution = TranscriptionSessionResolver.resolve(
            activeModel: model,
            currentOSVersion: modelStore.currentSessionOSVersion,
            hasCompleteModel: hasCompleteModel,
            primaryLanguageCode: modelStore.speechLanguages.primaryLanguageCode,
            additionalLanguageCode: modelStore.speechLanguages.additionalLanguageCode,
            operation: operation,
            legacyLanguageCode: legacyLanguageCode
        )
        switch resolution {
        case .available:
            return .unavailable(.incompleteModel(modelID: model.id))
        case .unavailable(let reason):
            return .unavailable(reason)
        }
    }

    private func cachedWhisperKitEngine(
        for activeModel: ActiveTranscriptionModel
    ) -> WhisperKitTranscriptionEngine {
        let cacheKey = [
            activeModel.model.id,
            activeModel.modelFolderURL.path
        ].joined(separator: "|")

        if let cachedEngine = whisperKitEngines[cacheKey] {
            return cachedEngine
        }

        let engine = WhisperKitTranscriptionEngine(
            model: activeModel.model,
            modelFolderURL: activeModel.modelFolderURL
        )
        whisperKitEngines[cacheKey] = engine
        return engine
    }

    private func cachedParakeetEngine(
        for activeModel: ActiveTranscriptionModel
    ) -> ParakeetTranscriptionEngine {
        let cacheKey = [
            activeModel.model.id,
            activeModel.modelFolderURL.path
        ].joined(separator: "|")

        if let cachedEngine = parakeetEngines[cacheKey] {
            return cachedEngine
        }

        let engine = ParakeetTranscriptionEngine(
            model: activeModel.model,
            modelFolderURL: activeModel.modelFolderURL
        )
        parakeetEngines[cacheKey] = engine
        return engine
    }

    private func cachedCanaryEngine(
        for activeModel: ActiveTranscriptionModel
    ) -> CanaryCoreMLEngine {
        let cacheKey = [
            activeModel.model.id,
            activeModel.modelFolderURL.path
        ].joined(separator: "|")

        if let cachedEngine = canaryEngines[cacheKey] {
            return cachedEngine
        }

        let engine = CanaryCoreMLEngine(
            model: activeModel.model,
            modelFolderURL: activeModel.modelFolderURL
        )
        canaryEngines[cacheKey] = engine
        return engine
    }

    private func cachedGigaAMEngine(
        for activeModel: ActiveTranscriptionModel
    ) -> GigaAMCoreMLEngine {
        let cacheKey = [
            activeModel.model.id,
            activeModel.modelFolderURL.path
        ].joined(separator: "|")

        if let cachedEngine = gigaAMEngines[cacheKey] {
            return cachedEngine
        }

        let engine = GigaAMCoreMLEngine(
            model: activeModel.model,
            modelFolderURL: activeModel.modelFolderURL
        )
        gigaAMEngines[cacheKey] = engine
        return engine
    }
}
