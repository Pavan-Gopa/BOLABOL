import Foundation
import Testing
@testable import VaniScriptCore

@MainActor
@Suite("VaniScript MCP glossary tools")
struct McpGlossaryToolServiceTests {
    @Test("creates, searches, updates, exports, and imports glossary entries")
    func glossaryCRUD() throws {
        let confirmations = McpConfirmationStore()
        var workflow = makeWorkflow()
        workflow.settings.glossary = []

        let created = try McpGlossaryToolService.execute(
            name: "create_glossary_entry",
            arguments: [
                "source": "Krsna",
                "translation": "Кришна",
                "variants": ["Krishna", "Kṛṣṇa"],
                "category": "Names",
            ],
            workflow: workflow,
            confirmationStore: confirmations
        )
        workflow = created.workflow
        let entryID = try #require(workflow.settings.glossary.first?.id)
        #expect(McpProjectRevision.make(workflow: workflow) != McpProjectRevision.make(workflow: makeWorkflow()))

        let search = try McpGlossaryToolService.execute(
            name: "search_glossary",
            arguments: ["query": "kṛṣṇa"],
            workflow: workflow,
            confirmationStore: confirmations
        )
        #expect((search.details["entries"] as? [[String: Any]])?.count == 1)

        let updated = try McpGlossaryToolService.execute(
            name: "update_glossary_entry",
            arguments: ["entryId": entryID, "remember": false],
            workflow: workflow,
            confirmationStore: confirmations
        )
        workflow = updated.workflow
        #expect(workflow.settings.glossary.first?.remember == false)

        let exported = try McpGlossaryToolService.execute(
            name: "export_glossary",
            arguments: [:],
            workflow: workflow,
            confirmationStore: confirmations
        )
        #expect((exported.details["json"] as? String)?.contains("Krishna") == true)

        let imported = try McpGlossaryToolService.execute(
            name: "import_glossary",
            arguments: [
                "entries": [[
                    "id": "rama",
                    "source": "Rama",
                    "translation": "Рама",
                    "variants": ["Ram"],
                ]],
            ],
            workflow: workflow,
            confirmationStore: confirmations
        )
        #expect(imported.workflow.settings.glossary.count == 2)
    }

    @Test("previews and confirms project glossary application")
    func glossaryApplicationRequiresConfirmation() throws {
        let confirmations = McpConfirmationStore()
        let workflow = makeWorkflow()
        let entryID = try #require(workflow.settings.glossary.first?.id)
        let previewArguments: [String: Any] = [
            "entryId": entryID,
            "scope": "project",
            "side": "source",
            "dryRun": true,
        ]
        let preview = try McpGlossaryToolService.execute(
            name: "apply_glossary_entry",
            arguments: previewArguments,
            workflow: workflow,
            confirmationStore: confirmations
        )
        let token = try #require(preview.details["confirmationToken"] as? String)
        #expect((preview.details["replacementCount"] as? Int ?? 0) > 0)
        #expect(preview.workflow == workflow)

        var applyArguments = previewArguments
        applyArguments["dryRun"] = false
        applyArguments["confirmationToken"] = token
        applyArguments["expectedRevision"] = McpProjectRevision.make(workflow: workflow)
        let applied = try McpGlossaryToolService.execute(
            name: "apply_glossary_entry",
            arguments: applyArguments,
            workflow: workflow,
            confirmationStore: confirmations
        )
        #expect(applied.workflow.session?.chunks[0].original.contains("Krsna") == true)
        #expect(applied.workflow.session?.chunks[1].original.contains("Krsna") == true)
    }
}

private extension McpGlossaryToolServiceTests {
    func makeWorkflow() -> WorkflowState {
        var settings = AppSettings.defaults
        settings.glossary = [
            GlossaryEntry(
                id: "krsna",
                variants: ["Krishna", "Kṛṣṇa"],
                source: "Krsna",
                translation: "Кришна",
                category: "Names",
                translations: ["Russian": "Кришна"],
                remember: true,
                createdAt: "2026-07-10T00:00:00Z",
                updatedAt: "2026-07-10T00:00:00Z"
            ),
        ]
        let first = ChunkData(
            index: 0,
            filePath: "/tmp/chunk-0.wav",
            durationSec: 10,
            startSec: 0,
            endSec: 10,
            original: "Hare Krishna",
            translated: "Харе Кришна",
            originalCues: [TranscriptCue(startSec: 0, endSec: 10, text: "Hare Krishna")],
            status: .done,
            approved: false
        )
        let second = ChunkData(
            index: 1,
            filePath: "/tmp/chunk-1.wav",
            durationSec: 10,
            startSec: 10,
            endSec: 20,
            original: "Remember Krishna",
            translated: "Помни Кришну",
            status: .done,
            approved: false
        )
        var workflow = WorkflowState.initial(settings: settings)
        workflow.sourceFile = "/tmp/lecture.wav"
        workflow.sourceFileName = "lecture.wav"
        workflow.durationSec = 20
        workflow.screen = .review
        workflow.session = SessionState(
            sourceFile: workflow.sourceFile,
            sourceFileName: workflow.sourceFileName,
            durationSec: 20,
            metadata: .empty,
            sourceLang: "English",
            targetLang: "Russian",
            transcriptionProvider: "coreml-whisperkit",
            translationProvider: "mlx-native",
            outputFormats: [.txt],
            chunks: [first, second],
            currentChunkIndex: 0,
            availableTranslationLanguages: ["Russian"],
            activeTranslationLanguage: "Russian"
        )
        return workflow
    }
}
