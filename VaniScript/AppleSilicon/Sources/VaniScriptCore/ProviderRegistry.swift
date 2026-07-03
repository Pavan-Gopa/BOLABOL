import Foundation

public enum ProviderGroup: String, Codable, Equatable, Sendable {
    case cloud
    case local
}

public enum ProviderKind: String, Codable, Equatable, Sendable {
    case transcription
    case translation
}

public struct ProviderOption: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var group: ProviderGroup
    public var kind: ProviderKind
    public var requiresKey: String?
}

public struct TranslationProviderAvailability: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var providers: [ProviderOption]
}

public enum ProviderRegistry {
    public static func availableTranscriptionProviders(settings: AppSettings) -> [ProviderOption] {
        var providers: [ProviderOption] = [
            ProviderOption(
                id: "coreml-whisperkit",
                label: "WhisperKit Core ML",
                group: .local,
                kind: .transcription,
                requiresKey: nil
            )
        ]
        if !settings.geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            providers.append(
                ProviderOption(
                    id: "gemini-cloud",
                    label: "Gemini Cloud",
                    group: .cloud,
                    kind: .transcription,
                    requiresKey: "gemini"
                )
            )
        }
        if !settings.openaiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            providers.append(
                ProviderOption(
                    id: "gpt-cloud",
                    label: "GPT Cloud",
                    group: .cloud,
                    kind: .transcription,
                    requiresKey: "openai"
                )
            )
        }
        return providers + downloadedLocalProviders(models: settings.localAsrModels, kind: .transcription)
    }

    public static func availableTranslationProviders(
        settings: AppSettings,
        targetLang: String
    ) -> TranslationProviderAvailability {
        guard targetLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "same" else {
            return TranslationProviderAvailability(enabled: false, providers: [])
        }

        var providers: [ProviderOption] = []
        if !settings.geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            providers.append(
                ProviderOption(
                    id: "gemini-cloud",
                    label: "Gemini Cloud",
                    group: .cloud,
                    kind: .translation,
                    requiresKey: "gemini"
                )
            )
        }
        if !settings.openaiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            providers.append(
                ProviderOption(
                    id: "gpt-cloud",
                    label: "GPT Cloud",
                    group: .cloud,
                    kind: .translation,
                    requiresKey: "openai"
                )
            )
        }
        providers.append(
            ProviderOption(
                id: "mlx-native",
                label: "MLX Swift Local",
                group: .local,
                kind: .translation,
                requiresKey: nil
            )
        )
        providers += downloadedLocalProviders(models: settings.localTranslationModels, kind: .translation)
        return TranslationProviderAvailability(enabled: true, providers: providers)
    }

    private static func downloadedLocalProviders(
        models: [String: LocalModelState],
        kind: ProviderKind
    ) -> [ProviderOption] {
        models
            .filter { id, state in
                guard state.status == .downloaded else { return false }
                switch kind {
                case .transcription:
                    return LocalModelVerification.verifyModelPath(state.path, isWhisper: true)
                case .translation:
                    return state.runtime == .mlx
                        && LocalModelVerification.verifyTranslationModelPath(state.path, modelID: id)
                }
            }
            .map { id, state in
                ProviderOption(
                    id: id,
                    label: state.label,
                    group: .local,
                    kind: kind,
                    requiresKey: nil
                )
            }
            .sorted { $0.label < $1.label }
    }
}
