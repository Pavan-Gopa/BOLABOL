import Foundation
import NativeSmartScribeCore

@MainActor
final class TranscriptionEngineStore: ObservableObject {
    /// Apple Speech is intentionally never used as a fallback.

    static func live() -> TranscriptionEngineStore {
        TranscriptionEngineStore()
    }

    /// Resolves the local Whisper engine when backend is local and a model is active.
    /// For Gemini cloud, callers must use `GeminiCloudDictationEngine` instead.
    func activeEngine(
        modelStore: TranscriptionModelStore
    ) -> any TranscriptionEngine {
        switch modelStore.settings.backend {
        case .geminiCloud:
            // Cloud path is handled separately; return unavailable if misrouted.
            return UnavailableTranscriptionEngine()
        case .localWhisper:
            guard let activeModel = modelStore.settings.activeDownloadedModel(
                catalog: modelStore.catalog
            ) else {
                return UnavailableTranscriptionEngine()
            }

            switch activeModel.model.backend {
            case .whisperKitCoreML:
                return cachedWhisperKitEngine(for: activeModel)
            }
        }
    }

    private var whisperKitEngines: [String: WhisperKitTranscriptionEngine] = [:]

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
}
