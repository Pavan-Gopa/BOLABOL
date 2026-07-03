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
}
