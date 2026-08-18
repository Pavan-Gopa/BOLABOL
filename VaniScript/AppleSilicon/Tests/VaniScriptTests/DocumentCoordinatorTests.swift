import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Document translation coordinator")
struct DocumentCoordinatorTests {
    actor Counter {
        var calls = 0
        func increment() { calls += 1 }
        func value() -> Int { calls }
    }
    actor PromptCapture {
        var prompts: [DocumentTranslationPrompt] = []

        func record(_ prompt: DocumentTranslationPrompt) {
            prompts.append(prompt)
        }

        func snapshot() -> [DocumentTranslationPrompt] { prompts }
    }

    private func session(approval: ApprovalMode = .manual, firstTranslated: String = "") -> SessionState {
        sessionWithTranslations([firstTranslated, ""], approval: approval)
    }

    private func sessionWithTranslations(
        _ translated: [String],
        approval: ApprovalMode = .manual,
        currentIndex: Int = 0
    ) -> SessionState {
        let texts = translated.isEmpty ? [""] : translated
        let sourceTexts = texts.indices.map { index in
            ["One", "Two", "Three", "Four", "Five"][index % 5]
        }
        let blocks = texts.enumerated().map { index, text in
            DocumentBlock(
                id: "b\(index + 1)",
                location: DocumentLocation(paragraphOrdinal: index),
                spans: [RichTextSpan(id: "s\(index + 1)", text: text.isEmpty ? sourceTexts[index] : text)]
            )
        }
        let plans = texts.enumerated().map { index, _ in
            DocumentChunkPlan(id: "chunk-\(index + 1)", blockIDs: ["b\(index + 1)"], sourceHash: "h\(index + 1)")
        }
        let chunks = texts.enumerated().map { index, text in
            let hasTranslation = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return ChunkData(
                index: index,
                filePath: "/tmp/book.txt",
                durationSec: 0,
                startSec: 0,
                endSec: 0,
                original: sourceTexts[index],
                translated: text,
                status: hasTranslation ? .done : .pending,
                approved: false,
                sourceAnchor: .document(DocumentRange(startBlockID: "b\(index + 1)", endBlockID: "b\(index + 1)"))
            )
        }
        return SessionState(
            sourceFile: "/tmp/book.txt",
            sourceFileName: "book.txt",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "English",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "mock",
            outputFormats: [.txt],
            chunks: chunks,
            currentChunkIndex: min(max(0, currentIndex), max(0, chunks.count - 1)),
            sourceKind: .document,
            documentState: DocumentState(
                format: .txt,
                originalAsset: ProjectAssetReference(key: "source"),
                blocks: blocks,
                chunks: plans
            ),
            approvalMode: approval
        )
    }

    private func liveShapedFrontMatterSession() -> SessionState {
        let texts = Array(repeating: "", count: 11)
            + [
                "All rights reserved.",
                "All rights reserved.",
                "Translation: [NAME]",
                "kadambafoundation.com",
                "© 2026 Kadamba Foundation"
            ]
            + (1...17).map { "Synthetic paragraph \($0)." }
        let blocks = texts.enumerated().map { index, text in
            DocumentBlock(
                id: "front-\(index)",
                location: DocumentLocation(paragraphOrdinal: index),
                kind: text.isEmpty ? .empty : .paragraph,
                spans: text.isEmpty ? [] : [RichTextSpan(id: "span-front-\(index)", text: text)]
            )
        }
        let plan = DocumentChunkPlan(
            id: "front-matter",
            blockIDs: blocks.map(\.id),
            sourceHash: "front-matter-hash"
        )
        return SessionState(
            sourceFile: "/tmp/front-matter.txt",
            sourceFileName: "front-matter.txt",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "English",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "mock",
            outputFormats: [.txt],
            chunks: [
                ChunkData(
                    index: 0,
                    filePath: "/tmp/front-matter.txt",
                    durationSec: 0,
                    startSec: 0,
                    endSec: 0,
                    original: texts.joined(separator: "\n\n"),
                    translated: "",
                    status: .pending,
                    approved: false,
                    sourceAnchor: .document(
                        DocumentRange(startBlockID: blocks[0].id, endBlockID: blocks[blocks.count - 1].id)
                    )
                )
            ],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: DocumentState(
                format: .txt,
                originalAsset: ProjectAssetReference(key: "source"),
                blocks: blocks,
                chunks: [plan]
            ),
            approvalMode: .manual
        )
    }

    @Test("live-shaped front matter commits source-aware output pending without repair")
    func liveShapedFrontMatterCommitsPending() async throws {
        let capture = PromptCapture()
        let counter = Counter()
        let adapter = DocumentTranslationProviderAdapter(id: "front-matter-test") { prompt in
            await capture.record(prompt)
            await counter.increment()
            let outputs = prompt.request.blocks.map { block in
                let text: String
                switch block.sourceText {
                case "All rights reserved.", "Translation: [NAME]", "kadambafoundation.com", "© 2026 Kadamba Foundation":
                    text = block.sourceText == "Translation: [NAME]"
                        ? "Перевод: [NAME]"
                        : block.sourceText
                default:
                    text = block.sourceText.replacingOccurrences(of: "Synthetic paragraph", with: "Синтетический абзац")
                }
                return DocumentTranslationOutputBlock(id: block.id, text: text)
            }
            return String(
                decoding: try JSONEncoder().encode(
                    DocumentTranslationResponse(chunkId: prompt.request.chunkId, blocks: outputs)
                ),
                as: UTF8.self
            )
        }

        let result = try await DocumentTranslationCoordinator(
            session: liveShapedFrontMatterSession(),
            engine: DocumentTranslationEngine(provider: adapter)
        ).targetedCurrent()
        let prompts = await capture.snapshot()
        let chunk = result.session.chunks[0]

        #expect(await counter.value() == 1)
        #expect(result.providerCallCount == 1)
        #expect(result.outcome == .success)
        #expect(chunk.status == .done)
        #expect(chunk.reviewDisposition == .pending)
        #expect(!chunk.approved)
        #expect(chunk.qualityReport?.errors.isEmpty == true)
        #expect(prompts.count == 1)
        #expect(prompts[0].request.blocks.count == 22)
        #expect(!prompts[0].request.blocks.contains { $0.sourceText.isEmpty })
        #expect(result.session.documentState?.translationsByLanguage[
            TranslationArchive.languageKey("Russian")
        ]?.count == 33)
    }

    @Test("one invalid block is repaired with exactly one subset call")
    func invalidBlockUsesOneSubsetRepair() async throws {
        let capture = PromptCapture()
        let counter = Counter()
        let adapter = DocumentTranslationProviderAdapter(id: "subset-coordinator-test") { prompt in
            await capture.record(prompt)
            await counter.increment()
            let text = await counter.value() == 1
                ? "Here is the translation: invalid"
                : "Исправленный текст"
            let outputs = prompt.request.blocks.map {
                DocumentTranslationOutputBlock(id: $0.id, text: text)
            }
            return String(
                decoding: try JSONEncoder().encode(
                    DocumentTranslationResponse(chunkId: prompt.request.chunkId, blocks: outputs)
                ),
                as: UTF8.self
            )
        }
        let result = try await DocumentTranslationCoordinator(
            session: session(),
            engine: DocumentTranslationEngine(provider: adapter)
        ).targetedCurrent()
        let prompts = await capture.snapshot()

        #expect(await counter.value() == 2)
        #expect(result.providerCallCount == 2)
        #expect(result.outcome == .success)
        #expect(result.session.chunks[0].translated == "Исправленный текст")
        #expect(result.session.chunks[0].reviewDisposition == .pending)
        #expect(prompts.map { $0.request.expectedBlockIDs } == [["b1"], ["b1"]])
        #expect(prompts[1].request.repair?.blockIDs == ["b1"])
    }
    @Test("coordinator commits an entirely deterministic chunk without a provider call")
    func deterministicChunkCommitsWithoutProvider() async throws {
        let counter = Counter()
        let adapter = DocumentTranslationProviderAdapter(id: "deterministic-coordinator-test") { _ in
            await counter.increment()
            return ""
        }
        let block = DocumentBlock(
            id: "empty",
            location: DocumentLocation(paragraphOrdinal: 0),
            kind: .empty,
            spans: []
        )
        let plan = DocumentChunkPlan(id: "empty-chunk", blockIDs: ["empty"], sourceHash: "empty-hash")
        let session = SessionState(
            sourceFile: "/tmp/empty.txt",
            sourceFileName: "empty.txt",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "English",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "mock",
            outputFormats: [.txt],
            chunks: [
                ChunkData(
                    index: 0,
                    filePath: "/tmp/empty.txt",
                    durationSec: 0,
                    startSec: 0,
                    endSec: 0,
                    original: "",
                    translated: "",
                    status: .pending,
                    approved: false,
                    sourceAnchor: .document(DocumentRange(startBlockID: "empty", endBlockID: "empty"))
                )
            ],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: DocumentState(
                format: .txt,
                originalAsset: ProjectAssetReference(key: "source"),
                blocks: [block],
                chunks: [plan]
            ),
            approvalMode: .manual
        )

        let result = try await DocumentTranslationCoordinator(
            session: session,
            engine: DocumentTranslationEngine(provider: adapter)
        ).targetedCurrent()

        #expect(await counter.value() == 0)
        #expect(result.providerCallCount == 0)
        #expect(result.outcome == .success)
        #expect(result.session.chunks[0].status == .done)
        #expect(result.session.chunks[0].reviewDisposition == .pending)
        #expect(result.session.documentState?.translationsByLanguage[
            TranslationArchive.languageKey("Russian")
        ]?["empty"] != nil)
    }
    @Test("provider failure during repair remains a provider failure")
    func repairProviderFailureIsClassified() async throws {
        let counter = Counter()
        let adapter = DocumentTranslationProviderAdapter(id: "repair-provider-failure") { prompt in
            await counter.increment()
            if await counter.value() == 1 {
                let output = DocumentTranslationResponse(
                    chunkId: prompt.request.chunkId,
                    blocks: prompt.request.blocks.map {
                        DocumentTranslationOutputBlock(id: $0.id, text: "Translation: invalid")
                    }
                )
                return String(decoding: try JSONEncoder().encode(output), as: UTF8.self)
            }
            throw NSError(domain: "repair-provider", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "offline"
            ])
        }

        let result = try await DocumentTranslationCoordinator(
            session: session(),
            engine: DocumentTranslationEngine(provider: adapter)
        ).targetedCurrent()

        #expect(await counter.value() == 2)
        #expect(result.providerCallCount == 2)
        #expect(result.outcome == .providerFailure)
        #expect(result.session.chunks[0].reviewDisposition == .failed)
        #expect(result.session.chunks[0].translated.isEmpty)
    }
    @Test("automatic batch is sequential and auto-approves valid chunks")
    func automaticBatch() async throws {
        let counter = Counter()
        let adapter = DocumentTranslationProviderAdapter(id: "mock") { prompt in
            await counter.increment()
            let outputs = prompt.request.blocks.map { DocumentTranslationOutputBlock(id: $0.id, text: "T-\($0.id)") }
            return String(decoding: try JSONEncoder().encode(DocumentTranslationResponse(chunkId: prompt.request.chunkId, blocks: outputs)), as: UTF8.self)
        }
        let result = try await DocumentTranslationCoordinator(
            session: session(approval: .automatic),
            engine: DocumentTranslationEngine(provider: adapter)
        ).automaticBatch()
        #expect(await counter.value() == 2)
        #expect(result.providerCallCount == 2)
        #expect(result.session.chunks.allSatisfy { $0.reviewDisposition == .autoApproved })
        #expect(result.session.currentChunkIndex == 0)
    }

    @Test("targeted success replaces only current chunk and stays pending")
    func targetedSuccessIsolated() async throws {
        let counter = Counter()
        let adapter = DocumentTranslationProviderAdapter(id: "mock") { prompt in
            await counter.increment()
            let outputs = prompt.request.blocks.map {
                DocumentTranslationOutputBlock(id: $0.id, text: "Replacement-\($0.id)")
            }
            return String(
                decoding: try JSONEncoder().encode(
                    DocumentTranslationResponse(chunkId: prompt.request.chunkId, blocks: outputs)
                ),
                as: UTF8.self
            )
        }
        let result = try await DocumentTranslationCoordinator(
            session: session(approval: .automatic, firstTranslated: "Prior valid"),
            engine: DocumentTranslationEngine(provider: adapter)
        ).targetedCurrent()

        #expect(await counter.value() == 1)
        #expect(result.providerCallCount == 1)
        #expect(result.session.currentChunkIndex == 0)
        #expect(result.session.chunks[0].translated == "Replacement-b1")
        #expect(result.session.chunks[0].reviewDisposition == .pending)
        #expect(!result.session.chunks[0].approved)
        #expect(result.session.chunks[1].translated.isEmpty)
        #expect(result.session.chunks[1].reviewDisposition == .pending)
        let stored = result.session.documentState?.translationsByLanguage[
            TranslationArchive.languageKey("Russian")
        ]?["b1"]
        #expect(stored?.text == "Replacement-b1")
        #expect(stored?.reviewDisposition == .pending)
        #expect(result.outcome == .success)
    }

    @Test("manual approve-and-next skips an already-ready chunk without a provider call")
    func readyNextDoesNotCallProvider() async throws {
        let counter = Counter()
        let adapter = DocumentTranslationProviderAdapter(id: "mock") { prompt in
            await counter.increment()
            let outputs = prompt.request.blocks.map { DocumentTranslationOutputBlock(id: $0.id, text: "T-\($0.id)") }
            return String(decoding: try JSONEncoder().encode(DocumentTranslationResponse(chunkId: prompt.request.chunkId, blocks: outputs)), as: UTF8.self)
        }
        let result = try await DocumentTranslationCoordinator(
            session: sessionWithTranslations(["Approved", "Already ready"], approval: .manual),
            engine: DocumentTranslationEngine(provider: adapter)
        ).run(intent: .manualCurrent, currentIndex: 1)

        #expect(await counter.value() == 0)
        #expect(result.providerCallCount == 0)
        #expect(result.processedIndices.isEmpty)
        #expect(result.session.currentChunkIndex == 1)
        #expect(result.session.chunks[1].translated == "Already ready")
    }

    @Test("manual approve-and-next translates an untranslated next chunk exactly once")
    func untranslatedNextCallsManualCurrentOnce() async throws {
        let counter = Counter()
        let adapter = DocumentTranslationProviderAdapter(id: "mock") { prompt in
            await counter.increment()
            let outputs = prompt.request.blocks.map { DocumentTranslationOutputBlock(id: $0.id, text: "T-\($0.id)") }
            return String(decoding: try JSONEncoder().encode(DocumentTranslationResponse(chunkId: prompt.request.chunkId, blocks: outputs)), as: UTF8.self)
        }
        let result = try await DocumentTranslationCoordinator(
            session: sessionWithTranslations(["Approved", ""], approval: .manual),
            engine: DocumentTranslationEngine(provider: adapter)
        ).run(intent: .manualCurrent, currentIndex: 1)

        #expect(await counter.value() == 1)
        #expect(result.providerCallCount == 1)
        #expect(result.processedIndices == [1])
        #expect(result.session.chunks[1].translated == "T-b2")
        #expect(result.session.chunks[1].reviewDisposition == .pending)
    }

    @Test("automatic batch continues after Needs Review and auto-approves only clean later output")
    func automaticBatchContinuesPastReview() async throws {
        let counter = Counter()
        let adapter = DocumentTranslationProviderAdapter(id: "mock") { prompt in
            await counter.increment()
            let output: DocumentTranslationResponse
            if prompt.request.chunkId == "chunk-1" {
                output = DocumentTranslationResponse(
                    chunkId: prompt.request.chunkId,
                    blocks: [DocumentTranslationOutputBlock(id: "unexpected", text: "Invalid")]
                )
            } else {
                let outputs = prompt.request.blocks.map { DocumentTranslationOutputBlock(id: $0.id, text: "T-\($0.id)") }
                output = DocumentTranslationResponse(chunkId: prompt.request.chunkId, blocks: outputs)
            }
            return String(decoding: try JSONEncoder().encode(output), as: UTF8.self)
        }
        let result = try await DocumentTranslationCoordinator(
            session: sessionWithTranslations(["", "", ""], approval: .automatic),
            engine: DocumentTranslationEngine(provider: adapter),
            maxRepairAttempts: 0
        ).automaticBatch()

        #expect(await counter.value() == 3)
        #expect(result.providerCallCount == 3)
        #expect(result.processedIndices == [0, 1, 2])
        #expect(result.session.chunks[0].reviewDisposition == .needsReview)
        #expect(result.session.chunks[1].reviewDisposition == .autoApproved)
        #expect(result.session.chunks[2].reviewDisposition == .autoApproved)
        #expect(result.session.chunks[1].translated == "T-b2")
        #expect(result.session.chunks[2].translated == "T-b3")
        #expect(!result.session.chunks[0].approved)
    }


    @Test("targeted current makes one call and preserves prior output on failure")
    func targetedFailureIsolated() async throws {
        let counter = Counter()
        let adapter = DocumentTranslationProviderAdapter(id: "mock") { _ in
            await counter.increment()
            throw NSError(domain: "mock", code: 1, userInfo: [NSLocalizedDescriptionKey: "offline"])
        }
        let result = try await DocumentTranslationCoordinator(
            session: session(approval: .automatic, firstTranslated: "Prior valid"),
            engine: DocumentTranslationEngine(provider: adapter)
        ).targetedCurrent()
        #expect(await counter.value() == 1)
        #expect(result.providerCallCount == 1)
        #expect(result.session.currentChunkIndex == 0)
        #expect(result.session.chunks[0].translated == "Prior valid")
        #expect(result.outcome == .providerFailure)
        #expect(!result.message.contains("retranslated"))
    }
    @Test("mapping output spans preserves source foreground color and provider cannot invent colors")
    func preservesSourceColorInTranslatedSpans() async throws {
        let block = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            spans: [
                RichTextSpan(id: "s1", text: "Normal text and ", foregroundColorHex: nil),
                RichTextSpan(id: "s2", text: "red placeholder", foregroundColorHex: "FF0000")
            ]
        )
        let plan = DocumentChunkPlan(id: "chunk-1", blockIDs: ["b1"], sourceHash: "h1")
        let chunk = ChunkData(
            index: 0,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: "Normal text and red placeholder",
            translated: "",
            status: .pending,
            approved: false,
            sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b1"))
        )
        let testSession = SessionState(
            sourceFile: "/tmp/doc.docx",
            sourceFileName: "doc.docx",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "English",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "mock",
            outputFormats: [.txt],
            chunks: [chunk],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: DocumentState(
                format: .docx,
                originalAsset: ProjectAssetReference(key: "source"),
                blocks: [block],
                chunks: [plan]
            ),
            approvalMode: .manual
        )

        let adapter = DocumentTranslationProviderAdapter(id: "color-test") { prompt in
            let outputs = [
                DocumentTranslationOutputBlock(
                    id: "b1",
                    spans: [
                        DocumentTranslationOutputSpan(id: "s1", style: "plain", text: "Обычный текст и "),
                        DocumentTranslationOutputSpan(id: "s2", style: "plain", text: "красный заполнитель")
                    ]
                )
            ]
            return String(
                decoding: try JSONEncoder().encode(
                    DocumentTranslationResponse(chunkId: prompt.request.chunkId, blocks: outputs)
                ),
                as: UTF8.self
            )
        }

        let result = try await DocumentTranslationCoordinator(
            session: testSession,
            engine: DocumentTranslationEngine(provider: adapter)
        ).targetedCurrent()

        let trans = result.session.documentState?.translationsByLanguage["russian"]?["b1"]
        #expect(trans != nil)
        #expect(trans?.spans.count == 2)
        #expect(trans?.spans[0].text == "Обычный текст и ")
        #expect(trans?.spans[0].foregroundColorHex == nil)
        #expect(trans?.spans[1].text == "красный заполнитель")
        #expect(trans?.spans[1].foregroundColorHex == "FF0000")
    }

    @Test("collapsed provider spans still inherit source color on preserved tokens")
    func collapsedProviderOutputSplitsPreservedColoredTokens() async throws {
        let block = DocumentBlock(
            id: "b1",
            location: DocumentLocation(paragraphOrdinal: 0),
            spans: [
                RichTextSpan(id: "s1", text: "First edition published in ", foregroundColorHex: nil),
                RichTextSpan(id: "s2", text: "[YEAR]", foregroundColorHex: "FF0000"),
                RichTextSpan(id: "s3", text: " by Kadamba", foregroundColorHex: nil)
            ]
        )
        let plan = DocumentChunkPlan(id: "chunk-1", blockIDs: ["b1"], sourceHash: "h1")
        let chunk = ChunkData(
            index: 0,
            filePath: "/tmp/doc.docx",
            durationSec: 0,
            startSec: 0,
            endSec: 0,
            original: "First edition published in [YEAR] by Kadamba",
            translated: "",
            status: .pending,
            approved: false,
            sourceAnchor: .document(DocumentRange(startBlockID: "b1", endBlockID: "b1"))
        )
        let testSession = SessionState(
            sourceFile: "/tmp/doc.docx",
            sourceFileName: "doc.docx",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "English",
            targetLang: "Ukrainian",
            transcriptionProvider: "",
            translationProvider: "mock",
            outputFormats: [.txt],
            chunks: [chunk],
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: DocumentState(
                format: .docx,
                originalAsset: ProjectAssetReference(key: "source"),
                blocks: [block],
                chunks: [plan]
            ),
            approvalMode: .manual
        )

        // Provider collapses the whole block into ONE span and drops span ids.
        // The preserved token text stays verbatim so color transfer can split it.
        let adapter = DocumentTranslationProviderAdapter(id: "collapsed-color") { prompt in
            let outputs = [
                DocumentTranslationOutputBlock(
                    id: "b1",
                    spans: [
                        DocumentTranslationOutputSpan(
                            id: nil,
                            style: "plain",
                            text: "Перше видання опубліковано у [YEAR] by Kadamba"
                        )
                    ]
                )
            ]
            return String(
                decoding: try JSONEncoder().encode(
                    DocumentTranslationResponse(chunkId: prompt.request.chunkId, blocks: outputs)
                ),
                as: UTF8.self
            )
        }

        let result = try await DocumentTranslationCoordinator(
            session: testSession,
            engine: DocumentTranslationEngine(provider: adapter)
        ).targetedCurrent()

        let trans = result.session.documentState?.translationsByLanguage["ukrainian"]?["b1"]
        #expect(trans != nil)
        let colored = (trans?.spans ?? []).filter { $0.foregroundColorHex == "FF0000" }
        #expect(colored.count == 1)
        #expect(colored.first?.text == "[YEAR]")
        #expect(colored.first?.id == "s2")
        #expect((trans?.spans ?? []).contains(where: { $0.text.contains("Перше") && $0.foregroundColorHex == nil }))
    }
}
