import NativeBlaboomCore
import Testing

@Suite("Glossary text rewriter")
struct GlossaryTextRewriterTests {
    @Test("replaces source variants without touching embedded words")
    func replacesSourceVariants() {
        let entry = glossaryEntry(
            variants: ["Jipatake Maharaj", "Jay Pataka"],
            source: "Jayapataka Maharaja",
            translation: "Джаяпатака Махарадж"
        )

        let result = GlossaryTextRewriter.apply(
            to: "Jipatake Maharaj came. Jay Pataka spoke. NotJay Pataka stays.",
            entries: [entry],
            target: .source
        )

        #expect(result.text == "Jayapataka Maharaja came. Jayapataka Maharaja spoke. NotJay Pataka stays.")
        #expect(result.count == 2)
    }

    @Test("replaces longer variants before shorter variants")
    func replacesLongerVariantsFirst() {
        let entry = glossaryEntry(
            variants: ["New York", "York"],
            source: "NYC",
            translation: "Нью-Йорк"
        )

        let result = GlossaryTextRewriter.apply(
            to: "New York met York.",
            entries: [entry],
            target: .source
        )

        #expect(result.text == "NYC met NYC.")
        #expect(result.count == 2)
    }

    @Test("uses unicode word boundaries")
    func usesUnicodeWordBoundaries() {
        let entry = glossaryEntry(
            variants: ["Krishna"],
            source: "Kṛṣṇa",
            translation: "Кришна"
        )

        let result = GlossaryTextRewriter.apply(
            to: "Krishna spoke. NotKrishna stays. Krishna2 stays. Krishna-bhakti changes.",
            entries: [entry],
            target: .source
        )

        #expect(result.text == "Kṛṣṇa spoke. NotKrishna stays. Krishna2 stays. Kṛṣṇa-bhakti changes.")
        #expect(result.count == 2)
    }

    @Test("replaces translation target using variants and source")
    func replacesTranslationTargetUsingVariantsAndSource() {
        let entry = glossaryEntry(
            variants: ["Джай Патака Махарадж"],
            source: "Jayapataka Maharaja",
            translation: "Джаяпатака Махарадж"
        )

        let result = GlossaryTextRewriter.apply(
            to: "Jayapataka Maharaja and Джай Патака Махарадж arrived.",
            entries: [entry],
            target: .translation
        )

        #expect(result.text == "Джаяпатака Махарадж and Джаяпатака Махарадж arrived.")
        #expect(result.count == 2)
    }

    @Test("uses requested translation language when present")
    func usesRequestedTranslationLanguageWhenPresent() {
        var entry = glossaryEntry(
            variants: ["Srila Prabupada"],
            source: "Śrīla Prabhupāda",
            translation: "Шрила Прабхупада"
        )
        entry.translations["German"] = "Srila Prabhupada (Deutsch)"

        let result = GlossaryTextRewriter.apply(
            to: "Srila Prabupada arrived.",
            entries: [entry],
            target: .translation,
            translationLanguage: "German"
        )

        #expect(result.text == "Srila Prabhupada (Deutsch) arrived.")
        #expect(result.count == 1)
    }

    @Test("does not apply fuzzy corrections")
    func doesNotApplyFuzzyCorrections() {
        let entry = glossaryEntry(
            variants: ["Krishna"],
            source: "Kṛṣṇa",
            translation: "Кришна"
        )

        let result = GlossaryTextRewriter.apply(
            to: "Krisna stayed untouched.",
            entries: [entry],
            target: .source
        )

        #expect(result.text == "Krisna stayed untouched.")
        #expect(result.count == 0)
    }

    private func glossaryEntry(
        variants: [String],
        source: String,
        translation: String
    ) -> GlossaryEntry {
        GlossaryEntry(
            id: "g1",
            variants: variants,
            source: source,
            translation: translation,
            category: "Test",
            translations: ["Russian": translation],
            remember: true,
            createdAt: "2026-07-01T00:00:00.000Z",
            updatedAt: "2026-07-01T00:00:00.000Z"
        )
    }
}
