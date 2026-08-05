import Foundation
import NativeBolabolCore
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
    // S2 — Settings local models recommendations (plan §9.4)
    .settingsLocalModelsRecommendedTitle,
    .settingsLocalModelsRecommendedHint,
    .settingsLocalModelsAllTitle,
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

private let s10LocalModelsKeys: [AppTextKey] = [
    .localModelsCanaryFlashTitle,
    .localModelsCanaryFlashSubtitle,
    .localModelsCanaryFlashBadge,
    .localModelsCanaryRuntimeBadge,
    .localModelsNoAutomaticLanguageBadge,
    .localModelsGigaAMTitle,
    .localModelsGigaAMSubtitle,
    .localModelsGigaAMBadge,
    .localModelsGigaAMRuntimeBadge,
    .localModelsCanary1BTitle,
    .localModelsCanary1BSubtitle,
    .localModelsCanary1BBadge,
    .localModelsNoAutomaticLanguageNotice,
    .localModelsLanguageModesHelpPath,
    .localModelsCanaryClampWarning,
    .localModelsCanaryLanguageBlock,
    .localModelsGigaAMRussianTip,
    .localModelsRequiresMacOS,
    .localModelsLargeDownloadTitle,
    .localModelsLargeDownloadMessage,
    .localModelsLargeDownloadConfirm,
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
func S10LocalModelsKeysResolveInEveryLocaleWithoutSilentFallback() {
    let english = UILanguagePreference.english
    let intentionallySharedKeyNames: Set<String> = [
        AppTextKey.localModelsCanaryRuntimeBadge.rawValue,
        AppTextKey.localModelsGigaAMRuntimeBadge.rawValue,
        AppTextKey.localModelsCanaryFlashTitle.rawValue,
        AppTextKey.localModelsCanary1BTitle.rawValue,
        AppTextKey.localModelsCanary1BBadge.rawValue,
    ]

    for language in concreteLanguages {
        for key in s10LocalModelsKeys {
            let value = AppText.localized(key, language: language)
            #expect(!value.isEmpty, "S10 key \(key.rawValue) is empty for \(language.rawValue)")
            #expect(value != key.rawValue, "S10 key \(key.rawValue) fell back to raw key")
            if language != english, !intentionallySharedKeyNames.contains(key.rawValue) {
                #expect(
                    value != AppText.localized(key, language: english),
                    "S10 key \(key.rawValue) silently fell back to English for \(language.rawValue)"
                )
            }
        }
    }
}

@Test
func S10LocalModelsCopyIsHonestAboutCapabilitiesAndLanguagePair() {
    let english = UILanguagePreference.english
    let flash = AppText.localized(.localModelsCanaryFlashSubtitle, language: english)
    let gigaAM = AppText.localized(.localModelsGigaAMSubtitle, language: english)
    let oneB = AppText.localized(.localModelsCanary1BSubtitle, language: english)
    let flashBadge = AppText.localized(.localModelsCanaryFlashBadge, language: english)
    let gigaBadge = AppText.localized(.localModelsGigaAMBadge, language: english)
    let oneBBadge = AppText.localized(.localModelsCanary1BBadge, language: english)
    let noAutoBadge = AppText.localized(.localModelsNoAutomaticLanguageBadge, language: english)
    let clamp = AppText.localized(.localModelsCanaryClampWarning, language: english).lowercased()
    let block = AppText.localized(.localModelsCanaryLanguageBlock, language: english).lowercased()
    let gigaTip = AppText.localized(.localModelsGigaAMRussianTip, language: english).lowercased()
    let helpPath = AppText.localized(.localModelsLanguageModesHelpPath, language: english)

    #expect(flash.contains("English") && flash.contains("German") && flash.contains("French") && flash.contains("Spanish"))
    #expect(gigaAM.contains("Russian only") && gigaAM.contains("Core ML/ANE"))
    #expect(oneB.contains("English ASR") && oneB.contains("English → French speech translation"))
    #expect(flashBadge == "Compact · 4 languages")
    #expect(gigaBadge == "Russian only")
    #expect(oneBBadge == "macOS 15+")
    #expect(noAutoBadge == "No auto-detect")
    #expect(!oneB.lowercased().contains("french asr"))
    #expect(!oneB.lowercased().contains("multilingual"))
    #expect(clamp.contains("primary") && clamp.contains("additional") && clamp.contains("not supported"))
    #expect(block.contains("primary") && block.contains("additional"))
    #expect(gigaTip.contains("primary") && gigaTip.contains("additional"))
    #expect(helpPath == "Settings → Help → Language modes")

    for language in concreteLanguages {
        for key in s10LocalModelsKeys {
            let value = AppText.localized(key, language: language).lowercased()
            #expect(!value.contains("target always output"))
            #expect(!value.contains("target output"))
            #expect(!value.contains("always output"))
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

/// S2 — Settings local models recommendations keys (plan §9.4).
/// Full 15-locale maps landed in S3.
private let s2SettingsLocalModelsKeys: [AppTextKey] = [
    .settingsLocalModelsRecommendedTitle,
    .settingsLocalModelsRecommendedHint,
    .settingsLocalModelsAllTitle,
]

@Test
func s2SettingsLocalModelsKeysResolveInEnglish() {
    for key in s2SettingsLocalModelsKeys {
        let value = AppText.localized(key, language: .english)
        #expect(!value.isEmpty, "S2 key \(key.rawValue) has no English translation")
        #expect(
            value != key.rawValue,
            "S2 key \(key.rawValue) fell back to its raw key in English"
        )
    }
}

@Test
func s2SettingsLocalModelsHintMentionsPrimaryAndAdditional() {
    let english = UILanguagePreference.english
    let hint = AppText.localized(.settingsLocalModelsRecommendedHint, language: english).lowercased()
    #expect(hint.contains("primary") && hint.contains("additional"),
            "S2 hint should mention primary and additional languages")
    #expect(!hint.contains("target always"),
            "S2 hint should not use 'target always' terminology")
}

@Test
func s2SettingsLocalModelsKeysResolveInEveryLanguage() {
    // S3 (plan §9.4): the S2 recommendation keys now have full 15-locale maps —
    // never an empty string or raw-key fallback in any concrete UI language.
    for language in concreteLanguages {
        for key in s2SettingsLocalModelsKeys {
            let value = AppText.localized(key, language: language)
            #expect(!value.isEmpty, "S2 key \(key.rawValue) resolved empty for \(language.rawValue)")
            #expect(
                value != key.rawValue,
                "S2 key \(key.rawValue) fell back to its raw key for \(language.rawValue)"
            )
        }
    }
}

@Test
func s2SettingsLocalModelsKeysDifferFromEnglishInEveryNonEnglishLocale() {
    // S3: a silent EN fallback in any non-EN locale means a missing translation.
    let english = UILanguagePreference.english
    for language in concreteLanguages where language != english {
        for key in s2SettingsLocalModelsKeys {
            let localized = AppText.localized(key, language: language)
            let englishValue = AppText.localized(key, language: english)
            #expect(
                localized != key.rawValue,
                "S2 key \(key.rawValue) missing for \(language.rawValue)"
            )
            #expect(
                localized != englishValue,
                "S2 key \(key.rawValue) fell back to English for \(language.rawValue)"
            )
        }
    }
}

@Test
func s2SettingsLocalModelsCopyAvoidsTargetAlwaysOutputTerminology() {
    // Plan §3.1 / §9.4: recommendations are an optional display order based on
    // the primary + additional speech languages — never a forced/target output
    // promise. Check every locale a user could see (EN fallback included).
    for language in concreteLanguages {
        for key in s2SettingsLocalModelsKeys {
            let value = AppText.localized(key, language: language).lowercased()
            #expect(!value.contains("target always"))
            #expect(!value.contains("target output"))
            #expect(!value.contains("always output"))
            #expect(!value.contains("always force"))
            #expect(!value.contains("force output"))
        }
    }
}

/// S2 — Recommendation grouping invariants (structural, not requiring UI render).
/// These assert the shared helper's contract that LocalModelsSettingsView relies on.
@Test
func onboardingModelRecommendationTopThreeReturnsUniqueModels() {
    let primary = "en"
    let additional = "ru"
    let available = TranscriptionModelCatalog.nativeWhisperKit.models

    let recommended = OnboardingModelRecommendation.topThree(
        primary: primary,
        additional: additional,
        available: available
    )

    // TopThree returns up to 3 unique models
    #expect(recommended.count <= 3, "topThree should return at most 3 models")

    let uniqueIDs = Set(recommended.map(\.id))
    #expect(uniqueIDs.count == recommended.count,
            "topThree should not contain duplicate models")

    // Recommended models must be from the available catalog
    for model in recommended {
        #expect(available.contains(where: { $0.id == model.id }),
                "Recommended model \(model.id) not found in catalog")
    }
}

@Test
func onboardingModelRecommendationTopThreeWithDifferentLanguagePairs() {
    let available = TranscriptionModelCatalog.nativeWhisperKit.models

    // Case 1: Russian primary — gigaAMRussian should rank first if available
    let ruPrimary = OnboardingModelRecommendation.topThree(
        primary: "ru",
        additional: "en",
        available: available
    )
    // Case 2: English primary, Russian additional — should still rank for ru
    let ruAdditional = OnboardingModelRecommendation.topThree(
        primary: "en",
        additional: "ru",
        available: available
    )
    // Case 3: Both canary-flash languages (en + de)
    let canaryFlash = OnboardingModelRecommendation.topThree(
        primary: "en",
        additional: "de",
        available: available
    )
    // Case 4: Neither primary nor additional is Russian or canary-flash
    let other = OnboardingModelRecommendation.topThree(
        primary: "fr",
        additional: "es",
        available: available
    )

    // Each call should return up to 3 models
    for result in [ruPrimary, ruAdditional, canaryFlash, other] {
        #expect(result.count <= 3)
        let ids = Set(result.map(\.id))
        #expect(ids.count == result.count, "No duplicates in result")
    }

    // The ranking order differs based on language pair
    // (We don't assert exact IDs to avoid brittleness, but verify the
    // helper is being invoked and returns valid catalog models)
    for result in [ruPrimary, ruAdditional, canaryFlash, other] {
        for model in result {
            #expect(available.contains(where: { $0.id == model.id }))
        }
    }
}

@Test
func s2RecommendationRecalculatesWhenSpeechPairChanges() {
    let available = TranscriptionModelCatalog.nativeWhisperKit.models

    let compactPair = OnboardingModelRecommendation.topThree(
        primary: "en",
        additional: "de",
        available: available
    )
    let broadPair = OnboardingModelRecommendation.topThree(
        primary: "hi",
        additional: "en",
        available: available
    )

    #expect(compactPair.map(\.id) == [
        "canary-180m-flash-coreml",
        "whisperkit-large-v3-full",
        "whisperkit-large-v3-turbo"
    ])
    #expect(broadPair.map(\.id) == [
        "whisperkit-large-v3-full",
        "whisperkit-large-v3-turbo",
        "canary-1b-v2-coreml"
    ])
    #expect(compactPair.map(\.id) != broadPair.map(\.id))
}

@Test
func recommendedAndRemainingPartitionFullCatalog() {
    // This test mirrors the LocalModelsSettingsView logic:
    // recommendedModels + remainingModels == full catalog, no overlaps.
    let speech = UserSpeechLanguages(primaryLanguageCode: "en", additionalLanguageCode: "ru")
    let available = TranscriptionModelCatalog.nativeWhisperKit.models

    let recommended = OnboardingModelRecommendation.topThree(
        primary: speech.primaryLanguageCode,
        additional: speech.additionalLanguageCode,
        available: available
    )
    let recommendedIDs = Set(recommended.map(\.id))
    let remaining = available.filter { !recommendedIDs.contains($0.id) }

    // Combined count equals catalog count
    #expect(recommended.count + remaining.count == available.count,
            "Recommended + remaining should partition the full catalog")

    // No overlap
    let remainingIDs = Set(remaining.map(\.id))
    #expect(recommendedIDs.isDisjoint(with: remainingIDs),
            "Recommended and remaining should be disjoint sets")

    // Every model appears exactly once across both groups
    let combined = recommended + remaining
    let combinedIDs = Set(combined.map(\.id))
    #expect(combinedIDs.count == available.count,
            "Every catalog model should appear exactly once")
}
