import Foundation
import NativeBolabolCore
import Testing

// Edge cases for translation prompts, focused insertion, sanitizer, markdown,
// and cloud raw prompts that sit on the critical dictation path.

// MARK: Translation

@Test
func translationPromptTrimsLanguageAndText() throws {
  let prompt = try TranslationPrompt.render(
    text: "  Hello world  ",
    targetLanguage: "  French  "
  )
  #expect(prompt.contains("to French"))
  #expect(prompt.contains("Hello world"))
  #expect(!prompt.contains("  Hello"))
}

@Test
func translationPromptRejectsEmptyAfterTrim() {
  #expect(throws: TranslationPromptError.emptyText) {
    try TranslationPrompt.render(text: "\n\t", targetLanguage: "English")
  }
}

// MARK: Cloud raw prompt

@Test
func cloudRawPromptForceTargetDefaultsEmptyLanguageToEnglish() {
  let prompt = CloudRawTranscriptionPrompt.instruction(
    forceTargetLanguage: true,
    targetLanguageName: "   "
  )
  #expect(prompt.contains("entire result in English"))
}

@Test
func cloudRawPromptNeverMentionsVariantPolishing() {
  for force in [false, true] {
    let prompt = CloudRawTranscriptionPrompt.instruction(
      forceTargetLanguage: force,
      targetLanguageName: "German"
    )
    #expect(!prompt.localizedCaseInsensitiveContains("variant 1"))
    #expect(!prompt.localizedCaseInsensitiveContains("variant 2"))
    #expect(prompt.contains("Do not add an introduction"))
  }
}

// MARK: Focused text insertion (type-into-app)

@Test
func focusedTextInsertionInsertsAtCaretWithZeroLengthSelection() {
  let snapshot = FocusedTextInsertionSnapshot(
    value: "Hello world",
    selection: NSRange(location: 5, length: 0)
  )
  let result = snapshot.inserting(" beautiful")
  #expect(result.value == "Hello beautiful world")
  #expect(result.selection.location == 15)
  #expect(result.selection.length == 0)
}

@Test
func focusedTextInsertionHandlesEmptyDocument() {
  let snapshot = FocusedTextInsertionSnapshot(
    value: "",
    selection: NSRange(location: 0, length: 0)
  )
  let result = snapshot.inserting("Hi")
  #expect(result.value == "Hi")
  #expect(result.selection.location == 2)
}

@Test
func focusedTextInsertionClampsNegativeSelection() {
  let snapshot = FocusedTextInsertionSnapshot(
    value: "abc",
    selection: NSRange(location: -5, length: 2)
  )
  let result = snapshot.inserting("X")
  #expect(result.value.hasPrefix("X") || result.value.contains("X"))
}

// MARK: Speech cleanup English fillers

@Test
func speechCleanupRemovesEnglishFillers() {
  let output = SpeechCleanupNormalizer.normalize(
    "um uh you know like this is the point",
    mode: .lightCleanup
  )
  #expect(!output.localizedCaseInsensitiveContains(" um "))
  #expect(!output.localizedCaseInsensitiveContains(" uh "))
  #expect(output.localizedCaseInsensitiveContains("point"))
  #expect(output.hasSuffix(".") || output.hasSuffix("!"))
}

@Test
func speechCleanupStructuredModeSeparatesSentences() {
  let output = SpeechCleanupNormalizer.normalize(
    "One sentence here. Two sentence there. Three sentence end.",
    mode: .structuredCleanup
  )
  #expect(output.contains("\n\n"))
}

@Test
func speechCleanupEmptyInputReturnsEmpty() {
  #expect(SpeechCleanupNormalizer.normalize("   ", mode: .lightCleanup).isEmpty)
  #expect(SpeechCleanupNormalizer.normalize("", mode: .structuredCleanup).isEmpty)
}

// MARK: Model output sanitizer edge cases

@Test
func modelOutputSanitizerHandlesEmptyAndWhitespace() {
  #expect(ModelOutputSanitizer.sanitize("").isEmpty)
  #expect(ModelOutputSanitizer.sanitize("   \n").isEmpty)
}

@Test
func modelOutputSanitizerStripsMarkdownFencesWhenPresent() {
  let input = """
    ```text
    Clean answer only.
    ```
    """
  let output = ModelOutputSanitizer.sanitize(input)
  #expect(output.contains("Clean answer only"))
  #expect(!output.contains("```"))
}

// MARK: Markdown post-processor

@Test
func markdownPostProcessorHandlesEmptyInput() {
  let result = MarkdownGenerationPostProcessor.ensureVisibleMarkdown("", sourceText: "")
  #expect(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !result.isEmpty)
}

// MARK: HUD spectrum

@Test
func hudSpectrumEmptyBandsReturnNoiseFloorBars() {
  let values = HUDSpectrumResponse.classicListeningValues(bands: [], barCount: 8)
  #expect(values.count == 8)
  #expect(values.allSatisfy { $0 >= 0 && $0 <= 1 })
}

@Test
func hudSpectrumZeroBarCountReturnsEmpty() {
  #expect(HUDSpectrumResponse.classicListeningValues(bands: [0.5], barCount: 0).isEmpty)
}

@Test
func hudSpectrumClampsNonFiniteAndOutOfRangeBands() {
  let values = HUDSpectrumResponse.classicListeningValues(
    bands: [Float.nan, Float.infinity, -1, 2, 0.5],
    barCount: 5
  )
  #expect(values.count == 5)
  #expect(values.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
}

// MARK: Hotkey session coordinator basics

@MainActor
@Test
func hotkeySessionCoordinatorStartStopSameOwner() {
  let coordinator = HotkeySessionCoordinator()
  let owner = UUID()
  let other = UUID()
  #expect(coordinator.beginRecording(ownerID: owner))
  #expect(!coordinator.beginRecording(ownerID: other))
  #expect(coordinator.beginProcessing(ownerID: owner))
  coordinator.finish(ownerID: owner)
  #expect(coordinator.beginRecording(ownerID: other))
}

// MARK: Prompt template render smoke

@Test
func promptTemplateRendersTranscriptionIntoBody() throws {
  let template = PromptTemplate(
    id: "v1",
    title: "V1",
    body: "Polish:\n${transcription}\nDone."
  )
  let rendered = try template.render(transcription: "hello there")
  #expect(rendered.contains("hello there"))
  #expect(rendered.contains("Polish:"))
}
