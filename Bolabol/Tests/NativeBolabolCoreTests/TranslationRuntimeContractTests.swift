import Foundation
@testable import NativeBolabol
import NativeBolabolCore
import Testing

@Test
func translationRuntimeUsesAnExplicitTextPrompt() throws {
    let prompt = try TranslationPrompt.render(
        text: "Keep this meaning.",
        targetLanguage: "French"
    )

    #expect(prompt.contains("Translate the provided text to French"))
    #expect(prompt.contains("Keep this meaning."))
    #expect(!prompt.contains("speech"))
}

@Test
func translationRuntimeHasNoCanarySpeechTranslationSurface() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBolabol/Views/TranslationModalView.swift",
        encoding: .utf8
    )
    let floatingSource = try String(
        contentsOfFile: "Sources/NativeBolabol/Services/FloatingTranslationWindowManager.swift",
        encoding: .utf8
    )

    #expect(!source.contains("Canary"))
    #expect(!source.contains("SpeechTranslation"))
    #expect(!floatingSource.contains("Canary"))
    #expect(!floatingSource.contains("SpeechTranslation"))
    #expect(!floatingSource.contains("onCanaryTranslation"))
}
