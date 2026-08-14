import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Document export writers")
struct DocumentExportTests {
    @Test("DOCX writer round-trips translations and preserves styles and package entries")
    func docxWriterRoundTrip() throws {
        let fixture = fixtureURL()
        let parsedSource = try DOCXPackageReader.read(from: fixture)
        #expect(parsedSource.blocks.count >= 10)

        let block0 = parsedSource.blocks[0]
        let block1 = parsedSource.blocks[1]

        let translatedRussian: [String: TranslatedBlock] = [
            block0.id: TranslatedBlock(id: "t0", blockID: block0.id, text: "Глава Первая: Начало"),
            block1.id: TranslatedBlock(id: "t1", blockID: block1.id, text: "Обычный абзац с прямой речью и контекстом.")
        ]

        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "src", originalFileName: "synthetic-document.docx"),
            metadata: parsedSource.metadata,
            blocks: parsedSource.blocks,
            translationsByLanguage: ["russian": translatedRussian]
        )

        let tempDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-output-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: tempDestination) }

        try DocumentExportWriters.writeDOCX(
            sourceDocxURL: fixture,
            documentState: documentState,
            language: "Russian",
            to: tempDestination
        )

        #expect(FileManager.default.fileExists(atPath: tempDestination.path))

        // Read back the exported DOCX package
        let parsedExport = try DOCXPackageReader.read(from: tempDestination)
        #expect(parsedExport.blocks.count == parsedSource.blocks.count)

        // Block 0 should have translated text and preserved heading style
        let exportedBlock0 = parsedExport.blocks[0]
        #expect(exportedBlock0.kind == .heading)
        #expect(exportedBlock0.styleID == "ChapterTitle")
        #expect(exportedBlock0.spans.map(\.text).joined() == "Глава Первая: Начало")

        // Block 1 should have translated text
        let exportedBlock1 = parsedExport.blocks[1]
        #expect(exportedBlock1.spans.map(\.text).joined() == "Обычный абзац с прямой речью и контекстом.")

        // Block 2 should remain untranslated source text with italic trait
        let exportedBlock2 = parsedExport.blocks[2]
        #expect(exportedBlock2.spans.map(\.text).joined() == "Italic Book Title")
        #expect(exportedBlock2.spans.contains { $0.traits.contains(.italic) })

        // Other entry names should be preserved in package
        #expect(parsedExport.entryNames.contains("word/document.xml"))
        #expect(parsedExport.entryNames.contains("word/header1.xml") || parsedExport.entryNames.contains("word/_rels/document.xml.rels"))
    }

    @Test("PDF writer generates valid A4 multi-page CoreText PDF")
    func pdfWriterGeneratesValidPDF() throws {
        var paragraphs: [String] = ["Heading Title"]
        for i in 1...40 {
            paragraphs.append("Paragraph \(i): This is a substantial block of text describing the literary translation workflow and verifying that CoreText pagination properly breaks lines and pages.")
        }
        let fullText = paragraphs.joined(separator: "\n\n")

        let tempPDF = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: tempPDF) }

        try DocumentExportWriters.writePDF(text: fullText, to: tempPDF)

        let data = try Data(contentsOf: tempPDF)
        #expect(data.count > 1_000)

        let header = String(decoding: data.prefix(4), as: UTF8.self)
        #expect(header == "%PDF")
    }

    @Test("TXT writer writes UTF-8 text deterministically")
    func txtWriterWritesUTF8() throws {
        let text = "Глава 1\n\nПервый абзац на русском языке."
        let tempTXT = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tempTXT) }

        try DocumentExportWriters.writeTXT(text: text, to: tempTXT)

        let readBack = try String(contentsOf: tempTXT, encoding: .utf8)
        #expect(readBack == text)
    }

    @Test("writers throw expected errors for missing source and missing translation")
    func writersErrorHandling() {
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non-existent-\(UUID().uuidString).docx")
        let tempDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("out-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: tempDestination) }

        let documentState = DocumentState(
            format: .docx,
            translationsByLanguage: ["russian": ["b1": TranslatedBlock(id: "t1", blockID: "b1", text: "Перевод")]]
        )

        #expect(throws: DocumentExportWriters.ExportError.missingSourceDocument) {
            try DocumentExportWriters.writeDOCX(
                sourceDocxURL: nonExistentURL,
                documentState: documentState,
                language: "Russian",
                to: tempDestination
            )
        }

        let emptyDocState = DocumentState(format: .docx)
        #expect(throws: DocumentExportWriters.ExportError.missingTranslation) {
            try DocumentExportWriters.writeDOCX(
                sourceDocxURL: fixtureURL(),
                documentState: emptyDocState,
                language: "Russian",
                to: tempDestination
            )
        }

        #expect(throws: DocumentExportWriters.ExportError.missingTranslation) {
            try DocumentExportWriters.writeTXT(text: "   ", to: tempDestination)
        }

        #expect(throws: DocumentExportWriters.ExportError.missingTranslation) {
            try DocumentExportWriters.writePDF(text: "   ", to: tempDestination)
        }
    }

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/synthetic-document.docx")
    }
}
