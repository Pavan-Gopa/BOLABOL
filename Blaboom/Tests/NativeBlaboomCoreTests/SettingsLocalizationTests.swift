import Foundation
import NativeBlaboomCore
import Testing

/// Guards the settings/native-screen ↔ AppText key synchronisation added during
/// the i18n pass over the Glossary, API Providers, Hotkey, Local Models,
/// Polishing, Prompts, Notes, Translation and Sidebar surfaces. Every key that
/// those screens reference must resolve to a real, non-empty translation in all
/// 15 supported languages (never the raw-key fallback), and the genuinely
/// translatable ones must not silently fall back to English in non-English
/// locales.
private let concreteLanguages: [UILanguagePreference] = UILanguagePreference.allCases.filter {
    $0 != .system
}

/// A representative set of the keys introduced for the native screens, spanning
/// every localized surface and including plain labels, sentences and format
/// strings.
private let settingsKeys: [AppTextKey] = [
    // Glossary
    .settingsGlossary, .clearGlossaryTitle, .clearGlossary, .clearGlossaryMessage,
    .glossaryCleared, .transcriptionLanguageSetTo, .translation, .translationLanguageSetTo,
    .importJSON, .importCSV, .exportJSON, .exportCSV, .importExport,
    .search, .category, .allCategories, .newEntry, .languageForm,
    .variantsSeparatedBySemicolons, .addEntry, .entryAdded, .useGlossary,
    .custom, .apply, .variants, .mergeInto, .save, .searchTerm, .noMatchingEntries,
    .addToGlossary, .selectedVariant, .createNewEntry, .applyAs,
    .authorTranscription, .autoTranslation, .correctLanguageForm,
    .languageAutoTranslationForm, .noCategory, .addCategory, .newCategory,
    // API Providers
    .cloudProvider, .cloudProviderSubtitle, .baseURLLabel, .baseURLPlaceholder,
    .endpoint, .accountBalance, .fetchingBalance, .refreshOpenRouterBalance,
    .budgetLimit, .qwenSubscriptionBanner, .apiKeyLabel, .apiKeysCountLabel,
    .enableAllKeys, .testOnlyKey, .manageKeys, .manageKeysHelp, .addKey, .addKeyHelp,
    .disabled, .removeAPIKey, .polishingModelField, .selectModel, .modelID,
    .refreshModelList, .keyNonLatinError, .modelSpecContext, .modelSpecInput,
    .modelSpecOutput, .selectPolishingModelTitle, .modelsCount, .favoritesCount,
    .searchModelsPlaceholder, .showAllModels, .badgeRecommended, .badgeNew,
    .badgeFavorite, .contextLengthChip, .inputPriceChip, .outputPriceChip,
    .usageStatistics, .resetProviderStats, .resetProviderStatsHelp, .estCost,
    .totalLabel, .spentLabel, .balanceRemaining, .keyDisabledHelp, .keyActiveHelp,
    .apiKeyNumber, .apiKeyNumberPrimary, .enterAPIKey, .hideAPIKey, .showAPIKey,
    .favoritesFilter, .allFilter, .filterByFavorites, .noFavoriteModels,
    .noMatchingModels, .removeFromFavorites, .addToFavorites,
    // Misc screens (notes, translation modal, hotkey, local models, polishing, prompts, sidebar)
    .showVariant, .generateMarkdown, .model, .pasteFromClipboard,
    .pasteFromClipboardHelp, .hotkeyOptionHint, .translationWindowLabel,
    .translationWindowDesc, .quickTranslationLabel, .quickTranslationDesc,
    .openSettingsLabel, .openSettingsDesc, .transcriptionEngine, .engine,
    .localModelsHint, .googleAPI, .geminiModel, .googleAPIBody,
    .scanForLocalModels, .scanForLocalModelsBody, .scanning, .scan,
    .skippedUnsupportedModels, .localPolishingSupportHint, .markdown,
    .remove, .keyConfigured, .noAPIKey, .copied, .defaultModelName,
    .removeCustomModelHelp, .noNewModelsFound, .foundModelsCount, .cloudDictationUsesGemini,
    // HUD skins
    .hudStyle, .hudStyleCapsule, .hudStyleTech, .hudStyleVertical,
    // B3 — speech-language pair (plan §7.1, §9.4): resolves in every locale
    // via its own 15-locale map (B5).
    .languagePairSectionTitle, .primaryLanguage, .primaryLanguageHint,
    .additionalLanguage, .additionalLanguageHint, .additionalSameAsPrimary,
    .languagePairEngineNote,
    // B4 — Help bilingual section (plan §8.1)
    .helpBilingualTitle, .helpBilingualIntro, .helpBilingualPrimary,
    .helpBilingualAdditional, .helpBilingualNotAlwaysOutput, .helpBilingualWhere,
    .helpBilingualOnboarding, .helpBilingualSettingsPath, .helpBilingualCanary,
    .helpBilingualHUD, .helpBilingualAutoEngines, .helpBilingualPolishNote
]

@Test
func everySettingsKeyIsLocalizedInEveryLanguage() {
    #expect(!settingsKeys.isEmpty, "Expected settings keys to exist in AppTextKey")
    #expect(concreteLanguages.count == 15, "Expected 15 concrete UI languages")

    for language in concreteLanguages {
        for key in settingsKeys {
            let value = AppText.localized(key, language: language)
            #expect(
                !value.isEmpty,
                "Settings key \(key.rawValue) resolved to an empty string for \(language.rawValue)"
            )
            #expect(
                value != key.rawValue,
                "Settings key \(key.rawValue) fell back to its raw key for \(language.rawValue)"
            )
        }
    }
}

@Test
func settingsKeysAreActuallyTranslatedBeyondEnglish() {
    // Keys whose translations are expected to genuinely differ from English in
    // non-Latin / non-English locales (brand-neutral, clearly translatable
    // strings). A silent English fallback here means a missing translation.
    // B5 (plan §9): the B3 speech-language pair and the B4 Help bilingual
    // section are real 15-locale strings — they must differ in every non-EN
    // locale, never fall back to the English source.
    let translatedKeys: [AppTextKey] = [
        .clearGlossaryTitle, .glossaryCleared, .useGlossary, .addEntry,
        .cloudProvider, .accountBalance, .removeAPIKey, .usageStatistics,
        .translationWindowLabel, .quickTranslationLabel, .openSettingsLabel,
        .transcriptionEngine, .scanForLocalModels, .scanning, .noNewModelsFound,
        .copied, .defaultModelName, .removeCustomModelHelp, .cloudDictationUsesGemini,
        .hudStyle, .hudStyleCapsule, .hudStyleTech, .hudStyleVertical,
        // B3 — Settings speech-language pair (plan §7.1)
        .languagePairSectionTitle, .primaryLanguage, .primaryLanguageHint,
        .additionalLanguage, .additionalLanguageHint, .additionalSameAsPrimary,
        .languagePairEngineNote,
        // B4 — Help bilingual section (plan §8.1)
        .helpBilingualTitle, .helpBilingualIntro, .helpBilingualPrimary,
        .helpBilingualAdditional, .helpBilingualNotAlwaysOutput, .helpBilingualWhere,
        .helpBilingualOnboarding, .helpBilingualSettingsPath, .helpBilingualCanary,
        .helpBilingualHUD, .helpBilingualAutoEngines, .helpBilingualPolishNote
    ]

    let english = UILanguagePreference.english
    // B5 (Tester): iterate ALL 14 non-EN concrete languages — a 4-locale
    // sample (ru/zh/ar/hi) could miss a silent EN fallback in the other 10.
    // Independently verified: 0 identical-to-EN across all 14 non-EN locales.
    for language in concreteLanguages where language != english {
        for key in translatedKeys {
            let localized = AppText.localized(key, language: language)
            let englishValue = AppText.localized(key, language: english)
            #expect(
                localized != key.rawValue,
                "Settings key \(key.rawValue) missing for \(language.rawValue)"
            )
            #expect(
                localized != englishValue,
                "Settings key \(key.rawValue) fell back to English for \(language.rawValue)"
            )
        }
    }
}

/// B3 — keys added for the Settings speech-language pair (plan §7.1, §9.4).
/// Full 15-locale maps landed in B5; EN remains the authoritative source.
private let b3SettingsSpeechLanguageKeys: [AppTextKey] = [
  .languagePairSectionTitle,
  .primaryLanguage,
  .primaryLanguageHint,
  .additionalLanguage,
  .additionalLanguageHint,
  .additionalSameAsPrimary,
  .languagePairEngineNote,
]

@Test
func settingsSpeechLanguageKeysResolveInEnglish() {
  // B3 requires real EN strings for the new keys — never the raw-key fallback.
  for key in b3SettingsSpeechLanguageKeys {
    let value = AppText.localized(key, language: .english)
    #expect(!value.isEmpty, "B3 key \(key.rawValue) has no English translation")
    #expect(
      value != key.rawValue,
      "B3 key \(key.rawValue) fell back to its raw key in English"
    )
  }
}

@Test
func settingsSpeechLanguageCopyAvoidsTargetAlwaysOutputTerminology() {
  // Plan §3.1 / §7.2: additional is a second language the user often uses —
  // never a "target" / "always output" language. Check every locale a user
  // could see (EN fallback included).
  for language in concreteLanguages {
    for key in b3SettingsSpeechLanguageKeys {
      let value = AppText.localized(key, language: language).lowercased()
      #expect(!value.contains("target always"))
      #expect(!value.contains("target output"))
      #expect(!value.contains("always output"))
    }
  }
}

/// B4 — keys added for the Help bilingual section (plan §8.1).
/// Full 15-locale maps landed in B5; EN remains the authoritative source.
private let b4HelpBilingualKeys: [AppTextKey] = [
    .helpBilingualTitle,
    .helpBilingualIntro,
    .helpBilingualPrimary,
    .helpBilingualAdditional,
    .helpBilingualNotAlwaysOutput,
    .helpBilingualWhere,
    .helpBilingualOnboarding,
    .helpBilingualSettingsPath,
    .helpBilingualCanary,
    .helpBilingualHUD,
    .helpBilingualAutoEngines,
    .helpBilingualPolishNote
]

@Test
func helpBilingualKeysResolveInEnglish() {
    // B4 requires real EN strings for the new Help bilingual keys — never raw-key fallback.
    for key in b4HelpBilingualKeys {
        let value = AppText.localized(key, language: .english)
        #expect(!value.isEmpty, "B4 key \(key.rawValue) has no English translation")
        #expect(
            value != key.rawValue,
            "B4 key \(key.rawValue) fell back to its raw key in English"
        )
    }
}

@Test
func helpBilingualCopyAvoidsUnnegatedTargetAlwaysOutputTerminology() {
    // Plan §3.1 / §8.1: additional language is a second language the user often uses —
    // never a "target" / "always output" language promise. "Target always output"
    // may only appear when explicitly negated (e.g., "not a 'target always output'").
    for language in concreteLanguages {
        for key in b4HelpBilingualKeys {
            let value = AppText.localized(key, language: language).lowercased()
            let phrases = ["target always output", "target output", "always output"]
            for phrase in phrases {
                if value.contains(phrase) {
                    #expect(
                        value.contains("not a") || value.contains("not "),
                        "B4 key \(key.rawValue) contained '\(phrase)' without negation in \(language.rawValue)"
                    )
                }
            }
        }
    }
}

@Test
func helpBilingualCopyDescribesPrimaryAndAdditionalModel() {
    let english = UILanguagePreference.english
    let intro = AppText.localized(.helpBilingualIntro, language: english).lowercased()
    let primary = AppText.localized(.helpBilingualPrimary, language: english).lowercased()
    let additional = AppText.localized(.helpBilingualAdditional, language: english).lowercased()
    let canary = AppText.localized(.helpBilingualCanary, language: english).lowercased()
    let polish = AppText.localized(.helpBilingualPolishNote, language: english).lowercased()

    #expect(intro.contains("primary language") && intro.contains("additional language"))
    #expect(primary.contains("primary language"))
    #expect(additional.contains("additional language"))
    #expect(canary.contains("canary") && (canary.contains("no a") || canary.contains("does not have an a")))
    #expect(polish.contains("polishing") && polish.contains("after transcription"))
}

@Test
func helpBilingualSettingsPathMentionsHotkeyAndYourLanguages() {
    let english = UILanguagePreference.english
    let settingsPath = AppText.localized(.helpBilingualSettingsPath, language: english).lowercased()
    #expect(settingsPath.contains("hotkey"), "helpBilingualSettingsPath should mention Hotkey")
    #expect(settingsPath.contains("your languages"), "helpBilingualSettingsPath should mention Your Languages")
}

@Test
func helpLangHelpHUDConsistentWithBilingualModel() {
    // Spot-check: helpLang/helpHUD copy should not contradict the bilingual model.
    // Bilingual model: additional = second language for quick switching, NOT target always output.
    let english = UILanguagePreference.english
    
    // helpLangForced should mention additional language as default, not target always output
    let langForced = AppText.localized(.helpLangForced, language: english).lowercased()
    #expect(langForced.contains("additional language"), "helpLangForced should reference additional language")
    #expect(!langForced.contains("target always output"), "helpLangForced should not use 'target always output' terminology")
    
    // helpHUDLeftLetter should mention additional language as default letter
    let hudLeftLetter = AppText.localized(.helpHUDLeftLetter, language: english).lowercased()
    #expect(hudLeftLetter.contains("additional language"), "helpHUDLeftLetter should reference additional language")
    
    // helpHUDControlLanguage should describe A as auto-detect and letter as force output
    let hudControlLang = AppText.localized(.helpHUDControlLanguage, language: english).lowercased()
    #expect(hudControlLang.contains("auto"), "helpHUDControlLanguage should mention auto-detect for A")
    #expect(hudControlLang.contains("force") || hudControlLang.contains("letter"), "helpHUDControlLanguage should mention force output for letter")
    
    // helpLangWhere should reference Settings -> Hotkey -> Your Languages
    let langWhere = AppText.localized(.helpLangWhere, language: english).lowercased()
    #expect(langWhere.contains("hotkey") && langWhere.contains("your languages"), "helpLangWhere should reference Hotkey -> Your Languages")
}

/// B5 (Tester gap-hunt) — helpLang*/helpHUD* families rewritten for the
/// bilingual model (plan §8.2). Every key must be a real translation in ALL
/// 14 non-EN locales — never a silent EN fallback (the 4-locale ru/zh/ar/hi
/// sample alone could miss es/de/fr/it/pt/ja/ko/uk/tr/pl).
private let helpLangHelpHUDKeys: [AppTextKey] = [
    .helpLangIntro, .helpLangAuto, .helpLangForced, .helpLangEnglishNote,
    .helpLangOtherNote, .helpLangWhere,
    .helpHUDLeftA, .helpHUDLeftLetter, .helpHUDLeftTap, .helpHUDControlLanguage,
]

@Test
func helpLangHelpHUDDifferFromEnglishInEveryNonEnglishLocale() {
    let english = UILanguagePreference.english
    for language in concreteLanguages where language != english {
        for key in helpLangHelpHUDKeys {
            let localized = AppText.localized(key, language: language)
            let englishValue = AppText.localized(key, language: english)
            #expect(
                localized != key.rawValue,
                "helpLang/helpHUD key \(key.rawValue) missing for \(language.rawValue)"
            )
            #expect(
                localized != englishValue,
                "helpLang/helpHUD key \(key.rawValue) fell back to English for \(language.rawValue)"
            )
        }
    }
}

@Test
func helpLangHelpHUDCopyAvoidsUnnegatedTargetAlwaysOutputInEveryLocale() {
    // Plan §3.1 / §8.2: the rewritten helpLang*/helpHUD* copy must not
    // reintroduce the old single-"target" product promise in ANY locale —
    // "target always output" may only appear when explicitly negated.
    for language in concreteLanguages {
        for key in helpLangHelpHUDKeys {
            let value = AppText.localized(key, language: language).lowercased()
            let phrases = ["target always output", "target output", "always output"]
            for phrase in phrases {
                if value.contains(phrase) {
                    #expect(
                        value.contains("not a") || value.contains("not "),
                        "helpLang/helpHUD key \(key.rawValue) contained '\(phrase)' without negation in \(language.rawValue)"
                    )
                }
            }
        }
    }
}

/// B5 (Tester gap-hunt) — terminology presence: in sample locales (ru, zh,
/// ar, tr) the primary/additional pair must resolve to DISTINCT translations
/// (never identical labels or an EN fallback), the same-as-primary copy must
/// exist and differ from the plain primary/additional labels, and onboarding
/// must share the exact same-as-primary wording with Settings (plan §6.2/§7.1).
@Test
func primaryAdditionalTerminologyDistinctInSampleLocales() {
    let sampleLocales: [UILanguagePreference] = [.russian, .chinese, .arabic, .turkish]
    for language in sampleLocales {
        let primary = AppText.localized(.primaryLanguage, language: language)
        let additional = AppText.localized(.additionalLanguage, language: language)
        let settingsSameAs = AppText.localized(.additionalSameAsPrimary, language: language)
        let onboardingSameAs = AppText.localized(.onboardingAdditionalSameAsPrimary, language: language)
        let englishPrimary = AppText.localized(.primaryLanguage, language: .english)

        #expect(!primary.isEmpty && primary != AppTextKey.primaryLanguage.rawValue,
                "\(language.rawValue): primary language label missing")
        #expect(!additional.isEmpty && additional != AppTextKey.additionalLanguage.rawValue,
                "\(language.rawValue): additional language label missing")
        #expect(primary != additional,
                "\(language.rawValue): primary and additional labels are identical: '\(primary)'")
        #expect(primary != englishPrimary,
                "\(language.rawValue): primary language label fell back to English")
        #expect(!settingsSameAs.isEmpty && settingsSameAs != AppTextKey.additionalSameAsPrimary.rawValue,
                "\(language.rawValue): same-as-primary copy missing")
        #expect(settingsSameAs != primary && settingsSameAs != additional,
                "\(language.rawValue): same-as-primary copy should be a distinct phrase, got '\(settingsSameAs)'")
        #expect(settingsSameAs == onboardingSameAs,
                "\(language.rawValue): onboarding and Settings same-as-primary wording diverged")
    }
}

