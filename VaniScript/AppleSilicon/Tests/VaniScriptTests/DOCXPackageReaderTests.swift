import Foundation
import Testing
@testable import VaniScript

@Suite("DOCX package reader")
struct DOCXPackageReaderTests {
    @Test("walks synthetic paragraphs and preserves paragraph/run structure")
    func readsSyntheticFixture() throws {
        let fixture = fixtureURL()
        let parsed = try DOCXPackageReader.read(from: fixture)

        #expect(parsed.blocks.count >= 10)
        #expect(parsed.blocks.first?.kind == .heading)
        #expect(parsed.blocks.first?.styleID == "ChapterTitle")
        #expect(parsed.blocks.first?.paragraphPropertiesFingerprint.isEmpty == false)
        #expect(parsed.blocks.contains { $0.spans.contains { $0.traits.contains(.bold) } })
        #expect(parsed.blocks.contains { $0.spans.contains { $0.traits.contains(.italic) } })
        #expect(parsed.blocks.contains { $0.spans.contains { $0.text.contains("śrī") } })
        #expect(parsed.entryNames.contains("word/document.xml"))
        #expect(!parsed.sourceHash.isEmpty)
    }

    @Test("enforces package limits before parsing XML")
    func rejectsOversizedPackage() {
        let fixture = fixtureURL()
        let limits = DOCXPackageReader.Limits(maxPackageBytes: 10, maxEntryCount: 10, maxEntryBytes: 10)
        #expect(throws: DOCXPackageReader.DOCXPackageReaderError.self) {
            _ = try DOCXPackageReader.read(from: fixture, limits: limits)
        }
    }
    @Test("parses direct w:color in DOCX runs and preserves default runs as nil")
    func parsesColoredRuns() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docx-color-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("word"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """
        try contentTypes.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
        try rels.write(to: tempDir.appendingPathComponent("_rels/.rels"), atomically: true, encoding: .utf8)

        let docXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:body>
                <w:p>
                    <w:r>
                        <w:rPr/>
                        <w:t>Black default text and </w:t>
                    </w:r>
                    <w:r>
                        <w:rPr>
                            <w:color w:val="FF0000"/>
                        </w:rPr>
                        <w:t>red placeholder</w:t>
                    </w:r>
                </w:p>
            </w:body>
        </w:document>
        """
        try docXML.write(to: tempDir.appendingPathComponent("word/document.xml"), atomically: true, encoding: .utf8)

        let docxURL = tempDir.appendingPathComponent("test.docx")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = tempDir
        proc.arguments = ["-q", "-r", docxURL.path, "[Content_Types].xml", "_rels", "word"]
        try proc.run()
        proc.waitUntilExit()
        #expect(proc.terminationStatus == 0)

        let parsed = try DOCXPackageReader.read(from: docxURL)
        #expect(parsed.blocks.count == 1)
        let block = parsed.blocks[0]
        #expect(block.spans.count == 2)
        #expect(block.spans[0].text == "Black default text and ")
        #expect(block.spans[0].foregroundColorHex == nil)
        #expect(block.spans[1].text == "red placeholder")
        #expect(block.spans[1].foregroundColorHex == "FF0000")
    }

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/synthetic-document.docx")
    }
}
