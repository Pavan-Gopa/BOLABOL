import CryptoKit
import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

// S20 (ADR-007): Refresh Source at the WorkflowStore level. The 7 pure tests
// in VaniScriptCoreTests pin DocumentSourceRefresh.merge; these pin the store
// wiring the pure layer cannot express:
//   - media projects are rejected before any panel/import happens,
//   - the refresh itself never contacts a translation provider,
//   - a failed import leaves the project untouched,
//   - the apply path re-imports + merges + rebuilds chunks + persists.
//
// TEST-ISOLATION CONTRACT (mirrors DocumentReplaceEverywhereTests): every
// WorkflowStore construction injects a no-op projectsPersistence, because the
// default persistence writes the user's REAL
// ~/Library/Application Support/VaniScript/projects.json.
//
// applyRefreshedProjectSource hard-resolves the project directory via
// AppStoragePaths.projectDirectory(id:) — there is no seam, and adding one is
// prohibited — so the apply tests use throwaway ids "s20-refresh-apply" and
// "s20-refresh-apply-docx" and scrub
// ~/Library/Application Support/VaniScript/Projects/<that id>.
@MainActor
@Suite("WorkflowStore refresh source (S20)")
struct WorkflowStoreRefreshSourceTests {
    /// Never equals any project id used by a real session, so the scrub can
    /// only ever delete the directory this suite itself creates.
    private static let applyProjectID = "s20-refresh-apply"

    private static let applyProjectDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("VaniScript", isDirectory: true)
        .appendingPathComponent("Projects", isDirectory: true)
        .appendingPathComponent(applyProjectID, isDirectory: true)

    /// Second throwaway id for the prefixed-DOCX apply test; same contract as
    /// `applyProjectID`, distinct so parallel test runs cannot share a scrub.
    private static let applyDocxProjectID = "s20-refresh-apply-docx"

    private static let applyDocxProjectDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("VaniScript", isDirectory: true)
        .appendingPathComponent("Projects", isDirectory: true)
        .appendingPathComponent(applyDocxProjectID, isDirectory: true)

    private func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func block(id: String, text: String) -> DocumentBlock {
        DocumentBlock(
            id: id,
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .paragraph,
            spans: [RichTextSpan(id: "\(id)-s1", text: text)],
            sourceHash: hash(text)
        )
    }

    private func documentState(blocks: [DocumentBlock], translations: [String: TranslatedBlock]) -> DocumentState {
        DocumentState(
            format: .txt,
            originalAsset: ProjectAssetReference(key: "src", originalFileName: "story.txt"),
            blocks: blocks,
            chunks: [],
            translationsByLanguage: translations.isEmpty ? [:] : ["croatian": translations]
        )
    }

    /// Refresh must never reach a provider, so translationProvider is left at
    /// the archive default ("none"), which errors out if it is ever resolved.
    /// Persistence is a no-op (injected) to shield the real projects.json.
    private func makeStore(session: SessionState, projectID: String) -> WorkflowStore {
        WorkflowStore(
            settings: AppSettings.defaults,
            projects: [
                ProjectRecord(
                    id: projectID,
                    createdAt: "2026-01-01T00:00:00Z",
                    updatedAt: "2026-01-01T00:00:00Z",
                    session: session
                ),
            ],
            settingsPersistence: { _ in },
            projectsPersistence: { _ in },
            autosaveInterval: .seconds(600),
            startInitialModelScan: false
        )
    }

    private func mediaSession() -> SessionState {
        SessionState(
            sourceFile: "/tmp/interview.mp4",
            sourceFileName: "interview.mp4",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "auto",
            targetLang: "Croatian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "none",
            outputFormats: [.txt],
            chunks: [],
            currentChunkIndex: 0,
            sourceKind: .media,
            documentState: nil
        )
    }

    private func refreshSummary(projectID: String, changed: [Int]) -> DocumentSourceRefreshSummary {
        DocumentSourceRefreshSummary(
            projectID: projectID,
            matchedBlockCount: 1,
            addedBlockCount: 0,
            removedBlockCount: 0,
            keptTranslationCount: 0,
            changedChunkIndices: changed,
            sourceFileName: "revised-story.txt"
        )
    }

    @Test("media project refresh is rejected without touching the session or opening the retranslate arm")
    func mediaProjectRefreshRejected() {
        let store = makeStore(session: mediaSession(), projectID: "media-1")

        store.applyRefreshedProjectSource(projectID: "media-1", fileURL: URL(fileURLWithPath: "/tmp/replacement.mp4"))

        #expect(store.statusMessage == "Refresh Source is only available for document projects.")
        #expect(store.projects.first?.session.sourceKind == .media)
        #expect(store.projects.first?.session.sourceFileName == "interview.mp4")
        #expect(store.sourceRefreshSummary == nil)

        // The retranslate arm is a second, independent media guard: a stale
        // summary pointing at a media project must not launch translation.
        store.sourceRefreshSummary = refreshSummary(projectID: "media-1", changed: [0])
        store.openProject(id: "media-1")
        store.retranslateChangedChunksAfterSourceRefresh()
        #expect(store.statusMessage == "Open the refreshed document project before retranslating.")
        #expect(store.sourceRefreshSummary != nil)
    }

    @Test("apply rejects unknown id, missing document state, and unreadable file without touching the project")
    func applyFailureLeavesProjectUntouched() {
        let store = makeStore(session: mediaSession(), projectID: "doc-1")

        // Unknown id: silent, no status flip, no summary.
        store.applyRefreshedProjectSource(projectID: "ghost", fileURL: URL(fileURLWithPath: "/tmp/nope.txt"))
        #expect(store.statusMessage.isEmpty)
        #expect(store.sourceRefreshSummary == nil)

        // Document project with no documentState: rejected like media.
        var noState = mediaSession()
        noState.sourceKind = .document
        noState.documentState = nil
        store.projects = [ProjectRecord(id: "doc-1", createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:00Z", session: noState)]
        store.applyRefreshedProjectSource(projectID: "doc-1", fileURL: URL(fileURLWithPath: "/tmp/nope.txt"))
        #expect(store.statusMessage == "Refresh Source is only available for document projects.")
        #expect(store.sourceRefreshSummary == nil)

        // Unreadable replacement file: failure status, project session intact.
        var withDoc = mediaSession()
        withDoc.sourceKind = .document
        withDoc.documentState = documentState(blocks: [block(id: "b1", text: "Hello")], translations: [:])
        store.projects = [ProjectRecord(id: "doc-1", createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:00Z", session: withDoc)]
        store.applyRefreshedProjectSource(projectID: "doc-1", fileURL: URL(fileURLWithPath: "/tmp/definitely-missing-s20.txt"))
        #expect(store.statusMessage.hasPrefix("Refresh Source failed:"))
        #expect(store.sourceRefreshSummary == nil)
        #expect(store.projects.first?.session.sourceKind == .document)
        #expect(store.projects.first?.session.documentState?.blocks.map(\.id) == ["b1"])
    }

    @Test("apply path merges refreshed TXT, keeps matching translation, publishes summary, rebuilds chunks")
    func applyPathMergesAndPublishesSummary() throws {
        // The throwaway id must resolve under this machine's real home so the
        // scrubbed directory is deterministic and never a real project.
        #expect(Self.applyProjectDir.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path))
        let fm = FileManager.default
        defer { try? fm.removeItem(at: Self.applyProjectDir) }

        let translation = TranslatedBlock(
            id: "t1",
            sourceBlockID: "b1",
            text: "Alfa",
            spans: [RichTextSpan(id: "t1-s1", text: "Alfa")],
            sourceHash: hash("Alpha"),
            reviewDisposition: .pending
        )
        var session = mediaSession()
        session.sourceFile = nil
        session.sourceFileName = "story.txt"
        session.sourceKind = .document
        session.documentState = documentState(
            blocks: [block(id: "b1", text: "Alpha"), block(id: "b2", text: "Beta")],
            translations: ["b1": translation]
        )
        session.chunks = [
            ChunkData(index: 0, filePath: "/tmp/old/story.txt", durationSec: 0, startSec: 0, endSec: 0, original: "Alpha", translated: "Alfa", status: .done, approved: false, sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b1"))),
            ChunkData(index: 1, filePath: "/tmp/old/story.txt", durationSec: 0, startSec: 0, endSec: 0, original: "Beta", translated: "", status: .pending, approved: false, sourceAnchor: .document(DocumentRange(startBlockID: "b2", endBlockID: "b2"))),
        ]

        let tempDir = fm.temporaryDirectory.appendingPathComponent("s20-refresh-tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        let replacementURL = tempDir.appendingPathComponent("revised-story.txt")
        try "Alpha\nGamma".write(to: replacementURL, atomically: true, encoding: .utf8)

        let store = makeStore(session: session, projectID: Self.applyProjectID)
        store.openProject(id: Self.applyProjectID)

        store.applyRefreshedProjectSource(projectID: Self.applyProjectID, fileURL: replacementURL)

        let summary = try #require(store.sourceRefreshSummary, "success must publish the retranslate offer")
        #expect(summary.projectID == Self.applyProjectID)
        #expect(summary.matchedBlockCount == 1)
        #expect(summary.addedBlockCount == 1)
        #expect(summary.removedBlockCount == 1)
        #expect(summary.keptTranslationCount == 1)

        let applied = store.projects.first?.session
        #expect(applied?.sourceFileName == "revised-story.txt")
        #expect(applied?.documentState?.blocks.first?.id == "b1", "matching block must keep its old id")
        #expect(applied?.documentState?.translationsByLanguage["croatian"]?["b1"]?.text == "Alfa", "matching translation is kept")
        #expect(applied?.documentState?.blocks.last?.spans.map(\.text).joined() == "Gamma")

        // Rebuilt rows reference the imported copy inside the project dir.
        let expectedPrefix = Self.applyProjectDir.appendingPathComponent("source", isDirectory: true).path
        for chunk in applied?.chunks ?? [] {
            #expect(chunk.filePath.hasPrefix(expectedPrefix))
        }

        #expect(store.statusMessage.hasPrefix("Source refreshed:"))

        // The summary drives the offer; dismissing clears it.
        store.dismissSourceRefreshSummary()
        #expect(store.sourceRefreshSummary == nil)
    }

    @Test("apply path refreshes a prefixed DOCX end-to-end and keeps matching translation")
    func applyPathMergesPrefixedDOCX() throws {
        // The throwaway id must resolve under this machine's real home so the
        // scrubbed directory is deterministic and never a real project.
        #expect(Self.applyDocxProjectDir.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path))
        let fm = FileManager.default
        defer { try? fm.removeItem(at: Self.applyDocxProjectDir) }

        let translation = TranslatedBlock(
            id: "t1",
            sourceBlockID: "b1",
            text: "Alfa",
            spans: [RichTextSpan(id: "t1-s1", text: "Alfa")],
            sourceHash: hash("Alpha"),
            reviewDisposition: .pending
        )
        var session = mediaSession()
        session.sourceFile = nil
        session.sourceFileName = "manuscript.docx"
        session.sourceKind = .document
        session.documentState = documentState(
            blocks: [block(id: "b1", text: "Alpha"), block(id: "b2", text: "Beta")],
            translations: ["b1": translation]
        )
        session.chunks = [
            ChunkData(index: 0, filePath: "/tmp/old/manuscript.docx", durationSec: 0, startSec: 0, endSec: 0, original: "Alpha", translated: "Alfa", status: .done, approved: false, sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b1"))),
            ChunkData(index: 1, filePath: "/tmp/old/manuscript.docx", durationSec: 0, startSec: 0, endSec: 0, original: "Beta", translated: "", status: .pending, approved: false, sourceAnchor: .document(DocumentRange(startBlockID: "b2", endBlockID: "b2"))),
        ]

        let replacementURL = try makePrefixedDOCX(paragraphs: ["Alpha", "Gamma"])
        defer { try? fm.removeItem(at: replacementURL.deletingLastPathComponent()) }

        let store = makeStore(session: session, projectID: Self.applyDocxProjectID)
        store.openProject(id: Self.applyDocxProjectID)

        store.applyRefreshedProjectSource(projectID: Self.applyDocxProjectID, fileURL: replacementURL)

        let summary = try #require(store.sourceRefreshSummary, "prefixed DOCX refresh must publish the retranslate offer")
        #expect(summary.projectID == Self.applyDocxProjectID)
        #expect(summary.matchedBlockCount == 1)
        #expect(summary.addedBlockCount == 1)
        #expect(summary.removedBlockCount == 1)
        #expect(summary.keptTranslationCount == 1)

        let applied = store.projects.first?.session
        #expect(applied?.documentState?.format == .docx, "refresh must import through the DOCX reader path")
        #expect(applied?.sourceFileName == "revised-manuscript.docx")
        #expect(applied?.documentState?.blocks.first?.id == "b1", "matching block must keep its old id")
        let keptTranslation = applied?.documentState?.translationsByLanguage["croatian"]?["b1"]
        #expect(keptTranslation?.text == "Alfa", "matching translation is kept")
        #expect(
            keptTranslation?.sourceHash == applied?.documentState?.blocks.first?.sourceHash,
            "kept translation must realign to the refreshed block hash"
        )
        #expect(applied?.documentState?.blocks.last?.spans.map(\.text).joined() == "Gamma")

        // Rebuilt rows reference the imported copy inside the project dir.
        let expectedPrefix = Self.applyDocxProjectDir.appendingPathComponent("source", isDirectory: true).path
        for chunk in applied?.chunks ?? [] {
            #expect(chunk.filePath.hasPrefix(expectedPrefix))
        }
        #expect(store.statusMessage.hasPrefix("Source refreshed:"))
    }

    /// Builds a minimal two-paragraph DOCX whose ZIP stream is preceded by a
    /// custom header, so the repaired prefixed-offset EOCD/central-directory
    /// resolution is exercised through the full refresh chain:
    /// import → DOCXPackageReader → merge → chunk rebuild.
    private func makePrefixedDOCX(paragraphs: [String]) throws -> URL {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("s20-refresh-docx-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tempDir.appendingPathComponent("word"), withIntermediateDirectories: true)

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

        let paragraphXML = paragraphs.map { "<w:p><w:r><w:t>\($0)</w:t></w:r></w:p>" }.joined()
        let docXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:body>\(paragraphXML)</w:body>
        </w:document>
        """
        try docXML.write(to: tempDir.appendingPathComponent("word/document.xml"), atomically: true, encoding: .utf8)

        let zipURL = tempDir.appendingPathComponent("staged.docx")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = tempDir
        proc.arguments = ["-q", "-r", zipURL.path, "[Content_Types].xml", "_rels", "word"]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "WorkflowStoreRefreshSourceTests", code: 1)
        }

        var prefix = Data("VANISCRIPT_QA_REFRESH_PREFIX".utf8)
        prefix.append(Data(repeating: 0x52, count: 256))
        let prefixed = prefix + (try Data(contentsOf: zipURL))

        let docxURL = tempDir.appendingPathComponent("revised-manuscript.docx")
        try prefixed.write(to: docxURL)
        return docxURL
    }
}
