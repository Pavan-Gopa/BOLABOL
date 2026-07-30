import Foundation
import NativeSmartScribeCore

/// Placeholder engine used when neither a local Whisper model nor Gemini cloud
/// dictation is configured. Apple Speech is intentionally never used.
struct UnavailableTranscriptionEngine: TranscriptionEngine {
    let id = "transcription-unavailable"
    let displayName = "Transcription unavailable"

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        throw UnavailableTranscriptionError.notConfigured
    }
}

enum UnavailableTranscriptionError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "No transcription path is ready. Download a local Whisper model in Settings → Local Models, or switch Transcription to Cloud · Google Gemini and add a Google API key in Settings → API Providers."
        }
    }
}
