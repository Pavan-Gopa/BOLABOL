import Foundation
import NativeBlaboomCore
@preconcurrency import Speech

final class AppleSpeechTranscriptionEngine: TranscriptionEngine {
    let id = "apple-speech-on-device"
    let displayName = "Apple Speech On-Device"

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        guard let audioFileURL = request.audioFileURL else {
            throw AppleSpeechTranscriptionError.missingAudioFile
        }

        let authorizationStatus = await Self.requestAuthorization()
        guard authorizationStatus == .authorized else {
            throw AppleSpeechTranscriptionError.notAuthorized
        }

        let locale = request.forcedLanguageCode.map(Locale.init(identifier:)) ?? .current
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AppleSpeechTranscriptionError.recognizerUnavailable(locale.identifier)
        }

        guard recognizer.isAvailable else {
            throw AppleSpeechTranscriptionError.recognizerUnavailable(locale.identifier)
        }

        guard recognizer.supportsOnDeviceRecognition else {
            throw AppleSpeechTranscriptionError.onDeviceRecognitionUnavailable(locale.identifier)
        }

        let speechRequest = SFSpeechURLRecognitionRequest(url: audioFileURL)
        speechRequest.shouldReportPartialResults = false
        speechRequest.requiresOnDeviceRecognition = true

        let startedAt = Date()
        let text = try await recognize(with: recognizer, request: speechRequest)
        let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)

        return TranscriptionResult(
            text: text,
            diagnostics: EngineDiagnostics(
                backendName: displayName,
                loadTimeMilliseconds: elapsedMilliseconds
            )
        )
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func recognize(
        with recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let state = RecognitionState()
            state.task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    state.resume(continuation, throwing: error)
                    return
                }

                guard let result, result.isFinal else { return }

                let text = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if text.isEmpty {
                    state.resume(continuation, throwing: AppleSpeechTranscriptionError.emptyResult)
                } else {
                    state.resume(continuation, returning: text)
                }
            }
        }
    }
}

private enum AppleSpeechTranscriptionError: LocalizedError {
    case missingAudioFile
    case notAuthorized
    case recognizerUnavailable(String)
    case onDeviceRecognitionUnavailable(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            AppText.localized(.missingAudioFileForTranscription, language: .english)
        case .notAuthorized:
            AppText.localized(.speechPermissionDisabled, language: .english)
        case .recognizerUnavailable(let locale):
            String(
                format: AppText.localized(.appleSpeechUnavailableForLocale, language: .english),
                locale
            )
        case .onDeviceRecognitionUnavailable(let locale):
            String(
                format: AppText.localized(.appleSpeechOnDeviceUnavailableForLocale, language: .english),
                locale
            )
        case .emptyResult:
            AppText.localized(.appleSpeechReturnedEmptyTranscript, language: .english)
        }
    }
}

private final class RecognitionState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    var task: SFSpeechRecognitionTask?

    func resume(
        _ continuation: CheckedContinuation<String, Error>,
        returning value: String
    ) {
        resume(continuation, result: .success(value))
    }

    func resume(
        _ continuation: CheckedContinuation<String, Error>,
        throwing error: Error
    ) {
        resume(continuation, result: .failure(error))
    }

    private func resume(
        _ continuation: CheckedContinuation<String, Error>,
        result: Result<String, Error>
    ) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        let currentTask = task
        task = nil
        lock.unlock()

        currentTask?.cancel()

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
