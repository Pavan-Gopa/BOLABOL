import CryptoKit
import Foundation
import Testing
@testable import VaniScriptCore

@Suite("DocumentTranslationFreshness (PRD §9, §26.4)")
struct DocumentTranslationFreshnessTests {
    private func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func sourceBlock(text: String = "Source paragraph") -> DocumentBlock {
        DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .paragraph,
            spans: [RichTextSpan(id: "s1", text: text)],
            sourceHash: hash(text)
        )
    }

    private func translatedBlock(sourceText: String, text: String = "Переведенный абзац") -> TranslatedBlock {
        TranslatedBlock(
            id: "tb1",
            blockID: "b1",
            text: text,
            sourceHash: hash(sourceText)
        )
    }

    @Test("No translation derives missing")
    func missingTranslation() {
        let freshness = TranslationFreshness.derive(sourceBlock: sourceBlock(), translatedBlock: nil)
        #expect(freshness == .missing)
    }

    @Test("Matching source hashes derive fresh")
    func matchingHashesAreFresh() {
        let freshness = TranslationFreshness.derive(
            sourceBlock: sourceBlock(text: "Source paragraph"),
            translatedBlock: translatedBlock(sourceText: "Source paragraph")
        )
        #expect(freshness == .fresh)
    }

    @Test("Source typo changes hash and derives stale")
    func sourceTypoIsStale() {
        let freshness = TranslationFreshness.derive(
            sourceBlock: sourceBlock(text: "Source paragraph with typo fix"),
            translatedBlock: translatedBlock(sourceText: "Source paragraph")
        )
        #expect(freshness == .stale)
    }

    @Test("Empty hashes never derive fresh")
    func emptyHashesAreStale() {
        var block = sourceBlock()
        block.sourceHash = ""
        var translation = translatedBlock(sourceText: "Source paragraph")
        translation.sourceHash = ""
        #expect(TranslationFreshness.derive(sourceBlock: block, translatedBlock: translation) == .stale)
    }

    @Test("Orphaned translation without source block derives stale")
    func orphanedTranslationIsStale() {
        let freshness = TranslationFreshness.derive(
            sourceBlock: nil,
            translatedBlock: translatedBlock(sourceText: "Source paragraph")
        )
        #expect(freshness == .stale)
    }

    // MARK: - isProvablyStale (gating predicate, PRD §9)

    /// Gating (approval, export, sidebar red) uses isProvablyStale, not
    /// derive: a hash that merely cannot prove freshness must never block a
    /// user action. These tests pin that predicate independent of derive.
    @Test("isProvablyStale requires both hashes present and different")
    func isProvablyStaleRequiresMismatchedNonEmptyHashes() {
        var block = sourceBlock()
        let translation = translatedBlock(sourceText: "different text")

        let state = { (block: DocumentBlock, translation: TranslatedBlock?) in
            DocumentState(
                format: .docx,
                originalAsset: ProjectAssetReference(key: "src", originalFileName: "doc.docx"),
                blocks: [block],
                chunks: [DocumentChunkPlan(id: "p1", blockIDs: ["b1"])],
                translationsByLanguage: ["russian": translation.map { ["b1": $0] } ?? [:]]
            )
        }

        // Mismatching non-empty hashes: provably stale.
        #expect(TranslationFreshness.isProvablyStale(documentState: state(block, translation), blockID: "b1", languageKey: "russian") == true)

        // Matching hashes: fresh, never provably stale.
        block.sourceHash = translation.sourceHash
        #expect(TranslationFreshness.isProvablyStale(documentState: state(block, translation), blockID: "b1", languageKey: "russian") == false)

        // Empty hash on either side proves nothing: derive says .stale, but
        // isProvablyStale must stay false so hashless blocks still approve.
        var emptySource = block
        emptySource.sourceHash = ""
        #expect(TranslationFreshness.isProvablyStale(documentState: state(emptySource, translation), blockID: "b1", languageKey: "russian") == false)
        var emptyTranslation = translation
        emptyTranslation.sourceHash = ""
        #expect(TranslationFreshness.isProvablyStale(documentState: state(block, emptyTranslation), blockID: "b1", languageKey: "russian") == false)

        // Missing translations / unknown blocks are never provably stale.
        #expect(TranslationFreshness.isProvablyStale(documentState: state(block, nil), blockID: "b1", languageKey: "russian") == false)
        #expect(TranslationFreshness.isProvablyStale(documentState: state(block, translation), blockID: "unknown", languageKey: "russian") == false)
        #expect(TranslationFreshness.isProvablyStale(documentState: state(block, translation), blockID: "b1", languageKey: "german") == false)
    }

    @Test("DocumentState overload resolves block and language keys")
    func documentStateDerive() {
        let sourceText = "Source paragraph"
        let documentState = DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "src", originalFileName: "doc.docx"),
            blocks: [sourceBlock(text: sourceText)],
            chunks: [DocumentChunkPlan(id: "p1", blockIDs: ["b1"])],
            translationsByLanguage: [
                "russian": ["b1": translatedBlock(sourceText: sourceText)],
                "german": ["b1": translatedBlock(sourceText: "Old text")],
            ]
        )
        #expect(TranslationFreshness.derive(documentState: documentState, blockID: "b1", languageKey: "russian") == .fresh)
        #expect(TranslationFreshness.derive(documentState: documentState, blockID: "b1", languageKey: "german") == .stale)
        #expect(TranslationFreshness.derive(documentState: documentState, blockID: "b1", languageKey: "french") == .missing)
        #expect(TranslationFreshness.derive(documentState: documentState, blockID: "missing", languageKey: "russian") == .missing)
    }
}
