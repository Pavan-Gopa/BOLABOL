import NativeSmartScribeCore
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
func modelOutputSanitizerRemovesCommonChatPreamblesAndVariantLabels() {
    let output = "Вариант 2: Конечно, это аккуратный текст."

    #expect(ModelOutputSanitizer.sanitize(output) == "это аккуратный текст.")
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

// MARK: - Reasoning model (Qwopus/Opus) chain-of-thought handling

/// Reproduces the Qwopus screenshot: the model dumps its English reasoning
/// (preamble + "Analysis:" + "Checking for duplicates:") and is cut off before
/// producing any final text. The sanitizer must return an empty string so the
/// worker raises a clear error instead of showing the raw reasoning.
@Test
func modelOutputSanitizerReturnsEmptyForTruncatedReasoning() {
    let output = """
    The user wants me to clean up a Russian text that appears to be dictated speech. Let me analyze the input:

    Input text:
    "Так, еще одна небольшая правка. Нужно посмотреть, в чем проблема."

    Analysis:
    1. "Так" - filler word, should be removed
    2. "еще одна небольшая правка" - this is a complete thought, keep it

    Checking for duplicates:
    - No repeated
    """

    #expect(ModelOutputSanitizer.sanitize(output) == "")
}

/// When a reasoning model finishes and places the actual cleaned text as the
/// final paragraph after its reasoning, that final paragraph must be returned.
@Test
func modelOutputSanitizerKeepsFinalAnswerParagraphAfterReasoning() {
    let output = """
    The user wants me to clean up a Russian text. Let me analyze the input:

    Analysis:
    1. "Так" - filler word, should be removed

    Еще одна небольшая правка. Нужно посмотреть, в чем проблема.
    """

    #expect(
        ModelOutputSanitizer.sanitize(output)
            == "Еще одна небольшая правка. Нужно посмотреть, в чем проблема."
    )
}

/// An explicit "Cleaned text:" delimiter still wins over the reasoning above it.
@Test
func modelOutputSanitizerExtractsAnswerAfterCleanedTextDelimiter() {
    let output = """
    The user wants me to clean up the text. Let me analyze the input.

    Analysis: a few fillers to remove.

    Cleaned text: Нужно посмотреть, в чем проблема.
    """

    #expect(
        ModelOutputSanitizer.sanitize(output) == "Нужно посмотреть, в чем проблема."
    )
}
