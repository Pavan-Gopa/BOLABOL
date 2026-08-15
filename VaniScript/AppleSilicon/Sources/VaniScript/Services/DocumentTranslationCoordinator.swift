import CryptoKit
import Foundation
import VaniScriptCore

public enum DocumentTranslationExecutionIntent: String, Codable, Equatable, Sendable {
    case automaticBatch
    case manualCurrent
    case targetedCurrent
}

public typealias DocumentTranslationExecutionMode = DocumentTranslationExecutionIntent

public struct DocumentTranslationCoordinatorProgress: Equatable, Sendable {
    public var intent: DocumentTranslationExecutionIntent
    public var currentIndex: Int?
    public var totalChunks: Int
    public var completedCount: Int
    public var autoApprovedCount: Int
    public var needsReviewCount: Int
    public var failedCount: Int
    public var message: String
    public var fraction: Double

    public init(
        intent: DocumentTranslationExecutionIntent,
        currentIndex: Int?,
        totalChunks: Int,
        completedCount: Int,
        autoApprovedCount: Int,
        needsReviewCount: Int,
        failedCount: Int,
        message: String,
        fraction: Double
    ) {
        self.intent = intent
        self.currentIndex = currentIndex
        self.totalChunks = totalChunks
        self.completedCount = completedCount
        self.autoApprovedCount = autoApprovedCount
        self.needsReviewCount = needsReviewCount
        self.failedCount = failedCount
        self.message = message
        self.fraction = fraction
    }
}

public enum DocumentTranslationTerminalOutcome: String, Codable, Equatable, Sendable {
    case success
    case needsReview
    case validationFailure
    case providerFailure
    case cancelled
}

public struct DocumentTranslationCoordinatorResult: Equatable, Sendable {
    public var session: SessionState
    public var intent: DocumentTranslationExecutionIntent
    public var processedIndices: [Int]
    public var providerCallCount: Int
    public var stoppedByCancellation: Bool
    public var outcome: DocumentTranslationTerminalOutcome
    public var message: String

    public init(
        session: SessionState,
        intent: DocumentTranslationExecutionIntent,
        processedIndices: [Int] = [],
        providerCallCount: Int = 0,
        stoppedByCancellation: Bool = false,
        outcome: DocumentTranslationTerminalOutcome = .success,
        message: String = ""
    ) {
        self.session = session
        self.intent = intent
        self.processedIndices = processedIndices
        self.providerCallCount = providerCallCount
        self.stoppedByCancellation = stoppedByCancellation
        self.outcome = outcome
        self.message = message
    }
}

/// Owns document queue decisions separately from media processing. A targeted
/// request never enters the batch loop, even when the session is automatic.
public actor DocumentTranslationCoordinator {
    public typealias SaveHandler = @Sendable (SessionState) async -> Void
    public typealias ProgressHandler = @Sendable (DocumentTranslationCoordinatorProgress) async -> Void

    private let engine: DocumentTranslationEngine
    private let saveHandler: SaveHandler?
    private let progressHandler: ProgressHandler?
    private let maxRepairAttempts: Int
    private var session: SessionState
    private var paused = false
    private var cancelled = false
    private var rollingMemory: DocumentTranslationMemory
    private var providerCallCount = 0

    public init(
        session: SessionState,
        engine: DocumentTranslationEngine,
        maxRepairAttempts: Int = 2,
        save: SaveHandler? = nil,
        progress: ProgressHandler? = nil
    ) {
        self.session = Self.normalizedSession(session)
        self.engine = engine
        self.maxRepairAttempts = max(0, min(2, maxRepairAttempts))
        self.saveHandler = save
        self.progressHandler = progress
        self.rollingMemory = Self.initialMemory(for: session)
    }

    public init(
        engine: DocumentTranslationEngine,
        session: SessionState,
        maxRepairAttempts: Int = 2,
        save: SaveHandler? = nil,
        progress: ProgressHandler? = nil
    ) {
        self.init(session: session, engine: engine, maxRepairAttempts: maxRepairAttempts, save: save, progress: progress)
    }

    public func currentSession() -> SessionState { session }

    public func pause() { paused = true }
    public func resume() { paused = false }
    public func cancel() { cancelled = true; paused = false }
    public func isPaused() -> Bool { paused }
    public func isCancelled() -> Bool { cancelled }

    public func run(
        intent: DocumentTranslationExecutionIntent,
        currentIndex: Int? = nil
    ) async throws -> DocumentTranslationCoordinatorResult {
        guard session.sourceKind == .document, session.documentState != nil else {
            throw DocumentTranslationCoordinatorError.notDocumentSession
        }
        cancelled = false
        providerCallCount = 0
        switch intent {
        case .automaticBatch:
            return await runAutomaticBatch()
        case .manualCurrent:
            let index = currentIndex ?? session.currentChunkIndex
            return await runSingle(index: index, intent: .manualCurrent)
        case .targetedCurrent:
            let index = currentIndex ?? session.currentChunkIndex
            return await runSingle(index: index, intent: .targetedCurrent)
        }
    }

    public func automaticBatch() async throws -> DocumentTranslationCoordinatorResult {
        try await run(intent: .automaticBatch)
    }

    public func manualCurrent() async throws -> DocumentTranslationCoordinatorResult {
        try await run(intent: .manualCurrent)
    }

    public func targetedCurrent() async throws -> DocumentTranslationCoordinatorResult {
        try await run(intent: .targetedCurrent)
    }

    private func runAutomaticBatch() async -> DocumentTranslationCoordinatorResult {
        let indexes = session.chunks.indices.filter { index in
            !hasReadyTranslation(at: index)
                || session.chunks[index].reviewDisposition == .needsReview
                || session.chunks[index].reviewDisposition == .failed
        }
        var processed: [Int] = []
        var terminalOutcome: DocumentTranslationTerminalOutcome = .success
        var terminalMessage = "Document translation complete."
        for index in indexes {
            if cancelled { break }
            await waitIfPaused()
            if cancelled { break }
            let outcome = await process(index: index, intent: .automaticBatch)
            if outcome.didProcess { processed.append(index) }
            if terminalOutcome == .success, outcome.outcome != .success {
                terminalOutcome = outcome.outcome
                terminalMessage = outcome.message
            }
            await publishProgress(intent: .automaticBatch, currentIndex: index, message: outcome.message)
        }

        if cancelled {
            terminalOutcome = .cancelled
            terminalMessage = "Document translation cancelled."
        }
        if let needsReview = session.chunks.firstIndex(where: {
            $0.reviewDisposition == .needsReview || $0.reviewDisposition == .failed
        }) {
            session.currentChunkIndex = needsReview
        } else if !session.chunks.isEmpty {
            session.currentChunkIndex = min(session.currentChunkIndex, session.chunks.count - 1)
        }
        await publishProgress(
            intent: .automaticBatch,
            currentIndex: session.currentChunkIndex,
            message: terminalMessage
        )
        return DocumentTranslationCoordinatorResult(
            session: session,
            intent: .automaticBatch,
            processedIndices: processed,
            providerCallCount: providerCallCount,
            stoppedByCancellation: cancelled,
            outcome: terminalOutcome,
            message: terminalMessage
        )
    }

    private func runSingle(index: Int, intent: DocumentTranslationExecutionIntent) async -> DocumentTranslationCoordinatorResult {
        guard session.chunks.indices.contains(index) else {
            let message = "Document chunk is unavailable."
            return DocumentTranslationCoordinatorResult(
                session: session,
                intent: intent,
                providerCallCount: providerCallCount,
                outcome: .validationFailure,
                message: message
            )
        }
        session.currentChunkIndex = index
        let outcome: ProcessOutcome
        if intent == .manualCurrent, hasReadyTranslation(at: index) {
            outcome = ProcessOutcome(
                didProcess: false,
                message: "Chunk already has a valid translation.",
                outcome: .success
            )
        } else {
            outcome = await process(index: index, intent: intent)
        }
        await publishProgress(intent: intent, currentIndex: index, message: outcome.message)
        return DocumentTranslationCoordinatorResult(
            session: session,
            intent: intent,
            processedIndices: outcome.didProcess ? [index] : [],
            providerCallCount: providerCallCount,
            stoppedByCancellation: cancelled,
            outcome: outcome.outcome,
            message: outcome.message
        )
    }

    private struct ProcessOutcome: Sendable {
        var didProcess: Bool
        var message: String
        var outcome: DocumentTranslationTerminalOutcome
    }

    private func process(index: Int, intent: DocumentTranslationExecutionIntent) async -> ProcessOutcome {
        guard session.chunks.indices.contains(index), let documentState = session.documentState else {
            return ProcessOutcome(
                didProcess: false,
                message: "Document chunk is unavailable.",
                outcome: .validationFailure
            )
        }
        guard let plan = plan(for: index, in: documentState), !plan.blockIDs.isEmpty else {
            markFailure(index: index, code: "missingPlan", message: "Document chunk plan is unavailable.", preserveValid: false)
            await save()
            return ProcessOutcome(
                didProcess: false,
                message: "Document chunk plan is unavailable.",
                outcome: .validationFailure
            )
        }
        if intent != .targetedCurrent, intent != .manualCurrent, hasReadyTranslation(at: index) {
            return ProcessOutcome(
                didProcess: false,
                message: "Chunk already has a valid translation.",
                outcome: .success
            )
        }

        let request = DocumentTranslationEngine.request(
            for: plan,
            in: documentState,
            sourceLanguage: session.sourceLang,
            targetLanguage: session.targetLang,
            memory: rollingMemory
        )
        guard request.expectedBlockIDs == plan.blockIDs else {
            let message = "The selected document chunk is missing one or more planned source blocks."
            markFailure(index: index, code: "missingSourceBlock", message: message, preserveValid: hasReadyTranslation(at: index))
            await save()
            return ProcessOutcome(
                didProcess: false,
                message: message,
                outcome: .validationFailure
            )
        }

        let hadPriorValid = hasReadyTranslation(at: index)
        session.chunks[index].status = .processing
        await publishProgress(intent: intent, currentIndex: index, message: "Translating chunk \(index + 1) / \(session.chunks.count)…")

        var lastResult: DocumentTranslationEngineResult?
        var lastError: Error?
        for attempt in 0...maxRepairAttempts {
            if cancelled {
                session.chunks[index].status = hadPriorValid ? .done : .pending
                return ProcessOutcome(
                    didProcess: false,
                    message: "Document translation cancelled.",
                    outcome: .cancelled
                )
            }
            do {
                if let prior = lastResult {
                    // Do not spend a call when the remaining validation
                    // errors belong only to deterministic structure or have no
                    // identifiable translatable block.
                    let repairableIDs = await engine.repairableBlockIDs(
                        request: request,
                        result: prior
                    )
                    guard !repairableIDs.isEmpty else { break }
                }
                if !request.translatableBlocks.isEmpty {
                    providerCallCount += 1
                }
                let result: DocumentTranslationEngineResult
                if let prior = lastResult {
                    result = try await engine.translate(
                        request: request,
                        repairFor: prior,
                        attempts: attempt + 1,
                        intent: intent.rawValue,
                        chunkIndex: index
                    )
                } else {
                    result = try await engine.translate(
                        request: request,
                        attempts: 1,
                        intent: intent.rawValue,
                        chunkIndex: index
                    )
                }
                lastResult = result
                if result.validation.isValid {
                    let approval: ReviewDisposition = intent == .automaticBatch ? .autoApproved : .pending
                    commit(
                        result: result,
                        request: request,
                        plan: plan,
                        index: index,
                        disposition: approval,
                        attempts: attempt + 1
                    )
                    if approval.isApproved {
                        updateRollingMemory(from: result.response, request: request)
                    }
                    await save()
                    let label = approval == .autoApproved
                        ? "Auto-approved"
                        : "Translation ready for manual approval"
                    return ProcessOutcome(
                        didProcess: true,
                        message: "\(label): chunk \(index + 1) / \(session.chunks.count).",
                        outcome: .success
                    )
                }
            } catch is CancellationError {
                session.chunks[index].status = hadPriorValid ? .done : .pending
                return ProcessOutcome(
                    didProcess: false,
                    message: "Document translation cancelled.",
                    outcome: .cancelled
                )
            } catch {
                lastError = error
                if case DocumentTranslationEngineError.requestExceedsBudget = error {
                    providerCallCount = max(0, providerCallCount - 1)
                }
                // A provider/network error is not repairable JSON. Stop this
                // chunk and preserve any previously committed valid replacement.
                break
            }
        }

        let issues: [QualityIssue]
        if let lastError {
            issues = [QualityIssue(code: "provider", message: lastError.localizedDescription)]
        } else if let lastResult {
            issues = lastResult.validation.issues
        } else {
            issues = [QualityIssue(code: "invalidOutput", message: "The provider response did not pass local validation.")]
        }
        let preserve = hadPriorValid
        let detail = issues.map { issue in
            if issue.code.isEmpty || issue.message.hasPrefix("[\(issue.code)]") {
                return issue.message
            }
            return "[\(issue.code)] \(issue.message)"
        }.joined(separator: " ")
        markFailure(
            index: index,
            code: preserve ? "targetedReplacementFailed" : "translationFailed",
            message: detail,
            issues: issues,
            preserveValid: preserve,
            needsReviewOnFailure: lastResult != nil && lastError == nil
        )
        await save()
        let disposition = preserve
            ? "Previous valid translation preserved. \(detail)"
            : detail
        let terminalOutcome: DocumentTranslationTerminalOutcome
        if lastError != nil {
            terminalOutcome = .providerFailure
        } else if lastResult != nil {
            terminalOutcome = preserve ? .needsReview : .validationFailure
        } else {
            terminalOutcome = .providerFailure
        }
        return ProcessOutcome(
            didProcess: true,
            message: disposition,
            outcome: terminalOutcome
        )
    }

    private func commit(
        result: DocumentTranslationEngineResult,
        request: DocumentTranslationRequest,
        plan: DocumentChunkPlan,
        index: Int,
        disposition: ReviewDisposition,
        attempts: Int
    ) {
        guard var documentState = session.documentState else { return }
        let language = TranslationArchive.languageKey(session.targetLang)
        var translations = documentState.translationsByLanguage[language] ?? [:]
        let outputHash = stableHash(result.response.text)
        let report = result.validation.qualityReport(
            sourceHash: plan.sourceHash,
            attempts: attempts,
            outputHash: outputHash
        )
        let translatedBlocks = result.response.blocks.map { output in
            let sourceBlock = documentState.blocks.first(where: { $0.id == output.id })
                ?? documentState.blocks.first(where: { block in plan.blockSlices?.contains(where: { $0.blockID == block.id }) == true })

            let spans = output.spans.enumerated().map { spanIndex, outputSpan in
                let matchedSourceSpan: RichTextSpan?
                if let spanId = outputSpan.id, let match = sourceBlock?.spans.first(where: { $0.id == spanId }) {
                    matchedSourceSpan = match
                } else if let match = sourceBlock?.spans.first(where: { $0.styleKey == outputSpan.style || ($0.styleKey.isEmpty && outputSpan.style == "plain") }) {
                    matchedSourceSpan = match
                } else if let sourceSpans = sourceBlock?.spans, sourceSpans.indices.contains(spanIndex), sourceSpans.count == output.spans.count {
                    matchedSourceSpan = sourceSpans[spanIndex]
                } else {
                    matchedSourceSpan = nil
                }

                let spanId = outputSpan.id ?? matchedSourceSpan?.id ?? UUID().uuidString
                let styleKey = matchedSourceSpan?.styleKey ?? outputSpan.style
                let traits = matchedSourceSpan?.traits ?? []
                let policy = matchedSourceSpan?.translationPolicy ?? .translate
                let colorHex = matchedSourceSpan?.foregroundColorHex

                return RichTextSpan(
                    id: spanId,
                    text: outputSpan.text,
                    styleKey: styleKey,
                    traits: traits,
                    translationPolicy: policy,
                    foregroundColorHex: colorHex
                )
            }

            return TranslatedBlock(
                id: output.id,
                sourceBlockID: output.id,
                text: output.text,
                spans: spans,
                sourceHash: plan.sourceHash,
                reviewDisposition: disposition,
                qualityReport: report
            )
        }
        for block in translatedBlocks {
            if let slice = plan.blockSlices?.first(where: { $0.blockID == block.sourceBlockID }) {
                let allSlicesForBlock = documentState.chunks
                    .compactMap(\.blockSlices)
                    .flatMap { $0 }
                    .filter { $0.blockID == block.sourceBlockID }
                    .sorted { $0.startOffset < $1.startOffset }
                let sliceIndex = allSlicesForBlock.firstIndex(where: {
                    $0.startOffset == slice.startOffset && $0.endOffset == slice.endOffset
                }) ?? 0
                let compoundKey = TranslationArchive.sliceKey(blockID: block.sourceBlockID, sliceIndex: sliceIndex)
                let offsetKey = TranslationArchive.sliceKey(blockID: block.sourceBlockID, startOffset: slice.startOffset, endOffset: slice.endOffset)
                var sliceBlock = block
                sliceBlock.id = compoundKey
                sliceBlock.sourceBlockID = compoundKey
                translations[compoundKey] = sliceBlock
                translations[offsetKey] = sliceBlock

                let availableSliceBlocks = allSlicesForBlock.enumerated().compactMap { i, s -> TranslatedBlock? in
                    let keyI = TranslationArchive.sliceKey(blockID: block.sourceBlockID, sliceIndex: i)
                    let keyO = TranslationArchive.sliceKey(blockID: block.sourceBlockID, startOffset: s.startOffset, endOffset: s.endOffset)
                    return translations[keyI] ?? translations[keyO]
                }
                if !allSlicesForBlock.isEmpty && availableSliceBlocks.count == allSlicesForBlock.count {
                    let mergedText = availableSliceBlocks.map(\.text).joined(separator: " ")
                    var fullBlock = block
                    fullBlock.id = block.sourceBlockID
                    fullBlock.sourceBlockID = block.sourceBlockID
                    fullBlock.text = mergedText
                    fullBlock.spans = availableSliceBlocks.flatMap(\.spans)
                    translations[block.sourceBlockID] = fullBlock
                }
            } else {
                translations[block.sourceBlockID] = block
            }
        }
        documentState.translationsByLanguage[language] = translations
        session.documentState = documentState
        var chunk = session.chunks[index]
        chunk.translated = translatedBlocks.map(\.text).joined(separator: "\n\n")
        chunk.status = .done
        chunk.reviewDisposition = disposition
        chunk.qualityReport = report
        chunk.approved = disposition.isApproved
        session.chunks[index] = chunk
        session.registerTranslationLanguage(session.targetLang)
        session.activeTranslationLanguage = TranslationArchive.displayLanguage(session.targetLang)
    }
    private func markFailure(
        index: Int,
        code: String,
        message: String,
        issues: [QualityIssue] = [],
        preserveValid: Bool,
        needsReviewOnFailure: Bool = false
    ) {
        guard session.chunks.indices.contains(index) else { return }
        let chunk = session.chunks[index]
        let sourceHash = plan(for: index, in: session.documentState)?.sourceHash ?? ""
        let report = ChunkQualityReport(
            validatorVersion: DocumentTranslationContract.validatorVersion,
            errors: issues.isEmpty ? [QualityIssue(code: code, message: message)] : issues,
            warnings: [],
            attempts: max(1, chunk.qualityReport?.attempts ?? 1),
            sourceHash: sourceHash,
            outputHash: preserveValid ? chunk.qualityReport?.outputHash : nil
        )
        session.chunks[index].qualityReport = report
        if preserveValid {
            session.chunks[index].status = .done
            session.chunks[index].reviewDisposition = .needsReview
            session.chunks[index].approved = false
        } else {
            session.chunks[index].status = .error
            session.chunks[index].reviewDisposition = needsReviewOnFailure ? .needsReview : .failed
            session.chunks[index].approved = false
        }
    }

    private func hasReadyTranslation(at index: Int) -> Bool {
        guard session.chunks.indices.contains(index) else { return false }
        let chunk = session.chunks[index]
        guard let documentState = session.documentState,
              let plan = plan(for: index, in: documentState)
        else {
            return TranslationArchive.isUsableTranslationText(chunk.translated)
        }

        let byID = Dictionary(uniqueKeysWithValues: documentState.blocks.map { ($0.id, $0) })
        let deterministicOnly = plan.blockIDs.allSatisfy { id in
            guard let block = byID[id] else { return false }
            let slice = plan.blockSlices?.first(where: { $0.blockID == id })
            return DocumentTranslationRequest.isDeterministic(DocumentTranslationInputBlock(block: block, slice: slice))
        }
        let language = TranslationArchive.languageKey(session.targetLang)
        let stored = documentState.translationsByLanguage[language] ?? [:]
        if deterministicOnly {
            // Empty deterministic output is still a completed translation; it
            // is ready once every planned block has an archive entry.
            return plan.blockIDs.allSatisfy { id in
                if stored[id] != nil { return true }
                if let slice = plan.blockSlices?.first(where: { $0.blockID == id }) {
                    let allSlices = documentState.chunks.compactMap(\.blockSlices).flatMap { $0 }.filter { $0.blockID == id }.sorted { $0.startOffset < $1.startOffset }
                    let idx = allSlices.firstIndex(where: { $0.startOffset == slice.startOffset && $0.endOffset == slice.endOffset }) ?? 0
                    let keyIdx = TranslationArchive.sliceKey(blockID: id, sliceIndex: idx)
                    let keyOff = TranslationArchive.sliceKey(blockID: id, startOffset: slice.startOffset, endOffset: slice.endOffset)
                    if stored[keyIdx] != nil || stored[keyOff] != nil { return true }
                }
                return false
            }
        }

        guard TranslationArchive.isUsableTranslationText(chunk.translated) else { return false }
        if stored.isEmpty { return true }
        return plan.blockIDs.allSatisfy { id in
            guard let block = byID[id] else { return false }
            let slice = plan.blockSlices?.first(where: { $0.blockID == id })
            let inputBlock = DocumentTranslationInputBlock(block: block, slice: slice)
            if DocumentTranslationRequest.isDeterministic(inputBlock) {
                return true
            }
            if let slice {
                let allSlices = documentState.chunks.compactMap(\.blockSlices).flatMap { $0 }.filter { $0.blockID == id }.sorted { $0.startOffset < $1.startOffset }
                let idx = allSlices.firstIndex(where: { $0.startOffset == slice.startOffset && $0.endOffset == slice.endOffset }) ?? 0
                let keyIdx = TranslationArchive.sliceKey(blockID: id, sliceIndex: idx)
                let keyOff = TranslationArchive.sliceKey(blockID: id, startOffset: slice.startOffset, endOffset: slice.endOffset)
                if let entry = stored[keyIdx] ?? stored[keyOff], TranslationArchive.isUsableTranslationText(entry.text) {
                    return true
                }
            }
            return stored[id].map { TranslationArchive.isUsableTranslationText($0.text) } ?? false
        }
    }

    private func plan(for index: Int, in documentState: DocumentState?) -> DocumentChunkPlan? {
        guard let documentState else { return nil }
        if documentState.chunks.indices.contains(index) {
            let candidate = documentState.chunks[index]
            if session.chunks.indices.contains(index), case let .document(range) = session.chunks[index].sourceAnchor {
                if candidate.blockIDs.first == range.startBlockID && candidate.blockIDs.last == range.endBlockID {
                    return candidate
                }
            } else {
                return candidate
            }
        }
        if session.chunks.indices.contains(index), case let .document(range) = session.chunks[index].sourceAnchor {
            if let matched = documentState.chunks.first(where: {
                $0.blockIDs.first == range.startBlockID && $0.blockIDs.last == range.endBlockID
            }) {
                return matched
            }
        }
        return documentState.chunks.indices.contains(index) ? documentState.chunks[index] : nil
    }

    private func updateRollingMemory(from response: DocumentTranslationResponse, request: DocumentTranslationRequest) {
        var recent = rollingMemory.recentApprovedBlocks
        let sourceByID = Dictionary(uniqueKeysWithValues: request.blocks.map { ($0.id, $0.sourceText) })
        for block in response.blocks {
            recent.append(DocumentTranslationMemoryBlock(
                id: block.id,
                source: sourceByID[block.id] ?? "",
                target: block.text
            ))
        }
        rollingMemory.recentApprovedBlocks = Array(recent.suffix(2))
    }

    private func publishProgress(
        intent: DocumentTranslationExecutionIntent,
        currentIndex: Int?,
        message: String
    ) async {
        guard let progressHandler else { return }
        let total = session.chunks.count
        let completed = session.chunks.filter { $0.status == .done }.count
        let autoApproved = session.chunks.filter { $0.reviewDisposition == .autoApproved }.count
        let needsReview = session.chunks.filter { $0.reviewDisposition == .needsReview || $0.reviewDisposition == .pending && $0.status == .done }.count
        let failed = session.chunks.filter { $0.reviewDisposition == .failed }.count
        let fraction = total == 0 ? 1 : Double(completed + failed) / Double(total)
        await progressHandler(DocumentTranslationCoordinatorProgress(
            intent: intent,
            currentIndex: currentIndex,
            totalChunks: total,
            completedCount: completed,
            autoApprovedCount: autoApproved,
            needsReviewCount: needsReview,
            failedCount: failed,
            message: message,
            fraction: min(1, max(0, fraction))
        ))
    }

    private func save() async {
        guard let saveHandler else { return }
        await saveHandler(session)
    }

    private func waitIfPaused() async {
        while paused && !cancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private static func normalizedSession(_ value: SessionState) -> SessionState {
        var copy = value
        for index in copy.chunks.indices where copy.chunks[index].status == .processing {
            copy.chunks[index].status = .pending
            if copy.chunks[index].reviewDisposition == .failed {
                copy.chunks[index].reviewDisposition = .pending
            }
        }
        return copy
    }

    private static func initialMemory(for session: SessionState) -> DocumentTranslationMemory {
        guard let state = session.documentState else { return DocumentTranslationMemory() }
        let language = TranslationArchive.languageKey(session.targetLang)
        let stored = state.translationsByLanguage[language] ?? [:]
        let approved = stored.values
            .filter { $0.reviewDisposition.isApproved }
            .suffix(2)
            .map { DocumentTranslationMemoryBlock(id: $0.sourceBlockID, source: "", target: $0.text) }
        return DocumentTranslationMemory(
            glossary: session.documentState?.profile.projectGlossary ?? [],
            protectedTerms: session.documentState?.profile.protectedTerms.map(\.source) ?? [],
            recentApprovedBlocks: Array(approved),
            chapterContext: session.documentState?.metadata.title ?? ""
        )
    }

    private func stableHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.precomposedStringWithCanonicalMapping.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public enum DocumentTranslationCoordinatorError: LocalizedError, Equatable, Sendable {
    case notDocumentSession

    public var errorDescription: String? {
        switch self {
        case .notDocumentSession: "Document translation requires an active document session."
        }
    }
}
