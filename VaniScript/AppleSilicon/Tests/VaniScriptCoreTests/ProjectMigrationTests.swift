import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Project schema migration")
struct ProjectMigrationTests {
    @Test("decodes old media JSON without changing transcript content")
    func decodesLegacyMediaJSON() throws {
        let data = Data(
            #"{"id":"legacy","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z","session":{"sourceFile":"/tmp/lecture.mp3","sourceFileName":"lecture.mp3","durationSec":18,"metadata":{"date":"","location":"","lecturer":"","participants":""},"sourceLang":"auto","targetLang":"Russian","transcriptionProvider":"coreml-whisperkit","translationProvider":"mlx-native","outputFormats":["TXT"],"chunks":[{"index":2,"filePath":"/tmp/lecture.mp3","durationSec":5.5,"startSec":12.5,"endSec":18,"original":"Original text","translated":"Перевод","status":"done","approved":true}],"currentChunkIndex":0}}"#.utf8
        )

        let records = try ProjectArchive.decode(data)
        let record = try #require(records.first)
        let chunk = try #require(record.session.chunks.first)
        #expect(record.session.sourceKind == .media)
        #expect(chunk.original == "Original text")
        #expect(chunk.translated == "Перевод")
        #expect(chunk.sourceAnchor == .media(startSec: 12.5, endSec: 18))
        #expect(chunk.reviewDisposition == .manuallyApproved)
        #expect(chunk.approved)
    }

    @Test("rejects an unsupported bundle schema instead of ignoring it")
    func rejectsUnsupportedSchema() {
        do {
            try ProjectMigrator.validateSchemaVersion(99)
            #expect(Bool(false), "schema 99 must be rejected")
        } catch let error as ProjectMigrationError {
            #expect(error == .unsupportedSchemaVersion(99))
        } catch {
            #expect(Bool(false), "unexpected migration error: \(error)")
        }
    }

    @Test("exports schema v4 with a typed asset manifest and imports a v3 bundle")
    func exportsV4AndImportsV3() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaniScript-S7-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourceURL = tempDirectory.appendingPathComponent("lecture.mp3")
        try Data("source-media".utf8).write(to: sourceURL)
        let record = ProjectRecord(
            id: "v4-project",
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            session: SessionState(
                sourceFile: sourceURL.path,
                sourceFileName: sourceURL.lastPathComponent,
                durationSec: 18,
                metadata: .empty,
                sourceLang: "auto",
                targetLang: "Russian",
                transcriptionProvider: "coreml-whisperkit",
                translationProvider: "mlx-native",
                outputFormats: [.txt],
                chunks: [
                    ChunkData(
                        index: 0,
                        filePath: sourceURL.path,
                        durationSec: 18,
                        startSec: 0,
                        endSec: 18,
                        original: "One",
                        translated: "Один",
                        status: .done,
                        approved: true
                    )
                ],
                currentChunkIndex: 0
            )
        )

        let exportURL = tempDirectory.appendingPathComponent("v4.vaniscript")
        try ProjectBundleExporter.exportBundle(record: record, to: exportURL)
        let exportedData = try Data(contentsOf: exportURL)
        let exportedMetadata = try metadata(from: exportedData)
        #expect(exportedMetadata["schemaVersion"] as? Int == 4)
        let manifest = try #require(exportedMetadata["assetManifest"] as? [String: Any])
        #expect((manifest["entries"] as? [[String: Any]])?.isEmpty == false)

        let v3URL = tempDirectory.appendingPathComponent("v3.vaniscript")
        var v3Data = Data("VANISCRIPT_BUNDLE_V2\n".utf8)
        let v3Metadata: [String: Any] = [
            "format": "vaniscript-project-v2",
            "schemaVersion": 3,
            "project": try JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
        ]
        let v3JSON = try JSONSerialization.data(withJSONObject: v3Metadata, options: [.sortedKeys])
        v3Data.append(Data(String(format: "%012d\n", v3JSON.count).utf8))
        v3Data.append(v3JSON)
        try v3Data.write(to: v3URL)

        let imported = try ProjectBundleImporter.importBundle(
            fileURL: v3URL,
            destinationDirectoryURL: tempDirectory.appendingPathComponent("Projects", isDirectory: true)
        )
        let importedChunk = try #require(imported.first?.session.chunks.first)
        #expect(importedChunk.original == "One")
        #expect(importedChunk.translated == "Один")
        #expect(importedChunk.sourceAnchor == .media(startSec: 0, endSec: 18))
        #expect(importedChunk.reviewDisposition == .manuallyApproved)
    }

    private func metadata(from data: Data) throws -> [String: Any] {
        guard let separator = data.firstIndex(of: 0x0A),
              let secondSeparator = data[(separator + 1)...].firstIndex(of: 0x0A) else {
            throw NSError(domain: "ProjectMigrationTests", code: 1)
        }
        let lengthStart = separator + 1
        let lengthData = data[lengthStart..<secondSeparator]
        guard let length = Int(String(decoding: lengthData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(domain: "ProjectMigrationTests", code: 2)
        }
        let jsonStart = secondSeparator + 1
        return try #require(JSONSerialization.jsonObject(with: data[jsonStart..<(jsonStart + length)]) as? [String: Any])
    }
}
