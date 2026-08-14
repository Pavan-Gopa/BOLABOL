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

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/synthetic-document.docx")
    }
}
