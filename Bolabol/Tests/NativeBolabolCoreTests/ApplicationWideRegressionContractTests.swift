import Foundation
import Testing

@Test
func contentViewSettingsHumorLevelChangeUpdatesThePendingListeningSnapshot() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBolabol/Views/ContentView.swift",
        encoding: .utf8
    )
    let start = try #require(
        source.range(of: ".onChange(of: hotkeySettingsStore.settings.humorLevel)")
    )
    let remaining = source[start.lowerBound...]
    let end = remaining.range(of: ".onChange(", options: [], range: remaining.index(after: start.lowerBound)..<remaining.endIndex)
        ?? remaining.endIndex..<remaining.endIndex
    let observer = String(remaining[..<end.lowerBound])

    let guardsRecording = observer.contains("if audioRecorder.isRecording")
    let updatesPendingLevel = observer.contains("updatePendingHotkeyHumorSession(level: level)")
    #expect(guardsRecording)
    #expect(updatesPendingLevel)
}

@Test
func onboardingTryRecordNotificationHasAProductionConsumer() throws {
    let onboarding = try String(
        contentsOfFile: "Sources/NativeBolabol/Views/OnboardingView.swift",
        encoding: .utf8
    )
    let content = try String(
        contentsOfFile: "Sources/NativeBolabol/Views/ContentView.swift",
        encoding: .utf8
    )
    let app = try String(
        contentsOfFile: "Sources/NativeBolabol/App/NativeBolabolApp.swift",
        encoding: .utf8
    )

    #expect(onboarding.contains("tryMode(notification: .nativeBolabolHotkeyTriggered)"))
    let hasConsumer = content.contains("publisher(for: .nativeBolabolHotkeyTriggered)")
        || app.contains("publisher(for: .nativeBolabolHotkeyTriggered)")
        || app.contains("forName: .nativeBolabolHotkeyTriggered")
    #expect(hasConsumer)
}

@Test
func acceptedADR021KeepsCanaryOutOfTheTranslationRuntime() throws {
    let decisions = try String(
        contentsOfFile: "AI_Workflow_Kit/docs/DECISIONS.md",
        encoding: .utf8
    )
    let adrStart = try #require(decisions.range(of: "## ADR-021"))
    let adrTail = decisions[adrStart.lowerBound...]
    let adrEnd = adrTail.range(of: "\n---", options: [], range: adrTail.index(after: adrStart.lowerBound)..<adrTail.endIndex)
        ?? adrTail.endIndex..<adrTail.endIndex
    let adr = String(adrTail[..<adrEnd.lowerBound])

    #expect(adr.contains("**Status:** Accepted"))
    #expect(adr.contains("Canary remains an audio transcription model only"))
    #expect(!FileManager.default.fileExists(
        atPath: "Sources/NativeBolabol/Services/CanarySpeechTranslationRuntime.swift"
    ))

    let translationView = try String(
        contentsOfFile: "Sources/NativeBolabol/Views/TranslationModalView.swift",
        encoding: .utf8
    )
    let exposesCanaryTranslationHandler = translationView.contains("onCanaryTranslation")
    let exposesCanaryTranslationProvider = translationView.contains("localCanaryPrefix")
    #expect(!exposesCanaryTranslationHandler)
    #expect(!exposesCanaryTranslationProvider)
}

@Test
func translationUserFeedbackAndGlossaryActionsUseLocalizedCopy() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBolabol/Views/TranslationModalView.swift",
        encoding: .utf8
    )
    let hardCodedUserCopy = [
        "Pasted from clipboard",
        "Copied to clipboard!",
        "selectionActionTitle: \"Add to Glossary\""
    ]

    for literal in hardCodedUserCopy {
        let isLocalized = !source.contains(literal)
        #expect(isLocalized, "user-visible Translation copy must resolve through AppText: \(literal)")
    }
}
