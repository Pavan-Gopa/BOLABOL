import Testing
@testable import VaniScriptCore

@Suite("Universal architecture parity")
struct UniversalArchitectureTests {
    @Test("keeps the Universal workflow order and opens Visual Editor as a dedicated workspace")
    func workflowOrder() {
        #expect(UniversalWorkflowScreen.allCases.map(\.rawValue) == [
            "upload",
            "config",
            "processing",
            "review",
            "export",
            "visualEditor",
        ])
    }

    @Test("keeps the Universal settings tabs")
    func settingsTabs() {
        #expect(UniversalSettingsTab.allCases.map(\.title) == [
            "API Keys",
            "Models",
            "Appearance",
            "Glossary",
            "Chunking",
            "Transcription",
            "Prompts",
            "Statistics",
        ])
    }

    @Test("tracks the Universal service modules to port")
    func serviceModules() {
        #expect(UniversalArchitectureMap.serviceModules == [
            "storage",
            "transcription",
            "chunk-queue",
            "structured-translation",
            "local-translation",
            "cloud-translation",
            "literary-polish",
            "audio-review",
            "document-export",
            "shorts-reels",
            "render-engine",
        ])
    }
}
