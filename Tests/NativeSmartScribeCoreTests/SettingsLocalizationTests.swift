import Foundation
import NativeSmartScribeCore
import Testing

/// Guards the settings/native-screen ↔ AppText key synchronisation added during
/// the i18n pass over the Glossary, API Providers, Hotkey, Local Models,
/// Polishing, Prompts, Notes, Translation and Sidebar surfaces. Every key that
/// those screens reference must resolve to a real, non-empty translation in all
/// 12 supported languages (never the raw-key fallback), and the genuinely
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
    .hudStyle, .hudStyleCapsule, .hudStyleTech, .hudStyleVertical
]

@Test
func everySettingsKeyIsLocalizedInEveryLanguage() {
    #expect(!settingsKeys.isEmpty, "Expected settings keys to exist in AppTextKey")
    #expect(concreteLanguages.count == 12, "Expected 12 concrete UI languages")

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
    let translatedKeys: [AppTextKey] = [
        .clearGlossaryTitle, .glossaryCleared, .useGlossary, .addEntry,
        .cloudProvider, .accountBalance, .removeAPIKey, .usageStatistics,
        .translationWindowLabel, .quickTranslationLabel, .openSettingsLabel,
        .transcriptionEngine, .scanForLocalModels, .scanning, .noNewModelsFound,
        .copied, .defaultModelName, .removeCustomModelHelp, .cloudDictationUsesGemini,
        .hudStyle, .hudStyleCapsule, .hudStyleTech, .hudStyleVertical
    ]

    let english = UILanguagePreference.english
    for language in [UILanguagePreference.russian, .chinese, .arabic, .hindi] {
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
