import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Document translation engine")
struct DocumentTranslationEngineTests {
    actor CallCounter {
        var value = 0
        func increment() { value += 1 }
        func get() -> Int { value }
    }
    actor PromptCapture {
        var prompts: [DocumentTranslationPrompt] = []

        func record(_ prompt: DocumentTranslationPrompt) {
            prompts.append(prompt)
        }

        func snapshot() -> [DocumentTranslationPrompt] { prompts }
    }

    private func request() -> DocumentTranslationRequest {
        DocumentTranslationRequest(
            chunkId: "chunk-1",
            targetLanguage: "Russian",
            blocks: [DocumentTranslationInputBlock(id: "b1", sourceText: "Hello")]
        )
    }

    @Test("provider adapter receives strict prompt and valid output")
    func translatesWithMockProvider() async throws {
        let counter = CallCounter()
        let adapter = DocumentTranslationProviderAdapter(id: "mock") { prompt in
            await counter.increment()
            let response = DocumentTranslationResponse(
                chunkId: prompt.request.chunkId,
                blocks: [DocumentTranslationOutputBlock(id: "b1", text: "Привет")]
            )
            return String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
        }
        let result = try await DocumentTranslationEngine(provider: adapter).translate(request: request())
        #expect(result.isValid)
        #expect(result.response.blocks.first?.text == "Привет")
        #expect(await counter.get() == 1)
    }

    @Test("empty and truncated provider output is rejected")
    func rejectsEmptyAndTruncatedOutput() async {
        let empty = DocumentTranslationProviderAdapter { _ in "" }
        await #expect(throws: DocumentTranslationEngineError.self) {
            try await DocumentTranslationEngine(provider: empty).translate(request: request())
        }
        let truncated = DocumentTranslationProviderAdapter { _ in "{\"schema\":\"vaniscript.document.translation.v1\"" }
        await #expect(throws: DocumentTranslationEngineError.self) {
            try await DocumentTranslationEngine(provider: truncated).translate(request: request())
        }
    }
    @Test("deterministic blocks stay local and provider sees only translatable IDs")
    func deterministicBlocksAreReconstructed() async throws {
        let capture = PromptCapture()
        let counter = CallCounter()
        let request = DocumentTranslationRequest(
            chunkId: "deterministic",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(id: "empty", sourceText: ""),
                DocumentTranslationInputBlock(
                    id: "protected",
                    sourceText: "ॐ",
                    spans: [DocumentTranslationInputSpan(id: "protected-span", style: "italic", text: "ॐ")],
                    translationPolicy: .protect
                ),
                DocumentTranslationInputBlock(id: "translate", sourceText: "Hello")
            ]
        )
        let provider = DocumentTranslationProviderAdapter(id: "partition-test") { prompt in
            await capture.record(prompt)
            await counter.increment()
            let blocks = prompt.request.blocks.map {
                DocumentTranslationOutputBlock(id: $0.id, text: "Привет")
            }
            return String(
                decoding: try JSONEncoder().encode(
                    DocumentTranslationResponse(chunkId: prompt.request.chunkId, blocks: blocks)
                ),
                as: UTF8.self
            )
        }

        let result = try await DocumentTranslationEngine(provider: provider).translate(request: request)
        let prompts = await capture.snapshot()
        #expect(result.isValid)
        #expect(await counter.get() == 1)
        #expect(prompts.count == 1)
        #expect(prompts[0].request.expectedBlockIDs == ["translate"])
        #expect(result.response.blockIDs == ["empty", "protected", "translate"])
        #expect(result.response.blocks[0].text.isEmpty)
        #expect(result.response.blocks[1].spans == [
            DocumentTranslationOutputSpan(id: "protected-span", style: "italic", text: "ॐ")
        ])
        #expect(result.response.blocks[2].text == "Привет")
    }

    @Test("an entirely deterministic chunk completes without a provider call")
    func entirelyDeterministicChunkSkipsProvider() async throws {
        let counter = CallCounter()
        let request = DocumentTranslationRequest(
            chunkId: "only-deterministic",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(id: "empty", sourceText: ""),
                DocumentTranslationInputBlock(
                    id: "protected",
                    sourceText: "ॐ",
                    spans: [DocumentTranslationInputSpan(id: "span", style: "plain", text: "ॐ")],
                    translationPolicy: .protect
                )
            ]
        )
        let provider = DocumentTranslationProviderAdapter(id: "should-not-run") { _ in
            await counter.increment()
            return ""
        }

        let result = try await DocumentTranslationEngine(provider: provider).translate(request: request)
        #expect(result.isValid)
        #expect(await counter.get() == 0)
        #expect(result.response.blockIDs == ["empty", "protected"])
        #expect(result.response.blocks[1].text == "ॐ")
    }

    @Test("repair request is subset-only and preserves valid blocks byte-for-byte")
    func subsetRepairMergesFullCandidate() async throws {
        let capture = PromptCapture()
        let counter = CallCounter()
        let request = DocumentTranslationRequest(
            chunkId: "repair",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(id: "b1", sourceText: "First source paragraph."),
                DocumentTranslationInputBlock(id: "b2", sourceText: "Second source paragraph."),
                DocumentTranslationInputBlock(id: "b3", sourceText: "Third source paragraph.")
            ]
        )
        let provider = DocumentTranslationProviderAdapter(id: "repair-test") { prompt in
            await capture.record(prompt)
            await counter.increment()
            let blocks: [DocumentTranslationOutputBlock]
            if await counter.get() == 1 {
                blocks = [
                    DocumentTranslationOutputBlock(id: "b1", text: "Первый абзац."),
                    DocumentTranslationOutputBlock(id: "b2", text: "Here is the translation: bad"),
                    DocumentTranslationOutputBlock(id: "b3", text: "Третий абзац.")
                ]
            } else {
                blocks = prompt.request.blocks.map {
                    DocumentTranslationOutputBlock(id: $0.id, text: "Исправленный абзац.")
                }
            }
            return String(
                decoding: try JSONEncoder().encode(
                    DocumentTranslationResponse(chunkId: prompt.request.chunkId, blocks: blocks)
                ),
                as: UTF8.self
            )
        }
        let engine = DocumentTranslationEngine(provider: provider)

        let initial = try await engine.translate(request: request)
        #expect(!initial.isValid)
        let repaired = try await engine.translate(request: request, repairFor: initial, attempts: 2)
        let prompts = await capture.snapshot()

        #expect(repaired.isValid)
        #expect(await counter.get() == 2)
        #expect(prompts.count == 2)
        #expect(prompts[0].request.expectedBlockIDs == ["b1", "b2", "b3"])
        #expect(prompts[1].request.expectedBlockIDs == ["b2"])
        #expect(prompts[1].request.repair?.blockIDs == ["b2"])
        #expect(prompts[1].request.repair?.sourceBlocks.map(\.id) == ["b2"])
        #expect(prompts[1].request.repair?.previousCandidate.map(\.id) == ["b2"])
        #expect(repaired.response.blockIDs == ["b1", "b2", "b3"])
        let initialByID = Dictionary(uniqueKeysWithValues: initial.response.blocks.map { ($0.id, $0) })
        let repairedByID = Dictionary(uniqueKeysWithValues: repaired.response.blocks.map { ($0.id, $0) })
        #expect(repairedByID["b1"] == initialByID["b1"])
        #expect(repairedByID["b3"] == initialByID["b3"])
        #expect(repairedByID["b2"]?.text == "Исправленный абзац.")
    }

    @Test("each repair attempt narrows to the remaining invalid IDs")
    func repairNarrowsOnNextAttempt() async throws {
        let capture = PromptCapture()
        let counter = CallCounter()
        let request = DocumentTranslationRequest(
            chunkId: "repair-narrow",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(id: "b1", sourceText: "First source paragraph."),
                DocumentTranslationInputBlock(id: "b2", sourceText: "Second source paragraph."),
                DocumentTranslationInputBlock(id: "b3", sourceText: "Third source paragraph.")
            ]
        )
        let provider = DocumentTranslationProviderAdapter(id: "repair-narrow-test") { prompt in
            await capture.record(prompt)
            await counter.increment()
            let call = await counter.get()
            let blocks: [DocumentTranslationOutputBlock]
            switch call {
            case 1:
                blocks = [
                    DocumentTranslationOutputBlock(id: "b1", text: "Первый абзац."),
                    DocumentTranslationOutputBlock(id: "b2", text: "Translation: bad"),
                    DocumentTranslationOutputBlock(id: "b3", text: "Translation: bad")
                ]
            case 2:
                blocks = prompt.request.blocks.map {
                    DocumentTranslationOutputBlock(id: $0.id, text: $0.id == "b2" ? "Второй абзац." : "Translation: bad")
                }
            default:
                blocks = prompt.request.blocks.map {
                    DocumentTranslationOutputBlock(id: $0.id, text: "Третий абзац.")
                }
            }
            return String(
                decoding: try JSONEncoder().encode(
                    DocumentTranslationResponse(chunkId: prompt.request.chunkId, blocks: blocks)
                ),
                as: UTF8.self
            )
        }
        let engine = DocumentTranslationEngine(provider: provider)

        let initial = try await engine.translate(request: request)
        let second = try await engine.translate(request: request, repairFor: initial, attempts: 2)
        let final = try await engine.translate(request: request, repairFor: second, attempts: 3)
        let prompts = await capture.snapshot()

        #expect(!second.isValid)
        #expect(final.isValid)
        #expect(await counter.get() == 3)
        #expect(prompts.map { $0.request.expectedBlockIDs } == [["b1", "b2", "b3"], ["b2", "b3"], ["b3"]])
    }

    @Test("chunk 29 shape (10 blocks, 3 empty) with provider echoing all 10 IDs reconstructs 10 IDs in order and passes validation")
    func chunk29ShapeEchoingAll10IDs() async throws {
        let blocks = [
            DocumentTranslationInputBlock(id: "b0", sourceText: "Paragraph 0"),
            DocumentTranslationInputBlock(id: "b1", sourceText: ""),
            DocumentTranslationInputBlock(id: "b2", sourceText: "Paragraph 2"),
            DocumentTranslationInputBlock(id: "b3", sourceText: ""),
            DocumentTranslationInputBlock(id: "b4", sourceText: "Paragraph 4"),
            DocumentTranslationInputBlock(id: "b5", sourceText: "Paragraph 5"),
            DocumentTranslationInputBlock(id: "b6", sourceText: ""),
            DocumentTranslationInputBlock(id: "b7", sourceText: "Paragraph 7"),
            DocumentTranslationInputBlock(id: "b8", sourceText: "Paragraph 8"),
            DocumentTranslationInputBlock(id: "b9", sourceText: "Paragraph 9")
        ]
        let request = DocumentTranslationRequest(
            chunkId: "chunk-29",
            targetLanguage: "Russian",
            blocks: blocks
        )
        #expect(request.deterministicBlockIDs == ["b1", "b3", "b6"])
        #expect(request.translatableBlockIDs == ["b0", "b2", "b4", "b5", "b7", "b8", "b9"])

        let provider = DocumentTranslationProviderAdapter(id: "echo-all-10") { _ in
            let response = DocumentTranslationResponse(
                chunkId: "chunk-29",
                blocks: [
                    DocumentTranslationOutputBlock(id: "b0", text: "Абзац 0"),
                    DocumentTranslationOutputBlock(id: "b1", spans: []),
                    DocumentTranslationOutputBlock(id: "b2", text: "Абзац 2"),
                    DocumentTranslationOutputBlock(id: "b3", spans: []),
                    DocumentTranslationOutputBlock(id: "b4", text: "Абзац 4"),
                    DocumentTranslationOutputBlock(id: "b5", text: "Абзац 5"),
                    DocumentTranslationOutputBlock(id: "b6", spans: []),
                    DocumentTranslationOutputBlock(id: "b7", text: "Абзац 7"),
                    DocumentTranslationOutputBlock(id: "b8", text: "Абзац 8"),
                    DocumentTranslationOutputBlock(id: "b9", text: "Абзац 9")
                ]
            )
            return String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
        }

        let result = try await DocumentTranslationEngine(provider: provider).translate(request: request)
        #expect(result.isValid)
        #expect(result.response.blockIDs == request.expectedBlockIDs)
        #expect(result.response.blocks.count == 10)
        #expect(result.response.blocks[1].spans.isEmpty)
        #expect(result.response.blocks[3].spans.isEmpty)
        #expect(result.response.blocks[6].spans.isEmpty)
        #expect(result.response.blocks[0].text == "Абзац 0")
        #expect(result.response.blocks[9].text == "Абзац 9")
    }

    @Test("provider response echoing an empty ID twice remains valid without duplicateBlockID")
    func providerEchoingEmptyIDTwice() async throws {
        let request = DocumentTranslationRequest(
            chunkId: "empty-echo-twice",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(id: "b0", sourceText: "First paragraph"),
                DocumentTranslationInputBlock(id: "b1", sourceText: ""),
                DocumentTranslationInputBlock(id: "b2", sourceText: "Second paragraph")
            ]
        )
        let provider = DocumentTranslationProviderAdapter(id: "empty-echo-twice") { _ in
            let response = DocumentTranslationResponse(
                chunkId: "empty-echo-twice",
                blocks: [
                    DocumentTranslationOutputBlock(id: "b0", text: "Первый абзац"),
                    DocumentTranslationOutputBlock(id: "b1", spans: []),
                    DocumentTranslationOutputBlock(id: "b1", spans: []),
                    DocumentTranslationOutputBlock(id: "b2", text: "Второй абзац")
                ]
            )
            return String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
        }

        let result = try await DocumentTranslationEngine(provider: provider).translate(request: request)
        #expect(result.isValid)
        #expect(result.response.blockIDs == ["b0", "b1", "b2"])
        #expect(!result.validation.errors.contains { $0.code == "duplicateBlockID" })
    }

    @Test("provider duplicating a translatable ID still reports duplicateBlockID")
    func providerDuplicatingTranslatableID() async throws {
        let request = DocumentTranslationRequest(
            chunkId: "translatable-duplicate",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(id: "b0", sourceText: "First paragraph"),
                DocumentTranslationInputBlock(id: "b1", sourceText: ""),
                DocumentTranslationInputBlock(id: "b2", sourceText: "Second paragraph")
            ]
        )
        let provider = DocumentTranslationProviderAdapter(id: "translatable-duplicate") { _ in
            let response = DocumentTranslationResponse(
                chunkId: "translatable-duplicate",
                blocks: [
                    DocumentTranslationOutputBlock(id: "b0", text: "Первый абзац"),
                    DocumentTranslationOutputBlock(id: "b2", text: "Второй абзац 1"),
                    DocumentTranslationOutputBlock(id: "b2", text: "Второй абзац 2")
                ]
            )
            return String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
        }

        let result = try await DocumentTranslationEngine(provider: provider).translate(request: request)
        #expect(!result.isValid)
        #expect(result.validation.errors.contains { $0.code == "duplicateBlockID" && $0.blockID == "b2" })
    }

    @Test("malformed-order branch with duplicated empty echoes produces deterministic IDs exactly once")
    func malformedOrderWithDuplicatedEmptyEchoes() async throws {
        let request = DocumentTranslationRequest(
            chunkId: "malformed-empty-echoes",
            targetLanguage: "Russian",
            blocks: [
                DocumentTranslationInputBlock(id: "b0", sourceText: "First paragraph"),
                DocumentTranslationInputBlock(id: "b1", sourceText: ""),
                DocumentTranslationInputBlock(id: "b2", sourceText: "Second paragraph"),
                DocumentTranslationInputBlock(id: "b3", sourceText: "")
            ]
        )
        // Reversed translatable order: b2 before b0, with b1 echoed twice
        let provider = DocumentTranslationProviderAdapter(id: "malformed-order") { _ in
            let response = DocumentTranslationResponse(
                chunkId: "malformed-empty-echoes",
                blocks: [
                    DocumentTranslationOutputBlock(id: "b2", text: "Второй абзац"),
                    DocumentTranslationOutputBlock(id: "b1", spans: []),
                    DocumentTranslationOutputBlock(id: "b0", text: "Первый абзац"),
                    DocumentTranslationOutputBlock(id: "b1", spans: [])
                ]
            )
            return String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
        }

        let result = try await DocumentTranslationEngine(provider: provider).translate(request: request)
        #expect(!result.isValid)
        #expect(result.validation.errors.contains { $0.code == "blockOrder" })
        #expect(!result.validation.errors.contains { $0.code == "duplicateBlockID" && $0.blockID == "b1" })
        #expect(result.response.blockIDs.filter { $0 == "b1" }.count == 1)
        #expect(result.response.blockIDs.filter { $0 == "b3" }.count == 1)
    }
}
