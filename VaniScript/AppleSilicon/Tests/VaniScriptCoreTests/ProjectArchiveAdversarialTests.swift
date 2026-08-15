import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Project archive adversarial boundaries")
struct ProjectArchiveAdversarialTests {
    @Test("archive round-trip preserves records modulo documented archive normalization")
    func arrayRoundTrip() throws {
        let records = [record(id: "a", updated: "2026-01-02T00:00:00Z"), record(id: "b", updated: "2026-01-03T00:00:00Z")]
        let decoded = try ProjectArchive.decode(ProjectArchive.encode(records))
        let expected = records.map(normalized)
        #expect(decoded == expected)
    }

    @Test("archive decoder accepts a single ProjectRecord object for backward compatibility")
    func singleRecordDecode() throws {
        let source = record(id: "single", updated: "2026-01-03T00:00:00Z")
        let data = try JSONEncoder().encode(source)
        let decoded = try ProjectArchive.decode(data)
        #expect(decoded.count == 1)
        #expect(decoded[0] == normalized(source))
    }

    @Test("archive decoder rejects empty, null, and unrelated JSON")
    func malformedArchiveRejected() {
        for data in [Data(), Data("null".utf8), Data(#"{"hello":"world"}"#.utf8)] {
            #expect(throws: Error.self) {
                _ = try ProjectArchive.decode(data)
            }
        }
    }

    @Test("recent sorting uses updatedAt first and createdAt as deterministic tie breaker")
    func recentSortingTieBreaker() {
        var olderCreated = record(id: "old", updated: "2026-01-05T00:00:00Z")
        olderCreated.createdAt = "2026-01-01T00:00:00Z"
        var newerCreated = record(id: "new", updated: "2026-01-05T00:00:00Z")
        newerCreated.createdAt = "2026-01-04T00:00:00Z"
        let newestUpdate = record(id: "latest", updated: "2026-01-06T00:00:00Z")

        #expect(ProjectArchive.sortedRecent([olderCreated, newestUpdate, newerCreated]).map(\.id) == ["latest", "new", "old"])
    }

    @Test("project summary counts done and approved chunks without double counting completed slots")
    func summaryCounts() {
        var source = record(id: "counts", updated: "2026-01-03T00:00:00Z")
        source.session.chunks = [
            chunk(index: 0, status: .done, approved: true),
            chunk(index: 1, status: .done, approved: false),
            chunk(index: 2, status: .pending, approved: true),
            chunk(index: 3, status: .pending, approved: false)
        ]
        let summary = source.summary
        #expect(summary.totalChunks == 4)
        #expect(summary.approvedChunks == 2)
        #expect(summary.completedChunks == 3)
    }

    @Test("project name falls back for empty source filename and strips extension otherwise")
    func summaryProjectName() {
        var named = record(id: "named", updated: "2026-01-03T00:00:00Z")
        named.session.sourceFileName = "Bhagavatam.Part1.docx"
        #expect(named.summary.name == "Bhagavatam.Part1")

        var empty = named
        empty.session.sourceFileName = ""
        #expect(empty.summary.name == URL(fileURLWithPath: "").deletingPathExtension().lastPathComponent)
    }

    private func normalized(_ record: ProjectRecord) -> ProjectRecord {
        var copy = record
        copy.session.normalizeTranslationArchive()
        return copy
    }

    private func record(id: String, updated: String) -> ProjectRecord {
        let block = DocumentBlock(
            id: "b",
            location: DocumentLocation(paragraphOrdinal: 0),
            spans: [RichTextSpan(id: "s", text: "Source")]
        )
        let state = DocumentState(
            format: .txt,
            originalAsset: ProjectAssetReference(key: "source", originalFileName: "book.txt"),
            blocks: [block],
            chunks: [DocumentChunkPlan(id: "p", blockIDs: ["b"])],
            translationsByLanguage: ["russian": ["b": TranslatedBlock(id: "t", blockID: "b", text: "Перевод")]]
        )
        return ProjectRecord(
            id: id,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: updated,
            session: SessionState(
                sourceFile: "/tmp/book.txt",
                sourceFileName: "book.txt",
                durationSec: 0,
                metadata: .empty,
                sourceLang: "English",
                targetLang: "Russian",
                transcriptionProvider: "",
                translationProvider: "mock",
                outputFormats: [.txt],
                chunks: [chunk(index: 0, status: .done, approved: false)],
                currentChunkIndex: 0,
                sourceKind: .document,
                documentState: state,
                approvalMode: .manual
            )
        )
    }

    private func chunk(index: Int, status: ChunkStatus, approved: Bool) -> ChunkData {
        ChunkData(
            index: index,
            filePath: "/tmp/book.txt",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: "Source \(index)",
            translated: status == .done ? "Translated \(index)" : "",
            status: status,
            approved: approved,
            sourceAnchor: .document(DocumentRange(startBlockID: "b", endBlockID: "b"))
        )
    }
}
