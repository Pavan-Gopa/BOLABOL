import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Document translation runtime")
struct DocumentTranslationRuntimeTests {
    actor Capture {
        var prompt: DocumentTranslationPrompt?
        var calls = 0

        func record(_ prompt: DocumentTranslationPrompt) {
            self.prompt = prompt
            calls += 1
        }

        func snapshot() -> (DocumentTranslationPrompt?, Int) {
            (prompt, calls)
        }
    }

    private func block(_ id: String, text: String, ordinal: Int) -> DocumentBlock {
        DocumentBlock(
            id: id,
            location: DocumentLocation(paragraphOrdinal: ordinal),
            spans: [RichTextSpan(id: "span-\(id)", text: text)]
        )
    }

    private func glossaryEntry(_ index: Int, source: String? = nil) -> GlossaryEntry {
        GlossaryEntry(
            id: "glossary-\(index)",
            variants: [],
            source: source ?? "unrelated-term-\(index)",
            translation: "translation-\(index)",
            category: nil,
            translations: [:],
            remember: true,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    @Test("live-shaped glossary is filtered and one selected chunk stays bounded")
    func selectedChunkUsesBoundedWireRequest() async throws {
        let selectedText = String(repeating: "Sanskrit term appears in the selected block. ", count: 14)
        let blocks = [
            block("before", text: "bounded context before", ordinal: 0),
            block("selected", text: selectedText, ordinal: 1),
            block("after", text: "bounded context after", ordinal: 2),
            block("unrelated", text: "UNRELATED_SENTINEL_MANUSCRIPT", ordinal: 3)
        ]
        var glossary = (0..<104).map { glossaryEntry($0) }
        glossary.append(glossaryEntry(104, source: "Sanskrit"))
        glossary.append(glossaryEntry(105, source: "sanskrit"))
        let profile = DocumentTranslationProfile(
            sourceLanguage: "English",
            targetLanguage: "Russian",
            protectedTerms: [ProtectedTerm(source: "Sanskrit", translation: "Санскрит")],
            projectGlossary: glossary
        )
        let state = DocumentState(
            format: .txt,
            originalAsset: ProjectAssetReference(key: "source"),
            blocks: blocks,
            chunks: [DocumentChunkPlan(
                id: "chunk-selected",
                blockIDs: ["selected"],
                sourceTokenEstimate: 100,
                contextBeforeBlockIDs: ["before"],
                contextAfterBlockIDs: ["after"],
                sourceHash: "hash"
            )],
            profile: profile
        )
        let memory = DocumentTranslationMemory(
            glossary: glossary,
            protectedTerms: ["Sanskrit"],
            recentApprovedBlocks: [
                DocumentTranslationMemoryBlock(id: "unrelated", source: "UNRELATED_SENTINEL_MANUSCRIPT", target: "old target")
            ]
        )
        let request = DocumentTranslationEngine.request(
            for: state.chunks[0],
            in: state,
            sourceLanguage: "English",
            targetLanguage: "Russian",
            memory: memory
        )
        let capture = Capture()
        let provider = DocumentTranslationProviderAdapter(id: "runtime-test") { prompt in
            await capture.record(prompt)
            let response = DocumentTranslationResponse(
                chunkId: prompt.request.chunkId,
                blocks: prompt.request.blocks.map { DocumentTranslationOutputBlock(id: $0.id, text: "Перевод") }
            )
            return String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
        }
        let result = try await DocumentTranslationEngine(provider: provider).translate(
            request: request,
            intent: "targetedCurrent",
            chunkIndex: 0
        )
        let (prompt, calls) = await capture.snapshot()
        let captured = try #require(prompt)
        #expect(result.isValid)
        #expect(calls == 1)
        #expect(request.blocks.map(\.id) == ["selected"])
        #expect(request.readOnlyContextBefore.map(\.id) == ["before"])
        #expect(request.readOnlyContextAfter.map(\.id) == ["after"])
        #expect(request.profile.projectGlossary.count == 1)
        #expect(request.memory?.glossary.isEmpty == true)
        #expect(!captured.combinedText.contains("UNRELATED_SENTINEL_MANUSCRIPT"))
        #expect(captured.budget?.serializedPromptCharacters ?? 150_022 < 150_022)
        #expect(captured.system.contains("chunk-selected"))
        #expect(captured.system.contains("selected"))
        #expect(captured.system.contains("plain"))
    }

    @Test("selected blocks alone fail before an oversized provider call")
    func oversizedSelectedBlockFailsPreflight() async {
        let request = DocumentTranslationRequest(
            chunkId: "too-large",
            targetLanguage: "Russian",
            blocks: [DocumentTranslationInputBlock(id: "selected", sourceText: String(repeating: "source ", count: 2_000))]
        )
        let capture = Capture()
        let provider = DocumentTranslationProviderAdapter(
            id: "small-model",
            capabilities: TranslationModelCapabilities(
                modelID: "small-model",
                contextWindowTokens: 128,
                maxOutputTokens: 32,
                fallbackCharactersPerToken: 4,
                recommendedSoftSourceTokens: nil,
                recommendedHardSourceTokens: nil
            )
        ) { _ in
            await capture.record(DocumentTranslationPrompt(system: "", user: "", request: request))
            return ""
        }
        await #expect(throws: DocumentTranslationEngineError.self) {
            try await DocumentTranslationEngine(provider: provider).translate(request: request)
        }
        let (_, calls) = await capture.snapshot()
        #expect(calls == 0)
    }
}
