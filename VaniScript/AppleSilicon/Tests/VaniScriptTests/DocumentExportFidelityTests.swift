import AppKit
import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

/// S18 / PRD §16: DOCX editor run-property overlay (including explicit trait
/// OFF via `w:val="0"`) and PDF super/sub/smallCaps attributes after edits.
@Suite("Document export fidelity (S18)")
struct DocumentExportFidelityTests {
    // MARK: - EditorRunPropertyOverlay (unit)

    @Test("explicit bold OFF writes w:b w:val=0 over inherited bold source rPr")
    func explicitBoldOffWritesValZero() {
        let rPr = XMLElement(name: "w:rPr")
        let boldOn = XMLElement(name: "w:b")
        rPr.addChild(boldOn)

        let span = RichTextSpan(
            id: "s1",
            text: "plain again",
            traits: [],
            editorOverrides: EditorInlineOverrides(traitOverrides: [.bold: false])
        )
        EditorRunPropertyOverlay.apply(to: rPr, span: span)

        let bold = rPrChildren(rPr, localName: "b")
        #expect(bold.count == 1)
        let val = bold[0].attribute(forName: "w:val")?.stringValue
            ?? bold[0].attribute(forName: "val")?.stringValue
        #expect(val == "0", "user-disabled bold must export as explicit OFF, not missing element")
    }

    @Test("explicit bold ON adds w:b when source rPr has no bold")
    func explicitBoldOnAddsElement() {
        let rPr = XMLElement(name: "w:rPr")
        let span = RichTextSpan(
            id: "s1",
            text: "now bold",
            traits: [.bold]
        )
        EditorRunPropertyOverlay.apply(to: rPr, span: span)

        let bold = rPrChildren(rPr, localName: "b")
        #expect(bold.count == 1)
        let val = bold[0].attribute(forName: "w:val")?.stringValue
        #expect(val == nil || val == "1" || val == "true", "on-state bold should not carry val=0")
    }

    @Test("red foreground color still overlays onto rPr")
    func colorOverlaySurvives() {
        let rPr = XMLElement(name: "w:rPr")
        let span = RichTextSpan(
            id: "s1",
            text: "[NAME]",
            foregroundColorHex: "FF0000"
        )
        EditorRunPropertyOverlay.apply(to: rPr, span: span)
        let colors = rPrChildren(rPr, localName: "color")
        #expect(colors.count == 1)
        let val = colors[0].attribute(forName: "w:val")?.stringValue
            ?? colors[0].attribute(forName: "val")?.stringValue
        #expect(val == "FF0000")
    }

    @Test("clearsForegroundColor detaches w:color")
    func clearsForegroundColorRemovesElement() {
        let rPr = XMLElement(name: "w:rPr")
        let color = XMLElement(name: "w:color")
        color.addAttribute(XMLNode.attribute(withName: "w:val", stringValue: "FF0000") as! XMLNode)
        rPr.addChild(color)

        let span = RichTextSpan(
            id: "s1",
            text: "no color",
            editorOverrides: EditorInlineOverrides(clearsForegroundColor: true)
        )
        EditorRunPropertyOverlay.apply(to: rPr, span: span)
        #expect(rPrChildren(rPr, localName: "color").isEmpty)
    }

    @Test("superscript writes w:vertAlign superscript; subscript is mutually exclusive")
    func superscriptVertAlign() {
        let rPr = XMLElement(name: "w:rPr")
        let span = RichTextSpan(
            id: "s1",
            text: "x2",
            traits: [.superscript, .subscriptText] // superscript wins
        )
        EditorRunPropertyOverlay.apply(to: rPr, span: span)
        let verts = rPrChildren(rPr, localName: "vertAlign")
        #expect(verts.count == 1)
        let val = verts[0].attribute(forName: "w:val")?.stringValue
            ?? verts[0].attribute(forName: "val")?.stringValue
        #expect(val == "superscript")
    }

    @Test("explicit superscript OFF clears w:vertAlign")
    func superscriptOffClearsVertAlign() {
        let rPr = XMLElement(name: "w:rPr")
        let vert = XMLElement(name: "w:vertAlign")
        vert.addAttribute(XMLNode.attribute(withName: "w:val", stringValue: "superscript") as! XMLNode)
        rPr.addChild(vert)

        let span = RichTextSpan(
            id: "s1",
            text: "base",
            traits: [],
            editorOverrides: EditorInlineOverrides(traitOverrides: [.superscript: false])
        )
        EditorRunPropertyOverlay.apply(to: rPr, span: span)
        #expect(rPrChildren(rPr, localName: "vertAlign").isEmpty)
    }

    @Test("smallCaps toggle on writes w:smallCaps")
    func smallCapsOn() {
        let rPr = XMLElement(name: "w:rPr")
        let span = RichTextSpan(id: "s1", text: "Title", traits: [.smallCaps])
        EditorRunPropertyOverlay.apply(to: rPr, span: span)
        #expect(rPrChildren(rPr, localName: "smallCaps").count == 1)
    }

    // MARK: - PDF attributes

    @Test("explicit italic, underline, and strikethrough OFF write the OOXML off forms over inherited source rPr")
    func explicitItalicUnderlineStrikeOffWriteOffForms() {
        let rPr = XMLElement(name: "w:rPr")
        let italicOn = XMLElement(name: "w:i")
        rPr.addChild(italicOn)
        let underlineOn = XMLElement(name: "w:u")
        underlineOn.addAttribute(XMLNode.attribute(withName: "w:val", stringValue: "single") as! XMLNode)
        rPr.addChild(underlineOn)
        let strikeOn = XMLElement(name: "w:strike")
        rPr.addChild(strikeOn)

        let span = RichTextSpan(
            id: "s1",
            text: "plain again",
            traits: [],
            editorOverrides: EditorInlineOverrides(traitOverrides: [
                .italic: false,
                .underline: false,
                .strikethrough: false,
            ])
        )
        EditorRunPropertyOverlay.apply(to: rPr, span: span)

        let italic = rPrChildren(rPr, localName: "i")
        #expect(italic.count == 1)
        #expect(
            (italic[0].attribute(forName: "w:val")?.stringValue ?? italic[0].attribute(forName: "val")?.stringValue) == "0",
            "user-disabled italic must export as w:i w:val=\"0\", not a missing element"
        )

        let underline = rPrChildren(rPr, localName: "u")
        #expect(underline.count == 1)
        #expect(
            (underline[0].attribute(forName: "w:val")?.stringValue ?? underline[0].attribute(forName: "val")?.stringValue) == "none",
            "user-disabled underline must export as w:u w:val=\"none\""
        )

        let strike = rPrChildren(rPr, localName: "strike")
        #expect(strike.count == 1)
        #expect(
            (strike[0].attribute(forName: "w:val")?.stringValue ?? strike[0].attribute(forName: "val")?.stringValue) == "0",
            "user-disabled strikethrough must export as w:strike w:val=\"0\""
        )
    }

    @Test("PDF attributes: superscript uses raised baseline and smaller font")
    func pdfSuperscriptAttributes() {
        let style = NSMutableParagraphStyle()
        let span = RichTextSpan(id: "s1", text: "2", traits: [.superscript])
        let attrs = DocumentExportWriters.pdfSpanAttributes(for: span, paragraphStyle: style)
        let offset = numericOffset(attrs[.baselineOffset])
        #expect(offset != nil && offset! > 0)
        let font = attrs[.font] as? NSFont
        #expect(font != nil && font!.pointSize < 12)
    }

    @Test("PDF attributes: subscript uses lowered baseline")
    func pdfSubscriptAttributes() {
        let style = NSMutableParagraphStyle()
        let span = RichTextSpan(id: "s1", text: "i", traits: [.subscriptText])
        let attrs = DocumentExportWriters.pdfSpanAttributes(for: span, paragraphStyle: style)
        let offset = numericOffset(attrs[.baselineOffset])
        #expect(offset != nil && offset! < 0)
    }

    @Test("PDF attributes: editor override turns bold off even if traits still list bold")
    func pdfOverrideTurnsBoldOff() {
        let style = NSMutableParagraphStyle()
        // traits still contain bold, but override forces off — effectiveTraits must drop it
        let span = RichTextSpan(
            id: "s1",
            text: "x",
            traits: [.bold],
            editorOverrides: EditorInlineOverrides(traitOverrides: [.bold: false])
        )
        let attrs = DocumentExportWriters.pdfSpanAttributes(for: span, paragraphStyle: style)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(!font!.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("PDF attributes: smallCaps embeds the small-caps letterform feature settings in the font")
    func pdfSmallCapsFeatureSettings() {
        let style = NSMutableParagraphStyle()
        let span = RichTextSpan(id: "s1", text: "Title", traits: [.smallCaps])
        let attrs = DocumentExportWriters.pdfSpanAttributes(for: span, paragraphStyle: style)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)

        let rawSettings = font!.fontDescriptor.fontAttributes[.featureSettings]
        let featureSettings = rawSettings as? [[NSFontDescriptor.FeatureKey: Int]]
        #expect(featureSettings != nil, "smallCaps span must embed AAT feature settings in the exported font")
        let hasSmallCapsSelector = featureSettings?.contains { feature in
            feature[.typeIdentifier] == 37 && feature[.selectorIdentifier] == 1
        } ?? false
        #expect(hasSmallCapsSelector, "feature settings must include lower-case small caps (type 37 / selector 1)")
    }

    // MARK: - End-to-end DOCX export with fixture

    @Test("DOCX export applies explicit bold OFF on a translated run over bold source")
    func docxExportExplicitBoldOffRoundTrip() throws {
        let fixture = fixtureURL()
        let parsed = try DOCXPackageReader.read(from: fixture)
        // Prefer a source block whose first span is bold if present; otherwise
        // force traits/overrides on whatever first paragraph exists.
        guard let sourceBlock = parsed.blocks.first(where: { !$0.spans.isEmpty }) else {
            Issue.record("fixture has no blocks")
            return
        }

        let translatedSpan = RichTextSpan(
            id: sourceBlock.spans[0].id,
            text: "Не жирный перевод",
            styleKey: sourceBlock.spans[0].styleKey,
            traits: [],
            foregroundColorHex: "FF0000",
            // Force OFF even if the matched source run carries bold.
            editorOverrides: EditorInlineOverrides(traitOverrides: [.bold: false])
        )
        let translated = TranslatedBlock(
            id: sourceBlock.id,
            sourceBlockID: sourceBlock.id,
            text: translatedSpan.text,
            spans: [translatedSpan],
            sourceHash: sourceBlock.sourceHash,
            reviewDisposition: .manuallyApproved
        )
        let hash = try DocumentImportService.computeSHA256(for: fixture)
        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(
                key: "sourceFile",
                originalFileName: "synthetic-document.docx",
                role: .originalSource,
                format: "docx",
                sha256: hash
            ),
            metadata: parsed.metadata,
            preflight: parsed.preflight,
            blocks: parsed.blocks,
            chunks: [],
            translationsByLanguage: ["russian": [sourceBlock.id: translated]],
            profile: .default
        )

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("s18-bold-off-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: destination) }

        _ = try DocumentExportWriters.writeDOCX(
            sourceDocxURL: fixture,
            documentState: documentState,
            language: "Russian",
            to: destination
        )

        // Inspect the exported document.xml run properties for the translated text.
        let xml = try documentXML(fromDOCX: destination)
        #expect(xml.contains("Не жирный перевод"))
        #expect(xml.contains("w:val=\"FF0000\"") || xml.contains("w:val=\"ff0000\"") || xml.contains("val=\"FF0000\""))
        // Explicit OFF form must appear somewhere in rPr near the rewrite.
        #expect(
            xml.contains("w:val=\"0\"") || xml.contains("val=\"0\""),
            "exported DOCX must carry an explicit trait-off marker (w:val=0)"
        )
    }

    // MARK: - Helpers

    private func rPrChildren(_ rPr: XMLElement, localName: String) -> [XMLElement] {
        (rPr.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == localName }
    }

    private func numericOffset(_ value: Any?) -> Double? {
        if let cg = value as? CGFloat { return Double(cg) }
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let f = value as? Float { return Double(f) }
        return nil
    }

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/synthetic-document.docx")
    }

    private func documentXML(fromDOCX url: URL) throws -> String {
        let fm = FileManager.default
        let extractDir = fm.temporaryDirectory.appendingPathComponent("s18-x-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: extractDir) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", url.path, "-d", extractDir.path]
        try proc.run()
        proc.waitUntilExit()
        #expect(proc.terminationStatus == 0)

        let docURL = extractDir.appendingPathComponent("word/document.xml")
        return try String(contentsOf: docURL, encoding: .utf8)
    }
}
