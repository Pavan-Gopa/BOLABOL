import NativeBlaboomCore
import Testing

// B1 — canonical picker order (plan §5.3): English first → Europe (alpha by
// English name) → Asia & other (alpha). System sentinel sits apart.

@Test
func languagePickerOrderPutsEnglishFirstExcludingSystemSentinel() {
    #expect(LanguagePickerOrder.speechLanguages.first?.code == "en")
    #expect(LanguagePickerOrder.orderedSpeechCodes.first == "en")

    // UI-language list: System sentinel first, then English immediately after
    // — never between `en` and `fr`.
    #expect(LanguagePickerOrder.uiLanguages.first == .system)
    #expect(LanguagePickerOrder.uiLanguages.dropFirst().first == .english)
}

@Test
func languagePickerOrderRussianIsNotSecond() {
    #expect(LanguagePickerOrder.orderedSpeechCodes.count >= 3)
    #expect(LanguagePickerOrder.orderedSpeechCodes[0] == "en")
    #expect(LanguagePickerOrder.orderedSpeechCodes[1] == "fr")
    #expect(LanguagePickerOrder.orderedSpeechCodes[1] != "ru")
    #expect(LanguagePickerOrder.orderedSpeechCodes[2] != "ru")
}

@Test
func languagePickerOrderEuropeComesBeforeAsia() {
    let codes = LanguagePickerOrder.orderedSpeechCodes
    let ruIndex = codes.firstIndex(of: "ru")
    let zhIndex = codes.firstIndex(of: "zh")

    #expect(ruIndex != nil)
    #expect(zhIndex != nil)
    #expect(ruIndex! < zhIndex!)
}

@Test
func languagePickerOrderSystemSentinelIsNotBetweenEnglishAndFrench() {
    let ui = LanguagePickerOrder.uiLanguages

    #expect(ui.firstIndex(of: .system) == 0)
    #expect(ui.firstIndex(of: .english) == 1)
    #expect(ui.firstIndex(of: .french) == 2)
    #expect(!ui.contains { $0 == .system && ui.firstIndex(of: .system)! > 0 })
}

@Test
func languagePickerOrderSpeechListIsExactCanonicalSequence() {
    #expect(LanguagePickerOrder.orderedSpeechCodes == [
        "en", // English
        "fr", "de", "it", "pl", "pt", "ru", "es", "tr", "uk", // Europe
        "ar", "zh", "hi", "ja", "ko" // Asia & other
    ])
}

@Test
func languagePickerOrderSpeechLanguagesHaveEndonymDisplayNames() {
    let languages = LanguagePickerOrder.speechLanguages

    #expect(languages.count == 15)
    #expect(languages.first { $0.code == "en" }?.displayName == "English")
    #expect(languages.first { $0.code == "de" }?.displayName == "Deutsch")
    #expect(languages.first { $0.code == "ru" }?.displayName == "Русский")
    #expect(languages.first { $0.code == "zh" }?.displayName == "中文")
    for language in languages {
        #expect(!language.displayName.isEmpty)
        #expect(language.displayName != language.code)
    }
}

@Test
func languagePickerOrderResolvesCodesAndNames() {
    #expect(LanguagePickerOrder.isKnownSpeechCode("en"))
    #expect(LanguagePickerOrder.isKnownSpeechCode("UK"))
    #expect(!LanguagePickerOrder.isKnownSpeechCode("xx"))
    #expect(LanguagePickerOrder.speechCode(forNameOrCode: "en") == "en")
    #expect(LanguagePickerOrder.speechCode(forNameOrCode: "English") == "en")
    #expect(LanguagePickerOrder.speechCode(forNameOrCode: "Русский") == "ru")
    #expect(LanguagePickerOrder.speechCode(forNameOrCode: "  FR  ") == "fr")
    #expect(LanguagePickerOrder.speechCode(forNameOrCode: "") == nil)
    #expect(LanguagePickerOrder.speechCode(forNameOrCode: "Klingon") == nil)
}
