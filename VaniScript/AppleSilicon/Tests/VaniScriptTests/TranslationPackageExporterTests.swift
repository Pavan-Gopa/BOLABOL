import CryptoKit
import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Translation package exporter")
struct TranslationPackageExporterTests {
    @Test("Export package creates three files atomically: original DOCX, localized DOCX, and .vaniscript bundle")
    func exportsThreeFilesAtomically() throws {
        let fixture = fixtureURL()
        let parsedSource = try DOCXPackageReader.read(from: fixture)
        let block0 = parsedSource.blocks[0]
        let block1 = parsedSource.blocks[1]

        let translatedRussian: [String: TranslatedBlock] = [
            block0.id: TranslatedBlock(
                id: "tr-0",
                sourceBlockID: block0.id,
                text: "Глава Первая: Пакетный Экспорт",
                sourceHash: block0.sourceHash,
                reviewDisposition: .manuallyApproved
            ),
            block1.id: TranslatedBlock(
                id: "tr-1",
                sourceBlockID: block1.id,
                text: "Текст второго абзаца в локализованном пакете.",
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
            translationsByLanguage: ["ru": translatedRussian],
            profile: .default
        )

        let session = SessionState(
            sourceFile: fixture.path,
            sourceFileName: "synthetic-document.docx",
            durationSec: 0,
            metadata: AudioMetadata.empty,
            sourceLang: "auto",
            targetLang: "ru",
            transcriptionProvider: "none",
            translationProvider: "mlx-local",
            outputFormats: [],
            chunks: [],
            currentChunkIndex: 0,
            availableTranslationLanguages: ["ru"],
            activeTranslationLanguage: "ru",
            sourceKind: .document,
            documentState: documentState,
            approvalMode: .manual
        )

        let record = ProjectRecord(
            id: UUID().uuidString.lowercased(),
            createdAt: "2026-08-15T12:00:00Z",
            updatedAt: "2026-08-15T12:00:00Z",
            session: session
        )

        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pkg-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destDir) }

        let result = try DocumentExportWriters.exportTranslationPackage(
            sourceDocxURL: fixture,
            documentState: documentState,
            projectRecord: record,
            language: "ru",
            to: destDir
        )

        // 1. Assert result URLs exist on disk
        #expect(FileManager.default.fileExists(atPath: result.originalDocxURL.path))
        #expect(FileManager.default.fileExists(atPath: result.localizedDocxURL.path))
        #expect(FileManager.default.fileExists(atPath: result.projectBundleURL.path))

        // 2. Assert Original DOCX is byte-identical / SHA-256 matches the original
        let exportedOriginalHash = try DocumentImportService.computeSHA256(for: result.originalDocxURL)
        #expect(exportedOriginalHash == actualHash)

        // 3. Assert Localized DOCX is valid OOXML with translated text
        let parsedLocalized = try DOCXPackageReader.read(from: result.localizedDocxURL)
        #expect(parsedLocalized.blocks.count == parsedSource.blocks.count)
        let block0Text = parsedLocalized.blocks[0].spans.map { $0.text }.joined()
        let block1Text = parsedLocalized.blocks[1].spans.map { $0.text }.joined()
        #expect(block0Text == "Глава Первая: Пакетный Экспорт")
        #expect(block1Text == "Текст второго абзаца в локализованном пакете.")
        // 4. Assert .vaniscript bundle is valid and restores correctly
        let restoreDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pkg-restore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: restoreDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: restoreDir) }

        let importedRecords = try ProjectBundleImporter.importBundle(
            fileURL: result.projectBundleURL,
            destinationDirectoryURL: restoreDir
        )
        #expect(importedRecords.count == 1)

        let restored = importedRecords[0]
        #expect(restored.session.sourceKind == WorkflowSourceKind.document)
        #expect(restored.session.documentState != nil)
        #expect(restored.session.documentState?.blocks.count == parsedSource.blocks.count)

        if let restoredDocState = restored.session.documentState {
            let restoredTranslations = restoredDocState.translationsByLanguage["ru"]
            #expect(restoredTranslations?[block0.id]?.text == "Глава Первая: Пакетный Экспорт")
        }
        // Assert restored source file exists on disk
        if let restoredSourcePath = restored.session.sourceFile {
            #expect(FileManager.default.fileExists(atPath: restoredSourcePath))
            let restoredHash = try DocumentImportService.computeSHA256(for: URL(fileURLWithPath: restoredSourcePath))
            #expect(restoredHash == actualHash)
        } else {
            Issue.record("Restored project session sourceFile should not be nil.")
        }
    }

    @Test("Stale archived sourceHash is advisory and does not block package export")
    func staleSourceHashDoesNotBlockPackageExport() throws {
        let fixture = fixtureURL()
        let parsedSource = try DOCXPackageReader.read(from: fixture)
        let block0 = parsedSource.blocks[0]

        let translatedRussian: [String: TranslatedBlock] = [
            block0.id: TranslatedBlock(
                id: "tr-0",
                sourceBlockID: block0.id,
                text: "Текст",
                sourceHash: block0.sourceHash,
                reviewDisposition: .manuallyApproved
            )
        ]
        let wrongHash = "1111222233334444555566667777888899990000aaaaabbbbbcccccdddddeeeee"
        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(
                key: "sourceFile",
                originalFileName: "synthetic-document.docx",
                role: .originalSource,
                format: "docx",
                sha256: wrongHash
            ),
            metadata: parsedSource.metadata,
            blocks: parsedSource.blocks,
            translationsByLanguage: ["ru": translatedRussian]
        )

        let session = SessionState(
            sourceFile: fixture.path,
            sourceFileName: "synthetic-document.docx",
            durationSec: 0,
            metadata: AudioMetadata.empty,
            sourceLang: "auto",
            targetLang: "ru",
            transcriptionProvider: "none",
            translationProvider: "none",
            outputFormats: [],
            chunks: [],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: documentState
        )

        let record = ProjectRecord(
            id: UUID().uuidString.lowercased(),
            createdAt: "2026-08-15T12:00:00Z",
            updatedAt: "2026-08-15T12:00:00Z",
            session: session
        )

        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pkg-stale-hash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destDir) }

        _ = try DocumentExportWriters.exportTranslationPackage(
            sourceDocxURL: fixture,
            documentState: documentState,
            projectRecord: record,
            language: "ru",
            to: destDir
        )
        let contents = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
        #expect(!contents.isEmpty)
    }

    @Test("Missing source file throws missingSourceDocument error")
    func missingSourceRejectsPackageExport() {
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non-existent-source-\(UUID().uuidString).docx")
        let docState = DocumentState(
            format: .docx,
            blocks: [
                DocumentBlock(
                    id: "b0",
                    location: DocumentLocation(part: .mainBody, paragraphOrdinal: 0),
                    kind: .paragraph,
                    spans: [RichTextSpan(id: "s0", text: "Test")]
                )
            ],
            translationsByLanguage: ["ru": ["b0": TranslatedBlock(id: "t0", sourceBlockID: "b0", text: "Тест")]]
        )
        let session = SessionState(
            sourceFile: nonExistentURL.path,
            sourceFileName: "non-existent.docx",
            durationSec: 0,
            metadata: AudioMetadata.empty,
            sourceLang: "auto",
            targetLang: "ru",
            transcriptionProvider: "none",
            translationProvider: "none",
            outputFormats: [],
            chunks: [],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: docState
        )
        let record = ProjectRecord(
            id: UUID().uuidString.lowercased(),
            createdAt: "2026-08-15T12:00:00Z",
            updatedAt: "2026-08-15T12:00:00Z",
            session: session
        )
        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pkg-missing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destDir) }

        #expect(throws: DocumentExportWriters.ExportError.missingSourceDocument) {
            try DocumentExportWriters.exportTranslationPackage(
                sourceDocxURL: nonExistentURL,
                documentState: docState,
                projectRecord: record,
                language: "ru",
                to: destDir
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
