import Foundation
import NativeBolabolCore
import Testing

@Test(arguments: ["parakeet-tdt-06b-v3", "whisperkit-large-v3-turbo", "whisperkit-large-v3-full", "gemini"], [HotkeyTarget.raw, .note, .x2])
func s11TargetLanguageOutputMatrix(modelID: String, hotkeyTarget: HotkeyTarget) async throws {
    let isGemini = modelID == "gemini"
    let model: TranscriptionModelDescriptor?
    if isGemini {
        model = nil
    } else {
        let resolved = try #require(TranscriptionModelCatalog.nativeWhisperKit.model(withID: modelID))
        model = resolved
    }
    let source = "Это исходная русская заметка для проверки перевода на английский язык."
    let english = "This is the English translation of the original Russian note."
    for wantsTarget in [false, true] {
        let snapshot = HotkeyLanguageSnapshotResolver.resolve(
            hotkeyTarget: hotkeyTarget,
            wantsTargetOutput: wantsTarget,
            requestedTargetCode: "en",
            backend: model?.backend,
            modelSupportsNativeTranslation: model?.supportsNativeTranslationToEnglish ?? false,
            isGeminiCloud: isGemini,
            polishingCanTranslate: true
        )
        for response in ["success", "timeout", "wrong-language"] {
            let native = hotkeyTarget == .raw && (isGemini || modelID == "whisperkit-large-v3-full")
            let active = wantsTarget && (hotkeyTarget != .raw || native)
            let raw = native && active && response == "success" ? english : source
            let polished: String? = hotkeyTarget == .raw || response == "timeout"
                ? nil
                : (response == "success" ? english : source)
            let outcome = await TargetLanguageOutputPipeline.run(
                rawText: raw,
                polishText: polished,
                polishSucceeded: polished != nil,
                context: TargetLanguageOutputPipeline.Context(
                    snapshot: snapshot,
                    requestedVariant: hotkeyTarget.processingVariant,
                    primaryCode: "ru",
                    additionalCode: "en"
                ),
                polish: { _, _ in
                    if response == "timeout" { throw URLError(.timedOut) }
                    return response == "success" ? english : source
                },
                translate: { _, _ in
                    if hotkeyTarget == .raw {
                        Issue.record("Raw must never invoke a text translator: \(modelID)")
                    }
                    if response == "timeout" { throw URLError(.timedOut) }
                    return response == "success" ? english : source
                }
            )
            if !active {
                #expect(outcome.text == raw)
                #expect(outcome.kind == .verifiedNative)
            } else if response == "success" {
                #expect(outcome.text == english)
                #expect(outcome.kind == (native ? .verifiedNative : .translated))
                #expect(outcome.verifiedCode == "en")
            } else {
                #expect(outcome.text == source)
                #expect(outcome.kind == .sourceFallback)
                #expect(outcome.reason != nil)
            }
        }
    }
}
