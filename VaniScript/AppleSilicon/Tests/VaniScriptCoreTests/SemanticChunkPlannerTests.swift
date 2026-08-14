import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Semantic document chunk planner")
struct SemanticChunkPlannerTests {
    @Test("planning is deterministic and IDs/hash include the profile")
    func deterministicPlansAndHashes() {
        let blocks = [
            block(id: "chapter", text: "Chapter One", kind: .heading, styleID: "ChapterTitle"),
            block(id: "body-1", text: "The first paragraph carries the voice.") ,
            block(id: "body-2", text: "The second paragraph continues the scene.")
        ]
        let profile = DocumentTranslationProfile(targetLanguage: "Russian")
        let first = SemanticChunkPlanner.plan(blocks: blocks, profile: profile)
        let second = SemanticChunkPlanner.plan(blocks: blocks, profile: profile)
        #expect(first == second)
        #expect(first.map(\.id) == first.map(\.sourceHash).map { "document-chunk-\($0.prefix(20))" })

        let changed = SemanticChunkPlanner.plan(
            blocks: blocks,
            profile: DocumentTranslationProfile(targetLanguage: "French")
        )
        #expect(first.map(\.sourceHash) != changed.map(\.sourceHash))
    }

    @Test("chapter titles are hard boundaries and attach to the next text block")
    func chapterBoundaries() {
        let blocks = [
            block(id: "chapter-1", text: "Chapter One", kind: .heading, styleID: "ChapterTitle"),
            block(id: "body-1", text: "One body paragraph."),
            block(id: "body-2", text: "Another body paragraph."),
            block(id: "chapter-2", text: "Chapter Two", kind: .heading, styleID: "ChapterTitle"),
            block(id: "body-3", text: "The next chapter starts here.")
        ]
        let plans = SemanticChunkPlanner.plan(blocks: blocks, profile: .default)
        let firstChapter = try! #require(plans.first)
        let secondChapter = try! #require(plans.dropFirst().first)
        #expect(firstChapter.blockIDs.contains("chapter-1"))
        #expect(firstChapter.blockIDs.contains("body-1"))
        #expect(!firstChapter.blockIDs.contains("chapter-2"))
        #expect(secondChapter.blockIDs.contains("chapter-2"))
        #expect(secondChapter.blockIDs.contains("body-3"))
    }
    @Test("adjacent quotes and verse styles stay in one atomic group")
    func quoteAndVerseGrouping() {
        let blocks = [
            block(id: "body", text: "The following verse is preserved:"),
            block(id: "quote-1", text: "First quoted line.", kind: .quote, styleID: "Quote"),
            block(id: "verse-1", text: "Second verse line.", kind: .paragraph, styleID: "Verse"),
            block(id: "verse-2", text: "Third verse line.", kind: .paragraph, styleID: "Verse"),
            block(id: "body-after", text: "A closing paragraph.")
        ]
        let plans = SemanticChunkPlanner.plan(blocks: blocks, profile: .default)
        let quotePlan = try! #require(plans.first { $0.blockIDs.contains("quote-1") })
        #expect(quotePlan.blockIDs.contains("verse-1"))
        #expect(quotePlan.blockIDs.contains("verse-2"))
        #expect(quotePlan.blockIDs.firstIndex(of: "quote-1")! < quotePlan.blockIDs.firstIndex(of: "verse-2")!)
    }

    @Test("ordinary paragraphs remain atomic and blanks stay mapped without budget")
    func ordinaryParagraphsAndBlanks() {
        let blocks = [
            block(id: "body-1", text: "An ordinary paragraph is indivisible."),
            block(id: "blank", text: "", kind: .empty),
            block(id: "body-2", text: "A second ordinary paragraph follows.")
        ]
        let plans = SemanticChunkPlanner.plan(blocks: blocks, profile: .default)
        #expect(plans.flatMap(\.blockIDs) == blocks.map(\.id))
        #expect(plans.count == 1)
        #expect(plans[0].sourceTokenEstimate > 0)
        #expect(!plans[0].blockIDs.isEmpty)

        let blankPlan = SemanticChunkPlanner.plan(
            blocks: [block(id: "blank-only", text: "", kind: .empty)],
            profile: .default
        )
        #expect(blankPlan.count == 1)
        #expect(blankPlan[0].sourceTokenEstimate == 0)
    }

    @Test("provider-aware hard limits split only exceptional long paragraphs")
    func hardLimitFallback() {
        let capabilities = TranslationModelCapabilities(
            modelID: "test",
            contextWindowTokens: 256,
            maxOutputTokens: 64,
            recommendedSoftSourceTokens: 20,
            recommendedHardSourceTokens: 40
        )
        let configuration = SemanticChunkPlannerConfiguration(
            capabilities: capabilities,
            budgetConfiguration: TranslationBudgetConfiguration(
                promptTokens: 10,
                glossaryTokens: 5,
                rollingContextTokens: 5,
                safetyMarginTokens: 5,
                targetLanguageExpansion: 1.2
            )
        )
        let longText = (0..<30).map { "Sentence \($0) has enough words to require bounded packing." }.joined(separator: " ")
        let plans = SemanticChunkPlanner.plan(
            blocks: [block(id: "long", text: longText)],
            profile: .default,
            configuration: configuration
        )
        let hard = TranslationBudgetPlanner(capabilities: capabilities, configuration: configuration.budgetConfiguration)
            .budget(forSourceTokenEstimate: 1).hardSourceTokenLimit
        #expect(plans.count > 1)
        #expect(plans.allSatisfy { $0.sourceTokenEstimate <= hard })
        #expect(plans.allSatisfy { $0.blockSlices?.isEmpty == false })
    }

    @Test("context IDs are readonly neighbors and generated books stay bounded")
    func contextAndLargeFixture() {
        let blocks = (0..<872).map { index in
            block(id: "body-\(index)", text: "Paragraph \(index) contains a compact sentence for the synthetic manuscript fixture.")
        }
        let first = SemanticChunkPlanner.plan(blocks: blocks, profile: .default)
        let second = SemanticChunkPlanner.plan(blocks: blocks, profile: .default)
        #expect(first == second)
        #expect(first.count > 0)
        #expect(first.count < 872 / 4)
        for (index, plan) in first.enumerated() {
            #expect(Set(plan.contextBeforeBlockIDs).isDisjoint(with: Set(plan.blockIDs)))
            #expect(Set(plan.contextAfterBlockIDs).isDisjoint(with: Set(plan.blockIDs)))
            if index > 0 {
                #expect(!plan.contextBeforeBlockIDs.isEmpty)
            }
        }
    }

    private static func block(
        id: String,
        text: String,
        kind: DocumentBlockKind = .paragraph,
        styleID: String? = nil
    ) -> DocumentBlock {
        DocumentBlock(
            id: id,
            location: DocumentLocation(paragraphOrdinal: Int(id.split(separator: "-").last ?? "0") ?? 0),
            kind: kind,
            styleID: styleID,
            spans: text.isEmpty ? [] : [RichTextSpan(id: "span-\(id)", text: text)],
            sourceHash: "hash-\(id)"
        )
    }

    private func block(
        id: String,
        text: String,
        kind: DocumentBlockKind = .paragraph,
        styleID: String? = nil
    ) -> DocumentBlock {
        Self.block(id: id, text: text, kind: kind, styleID: styleID)
    }
}
