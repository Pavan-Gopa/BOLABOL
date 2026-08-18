import CryptoKit
import Foundation
import Testing
@testable import VaniScript
@testable import VaniScriptCore

@Suite("DocumentSelectionTranslationEngineTests (PRD §26.5)")
struct DocumentSelectionTranslationEngineTests {
    @Test("request contains selected target and mapped source context, not the whole target block")
    func requestShape() throws {
        let source = makeSourceBlock(text: "The source phrase and neighboring source text.")
        let target = makeTargetBlock(text: "Целевая фраза и соседний перевод.", traits: [.bold])
        let snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: "Целевая фраза",
            range: NSRange(location: 0, length: 13),
            style: "body",
            traits: [.bold]
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in "{}" }
        )

        let request = try engine.makeRequest(
            snapshot: snapshot,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: .default,
            targetLanguage: "Russian"
        )

        #expect(request.selectedTargetText == "Целевая фраза")
        #expect(!request.selectedTargetText.contains("соседний перевод"))
        #expect(request.sourceAlignment == .mappedSpans)
        #expect(request.sourceContext == source.spans[0].text)
        #expect(request.sourceBlockID == source.id)
    }

    @Test("provider failure preserves the original selection")
    @MainActor
    func providerFailurePreservesSelection() async throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Исходная фраза")
        let snapshot = makeSnapshot(targetText: target.text, selectedText: target.text, range: NSRange(location: 0, length: (target.text as NSString).length))
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter(id: "mock-failure") { _ in
                throw TestProviderError.failed
            }
        )
        var applied = false

        do {
            _ = try await engine.execute(
                snapshot: snapshot,
                sourceBlocks: [source],
                targetBlocks: [target],
                profile: .default,
                targetLanguage: "Russian",
                currentTargetBlock: { _ in target },
                apply: { _ in applied = true }
            )
            Issue.record("Expected provider failure")
        } catch let error as DocumentSelectionTranslationEngineError {
            #expect(error == .providerFailure("mock-failure"))
        }
        #expect(applied == false)
        #expect(target.text == "Исходная фраза")
    }

    @Test("invalid schema and operation ID responses never apply")
    @MainActor
    func invalidResponsesRejected() async throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Исходная фраза")
        let snapshot = makeSnapshot(targetText: target.text, selectedText: target.text, range: NSRange(location: 0, length: (target.text as NSString).length))
        for invalidResponse in [
            DocumentSelectionTranslationResponse(schema: "wrong", operationID: snapshot.operationID.uuidString, replacementText: "Новая фраза"),
            DocumentSelectionTranslationResponse(operationID: "other-operation", replacementText: "Новая фраза")
        ] {
            let engine = DocumentSelectionTranslationEngine(
                provider: DocumentSelectionTranslationProviderAdapter { _ in
                    try encoded(invalidResponse)
                }
            )
            var applied = false
            do {
                _ = try await engine.execute(
                    snapshot: snapshot,
                    sourceBlocks: [source],
                    targetBlocks: [target],
                    profile: .default,
                    targetLanguage: "Russian",
                    currentTargetBlock: { _ in target },
                    apply: { _ in applied = true }
                )
                Issue.record("Expected invalid response")
            } catch is DocumentSelectionTranslationEngineError {
                // The precise validation code is covered by the core validator suite.
            }
            #expect(applied == false)
        }
    }

    @Test("stale response gate blocks overwrite after newer typing")
    @MainActor
    func staleResponseBlocksOverwrite() async throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Исходная фраза")
        let snapshot = makeSnapshot(targetText: target.text, selectedText: target.text, range: NSRange(location: 0, length: (target.text as NSString).length))
        let response = DocumentSelectionTranslationResponse(
            operationID: snapshot.operationID.uuidString,
            replacementText: "Новая фраза"
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in try encoded(response) }
        )
        let newerTarget = makeTargetBlock(text: "Пользовательская правка")
        var applied = false

        do {
            _ = try await engine.execute(
                snapshot: snapshot,
                sourceBlocks: [source],
                targetBlocks: [target],
                profile: .default,
                targetLanguage: "Russian",
                currentTargetBlock: { _ in newerTarget },
                apply: { _ in applied = true }
            )
            Issue.record("Expected stale response rejection")
        } catch let error as DocumentSelectionTranslationEngineError {
            #expect(error == .staleResponse(source.id))
        }
        #expect(applied == false)
        #expect(newerTarget.text == "Пользовательская правка")
    }

    @Test("empty and cross-block selections disable the AI command")
    func unsafeSelectionsAreDisabled() {
        let empty = DocumentTextSelectionSnapshot(side: .translation)
        #expect(DocumentSelectionTranslationEngine.isEligible(empty) == false)

        let fragments = [
            DocumentTextFragment(blockID: "b1", utf16RangeInSpan: NSRange(location: 0, length: 1), text: "a"),
            DocumentTextFragment(blockID: "b2", utf16RangeInSpan: NSRange(location: 0, length: 1), text: "b")
        ]
        let crossBlock = DocumentTextSelectionSnapshot(
            side: .translation,
            fragments: fragments,
            selectedText: "ab"
        )
        #expect(DocumentSelectionTranslationEngine.isEligible(crossBlock) == false)

        let sourceSide = DocumentTextSelectionSnapshot(
            side: .source,
            fragments: [fragments[0]],
            selectedText: "a"
        )
        #expect(DocumentSelectionTranslationEngine.isEligible(sourceSide) == false)
    }

    @Test("validated replacement inherits trusted formatting")
    @MainActor
    func trustedFormattingInheritance() async throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Исходная фраза", traits: [.bold])
        let snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: target.text,
            range: NSRange(location: 0, length: (target.text as NSString).length),
            style: "body",
            traits: [.bold]
        )
        let response = DocumentSelectionTranslationResponse(
            operationID: snapshot.operationID.uuidString,
            replacementText: "Новая фраза"
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in try encoded(response) }
        )
        var updated: TranslatedBlock?

        _ = try await engine.execute(
            snapshot: snapshot,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: .default,
            targetLanguage: "Russian",
            currentTargetBlock: { _ in target },
            apply: { updated = $0 }
        )

        #expect(updated?.text == "Новая фраза")
        #expect(updated?.spans.first?.traits == [.bold])
        #expect(updated?.spans.first?.styleKey == "body")
    }

    @Test("mixed-format selection fails safely instead of silently flattening")
    func mixedFormattingSelectionFailsSafely() throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Исходная фраза", traits: [.bold])
        let fragmentA = DocumentTextFragment(
            blockID: "block-1",
            spanID: "span-1",
            utf16RangeInSpan: NSRange(location: 0, length: 9),
            text: "Исходная "
        )
        let fragmentB = DocumentTextFragment(
            blockID: "block-1",
            spanID: "span-1",
            utf16RangeInSpan: NSRange(location: 9, length: 6),
            text: "фраза",
            traits: [.bold]
        )
        let snapshot = DocumentTextSelectionSnapshot(
            side: .translation,
            fragments: [fragmentA, fragmentB],
            selectedText: "Исходная фраза",
            blockHashes: ["block-1": sha256(target.text)]
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in "{}" }
        )

        #expect(throws: DocumentSelectionTranslationEngineError.mixedFormatting) {
            try engine.makeRequest(
                snapshot: snapshot,
                sourceBlocks: [source],
                targetBlocks: [target],
                profile: .default,
                targetLanguage: "Russian"
            )
        }
    }

    @Test("unmapped source spans fall back to block-level context")
    func blockContextFallback() throws {
        let source = DocumentBlock(
            id: "block-1",
            location: DocumentLocation(paragraphOrdinal: 0),
            spans: [RichTextSpan(id: "s-span-1", text: "The complete source block.")],
            sourceHash: sha256("The complete source block.")
        )
        let target = TranslatedBlock(
            id: "block-1",
            sourceBlockID: "block-1",
            text: "Полный целевой блок.",
            spans: [RichTextSpan(id: "t-span-1", text: "Полный целевой блок.", styleKey: "body")],
            sourceHash: "source-hash"
        )
        let snapshot = DocumentTextSelectionSnapshot(
            operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            side: .translation,
            fragments: [DocumentTextFragment(
                blockID: "block-1",
                spanID: "t-span-1",
                utf16RangeInSpan: NSRange(location: 0, length: 7),
                text: "Полный "
            )],
            selectedText: "Полный ",
            blockHashes: ["block-1": sha256(target.text)]
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in "{}" }
        )

        let request = try engine.makeRequest(
            snapshot: snapshot,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: .default,
            targetLanguage: "Russian"
        )

        #expect(request.sourceAlignment == .blockContext)
        #expect(request.sourceContext == source.spans[0].text)
        #expect(request.sourceSpans.isEmpty)
        #expect(request.selectedTargetText == "Полный ")
    }

    @Test("profile protected terms become required tokens on the request")
    func profileProtectedTermsReachRequest() throws {
        let source = makeSourceBlock(text: "Krishna speaks")
        let target = makeTargetBlock(text: "Krishna speaks")
        let snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: target.text,
            range: NSRange(location: 0, length: (target.text as NSString).length)
        )
        let profile = DocumentTranslationProfile(
            protectedTerms: [ProtectedTerm(id: "term-1", source: "Krishna", translation: "Krishna")]
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in "{}" }
        )

        let request = try engine.makeRequest(
            snapshot: snapshot,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: profile,
            targetLanguage: "Russian"
        )

        #expect(request.protectedTokens.contains("Krishna"))
    }

    @Test("same phrase in two blocks modifies only the selected block")
    @MainActor
    func samePhraseInTwoBlocksModifiesOnlySelectedBlock() async throws {
        // Rejected-candidate regression: source-block-ID-based string search would
        // replace the phrase in every block. This snapshot pins block-1; block-2
        // shares the identical phrase with identical span identity.
        let block1Source = DocumentBlock(
            id: "block-1",
            location: DocumentLocation(paragraphOrdinal: 0),
            spans: [RichTextSpan(id: "span-1", text: "Source phrase")],
            sourceHash: sha256("Source phrase")
        )
        let block2Source = DocumentBlock(
            id: "block-2",
            location: DocumentLocation(paragraphOrdinal: 1),
            spans: [RichTextSpan(id: "span-1", text: "Source phrase")],
            sourceHash: sha256("Source phrase")
        )
        let block1Target = TranslatedBlock(
            id: "block-1",
            sourceBlockID: "block-1",
            text: "Исходная фраза",
            spans: [RichTextSpan(id: "span-1", text: "Исходная фраза", styleKey: "body")],
            sourceHash: "source-hash"
        )
        let block2Target = TranslatedBlock(
            id: "block-2",
            sourceBlockID: "block-2",
            text: "Исходная фраза",
            spans: [RichTextSpan(id: "span-1", text: "Исходная фраза", styleKey: "body")],
            sourceHash: "source-hash"
        )
        let snapshot = DocumentTextSelectionSnapshot(
            operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000016")!,
            side: .translation,
            fragments: [DocumentTextFragment(
                blockID: "block-1",
                spanID: "span-1",
                utf16RangeInSpan: NSRange(location: 0, length: 14),
                text: "Исходная фраза",
                styleKey: "body"
            )],
            selectedText: "Исходная фраза",
            blockHashes: [
                "block-1": sha256("Исходная фраза"),
                "block-2": sha256("Исходная фраза")
            ]
        )
        let response = DocumentSelectionTranslationResponse(
            operationID: snapshot.operationID.uuidString,
            replacementText: "Обновлённая фраза"
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in try encoded(response) }
        )
        var updated: TranslatedBlock?

        let outcome = try await engine.execute(
            snapshot: snapshot,
            sourceBlocks: [block1Source, block2Source],
            targetBlocks: [block1Target, block2Target],
            profile: .default,
            targetLanguage: "Russian",
            currentTargetBlock: { blockID in
                [block1Target, block2Target].first {
                    $0.sourceBlockID == blockID || $0.id == blockID
                }
            },
            apply: { updated = $0 }
        )

        #expect(outcome.blockID == "block-1")
        #expect(updated?.sourceBlockID == "block-1")
        #expect(updated?.text == "Обновлённая фраза")
        // Untouched neighbor block keeps its identical phrase.
        #expect(block2Target.text == "Исходная фраза")
    }

    @Test("AI replacement preserves unchanged span identities through the full engine path")
    @MainActor
    func engineReplacementPreservesUnchangedSpanIDs() async throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = TranslatedBlock(
            id: "block-1",
            sourceBlockID: "block-1",
            text: "Исходная фраза остаётся",
            spans: [
                RichTextSpan(id: "span-1", text: "Исходная фраза", styleKey: "body", traits: [.bold]),
                RichTextSpan(id: "span-2", text: " остаётся", styleKey: "body", traits: [.italic])
            ],
            sourceHash: "source-hash"
        )
        let snapshot = DocumentTextSelectionSnapshot(
            operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000017")!,
            side: .translation,
            fragments: [DocumentTextFragment(
                blockID: "block-1",
                spanID: "span-1",
                utf16RangeInSpan: NSRange(location: 0, length: 14),
                text: "Исходная фраза",
                styleKey: "body",
                traits: [.bold]
            )],
            selectedText: "Исходная фраза",
            blockHashes: ["block-1": sha256(target.text)]
        )
        let response = DocumentSelectionTranslationResponse(
            operationID: snapshot.operationID.uuidString,
            replacementText: "Новая фраза"
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in try encoded(response) }
        )
        var updated: TranslatedBlock?

        _ = try await engine.execute(
            snapshot: snapshot,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: .default,
            targetLanguage: "Russian",
            currentTargetBlock: { _ in target },
            apply: { updated = $0 }
        )

        let spans = try #require(updated?.spans)
        #expect(updated?.text == "Новая фраза остаётся")
        // Replaced span keeps its trusted identity through .inheritExisting.
        #expect(spans[0].id == "span-1")
        #expect(spans[0].traits == [.bold])
        // Span outside the selection keeps identity, text, and traits (INV-3).
        let span2 = spans.first(where: { $0.id == "span-2" })
        #expect(span2 != nil)
        #expect(span2?.text == " остаётся")
        #expect(span2?.traits == Set<InlineTrait>([.italic]))
    }

    @Test("single-block translation-side selection is eligible")
    func eligibleSingleBlockSelection() {
        let target = makeTargetBlock(text: "Исходная фраза")
        let snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: target.text,
            range: NSRange(location: 0, length: (target.text as NSString).length)
        )
        #expect(DocumentSelectionTranslationEngine.isEligible(snapshot))
    }

    @Test("selection without a recorded target hash never reaches the provider")
    @MainActor
    func missingTargetHashBlocksBeforeProvider() async throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Исходная фраза")
        var snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: target.text,
            range: NSRange(location: 0, length: (target.text as NSString).length)
        )
        snapshot.blockHashes = [:]
        nonisolated(unsafe) var providerCalled = false
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in
                providerCalled = true
                return "{}"
            }
        )
        var applied = false

        do {
            _ = try await engine.execute(
                snapshot: snapshot,
                sourceBlocks: [source],
                targetBlocks: [target],
                profile: .default,
                targetLanguage: "Russian",
                currentTargetBlock: { _ in target },
                apply: { _ in applied = true }
            )
            Issue.record("Expected missing target hash")
        } catch let error as DocumentSelectionTranslationEngineError {
            #expect(error == .missingTargetHash(source.id))
        }
        #expect(providerCalled == false)
        #expect(applied == false)
    }

    @Test("selection text that no longer matches the live span is rejected")
    func selectionChangedDetected() throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Исходная фраза")
        let snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: "Другая фраза",
            range: NSRange(location: 0, length: 13)
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in "{}" }
        )

        #expect(throws: DocumentSelectionTranslationEngineError.selectionChanged(source.id)) {
            try engine.makeRequest(
                snapshot: snapshot,
                sourceBlocks: [source],
                targetBlocks: [target],
                profile: .default,
                targetLanguage: "Russian"
            )
        }
    }

    @Test("formatting-only drift while AI is working blocks the overwrite")
    @MainActor
    func formattingDriftBlocksOverwrite() async throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Исходная фраза")
        let snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: target.text,
            range: NSRange(location: 0, length: (target.text as NSString).length)
        )
        let response = DocumentSelectionTranslationResponse(
            operationID: snapshot.operationID.uuidString,
            replacementText: "Новая фраза"
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in try encoded(response) }
        )
        let reformatted = makeTargetBlock(text: target.text, traits: [.italic])
        var applied = false

        do {
            _ = try await engine.execute(
                snapshot: snapshot,
                sourceBlocks: [source],
                targetBlocks: [target],
                profile: .default,
                targetLanguage: "Russian",
                currentTargetBlock: { _ in reformatted },
                apply: { _ in applied = true }
            )
            Issue.record("Expected stale response rejection")
        } catch let error as DocumentSelectionTranslationEngineError {
            #expect(error == .staleResponse(source.id))
        }
        #expect(applied == false)
    }

    @Test("target block removed after the provider call is never applied")
    @MainActor
    func missingCurrentTargetBlockNeverApplies() async throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Исходная фраза")
        let snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: target.text,
            range: NSRange(location: 0, length: (target.text as NSString).length)
        )
        let response = DocumentSelectionTranslationResponse(
            operationID: snapshot.operationID.uuidString,
            replacementText: "Новая фраза"
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in try encoded(response) }
        )
        var applied = false

        do {
            _ = try await engine.execute(
                snapshot: snapshot,
                sourceBlocks: [source],
                targetBlocks: [target],
                profile: .default,
                targetLanguage: "Russian",
                currentTargetBlock: { _ in nil },
                apply: { _ in applied = true }
            )
            Issue.record("Expected missing target block")
        } catch let error as DocumentSelectionTranslationEngineError {
            #expect(error == .missingTargetBlock(source.id))
        }
        #expect(applied == false)
    }

    @Test("non-JSON provider output is rejected without applying")
    @MainActor
    func nonJSONProviderOutputRejected() async throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Исходная фраза")
        let snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: target.text,
            range: NSRange(location: 0, length: (target.text as NSString).length)
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in "not json" }
        )
        var applied = false

        do {
            _ = try await engine.execute(
                snapshot: snapshot,
                sourceBlocks: [source],
                targetBlocks: [target],
                profile: .default,
                targetLanguage: "Russian",
                currentTargetBlock: { _ in target },
                apply: { _ in applied = true }
            )
            Issue.record("Expected invalid response")
        } catch let error as DocumentSelectionTranslationEngineError {
            #expect(error == .invalidResponse("invalidJSON"))
        }
        #expect(applied == false)
    }

    @Test("cancellation propagates as CancellationError, not provider failure")
    @MainActor
    func cancellationPropagates() async throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Исходная фраза")
        let snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: target.text,
            range: NSRange(location: 0, length: (target.text as NSString).length)
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in throw CancellationError() }
        )
        var applied = false

        await #expect(throws: CancellationError.self) {
            _ = try await engine.execute(
                snapshot: snapshot,
                sourceBlocks: [source],
                targetBlocks: [target],
                profile: .default,
                targetLanguage: "Russian",
                currentTargetBlock: { _ in target },
                apply: { _ in applied = true }
            )
        }
        #expect(applied == false)
    }

    @Test("length-ratio warnings surface without blocking the replacement")
    @MainActor
    func warningsSurfaceWithoutBlocking() async throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Фраза")
        let snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: target.text,
            range: NSRange(location: 0, length: (target.text as NSString).length)
        )
        let response = DocumentSelectionTranslationResponse(
            operationID: snapshot.operationID.uuidString,
            replacementText: "Это очень длинная заменяющая фраза, которая намного длиннее исходной."
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in try encoded(response) }
        )
        var applyCount = 0

        let outcome = try await engine.execute(
            snapshot: snapshot,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: .default,
            targetLanguage: "Russian",
            currentTargetBlock: { _ in target },
            apply: { _ in applyCount += 1 }
        )

        #expect(applyCount == 1)
        #expect(outcome.warningCodes.contains("lengthRatio"))
    }

    @Test("outcome reports replacement length in UTF-16 units")
    @MainActor
    func replacementUTF16LengthCountsSurrogatePairs() async throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Исходная фраза")
        let snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: target.text,
            range: NSRange(location: 0, length: (target.text as NSString).length)
        )
        let response = DocumentSelectionTranslationResponse(
            operationID: snapshot.operationID.uuidString,
            replacementText: "🌟🌟"
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in try encoded(response) }
        )

        let outcome = try await engine.execute(
            snapshot: snapshot,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: .default,
            targetLanguage: "Russian",
            currentTargetBlock: { _ in target },
            apply: { _ in }
        )

        #expect(outcome.replacementUTF16Length == 4)
    }

    @Test("target prefix and suffix are bounded to 120 units around the selection")
    func prefixSuffixBoundedAroundSelection() throws {
        let prefixText = String(repeating: "a", count: 150)
        let selection = "MIDDLE"
        let suffixText = String(repeating: "b", count: 150)
        let fullText = prefixText + selection + suffixText
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: fullText)
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in "{}" }
        )

        let middle = makeSnapshot(
            targetText: fullText,
            selectedText: selection,
            range: NSRange(location: 150, length: 6)
        )
        let middleRequest = try engine.makeRequest(
            snapshot: middle,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: .default,
            targetLanguage: "Russian"
        )
        #expect(middleRequest.targetPrefix == String(repeating: "a", count: 120))
        #expect(middleRequest.targetSuffix == String(repeating: "b", count: 120))

        let atStart = makeSnapshot(
            targetText: fullText,
            selectedText: prefixText,
            range: NSRange(location: 0, length: 150)
        )
        let startRequest = try engine.makeRequest(
            snapshot: atStart,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: .default,
            targetLanguage: "Russian"
        )
        #expect(startRequest.targetPrefix.isEmpty)
        #expect(startRequest.targetSuffix == selection + String(repeating: "b", count: 114))

        let atEnd = makeSnapshot(
            targetText: fullText,
            selectedText: suffixText,
            range: NSRange(location: 156, length: 150)
        )
        let endRequest = try engine.makeRequest(
            snapshot: atEnd,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: .default,
            targetLanguage: "Russian"
        )
        #expect(endRequest.targetPrefix == String(repeating: "a", count: 114) + selection)
        #expect(endRequest.targetSuffix.isEmpty)
    }

    @Test("glossary hints use the per-language translation and cap at 64 entries")
    func glossaryPerLanguageAndCap() throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Исходная фраза")
        let snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: target.text,
            range: NSRange(location: 0, length: (target.text as NSString).length)
        )
        var entries = [
            GlossaryEntry(
                id: "term-krishna",
                variants: [],
                source: "Krishna",
                translation: "Krishna",
                category: nil,
                translations: ["Russian": "Кришна"],
                remember: false,
                createdAt: "",
                updatedAt: ""
            )
        ]
        entries += (1...69).map { index in
            GlossaryEntry(
                id: "term-\(index)",
                variants: [],
                source: "Source \(index)",
                translation: "Target \(index)",
                category: nil,
                translations: [:],
                remember: false,
                createdAt: "",
                updatedAt: ""
            )
        }
        let profile = DocumentTranslationProfile(projectGlossary: entries)
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in "{}" }
        )

        let request = try engine.makeRequest(
            snapshot: snapshot,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: profile,
            targetLanguage: "Russian"
        )

        #expect(request.glossary.count == 64)
        #expect(request.glossary.first(where: { $0.id == "term-krishna" })?.translation == "Кришна")
    }

    @Test("identical protected text from fragment and source span is deduplicated")
    func protectedTokensDeduplicated() throws {
        let source = DocumentBlock(
            id: "block-1",
            location: DocumentLocation(paragraphOrdinal: 0),
            spans: [RichTextSpan(
                id: "span-1",
                text: "Krishna speaks",
                styleKey: "body",
                translationPolicy: .protect
            )],
            sourceHash: sha256("Krishna speaks")
        )
        let target = makeTargetBlock(text: "Krishna speaks")
        let snapshot = DocumentTextSelectionSnapshot(
            operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000018")!,
            side: .translation,
            fragments: [DocumentTextFragment(
                blockID: "block-1",
                spanID: "span-1",
                utf16RangeInSpan: NSRange(location: 0, length: 14),
                text: "Krishna speaks",
                styleKey: "body",
                translationPolicy: .protect
            )],
            selectedText: "Krishna speaks",
            blockHashes: ["block-1": sha256(target.text)]
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in "{}" }
        )

        let request = try engine.makeRequest(
            snapshot: snapshot,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: .default,
            targetLanguage: "Russian"
        )

        #expect(request.protectedTokens == ["Krishna speaks"])
    }

    @Test("source block without a stored hash falls back to hashing its text")
    func sourceBlockHashFallback() throws {
        let source = DocumentBlock(
            id: "block-1",
            location: DocumentLocation(paragraphOrdinal: 0),
            spans: [RichTextSpan(id: "span-1", text: "Source phrase", styleKey: "body")],
            sourceHash: ""
        )
        let target = makeTargetBlock(text: "Исходная фраза")
        let snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: target.text,
            range: NSRange(location: 0, length: (target.text as NSString).length)
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in "{}" }
        )

        let request = try engine.makeRequest(
            snapshot: snapshot,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: .default,
            targetLanguage: "Russian"
        )

        #expect(request.sourceBlockHash == sha256("Source phrase"))
    }

    @Test("spanless target block resolves a synthetic span and applies the replacement")
    @MainActor
    func spanlessTargetBlockAppliesReplacement() async throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = TranslatedBlock(
            id: "block-1",
            sourceBlockID: "block-1",
            text: "Исходная фраза",
            spans: [],
            sourceHash: "source-hash"
        )
        let snapshot = DocumentTextSelectionSnapshot(
            operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000019")!,
            side: .translation,
            fragments: [DocumentTextFragment(
                blockID: "block-1",
                utf16RangeInSpan: NSRange(location: 0, length: 14),
                text: "Исходная фраза"
            )],
            selectedText: "Исходная фраза",
            blockHashes: ["block-1": sha256(target.text)]
        )
        let response = DocumentSelectionTranslationResponse(
            operationID: snapshot.operationID.uuidString,
            replacementText: "Новая фраза"
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in try encoded(response) }
        )
        var updated: TranslatedBlock?

        _ = try await engine.execute(
            snapshot: snapshot,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: .default,
            targetLanguage: "Russian",
            currentTargetBlock: { _ in target },
            apply: { updated = $0 }
        )

        #expect(updated?.text == "Новая фраза")
    }

    @Test("contiguous selection across two same-style spans applies one replacement")
    @MainActor
    func multiFragmentSelectionAcrossSpansAppliesOnce() async throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = TranslatedBlock(
            id: "block-1",
            sourceBlockID: "block-1",
            text: "Исходная фраза остаётся",
            spans: [
                RichTextSpan(id: "span-1", text: "Исходная", styleKey: "body"),
                RichTextSpan(id: "span-2", text: " фраза", styleKey: "body"),
                RichTextSpan(id: "span-3", text: " остаётся", styleKey: "body", traits: [.italic])
            ],
            sourceHash: "source-hash"
        )
        let snapshot = DocumentTextSelectionSnapshot(
            operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            side: .translation,
            fragments: [
                DocumentTextFragment(
                    blockID: "block-1",
                    spanID: "span-1",
                    utf16RangeInSpan: NSRange(location: 0, length: 8),
                    text: "Исходная",
                    styleKey: "body"
                ),
                DocumentTextFragment(
                    blockID: "block-1",
                    spanID: "span-2",
                    utf16RangeInSpan: NSRange(location: 0, length: 6),
                    text: " фраза",
                    styleKey: "body"
                )
            ],
            selectedText: "Исходная фраза",
            blockHashes: ["block-1": sha256(target.text)]
        )
        let response = DocumentSelectionTranslationResponse(
            operationID: snapshot.operationID.uuidString,
            replacementText: "Новая фраза"
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in try encoded(response) }
        )
        var updated: TranslatedBlock?

        _ = try await engine.execute(
            snapshot: snapshot,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: .default,
            targetLanguage: "Russian",
            currentTargetBlock: { _ in target },
            apply: { updated = $0 }
        )

        #expect(updated?.text == "Новая фраза остаётся")
        let spans = try #require(updated?.spans)
        // The fully selected contiguous run collapses into one replacement span
        // inheriting the first fragment's identity (INV-3).
        let replaced = spans.first(where: { $0.id == "span-1" })
        #expect(replaced?.text == "Новая фраза")
        #expect(replaced?.styleKey == "body")
        // The span outside the selection keeps identity, text, and traits.
        let untouched = spans.first(where: { $0.id == "span-3" })
        #expect(untouched?.text == " остаётся")
        #expect(untouched?.traits == Set<InlineTrait>([.italic]))
    }

    @Test("prompt renders the schema, operation ID, and markdown instruction")
    func promptRendersContractAndOperation() throws {
        let source = makeSourceBlock(text: "Source phrase")
        let target = makeTargetBlock(text: "Исходная фраза")
        let snapshot = makeSnapshot(
            targetText: target.text,
            selectedText: target.text,
            range: NSRange(location: 0, length: (target.text as NSString).length)
        )
        let engine = DocumentSelectionTranslationEngine(
            provider: DocumentSelectionTranslationProviderAdapter { _ in "{}" }
        )
        let request = try engine.makeRequest(
            snapshot: snapshot,
            sourceBlocks: [source],
            targetBlocks: [target],
            profile: .default,
            targetLanguage: "Russian"
        )

        let prompt = DocumentSelectionTranslationPrompt(request: request)
        #expect(prompt.renderedText.contains("vaniscript.document.selection.v1"))
        #expect(prompt.renderedText.contains(request.operationID))
        #expect(prompt.renderedText.lowercased().contains("markdown"))
    }

    private enum TestProviderError: Error {
        case failed
    }

    private func makeSourceBlock(text: String) -> DocumentBlock {
        DocumentBlock(
            id: "block-1",
            location: DocumentLocation(paragraphOrdinal: 0),
            spans: [RichTextSpan(id: "span-1", text: text, styleKey: "body")],
            sourceHash: sha256(text)
        )
    }

    private func makeTargetBlock(text: String, traits: Set<InlineTrait> = []) -> TranslatedBlock {
        TranslatedBlock(
            id: "block-1",
            sourceBlockID: "block-1",
            text: text,
            spans: [RichTextSpan(id: "span-1", text: text, styleKey: "body", traits: traits)],
            sourceHash: "source-hash"
        )
    }

    private func makeSnapshot(
        targetText: String,
        selectedText: String,
        range: NSRange,
        style: String = "body",
        traits: Set<InlineTrait> = []
    ) -> DocumentTextSelectionSnapshot {
        DocumentTextSelectionSnapshot(
            operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            side: .translation,
            fragments: [DocumentTextFragment(
                blockID: "block-1",
                spanID: "span-1",
                utf16RangeInSpan: range,
                text: selectedText,
                styleKey: style,
                traits: traits
            )],
            selectedText: selectedText,
            blockHashes: ["block-1": sha256(targetText)]
        )
    }

    private func encoded(_ response: DocumentSelectionTranslationResponse) throws -> String {
        let data = try JSONEncoder().encode(response)
        return String(decoding: data, as: UTF8.self)
    }

    private func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
