import Testing
@testable import VaniScriptCore

@Suite("Native LLM prompts")
struct NativeLLMPromptTests {
    @Test("builds translation prompt with metadata and glossary")
    func buildsTranslationPrompt() {
        let prompt = NativeLLMPromptBuilder.translationPrompt(
            text: "Hare Krishna",
            targetLang: "Russian",
            metadata: AudioMetadata(date: "2026-05-25", location: "Mayapur", lecturer: "HH Kadamba Kanana Swami", participants: ""),
            glossary: [
                GlossaryEntry(id: "1", variants: ["Krishna"], source: "Krishna", translation: "Кришна", category: "name", translations: ["Russian": "Кришна"], remember: true, createdAt: "", updatedAt: "")
            ]
        )

        #expect(prompt.contains("Russian"))
        #expect(prompt.contains("HH Kadamba Kanana Swami"))
        #expect(prompt.contains("Krishna -> Кришна"))
        #expect(prompt.contains("Russian translation:"))
    }

    @Test("sanitizes marker wrapped and fenced output")
    func sanitizesOutput() {
        let raw = "Here is the translation:\n```text\n<<<BEGIN>>>\nТекст\n<<<END>>>\n```"

        #expect(ModelOutputSanitizer.sanitize(raw) == "Текст")
    }

    @Test("preserves English timestamped transcript output")
    func preservesEnglishTimestampedTranscriptOutput() {
        let expected = """
        [00:00] arrangements for the little kittens.
        [00:02] They already killed a pigeon and then dragged the kitchen on my doorstep.
        [00:05] They killed a pigeon on my doorstep and it's like, and all the little kittens are chewing on the pigeon.
        """
        let raw = "\n\(expected)\n"

        #expect(ModelOutputSanitizer.sanitize(raw).isEmpty)
        #expect(ModelOutputSanitizer.sanitizeTranscript(raw) == expected)
    }

    @Test("builds cue batch translation prompt with stable cue ids")
    func buildsCueBatchTranslationPrompt() {
        let prompt = NativeLLMPromptBuilder.cueBatchTranslationPrompt(
            cues: [
                TranscriptCue(startSec: 0, endSec: 2, text: "Hare Krishna"),
                TranscriptCue(startSec: 2, endSec: 4, text: "Thank you."),
            ],
            targetLang: "Russian",
            metadata: .empty,
            glossary: [],
            promptPresets: [
                "localTranslationUser": PromptPresetSettings(
                    active: "custom1",
                    custom: [
                        "custom1": "CUSTOM CUE STYLE {{targetLang}}\n{{text}}",
                        "custom2": "",
                        "custom3": "",
                    ]
                )
            ]
        )

        #expect(prompt.contains(#"<cue id="001">Hare Krishna</cue>"#))
        #expect(prompt.contains(#"<cue id="002">Thank you.</cue>"#))
        #expect(prompt.contains("Return exactly one translated cue for every input cue"))
        #expect(prompt.contains("CUSTOM CUE STYLE Russian"))
    }

    @Test("builds Universal-style timed transcript translation prompt")
    func buildsUniversalStyleTimedTranscriptPrompt() {
        let prompt = NativeLLMPromptBuilder.timedTranscriptTranslationPrompt(
            cues: [
                TranscriptCue(startSec: 10, endSec: 12.5, text: "Hare Krishna"),
                TranscriptCue(startSec: 12.5, endSec: 14, text: "Thank you."),
            ],
            targetLang: "Russian",
            metadata: .empty,
            glossary: []
        )

        #expect(prompt.contains("[00:10] Hare Krishna"))
        #expect(prompt.contains("[00:12] Thank you."))
        #expect(prompt.contains("Preserve every [MM:SS] timestamp exactly"))
        #expect(!prompt.contains("<cue"))
    }

    @Test("uses custom local translation prompt from prompt settings")
    func usesCustomLocalTranslationPromptFromPromptSettings() {
        let presets = [
            "localTranslationUser": PromptPresetSettings(
                active: "custom1",
                custom: [
                    "custom1": "CUSTOM LOCAL PROMPT for {{targetLang}}\n{{speakerHintLine}}\n{{glossaryBlock}}\n{{text}}",
                    "custom2": "",
                    "custom3": "",
                ]
            )
        ]

        let prompt = NativeLLMPromptBuilder.timedTranscriptTranslationPrompt(
            cues: [TranscriptCue(startSec: 10, endSec: 12.5, text: "Hare Krishna")],
            targetLang: "Russian",
            metadata: AudioMetadata(date: "", location: "", lecturer: "HH Kadamba Kanana Swami", participants: ""),
            glossary: [
                GlossaryEntry(id: "1", variants: [], source: "Krishna", translation: "Кришна", category: "", translations: ["Russian": "Кришна"], remember: true, createdAt: "", updatedAt: "")
            ],
            promptPresets: presets
        )

        #expect(prompt.contains("CUSTOM LOCAL PROMPT for Russian"))
        #expect(prompt.contains("HH Kadamba Kanana Swami"))
        #expect(prompt.contains("Krishna -> Кришна"))
        #expect(prompt.contains("[00:10] Hare Krishna"))
    }

    @Test("filters local translation glossary to terms present in source text")
    func filtersLocalTranslationGlossaryToSourceTerms() {
        let prompt = NativeLLMPromptBuilder.translationPrompt(
            text: "In this way, we are depending on Krishna.",
            targetLang: "Russian",
            metadata: .empty,
            glossary: [
                GlossaryEntry(id: "1", variants: ["Krishna", "Kṛṣṇa"], source: "Krishna", translation: "Кришна", category: "name", translations: ["Russian": "Кришна"], remember: true, createdAt: "", updatedAt: ""),
                GlossaryEntry(id: "2", variants: ["Srila Prabhupada"], source: "Srila Prabhupada", translation: "Шрила Прабхупада", category: "name", translations: ["Russian": "Шрила Прабхупада"], remember: true, createdAt: "", updatedAt: ""),
            ]
        )

        #expect(prompt.contains("Krishna -> Кришна"))
        #expect(!prompt.contains("Srila Prabhupada -> Шрила Прабхупада"))
    }

    @Test("marks MLX failure text as unusable translation")
    func marksMLXFailureTextAsUnusableTranslation() {
        #expect(!TranslationArchive.isUsableTranslationText("MLX translation failed: MLX returned no usable translation text."))
        #expect(TranslationArchive.isUsableTranslationText("[00:01] Ом Намо Бхагавате Васудевая"))
    }

    @Test("builds Qwen no-think raw chat prompt for MLX generation")
    func buildsQwenNoThinkRawPrompt() {
        let prompt = NativeLLMPromptBuilder.qwenNoThinkChatPrompt(
            userPrompt: "Translate this.",
            systemInstructions: "Return only final text."
        )

        #expect(prompt.contains("<|im_start|>system\nReturn only final text.<|im_end|>"))
        #expect(prompt.contains("<|im_start|>user\nTranslate this.<|im_end|>"))
        #expect(prompt.contains("<|im_start|>assistant\n<think>\n\n</think>"))
        #expect(prompt.hasSuffix("<<<RESULT>>>"))
    }

    @Test("parses timestamped MLX translation back onto source timings")
    func parsesTimestampedTimedTranslationOutput() throws {
        let cues = [
            TranscriptCue(startSec: 10, endSec: 12.5, text: "Hare Krishna", words: [
                TranscriptWord(startSec: 10, endSec: 11, text: "Hare"),
                TranscriptWord(startSec: 11, endSec: 12.5, text: "Krishna"),
            ]),
            TranscriptCue(startSec: 12.5, endSec: 14, text: "Thank you.", words: [
                TranscriptWord(startSec: 12.5, endSec: 14, text: "Thank"),
            ]),
        ]
        let raw = """
        <<<BEGIN>>>
        [00:10] Харе Кришна

        [00:12] Спасибо.
        <<<END>>>
        """

        let translated = try NativeLLMPromptBuilder.parseTimedTranscriptTranslationOutput(raw, sourceCues: cues)

        #expect(translated.map(\.startSec) == [10, 12.5])
        #expect(translated.map(\.endSec) == [12.5, 14])
        #expect(translated.map(\.text) == ["Харе Кришна", "Спасибо."])
        #expect(translated[0].words?.isEmpty == false)
    }

    @Test("falls back from plain timed translation text to source cue timing")
    func parsesPlainTimedTranslationFallback() throws {
        let cues = [
            TranscriptCue(startSec: 0, endSec: 2, text: "First source cue"),
            TranscriptCue(startSec: 2, endSec: 4, text: "Second source cue"),
        ]
        let raw = """
        <<<BEGIN>>>
        Первый перевод. Второй перевод.
        <<<END>>>
        """

        let translated = try NativeLLMPromptBuilder.parseTimedTranscriptTranslationOutput(raw, sourceCues: cues)

        #expect(translated.count == 2)
        #expect(translated.map(\.startSec) == [0, 2])
        #expect(translated.allSatisfy { !$0.text.isEmpty })
    }

    @Test("rejects collapsed one-token translation for many timed cues")
    func rejectsCollapsedOneTokenTranslationForManyTimedCues() throws {
        let cues = [
            TranscriptCue(startSec: 0, endSec: 2, text: "First source cue"),
            TranscriptCue(startSec: 2, endSec: 4, text: "Second source cue"),
            TranscriptCue(startSec: 4, endSec: 6, text: "Third source cue"),
        ]

        #expect(throws: CueBatchTranslationError.emptyOutput) {
            _ = try NativeLLMPromptBuilder.parseTimedTranscriptTranslationOutput("<<<BEGIN>>>and<<<END>>>", sourceCues: cues)
        }
    }

    @Test("rejects visible reasoning text in Russian timed translation")
    func rejectsVisibleReasoningTextInRussianTimedTranslation() throws {
        let cues = [
            TranscriptCue(startSec: 1, endSec: 5, text: "Om Namah Bhagavate Vasudevaya"),
            TranscriptCue(startSec: 30, endSec: 34, text: "O Namo Bhagavate Vasudevaya"),
        ]
        let raw = """
        [00:01] Om Namah Bhagavate Vasudevaya - This is a mantra. "Om" should probably be kept as "Om", but looking at the glossary, there's no specific entry for this.
        [00:30] I'll translate it as "Ом Намо Бхагавате Васудевая". The user said "Translate the transcript" and I should preserve timestamps.
        """

        #expect(throws: CueBatchTranslationError.emptyOutput) {
            _ = try NativeLLMPromptBuilder.parseTimedTranscriptTranslationOutput(raw, sourceCues: cues, targetLang: "Russian")
        }
    }

    @Test("parses cue batch translation output while preserving timings")
    func parsesCueBatchTranslationOutput() throws {
        let cues = [
            TranscriptCue(startSec: 10, endSec: 12.5, text: "Hare Krishna"),
            TranscriptCue(startSec: 12.5, endSec: 14, text: "Thank you."),
        ]
        let raw = """
        ```xml
        <<<BEGIN>>>
        <cue id="001">Харе Кришна</cue>
        <cue id="002">Спасибо.</cue>
        <<<END>>>
        ```
        """

        let translated = try NativeLLMPromptBuilder.parseCueBatchTranslationOutput(raw, sourceCues: cues)

        #expect(translated == [
            TranscriptCue(startSec: 10, endSec: 12.5, text: "Харе Кришна"),
            TranscriptCue(startSec: 12.5, endSec: 14, text: "Спасибо."),
        ])
    }

    @Test("falls back when timed cue ids are incomplete")
    func fallsBackWhenTimedCueIDsAreIncomplete() throws {
        let cues = [
            TranscriptCue(startSec: 0, endSec: 2, text: "First source cue"),
            TranscriptCue(startSec: 2, endSec: 4, text: "Second source cue"),
            TranscriptCue(startSec: 4, endSec: 6, text: "Third source cue"),
        ]
        let raw = """
        <<<BEGIN>>>
        <cue id="001">Первый перевод.</cue>
        <cue id="002">Второй перевод. Третий перевод.</cue>
        <<<END>>>
        """

        let translated = try NativeLLMPromptBuilder.parseCueBatchTranslationOutput(raw, sourceCues: cues)

        #expect(translated.count == 3)
        #expect(translated.map(\.startSec) == [0, 2, 4])
        #expect(translated.allSatisfy { !$0.text.isEmpty })
    }

    @Test("maps plain cue translation text back onto source timings")
    func mapsPlainCueTranslationTextBackOntoSourceTimings() throws {
        let cues = [
            TranscriptCue(startSec: 0, endSec: 2, text: "First source cue"),
            TranscriptCue(startSec: 2, endSec: 4, text: "Second source cue"),
        ]
        let raw = """
        <<<BEGIN>>>
        Первый перевод. Второй перевод.
        <<<END>>>
        """

        let translated = try NativeLLMPromptBuilder.parseCueBatchTranslationOutput(raw, sourceCues: cues)

        #expect(translated.count == 2)
        #expect(translated.map(\.endSec) == [2, 4])
        #expect(translated.map(\.text).joined(separator: " ").contains("перевод"))
    }

    @Test("splits timed cues into bounded translation batches")
    func splitsCueTranslationBatches() {
        let cues = [
            TranscriptCue(startSec: 0, endSec: 1, text: String(repeating: "a", count: 6)),
            TranscriptCue(startSec: 1, endSec: 2, text: String(repeating: "b", count: 6)),
            TranscriptCue(startSec: 2, endSec: 3, text: String(repeating: "c", count: 6)),
        ]

        let batches = NativeLLMPromptBuilder.cueTranslationBatches(cues, maxSourceCharacters: 12)

        #expect(batches.map(\.count) == [2, 1])
        #expect(batches.flatMap { $0 } == cues)
    }
}
