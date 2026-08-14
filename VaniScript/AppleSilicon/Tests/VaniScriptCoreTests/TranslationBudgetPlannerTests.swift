import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Translation budget planner")
struct TranslationBudgetPlannerTests {
    @Test("budget arithmetic accounts for every explicit reservation")
    func explicitArithmetic() {
        let capabilities = TranslationModelCapabilities(
            modelID: "arithmetic-test",
            contextWindowTokens: 10_000,
            maxOutputTokens: 2_000,
            recommendedSoftSourceTokens: nil,
            recommendedHardSourceTokens: nil
        )
        let configuration = TranslationBudgetConfiguration(
            promptTokens: 100,
            glossaryTokens: 200,
            rollingContextTokens: 300,
            safetyMarginTokens: 400,
            targetLanguageExpansion: 1.5
        )
        let planner = TranslationBudgetPlanner(capabilities: capabilities, configuration: configuration)
        let budget = planner.budget(forSourceTokenEstimate: 1_000)

        #expect(budget.reservedOutputTokens == 1_500)
        #expect(budget.fixedInputTokens == 1_000)
        #expect(budget.usableContextTokens == 7_500)
        #expect(budget.hardSourceTokenLimit == 1_333)
        #expect(budget.softSourceTokenTarget <= budget.hardSourceTokenLimit)
        #expect(budget.fitsHardLimit)
        #expect(budget.totalReservedTokens == 3_500)
    }

    @Test("hard limit is safe against context and output capacity")
    func hardLimitSafety() {
        let capabilities = TranslationModelCapabilities(
            modelID: "small-test",
            contextWindowTokens: 512,
            maxOutputTokens: 100,
            recommendedSoftSourceTokens: nil,
            recommendedHardSourceTokens: nil
        )
        let configuration = TranslationBudgetConfiguration(
            promptTokens: 20,
            glossaryTokens: 20,
            rollingContextTokens: 20,
            safetyMarginTokens: 20,
            targetLanguageExpansion: 2
        )
        let planner = TranslationBudgetPlanner(capabilities: capabilities, configuration: configuration)
        let limit = planner.budget(forSourceTokenEstimate: 1).hardSourceTokenLimit
        let atLimit = planner.budget(forSourceTokenEstimate: limit)
        let overLimit = planner.budget(forSourceTokenEstimate: limit + 1)
        #expect(limit == 50)
        #expect(atLimit.fitsHardLimit)
        #expect(!overLimit.fitsHardLimit)
        #expect(overLimit.reservedOutputTokens == 100)
    }

    @Test("bounded fallback estimator is deterministic and tokenizer can be injected")
    func fallbackEstimator() {
        let capabilities = TranslationModelCapabilities(
            modelID: "fallback-test",
            contextWindowTokens: 4_096,
            maxOutputTokens: 1_024,
            tokenizerAvailable: false,
            fallbackCharactersPerToken: 4
        )
        let planner = TranslationBudgetPlanner(capabilities: capabilities)
        #expect(planner.estimateTokens("") == 0)
        #expect(planner.estimateTokens("four words") >= 2)
        #expect(planner.estimateTokens("four words") == planner.estimateTokens("four words"))

        let tokenizerPlanner = TranslationBudgetPlanner(
            capabilities: TranslationModelCapabilities(
                modelID: "tokenizer-test",
                contextWindowTokens: 4_096,
                maxOutputTokens: 1_024,
                tokenizerAvailable: true
            ),
            tokenizer: { text in text == "known" ? 7 : 1 }
        )
        #expect(tokenizerPlanner.estimateTokens("known") == 7)
    }

    @Test("target-language expansion changes the reserved output")
    func expansionChangesOutputReservation() {
        let capabilities = TranslationModelCapabilities(
            contextWindowTokens: 8_192,
            maxOutputTokens: 8_192,
            recommendedSoftSourceTokens: nil,
            recommendedHardSourceTokens: nil
        )
        let planner = TranslationBudgetPlanner(capabilities: capabilities)
        let compact = planner.budget(for: TranslationBudgetRequest(sourceTokenEstimate: 400, targetLanguageExpansion: 1.1))
        let expanded = planner.budget(for: TranslationBudgetRequest(sourceTokenEstimate: 400, targetLanguageExpansion: 1.8))
        #expect(compact.reservedOutputTokens < expanded.reservedOutputTokens)
        #expect(compact.usableContextTokens > expanded.usableContextTokens)
    }

    @Test("prompt budget measures serialized text against model capacity")
    func renderedPromptBudget() {
        let capabilities = TranslationModelCapabilities(
            modelID: "prompt-budget-test",
            contextWindowTokens: 256,
            maxOutputTokens: 64,
            fallbackCharactersPerToken: 4
        )
        let planner = TranslationBudgetPlanner(
            capabilities: capabilities,
            configuration: TranslationBudgetConfiguration(
                safetyMarginTokens: 8,
                targetLanguageExpansion: 1.5
            )
        )
        let budget = planner.promptBudget(
            for: String(repeating: "word ", count: 300),
            sourceText: "source text"
        )
        #expect(budget.serializedPromptCharacters > 500)
        #expect(budget.estimatedPromptTokens > 100)
        #expect(budget.reservedOutputTokens > 0)
        #expect(!budget.fits)
        #expect(budget.totalEstimatedTokens > budget.contextWindowTokens)
    }

    @Test("live-shaped 18-block and 37-block synthetic chunks fit within cloudDefault budget")
    func liveShapedSyntheticChunksFitBudget() {
        let planner = TranslationBudgetPlanner(capabilities: .cloudDefault)

        // Synthetic 18-block source text totaling ~6,273 characters (no manuscript content)
        let block18Texts = (1...18).map { i in
            "Synthetic paragraph \(i): " + String(repeating: "narrative sentence \(i). ", count: 14)
        }
        let text18 = block18Texts.joined(separator: "\n\n")
        #expect(abs(text18.count - 6_273) < 500)

        let budget18 = planner.budget(forSourceText: text18)
        #expect(budget18.fitsHardLimit)
        #expect(budget18.sourceTokenEstimate > 1_000 && budget18.sourceTokenEstimate < 2_500)
        #expect(budget18.reservedOutputTokens > 1_500 && budget18.reservedOutputTokens <= 8_192)

        let promptBudget18 = planner.promptBudget(
            for: "SYSTEM:\nprompt\n\nUSER:\n" + text18,
            sourceText: text18
        )
        #expect(promptBudget18.fits)
        #expect(promptBudget18.reservedOutputTokens > 1_500)

        // Synthetic 37-block source text totaling ~7,567 characters (no manuscript content)
        let block37Texts = (1...37).map { i in
            "Synthetic paragraph \(i): " + String(repeating: "descriptive phrase \(i). ", count: 8)
        }
        let text37 = block37Texts.joined(separator: "\n\n")
        #expect(abs(text37.count - 7_567) < 500)

        let budget37 = planner.budget(forSourceText: text37)
        #expect(budget37.fitsHardLimit)
        #expect(budget37.sourceTokenEstimate > 1_200 && budget37.sourceTokenEstimate < 2_600)
        #expect(budget37.reservedOutputTokens > 1_800 && budget37.reservedOutputTokens <= 8_192)

        let promptBudget37 = planner.promptBudget(
            for: "SYSTEM:\nprompt\n\nUSER:\n" + text37,
            sourceText: text37
        )
        #expect(promptBudget37.fits)
        #expect(promptBudget37.reservedOutputTokens > 1_800)
    }
}
