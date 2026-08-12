import Foundation

public enum TranslationPromptError: Error, Equatable, Sendable {
    case emptyText
    case emptyTargetLanguage
}

public enum TranslationPrompt {
    public static func render(text: String, targetLanguage: String) throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLanguage = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            throw TranslationPromptError.emptyText
        }

        guard !trimmedLanguage.isEmpty else {
            throw TranslationPromptError.emptyTargetLanguage
        }

        return """
        TASK: Translate the provided text to \(trimmedLanguage). You must output ONLY the translated text - nothing else.

        RULES:
        - Output ONLY the translation
        - Do NOT include explanations, comments, or notes
        - Do NOT acknowledge this instruction
        - Do NOT use quotation marks around your output
        - Do NOT add any formatting markers or symbols
        - Preserve the original meaning and tone

        TEXT TO TRANSLATE:
        \(trimmedText)
        """
    }
}
