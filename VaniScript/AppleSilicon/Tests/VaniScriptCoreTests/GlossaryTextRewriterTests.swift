import Testing
@testable import VaniScriptCore

@Suite("Glossary text rewriter")
struct GlossaryTextRewriterTests {
    @Test("replaces source variants without touching embedded words")
    func replacesSourceVariants() {
        let entry = GlossaryEntry(
            id: "g1",
            variants: ["Jipatake Maharaj", "Jay Pataka"],
            source: "Jayapataka Maharaja",
            translation: "Джаяпатака Махарадж",
            category: "Teachers",
            translations: ["Russian": "Джаяпатака Махарадж"],
            remember: true,
            createdAt: "",
            updatedAt: ""
        )

        let result = GlossaryTextRewriter.apply(
            to: "Jipatake Maharaj came. Jay Pataka spoke. NotJay Pataka stays.",
            entries: [entry],
            target: .source
        )

        #expect(result.text == "Jayapataka Maharaja came. Jayapataka Maharaja spoke. NotJay Pataka stays.")
        #expect(result.count == 2)
    }

    @Test("replaces translated variants")
    func replacesTranslatedVariants() {
        let entry = GlossaryEntry(
            id: "g2",
            variants: ["Джай Патака Махарадж"],
            source: "Jayapataka Maharaja",
            translation: "Джаяпатака Махарадж",
            category: "Teachers",
            translations: ["Russian": "Джаяпатака Махарадж"],
            remember: true,
            createdAt: "",
            updatedAt: ""
        )

        let result = GlossaryTextRewriter.apply(
            to: "Джай Патака Махарадж сказал.",
            entries: [entry],
            target: .translation
        )

        #expect(result.text == "Джаяпатака Махарадж сказал.")
        #expect(result.count == 1)
    }

    @Test("normalizes current Krishna variants to glossary source form")
    func normalizesKrishnaVariants() throws {
        let entry = try #require(AppSettings.defaults.glossary.first { $0.source == "Kṛṣṇa" })

        let result = GlossaryTextRewriter.apply(
            to: "that the benedictions being paid to Krishna were fitting.",
            entries: [entry],
            target: .source
        )

        #expect(result.text == "that the benedictions being paid to Kṛṣṇa were fitting.")
        #expect(result.count == 1)
    }
}
