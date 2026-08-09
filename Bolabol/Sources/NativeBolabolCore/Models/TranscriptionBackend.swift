/// How Bolabol turns microphone audio into text.
///
/// - `localWhisper`: on-device speech models (requires a downloaded model).
/// - `geminiCloud`: audio → lightly cleaned Raw text with Google Gemini Flash /
///   Flash-Lite, followed by an optional text-only Variant 1/2 pass.
///   No Apple Speech path — on-device system STT is intentionally unsupported
///   because quality is too low for this product.
public enum TranscriptionBackend: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case localWhisper
    case geminiCloud

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .localWhisper:
            "Local"
        case .geminiCloud:
            "Cloud · Google"
        }
    }

    public var shortDescription: String {
        switch self {
        case .localWhisper:
            "On-device speech models. Best quality when your Mac has enough memory for a model."
        case .geminiCloud:
            "Fast Gemini Raw transcription first, then an optional text-only Variant 1/2 pass. Google API only."
        }
    }

    public var supportsRawHotkeyTarget: Bool {
        true
    }
}
