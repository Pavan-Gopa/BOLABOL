import Testing
@testable import VaniScriptCore

@Suite("VaniScript help catalog")
struct VaniScriptHelpCatalogTests {
    @Test("provides a substantial bilingual product guide")
    func bilingualCatalog() throws {
        let english = VaniScriptHelpCatalog.list(language: .english)
        let russian = VaniScriptHelpCatalog.list(language: .russian)

        #expect(english.count >= 19)
        #expect(english.map(\.id) == russian.map(\.id))
        #expect(english.first?.title != russian.first?.title)
        #expect(english.contains { $0.id == "embedded-chat" })
        #expect(english.contains { $0.id == "visual-editor" })
    }

    @Test("finds accurate Russian and English how-to topics")
    func bilingualSearch() throws {
        let russian = VaniScriptHelpCatalog.search(
            query: "как экспортировать субтитры srt",
            language: .russian,
            limit: 3
        )
        let english = VaniScriptHelpCatalog.search(
            query: "connect Codex MCP agent",
            language: .english,
            limit: 3
        )

        #expect(russian.first?.id == "export-documents")
        #expect(english.first?.id == "settings-agents")
    }

    @Test("returns screen-aware next actions")
    func contextualHelp() {
        let upload = VaniScriptHelpCatalog.contextualHelp(
            screen: .upload,
            hasSource: false,
            hasSession: false,
            processingProgress: 0,
            hasShortsPlans: false,
            language: .english
        )
        let review = VaniScriptHelpCatalog.contextualHelp(
            screen: .review,
            hasSource: true,
            hasSession: true,
            processingProgress: 1,
            hasShortsPlans: false,
            language: .russian
        )

        #expect(upload.screen == "upload")
        #expect(upload.recommendedTopicIDs.contains("getting-started"))
        #expect(review.screen == "review")
        #expect(review.recommendedTopicIDs.contains("review-transcript"))
        #expect(review.nextActions.contains { $0.contains("Approve & Next") })
    }

    @Test("onboarding checklist covers the complete first project route")
    func onboardingChecklist() {
        let checklist = VaniScriptHelpCatalog.onboardingChecklist(language: .russian)

        #expect(checklist.steps.count >= 8)
        #expect(checklist.steps.contains { $0.contains("Initialize Engine") })
        #expect(checklist.steps.contains { $0.contains("Approve & Next") })
        #expect(checklist.steps.contains { $0.contains("Help Tour") })
    }
}
