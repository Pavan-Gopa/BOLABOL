import NativeBlaboomCore
import Testing

@Test
func translationPromptRendersStrictTargetLanguagePrompt() throws {
    let prompt = try TranslationPrompt.render(
        text: "Привет, это тест.",
        targetLanguage: "English"
    )

    #expect(prompt.contains("Translate the provided text to English"))
    #expect(prompt.contains("Output ONLY the translation"))
    #expect(prompt.contains("Привет, это тест."))
}

@Test
func translationPromptRejectsEmptyInput() {
    #expect(throws: TranslationPromptError.emptyText) {
        try TranslationPrompt.render(text: "   ", targetLanguage: "English")
    }
}

@Test
func translationPromptRejectsEmptyTargetLanguage() {
    #expect(throws: TranslationPromptError.emptyTargetLanguage) {
        try TranslationPrompt.render(text: "Hello", targetLanguage: "   ")
    }
}
