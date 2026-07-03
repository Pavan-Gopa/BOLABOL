import Foundation
import NativeSmartScribeCore

struct LocalRuleBasedPolishingEngine: PolishingEngine {
    let id = "local-rule-based-polish"
    let displayName = "Quick Local Cleanup"

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        _ = try request.template.render(transcription: request.rawText)

        let cleaned = SpeechCleanupNormalizer.normalize(request.rawText, mode: .lightCleanup)
        guard !cleaned.isEmpty else {
            throw LocalRuleBasedPolishingError.emptyInput
        }

        let output: String
        switch request.variant {
        case .raw:
            output = cleaned
        case .variantOne:
            output = cleaned
        case .variantTwo:
            output = SpeechCleanupNormalizer.normalize(request.rawText, mode: .structuredCleanup)
        }

        return PolishingResult(
            text: output,
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private enum LocalRuleBasedPolishingError: LocalizedError {
    case emptyInput

    var errorDescription: String? {
        AppText.localized(.noTranscriptToPolish, language: .english)
    }
}
