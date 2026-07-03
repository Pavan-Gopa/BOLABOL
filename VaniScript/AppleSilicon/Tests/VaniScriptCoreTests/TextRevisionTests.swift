import Testing
@testable import VaniScriptCore

@Suite("Review text revision")
struct TextRevisionTests {
    @Test("edits inside the selected timed cue instead of the first duplicate")
    func editsSelectedTimedCue() {
        let content = "[09:55] Mayapur is sacred.\n\n[10:04] Mayapur is here."

        let result = TextSnippetRevision.replaceSelectedText(
            in: content,
            selectedText: "Mayapur",
            replacementText: "Mayapur Dham",
            contextText: "Mayapur is here."
        )

        #expect(result.changed)
        #expect(result.text == "[09:55] Mayapur is sacred.\n\n[10:04] Mayapur Dham is here.")
    }

    @Test("preserves a timestamp when replacing a full timed line body")
    func preservesTimestampForFullTimedLine() {
        let content = "[00:32] И часть подготовки к празднику заключалась в небольшом строительстве."

        let result = TextSnippetRevision.replaceSelectedText(
            in: content,
            selectedText: "И часть подготовки к празднику заключалась в небольшом строительстве.",
            replacementText: "Итак, однажды Бхавананда отвечал за строительство здесь, в Майяпуре.",
            contextText: "И часть подготовки к празднику заключалась в небольшом строительстве."
        )

        #expect(result.changed)
        #expect(result.text == "[00:32] Итак, однажды Бхавананда отвечал за строительство здесь, в Майяпуре.")
    }
}
