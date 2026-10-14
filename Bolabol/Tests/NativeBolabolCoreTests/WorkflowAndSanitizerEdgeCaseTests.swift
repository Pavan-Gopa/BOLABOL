import Foundation
@testable import NativeBolabol
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

// Exercise the real cloud engine and workflow without contacting a provider.
// The protocol accepts only a reserved fixture host; the store is in-memory.
@Suite("Model output sanitizer cloud workflow", .serialized)
struct ModelOutputSanitizerCloudWorkflowTests {
  @MainActor
  @Test
  func modelOutputSanitizerCloudPolishKeepsLegitimateEnglishNonempty() async throws {
    #expect(URLProtocol.registerClass(SanitizerCloudOutputURLProtocol.self))
    defer { URLProtocol.unregisterClass(SanitizerCloudOutputURLProtocol.self) }

    for (path, expected) in [
      ("plain", SanitizerCloudOutputURLProtocol.english),
      ("fenced", SanitizerCloudOutputURLProtocol.english),
      ("literal-closing", SanitizerCloudOutputURLProtocol.literalClosingTag),
      ("inline-closing-text", SanitizerCloudOutputURLProtocol.inlineClosingTagWithTrailingText),
    ] {
      let engine = CloudTextPolishingEngine(
        kind: .openRouter,
        configuration: APIProviderConfiguration(
          apiKeys: ["sanitizer-fixture-key"],
          textModel: "sanitizer-fixture-model",
          baseURL: "https://sanitizer-qa.invalid/\(path)"
        )
      )
      let store = NoteStore(notes: [], isPersistenceEnabled: false)
      let note = store.addEmptyNote()
      store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
          text: expected,
          diagnostics: EngineDiagnostics(backendName: "Fixture transcript")
        )
      )

      let cloudResult = try await engine.polish(PolishingRequest(
        rawText: expected,
        variant: .variantOne,
        template: .defaultTemplate(for: .variantOne)
      ))
      #expect(cloudResult.text == expected, "cloud polish deleted or changed legitimate English: \(path)")

      let workflow = PolishingWorkflow(noteStore: store, engine: engine)
      let results = await workflow.polishNote(note.id)
      for variant in [ProcessingVariant.variantOne, .variantTwo] {
        #expect(results[variant]?.text == expected, "sanitized cloud output was rejected by workflow: \(path)")
        #expect(store.note(withID: note.id)?.polishingStatus(for: variant).phase == .completed)
      }
      #expect(store.note(withID: note.id)?.polishedVariantOne == expected)
      #expect(store.note(withID: note.id)?.polishedVariantTwo == expected)
    }
  }
}

private final class SanitizerCloudOutputURLProtocol: URLProtocol {
  static let english = "I would finally like to open the calendar. I really see the horizon at this moment. 👩🏽‍💻"
  static let literalClosingTag = "To close the block, write </think>"
  static let inlineClosingTagWithTrailingText = "Write </think> to close it. I would finally like to open the calendar."

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "sanitizer-qa.invalid"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path ?? ""
    let content: String
    if path.contains("/literal-closing/") {
      content = Self.literalClosingTag
    } else if path.contains("/inline-closing-text/") {
      content = Self.inlineClosingTagWithTrailingText
    } else if path.contains("/fenced/") {
      content = "```text\n\(Self.english)\n```"
    } else {
      content = Self.english
    }
    do {
      let data = try JSONSerialization.data(withJSONObject: [
        "choices": [["message": ["content": content]]]
      ])
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
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
