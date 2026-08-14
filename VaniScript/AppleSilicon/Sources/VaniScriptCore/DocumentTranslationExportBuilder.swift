import Foundation

public enum DocumentTranslationExportBuilder {
    public static func translatedDocumentText(
        documentState: DocumentState,
        language: String? = nil
    ) -> String {
        let translations: [String: TranslatedBlock]
        if let language, TranslationArchive.isRealLanguage(language) {
            let key = TranslationArchive.languageKey(language)
            translations = documentState.translationsByLanguage[key]
                ?? documentState.translationsByLanguage[language.lowercased()]
                ?? [:]
        } else if let firstKey = documentState.translationsByLanguage.keys.sorted().first,
                  let firstTranslations = documentState.translationsByLanguage[firstKey] {
            translations = firstTranslations
        } else {
            translations = [:]
        }

        let lines = documentState.blocks.map { block -> String in
            if block.kind == .empty {
                return ""
            }
            if let translated = translations[block.id]?.text {
                return translated
            }
            return block.spans.map(\.text).joined()
        }

        return lines.joined(separator: "\n\n")
    }
}
