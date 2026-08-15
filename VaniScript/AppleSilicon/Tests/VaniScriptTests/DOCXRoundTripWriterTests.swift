import CryptoKit
import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("DOCX round-trip writer")
struct DOCXRoundTripWriterTests {
    @Test("Round-trip exports translated DOCX, preserves styles, paragraph structure, and XML relationships")
    func roundTripExportsTranslatedDOCXAndPreservesStyles() throws {
        let fixture = fixtureURL()
        let parsedSource = try DOCXPackageReader.read(from: fixture)
        #expect(parsedSource.blocks.count >= 6)

        let block0 = parsedSource.blocks[0]
        let block1 = parsedSource.blocks[1]

        let translatedRussian: [String: TranslatedBlock] = [
            block0.id: TranslatedBlock(
                id: "tr-0",
                sourceBlockID: block0.id,
                text: "Глава Первая: Новое Начало",
                sourceHash: block0.sourceHash,
                reviewDisposition: .manuallyApproved
            ),
            block1.id: TranslatedBlock(
                id: "tr-1",
                sourceBlockID: block1.id,
                text: "Переведённый абзац с сохранённым стилем.",
                sourceHash: block1.sourceHash,
                reviewDisposition: .manuallyApproved
            )
        ]

        let actualHash = try DocumentImportService.computeSHA256(for: fixture)
        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(
                key: "sourceFile",
                originalFileName: "synthetic-document.docx",
                role: .originalSource,
                format: "docx",
                sha256: actualHash
            ),
            metadata: parsedSource.metadata,
            preflight: parsedSource.preflight,
            blocks: parsedSource.blocks,
            chunks: [],
            translationsByLanguage: ["russian": translatedRussian],
            profile: .default
        )

        let tempDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip-output-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: tempDestination) }

        let result = try DocumentExportWriters.writeDOCX(
            sourceDocxURL: fixture,
            documentState: documentState,
            language: "Russian",
            to: tempDestination
        )

        #expect(FileManager.default.fileExists(atPath: tempDestination.path))
        #expect(result.destinationURL == tempDestination)

        // Read back the exported DOCX with DOCXPackageReader
        let parsedExport = try DOCXPackageReader.read(from: tempDestination)
        #expect(parsedExport.blocks.count == parsedSource.blocks.count)

        // Block 0 was translated and retained its heading kind and styleID
        let exportedBlock0 = parsedExport.blocks[0]
        #expect(exportedBlock0.kind == .heading)
        #expect(exportedBlock0.styleID == "ChapterTitle")
        #expect(exportedBlock0.spans.map(\.text).joined() == "Глава Первая: Новое Начало")

        // Block 1 was translated
        let exportedBlock1 = parsedExport.blocks[1]
        #expect(exportedBlock1.spans.map(\.text).joined() == "Переведённый абзац с сохранённым стилем.")

        // Block 2 (untranslated) preserved original text and italic trait
        let exportedBlock2 = parsedExport.blocks[2]
        #expect(exportedBlock2.spans.map(\.text).joined() == "Italic Book Title")
        #expect(exportedBlock2.spans.contains { $0.traits.contains(.italic) })

        // Package preserved required parts
        #expect(parsedExport.entryNames.contains("word/document.xml"))
        #expect(parsedExport.entryNames.contains("[Content_Types].xml"))
    }
    @Test("DOCX export preserves colored translated runs and does not blank styled runs")
    func exportsColoredRunsWithoutBlanking() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docx-color-export-\(UUID().uuidString)")
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

        let sourceDocxURL = tempDir.appendingPathComponent("source.docx")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = tempDir
        proc.arguments = ["-q", "-r", sourceDocxURL.path, "[Content_Types].xml", "_rels", "word"]
        try proc.run()
        proc.waitUntilExit()
        #expect(proc.terminationStatus == 0)

        let parsedSource = try DOCXPackageReader.read(from: sourceDocxURL)
        let block0 = parsedSource.blocks[0]

        let translatedSpans = [
            RichTextSpan(id: block0.spans[0].id, text: "Черный текст и ", foregroundColorHex: nil),
            RichTextSpan(id: block0.spans[1].id, text: "красный плейсхолдер", foregroundColorHex: "FF0000")
        ]
        let translatedBlock = TranslatedBlock(
            id: block0.id,
            sourceBlockID: block0.id,
            text: "Черный текст и красный плейсхолдер",
            spans: translatedSpans,
            reviewDisposition: .manuallyApproved
        )

        let docState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "sourceFile", format: "docx"),
            blocks: [block0],
            chunks: [],
            translationsByLanguage: ["russian": [block0.id: translatedBlock]]
        )

        let outputDocxURL = tempDir.appendingPathComponent("output.docx")
        try DocumentExportWriters.writeDOCX(
            sourceDocxURL: sourceDocxURL,
            documentState: docState,
            language: "russian",
            to: outputDocxURL
        )

        let parsedOutput = try DOCXPackageReader.read(from: outputDocxURL)
        #expect(parsedOutput.blocks.count == 1)
        let outBlock = parsedOutput.blocks[0]
        #expect(outBlock.spans.count == 2)
        #expect(outBlock.spans[0].text == "Черный текст и ")
        #expect(outBlock.spans[0].foregroundColorHex == nil)
        #expect(outBlock.spans[1].text == "красный плейсхолдер")
        #expect(outBlock.spans[1].foregroundColorHex == "FF0000")
    }

    @Test("Wrong sourceHash rejects export with sourceHashMismatch error")
    func hashMismatchRejectsExport() throws {
        let fixture = fixtureURL()
        let parsedSource = try DOCXPackageReader.read(from: fixture)
        let block0 = parsedSource.blocks[0]

        let translatedRussian: [String: TranslatedBlock] = [
            block0.id: TranslatedBlock(
                id: "tr-0",
                sourceBlockID: block0.id,
                text: "Перевод",
                sourceHash: block0.sourceHash,
                reviewDisposition: .manuallyApproved
            )
        ]

        let mismatchedHash = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(
                key: "sourceFile",
                originalFileName: "synthetic-document.docx",
                role: .originalSource,
                format: "docx",
                sha256: mismatchedHash
            ),
            metadata: parsedSource.metadata,
            blocks: parsedSource.blocks,
            translationsByLanguage: ["russian": translatedRussian]
        )

        let tempDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("hash-mismatch-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: tempDestination) }

        #expect {
            try DocumentExportWriters.writeDOCX(
                sourceDocxURL: fixture,
                documentState: documentState,
                language: "Russian",
                to: tempDestination
            )
        } throws: { error in
            guard case let DocumentExportWriters.ExportError.sourceHashMismatch(expected, _) = error else {
                return false
            }
            return expected == mismatchedHash
        }
    }

    @Test("Matching sourceHash allows export to proceed")
    func matchingSourceHashAllowsExport() throws {
        let fixture = fixtureURL()
        let parsedSource = try DOCXPackageReader.read(from: fixture)
        let block0 = parsedSource.blocks[0]

        let actualHash = try DocumentImportService.computeSHA256(for: fixture)
        let verified = try DocumentImportService.verifySourceHash(fileURL: fixture, expectedHash: actualHash)
        #expect(verified == true)

        let translatedRussian: [String: TranslatedBlock] = [
            block0.id: TranslatedBlock(
                id: "tr-0",
                sourceBlockID: block0.id,
                text: "Перевод заголовка",
                sourceHash: block0.sourceHash,
                reviewDisposition: .manuallyApproved
            )
        ]

        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(
                key: "sourceFile",
                originalFileName: "synthetic-document.docx",
                role: .originalSource,
                format: "docx",
                sha256: actualHash
            ),
            metadata: parsedSource.metadata,
            blocks: parsedSource.blocks,
            translationsByLanguage: ["russian": translatedRussian]
        )

        let tempDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("valid-hash-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: tempDestination) }

        let result = try DocumentExportWriters.writeDOCX(
            sourceDocxURL: fixture,
            documentState: documentState,
            language: "Russian",
            to: tempDestination
        )

        #expect(FileManager.default.fileExists(atPath: result.destinationURL.path))
    }

    @Test("Detects Gentium and Brill font references in styles.xml and emits warnings")
    func fontWarningEmittedForBrillOrGentium() throws {
        let tempFixtureDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docx-font-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempFixtureDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempFixtureDir) }

        // Extract base synthetic fixture
        let fixture = fixtureURL()
        let unzipProc = Process()
        unzipProc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProc.arguments = ["-q", fixture.path, "-d", tempFixtureDir.path]
        try unzipProc.run()
        unzipProc.waitUntilExit()

        // Inject word/styles.xml containing Gentium and Brill-Roman
        let stylesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:style w:type="paragraph" w:styleId="Normal">
                <w:rPr>
                    <w:rFonts w:ascii="Gentium" w:hAnsi="Gentium"/>
                </w:rPr>
            </w:style>
            <w:style w:type="character" w:styleId="ScholarScript">
                <w:rPr>
                    <w:rFonts w:ascii="Brill-Roman" w:cs="Brill"/>
                </w:rPr>
            </w:style>
        </w:styles>
        """
        let stylesURL = tempFixtureDir.appendingPathComponent("word/styles.xml")
        try stylesXML.data(using: .utf8)?.write(to: stylesURL)

        // Zip up into a test DOCX
        let customDocx = FileManager.default.temporaryDirectory
            .appendingPathComponent("font-test-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: customDocx) }

        let zipProc = Process()
        zipProc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProc.currentDirectoryURL = tempFixtureDir
        zipProc.arguments = ["-q", "-r", "-X", customDocx.path, "."]
        try zipProc.run()
        zipProc.waitUntilExit()

        let parsedSource = try DOCXPackageReader.read(from: customDocx)
        let block0 = parsedSource.blocks[0]

        let translatedRussian: [String: TranslatedBlock] = [
            block0.id: TranslatedBlock(
                id: "tr-0",
                sourceBlockID: block0.id,
                text: "Заголовок с шрифтами",
                sourceHash: block0.sourceHash,
                reviewDisposition: .manuallyApproved
            )
        ]

        let docState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(
                key: "sourceFile",
                originalFileName: "font-test.docx",
                role: .originalSource,
                format: "docx"
            ),
            metadata: parsedSource.metadata,
            blocks: parsedSource.blocks,
            translationsByLanguage: ["russian": translatedRussian]
        )

        let tempDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("font-warn-output-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: tempDestination) }

        let result = try DocumentExportWriters.writeDOCX(
            sourceDocxURL: customDocx,
            documentState: docState,
            language: "Russian",
            to: tempDestination
        )

        #expect(FileManager.default.fileExists(atPath: tempDestination.path))
        #expect(result.warnings.count >= 2)
        #expect(result.warnings.contains { $0.contains("Gentium") })
        #expect(result.warnings.contains { $0.contains("Brill") })
        #expect(result.detectedFonts.contains("Gentium"))
        #expect(result.detectedFonts.contains("Brill-Roman"))
    }

    @Test("Error handling for missing source and missing translation")
    func errorHandling() {
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non-existent-\(UUID().uuidString).docx")
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        let docState = DocumentState(
            format: .docx,
            blocks: [
                DocumentBlock(
                    id: "b0",
                    location: DocumentLocation(part: .mainBody, paragraphOrdinal: 0),
                    kind: .paragraph,
                    spans: [RichTextSpan(id: "s0", text: "Hello")]
                )
            ],
            translationsByLanguage: ["russian": ["b0": TranslatedBlock(id: "t0", sourceBlockID: "b0", text: "Привет")]]
        )

        #expect(throws: DocumentExportWriters.ExportError.missingSourceDocument) {
            try DocumentExportWriters.writeDOCX(
                sourceDocxURL: nonExistentURL,
                documentState: docState,
                language: "Russian",
                to: destinationURL
            )
        }

        let emptyDocState = DocumentState(
            format: .docx,
            blocks: [
                DocumentBlock(
                    id: "b0",
                    location: DocumentLocation(part: .mainBody, paragraphOrdinal: 0),
                    kind: .paragraph,
                    spans: [RichTextSpan(id: "s0", text: "Hello")]
                )
            ],
            translationsByLanguage: [:]
        )

        #expect(throws: DocumentExportWriters.ExportError.missingTranslation) {
            try DocumentExportWriters.writeDOCX(
                sourceDocxURL: fixtureURL(),
                documentState: emptyDocState,
                language: "Russian",
                to: destinationURL
            )
        }
    }

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/synthetic-document.docx")
    }
}
