import NativeBolabolCore
import Testing

@Test
func transcriptionLanguageModeTogglesBetweenAutoAndTarget() {
    #expect(TranscriptionLanguageMode.auto.toggled() == .target)
    #expect(TranscriptionLanguageMode.target.toggled() == .auto)
}

@Test
func transcriptionLanguageModeIsCaseIterableInStableOrder() {
    #expect(TranscriptionLanguageMode.allCases == [.auto, .target, .switchable, .fixed, .unavailable])
    #expect(TranscriptionLanguageMode.auto.id == "auto")
    #expect(TranscriptionLanguageMode.target.id == "target")
    #expect(TranscriptionLanguageMode.automatic == .auto)
    #expect(TranscriptionLanguageMode.explicitSwitchable == .switchable)
    #expect(TranscriptionLanguageMode.explicitFixed == .fixed)
}

@Test
func transcriptionLanguageModeRoundTripsRawValue() {
    #expect(TranscriptionLanguageMode(rawValue: "auto") == .auto)
    #expect(TranscriptionLanguageMode(rawValue: "target") == .target)
    #expect(TranscriptionLanguageMode(rawValue: "explicit-switchable") == .switchable)
    #expect(TranscriptionLanguageMode(rawValue: "explicit-fixed") == .fixed)
    #expect(TranscriptionLanguageMode(rawValue: "unavailable") == .unavailable)
    #expect(TranscriptionLanguageMode(rawValue: "unknown") == nil)
}

@Test
func transcriptionLanguageModeKeepsExplicitStatesStable() {
    #expect(TranscriptionLanguageMode.switchable.toggled() == .switchable)
    #expect(TranscriptionLanguageMode.fixed.toggled() == .fixed)
    #expect(TranscriptionLanguageMode.unavailable.toggled() == .unavailable)
}
