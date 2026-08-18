import CryptoKit
import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

// S15 extension (PRD §9, ADR-005): per-chunk staleness derivation, sidebar
// summary propagation, export gating, retranslation recovery, and the
// legacy plan-hash migration. Deterministic: no disk I/O (injected
// persistence), no debounce waits (autosave interval injected at 600 s),
// no real model weights.
@MainActor
@Suite("Document staleness gating (PRD §9, ADR-005)")
struct DocumentStalenessGatingTests {
    private func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Two-chunk document session; both translations fresh (hashes match).
    private func makeDocumentSession() -> SessionState {
        let block1 = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .paragraph,
            spans: [RichTextSpan(id: "s1", text: "First paragraph")],
            sourceHash: hash("First paragraph")
        )
        let block2 = DocumentBlock(
            id: "b2",
            location: DocumentLocation(paragraphOrdinal: 1),
            kind: .paragraph,
            spans: [RichTextSpan(id: "s2", text: "Second paragraph")],
            sourceHash: hash("Second paragraph")
        )
        let chunk1 = ChunkData(
            index: 0,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: "First paragraph",
            translated: "Первый абзац",
            status: .pending,
            approved: false,
            sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b1"))
        )
        let chunk2 = ChunkData(
            index: 1,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: "Second paragraph",
            translated: "Второй абзац",
            status: .pending,
            approved: false,
            sourceAnchor: .document(DocumentRange(startBlockID: "b2", endBlockID: "b2"))
        )
        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "src", originalFileName: "doc.docx"),
            blocks: [block1, block2],
            chunks: [
                DocumentChunkPlan(id: "p1", blockIDs: ["b1"]),
                DocumentChunkPlan(id: "p2", blockIDs: ["b2"]),
            ],
            translationsByLanguage: [
                "russian": [
                    "b1": TranslatedBlock(
                        id: "tb1",
                        blockID: "b1",
                        text: "Первый абзац",
                        sourceHash: hash("First paragraph")
                    ),
                    "b2": TranslatedBlock(
                        id: "tb2",
                        blockID: "b2",
                        text: "Второй абзац",
                        sourceHash: hash("Second paragraph")
                    ),
                ],
            ]
        )
        var session = SessionState(
            sourceFile: "/tmp/doc.docx",
            sourceFileName: "doc.docx",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "auto",
            targetLang: "Russian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "mlx-native",
            outputFormats: [.txt],
            chunks: [chunk1, chunk2],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: documentState,
            approvalMode: .manual
        )
        session.activeTranslationLanguage = "Russian"
        return session
    }

    private func makeStore(session: SessionState, projectID: String = "proj-1") -> WorkflowStore {
        let record = ProjectRecord(
            id: projectID,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            session: session
        )
        return WorkflowStore(
            settings: AppSettings.defaults,
            projects: [record],
            settingsPersistence: { _ in },
            projectsPersistence: { _ in },
            autosaveInterval: .seconds(600),
            startInitialModelScan: false
        )
    }

    // MARK: - Per-chunk staleness derivation

    @Test("staleDocumentChunkIndices marks exactly the chunk whose source was edited")
    func staleIndicesMarkOnlyEditedChunk() {
        let store = makeStore(session: makeDocumentSession())
        store.openProject(id: "proj-1")
        #expect(store.staleDocumentChunkIndices == [])
        #expect(store.hasStaleDocumentChunks == false)

        // Edit chunk 2's (zero-based index 1) source text.
        store.selectChunkIndex(1)
        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b2", spans: [RichTextSpan(id: "s2", text: "Second paragraph edited")], text: "Second paragraph edited")],
            text: "Second paragraph edited"
        )

        #expect(store.staleDocumentChunkIndices == [1])
        #expect(store.hasStaleDocumentChunks == true)
        #expect(store.isCurrentDocumentChunkStale == true)

        // The untouched chunk stays unmarked, both at store and session level.
        let session = store.workflow.session!
        #expect(session.staleDocumentChunkIndices(languageKey: "russian") == [1])
        store.selectChunkIndex(0)
        #expect(store.isCurrentDocumentChunkStale == false)
    }

    // MARK: - Sidebar summary propagation

    @Test("ProjectRecord.summary carries stale chunk indices for document sessions only")
    func summaryCarriesStaleChunkIndices() {
        var session = makeDocumentSession()
        // Make chunk 2 genuinely stale: source hash no longer matches translation.
        session.documentState?.blocks[1].sourceHash = hash("Second paragraph edited")

        let record = ProjectRecord(
            id: "proj-1",
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            session: session
        )
        let summary = record.summary
        #expect(summary.staleChunkIndices == [1])
        #expect(summary.isStaleChunk(at: 1) == true)
        #expect(summary.isStaleChunk(at: 0) == false)

        // Media sessions never carry document staleness.
        let mediaSession = SessionState(
            sourceFile: "/tmp/video.mp4",
            sourceFileName: "video.mp4",
            durationSec: 60,
            metadata: .empty,
            sourceLang: "auto",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "",
            outputFormats: [.txt],
            chunks: [
                ChunkData(
                    index: 0,
                    filePath: "/tmp/video.mp4",
                    durationSec: 60,
                    startSec: 0,
                    endSec: 60,
                    original: "Hello",
                    translated: "",
                    status: .pending,
                    approved: false,
                    sourceAnchor: .media(startSec: 0, endSec: 60)
                ),
            ],
            currentChunkIndex: 0
        )
        let mediaRecord = ProjectRecord(
            id: "proj-2",
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            session: mediaSession
        )
        #expect(mediaRecord.summary.staleChunkIndices == [])
    }

    // MARK: - Export gating

    @Test("Document export is blocked while any chunk is stale")
    func exportBlockedWhileStale() {
        let store = makeStore(session: makeDocumentSession())
        store.openProject(id: "proj-1")
        store.selectChunkIndex(1)
        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b2", spans: [RichTextSpan(id: "s2", text: "Second paragraph edited")], text: "Second paragraph edited")],
            text: "Second paragraph edited"
        )
        #expect(store.hasStaleDocumentChunks == true)

        let expected = "Fix the stale chunks (translation doesn't match the source) before exporting."
        store.exportDocument(format: .txt)
        #expect(store.statusMessage == expected)

        store.exportDocumentTranslationPackage()
        #expect(store.statusMessage == expected)
    }

    @Test("Retranslating the stale chunk clears staleness and re-enables export")
    func retranslationClearsStalenessAndUnblocksExport() {
        let store = makeStore(session: makeDocumentSession())
        store.openProject(id: "proj-1")
        store.selectChunkIndex(1)
        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b2", spans: [RichTextSpan(id: "s2", text: "Second paragraph edited")], text: "Second paragraph edited")],
            text: "Second paragraph edited"
        )
        #expect(store.staleDocumentChunkIndices == [1])

        // Retranslate the stale chunk: the translation hash is re-synced.
        store.updateCurrentDocumentTranslated(
            blocks: [(blockID: "b2", spans: [RichTextSpan(id: "ts2", text: "Второй абзац (новый)")], text: "Второй абзац (новый)")],
            text: "Второй абзац (новый)"
        )

        #expect(store.staleDocumentChunkIndices == [])
        #expect(store.hasStaleDocumentChunks == false)
        #expect(store.isCurrentDocumentChunkStale == false)
        let translation = store.workflow.session?.documentState?.translationsByLanguage["russian"]?["b2"]
        #expect(translation?.sourceHash == hash("Second paragraph edited"))
    }

    // MARK: - needsReview clearing (candidate 02 regression guard)

    @Test("needsReview is set by a staling edit and cleared by retranslation")
    func needsReviewClearsAfterRetranslation() {
        let store = makeStore(session: makeDocumentSession())
        store.openProject(id: "proj-1")
        store.selectChunkIndex(1)
        store.workflow.session?.chunks[1].reviewDisposition = .manuallyApproved

        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b2", spans: [RichTextSpan(id: "s2", text: "Second paragraph edited")], text: "Second paragraph edited")],
            text: "Second paragraph edited"
        )
        #expect(store.workflow.session?.chunks[1].reviewDisposition == .needsReview)

        store.updateCurrentDocumentTranslated(
            blocks: [(blockID: "b2", spans: [RichTextSpan(id: "ts2", text: "Второй абзац (новый)")], text: "Второй абзац (новый)")],
            text: "Второй абзац (новый)"
        )
        #expect(store.workflow.session?.chunks[1].reviewDisposition == .pending)
    }

    // MARK: - Empty-hash contract

    @Test("Empty-hash blocks are never stale and approval still succeeds")
    func emptyHashBlocksNeverStaleAndApproveSucceeds() {
        let store = WorkflowStore(
            projects: [],
            settingsPersistence: { _ in },
            projectsPersistence: { _ in },
            startInitialModelScan: false
        )

        let block1 = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .paragraph,
            spans: [RichTextSpan(id: "s1", text: "Source paragraph")]
        )
        let chunk1 = ChunkData(
            index: 0,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: "Source paragraph",
            translated: "Переведенный абзац",
            status: .pending,
            approved: false,
            sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b1"))
        )
        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "src", originalFileName: "doc.docx"),
            blocks: [block1],
            chunks: [DocumentChunkPlan(id: "p1", blockIDs: ["b1"])],
            translationsByLanguage: [
                "russian": [
                    "b1": TranslatedBlock(id: "tb1", blockID: "b1", text: "Переведенный абзац"),
                ],
            ]
        )
        var session = SessionState(
            sourceFile: "/tmp/doc.docx",
            sourceFileName: "doc.docx",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "auto",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "gemini-cloud",
            outputFormats: [.txt],
            chunks: [chunk1],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: documentState,
            approvalMode: .manual
        )
        session.activeTranslationLanguage = "Russian"
        store.workflow.session = session
        store.workflow.screen = .review

        // Empty hashes cannot prove staleness: nothing is marked, nothing blocks.
        #expect(store.staleDocumentChunkIndices == [])
        #expect(store.hasStaleDocumentChunks == false)
        #expect(store.isCurrentDocumentChunkStale == false)

        store.approveAndAdvance()
        #expect(store.workflow.session?.chunks[0].approved == true)
        #expect(store.workflow.screen == .export)
    }

    // MARK: - ProjectSummary backward compatibility

    @Test("ProjectSummary decodes legacy JSON without a staleChunkIndices key")
    func projectSummaryDecodesWithoutStaleChunkIndices() throws {
        // Legacy persisted archives predate PRD §9: the key must be absent
        // from CodingKeys and decode must fall back to an empty set.
        let json = """
        {
          "id": "proj-9",
          "name": "Legacy",
          "sourceFileName": "legacy.docx",
          "sourceMediaInfo": null,
          "updatedAt": "2026-01-01T00:00:00Z",
          "createdAt": "2026-01-01T00:00:00Z",
          "currentIndex": 0,
          "totalChunks": 3,
          "approvedChunks": 1,
          "completedChunks": 1,
          "targetLang": "Russian"
        }
        """
        let summary = try JSONDecoder().decode(ProjectSummary.self, from: Data(json.utf8))
        #expect(summary.staleChunkIndices == [])
        #expect(summary.isStaleChunk(at: 0) == false)

        // Derived-on-read: encoding a stale summary must NOT persist the key.
        var staleSummary = summary
        staleSummary.staleChunkIndices = [0]
        let reencoded = try JSONEncoder().encode(staleSummary)
        let object = try JSONSerialization.jsonObject(with: reencoded) as? [String: Any]
        #expect(object?["staleChunkIndices"] == nil)
        let decoded = try JSONDecoder().decode(ProjectSummary.self, from: reencoded)
        #expect(decoded.staleChunkIndices == [])
    }

    // MARK: - Approve gating disabled state + defense-in-depth guard

    @Test("Approve & Next is blocked while the current chunk is provably stale and allowed once fresh")
    func approveBlockedWhileStaleAndAllowedOnceFresh() throws {
        let store = makeStore(session: makeDocumentSession())
        store.openProject(id: "proj-1")

        // Make chunk 1 stale while chunk 0 stays fresh.
        store.selectChunkIndex(1)
        store.updateCurrentDocumentSource(
            blocks: [(blockID: "b2", spans: [RichTextSpan(id: "s2", text: "Second paragraph edited")], text: "Second paragraph edited")],
            text: "Second paragraph edited"
        )

        // Fresh chunk 0 approves and advances onto the stale chunk.
        store.selectChunkIndex(0)
        #expect(store.isCurrentDocumentChunkStale == false)
        store.approveAndAdvance()
        #expect(store.workflow.session?.chunks[0].approved == true)
        #expect(store.workflow.session?.currentChunkIndex == 1)

        // Button state: the stale chunk reports stale, so the view disables Approve.
        #expect(store.staleDocumentChunkIndices == [1])
        #expect(store.isCurrentDocumentChunkStale == true)

        // Defense in depth: a programmatic approveAndAdvance() must not approve.
        store.approveAndAdvance()
        #expect(store.workflow.session?.chunks[1].approved == false)
        #expect(store.workflow.session?.currentChunkIndex == 1)
        #expect(store.statusMessage == "The source changed — update the translation before approving this chunk.")

        // Resolving the translation re-enables approval end to end.
        store.updateCurrentDocumentTranslated(
            blocks: [(blockID: "b2", spans: [RichTextSpan(id: "ts2", text: "Второй абзац (новый)")], text: "Второй абзац (новый)")],
            text: "Второй абзац (новый)"
        )
        #expect(store.isCurrentDocumentChunkStale == false)
        store.approveAndAdvance()
        #expect(store.workflow.session?.chunks[1].approved == true)
    }

    // MARK: - Media isolation (PRD §9: document-only staleness)

    @Test("Media approval is never gated by document staleness")
    func mediaApprovalNeverBlockedByDocumentStaleness() throws {
        // Hashless document blocks derive .stale yet must not block approve.
        let hashlessBlock = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .paragraph,
            spans: [RichTextSpan(id: "s1", text: "Source paragraph")]
        )
        let hashlessChunk = ChunkData(
            index: 0,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: "Source paragraph",
            translated: "Переведенный абзац",
            status: .pending,
            approved: false,
            sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b1"))
        )
        let docState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "src", originalFileName: "doc.docx"),
            blocks: [hashlessBlock],
            chunks: [DocumentChunkPlan(id: "p1", blockIDs: ["b1"])],
            translationsByLanguage: ["russian": ["b1": TranslatedBlock(id: "tb1", blockID: "b1", text: "Переведенный абзац")]]
        )
        var docSession = SessionState(
            sourceFile: "/tmp/doc.docx",
            sourceFileName: "doc.docx",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "auto",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "",
            outputFormats: [.txt],
            chunks: [hashlessChunk],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: docState,
            approvalMode: .manual
        )
        docSession.activeTranslationLanguage = "Russian"
        // derive says .stale for hashless blocks; approval must still succeed.
        #expect(TranslationFreshness.derive(documentState: docState, blockID: "b1", languageKey: "russian") == .stale)

        // A media session in the same store, with no translation at all.
        let mediaSession = SessionState(
            sourceFile: "/tmp/video.mp4",
            sourceFileName: "video.mp4",
            durationSec: 60,
            metadata: .empty,
            sourceLang: "auto",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "",
            outputFormats: [.txt],
            chunks: [
                ChunkData(
                    index: 0,
                    filePath: "/tmp/video.mp4",
                    durationSec: 60,
                    startSec: 0,
                    endSec: 60,
                    original: "Hello world",
                    translated: "Привет мир",
                    status: .pending,
                    approved: false,
                    sourceAnchor: .media(startSec: 0, endSec: 60)
                ),
            ],
            currentChunkIndex: 0
        )
        let store = WorkflowStore(
            settings: AppSettings.defaults,
            projects: [
                ProjectRecord(id: "proj-doc", createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:00Z", session: docSession),
                ProjectRecord(id: "proj-media", createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:00Z", session: mediaSession),
            ],
            settingsPersistence: { _ in },
            projectsPersistence: { _ in },
            autosaveInterval: .seconds(600),
            startInitialModelScan: false
        )

        store.openProject(id: "proj-doc")
        #expect(store.isCurrentDocumentChunkStale == false)
        store.approveAndAdvance()
        #expect(store.workflow.session?.chunks[0].approved == true)

        store.openProject(id: "proj-media")
        #expect(store.workflow.session?.sourceKind == .media)
        #expect(store.staleDocumentChunkIndices == [])
        #expect(store.hasStaleDocumentChunks == false)
        store.approveAndAdvance()
        #expect(store.workflow.session?.chunks[0].approved == true)
        // Approval must not be blocked by the staleness status message.
        #expect(store.statusMessage != "The source changed — update the translation before approving this chunk.")
    }

    // MARK: - ADR-005 legacy plan-hash migration

    @Test("Normalization migrates legacy plan-hash translations to the block hash")
    func migrationRewritesLegacyPlanHashes() {
        var session = makeDocumentSession()
        // Legacy convention: translation hash equals the composite plan hash.
        session.documentState?.chunks[0].sourceHash = "legacy-plan-hash-1"
        session.documentState?.translationsByLanguage["russian"]?["b1"]?.sourceHash = "legacy-plan-hash-1"
        // Genuinely stale block: hashes differ and match neither plan nor block.
        session.documentState?.chunks[1].sourceHash = "legacy-plan-hash-2"
        session.documentState?.translationsByLanguage["russian"]?["b2"]?.sourceHash = "unrelated-hash"

        #expect(session.staleDocumentChunkIndices(languageKey: "russian") == [0, 1])

        session.normalizeTranslationArchive()

        let translations = session.documentState?.translationsByLanguage["russian"]
        // Legacy entry now matches the current block hash -> fresh.
        #expect(translations?["b1"]?.sourceHash == hash("First paragraph"))
        // Genuinely stale entry is left untouched -> still stale.
        #expect(translations?["b2"]?.sourceHash == "unrelated-hash")
        #expect(session.staleDocumentChunkIndices(languageKey: "russian") == [1])
    }

    @Test("openProject converges migrated hashes into the in-memory project record")
    func openProjectConvergesMigratedHashes() {
        var session = makeDocumentSession()
        session.documentState?.chunks[0].sourceHash = "legacy-plan-hash-1"
        session.documentState?.translationsByLanguage["russian"]?["b1"]?.sourceHash = "legacy-plan-hash-1"

        let store = makeStore(session: session)
        // Before opening, the persisted record still carries the legacy hash.
        #expect(store.projects.first?.session.staleDocumentChunkIndices(languageKey: "russian") == [0])

        store.openProject(id: "proj-1")

        // The sidebar-facing record is migrated immediately, no save required.
        #expect(store.projects.first?.session.staleDocumentChunkIndices(languageKey: "russian") == [])
        #expect(store.hasStaleDocumentChunks == false)
        let migrated = store.projects.first?.session.documentState?.translationsByLanguage["russian"]?["b1"]
        #expect(migrated?.sourceHash == hash("First paragraph"))
    }
}
