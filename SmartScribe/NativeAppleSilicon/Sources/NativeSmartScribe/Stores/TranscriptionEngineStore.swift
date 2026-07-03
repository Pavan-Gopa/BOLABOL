import Foundation
import NativeSmartScribeCore

@MainActor
final class TranscriptionEngineStore: ObservableObject {
    private let fallbackEngine: any TranscriptionEngine
    private var whisperKitEngines: [String: WhisperKitTranscriptionEngine] = [:]

    init(fallbackEngine: any TranscriptionEngine = AppleSpeechTranscriptionEngine()) {
        self.fallbackEngine = fallbackEngine
    }

    static func live() -> TranscriptionEngineStore {
        TranscriptionEngineStore()
    }

    func activeEngine(
        modelStore: TranscriptionModelStore
    ) -> any TranscriptionEngine {
        guard let activeModel = modelStore.settings.activeDownloadedModel(
            catalog: modelStore.catalog
        ) else {
            return fallbackEngine
        }

        switch activeModel.model.backend {
        case .whisperKitCoreML:
            return cachedWhisperKitEngine(for: activeModel)
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
}
