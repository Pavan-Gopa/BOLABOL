import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import PDFKit
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("PDF document importer")
struct PDFDocumentImporterTests {
    @Test("reads text-layer PDF and reconstructs structured paragraphs and preflight")
    func readsTextLayerPDF() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdfURL = root.appendingPathComponent("sample.pdf")

        let page1 = "CHAPTER I: THE BEGINNING\n\nThis is a reconstructed paragraph from page 1.\nIt wraps onto a second line.\n\nAnother paragraph here."
        let page2 = "CHAPTER II: THE CONTINUATION\n\nPage 2 paragraph with de-hyphen-\nation test.\n\nConcluding remark."
        createTextLayerPDF(url: pdfURL, pages: [page1, page2])

        let state = try PDFDocumentImporter.read(from: pdfURL)

        #expect(state.format == .pdf)
        #expect(state.preflight.pageCount == 2)
        #expect(state.preflight.sectionCount == 2)
        #expect(state.blocks.count >= 4)
        #expect(state.metadata.title == "sample")

        // Heading detection
        #expect(state.blocks.contains(where: { $0.kind == .heading }))
        #expect(state.blocks.contains(where: { $0.kind == .paragraph }))
    }

    @Test("throws scannedPDFNotSupported when PDF has no text layer")
    func throwsScannedPDFError() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdfURL = root.appendingPathComponent("scanned.pdf")

        createScannedPDF(url: pdfURL, pageCount: 3)

        #expect(throws: PDFDocumentImporter.PDFImporterError.scannedPDFNotSupported) {
            _ = try PDFDocumentImporter.read(from: pdfURL)
        }
    }

    @Test("throws fileNotFound when path does not exist")
    func throwsFileNotFound() {
        let missingURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).pdf")
        #expect(throws: PDFDocumentImporter.PDFImporterError.fileNotFound) {
            _ = try PDFDocumentImporter.read(from: missingURL)
        }
    }

    @Test("enforces maxFileBytes and maxPageCount limits")
    func enforcesLimits() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdfURL = root.appendingPathComponent("test.pdf")

        createTextLayerPDF(url: pdfURL, pages: ["Page 1", "Page 2", "Page 3"])

        // Page count limit test
        var limits = PDFDocumentImporter.Limits()
        limits.maxPageCount = 2

        #expect(throws: PDFDocumentImporter.PDFImporterError.pageCountExceedsLimit(count: 3, limit: 2)) {
            _ = try PDFDocumentImporter.read(from: pdfURL, limits: limits)
        }

        // File size limit test
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: pdfURL.path)[.size] as? Int64) ?? 1000
        limits.maxPageCount = 10
        limits.maxFileBytes = fileSize - 10

        #expect(throws: PDFDocumentImporter.PDFImporterError.fileSizeExceedsLimit(size: fileSize, limit: fileSize - 10)) {
            _ = try PDFDocumentImporter.read(from: pdfURL, limits: limits)
        }
    }

    @Test("respects cancellation check during PDF import")
    func respectsCancellation() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdfURL = root.appendingPathComponent("test.pdf")

        createTextLayerPDF(url: pdfURL, pages: ["Page 1", "Page 2"])

        #expect(throws: PDFDocumentImporter.PDFImporterError.cancelled) {
            _ = try PDFDocumentImporter.read(
                from: pdfURL,
                cancellationCheck: { true }
            )
        }
    }
    @Test("reconstructs PDF text layer spans with representable foreground colors")
    func reconstructsColoredPDFSpans() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdfURL = root.appendingPathComponent("colored.pdf")

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else { return }
        var pageBox = mediaBox
        context.beginPage(mediaBox: &pageBox)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = graphicsContext

        let attributed = NSMutableAttributedString()
        attributed.append(NSAttributedString(string: "Default text and ", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black
        ]))
        attributed.append(NSAttributedString(string: "red placeholder", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(srgbRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        ]))
        attributed.draw(in: CGRect(x: 50, y: 50, width: 512, height: 692))
        NSGraphicsContext.current = previous
        context.endPage()
        context.closePDF()

        let state = try PDFDocumentImporter.read(from: pdfURL)
        #expect(!state.blocks.isEmpty)
        let block = state.blocks[0]
        #expect(block.spans.count >= 1)
        #expect(block.spans.contains { $0.foregroundColorHex == "FF0000" })
    }

    // MARK: - Helpers

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScript-PDFImporter-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func createTextLayerPDF(url: URL, pages: [String]) {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }
        for pageText in pages {
            var pageBox = mediaBox
            context.beginPage(mediaBox: &pageBox)
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = graphicsContext
            let str = NSAttributedString(
                string: pageText,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.black
                ]
            )
            str.draw(in: CGRect(x: 50, y: 50, width: 512, height: 692))
            NSGraphicsContext.current = previous
            context.endPage()
        }
        context.closePDF()
    }

    private func createScannedPDF(url: URL, pageCount: Int = 1) {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }
        for _ in 0..<pageCount {
            var pageBox = mediaBox
            context.beginPage(mediaBox: &pageBox)
            context.setFillColor(CGColor(gray: 0.9, alpha: 1.0))
            context.fill(CGRect(x: 100, y: 100, width: 400, height: 500))
            context.endPage()
        }
        context.closePDF()
    }
}
