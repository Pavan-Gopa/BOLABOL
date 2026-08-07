import Foundation
import NativeBolabolCore
import Testing

// Starter Vaishnava glossary + full transcription language routing matrix.

// MARK: Starter glossary

@Test
func starterGlossaryIsNonEmptyWithStableIDsAndCategories() {
  let entries = StarterGlossary.entries
  #expect(entries.count >= 50)
  #expect(entries.allSatisfy { $0.id.hasPrefix("starter-vaishnava-") })
  #expect(entries.allSatisfy { !$0.source.isEmpty })
  #expect(entries.allSatisfy { !$0.translation.isEmpty })
  #expect(entries.allSatisfy { $0.remember })

  let ids = entries.map(\.id)
  #expect(Set(ids).count == ids.count, "Starter glossary IDs must be unique")

  let categories = Set(entries.compactMap(\.category))
  #expect(categories.contains("Names of God") || categories.contains("Ачарьи / Учители")
    || categories.contains("Acharyas / Teachers"))
}

@Test
func starterGlossaryIncludesCoreDevotionalTerms() {
  let sources = StarterGlossary.entries.map { $0.source.lowercased() }
  #expect(sources.contains { $0.contains("kṛṣṇa") || $0.contains("krishna") })
  #expect(sources.contains { $0.contains("prabhupāda") || $0.contains("prabhupada") })
  #expect(sources.contains { $0.contains("bhagavad") })
  #expect(sources.contains { $0.contains("iskcon") })
}

@Test
func starterGlossaryMergeAddsMissingAndSkipsDuplicatesByID() {
  let existing = Array(StarterGlossary.entries.prefix(3))
  let merged = StarterGlossary.mergeStarterGlossary(existing)
  #expect(merged.count == StarterGlossary.entries.count)
  #expect(Set(merged.map(\.id)).count == merged.count)
}

@Test
func starterGlossaryMergeSkipsDuplicatesBySource() {
  let custom = GlossaryEntry(
    id: "user-krishna",
    variants: ["Krishna"],
    source: "Kṛṣṇa",
    translation: "Кришна custom",
    category: "Custom",
    translations: ["Default": "Кришна custom"],
    remember: true,
    createdAt: "",
    updatedAt: ""
  )
  let merged = StarterGlossary.mergeStarterGlossary([custom])
  let krishnaCount = merged.filter {
    $0.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      == "kṛṣṇa"
  }.count
  #expect(krishnaCount == 1)
  #expect(merged.contains { $0.id == "user-krishna" })
}

@Test
func starterGlossaryEntriesHaveRussianTranslations() {
  let withRussian = StarterGlossary.entries.filter {
    $0.translations["Russian"] != nil || $0.translations["Default"] != nil
  }
  #expect(withRussian.count == StarterGlossary.entries.count)
}

// MARK: Language routing matrix

@Test
func languageRouterAutoModeNeverForcesLanguage() {
  let route = TranscriptionLanguageRouter.route(
    resolvedLanguageCode: "auto",
    isMultilingualModel: true
  )
  #expect(route.forcedLanguageCode == nil)
  #expect(!route.translateToEnglish)
  #expect(route.postASRTextTranslationTargetLanguageCode == nil)
}

@Test
func languageRouterEmptyCodeBehavesLikeAuto() {
  let route = TranscriptionLanguageRouter.route(
    resolvedLanguageCode: "  ",
    isMultilingualModel: true
  )
  #expect(route.forcedLanguageCode == nil)
}

@Test
func languageRouterMultilingualKeepsForcedSourceLanguage() {
  let route = TranscriptionLanguageRouter.route(
    resolvedLanguageCode: "ru",
    isMultilingualModel: true
  )
  #expect(route.forcedLanguageCode == "ru")
  #expect(!route.translateToEnglish)
  #expect(route.postASRTextTranslationTargetLanguageCode == nil)
}

@Test
func languageRouterEnglishOnlyStillPassesForcedCode() {
  let route = TranscriptionLanguageRouter.route(
    resolvedLanguageCode: "de",
    isMultilingualModel: false
  )
  #expect(route.forcedLanguageCode == "de")
  #expect(!route.translateToEnglish)
}

@Test
func languageRouterForceEnglishOnMultilingualUsesWhisperTranslate() {
  let route = TranscriptionLanguageRouter.route(
    resolvedLanguageCode: "en",
    isMultilingualModel: true,
    forceTargetLanguage: true
  )
  #expect(route.forcedLanguageCode == nil)
  #expect(route.translateToEnglish)
  #expect(route.postASRTextTranslationTargetLanguageCode == nil)
}

@Test
func languageRouterForceEnglishOnEnglishOnlyUsesLLM() {
  let route = TranscriptionLanguageRouter.route(
    resolvedLanguageCode: "english",
    isMultilingualModel: false,
    forceTargetLanguage: true
  )
  #expect(!route.translateToEnglish)
  #expect(route.postASRTextTranslationTargetLanguageCode == "en")
}

@Test
func languageRouterForceNonEnglishAlwaysUsesLLMPass() {
  for code in ["ru", "es", "ja", "zh", "de", "fr"] {
    let multi = TranscriptionLanguageRouter.route(
      resolvedLanguageCode: code,
      isMultilingualModel: true,
      forceTargetLanguage: true
    )
    #expect(!multi.translateToEnglish, "force \(code) should not use Whisper translate")
  #expect(multi.postASRTextTranslationTargetLanguageCode == code, "force \(code) should LLM-translate")
    #expect(multi.forcedLanguageCode == nil, "force \(code) should not force source language")
  }
}

@Test
func languageRouterForceAutoDefaultsToEnglishTarget() {
  let route = TranscriptionLanguageRouter.route(
    resolvedLanguageCode: "auto",
    isMultilingualModel: true,
    forceTargetLanguage: true
  )
  #expect(route.translateToEnglish || route.postASRTextTranslationTargetLanguageCode == "en")
}

@Test
func languageRouterNormalizesCaseAndWhitespace() {
  let route = TranscriptionLanguageRouter.route(
    resolvedLanguageCode: "  RU  ",
    isMultilingualModel: true
  )
  #expect(route.forcedLanguageCode == "ru")
}
