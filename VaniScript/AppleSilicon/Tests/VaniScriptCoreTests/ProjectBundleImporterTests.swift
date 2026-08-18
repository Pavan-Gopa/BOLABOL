import Foundation
import Testing
@testable import VaniScriptCore

@Suite("VaniScript project bundle importer")
struct ProjectBundleImporterTests {
    @Test("imports V2 project bundle and extracts assets")
    func importsV2ProjectBundle() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.vaniscript")

        // Construct V2 project bundle data
        var data = Data()
        data.append("VANISCRIPT_BUNDLE_V2\n".data(using: .utf8)!)

        let projectRecord = ProjectRecord(
            id: "test-v2-proj",
            createdAt: "2026-05-25T10:00:00Z",
            updatedAt: "2026-05-25T10:05:00Z",
            session: SessionState(
                sourceFile: "/remote/path/lecture.mp3",
                sourceFileName: "lecture.mp3",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "Russian",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(index: 0, filePath: "/remote/path/chunk0.m4a", durationSec: 10, startSec: 0, endSec: 10, original: "One", translated: "Один", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .done, approved: true)
                ],
                currentChunkIndex: 0
            )
        )

        struct V2BundleMetadata: Codable {
            var format: String
            var project: ProjectRecord
        }
        let meta = V2BundleMetadata(format: "vaniscript-project-v2", project: projectRecord)
        let metaData = try JSONEncoder().encode(meta)

        let lenStr = String(format: "%012d\n", metaData.count)
        data.append(lenStr.data(using: .utf8)!)
        data.append(metaData)

        // Asset: sourceFile
        data.append("START_ASSET\n".data(using: .utf8)!)
        data.append("sourceFile\n".data(using: .utf8)!)
        data.append("lecture.mp3\n".data(using: .utf8)!)
        let sourceContent = "source-media-binary-data"
        data.append("\(sourceContent.count)\n".data(using: .utf8)!)
        data.append(sourceContent.data(using: .utf8)!)
        data.append("END_ASSET\n".data(using: .utf8)!)

        // Asset: chunk:0
        data.append("START_ASSET\n".data(using: .utf8)!)
        data.append("chunk:0\n".data(using: .utf8)!)
        data.append("chunk0.m4a\n".data(using: .utf8)!)
        let chunkContent = "chunk-segment-binary-data"
        data.append("\(chunkContent.count)\n".data(using: .utf8)!)
        data.append(chunkContent.data(using: .utf8)!)
        data.append("END_ASSET\n".data(using: .utf8)!)

        try data.write(to: bundleURL)

        let destDir = tempDir.appendingPathComponent("Projects", isDirectory: true)
        let imported = try ProjectBundleImporter.importBundle(fileURL: bundleURL, destinationDirectoryURL: destDir)

        #expect(imported.count == 1)
        let record = imported[0]
        #expect(!record.id.isEmpty)
        #expect(record.id != "test-v2-proj") // Must generate a new unique ID

        // Verify extracted files and updated paths
        let sourceFile = record.session.sourceFile ?? ""
        #expect(sourceFile.hasSuffix("Projects/\(record.id)/audio/lecture.mp3"))
        #expect(FileManager.default.fileExists(atPath: sourceFile))
        #expect(try String(contentsOfFile: sourceFile) == sourceContent)

        let chunkFile = record.session.chunks[0].filePath
        #expect(chunkFile.hasSuffix("Projects/\(record.id)/chunks/chunk0.m4a"))
        #expect(FileManager.default.fileExists(atPath: chunkFile))
        #expect(try String(contentsOfFile: chunkFile) == chunkContent)
    }

    @Test("imports V1 JSON project bundle and extracts assets")
    func importsV1JSONBundle() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test-v1.vaniscript")

        let projectRecord = ProjectRecord(
            id: "test-v1-proj",
            createdAt: "2026-05-25T10:00:00Z",
            updatedAt: "2026-05-25T10:05:00Z",
            session: SessionState(
                sourceFile: "/remote/path/lecture.mp3",
                sourceFileName: "lecture.mp3",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "Russian",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(index: 0, filePath: "/remote/path/chunk0.m4a", durationSec: 10, startSec: 0, endSec: 10, original: "One", translated: "Один", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .done, approved: true)
                ],
                currentChunkIndex: 0
            )
        )

        let sourceContent = "source-media-binary-data"
        let sourceBase64 = Data(sourceContent.utf8).base64EncodedString()
        let chunkContent = "chunk-segment-binary-data"
        let chunkBase64 = Data(chunkContent.utf8).base64EncodedString()

        let jsonStr = """
        {
          "format": "vaniscript-project-v1",
          "project": {
            "id": "test-v1-proj",
            "createdAt": "2026-05-25T10:00:00Z",
            "updatedAt": "2026-05-25T10:05:00Z",
            "session": {
              "sourceFile": "/remote/path/lecture.mp3",
              "sourceFileName": "lecture.mp3",
              "durationSec": 10,
              "metadata": { "date": "", "location": "", "lecturer": "", "participants": "" },
              "sourceLang": "auto",
              "targetLang": "Russian",
              "transcriptionProvider": "mlx",
              "translationProvider": "mlx",
              "outputFormats": ["TXT"],
              "chunks": [
                {
                  "index": 0,
                  "filePath": "/remote/path/chunk0.m4a",
                  "durationSec": 10,
                  "startSec": 0,
                  "endSec": 10,
                  "original": "One",
                  "translated": "Один",
                  "originalFormats": null,
                  "translatedFormats": null,
                  "unrecognizedFragments": [],
                  "status": "done",
                  "approved": true
                }
              ],
              "currentChunkIndex": 0
            }
          },
          "assets": [
            {
              "key": "sourceFile",
              "name": "lecture.mp3",
              "dataBase64": "\(sourceBase64)"
            },
            {
              "key": "chunk:0",
              "name": "chunk0.m4a",
              "dataBase64": "\(chunkBase64)"
            }
          ]
        }
        """

        try Data(jsonStr.utf8).write(to: bundleURL)

        let destDir = tempDir.appendingPathComponent("Projects", isDirectory: true)
        let imported = try ProjectBundleImporter.importBundle(fileURL: bundleURL, destinationDirectoryURL: destDir)

        #expect(imported.count == 1)
        let record = imported[0]
        #expect(!record.id.isEmpty)
        #expect(record.id != "test-v1-proj")

        // Verify extracted files and updated paths
        let sourceFile = record.session.sourceFile ?? ""
        #expect(sourceFile.hasSuffix("Projects/\(record.id)/audio/lecture.mp3"))
        #expect(FileManager.default.fileExists(atPath: sourceFile))
        #expect(try String(contentsOfFile: sourceFile) == sourceContent)

        let chunkFile = record.session.chunks[0].filePath
        #expect(chunkFile.hasSuffix("Projects/\(record.id)/chunks/chunk0.m4a"))
        #expect(FileManager.default.fileExists(atPath: chunkFile))
        #expect(try String(contentsOfFile: chunkFile) == chunkContent)
    }

    @Test("falls back to raw JSON decoding for standard formats")
    func fallsBackToRawJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test-raw.json")

        let jsonStr = """
        [
          {
            "id": "project-raw",
            "createdAt": "2026-05-25T10:00:00Z",
            "updatedAt": "2026-05-25T10:05:00Z",
            "session": {
              "sourceFile": "/tmp/lecture.mp3",
              "sourceFileName": "lecture.mp3",
              "durationSec": 60,
              "metadata": {
                "date": "2026-05-25",
                "location": "Mayapur",
                "lecturer": "HH Kadamba Kanana Swami",
                "participants": ""
              },
              "sourceLang": "auto",
              "targetLang": "Russian",
              "transcriptionProvider": "coreml-whisperkit",
              "translationProvider": "mlx-native",
              "outputFormats": ["TXT"],
              "chunks": [
                {
                  "index": 0,
                  "filePath": "/tmp/lecture.mp3",
                  "durationSec": 60,
                  "startSec": 0,
                  "endSec": 60,
                  "original": "One",
                  "translated": "Один",
                  "originalFormats": null,
                  "translatedFormats": null,
                  "unrecognizedFragments": [],
                  "status": "done",
                  "approved": true
                }
              ],
              "currentChunkIndex": 0
            }
          }
        ]
        """

        try Data(jsonStr.utf8).write(to: bundleURL)

        let destDir = tempDir.appendingPathComponent("Projects", isDirectory: true)
        let imported = try ProjectBundleImporter.importBundle(fileURL: bundleURL, destinationDirectoryURL: destDir)

        #expect(imported.count == 1)
        #expect(imported[0].id == "project-raw") // No new ID generated because it's a raw project list
        #expect(imported[0].session.sourceFile == "/tmp/lecture.mp3")
    }

    @Test("imports project when durationSec is missing from session JSON")
    func importsProjectMissingDurationSec() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test-missing-duration.json")

        let jsonStr = """
        [
          {
            "id": "project-missing-duration",
            "createdAt": "2026-05-25T10:00:00Z",
            "updatedAt": "2026-05-25T10:05:00Z",
            "session": {
              "sourceFile": "/tmp/lecture.mp3",
              "sourceFileName": "lecture.mp3",
              "sourceLang": "auto",
              "targetLang": "Russian",
              "outputFormats": ["txt"],
              "chunks": [
                {
                  "index": 0,
                  "filePath": "/tmp/lecture.mp3",
                  "startSec": 0,
                  "endSec": 60,
                  "original": "One",
                  "translated": "Один",
                  "status": "DONE",
                  "approved": true
                }
              ],
              "currentChunkIndex": 0
            }
          }
        ]
        """

        try Data(jsonStr.utf8).write(to: bundleURL)

        let destDir = tempDir.appendingPathComponent("Projects", isDirectory: true)
        let imported = try ProjectBundleImporter.importBundle(fileURL: bundleURL, destinationDirectoryURL: destDir)

        #expect(imported.count == 1)
        let record = imported[0]
        #expect(record.id == "project-missing-duration")
        #expect(record.session.durationSec == 0.0)
        #expect(record.session.transcriptionProvider == "coreml-whisperkit")
        #expect(record.session.chunks[0].durationSec == 0.0)
    }

    @Test("exports and then imports a V2 project bundle successfully")
    func exportAndImportRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceFile = tempDir.appendingPathComponent("source.wav")
        let sourceContent = "binary-media-source-wav-data"
        try Data(sourceContent.utf8).write(to: sourceFile)

        let chunkFile = tempDir.appendingPathComponent("chunk_0001.m4a")
        let chunkContent = "binary-chunk-m4a-data"
        try Data(chunkContent.utf8).write(to: chunkFile)

        let projectRecord = ProjectRecord(
            id: "export-test-proj",
            createdAt: "2026-05-25T10:00:00Z",
            updatedAt: "2026-05-25T10:05:00Z",
            session: SessionState(
                sourceFile: sourceFile.path,
                sourceFileName: "source.wav",
                durationSec: 10,
                metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""),
                sourceLang: "auto",
                targetLang: "Russian",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(index: 0, filePath: chunkFile.path, durationSec: 10, startSec: 0, endSec: 10, original: "One", translated: "Один", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .done, approved: true)
                ],
                currentChunkIndex: 0
            )
        )

        let exportURL = tempDir.appendingPathComponent("export.vaniscript")
        try ProjectBundleExporter.exportBundle(record: projectRecord, to: exportURL)

        let destDir = tempDir.appendingPathComponent("Projects", isDirectory: true)
        let imported = try ProjectBundleImporter.importBundle(fileURL: exportURL, destinationDirectoryURL: destDir)

        #expect(imported.count == 1)
        let record = imported[0]
        #expect(!record.id.isEmpty)
        #expect(record.id != "export-test-proj")

        let importedSource = record.session.sourceFile ?? ""
        #expect(importedSource.hasSuffix("Projects/\(record.id)/audio/source.wav"))
        #expect(FileManager.default.fileExists(atPath: importedSource))
        #expect(try String(contentsOfFile: importedSource) == sourceContent)

        let importedChunk = record.session.chunks[0].filePath
        #expect(importedChunk.hasSuffix("Projects/\(record.id)/chunks/chunk_0001.m4a"))
        #expect(FileManager.default.fileExists(atPath: importedChunk))
        #expect(try String(contentsOfFile: importedChunk) == chunkContent)
    }

    @Test("document foreground color survives project bundle export and import")
    func documentColorRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceFile = tempDir.appendingPathComponent("book.txt")
        try Data("Red placeholder text".utf8).write(to: sourceFile)

        let sourceBlock = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            spans: [
                RichTextSpan(id: "s1", text: "Red placeholder ", styleKey: "body", foregroundColorHex: "#ff0000"),
                RichTextSpan(id: "s2", text: "text", styleKey: "body")
            ],
            sourceHash: "hash-b1"
        )
        let translatedBlock = TranslatedBlock(
            id: "b1",
            sourceBlockID: "b1",
            text: "Красный заполнитель текст",
            spans: [
                RichTextSpan(id: "t1", text: "Красный заполнитель ", styleKey: "body", foregroundColorHex: "#ff0000"),
                RichTextSpan(id: "t2", text: "текст", styleKey: "body")
            ],
            sourceHash: "hash-b1"
        )
        let documentState = DocumentState(
            format: .txt,
            originalAsset: ProjectAssetReference(key: "sourceFile", originalFileName: "book.txt", format: "txt"),
            blocks: [sourceBlock],
            chunks: [DocumentChunkPlan(id: "plan-1", blockIDs: ["b1"], sourceHash: "hash-b1")],
            translationsByLanguage: ["russian": ["b1": translatedBlock]]
        )

        let projectRecord = ProjectRecord(
            id: "color-roundtrip-proj",
            createdAt: "2026-08-15T10:00:00Z",
            updatedAt: "2026-08-15T10:05:00Z",
            session: SessionState(
                sourceFile: sourceFile.path,
                sourceFileName: "book.txt",
                durationSec: 0,
                metadata: .empty,
                sourceLang: "English",
                targetLang: "Russian",
                transcriptionProvider: "",
                translationProvider: "mock",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(
                        index: 0,
                        filePath: sourceFile.path,
                        durationSec: 0,
                        startSec: 0,
                        endSec: 0,
                        original: "Red placeholder text",
                        translated: "Красный заполнитель текст",
                        status: .done,
                        approved: true,
                        sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b1"))
                    )
                ],
                currentChunkIndex: 0,
                sourceKind: .document,
                documentState: documentState
            )
        )

        let exportURL = tempDir.appendingPathComponent("color.vaniscript")
        try ProjectBundleExporter.exportBundle(record: projectRecord, to: exportURL)

        let destDir = tempDir.appendingPathComponent("Projects", isDirectory: true)
        let imported = try ProjectBundleImporter.importBundle(fileURL: exportURL, destinationDirectoryURL: destDir)

        #expect(imported.count == 1)
        let record = imported[0]
        let importedState = record.session.documentState
        #expect(importedState != nil)

        let importedSourceSpans = importedState?.blocks.first?.spans ?? []
        #expect(importedSourceSpans.count == 2)
        #expect(importedSourceSpans.first?.foregroundColorHex == "FF0000")
        #expect(importedSourceSpans.last?.foregroundColorHex == nil)

        let importedTranslated = importedState?.translationsByLanguage["russian"]?["b1"]
        #expect(importedTranslated != nil)
        #expect(importedTranslated?.spans.count == 2)
        #expect(importedTranslated?.spans.first?.foregroundColorHex == "FF0000")
        #expect(importedTranslated?.spans.last?.foregroundColorHex == nil)
    }

    @Test("applies displayNameOverride to single V2 project bundle without modifying sourceFileName")
    func appliesDisplayNameOverrideToV2Bundle() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("raw_lecture.mp3")
        try Data("audio-payload".utf8).write(to: sourceURL)

        let originalRecord = ProjectRecord(
            id: "orig-v2-proj",
            name: "Original Project Name",
            createdAt: "2026-05-25T10:00:00Z",
            updatedAt: "2026-05-25T10:05:00Z",
            session: SessionState(
                sourceFile: sourceURL.path,
                sourceFileName: "raw_lecture.mp3",
                durationSec: 30,
                metadata: AudioMetadata(date: "2026-05-25", location: "Mumbai", lecturer: "Lecturer", participants: ""),
                sourceLang: "auto",
                targetLang: "Russian",
                transcriptionProvider: "mlx",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(index: 0, filePath: sourceURL.path, durationSec: 30, startSec: 0, endSec: 30, original: "Hello", translated: "Привет", originalFormats: nil, translatedFormats: nil, unrecognizedFragments: [], status: .done, approved: true)
                ],
                currentChunkIndex: 0
            )
        )

        let bundleURL = tempDir.appendingPathComponent("Renamed-Lecture-2026.vaniscript")
        try ProjectBundleExporter.exportBundle(record: originalRecord, to: bundleURL)

        let destDir = tempDir.appendingPathComponent("Projects", isDirectory: true)
        let imported = try ProjectBundleImporter.importBundle(
            fileURL: bundleURL,
            destinationDirectoryURL: destDir,
            displayNameOverride: "Renamed-Lecture-2026"
        )

        #expect(imported.count == 1)
        let record = imported[0]
        #expect(record.name == "Renamed-Lecture-2026")
        #expect(record.summary.name == "Renamed-Lecture-2026")
        #expect(record.session.sourceFileName == "raw_lecture.mp3")
        #expect(record.summary.sourceFileName == "raw_lecture.mp3")
        #expect(record.session.sourceFile != nil)
        #expect(record.session.sourceFile != sourceURL.path) // Extracted to new project dir
    }

    @Test("applies displayNameOverride to document project bundle while preserving document assets and source metadata")
    func appliesDisplayNameOverrideToDocumentBundle() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let sourceDocURL = tempDir.appendingPathComponent("Philosophy_Manuscript.docx")
        try Data("fake-docx-content".utf8).write(to: sourceDocURL)

        let sourceBlock = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            spans: [RichTextSpan(id: "s1", text: "Introduction chapter.", styleKey: "body")],
            sourceHash: "hash-b1"
        )
        let translatedBlock = TranslatedBlock(
            id: "b1",
            sourceBlockID: "b1",
            text: "Вводная глава.",
            spans: [RichTextSpan(id: "t1", text: "Вводная глава.", styleKey: "body")],
            sourceHash: "hash-b1"
        )
        let docState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "sourceDocx", originalFileName: "Philosophy_Manuscript.docx", format: "docx"),
            blocks: [sourceBlock],
            chunks: [DocumentChunkPlan(id: "plan-1", blockIDs: ["b1"], sourceHash: "hash-b1")],
            translationsByLanguage: [
                "russian": ["b1": translatedBlock]
            ]
        )

        let projectRecord = ProjectRecord(
            id: "doc-project-id",
            name: "Old Doc Name",
            createdAt: "2026-08-15T10:00:00Z",
            updatedAt: "2026-08-15T10:05:00Z",
            session: SessionState(
                sourceFile: sourceDocURL.path,
                sourceFileName: "Philosophy_Manuscript.docx",
                durationSec: 0,
                metadata: .empty,
                sourceLang: "English",
                targetLang: "Russian",
                transcriptionProvider: "",
                translationProvider: "mlx",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(index: 0, filePath: sourceDocURL.path, durationSec: 0, startSec: 0, endSec: 0, original: "Introduction chapter.", translated: "Вводная глава.", status: .done, approved: true, sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b1")))
                ],
                currentChunkIndex: 0,
                sourceKind: .document,
                documentState: docState
            )
        )

        let exportURL = tempDir.appendingPathComponent("Renamed-Philosophy-Draft.vaniscript")
        try ProjectBundleExporter.exportBundle(record: projectRecord, to: exportURL)

        let destDir = tempDir.appendingPathComponent("Projects", isDirectory: true)
        let imported = try ProjectBundleImporter.importBundle(
            fileURL: exportURL,
            destinationDirectoryURL: destDir,
            displayNameOverride: "Renamed-Philosophy-Draft"
        )

        #expect(imported.count == 1)
        let record = imported[0]
        #expect(record.name == "Renamed-Philosophy-Draft")
        #expect(record.summary.name == "Renamed-Philosophy-Draft")
        #expect(record.session.sourceFileName == "Philosophy_Manuscript.docx")
        #expect(record.summary.sourceFileName == "Philosophy_Manuscript.docx")
        #expect(record.session.documentState?.originalAsset.originalFileName == "Philosophy_Manuscript.docx")
        #expect(record.session.documentState?.blocks.first?.spans.first?.text == "Introduction chapter.")
    }

    @Test("does not apply single displayNameOverride across library bundle items")
    func leavesLibraryBundleNamesUntouched() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScriptTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file1 = tempDir.appendingPathComponent("file1.mp3")
        let file2 = tempDir.appendingPathComponent("file2.mp3")
        try Data("audio1".utf8).write(to: file1)
        try Data("audio2".utf8).write(to: file2)

        let proj1 = ProjectRecord(
            id: "lib-proj-1",
            name: "Project Alpha",
            createdAt: "2026-08-10T10:00:00Z",
            updatedAt: "2026-08-10T10:05:00Z",
            session: SessionState(sourceFile: file1.path, sourceFileName: "file1.mp3", durationSec: 10, metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""), sourceLang: "auto", targetLang: "ru", transcriptionProvider: "mlx", translationProvider: "mlx", outputFormats: [.txt], chunks: [], currentChunkIndex: 0)
        )
        let proj2 = ProjectRecord(
            id: "lib-proj-2",
            name: "Project Beta",
            createdAt: "2026-08-10T10:00:00Z",
            updatedAt: "2026-08-10T10:05:00Z",
            session: SessionState(sourceFile: file2.path, sourceFileName: "file2.mp3", durationSec: 10, metadata: AudioMetadata(date: "", location: "", lecturer: "", participants: ""), sourceLang: "auto", targetLang: "ru", transcriptionProvider: "mlx", translationProvider: "mlx", outputFormats: [.txt], chunks: [], currentChunkIndex: 0)
        )

        let libraryURL = tempDir.appendingPathComponent("EntireLibraryExport.vaniscript-library")
        try ProjectBundleExporter.exportLibrary(records: [proj1, proj2], to: libraryURL)

        let destDir = tempDir.appendingPathComponent("Projects", isDirectory: true)
        let imported = try ProjectBundleImporter.importBundle(
            fileURL: libraryURL,
            destinationDirectoryURL: destDir,
            displayNameOverride: "EntireLibraryExport"
        )

        #expect(imported.count == 2)
        #expect(imported.contains(where: { $0.summary.name == "Project Alpha" }))
        #expect(imported.contains(where: { $0.summary.name == "Project Beta" }))
        #expect(!imported.contains(where: { $0.summary.name == "EntireLibraryExport" }))
    }
}
