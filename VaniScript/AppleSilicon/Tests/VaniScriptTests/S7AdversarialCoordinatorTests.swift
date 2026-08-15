import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("S7 adversarial coordinator regressions")
struct S7AdversarialCoordinatorTests {
    actor Counter {
        private var calls = 0
        func increment() { calls += 1 }
        func value() -> Int { calls }
    }

    actor Capture {
        private var prompts: [DocumentTranslationPrompt] = []
        func record(_ prompt: DocumentTranslationPrompt) { prompts.append(prompt) }
        func snapshot() -> [DocumentTranslationPrompt] { prompts }
    }

    @Test("a persisted mixed chunk with structural empty blocks is ready without another paid call")
    func mixedChunkDoesNotRetranslateAfterSuccessfulCommit() async throws {
        let counter = Counter()
        let adapter = provider(counter: counter)

        let first = try await DocumentTranslationCoordinator(
            session: mixedSession(approval: .manual),
            engine: DocumentTranslationEngine(provider: adapter)
        ).targetedCurrent()

        #expect(await counter.value() == 1)
        #expect(first.outcome == .success)
        #expect(first.session.documentState?.translationsByLanguage["russian"]?.count == 3)

        let second = try await DocumentTranslationCoordinator(
            session: first.session,
            engine: DocumentTranslationEngine(provider: adapter)
        ).manualCurrent()

        // A deterministic source-empty block is complete by presence, even
        // though its intentionally preserved output text is empty.
        #expect(await counter.value() == 1)
        #expect(second.providerCallCount == 0)
        #expect(second.processedIndices.isEmpty)
        #expect(second.message == "Chunk already has a valid translation.")
    }

    @Test("automatic resume skips a mixed chunk already committed in a previous coordinator instance")
    func automaticResumeDoesNotRepayForMixedChunk() async throws {
        let counter = Counter()
        let adapter = provider(counter: counter)

        let first = try await DocumentTranslationCoordinator(
            session: mixedSession(approval: .automatic),
            engine: DocumentTranslationEngine(provider: adapter)
        ).automaticBatch()

        #expect(await counter.value() == 1)
        #expect(first.session.chunks[0].reviewDisposition == .autoApproved)

        let resumed = try await DocumentTranslationCoordinator(
            session: first.session,
            engine: DocumentTranslationEngine(provider: adapter)
        ).automaticBatch()

        #expect(await counter.value() == 1)
        #expect(resumed.providerCallCount == 0)
        #expect(resumed.processedIndices.isEmpty)
        #expect(resumed.session.chunks[0].reviewDisposition == .autoApproved)
    }

    @Test("request builder sends only the selected oversized-paragraph slice")
    func requestBuilderHonorsBlockSlice() {
        let block = DocumentBlock(
            id: "long",
            location: DocumentLocation(paragraphOrdinal: 0),
            spans: [RichTextSpan(id: "span-long", text: "ABCDEFGHIJ")],
            sourceHash: "source-long"
        )
        let plan = DocumentChunkPlan(
            id: "slice-plan",
            blockIDs: ["long"],
            sourceTokenEstimate: 3,
            sourceHash: "slice-hash",
            blockSlices: [DocumentBlockSlice(blockID: "long", startOffset: 2, endOffset: 5)]
        )
        let state = DocumentState(format: .txt, blocks: [block], chunks: [plan])

        let request = DocumentTranslationEngine.request(
            for: plan,
            in: state,
            sourceLanguage: "English",
            targetLanguage: "Russian"
        )

        #expect(request.blocks.count == 1)
        #expect(request.blocks[0].id == "long")
        #expect(request.blocks[0].sourceText == "CDE")
        #expect(request.blocks[0].spans.map(\.text).joined() == "CDE")
    }

    @Test("second slice plan resolves by plan identity rather than ambiguous first/last block IDs")
    func secondSlicePlanKeepsItsIdentity() async throws {
        let counter = Counter()
        let capture = Capture()
        let adapter = provider(counter: counter, capture: capture)
        let session = slicedSession()

        let result = try await DocumentTranslationCoordinator(
            session: session,
            engine: DocumentTranslationEngine(provider: adapter)
        ).run(intent: .manualCurrent, currentIndex: 1)
        let prompts = await capture.snapshot()

        #expect(result.providerCallCount == 1)
        #expect(prompts.count == 1)
        #expect(prompts[0].request.chunkId == "slice-2")
        #expect(prompts[0].request.blocks.first?.sourceText == "FGHIJ")
    }

    @Test("two slices of one source block are translated once each and reassembled without archive overwrite")
    func siblingSlicesDoNotOverwriteEachOther() async throws {
        let counter = Counter()
        let capture = Capture()
        let adapter = DocumentTranslationProviderAdapter(id: "slice-reassembly") { prompt in
            await counter.increment()
            await capture.record(prompt)
            let marker = prompt.request.chunkId == "slice-1" ? "ONE" : "TWO"
            let blocks = prompt.request.blocks.map {
                DocumentTranslationOutputBlock(id: $0.id, text: marker)
            }
            return String(
                decoding: try JSONEncoder().encode(
                    DocumentTranslationResponse(chunkId: prompt.request.chunkId, blocks: blocks)
                ),
                as: UTF8.self
            )
        }

        let result = try await DocumentTranslationCoordinator(
            session: slicedSession(approval: .automatic),
            engine: DocumentTranslationEngine(provider: adapter)
        ).automaticBatch()
        let prompts = await capture.snapshot()
        let archiveText = result.session.documentState?
            .translationsByLanguage["russian"]?["long"]?.text ?? ""

        #expect(await counter.value() == 2)
        #expect(prompts.map { $0.request.chunkId } == ["slice-1", "slice-2"])
        #expect(archiveText.contains("ONE"))
        #expect(archiveText.contains("TWO"))
        #expect(archiveText.range(of: "ONE")!.lowerBound < archiveText.range(of: "TWO")!.lowerBound)
    }

    private func provider(
        counter: Counter,
        capture: Capture? = nil
    ) -> DocumentTranslationProviderAdapter {
        DocumentTranslationProviderAdapter(id: "adversarial-provider") { prompt in
            await counter.increment()
            if let capture { await capture.record(prompt) }
            let outputs = prompt.request.blocks.map { block in
                DocumentTranslationOutputBlock(id: block.id, text: "RU:\(block.sourceText)")
            }
            return String(
                decoding: try JSONEncoder().encode(
                    DocumentTranslationResponse(chunkId: prompt.request.chunkId, blocks: outputs)
                ),
                as: UTF8.self
            )
        }
    }

    private func mixedSession(approval: ApprovalMode) -> SessionState {
        let blocks = [
            DocumentBlock(
                id: "empty-before",
                location: DocumentLocation(paragraphOrdinal: 0),
                kind: .empty,
                spans: []
            ),
            DocumentBlock(
                id: "body",
                location: DocumentLocation(paragraphOrdinal: 1),
                spans: [RichTextSpan(id: "body-span", text: "A real paragraph.")]
            ),
            DocumentBlock(
                id: "empty-after",
                location: DocumentLocation(paragraphOrdinal: 2),
                kind: .empty,
                spans: []
            )
        ]
        let plan = DocumentChunkPlan(
            id: "mixed",
            blockIDs: blocks.map(\.id),
            sourceHash: "mixed-source"
        )
        return SessionState(
            sourceFile: "/tmp/mixed.txt",
            sourceFileName: "mixed.txt",
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
                    filePath: "/tmp/mixed.txt",
                    durationSec: 0,
                    startSec: 0,
                    endSec: 0,
                    original: "A real paragraph.",
                    translated: "",
                    status: .pending,
                    approved: false,
                    sourceAnchor: .document(
                        DocumentRange(startBlockID: "empty-before", endBlockID: "empty-after")
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
            approvalMode: approval
        )
    }

    private func slicedSession(approval: ApprovalMode = .manual) -> SessionState {
        let block = DocumentBlock(
            id: "long",
            location: DocumentLocation(paragraphOrdinal: 0),
            spans: [RichTextSpan(id: "span-long", text: "ABCDEFGHIJ")],
            sourceHash: "long-source"
        )
        let plans = [
            DocumentChunkPlan(
                id: "slice-1",
                blockIDs: ["long"],
                sourceTokenEstimate: 5,
                sourceHash: "slice-1-hash",
                blockSlices: [DocumentBlockSlice(blockID: "long", startOffset: 0, endOffset: 5)]
            ),
            DocumentChunkPlan(
                id: "slice-2",
                blockIDs: ["long"],
                sourceTokenEstimate: 5,
                sourceHash: "slice-2-hash",
                blockSlices: [DocumentBlockSlice(blockID: "long", startOffset: 5, endOffset: 10)]
            )
        ]
        let chunks = plans.enumerated().map { index, _ in
            ChunkData(
                index: index,
                filePath: "/tmp/long.txt",
                durationSec: 0,
                startSec: 0,
                endSec: 0,
                original: index == 0 ? "ABCDE" : "FGHIJ",
                translated: "",
                status: .pending,
                approved: false,
                sourceAnchor: .document(DocumentRange(startBlockID: "long", endBlockID: "long"))
            )
        }
        return SessionState(
            sourceFile: "/tmp/long.txt",
            sourceFileName: "long.txt",
            durationSec: 0,
            metadata: .empty,
            sourceLang: "English",
            targetLang: "Russian",
            transcriptionProvider: "",
            translationProvider: "mock",
            outputFormats: [.txt],
            chunks: chunks,
            currentChunkIndex: 0,
            sourceKind: .document,
            documentState: DocumentState(
                format: .txt,
                originalAsset: ProjectAssetReference(key: "source"),
                blocks: [block],
                chunks: plans
            ),
            approvalMode: approval
        )
    }
}
