import AppKit
import CryptoKit
import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Document import service")
struct DocumentImportServiceTests {
    @Test("copies TXT into the project store and builds document state")
    func importsTextWithoutMutatingSource() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        let original = "First paragraph\n\nSecond paragraph with śrī."
        try original.write(to: source, atomically: true, encoding: .utf8)
        let project = root.appendingPathComponent("project", isDirectory: true)

        let result = try DocumentImportService.importDocument(from: source, to: project)

        #expect(result.sourceKind == .document)
        #expect(result.originalFileName == "source.txt")
        #expect(result.importedFileURL != source)
        #expect(FileManager.default.fileExists(atPath: result.importedFileURL.path))
        #expect(try String(contentsOf: source, encoding: .utf8) == original)
        #expect(result.documentState.format == .txt)
        #expect(result.documentState.blocks.count == 3)
        #expect(result.documentState.blocks[1].kind == .empty)
        #expect(result.documentState.originalAsset.sha256 == result.sha256)
        #expect(result.sha256 == SHA256.hash(data: Data(original.utf8)).map { String(format: "%02x", $0) }.joined())
    }

    @Test("imports the synthetic DOCX and records its copied asset hash")
    func importsDOCXFixture() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = fixtureURL()
        let project = root.appendingPathComponent("project", isDirectory: true)

        let result = try DocumentImportService.importDocument(from: source, to: project)

        #expect(result.sourceKind == .document)
        #expect(result.documentState.format == .docx)
        #expect(result.documentState.originalAsset.originalFileName == "synthetic-document.docx")
        #expect(result.documentState.blocks.isEmpty == false)
        #expect(result.documentState.originalAsset.sha256 == result.sha256)
        #expect(result.importedFileURL.path.contains("/source/"))
    }

    @Test("does not silently accept macro or unsupported rich document formats")
    func rejectsUnsafeDocumentFormats() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let macro = root.appendingPathComponent("book.docm")
        try Data("not a package".utf8).write(to: macro)
        #expect(throws: SourceClassifierError.macroDocumentsUnsupported) {
            _ = try DocumentImportService.importDocument(from: macro, to: root.appendingPathComponent("macro-project"))
        }

        let pdf = root.appendingPathComponent("book.pdf")
        try Data("not a pdf".utf8).write(to: pdf)
        #expect(throws: DocumentImportServiceError.pdfParsingFailed("Could not parse PDF format.")) {
            _ = try DocumentImportService.importDocument(from: pdf, to: root.appendingPathComponent("pdf-project"))
        }
    }
    @Test("imports RTF preserving explicit foreground color and default runs as nil")
    func importsRTFWithColors() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rtfURL = root.appendingPathComponent("colored.rtf")

        let attr = NSMutableAttributedString(string: "Default text and ")
        attr.append(NSAttributedString(string: "red placeholder", attributes: [.foregroundColor: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)]))
        attr.append(NSAttributedString(string: "."))
        let rtfData = try attr.data(from: NSRange(location: 0, length: attr.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        try rtfData.write(to: rtfURL)

        let project = root.appendingPathComponent("project", isDirectory: true)
        let result = try DocumentImportService.importDocument(from: rtfURL, to: project)
        #expect(result.documentState.format == .rtf)
        #expect(!result.documentState.blocks.isEmpty)
        let block = result.documentState.blocks[0]
        #expect(block.spans.contains { $0.text.contains("Default text and") && $0.foregroundColorHex == nil })
        #expect(block.spans.contains { $0.text.contains("red placeholder") && $0.foregroundColorHex == "FF0000" })
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScript-DocumentImport-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/synthetic-document.docx")
    }
}
