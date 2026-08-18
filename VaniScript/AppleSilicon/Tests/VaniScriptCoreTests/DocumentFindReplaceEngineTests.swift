import Foundation
import Testing
@testable import VaniScriptCore

// S16 (PRD §11, §25, §26.6, ADR-E2): the pure document find/replace engine.
// Deterministic: no store, no disk, no model weights — only DocumentState IR.
@Suite("DocumentFindReplaceEngine (PRD §11, §25, ADR-E2)")
struct DocumentFindReplaceEngineTests {

    private func block(
        id: String,
        spans: [RichTextSpan],
        policy: BlockTranslationPolicy = .translate,
        ordinal: Int = 0
    ) -> DocumentBlock {
        DocumentBlock(
            id: id,
            location: DocumentLocation(paragraphOrdinal: ordinal),
            kind: .paragraph,
            spans: spans,
            sourceHash: "",
            translationPolicy: policy
        )
    }

    private func document(
        blocks: [DocumentBlock],
        translations: [String: [String: TranslatedBlock]] = [:]
    ) -> DocumentState {
        DocumentState(
            format: .docx,
            originalAsset: ProjectAssetReference(key: "src", originalFileName: "doc.docx"),
            blocks: blocks,
            chunks: blocks.map { DocumentChunkPlan(id: "p-\($0.id)", blockIDs: [$0.id]) },
            translationsByLanguage: translations
        )
    }

    // MARK: - 1. Whole-word Unicode boundaries

    @Test("Whole-word matching rejects matches inside longer Unicode words")
    func wholeWordUnicodeBoundaries() {
        // Cyrillic: "Рама" must not match inside "Рамаяна"; punctuation and
        // whitespace neighbours are accepted.
        let doc = document(blocks: [
            block(id: "b1", spans: [RichTextSpan(id: "s1", text: "Рамаяна и Рама, Рама.")]),
        ])
        let report = DocumentFindReplaceEngine.matches(
            in: doc,
            scope: .currentSourceDocument,
            query: "Рама",
            options: DocumentFindReplaceOptions()
        )
        #expect(report.foundCount == 2)
        #expect(report.skippedMixedStyleCount == 0)

        // Devanagari: "राम" must not match when a letter (क) follows it.
        // Note: the mandated \p{L}\p{N}_ boundary (verbatim GlossaryTextRewriter
        // behavior) does not reject vowel signs (\p{M}), so the neighbour here
        // is a consonant.
        let devanagari = document(blocks: [
            block(id: "b1", spans: [RichTextSpan(id: "s1", text: "रामकथा राम")]),
        ])
        let devanagariReport = DocumentFindReplaceEngine.matches(
            in: devanagari,
            scope: .currentSourceDocument,
            query: "राम",
            options: DocumentFindReplaceOptions()
        )
        #expect(devanagariReport.foundCount == 1)
        let substringReport = DocumentFindReplaceEngine.matches(
            in: doc,
            scope: .currentSourceDocument,
            query: "Рама",
            options: DocumentFindReplaceOptions(wholeWord: false)
        )
        #expect(substringReport.foundCount == 3)
    }

    // MARK: - 2/3. Case sensitivity

    @Test("Case-sensitive matching distinguishes rama from Rama")
    func caseSensitiveOn() {
        let doc = document(blocks: [block(id: "b1", spans: [RichTextSpan(id: "s1", text: "Rama")])])
        let report = DocumentFindReplaceEngine.matches(
            in: doc,
            scope: .currentSourceDocument,
            query: "rama",
            options: DocumentFindReplaceOptions(caseSensitive: true)
        )
        #expect(report.foundCount == 0)
    }

    @Test("Case-insensitive default matches Rama with query rama")
    func caseInsensitiveDefault() {
        let doc = document(blocks: [block(id: "b1", spans: [RichTextSpan(id: "s1", text: "Rama")])])
        let report = DocumentFindReplaceEngine.matches(
            in: doc,
            scope: .currentSourceDocument,
            query: "rama",
            options: DocumentFindReplaceOptions()
        )
        #expect(report.foundCount == 1)
    }

    // MARK: - 4. Protected spans

    @Test("Protected matches are skipped and counted, or included when not skipping")
    func protectedMatches() {
        let doc = document(blocks: [
            block(id: "b1", spans: [RichTextSpan(id: "s1", text: "cat", translationPolicy: .protect)]),
        ])

        let skipped = DocumentFindReplaceEngine.matches(
            in: doc,
            scope: .currentSourceDocument,
            query: "cat",
            options: DocumentFindReplaceOptions()
        )
        #expect(skipped.foundCount == 0)
        #expect(skipped.skippedProtectedCount == 1)

        let included = DocumentFindReplaceEngine.matches(
            in: doc,
            scope: .currentSourceDocument,
            query: "cat",
            options: DocumentFindReplaceOptions(skipProtected: false)
        )
        #expect(included.foundCount == 1)
        #expect(included.skippedProtectedCount == 0)
        #expect(included.matchesByBlock["b1"]?.first?.protectedMatch == true)

        // Block-level protect behaves like span-level protect.
        let blockProtected = document(blocks: [
            block(id: "b1", spans: [RichTextSpan(id: "s1", text: "cat")], policy: .protect),
        ])
        let blockReport = DocumentFindReplaceEngine.matches(
            in: blockProtected,
            scope: .currentSourceDocument,
            query: "cat",
            options: DocumentFindReplaceOptions()
        )
        #expect(blockReport.foundCount == 0)
        #expect(blockReport.skippedProtectedCount == 1)
    }

    // MARK: - 5. Mixed-style matches

    @Test("Mixed-style matches are skipped and counted; same-style multi-span matches replace")
    func mixedStyleMatches() {
        let mixed = document(blocks: [
            block(id: "b1", spans: [
                RichTextSpan(id: "s1", text: "Ra", traits: [.bold]),
                RichTextSpan(id: "s2", text: "ma"),
            ]),
        ])
        let mixedReport = DocumentFindReplaceEngine.matches(
            in: mixed,
            scope: .currentSourceDocument,
            query: "Rama",
            options: DocumentFindReplaceOptions(wholeWord: false)
        )
        #expect(mixedReport.foundCount == 0)
        #expect(mixedReport.skippedMixedStyleCount == 1)
        // Mixed-style matches never appear as replaceable matches.
        #expect(mixedReport.matchesByBlock.isEmpty)

        let plan = DocumentFindReplaceEngine.plan(
            in: mixed,
            scope: .currentSourceDocument,
            query: "Rama",
            replacement: "Sita",
            options: DocumentFindReplaceOptions(wholeWord: false)
        )
        #expect(plan == nil)

        // Same effective style across spans: the match is replaceable and the
        // replacement inherits the shared style.
        let sameStyle = document(blocks: [
            block(id: "b1", spans: [
                RichTextSpan(id: "s1", text: "Ra", styleKey: "Heading1"),
                RichTextSpan(id: "s2", text: "ma", styleKey: "Heading1"),
            ]),
        ])
        let sameStylePlan = DocumentFindReplaceEngine.plan(
            in: sameStyle,
            scope: .currentSourceDocument,
            query: "Rama",
            replacement: "Sita",
            options: DocumentFindReplaceOptions(wholeWord: false)
        )
        #expect(sameStylePlan?.report.foundCount == 1)
        let patch = sameStylePlan?.patches.first
        #expect(patch?.text == "Sita")
        #expect(patch?.spans.first?.styleKey == "Heading1")
    }

    // MARK: - 6. Formatting preservation

    @Test("Replacement inherits the host span formatting and keeps span identity")
    func formattingPreserved() {
        let doc = document(blocks: [
            block(id: "b1", spans: [
                RichTextSpan(
                    id: "s1",
                    text: "old term",
                    styleKey: "Heading1",
                    traits: [.bold],
                    foregroundColorHex: "FF0000"
                ),
            ]),
        ])
        let plan = DocumentFindReplaceEngine.plan(
            in: doc,
            scope: .currentSourceDocument,
            query: "term",
            replacement: "word",
            options: DocumentFindReplaceOptions()
        )
        let patch = plan?.patches.first
        #expect(patch?.text == "old word")
        #expect(patch?.spans.count == 1)
        // Single-span match keeps the span identity (INV-3).
        #expect(patch?.spans.first?.id == "s1")
        #expect(patch?.spans.first?.styleKey == "Heading1")
        #expect(patch?.spans.first?.traits == [.bold])
        #expect(patch?.spans.first?.foregroundColorHex == "FF0000")
    }

    // MARK: - 7. Zero matches

    @Test("Plan is nil for zero matches and empty queries")
    func zeroMatchPlanIsNil() {
        let doc = document(blocks: [block(id: "b1", spans: [RichTextSpan(id: "s1", text: "cat")])])
        #expect(DocumentFindReplaceEngine.plan(
            in: doc,
            scope: .currentSourceDocument,
            query: "zebra",
            replacement: "dog",
            options: DocumentFindReplaceOptions()
        ) == nil)
        #expect(DocumentFindReplaceEngine.plan(
            in: doc,
            scope: .currentSourceDocument,
            query: "",
            replacement: "dog",
            options: DocumentFindReplaceOptions()
        ) == nil)
        #expect(DocumentFindReplaceEngine.plan(
            in: doc,
            scope: .currentSourceDocument,
            query: "   ",
            replacement: "dog",
            options: DocumentFindReplaceOptions()
        ) == nil)
    }

    // MARK: - 8. Scope isolation (active language only, ADR-E2)

    @Test("Translation scope searches exactly the active language; source scope never searches translations")
    func scopeIsolation() {
        let doc = document(
            blocks: [block(id: "b1", spans: [RichTextSpan(id: "s1", text: "dog")])],
            translations: [
                "russian": [
                    "b1": TranslatedBlock(
                        id: "tb1",
                        blockID: "b1",
                        text: "cat",
                        spans: [RichTextSpan(id: "ts1", text: "cat")],
                        sourceHash: "h1"
                    ),
                ],
                "spanish": [
                    "b1": TranslatedBlock(
                        id: "tb2",
                        blockID: "b1",
                        text: "cat",
                        spans: [RichTextSpan(id: "ts2", text: "cat")],
                        sourceHash: "h1"
                    ),
                ],
            ]
        )

        // Russian only: the Spanish translation and the source are not searched.
        let russian = DocumentFindReplaceEngine.matches(
            in: doc,
            scope: .currentTranslation(languageKey: "russian"),
            query: "cat",
            options: DocumentFindReplaceOptions()
        )
        #expect(russian.foundCount == 1)
        #expect(russian.matchesByBlock["b1"]?.first?.languageKey == "russian")
        #expect(russian.matchesByBlock["b1"]?.first?.side == .translation)

        // Source scope never searches translations: "cat" exists only there.
        let source = DocumentFindReplaceEngine.matches(
            in: doc,
            scope: .currentSourceDocument,
            query: "cat",
            options: DocumentFindReplaceOptions()
        )
        #expect(source.foundCount == 0)

        // A language without translations yields nothing.
        let french = DocumentFindReplaceEngine.matches(
            in: doc,
            scope: .currentTranslation(languageKey: "french"),
            query: "cat",
            options: DocumentFindReplaceOptions()
        )
        #expect(french.foundCount == 0)

        // A translated block with empty spans contributes nothing (no
        // fabricated spans).
        let textOnly = document(
            blocks: [block(id: "b1", spans: [RichTextSpan(id: "s1", text: "dog")])],
            translations: [
                "russian": ["b1": TranslatedBlock(id: "tb1", blockID: "b1", text: "cat", spans: [], sourceHash: "h1")],
            ]
        )
        let textOnlyReport = DocumentFindReplaceEngine.matches(
            in: textOnly,
            scope: .currentTranslation(languageKey: "russian"),
            query: "cat",
            options: DocumentFindReplaceOptions()
        )
        #expect(textOnlyReport.foundCount == 0)
    }

    // MARK: - 9. Back-to-front application

    @Test("Multiple matches in one block apply without offset drift")
    func backToFrontApplication() {
        let doc = document(blocks: [
            block(id: "b1", spans: [RichTextSpan(id: "s1", text: "cat and cat and cat")]),
        ])
        let plan = DocumentFindReplaceEngine.plan(
            in: doc,
            scope: .currentSourceDocument,
            query: "cat",
            replacement: "dog",
            options: DocumentFindReplaceOptions()
        )
        #expect(plan?.report.foundCount == 3)
        #expect(plan?.patches.first?.text == "dog and dog and dog")

        // Matches distributed across adjacent same-style spans.
        let multiSpan = document(blocks: [
            block(id: "b1", spans: [
                RichTextSpan(id: "s1", text: "cat and "),
                RichTextSpan(id: "s2", text: "cat"),
            ]),
        ])
        let multiPlan = DocumentFindReplaceEngine.plan(
            in: multiSpan,
            scope: .currentSourceDocument,
            query: "cat",
            replacement: "dog",
            options: DocumentFindReplaceOptions()
        )
        #expect(multiPlan?.report.foundCount == 2)
        #expect(multiPlan?.patches.first?.text == "dog and dog")

        // A replacement longer than the match keeps later matches correct.
        let longer = document(blocks: [
            block(id: "b1", spans: [RichTextSpan(id: "s1", text: "cat cat")]),
        ])
        let longerPlan = DocumentFindReplaceEngine.plan(
            in: longer,
            scope: .currentSourceDocument,
            query: "cat",
            replacement: "elephant",
            options: DocumentFindReplaceOptions()
        )
        #expect(longerPlan?.patches.first?.text == "elephant elephant")
    }

    // MARK: - 10. Block boundaries

    @Test("Matches never cross block boundaries")
    func noCrossBlockMatches() {
        let doc = document(blocks: [
            block(id: "b1", spans: [RichTextSpan(id: "s1", text: "Ra")], ordinal: 0),
            block(id: "b2", spans: [RichTextSpan(id: "s2", text: "ma")], ordinal: 1),
        ])
        let report = DocumentFindReplaceEngine.matches(
            in: doc,
            scope: .currentSourceDocument,
            query: "Rama",
            options: DocumentFindReplaceOptions(wholeWord: false)
        )
        #expect(report.foundCount == 0)
    }

    // MARK: - Report shape

    @Test("Report counts replaceable matches and distinct blocks")
    func reportShape() {
        let doc = document(blocks: [
            block(id: "b1", spans: [RichTextSpan(id: "s1", text: "cat and cat")], ordinal: 0),
            block(id: "b2", spans: [RichTextSpan(id: "s2", text: "no match here")], ordinal: 1),
            block(id: "b3", spans: [RichTextSpan(id: "s3", text: "cat")], ordinal: 2),
        ])
        let report = DocumentFindReplaceEngine.matches(
            in: doc,
            scope: .currentSourceDocument,
            query: "cat",
            options: DocumentFindReplaceOptions()
        )
        #expect(report.foundCount == 3)
        #expect(report.blockCount == 2)
        #expect(report.matchesByBlock.count == 2)
        #expect(report.matchesByBlock["b1"]?.count == 2)
        #expect(report.matchesByBlock["b3"]?.count == 1)
        #expect(report.matchesByBlock["b2"] == nil)
    }
}
