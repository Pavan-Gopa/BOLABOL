import Foundation
import NativeBolabolCore
import Testing

@Test
func modelOutputSanitizerPrefersExplicitBeginEndMarkers() {
    let output = """
    Sure, here is the polished text.
    <<<BEGIN>>>
    Это аккуратно отполированный текст.
    <<<END>>>
    Extra explanation.
    """

    #expect(ModelOutputSanitizer.sanitize(output) == "Это аккуратно отполированный текст.")
}

@Test
func modelOutputSanitizerUnwrapsCodeFences() {
    let output = """
    ```text
    Clean text only.
    ```
    """

    #expect(ModelOutputSanitizer.sanitize(output) == "Clean text only.")
}

@Test
func modelOutputSanitizerRemovesThinkingBlocks() {
    let output = """
    <think>
    I need to reason about how to polish this text.
    </think>

    Это чистовой результат.
    """

    #expect(ModelOutputSanitizer.sanitize(output) == "Это чистовой результат.")
}

/// Dictated prose containing "Result:"-style labels is content, not a
/// final-answer delimiter: prompts forbid labels, so the sanitizer must
/// preserve such inputs verbatim (aside from surrounding trim).
@Test
func modelOutputSanitizerPreservesResultLabeledProse() {
    let single = "Result: we shipped"
    #expect(ModelOutputSanitizer.sanitize(single) == single)

    let multi = "We discussed the launch.\n\nResult: we shipped"
    #expect(ModelOutputSanitizer.sanitize(multi) == multi)

    let quoted = "Result: \"we shipped\""
    #expect(ModelOutputSanitizer.sanitize(quoted) == quoted)
}

// MARK: - Ordinary dictation preservation (S11: never delete or translate source prose)

/// Incident 2026-10-14: ordinary English openers sanitized to empty.
/// The sanitizer must preserve them verbatim.
@Test
func modelOutputSanitizerPreservesOrdinaryEnglishDictationOpeners() {
    let cases = [
        "I will open the calendar.",
        "I can open the calendar.",
        "I would like to open the calendar.",
        "Let me open the calendar.",
        "Okay, please check the calendar.",
        "Please open the calendar.",
        "Here is my report for today.",
        "Here is the summary we agreed on.",
        "I will be there at noon.",
    ]
    for input in cases {
        #expect(ModelOutputSanitizer.sanitize(input) == input, "dictation deleted: \(input)")
    }
}

/// Incident 2026-10-14: English words were replaced with Russian
/// ("Finally" -> "наконец", "really" -> "действительно", "moment" -> "момент").
/// No word-level translation may happen in the sanitizer.
@Test
func modelOutputSanitizerDoesNotTranslateEnglishWords() {
    let english = "Finally, I am really ready for this moment."
    #expect(ModelOutputSanitizer.sanitize(english) == english)

    let horizon = "The horizon at that moment felt really wide."
    #expect(ModelOutputSanitizer.sanitize(horizon) == horizon)

    // Legitimate Russian dictation (including variant labels and chat-like
    // openers) is preserved verbatim, not stripped or rewritten.
    let russian = "Вариант 2: Конечно, это аккуратный текст."
    #expect(ModelOutputSanitizer.sanitize(russian) == russian)
}

/// Multi-paragraph speech and quoted/numbered source must survive intact.
@Test
func modelOutputSanitizerPreservesMultiParagraphQuotedAndNumberedSpeech() {
    let multi = "Okay, first point.\n\nSecond point follows."
    #expect(ModelOutputSanitizer.sanitize(multi) == multi)

    let quoted = "\"Let me open the calendar,\" she said."
    #expect(ModelOutputSanitizer.sanitize(quoted) == quoted)

    let numbered = "1. First item\n2. Second item"
    #expect(ModelOutputSanitizer.sanitize(numbered) == numbered)
}

/// Intentional repetition is content, not duplication noise.
@Test
func modelOutputSanitizerPreservesIntentionalRepetition() {
    let repeatedLines = "Same line.\nSame line."
    #expect(ModelOutputSanitizer.sanitize(repeatedLines) == repeatedLines)

    let repeatedSentence = "Time to go. Time to go."
    #expect(ModelOutputSanitizer.sanitize(repeatedSentence) == repeatedSentence)
}

/// Explicit <think> wrappers are still removed, without eating the
/// legitimate prose that follows them.
@Test
func modelOutputSanitizerExplicitThinkWrapperStillStrippedWithoutEatingProse() {
    let output = "<think>reasoning about the text</think>Let me open the calendar."
    #expect(ModelOutputSanitizer.sanitize(output) == "Let me open the calendar.")
}

@Test
func modelOutputSanitizerPreservesFormerReplacementWordsInEveryPositionAndCase() {
    for word in ["finally", "really", "horizon", "horizonte", "horizontes", "moment"] {
        for spelling in [word, word.uppercased(), word.capitalized, word.enumerated().map {
            $0.offset.isMultiple(of: 2) ? String($0.element).uppercased() : String($0.element)
        }.joined()] {
            for sentence in [
                "\(spelling), I would like the entire English sentence to stay in English.",
                "I will put \(spelling) in the middle of this longer English sentence.",
                "Here is the English sentence that ends with \(spelling).",
            ] {
                #expect(ModelOutputSanitizer.sanitize(sentence) == sentence)
            }
        }
    }
}

@Test
func modelOutputSanitizerTrimsOnlyOuterWhitespaceInMixedUnicodeProse() {
    let content = "I really agree: действительно, finally готово! 👩🏽‍💻 🚀\r\n\tKeep  two spaces.\r\n\r\nCafé / Cafe\u{301} — горизонт, horizon, momento."
    let result = ModelOutputSanitizer.sanitize("\r\n \t\u{00A0}\(content)\u{00A0}\t \r\n")
    #expect(Array(result.utf8) == Array(content.utf8))
}

@Test
func modelOutputSanitizerPreservesLongEnglishAndRussianOutput() {
    let paragraph = "I would like to really preserve this moment, finally looking at the horizon and horizonte. Это русский текст 👩🏽‍💻.\r\n\r\n"
    let text = String(repeating: paragraph, count: 10_000) + "The final sentence must survive."
    #expect(ModelOutputSanitizer.sanitize(text) == text)
}

@Test
func modelOutputSanitizerHandlesIncompleteThinkingWrappers() {
    #expect(ModelOutputSanitizer.sanitize("<ThInK>Unfinished reasoning.\r\nStill reasoning.").isEmpty)
    // Inline closers are prose, not a reasoning boundary: preserved verbatim.
    #expect(ModelOutputSanitizer.sanitize("Reasoning without an opening tag.</THINK>\r\nI can finally deliver the English answer.") == "Reasoning without an opening tag.</THINK>\r\nI can finally deliver the English answer.")
    #expect(ModelOutputSanitizer.sanitize("Write </think> to close it.") == "Write </think> to close it.")
    #expect(ModelOutputSanitizer.sanitize("Write </THINK> to close it.") == "Write </THINK> to close it.")
    #expect(ModelOutputSanitizer.sanitize("To close the block, write </think>") == "To close the block, write </think>")
    // Only an own-line closer ends a reasoning prefix.
    #expect(ModelOutputSanitizer.sanitize("Reasoning without an opening tag.\n</THINK>\nI can finally deliver the English answer.") == "I can finally deliver the English answer.")
    #expect(ModelOutputSanitizer.sanitize("Reasoning without an opening tag.\r\n</THINK>\r\nI can finally deliver the English answer.") == "I can finally deliver the English answer.")
    #expect(ModelOutputSanitizer.sanitize("reasoning\n</think>\n\nWrite </think> to close it.") == "Write </think> to close it.")
}

@Test
func modelOutputSanitizerExtractsAnswerAroundEchoedInput() {
    #expect(ModelOutputSanitizer.sanitize("<<<INPUT>>>Original dictation.<<<END_INPUT>>>\r\nI would like the final answer.") == "I would like the final answer.")
    #expect(ModelOutputSanitizer.sanitize("Это итоговый ответ.\r\n<<<INPUT>>>Исходная диктовка.<<<END_INPUT>>>") == "Это итоговый ответ.")
}

@Test
func modelOutputSanitizerPreservesPartialAndEmbeddedFencesAndIncompleteSentinels() {
    for text in [
        "```text\nI will keep this unfinished fenced answer.",
        "I will keep this answer with an unmatched fence.\n```",
        "I would like to show this example:\n```text\nReally useful.\n```\nThen continue speaking.",
        "```text\nFinally useful.\n```\nI will continue after the example.",
        "<<<BEGIN>>>\nI can keep the English answer even without an end marker.",
        "I can keep the answer with only a closing marker. <<<END>>>",
    ] {
        #expect(ModelOutputSanitizer.sanitize(text) == text)
    }
}

@Test
func modelOutputSanitizerUnwrapsCRLFLanguageTaggedFence() {
    let content = "I would really like this moment to survive. 👩🏽‍💻\r\nЭто тоже часть ответа."
    #expect(ModelOutputSanitizer.sanitize("```text\r\n\(content)\r\n```") == content)
}

@Test
func modelOutputSanitizerRemovesComposedExplicitWrappers() {
    let text = "I can finally see the horizon."
    #expect(ModelOutputSanitizer.sanitize("<<<BEGIN>>>\n```text\n\(text)\n```\n<<<END>>>") == text)
    #expect(ModelOutputSanitizer.sanitize("<<<BEGIN>>><think>Reasoning.</think>\(text)<<<END>>>") == text)
}

// Literal tag names in dictated technical prose are not model reasoning.
// This catches the destructive mid-sentence unclosed-block interpretation.
@Test
func modelOutputSanitizerPreservesLiteralThinkTagInEnglishProse() {
    let text = "I would like to explain the literal <think> tag in this English sentence."
    #expect(ModelOutputSanitizer.sanitize(text) == text)
}

@Test
func modelOutputSanitizerReturnsEmptyForEmptyBeginEndWrapper() {
    // An empty provider answer must not become a successful note containing
    // the protocol's delimiters.
    #expect(ModelOutputSanitizer.sanitize("<<<BEGIN>>><<<END>>>").isEmpty)
}

@Test
func modelOutputSanitizerReturnsEmptyForEmptyWholeOutputFence() {
    #expect(ModelOutputSanitizer.sanitize("```\n```").isEmpty)
    #expect(ModelOutputSanitizer.sanitize("```text\r\n```").isEmpty)
}

@Test
func modelOutputSanitizerRemovesThinkingInsideWholeOutputFence() {
    let answer = "I would finally like to open the calendar."
    #expect(ModelOutputSanitizer.sanitize("```text\n<think>Reasoning about the answer.</think>\n\(answer)\n```") == answer)
    #expect(ModelOutputSanitizer.sanitize("```text\nReasoning about the answer.\n</think>\n\(answer)\n```") == answer)
    #expect(ModelOutputSanitizer.sanitize("```text\n<think>Unfinished reasoning.\n```").isEmpty)
}

@Test
func modelOutputSanitizerUnwrapsWholeOutputFenceWithPunctuatedLanguageTag() {
    let answer = "I would like to explain C++ templates without changing this English sentence."
    #expect(ModelOutputSanitizer.sanitize("```c++\n\(answer)\n```") == answer)
}
