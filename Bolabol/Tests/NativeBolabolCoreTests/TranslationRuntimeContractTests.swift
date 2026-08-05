import Foundation
@testable import NativeBolabol
import NativeBolabolCore
import Testing

@Test
func speechTranslationRequestKeepsAnExplicitPairSeparateFromDictationSettings() {
    let request = SpeechTranslationRequest(
        audioFileURL: URL(fileURLWithPath: "/tmp/translation.wav"),
        sourceLanguageCode: " ru ",
        targetLanguageCode: " en "
    )

    #expect(request.sourceLanguageCode == " ru ")
    #expect(request.targetLanguageCode == " en ")
    #expect(request.audioFileURL.path == "/tmp/translation.wav")
}

@Test
@MainActor
func translationRuntimeStoreCachesByModelAndFolderWithoutUsingTheMainStore() throws {
    let model = try #require(
        TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-1b-v2-coreml")
    )
    let activeModel = ActiveTranscriptionModel(
        model: model,
        modelFolderURL: URL(fileURLWithPath: "/tmp/canary-translation-runtime")
    )
    let store = CanarySpeechTranslationRuntimeStore()

    let first = store.runtime(for: activeModel)
    let second = store.runtime(for: activeModel)

    #expect(first.id == "canary-speech-translation:canary-1b-v2-coreml")
    #expect(first.id == second.id)
    #expect(first.displayName.contains("Speech Translation"))
}
