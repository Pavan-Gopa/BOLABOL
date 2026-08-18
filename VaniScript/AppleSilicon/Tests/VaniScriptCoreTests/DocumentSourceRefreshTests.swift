import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Document source refresh (S20)")
struct DocumentSourceRefreshTests {
    private func block(
        id: String,
        text: String,
        color: String? = nil,
        sourceHash: String? = nil
    ) -> DocumentBlock {
        let spans = [
            RichTextSpan(
                id: "\(id)-s1",
                text: text,
                styleKey: "body",
                foregroundColorHex: color
            )
        ]
        let hash = sourceHash ?? "hash-\(id)-\(text)-\(color ?? "nil")"
        return DocumentBlock(
            id: id,
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .paragraph,
            spans: spans,
            sourceHash: hash
        )
    }

    private func state(
        blocks: [DocumentBlock],
        translations: [String: [String: TranslatedBlock]] = [:],
        glossary: [GlossaryEntry] = []
    ) -> DocumentState {
        var profile = DocumentTranslationProfile.default
        if !glossary.isEmpty {
            profile.projectGlossary = glossary
        }
        profile.targetLanguage = "Croatian"
        return DocumentState(
            format: .txt,
            originalAsset: ProjectAssetReference(key: "sourceFile", originalFileName: "book.txt"),
            blocks: blocks,
            chunks: [],
            translationsByLanguage: translations,
            profile: profile
        )
    }

    private func glossaryEntry(source: String, translation: String) -> GlossaryEntry {
        GlossaryEntry(
            id: "g-\(source)",
            variants: [],
            source: source,
            translation: translation,
            category: nil,
            translations: [:],
            remember: true,
            createdAt: "t",
            updatedAt: "t"
        )
    }

    @Test("formatting-only upgrade keeps translation and realigns sourceHash")
    func formattingOnlyKeepsTranslation() {
        let oldBlock = block(id: "old-1", text: "Printed by [PRINTER, COUNTRY].", color: nil, sourceHash: "old-hash")
        let oldTrans = TranslatedBlock(
            id: "old-1",
            sourceBlockID: "old-1",
            text: "Tiskano od strane [PRINTER, COUNTRY].",
            spans: [RichTextSpan(id: "t1", text: "Tiskano od strane [PRINTER, COUNTRY].")],
            sourceHash: "old-hash",
            reviewDisposition: .manuallyApproved
        )
        let old = state(
            blocks: [oldBlock],
            translations: ["croatian": ["old-1": oldTrans]]
        )

        let newBlock = block(
            id: "new-uuid",
            text: "Printed by [PRINTER, COUNTRY].",
            color: "FF0000",
            sourceHash: "new-hash-with-color"
        )
        let newState = state(blocks: [newBlock])

        let result = DocumentSourceRefresh.merge(old: old, new: newState)

        #expect(result.matchedBlockCount == 1)
        #expect(result.addedBlockCount == 0)
        #expect(result.removedBlockCount == 0)
        #expect(result.keptTranslationCount == 1)
        #expect(result.changedChunkIndices.isEmpty)

        let merged = result.documentState.blocks[0]
        #expect(merged.id == "old-1")
        #expect(merged.spans.first?.foregroundColorHex == "FF0000")
        #expect(merged.sourceHash == "new-hash-with-color")

        let kept = result.documentState.translationsByLanguage["croatian"]?["old-1"]
        #expect(kept?.text == "Tiskano od strane [PRINTER, COUNTRY].")
        #expect(kept?.sourceHash == "new-hash-with-color")
        #expect(kept?.reviewDisposition == .manuallyApproved)
        #expect(
            TranslationFreshness.derive(sourceBlock: merged, translatedBlock: kept) == .fresh
        )
    }

    @Test("text change drops old translation and marks chunks changed")
    func textChangeDropsTranslation() {
        let oldBlock = block(id: "old-1", text: "Hello world", sourceHash: "h1")
        let oldTrans = TranslatedBlock(
            id: "old-1",
            sourceBlockID: "old-1",
            text: "Pozdrav svijete",
            spans: [RichTextSpan(id: "t1", text: "Pozdrav svijete")],
            sourceHash: "h1",
            reviewDisposition: .autoApproved
        )
        let old = state(
            blocks: [oldBlock],
            translations: ["croatian": ["old-1": oldTrans]]
        )
        let newState = state(blocks: [
            block(id: "new-1", text: "Hello brave world", sourceHash: "h2")
        ])

        let result = DocumentSourceRefresh.merge(old: old, new: newState)
        #expect(result.matchedBlockCount == 0)
        #expect(result.addedBlockCount == 1)
        #expect(result.removedBlockCount == 1)
        #expect(result.keptTranslationCount == 0)
        #expect(!result.changedChunkIndices.isEmpty)
        let croatian = result.documentState.translationsByLanguage["croatian"] ?? [:]
        #expect(croatian.isEmpty)
        #expect(result.documentState.blocks[0].id == "new-1")
    }

    @Test("identical duplicate paragraphs match in order without cross-wiring")
    func multisetOrderPreserved() {
        let oldBlocks = [
            block(id: "a", text: "Same", sourceHash: "ha"),
            block(id: "b", text: "Same", sourceHash: "hb")
        ]
        let old = state(
            blocks: oldBlocks,
            translations: [
                "croatian": [
                    "a": TranslatedBlock(
                        id: "a",
                        sourceBlockID: "a",
                        text: "Isto-A",
                        spans: [RichTextSpan(id: "ta", text: "Isto-A")],
                        sourceHash: "ha",
                        reviewDisposition: .manuallyApproved
                    ),
                    "b": TranslatedBlock(
                        id: "b",
                        sourceBlockID: "b",
                        text: "Isto-B",
                        spans: [RichTextSpan(id: "tb", text: "Isto-B")],
                        sourceHash: "hb",
                        reviewDisposition: .manuallyApproved
                    )
                ]
            ]
        )
        let newState = state(blocks: [
            block(id: "n1", text: "Same", color: "FF0000", sourceHash: "hn1"),
            block(id: "n2", text: "Same", color: "00FF00", sourceHash: "hn2")
        ])

        let result = DocumentSourceRefresh.merge(old: old, new: newState)
        #expect(result.matchedBlockCount == 2)
        #expect(result.documentState.blocks.map(\.id) == ["a", "b"])
        #expect(result.documentState.blocks[0].spans.first?.foregroundColorHex == "FF0000")
        #expect(result.documentState.blocks[1].spans.first?.foregroundColorHex == "00FF00")
        #expect(result.documentState.translationsByLanguage["croatian"]?["a"]?.text == "Isto-A")
        #expect(result.documentState.translationsByLanguage["croatian"]?["b"]?.text == "Isto-B")
        #expect(result.documentState.translationsByLanguage["croatian"]?["a"]?.sourceHash == "hn1")
        #expect(result.documentState.translationsByLanguage["croatian"]?["b"]?.sourceHash == "hn2")
        #expect(result.changedChunkIndices.isEmpty)
    }

    @Test("empty old translations marks every plan index changed")
    func emptyTranslationsAllChanged() {
        let old = state(blocks: [block(id: "o1", text: "One")])
        let newState = state(blocks: [
            block(id: "n1", text: "One"),
            block(id: "n2", text: "Two")
        ])
        let result = DocumentSourceRefresh.merge(old: old, new: newState)
        #expect(result.matchedBlockCount == 1)
        #expect(result.addedBlockCount == 1)
        #expect(result.keptTranslationCount == 0)
        #expect(result.changedChunkIndices == Array(result.documentState.chunks.indices))
    }

    @Test("rebuildSessionChunks count equals plan count and marks changed pending")
    func rebuildSessionChunksBasic() {
        let oldBlock = block(id: "old-1", text: "Alpha", sourceHash: "h1")
        let oldTrans = TranslatedBlock(
            id: "old-1",
            sourceBlockID: "old-1",
            text: "Alfa",
            spans: [RichTextSpan(id: "t", text: "Alfa")],
            sourceHash: "h1",
            reviewDisposition: .manuallyApproved
        )
        let old = state(
            blocks: [oldBlock],
            translations: ["croatian": ["old-1": oldTrans]]
        )
        let newState = state(blocks: [
            block(id: "n1", text: "Alpha", sourceHash: "h1b"),
            block(id: "n2", text: "Beta", sourceHash: "h2")
        ])
        let merged = DocumentSourceRefresh.merge(old: old, new: newState)
        let chunks = DocumentSourceRefresh.rebuildSessionChunks(
            oldChunks: [
                ChunkData(
                    index: 0,
                    filePath: "/tmp/old.txt",
                    durationSec: 0,
                    startSec: 0,
                    endSec: 0,
                    original: "Alpha",
                    translated: "Alfa",
                    status: .done,
                    approved: true,
                    sourceAnchor: .document(DocumentRange(startBlockID: "old-1", endBlockID: "old-1"))
                )
            ],
            documentState: merged.documentState,
            sourceFilePath: "/tmp/new.txt",
            preferredLanguageKey: "croatian",
            changedChunkIndices: merged.changedChunkIndices
        )

        #expect(chunks.count == merged.documentState.chunks.count)
        #expect(chunks.allSatisfy { $0.filePath == "/tmp/new.txt" })
        #expect(!merged.changedChunkIndices.isEmpty)
        for index in merged.changedChunkIndices {
            #expect(chunks[index].status == .pending || chunks[index].reviewDisposition == .needsReview)
        }
        if let alphaIndex = merged.documentState.chunks.firstIndex(where: { $0.blockIDs == ["old-1"] }) {
            #expect(chunks[alphaIndex].translated == "Alfa")
        }
    }

    @Test("text identity is NFC-stable and ignores block id")
    func textIdentityIgnoresID() {
        let a = block(id: "1", text: "Café")
        let b = block(id: "2", text: "Café")
        #expect(DocumentSourceRefresh.textIdentity(for: a) == DocumentSourceRefresh.textIdentity(for: b))
        let c = block(id: "3", text: "Cafe")
        #expect(DocumentSourceRefresh.textIdentity(for: a) != DocumentSourceRefresh.textIdentity(for: c))
    }

    @Test("old glossary survives when new import has empty glossary")
    func preservesOldGlossary() {
        let entry = glossaryEntry(source: "Name", translation: "Ime")
        let old = state(
            blocks: [block(id: "o", text: "Name")],
            glossary: [entry]
        )
        var newProfile = DocumentTranslationProfile.default
        newProfile.projectGlossary = []
        let newState = DocumentState(
            format: .txt,
            blocks: [block(id: "n", text: "Name")],
            profile: newProfile
        )
        let result = DocumentSourceRefresh.merge(old: old, new: newState)
        #expect(result.documentState.profile.projectGlossary == [entry])
    }

    @Test("changed chunk with partial surviving translation needs review, and prior timing follows the row index")
    func changedChunkPartialTranslationNeedsReview() {
        // Old: A kept identical, B rewritten, C added by the refresh.
        let oldTransA = TranslatedBlock(
            id: "a",
            sourceBlockID: "a",
            text: "Zadrži jedan",
            spans: [RichTextSpan(id: "ta", text: "Zadrži jedan")],
            sourceHash: "ha",
            reviewDisposition: .manuallyApproved
        )
        let oldTransB = TranslatedBlock(
            id: "b",
            sourceBlockID: "b",
            text: "Promijeni me",
            spans: [RichTextSpan(id: "tb", text: "Promijeni me")],
            sourceHash: "hb",
            reviewDisposition: .manuallyApproved
        )
        let old = state(
            blocks: [
                block(id: "a", text: "Keep one", sourceHash: "ha"),
                block(id: "b", text: "Change me", sourceHash: "hb"),
            ],
            translations: ["croatian": ["a": oldTransA, "b": oldTransB]]
        )
        let newState = state(blocks: [
            block(id: "n-a", text: "Keep one", color: "FF0000", sourceHash: "hna"),
            block(id: "n-b", text: "Changed now", sourceHash: "hnb"),
            block(id: "n-c", text: "Fresh", sourceHash: "hnc"),
        ])
        let merged = DocumentSourceRefresh.merge(old: old, new: newState)

        let oldChunks = [
            ChunkData(index: 0, filePath: "/tmp/old.txt", durationSec: 12.5, startSec: 1, endSec: 13.5, original: "Keep one", translated: "Zadrži jedan", status: .done, approved: true),
            ChunkData(index: 1, filePath: "/tmp/old.txt", durationSec: 7.5, startSec: 14, endSec: 21.5, original: "Change me", translated: "Promijeni me", status: .done, approved: true),
        ]
        let chunks = DocumentSourceRefresh.rebuildSessionChunks(
            oldChunks: oldChunks,
            documentState: merged.documentState,
            sourceFilePath: "/tmp/new.txt",
            preferredLanguageKey: "croatian",
            changedChunkIndices: merged.changedChunkIndices
        )

        #expect(chunks.count == merged.documentState.chunks.count)
        #expect(!merged.changedChunkIndices.isEmpty)

        // Every changed plan contains at least one block without a Croatian
        // translation, so none may stay silently approved.
        let changed = Set(merged.changedChunkIndices)
        for index in merged.changedChunkIndices {
            let plan = merged.documentState.chunks[index]
            let row = chunks[index]
            #expect(!row.reviewDisposition.isApproved)
            if plan.blockIDs.contains("a") {
                // The kept Croatian row survives in the aggregate text while
                // the whole chunk drops to needsReview for rework.
                #expect(row.reviewDisposition == .needsReview)
                #expect(row.status == .pending)
                #expect(row.translated.contains("Zadrži jedan"))
            } else {
                #expect(row.reviewDisposition == .pending)
                #expect(row.status == .pending)
            }
        }

        // A plan left fully matched and approved keeps done+approved and is
        // not offered for retranslation.
        for (index, plan) in merged.documentState.chunks.enumerated() where plan.blockIDs == ["a"] {
            #expect(!changed.contains(index))
            #expect(chunks[index].status == .done)
            #expect(chunks[index].reviewDisposition == .manuallyApproved)
            #expect(chunks[index].approved)
            #expect(chunks[index].translated == "Zadrži jedan")
        }

        // Timing fields are preserved strictly by row index: rows beyond the
        // old chunk array start from zero (chunk count grew via the refresh).
        for (index, row) in chunks.enumerated() {
            if index < oldChunks.count {
                #expect(row.durationSec == oldChunks[index].durationSec)
                #expect(row.startSec == oldChunks[index].startSec)
                #expect(row.endSec == oldChunks[index].endSec)
            } else {
                #expect(row.durationSec == 0)
                #expect(row.startSec == 0)
                #expect(row.endSec == 0)
            }
        }
    }

    @Test("chunk changed only for a non-preferred language keeps its complete preferred translation done and unapproved")
    func changedOnlyForOtherLanguageKeepsPreferredDone() {
        // Formatting-only refresh: every block matches. Croatian covers both
        // blocks; German misses block B, so plans containing B are changed —
        // but their preferred Croatian aggregate is still fully present.
        let croatianA = TranslatedBlock(id: "a", sourceBlockID: "a", text: "Prvi", sourceHash: "ha", reviewDisposition: .manuallyApproved)
        let croatianB = TranslatedBlock(id: "b", sourceBlockID: "b", text: "Drugi", sourceHash: "hb", reviewDisposition: .pending)
        let germanA = TranslatedBlock(id: "a", sourceBlockID: "a", text: "Erste", sourceHash: "ha", reviewDisposition: .manuallyApproved)
        let old = state(
            blocks: [
                block(id: "a", text: "First", sourceHash: "ha"),
                block(id: "b", text: "Second", sourceHash: "hb"),
            ],
            translations: [
                "croatian": ["a": croatianA, "b": croatianB],
                "german": ["a": germanA],
            ]
        )
        let newState = state(blocks: [
            block(id: "n-a", text: "First", color: "00FF00", sourceHash: "hna"),
            block(id: "n-b", text: "Second", color: "0000FF", sourceHash: "hnb"),
        ])
        let merged = DocumentSourceRefresh.merge(old: old, new: newState)

        #expect(merged.matchedBlockCount == 2)
        // German's gap on block B flags every plan containing B, even though
        // the preferred Croatian map is complete for both blocks.
        let plans = merged.documentState.chunks
        let plansWithB = plans.indices.filter { plans[$0].blockIDs.contains("b") }
        #expect(Set(merged.changedChunkIndices) == Set(plansWithB))

        let chunks = DocumentSourceRefresh.rebuildSessionChunks(
            oldChunks: [],
            documentState: merged.documentState,
            sourceFilePath: "/tmp/new.txt",
            preferredLanguageKey: "croatian",
            changedChunkIndices: merged.changedChunkIndices
        )
        // Croatian is complete for every plan, so a changed row keeps .done
        // and its aggregate text — but must not re-derive approval from the
        // partially approved plan (chunk A approved, chunk B pending).
        for index in merged.changedChunkIndices {
            #expect(chunks[index].status == .done)
            #expect(chunks[index].reviewDisposition == .pending)
            #expect(!chunks[index].approved)
            #expect(chunks[index].translated.contains("Drugi"))
        }
        let plansWithoutB = Set(plans.indices).subtracting(plansWithB)
        for index in plansWithoutB {
            #expect(chunks[index].status == .done)
            #expect(chunks[index].reviewDisposition == .manuallyApproved)
            #expect(chunks[index].approved)
        }
    }
}
