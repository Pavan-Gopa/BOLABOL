import Foundation

/// Offline, zero-model polishing path used as a safe fallback / quick cleanup.
/// Applies `SpeechCleanupNormalizer` (light for Variant 1, structured for Variant 2).
public struct LocalRuleBasedPolishingEngine: PolishingEngine {
  public let id = "local-rule-based-polish"
  public let displayName = "Quick Local Cleanup"

  public init() {}

  public func polish(_ request: PolishingRequest) async throws -> PolishingResult {
    _ = try request.template.render(transcription: request.rawText)

    let cleaned = SpeechCleanupNormalizer.normalize(request.rawText, mode: .lightCleanup)
    guard !cleaned.isEmpty else {
      throw LocalRuleBasedPolishingError.emptyInput
    }

    let output: String
    switch request.variant {
    case .raw, .variantOne:
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

public enum LocalRuleBasedPolishingError: LocalizedError, Equatable, Sendable {
  case emptyInput

  public var errorDescription: String? {
    switch self {
    case .emptyInput:
      AppText.localized(.noTranscriptToPolish, language: .english)
    }
  }
}
