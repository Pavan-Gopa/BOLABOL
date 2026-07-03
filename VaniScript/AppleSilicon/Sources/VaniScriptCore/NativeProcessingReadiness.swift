import Foundation

public struct NativeProcessingReadinessResult: Codable, Equatable, Sendable {
    public var canTranscribe: Bool
    public var canTranslate: Bool
    public var transcriptionMessage: String
    public var translationMessage: String
}

public enum NativeProcessingReadiness {
    public static func evaluate(
        settings: AppSettings,
        targetLang: String,
        transcriptionProvider: String,
        translationProvider: String
    ) -> NativeProcessingReadinessResult {
        let transcriptionOption = ProviderRegistry
            .availableTranscriptionProviders(settings: settings)
            .first { $0.id == transcriptionProvider }
        let cloudTranscriptionReady = transcriptionOption?.group == .cloud
        let localTranscriptionReady = NativeModelCatalog.activeWhisperKitModel(
            settings: settings,
            providerID: transcriptionProvider
        ) != nil
        let transcriptionReady = cloudTranscriptionReady || localTranscriptionReady

        let translationNeeded = targetLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "same"
        let translationOption = ProviderRegistry
            .availableTranslationProviders(settings: settings, targetLang: targetLang)
            .providers
            .first { $0.id == translationProvider }
        let cloudTranslationReady = translationOption?.group == .cloud
        let localTranslationReady = NativeModelCatalog.activeMLXModel(settings: settings, providerID: translationProvider) != nil
        let translationReady = !translationNeeded || cloudTranslationReady || localTranslationReady

        let translationMessage: String
        if !translationNeeded {
            translationMessage = "Translation disabled for same-language sessions."
        } else if let translationOption, translationOption.group == .cloud {
            translationMessage = "\(translationOption.label) translation ready."
        } else if localTranslationReady {
            translationMessage = "MLX translation model ready."
        } else {
            translationMessage = "MLX translation requires a downloaded or located local model."
        }

        let transcriptionMessage: String
        if let transcriptionOption, transcriptionOption.group == .cloud {
            transcriptionMessage = "\(transcriptionOption.label) transcription ready."
        } else if localTranscriptionReady {
            transcriptionMessage = "Core ML transcription model ready."
        } else {
            transcriptionMessage = "Core ML transcription requires a downloaded or located WhisperKit model."
        }

        return NativeProcessingReadinessResult(
            canTranscribe: transcriptionReady,
            canTranslate: translationReady,
            transcriptionMessage: transcriptionMessage,
            translationMessage: translationMessage
        )
    }

}
