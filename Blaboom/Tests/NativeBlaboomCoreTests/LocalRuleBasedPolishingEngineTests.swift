import Foundation
import NativeBlaboomCore
import Testing

private func template() -> PromptTemplate {
  PromptTemplate(id: "t", title: "T", body: "Clean: ${transcription}")
}

@Test
func localRuleEngineIDsAreStable() {
  let engine = LocalRuleBasedPolishingEngine()
  #expect(engine.id == "local-rule-based-polish")
  #expect(engine.displayName == "Quick Local Cleanup")
}

@Test
func localRuleEngineVariantOneAppliesLightCleanup() async throws {
  let engine = LocalRuleBasedPolishingEngine()
  let result = try await engine.polish(
    PolishingRequest(
      rawText: "ну вот я хочу записать записать текст",
      variant: .variantOne,
      template: template()
    )
  )
  #expect(!result.text.localizedCaseInsensitiveContains("ну"))
  #expect(!result.text.localizedCaseInsensitiveContains("записать записать"))
  #expect(result.diagnostics.backendName == "Quick Local Cleanup")
}

@Test
func localRuleEngineVariantTwoUsesStructuredCleanup() async throws {
  let engine = LocalRuleBasedPolishingEngine()
  let input =
    "Первое предложение здесь. Второе предложение тоже здесь. Третье завершает мысль."
  let result = try await engine.polish(
    PolishingRequest(rawText: input, variant: .variantTwo, template: template())
  )
  #expect(result.text.contains("\n\n") || result.text.contains("."))
  #expect(!result.text.isEmpty)
}

@Test
func localRuleEngineRawVariantAlsoCleans() async throws {
  let engine = LocalRuleBasedPolishingEngine()
  let result = try await engine.polish(
    PolishingRequest(
      rawText: "um hello hello world",
      variant: .raw,
      template: template()
    )
  )
  #expect(result.text.localizedCaseInsensitiveContains("hello"))
  #expect(!result.text.localizedCaseInsensitiveContains("um"))
}

@Test
func localRuleEngineRejectsWhitespaceOnlyInput() async {
  let engine = LocalRuleBasedPolishingEngine()
  do {
    _ = try await engine.polish(
      PolishingRequest(rawText: "   \n\t  ", variant: .variantOne, template: template())
    )
    Issue.record("Expected emptyInput error")
  } catch let error as LocalRuleBasedPolishingError {
    #expect(error == .emptyInput)
    #expect(error.errorDescription != nil)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test
func localRuleEngineRequiresValidTemplatePlaceholder() async {
  let engine = LocalRuleBasedPolishingEngine()
  let bad = PromptTemplate(id: "bad", title: "Bad", body: "No placeholder here")
  do {
    _ = try await engine.polish(
      PolishingRequest(rawText: "hello", variant: .variantOne, template: bad)
    )
    Issue.record("Expected template render failure")
  } catch let error as PromptTemplateError {
    #expect(error == .missingTranscriptionPlaceholder)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}
