import Testing
@testable import VaniScriptCore

@Suite("Native processing readiness")
struct NativeProcessingReadinessTests {
    init() {
        LocalModelVerification.skipVerificationForTesting = true
    }

    @Test("requires downloaded Core ML model for native transcription")
    func requiresCoreMLModel() {
        let result = NativeProcessingReadiness.evaluate(settings: .defaults, targetLang: "Russian", transcriptionProvider: "coreml-whisperkit", translationProvider: "mlx-native")

        #expect(result.canTranscribe == false)
        #expect(result.transcriptionMessage.contains("Core ML"))
    }

    @Test("allows processing when required local models are present")
    func allowsReadyNativeModels() {
        var settings = AppSettings.defaults
        settings.localAsrModels["whisper-large-v3"]?.status = .downloaded
        settings.localAsrModels["whisper-large-v3"]?.path = "/models/whisper"
        settings.localTranslationModels["qwen35-4b-4bit"]?.status = .downloaded
        settings.localTranslationModels["qwen35-4b-4bit"]?.path = "/models/qwen35-4b"

        let result = NativeProcessingReadiness.evaluate(settings: settings, targetLang: "Russian", transcriptionProvider: "coreml-whisperkit", translationProvider: "qwen35-4b-4bit")

        #expect(result.canTranscribe)
        #expect(result.canTranslate)
    }

    @Test("does not require MLX translation model for same-language sessions")
    func sameLanguageDoesNotRequireTranslationModel() {
        var settings = AppSettings.defaults
        settings.localAsrModels["whisper-large-v3"]?.status = .downloaded
        settings.localAsrModels["whisper-large-v3"]?.path = "/models/whisper"

        let result = NativeProcessingReadiness.evaluate(settings: settings, targetLang: "same", transcriptionProvider: "coreml-whisperkit", translationProvider: "")

        #expect(result.canTranscribe)
        #expect(result.canTranslate)
    }

    @Test("allows cloud translation provider without local MLX model")
    func cloudTranslationProviderDoesNotRequireMLXModel() {
        var settings = AppSettings.defaults
        settings.geminiKey = "gemini-key"
        settings.localAsrModels["whisper-large-v3"]?.status = .downloaded
        settings.localAsrModels["whisper-large-v3"]?.path = "/models/whisper"

        let result = NativeProcessingReadiness.evaluate(
            settings: settings,
            targetLang: "Russian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "gemini-cloud"
        )

        #expect(result.canTranscribe)
        #expect(result.canTranslate)
        #expect(result.translationMessage.contains("Gemini Cloud"))
    }

    @Test("allows cloud transcription provider without local Whisper model")
    func cloudTranscriptionProviderDoesNotRequireWhisperModel() {
        var settings = AppSettings.defaults
        settings.geminiKey = "gemini-key"

        let result = NativeProcessingReadiness.evaluate(
            settings: settings,
            targetLang: "same",
            transcriptionProvider: "gemini-cloud",
            translationProvider: "mlx-native"
        )

        #expect(result.canTranscribe)
        #expect(result.canTranslate)
        #expect(result.transcriptionMessage.contains("Gemini Cloud"))
    }

    @Test("allows cloud transcription and cloud translation without local models")
    func cloudTranscriptionAndTranslationDoNotRequireLocalModels() {
        var settings = AppSettings.defaults
        settings.geminiKey = "gemini-key"

        let result = NativeProcessingReadiness.evaluate(
            settings: settings,
            targetLang: "Russian",
            transcriptionProvider: "gemini-cloud",
            translationProvider: "gemini-cloud"
        )

        #expect(result.canTranscribe)
        #expect(result.canTranslate)
        #expect(result.transcriptionMessage.contains("Gemini Cloud"))
        #expect(result.translationMessage.contains("Gemini Cloud"))
    }
}
