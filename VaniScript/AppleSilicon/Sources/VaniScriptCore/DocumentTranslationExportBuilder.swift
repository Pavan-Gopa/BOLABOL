import Foundation

public enum DocumentTranslationExportBuilder {
    public static func resolvedTranslationsDictionary(
        documentState: DocumentState,
        language: String? = nil
    ) -> [String: TranslatedBlock] {
        if let language, TranslationArchive.isRealLanguage(language) {
            let key = TranslationArchive.languageKey(language)
            return documentState.translationsByLanguage[key]
                ?? documentState.translationsByLanguage[language.lowercased()]
                ?? [:]
        } else if let firstKey = documentState.translationsByLanguage.keys.sorted().first,
                  let firstTranslations = documentState.translationsByLanguage[firstKey] {
            return firstTranslations
        } else {
            return [:]
        }
    }

    public static func resolvedTranslation(
        for blockID: String,
        in translations: [String: TranslatedBlock],
        chunks: [DocumentChunkPlan] = []
    ) -> String? {
        if let direct = translations[blockID]?.text, TranslationArchive.isUsableTranslationText(direct) {
            return direct
        }

        let allSlices = chunks
            .compactMap(\.blockSlices)
            .flatMap { $0 }
            .filter { $0.blockID == blockID }
            .sorted { $0.startOffset < $1.startOffset }

        if !allSlices.isEmpty {
            let sliceTexts = allSlices.enumerated().compactMap { i, slice -> String? in
                let keyIndex = TranslationArchive.sliceKey(blockID: blockID, sliceIndex: i)
                let keyOffset = TranslationArchive.sliceKey(blockID: blockID, startOffset: slice.startOffset, endOffset: slice.endOffset)
                guard let text = translations[keyIndex]?.text ?? translations[keyOffset]?.text,
                      TranslationArchive.isUsableTranslationText(text)
                else {
                    return nil
                }
                return text
            }
            if sliceTexts.count == allSlices.count {
                let merged = sliceTexts.joined(separator: " ")
                if TranslationArchive.isUsableTranslationText(merged) {
                    return merged
                }
            }
        }

        let prefix = "\(blockID)#slice_"
        let matchedKeys = translations.keys.filter { $0.hasPrefix(prefix) }.sorted()
        if !matchedKeys.isEmpty {
            let texts = matchedKeys.compactMap { key -> String? in
                guard let text = translations[key]?.text, TranslationArchive.isUsableTranslationText(text) else {
                    return nil
                }
                return text
            }
            if !texts.isEmpty && texts.count == matchedKeys.count {
                let merged = texts.joined(separator: " ")
                if TranslationArchive.isUsableTranslationText(merged) {
                    return merged
                }
            }
        }

        return nil
    }

    public static func translatedDocumentText(
        documentState: DocumentState,
        language: String? = nil,
        includeUntranslatedAsOriginal: Bool = false
    ) -> String {
        let translations = resolvedTranslationsDictionary(documentState: documentState, language: language)

        let lines = documentState.blocks.map { block -> String in
            if block.kind == .empty {
                return ""
            }
            if let translated = resolvedTranslation(for: block.id, in: translations, chunks: documentState.chunks) {
                return translated
            }
            if includeUntranslatedAsOriginal {
                return block.spans.map(\.text).joined()
            }
            return ""
        }

        return lines.joined(separator: "\n\n")
    }

    public static func translatedBlocks(
        documentState: DocumentState,
        language: String? = nil
    ) -> [(block: DocumentBlock, translatedText: String)] {
        let translations = resolvedTranslationsDictionary(documentState: documentState, language: language)
        return documentState.blocks.compactMap { block in
            guard block.kind != .empty else { return nil }
            guard let text = resolvedTranslation(for: block.id, in: translations, chunks: documentState.chunks) else {
                return nil
            }
            return (block: block, translatedText: text)
        }
    }
}
