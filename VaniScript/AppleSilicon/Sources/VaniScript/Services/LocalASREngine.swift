import Foundation
import VaniScriptCore

/// The small request surface shared by native ASR engines.
///
/// Local engines receive an audio file and an optional source-language hint. The
/// translation flag remains part of the request so every local engine can reject
/// a translation route explicitly instead of silently returning the wrong mode.
struct LocalASRRequest: Sendable, Equatable {
    var audioFileURL: URL?
    var languageHint: String?
    var translateToEnglish: Bool

    init(
        audioFileURL: URL? = nil,
        languageHint: String? = nil,
        translateToEnglish: Bool = false
    ) {
        self.audioFileURL = audioFileURL
        self.languageHint = languageHint
        self.translateToEnglish = translateToEnglish
    }
}

/// A successful local ASR response. Cue construction belongs to the caller;
/// engines only guarantee usable source-language text.
struct LocalASRResult: Sendable, Equatable {
    var text: String

    init(text: String) {
        self.text = text
    }
}

enum LocalASREngineError: LocalizedError, Equatable, Sendable {
    case missingAudioFile
    case translationUnsupported
    case unsupportedModel(String)
    case modelUnavailable(URL)
    case audioPreparationFailed(String)
    case inferenceFailed(String)
    case emptyResult
    case decoderStateInitializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            return "Local transcription needs a recorded or imported audio file."
        case .translationUnsupported:
            return "Local ASR transcribes the source language but does not translate speech to English."
        case .unsupportedModel(let detail):
            return "The selected local ASR model is unsupported: \(detail)"
        case .modelUnavailable(let url):
            return "The selected local ASR model is not available at \(url.path)."
        case .audioPreparationFailed(let detail):
            return "Could not prepare audio for local transcription: \(detail)"
        case .inferenceFailed(let detail):
            return "Local transcription failed: \(detail)"
        case .emptyResult:
            return "Local transcription returned no text."
        case .decoderStateInitializationFailed(let detail):
            return "Could not initialize local ASR decoder state: \(detail)"
        }
    }
}

/// ASR-only contract implemented by local transcription engines.
protocol LocalASREngine: Sendable {
    var descriptor: LocalASRModelDescriptor { get }
    func transcribe(_ request: LocalASRRequest) async throws -> LocalASRResult
    func unload() async
}
