import Testing
@testable import VaniScriptCore

@Suite("Universal AI document export formatter")
struct DocumentExportFormatterTests {
    @Test("sanitizes marked and fenced document output")
    func sanitizesMarkedDocumentOutput() {
        let raw = """
        Here is the document:
        ```markdown
        <<<DOCUMENT>>>
        # Title

        Body
        <<<END>>>
        ```
        """

        let sanitized = DocumentExportFormatter.sanitizeDocumentExportOutput(raw)

        #expect(sanitized == "# Title\n\nBody")
    }

    @Test("splits markdown on block boundaries")
    func splitsMarkdownInput() {
        let text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."

        let parts = DocumentExportFormatter.splitDocumentExportInput(
            text,
            format: .markdown,
            maxChars: 24
        )

        #expect(parts == ["First paragraph.", "Second paragraph.", "Third paragraph."])
    }

    @Test("combines and renumbers SRT parts")
    func combinesSRTParts() {
        let combined = DocumentExportFormatter.combineDocumentExportParts([
            "4\n00:00:00,000 --> 00:00:01,000\nHello",
            "9\n00:00:01,000 --> 00:00:02,000\nWorld",
        ], format: .srt)

        #expect(combined.contains("1\n00:00:00,000 --> 00:00:01,000\nHello"))
        #expect(combined.contains("2\n00:00:01,000 --> 00:00:02,000\nWorld"))
    }

    @Test("combines local markdown parts into one shell")
    func combinesLocalMarkdownParts() {
        let source = """
        # Transcript

        **Date**: 2026-05-25

        ## Contents

        1. Old

        ## First Topic

        Original body.
        """
        let combined = DocumentExportFormatter.combineLocalMarkdownParts(
            parts: ["# Ignored\n\n**Date**: duplicate\n\n## First Topic\n\nBody one.", "## Second Topic\n\nBody two."],
            sourceDocument: source,
            targetLang: "English"
        )

        #expect(combined.hasPrefix("# Transcript"))
        #expect(combined.contains("**Date**: 2026-05-25"))
        #expect(combined.contains("## Contents"))
        #expect(combined.contains("1. First Topic"))
        #expect(combined.contains("2. Second Topic"))
        #expect(!combined.contains("duplicate"))
    }
}
