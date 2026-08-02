import Foundation
import NativeBlaboomCore
import Testing

// B1 — canonical speech-language pair defaults + migration (plan §3.3, §3.4).

@Test
func userSpeechLanguagesDefaultsMapKnownSystemLocale() {
    let languages = UserSpeechLanguages.makeDefaults(systemLocale: Locale(identifier: "ru_RU"))

    #expect(languages.primaryLanguageCode == "ru")
    #expect(languages.additionalLanguageCode == "en")
    #expect(!languages.usesSameAdditionalAsPrimary)
}

@Test
func userSpeechLanguagesDefaultsMapAdditionalLocales() {
    #expect(UserSpeechLanguages.makeDefaults(systemLocale: Locale(identifier: "pt_BR")).primaryLanguageCode == "pt")
    #expect(UserSpeechLanguages.makeDefaults(systemLocale: Locale(identifier: "de_DE")).primaryLanguageCode == "de")
    #expect(UserSpeechLanguages.makeDefaults(systemLocale: Locale(identifier: "zh_Hans")).primaryLanguageCode == "zh")
    #expect(UserSpeechLanguages.makeDefaults(systemLocale: Locale(identifier: "uk_UA")).primaryLanguageCode == "uk")
    #expect(UserSpeechLanguages.makeDefaults(systemLocale: Locale(identifier: "tr_TR")).primaryLanguageCode == "tr")
}

@Test
func userSpeechLanguagesDefaultsFallBackToEnglishForUnknownLocale() {
    let languages = UserSpeechLanguages.makeDefaults(systemLocale: Locale(identifier: "nl_NL"))

    #expect(languages.primaryLanguageCode == "en")
    #expect(languages.additionalLanguageCode == "en")
    #expect(languages.usesSameAdditionalAsPrimary)
}

@Test
func userSpeechLanguagesDefaultsUseSameAsPrimaryPolicyWhenPrimaryIsEnglish() {
    let languages = UserSpeechLanguages.makeDefaults(systemLocale: Locale(identifier: "en_US"))

    #expect(languages.primaryLanguageCode == "en")
    #expect(languages.additionalLanguageCode == "en")
    #expect(languages.usesSameAdditionalAsPrimary)
}

@Test
func userSpeechLanguagesAdditionalMayEqualPrimary() {
    let languages = UserSpeechLanguages(primaryLanguageCode: "ru", additionalLanguageCode: "ru")

    #expect(languages.primaryLanguageCode == "ru")
    #expect(languages.additionalLanguageCode == "ru")
    #expect(languages.usesSameAdditionalAsPrimary)
}

// B2 — primary-change semantics used by the onboarding primary step (plan
// §6.2): same-as-primary pairs stay mirrored, explicit additional choices stay.

@Test
func userSpeechLanguagesSettingPrimaryKeepsSameAsPrimaryMirror() {
    let sameAsPrimary = UserSpeechLanguages(
        primaryLanguageCode: "ru",
        additionalLanguageCode: "ru"
    ).settingPrimary("de")

    #expect(sameAsPrimary.primaryLanguageCode == "de")
    #expect(sameAsPrimary.additionalLanguageCode == "de")
    #expect(sameAsPrimary.usesSameAdditionalAsPrimary)
}

@Test
func userSpeechLanguagesSettingPrimaryKeepsExplicitAdditional() {
    let explicit = UserSpeechLanguages(
        primaryLanguageCode: "ru",
        additionalLanguageCode: "en"
    ).settingPrimary("de")

    #expect(explicit.primaryLanguageCode == "de")
    #expect(explicit.additionalLanguageCode == "en")
    #expect(!explicit.usesSameAdditionalAsPrimary)
}

@Test
func userSpeechLanguagesSettingPrimaryNormalizesInput() {
    let changed = UserSpeechLanguages(
        primaryLanguageCode: "ru",
        additionalLanguageCode: "en"
    ).settingPrimary(" FR ")

    #expect(changed.primaryLanguageCode == "fr")
    #expect(changed.additionalLanguageCode == "en")
}

@Test
func userSpeechLanguagesSameAsPrimaryHelperMirrorsPrimary() {
    let languages = UserSpeechLanguages(primaryLanguageCode: "hi", additionalLanguageCode: "en")
        .settingAdditionalSameAsPrimary()

    #expect(languages.primaryLanguageCode == "hi")
    #expect(languages.additionalLanguageCode == "hi")
    #expect(languages.usesSameAdditionalAsPrimary)
}

// B3 — additional-change semantics used by the Settings additional picker
// (plan §7.1): primary stays untouched; same-as-primary is expressed by
// additional == primary (plan §3.4).

@Test
func userSpeechLanguagesSettingAdditionalKeepsPrimary() {
    let changed = UserSpeechLanguages(
        primaryLanguageCode: "ru",
        additionalLanguageCode: "en"
    ).settingAdditional("de")

    #expect(changed.primaryLanguageCode == "ru")
    #expect(changed.additionalLanguageCode == "de")
    #expect(!changed.usesSameAdditionalAsPrimary)
}

@Test
func userSpeechLanguagesSettingAdditionalNormalizesInput() {
    let changed = UserSpeechLanguages(
        primaryLanguageCode: "ru",
        additionalLanguageCode: "en"
    ).settingAdditional(" FR ")

    #expect(changed.primaryLanguageCode == "ru")
    #expect(changed.additionalLanguageCode == "fr")
}

@Test
func userSpeechLanguagesSettingAdditionalToPrimaryRestoresSameAsPrimary() {
    let languages = UserSpeechLanguages(
        primaryLanguageCode: "hi",
        additionalLanguageCode: "en"
    ).settingAdditional("hi")

    #expect(languages.primaryLanguageCode == "hi")
    #expect(languages.additionalLanguageCode == "hi")
    #expect(languages.usesSameAdditionalAsPrimary)
}

@Test
func userSpeechLanguagesNormalizesCodes() {
    let languages = UserSpeechLanguages(primaryLanguageCode: " RU ", additionalLanguageCode: "English")

    #expect(languages.primaryLanguageCode == "ru")
    #expect(languages.additionalLanguageCode == "english")
}

@Test
func userSpeechLanguagesMigrationSeedsPrimaryFromLegacyTranscriptionCode() {
    let languages = UserSpeechLanguages.migrating(
        legacyTranscriptionCode: "ru",
        legacyTargetLanguageName: "English",
        systemLocale: Locale(identifier: "en_US")
    )

    #expect(languages.primaryLanguageCode == "ru")
    #expect(languages.additionalLanguageCode == "en")
}

@Test
func userSpeechLanguagesMigrationSeedsAdditionalFromLegacyForceTargetName() {
    let languages = UserSpeechLanguages.migrating(
        legacyTranscriptionCode: "en",
        legacyTargetLanguageName: "German",
        systemLocale: Locale(identifier: "en_US")
    )

    #expect(languages.primaryLanguageCode == "en")
    #expect(languages.additionalLanguageCode == "de")
}

@Test
func userSpeechLanguagesMigrationAcceptsLegacyTargetCodesAndEndonyms() {
    let byCode = UserSpeechLanguages.migrating(
        legacyTranscriptionCode: "de",
        legacyTargetLanguageName: "en",
        systemLocale: Locale(identifier: "de_DE")
    )
    #expect(byCode.primaryLanguageCode == "de")
    #expect(byCode.additionalLanguageCode == "en")

    let byEndonym = UserSpeechLanguages.migrating(
        legacyTranscriptionCode: "de",
        legacyTargetLanguageName: "Русский",
        systemLocale: Locale(identifier: "de_DE")
    )
    #expect(byEndonym.primaryLanguageCode == "de")
    #expect(byEndonym.additionalLanguageCode == "ru")
}

@Test
func userSpeechLanguagesMigrationNeverDuplicatesTargetIntoPrimary() {
    // Same legacy value in both slots — additional stays "en", primary wins.
    let languages = UserSpeechLanguages.migrating(
        legacyTranscriptionCode: "fr",
        legacyTargetLanguageName: "French",
        systemLocale: Locale(identifier: "en_US")
    )

    #expect(languages.primaryLanguageCode == "fr")
    #expect(languages.additionalLanguageCode == "en")
}

@Test
func userSpeechLanguagesMigrationIgnoresUnknownLegacyValues() {
    let languages = UserSpeechLanguages.migrating(
        legacyTranscriptionCode: "xx",
        legacyTargetLanguageName: "Klingon",
        systemLocale: Locale(identifier: "nl_NL")
    )

    #expect(languages.primaryLanguageCode == "en")
    #expect(languages.additionalLanguageCode == "en")
    #expect(languages.usesSameAdditionalAsPrimary)
}

@Test
func userSpeechLanguagesMigrationRoundTripsThroughCodable() throws {
    let original = UserSpeechLanguages.migrating(
        legacyTranscriptionCode: "ru",
        legacyTargetLanguageName: "English"
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(UserSpeechLanguages.self, from: data)

    #expect(decoded == original)
    #expect(decoded.primaryLanguageCode == "ru")
    #expect(decoded.additionalLanguageCode == "en")
}

@Test
func userSpeechLanguagesDecodesLegacyPayloadWithoutKeys() throws {
    let data = Data("{}".utf8)

    let languages = try JSONDecoder().decode(UserSpeechLanguages.self, from: data)

    #expect(languages.primaryLanguageCode == "en")
    #expect(languages.additionalLanguageCode == "en")
}
