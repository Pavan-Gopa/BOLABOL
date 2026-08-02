import Foundation
import Testing
@testable import NativeBlaboomCore

// Instruction builder lives in the app target; mirror critical detection helpers here
// via duplicated pure logic tests for the contract we care about in Core.

@Test
func geminiPlaceholderDetectionCatchesClassicFailures() {
    let needles = [
        "Please provide an audio recording. The quick brown fox jumps over the lazy dog.",
        "please provide audio",
        "The quick brown fox jumps over the lazy dog"
    ]
    for sample in needles {
        let lower = sample.lowercased()
        let hit =
            lower.contains("please provide an audio")
            || lower.contains("please provide audio")
            || lower.contains("quick brown fox jumps over the lazy dog")
        #expect(hit, "Should flag placeholder: \(sample)")
    }
}

@Test
func cloudRawPromptKeepsAudioLanguageAndLimitsEditing() {
    let prompt = CloudRawTranscriptionPrompt.instruction(
        forceTargetLanguage: false,
        targetLanguageName: ""
    )

    #expect(prompt.contains("Keep the language spoken in the audio"))
    #expect(prompt.contains("Apply light cleanup only"))
    #expect(prompt.contains("Do not summarize, reinterpret"))
    #expect(!prompt.contains("Variant 1"))
    #expect(!prompt.contains("Variant 2"))
}

@Test
func cloudRawPromptCanForceTargetLanguageWithoutAddingPolishing() {
    let prompt = CloudRawTranscriptionPrompt.instruction(
        forceTargetLanguage: true,
        targetLanguageName: "Italian"
    )

    #expect(prompt.contains("entire result in Italian"))
    #expect(prompt.contains("translate it faithfully into Italian"))
    #expect(prompt.contains("original order"))
    #expect(!prompt.contains("reconstruct"))
}
