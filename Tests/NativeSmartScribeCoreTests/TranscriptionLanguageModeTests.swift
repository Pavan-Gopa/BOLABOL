import NativeSmartScribeCore
import Testing

@Test
func transcriptionLanguageModeTogglesBetweenAutoAndTarget() {
    #expect(TranscriptionLanguageMode.auto.toggled() == .target)
    #expect(TranscriptionLanguageMode.target.toggled() == .auto)
}

@Test
func transcriptionLanguageModeRoundTripsRawValue() {
    #expect(TranscriptionLanguageMode(rawValue: "auto") == .auto)
    #expect(TranscriptionLanguageMode(rawValue: "target") == .target)
    #expect(TranscriptionLanguageMode(rawValue: "unknown") == nil)
}
