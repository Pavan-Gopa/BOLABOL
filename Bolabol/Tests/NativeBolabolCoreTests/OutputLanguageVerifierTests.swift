import Foundation
import NativeBolabolCore
import Testing

// ADR-029: OutputLanguageVerifier gates insertion. Probe-backed cases:
// mixed Russian with identifiers reads ru once code-like words are stripped;
// "Ок" reads ru / "OK" reads en, so short text is inconclusive by script.

@Test
func verifierPassesLongEnglishForEnglishTarget() {
    let text = "Please run swift build and check the NoteStore enforcement logic in Xcode today."
    let decision = OutputLanguageVerifier.verify(text: text, targetCode: "en", primaryCode: "ru", additionalCode: "en")
    guard case .pass(let detected, _) = decision else {
        Issue.record("expected pass, got \(decision)")
        return
    }
    #expect(detected == "en")
}

@Test
func verifierFailsLongRussianForEnglishTarget() {
    let text = "Привет! Это тестовая заметка на русском языке для проверки перевода."
    let decision = OutputLanguageVerifier.verify(text: text, targetCode: "en", primaryCode: "ru", additionalCode: "en")
    guard case .fail(let detected, let confidence) = decision else {
        Issue.record("expected fail, got \(decision)")
        return
    }
    #expect(detected == "ru")
    #expect(confidence >= 0.6)
}

@Test
func verifierPassesLongRussianForRussianTarget() {
    let text = "Привет! Это тестовая заметка на русском языке для проверки перевода."
    let decision = OutputLanguageVerifier.verify(text: text, targetCode: "ru", primaryCode: "ru", additionalCode: "en")
    guard case .pass(let detected, _) = decision else {
        Issue.record("expected pass, got \(decision)")
        return
    }
    #expect(detected == "ru")
}

@Test
func verifierDetectsUkrainianAgainstRussianTarget() {
    let text = "Привіт! Це тестова нотатка українською мовою для перевірки перекладу тексту."
    let decision = OutputLanguageVerifier.verify(text: text, targetCode: "ru", primaryCode: "ru", additionalCode: "uk")
    switch decision {
    case .fail(let detected, _):
        #expect(detected == "uk")
    case .inconclusive(let detected, _):
        // uk/ru are close; inconclusive never blocks insertion either.
        #expect(detected == "uk" || detected == "ru" || detected == nil)
    case .pass(let detected, _):
        Issue.record("Ukrainian text must not pass a Russian target (detected \(detected ?? "nil"))")
    }
}

@Test
func verifierPassesLongSpanishForSpanishTarget() {
    let text = "Hola, esta es una nota de prueba en español para verificar la traducción del texto."
    let decision = OutputLanguageVerifier.verify(text: text, targetCode: "es", primaryCode: "ru", additionalCode: "es")
    guard case .pass(let detected, _) = decision else {
        Issue.record("expected pass, got \(decision)")
        return
    }
    #expect(detected == "es")
}

@Test
func verifierStripsIdentifiersOnMixedCode() {
    // Probe: mixed Russian with code words reads en unless identifiers are stripped.
    let text = "Запусти swift build и проверь NoteStore.enforceAudioArchiveLimit в Xcode сегодня вечером"
    let decision = OutputLanguageVerifier.verify(text: text, targetCode: "en", primaryCode: "ru", additionalCode: "en")
    let stripped = OutputLanguageVerifier.strippingIdentifiersAndURLs(text)
    #expect(!stripped.contains("NoteStore.enforceAudioArchiveLimit"))
    // Ordinary lowercase words stay; only code-like tokens are stripped.
    #expect(stripped.contains("swift"))
    guard case .fail(let detected, _) = decision else {
        Issue.record("expected fail after identifier stripping, got \(decision)")
        return
    }
    #expect(detected == "ru")
}

@Test
func verifierShortTextIsInconclusiveByScript() {
    // "Ок" (Cyrillic) must not pass an English target — inconclusive, never a pass.
    let shortRu = OutputLanguageVerifier.verify(text: "Ок", targetCode: "en", primaryCode: "ru", additionalCode: "en")
    switch shortRu {
    case .pass(let detected, _):
        Issue.record("short Cyrillic text must not pass English target (detected \(detected ?? "nil"))")
    case .inconclusive, .fail:
        break
    }

    // "OK" (Latin) passes an English target through the script rule.
    let shortEn = OutputLanguageVerifier.verify(text: "OK", targetCode: "en", primaryCode: "ru", additionalCode: "en")
    guard case .pass(let detected, _) = shortEn else {
        Issue.record("expected pass for OK/en, got \(shortEn)")
        return
    }
    #expect(detected == "en")
}

@Test
func verifierEmptyTextIsInconclusive() {
    let decision = OutputLanguageVerifier.verify(text: "   ", targetCode: "en", primaryCode: "ru", additionalCode: "en")
    guard case .inconclusive = decision else {
        Issue.record("expected inconclusive for empty text, got \(decision)")
        return
    }
}

@Test(arguments: ["OK да", "API да", "Yes ок", "Привет", "Ок", "API готово"])
func verifierShortWrongScriptFailsEnglishTargetUnderAnyConstraints(text: String) {
    // S11 J2: the constrained recognizer reports `en` for these short texts
    // under both production constraint sets, so script alone must fail them.
    let ruConstrained = OutputLanguageVerifier.verify(text: text, targetCode: "en", primaryCode: "ru", additionalCode: "en")
    guard case .fail = ruConstrained else {
        Issue.record("expected fail for \(text) under [en, ru], got \(ruConstrained)")
        return
    }
    let enOnly = OutputLanguageVerifier.verify(text: text, targetCode: "en", primaryCode: "en", additionalCode: "en")
    guard case .fail = enOnly else {
        Issue.record("expected fail for \(text) under [en], got \(enOnly)")
        return
    }
}

@Test(arguments: ["OK", "Hi", "NASA", "NoteStore", "foo_bar", "42"])
func verifierShortLatinAndLetterlessPassEnglishTarget(text: String) {
    // Latin short text and letterless text (numbers, punctuation) still pass.
    let decision = OutputLanguageVerifier.verify(text: text, targetCode: "en", primaryCode: "en", additionalCode: "en")
    guard case .pass = decision else {
        Issue.record("expected pass for \(text), got \(decision)")
        return
    }
}
