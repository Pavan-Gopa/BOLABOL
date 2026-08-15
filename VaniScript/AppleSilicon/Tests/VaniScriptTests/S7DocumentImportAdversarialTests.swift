import Foundation
import Testing
@testable import VaniScript

@Suite("S7 adversarial document import")
struct S7DocumentImportAdversarialTests {
    @Test("CRLF and bare CR normalize to stable line blocks without losing empty lines")
    func newlineNormalization() throws {
        let root = makeTemp()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("mixed.txt")
        try Data("one\r\n\r\ntwo\rthree".utf8).write(to: source)

        let result = try DocumentImportService.importDocument(from: source, to: root.appendingPathComponent("project"))
        #expect(result.documentState.blocks.map { $0.spans.map(\.text).joined() } == ["one", "", "two", "three"])
        #expect(result.documentState.blocks.map(\.kind) == [.paragraph, .empty, .paragraph, .paragraph])
        #expect(result.documentState.blocks.map { $0.location.paragraphOrdinal } == [0, 1, 2, 3])
    }

    @Test("text import canonicalizes decomposed Unicode to NFC before hashing individual blocks")
    func nfcNormalization() throws {
        let root = makeTemp()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("unicode.txt")
        let decomposed = "Śrī Café".decomposedStringWithCanonicalMapping
        try decomposed.write(to: source, atomically: true, encoding: .utf8)

        let result = try DocumentImportService.importDocument(from: source, to: root.appendingPathComponent("project"))
        let imported = result.documentState.blocks[0].spans.map(\.text).joined()
        #expect(imported == "Śrī Café".precomposedStringWithCanonicalMapping)
        #expect(imported == imported.precomposedStringWithCanonicalMapping)
    }

    @Test("Markdown classifies headings, quotes, bullets, numbered items, blanks, and prose")
    func markdownKinds() throws {
        let root = makeTemp()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("book.md")
        let text = "# Heading\n> Quoted line\n- bullet\n* star\n1. numbered\n2) alternate\n\nplain"
        try text.write(to: source, atomically: true, encoding: .utf8)

        let result = try DocumentImportService.importDocument(from: source, to: root.appendingPathComponent("project"))
        #expect(result.documentState.format == .markdown)
        #expect(result.documentState.blocks.map(\.kind) == [
            .heading, .quote, .listItem, .listItem, .listItem, .listItem, .empty, .paragraph
        ])
    }

    @Test("an empty UTF-8 document still produces one structural empty block")
    func emptyTextProducesOneBlock() throws {
        let root = makeTemp()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("empty.txt")
        try Data().write(to: source)

        let result = try DocumentImportService.importDocument(from: source, to: root.appendingPathComponent("project"))
        #expect(result.documentState.blocks.count == 1)
        #expect(result.documentState.blocks[0].kind == .empty)
        #expect(result.documentState.blocks[0].spans.isEmpty)
    }

    @Test("invalid UTF-8 fails closed and removes the copied project asset")
    func invalidUTF8CleansDestination() throws {
        let root = makeTemp()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("invalid.txt")
        try Data([0xFF, 0xFE, 0xFF]).write(to: source)
        let project = root.appendingPathComponent("project")

        #expect(throws: DocumentImportServiceError.invalidTextEncoding("invalid.txt")) {
            _ = try DocumentImportService.importDocument(from: source, to: project)
        }
        let sourceDir = project.appendingPathComponent("source")
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: sourceDir.path)) ?? []
        #expect(contents.isEmpty)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("importing same filename twice never overwrites the first private copy")
    func duplicateFilenameGetsUniqueCopy() throws {
        let root = makeTemp()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("same.txt")
        try "first".write(to: source, atomically: true, encoding: .utf8)
        let project = root.appendingPathComponent("project")
        let first = try DocumentImportService.importDocument(from: source, to: project)

        try "second".write(to: source, atomically: true, encoding: .utf8)
        let second = try DocumentImportService.importDocument(from: source, to: project)

        #expect(first.importedFileURL != second.importedFileURL)
        #expect(try String(contentsOf: first.importedFileURL, encoding: .utf8) == "first")
        #expect(try String(contentsOf: second.importedFileURL, encoding: .utf8) == "second")
    }

    @Test("missing paths and directories are distinguished")
    func missingAndDirectoryErrors() throws {
        let root = makeTemp()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("missing.txt")
        #expect(throws: DocumentImportServiceError.sourceNotFound) {
            _ = try DocumentImportService.importDocument(from: missing, to: root.appendingPathComponent("p1"))
        }

        let directory = root.appendingPathComponent("folder.txt", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(throws: DocumentImportServiceError.sourceIsNotAFile) {
            _ = try DocumentImportService.importDocument(from: directory, to: root.appendingPathComponent("p2"))
        }
    }

    @Test("block IDs are deterministic for same filename and normalized content")
    func deterministicBlockIDs() throws {
        let root = makeTemp()
        defer { try? FileManager.default.removeItem(at: root) }
        let one = root.appendingPathComponent("a/same.txt")
        let two = root.appendingPathComponent("b/same.txt")
        try FileManager.default.createDirectory(at: one.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: two.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "A\nB".write(to: one, atomically: true, encoding: .utf8)
        try "A\r\nB".write(to: two, atomically: true, encoding: .utf8)

        let first = try DocumentImportService.importDocument(from: one, to: root.appendingPathComponent("p1"))
        let second = try DocumentImportService.importDocument(from: two, to: root.appendingPathComponent("p2"))
        #expect(first.documentState.blocks.map(\.id) == second.documentState.blocks.map(\.id))
        #expect(first.documentState.blocks.map(\.sourceHash) == second.documentState.blocks.map(\.sourceHash))
    }

    private func makeTemp() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VaniScript-S7-Import-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
