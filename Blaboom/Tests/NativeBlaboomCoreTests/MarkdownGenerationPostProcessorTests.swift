import NativeBlaboomCore
import Testing

@Test
func markdownPostProcessorConvertsPlainSequentialOutputIntoList() {
    let source = """
    Сначала открыть проект. Потом проверить кнопку M. Затем исправить код и собрать приложение.
    """
    let modelOutput = "Открыть проект. Проверить кнопку M. Исправить код и собрать приложение."

    let markdown = MarkdownGenerationPostProcessor.ensureVisibleMarkdown(
        modelOutput,
        sourceText: source
    )

    #expect(markdown.contains("## План"))
    #expect(markdown.contains("1. Открыть проект"))
    #expect(markdown.contains("2. Проверить кнопку M"))
    #expect(markdown.contains("3. Исправить код и собрать приложение"))
}

@Test
func markdownPostProcessorKeepsExistingMarkdownUnchanged() {
    let modelOutput = """
    # План

    1. Открыть проект
    2. Собрать приложение
    """

    let markdown = MarkdownGenerationPostProcessor.ensureVisibleMarkdown(
        modelOutput,
        sourceText: "Открыть проект. Собрать приложение."
    )

    #expect(markdown == modelOutput)
}

@Test
func markdownPostProcessorWrapsPlainParagraphWhenModelIgnoresMarkdown() {
    let text = "Это короткий текст без явной структуры."

    let markdown = MarkdownGenerationPostProcessor.ensureVisibleMarkdown(
        text,
        sourceText: text
    )

    #expect(markdown == "## Текст\n\nЭто короткий текст без явной структуры.")
}
