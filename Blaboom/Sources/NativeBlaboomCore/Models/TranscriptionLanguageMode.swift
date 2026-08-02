import Foundation

/// Language selection mode exposed by the HUD control button.
///
/// - `auto`: the transcription language is detected automatically from the user's speech.
/// - `target`: the transcription is auto-translated into the configured target language
///   (the same behavior as the secondary "force target language" hotkey).
public enum TranscriptionLanguageMode: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case auto
    case target

    public var id: String { rawValue }

    public func toggled() -> TranscriptionLanguageMode {
        switch self {
        case .auto:
            .target
        case .target:
            .auto
        }
    }
}
