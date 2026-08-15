import Foundation
import VaniScriptCore

public struct DocumentTranslationPrompt: Equatable, Sendable {
    public var system: String
    public var user: String
    public var request: DocumentTranslationRequest
    public var budget: TranslationPromptBudget?

    public init(
        system: String,
        user: String,
        request: DocumentTranslationRequest,
        budget: TranslationPromptBudget? = nil
    ) {
        self.system = system
        self.user = user
        self.request = request
        self.budget = budget
    }

    public var combinedText: String {
        "SYSTEM CONTRACT:\n\(system)\n\nUSER REQUEST:\n\(user)"
    }

    public var serializedCharacterCount: Int { combinedText.count }
}

public protocol DocumentTranslationProvider: Sendable {
    var id: String { get }
    var capabilities: TranslationModelCapabilities { get }
    func generate(prompt: DocumentTranslationPrompt) async throws -> String
}

public extension DocumentTranslationProvider {
    /// Adapters that know their model context can override this. Test and
    /// custom providers remain safe by using the conservative cloud profile.
    var capabilities: TranslationModelCapabilities {
        .cloudDefault
    }
}

/// A closure-backed adapter keeps provider calls deterministic and mockable in
/// tests while the production adapters below reuse the existing engines.
public struct DocumentTranslationProviderAdapter: DocumentTranslationProvider, Sendable {
    public let id: String
    public let capabilities: TranslationModelCapabilities
    private let generator: @Sendable (DocumentTranslationPrompt) async throws -> String

    public init(
        id: String = "mock",
        capabilities: TranslationModelCapabilities = .cloudDefault,
        generate: @escaping @Sendable (DocumentTranslationPrompt) async throws -> String
    ) {
        self.id = id
        self.capabilities = TranslationModelCapabilities(
            modelID: capabilities.modelID,
            contextWindowTokens: capabilities.contextWindowTokens,
            maxOutputTokens: capabilities.maxOutputTokens,
            supportsStructuredOutput: capabilities.supportsStructuredOutput,
            tokenizerAvailable: capabilities.tokenizerAvailable,
            fallbackCharactersPerToken: capabilities.fallbackCharactersPerToken,
            recommendedSoftSourceTokens: capabilities.recommendedSoftSourceTokens,
            recommendedHardSourceTokens: capabilities.recommendedHardSourceTokens
        )
        self.generator = generate
    }

    public func generate(prompt: DocumentTranslationPrompt) async throws -> String {
        try await generator(prompt)
    }
}


public struct DocumentTranslationEngineResult: Equatable, Sendable {
    public var response: DocumentTranslationResponse
    public var validation: DocumentTranslationValidationResult
    public var rawResponse: String
    public var attempts: Int

    public init(
        response: DocumentTranslationResponse,
        validation: DocumentTranslationValidationResult,
        rawResponse: String,
        attempts: Int = 1
    ) {
        self.response = response
        self.validation = validation
        self.rawResponse = rawResponse
        self.attempts = attempts
    }

    public var isValid: Bool { validation.isValid }
}

public enum DocumentTranslationEngineError: LocalizedError, Equatable, Sendable {
    case noProvider
    case emptyOutput
    case truncatedOutput
    case invalidOutput(String)
    case providerUnavailable(String)
    case providerFailure(String)
    case requestExceedsBudget(
        estimatedTokens: Int,
        reservedOutputTokens: Int,
        contextWindowTokens: Int,
        selectedSourceTokens: Int
    )

    public var errorDescription: String? {
        switch self {
        case .noProvider:
            "No document translation provider is configured."
        case .emptyOutput:
            "The document translation provider returned an empty response."
        case .truncatedOutput:
            "The document translation provider returned truncated JSON."
        case let .invalidOutput(detail):
            "The document translation provider returned invalid output: \(detail)"
        case let .providerUnavailable(detail):
            "Document translation provider is unavailable: \(detail)"
        case let .providerFailure(detail):
            "Document translation provider failed: \(detail)"
        case let .requestExceedsBudget(estimated, reservedOutput, contextWindow, selectedSource):
            "The selected document chunk is too large for this model before translation (\(estimated) input tokens plus \(reservedOutput) output tokens; model context is \(contextWindow) tokens; selected source is \(selectedSource) tokens). Choose a larger-context model or reduce the selected chunk."
        }
    }
}

public actor DocumentTranslationEngine {
    private let provider: any DocumentTranslationProvider
    private let validator: DocumentTranslationValidator
    private let encoder: JSONEncoder

    public init(
        provider: any DocumentTranslationProvider,
        validator: DocumentTranslationValidator = DocumentTranslationValidator()
    ) {
        self.provider = provider
        self.validator = validator
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    public var providerID: String { provider.id }

    public func translate(
        request: DocumentTranslationRequest,
        attempts: Int = 1,
        intent: String = "unknown",
        chunkIndex: Int? = nil
    ) async throws -> DocumentTranslationEngineResult {
        guard !request.blocks.isEmpty else {
            let error = DocumentTranslationEngineError.invalidOutput("The request contains no translatable blocks.")
            logDocumentTranslationEnd(
                request: request,
                intent: intent,
                chunkIndex: chunkIndex,
                prompt: nil,
                outputCharacters: 0,
                attempt: attempts,
                failureClass: "request"
            )
            throw error
        }

        // Empty and protected blocks are deterministic. A chunk containing
        // only those blocks completes locally and never fabricates provider
        // output or spends a provider call.
        if request.translatableBlocks.isEmpty {
            let response = reconstructedResponse(
                providerResponse: nil,
                request: request,
                providerBlockIDs: []
            )
            let validation = validator.validate(response: response, request: request)
            logDocumentTranslationEnd(
                request: request,
                intent: intent,
                chunkIndex: chunkIndex,
                prompt: nil,
                outputCharacters: 0,
                attempt: attempts,
                failureClass: validation.isValid ? nil : "validation",
                validationIssues: validation.errors
            )
            return DocumentTranslationEngineResult(
                response: response,
                validation: validation,
                rawResponse: "",
                attempts: max(1, attempts)
            )
        }

        let prompt: DocumentTranslationPrompt
        do {
            prompt = try makePrompt(request: request)
        } catch {
            logDocumentTranslationEnd(
                request: request,
                intent: intent,
                chunkIndex: chunkIndex,
                prompt: nil,
                outputCharacters: 0,
                attempt: attempts,
                failureClass: failureClass(for: error)
            )
            throw error
        }

        logDocumentTranslationStart(
            request: request,
            intent: intent,
            chunkIndex: chunkIndex,
            prompt: prompt,
            attempt: attempts
        )

        let raw: String
        do {
            raw = try await provider.generate(prompt: prompt)
        } catch is CancellationError {
            logDocumentTranslationEnd(
                request: request,
                intent: intent,
                chunkIndex: chunkIndex,
                prompt: prompt,
                outputCharacters: 0,
                attempt: attempts,
                failureClass: "cancellation"
            )
            throw CancellationError()
        } catch let error as DocumentTranslationEngineError {
            logDocumentTranslationEnd(
                request: request,
                intent: intent,
                chunkIndex: chunkIndex,
                prompt: prompt,
                outputCharacters: 0,
                attempt: attempts,
                failureClass: failureClass(for: error)
            )
            throw error
        } catch {
            let mapped = DocumentTranslationEngineError.providerFailure(safeProviderDetail(error))
            logDocumentTranslationEnd(
                request: request,
                intent: intent,
                chunkIndex: chunkIndex,
                prompt: prompt,
                outputCharacters: 0,
                attempt: attempts,
                failureClass: "provider"
            )
            throw mapped
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let error = DocumentTranslationEngineError.emptyOutput
            logDocumentTranslationEnd(
                request: request,
                intent: intent,
                chunkIndex: chunkIndex,
                prompt: prompt,
                outputCharacters: raw.count,
                attempt: attempts,
                failureClass: "empty-output"
            )
            throw error
        }
        guard !looksTruncated(trimmed) else {
            let error = DocumentTranslationEngineError.truncatedOutput
            logDocumentTranslationEnd(
                request: request,
                intent: intent,
                chunkIndex: chunkIndex,
                prompt: prompt,
                outputCharacters: raw.count,
                attempt: attempts,
                failureClass: "truncated-json"
            )
            throw error
        }

        let providerResponse: DocumentTranslationResponse
        do {
            providerResponse = try DocumentTranslationResponse.decodeStrict(Data(trimmed.utf8))
        } catch let error as DocumentTranslationContractError {
            let mapped = DocumentTranslationEngineError.invalidOutput(error.localizedDescription)
            logDocumentTranslationEnd(
                request: request,
                intent: intent,
                chunkIndex: chunkIndex,
                prompt: prompt,
                outputCharacters: raw.count,
                attempt: attempts,
                failureClass: "invalid-json"
            )
            throw mapped
        } catch {
            let mapped = DocumentTranslationEngineError.invalidOutput("The response must be one JSON object with schema, chunkId, and blocks.")
            logDocumentTranslationEnd(
                request: request,
                intent: intent,
                chunkIndex: chunkIndex,
                prompt: prompt,
                outputCharacters: raw.count,
                attempt: attempts,
                failureClass: "invalid-json"
            )
            throw mapped
        }

        // The provider response is a subset; validation is deliberately
        // performed only after deterministic blocks are restored and repaired
        // blocks are merged into the complete original candidate.
        let response = reconstructedResponse(
            providerResponse: providerResponse,
            request: request,
            providerBlockIDs: prompt.request.expectedBlockIDs
        )
        let validation = validator.validate(response: response, request: request)
        logDocumentTranslationEnd(
            request: request,
            intent: intent,
            chunkIndex: chunkIndex,
            prompt: prompt,
            outputCharacters: raw.count,
            attempt: attempts,
            failureClass: validation.isValid ? nil : "validation",
            validationIssues: validation.errors
        )
        return DocumentTranslationEngineResult(
            response: response,
            validation: validation,
            rawResponse: raw,
            attempts: max(1, attempts)
        )
    }

    public func repairableBlockIDs(
        request: DocumentTranslationRequest,
        result: DocumentTranslationEngineResult
    ) -> [String] {
        invalidTranslatableBlockIDs(result: result, request: request)
    }

    public func translate(
        request: DocumentTranslationRequest,
        repairFor result: DocumentTranslationEngineResult,
        attempts: Int,
        intent: String = "unknown",
        chunkIndex: Int? = nil
    ) async throws -> DocumentTranslationEngineResult {
        let ids = invalidTranslatableBlockIDs(result: result, request: request)
        guard !ids.isEmpty else {
            // Structural errors with no invalid translatable block cannot be
            // repaired by a provider subset. Returning the prior candidate
            // keeps the coordinator from inventing a source translation.
            return result
        }
        let repair = DocumentTranslationRepairRequest(
            blockIDs: ids,
            sourceBlocks: request.blocks.filter { ids.contains($0.id) },
            previousCandidate: result.response.blocks,
            issues: result.validation.errors
        )
        var repairedRequest = request
        repairedRequest.repair = repair
        return try await translate(
            request: repairedRequest,
            attempts: attempts,
            intent: intent,
            chunkIndex: chunkIndex
        )
    }

    private func invalidTranslatableBlockIDs(
        result: DocumentTranslationEngineResult,
        request: DocumentTranslationRequest
    ) -> [String] {
        let expected = request.translatableBlockIDs
        let expectedSet = Set(expected)
        guard !expected.isEmpty else { return [] }

        var invalid = Set<String>()
        for issue in result.validation.errors {
            if let blockID = issue.blockID, expectedSet.contains(blockID) {
                invalid.insert(blockID)
            }
        }

        let actual = result.response.blockIDs.filter { expectedSet.contains($0) }
        if result.validation.errors.contains(where: { $0.code == "blockOrder" }),
           actual != expected
        {
            invalid.formUnion(expected)
        }
        for id in expected where !actual.contains(id) {
            if result.validation.errors.contains(where: { $0.code == "missingBlockID" && $0.blockID == id }) {
                invalid.insert(id)
            }
        }

        // Preserve the original plan order regardless of the order in which
        // validation discovered issues.
        return expected.filter { invalid.contains($0) }
    }

    private func reconstructedResponse(
        providerResponse: DocumentTranslationResponse?,
        request: DocumentTranslationRequest,
        providerBlockIDs: [String]
    ) -> DocumentTranslationResponse {
        let deterministicInputs = request.deterministicBlocks
        let deterministicIDs = Set(deterministicInputs.map(\.id))
        let previousCandidate = request.repair?.previousCandidate ?? []
        var working = previousCandidate.isEmpty
            ? (providerResponse?.blocks ?? [])
            : previousCandidate

        if let providerResponse {
            let providerIDs = Set(providerBlockIDs)
            if previousCandidate.isEmpty {
                working = providerResponse.blocks
            } else {
                for output in providerResponse.blocks {
                    if providerIDs.contains(output.id),
                       let index = working.firstIndex(where: { $0.id == output.id })
                    {
                        working[index] = output
                    } else if !deterministicIDs.contains(output.id) {
                        // Keep malformed/extra provider blocks visible to the
                        // full validator rather than silently dropping them.
                        working.append(output)
                    }
                }
            }
        }

        let nonDeterministicActualIDs = providerResponse?.blockIDs.filter { !deterministicIDs.contains($0) } ?? []
        let providerOrderIsValid = providerResponse == nil
            || nonDeterministicActualIDs == providerBlockIDs
            || providerResponse?.blockIDs == request.expectedBlockIDs

        let responseBlocks: [DocumentTranslationOutputBlock]
        if providerOrderIsValid {
            var used = Set<Int>()
            var ordered: [DocumentTranslationOutputBlock] = []
            for input in request.blocks {
                if DocumentTranslationRequest.isDeterministic(input) {
                    if let index = working.indices.first(where: {
                        !used.contains($0) && working[$0].id == input.id
                    }) {
                        used.insert(index)
                        let candidate = working[index]
                        if isDeterministicSafe(candidate, for: input) {
                            ordered.append(candidate)
                        } else {
                            ordered.append(deterministicOutput(for: input))
                        }
                    } else {
                        ordered.append(deterministicOutput(for: input))
                    }
                } else if let index = working.indices.first(where: {
                    !used.contains($0) && working[$0].id == input.id
                }) {
                    used.insert(index)
                    ordered.append(working[index])
                }
            }
            ordered.append(contentsOf: working.enumerated().compactMap { index, block in
                if used.contains(index) || deterministicIDs.contains(block.id) {
                    return nil
                }
                return block
            })
            responseBlocks = ordered
        } else {
            var malformed = working
            var firstDeterministicIndices: [String: Int] = [:]
            for (index, block) in malformed.enumerated() {
                if deterministicIDs.contains(block.id) {
                    if firstDeterministicIndices[block.id] == nil {
                        firstDeterministicIndices[block.id] = index
                    }
                }
            }
            for input in deterministicInputs {
                if let firstIndex = firstDeterministicIndices[input.id] {
                    malformed[firstIndex] = deterministicOutput(for: input)
                } else {
                    malformed.append(deterministicOutput(for: input))
                }
            }
            var seenDeterministic = Set<String>()
            var deduplicatedMalformed: [DocumentTranslationOutputBlock] = []
            for block in malformed {
                if deterministicIDs.contains(block.id) {
                    if seenDeterministic.insert(block.id).inserted {
                        deduplicatedMalformed.append(block)
                    }
                } else {
                    deduplicatedMalformed.append(block)
                }
            }
            responseBlocks = deduplicatedMalformed
        }

        return DocumentTranslationResponse(
            schema: providerResponse?.schema ?? request.schema,
            chunkId: providerResponse?.chunkId ?? request.chunkId,
            blocks: responseBlocks
        )
    }

    private func isDeterministicSafe(
        _ output: DocumentTranslationOutputBlock,
        for input: DocumentTranslationInputBlock
    ) -> Bool {
        if input.translationPolicy == .protect {
            guard output.spans.count == input.spans.count else { return false }
            return zip(output.spans, input.spans).allSatisfy { outSpan, inSpan in
                outSpan.id == inSpan.id && outSpan.style == inSpan.style && outSpan.text == inSpan.text
            }
        }
        if input.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return output.spans.isEmpty || output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    private func deterministicOutput(
        for input: DocumentTranslationInputBlock
    ) -> DocumentTranslationOutputBlock {
        if input.translationPolicy == .protect {
            return DocumentTranslationOutputBlock(
                id: input.id,
                spans: input.spans.map {
                    DocumentTranslationOutputSpan(id: $0.id, style: $0.style, text: $0.text)
                }
            )
        }
        return DocumentTranslationOutputBlock(id: input.id, spans: [])
    }

    private func makePrompt(request: DocumentTranslationRequest) throws -> DocumentTranslationPrompt {
        guard provider.capabilities.supportsStructuredOutput else {
            throw DocumentTranslationEngineError.providerUnavailable(
                "The selected model does not support structured JSON document translation."
            )
        }

        var before = request.readOnlyContextBefore
        var after = request.readOnlyContextAfter
        var includeMemory = request.memory != nil
        let planner = TranslationBudgetPlanner(capabilities: provider.capabilities)

        while true {
            let candidate = compactRequest(
                request,
                contextBefore: before,
                contextAfter: after,
                includeMemory: includeMemory
            )
            let rendered = try renderPrompt(for: candidate)
            let combined = "SYSTEM CONTRACT:\n\(rendered.system)\n\nUSER REQUEST:\n\(rendered.user)"
            let sourceText = candidate.blocks.map(\.sourceText).joined(separator: "\n\n")
            let budget = planner.promptBudget(for: combined, sourceText: sourceText)
            if budget.fits {
                return DocumentTranslationPrompt(
                    system: rendered.system,
                    user: rendered.user,
                    request: candidate,
                    budget: budget
                )
            }

            // Remove optional material in a deterministic order. Selected
            // blocks and relevant terminology are never silently dropped.
            if includeMemory {
                includeMemory = false
                continue
            }
            if !before.isEmpty {
                before.removeFirst()
                continue
            }
            if !after.isEmpty {
                after.removeLast()
                continue
            }

            throw DocumentTranslationEngineError.requestExceedsBudget(
                estimatedTokens: budget.estimatedPromptTokens,
                reservedOutputTokens: budget.reservedOutputTokens,
                contextWindowTokens: budget.contextWindowTokens,
                selectedSourceTokens: budget.sourceTokenEstimate
            )
        }
    }

    private func compactRequest(
        _ original: DocumentTranslationRequest,
        contextBefore: [DocumentTranslationContextBlock],
        contextAfter: [DocumentTranslationContextBlock],
        includeMemory: Bool
    ) -> DocumentTranslationRequest {
        var candidate = original
        let providerIDs: Set<String>
        if let repair = candidate.repair {
            providerIDs = Set(repair.blockIDs)
        } else {
            providerIDs = Set(candidate.translatableBlockIDs)
        }
        candidate.blocks = candidate.blocks.filter { providerIDs.contains($0.id) }
        let context = contextBefore + contextAfter
        let relevantText = (
            candidate.blocks.map(\.sourceText)
                + context.map(\.text)
        ).joined(separator: "\n\n")
        let allGlossary = candidate.profile.projectGlossary
            + (candidate.memory?.glossary ?? [])
        let glossary = relevantGlossaryEntries(allGlossary, in: relevantText)
        var profile = candidate.profile
        profile.projectGlossary = glossary
        profile.protectedTerms = relevantProtectedTerms(
            profile.protectedTerms + (candidate.memory?.protectedTerms ?? []).map {
                ProtectedTerm(source: $0)
            },
            in: relevantText
        )
        // Translator notes are optional wire context. The complete profile
        // remains persisted in DocumentState; only this provider copy is
        // compacted.
        profile.translatorNotes = ""
        candidate.profile = profile
        candidate.protectedTokens = relevantProtectedTokens(
            candidate.protectedTokens
                + profile.protectedTerms.flatMap { [$0.source, $0.translation] },
            in: relevantText
        )
        candidate.knownStyleIDs = Array(Set(candidate.blocks.flatMap(\.styleIDs))).sorted()
        candidate.readOnlyContextBefore = contextBefore
        candidate.readOnlyContextAfter = contextAfter

        if includeMemory, let memory = candidate.memory {
            candidate.memory = DocumentTranslationMemory(
                glossary: [],
                protectedTerms: [],
                voiceRules: [],
                recentApprovedBlocks: memory.recentApprovedBlocks.suffix(2).map {
                    // Approved target text can help preserve voice, but source
                    // manuscript text from unrelated blocks is never sent.
                    DocumentTranslationMemoryBlock(id: $0.id, source: "", target: $0.target)
                },
                chapterContext: memory.chapterContext,
                modelVersion: memory.modelVersion,
                promptVersion: memory.promptVersion
            )
        } else {
            candidate.memory = nil
        }

        if let repair = candidate.repair {
            let allowedIDs = Set(candidate.expectedBlockIDs)
            candidate.repair = DocumentTranslationRepairRequest(
                blockIDs: repair.blockIDs.filter { allowedIDs.contains($0) },
                sourceBlocks: repair.sourceBlocks.filter { allowedIDs.contains($0.id) },
                previousCandidate: repair.previousCandidate.filter { allowedIDs.contains($0.id) },
                issues: repair.issues
            )
        }
        return candidate
    }

    private func renderPrompt(
        for request: DocumentTranslationRequest
    ) throws -> (system: String, user: String) {
        let requestData = try encoder.encode(request)
        let requestJSON = String(decoding: requestData, as: UTF8.self)
        let template = DocumentTranslationContract.canonicalResponseTemplate(
            chunkID: request.chunkId,
            blockIDs: request.expectedBlockIDs,
            styleIDs: Array(request.expectedStyleIDs).sorted()
        )
        let requiredIDs = try encodedArray(request.expectedBlockIDs)
        let allowedStyles = try encodedArray(Array(request.expectedStyleIDs).sorted())
        let variables = [
            "targetLang": request.targetLanguage,
            "requestJson": requestJSON,
            "responseTemplate": template,
            "chunkId": request.chunkId,
            "requiredBlockIDs": requiredIDs,
            "allowedStyleIDs": allowedStyles
        ]
        let system = DefaultPrompts.render(
            id: "documentLiteraryTranslationSystem",
            promptPresets: [:],
            variables: variables
        )
        let userID = request.repair == nil
            ? "documentLiteraryTranslationUser"
            : "documentTranslationRepair"
        let userVariables: [String: String]
        if request.repair == nil {
            userVariables = variables
        } else {
            let issues = request.repair?.issues
                .map { "[\($0.code)] \($0.message)" }
                .joined(separator: "\n") ?? ""
            userVariables = variables.merging(
                ["issues": issues],
                uniquingKeysWith: { _, replacement in replacement }
            )
        }
        return (
            system,
            DefaultPrompts.render(
                id: userID,
                promptPresets: [:],
                variables: userVariables
            )
        )
    }

    private func encodedArray(_ values: [String]) throws -> String {
        let data = try JSONEncoder().encode(values)
        return String(decoding: data, as: UTF8.self)
    }

    private func relevantGlossaryEntries(
        _ entries: [GlossaryEntry],
        in text: String
    ) -> [GlossaryEntry] {
        let normalizedText = normalized(text)
        var seenIDs = Set<String>()
        var seenSources = Set<String>()
        return entries.filter { entry in
            let id = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = normalized(entry.source)
            guard !seenIDs.contains(id), !seenSources.contains(source) else { return false }
            let terms = [entry.source] + entry.variants
            guard terms.contains(where: { term in
                let normalizedTerm = normalized(term)
                return !normalizedTerm.isEmpty && normalizedText.contains(normalizedTerm)
            }) else {
                return false
            }
            seenIDs.insert(id)
            if !source.isEmpty { seenSources.insert(source) }
            return true
        }
    }

    private func relevantProtectedTerms(
        _ terms: [ProtectedTerm],
        in text: String
    ) -> [ProtectedTerm] {
        let normalizedText = normalized(text)
        var seen = Set<String>()
        return terms.filter { term in
            let key = normalized(term.source)
            guard !key.isEmpty, !seen.contains(key) else { return false }
            let matches = [term.source, term.translation].contains {
                let value = normalized($0)
                return !value.isEmpty && normalizedText.contains(value)
            }
            guard matches else { return false }
            seen.insert(key)
            return true
        }
    }

    private func relevantProtectedTokens(_ tokens: [String], in text: String) -> [String] {
        let normalizedText = normalized(text)
        var seen = Set<String>()
        return tokens.filter { token in
            let value = normalized(token)
            guard !value.isEmpty, !seen.contains(value), normalizedText.contains(value) else {
                return false
            }
            seen.insert(value)
            return true
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private func logDocumentTranslationStart(
        request: DocumentTranslationRequest,
        intent: String,
        chunkIndex: Int?,
        prompt: DocumentTranslationPrompt,
        attempt: Int
    ) {
        let budget = prompt.budget
        AppLogger.shared.info(
            "Document translation start provider=\(safeIdentifier(provider.id)) " +
            "model=\(safeIdentifier(provider.capabilities.modelID)) " +
            "intent=\(safeIdentifier(intent)) " +
            "chunkIndex=\(chunkIndex.map { String($0) } ?? "unknown") " +
            "plannedBlockCount=\(request.blocks.count) " +
            "sourceCharacters=\(request.blocks.reduce(0) { $0 + $1.sourceText.count }) " +
            "promptCharacters=\(budget?.serializedPromptCharacters ?? prompt.serializedCharacterCount) " +
            "promptTokenEstimate=\(budget?.estimatedPromptTokens ?? 0) " +
            "outputCharacters=0 attempt=\(max(1, attempt)) failureClass=none"
        )
    }

    private func logDocumentTranslationEnd(
        request: DocumentTranslationRequest,
        intent: String,
        chunkIndex: Int?,
        prompt: DocumentTranslationPrompt?,
        outputCharacters: Int,
        attempt: Int,
        failureClass: String?,
        validationIssues: [QualityIssue] = []
    ) {
        let budget = prompt?.budget
        var line = "Document translation end provider=\(safeIdentifier(provider.id)) " +
            "model=\(safeIdentifier(provider.capabilities.modelID)) " +
            "intent=\(safeIdentifier(intent)) " +
            "chunkIndex=\(chunkIndex.map { String($0) } ?? "unknown") " +
            "plannedBlockCount=\(request.blocks.count) " +
            "sourceCharacters=\(request.blocks.reduce(0) { $0 + $1.sourceText.count }) " +
            "promptCharacters=\(budget?.serializedPromptCharacters ?? 0) " +
            "promptTokenEstimate=\(budget?.estimatedPromptTokens ?? 0) " +
            "outputCharacters=\(max(0, outputCharacters)) attempt=\(max(1, attempt)) " +
            "failureClass=\(failureClass ?? "none")"
        if failureClass == "validation", !validationIssues.isEmpty {
            let formatted = validationIssues.map { issue in
                if let blockID = issue.blockID, !blockID.isEmpty {
                    return "\(safeIdentifier(issue.code)):\(safeIdentifier(blockID))"
                }
                return safeIdentifier(issue.code)
            }.joined(separator: ",")
            line += " validationIssues=\(formatted)"
        }
        AppLogger.shared.info(line)
    }

    private func safeIdentifier(_ value: String) -> String {
        let safe = value.map { character in
            character.isLetter || character.isNumber || "-_./:".contains(character)
                ? String(character)
                : "-"
        }.joined()
        let trimmed = safe.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((trimmed.isEmpty ? "unknown" : trimmed).prefix(96))
    }

    private func failureClass(for error: Error) -> String {
        guard let error = error as? DocumentTranslationEngineError else {
            return "provider"
        }
        switch error {
        case .emptyOutput:
            return "empty-output"
        case .truncatedOutput:
            return "truncated-json"
        case .invalidOutput:
            return "invalid-json"
        case .providerUnavailable:
            return "provider-unavailable"
        case .providerFailure:
            return "provider"
        case .requestExceedsBudget:
            return "budget"
        case .noProvider:
            return "provider-unavailable"
        }
    }

    private func safeProviderDetail(_ error: Error) -> String {
        let description = error.localizedDescription
        if description.localizedCaseInsensitiveContains("raw response")
            || description.localizedCaseInsensitiveContains("response preview")
        {
            return "The provider returned an unusable response."
        }
        if let httpRange = description.range(of: "HTTP", options: .caseInsensitive) {
            let statusAndProvider = description[httpRange.lowerBound...]
                .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
                .first
            if let statusAndProvider, !statusAndProvider.isEmpty {
                return String(statusAndProvider)
            }
        }
        return "The selected provider could not complete the request."
    }

    private func looksTruncated(_ value: String) -> Bool {
        if value.contains("```") { return false } // parser reports the contract violation
        let openBraces = value.filter { $0 == "{" }.count
        let closeBraces = value.filter { $0 == "}" }.count
        let openBrackets = value.filter { $0 == "[" }.count
        let closeBrackets = value.filter { $0 == "]" }.count
        return (openBraces > closeBraces || openBrackets > closeBrackets)
            || value.hasSuffix(":")
            || value.hasSuffix(",")
    }

    public static func request(
        for plan: DocumentChunkPlan,
        in documentState: DocumentState,
        sourceLanguage: String,
        targetLanguage: String,
        memory: DocumentTranslationMemory? = nil
    ) -> DocumentTranslationRequest {
        let byID = Dictionary(uniqueKeysWithValues: documentState.blocks.map { ($0.id, $0) })
        let slicesByBlockID: [String: DocumentBlockSlice]
        if let slices = plan.blockSlices, !slices.isEmpty {
            slicesByBlockID = Dictionary(slices.map { ($0.blockID, $0) }, uniquingKeysWith: { first, _ in first })
        } else {
            slicesByBlockID = [:]
        }
        let requestedBlocks: [DocumentTranslationInputBlock] = plan.blockIDs.compactMap { id in
            guard let block = byID[id] else { return nil }
            let slice = slicesByBlockID[id]
            return DocumentTranslationInputBlock(block: block, slice: slice)
        }
        let before = plan.contextBeforeBlockIDs.compactMap { id -> DocumentTranslationContextBlock? in
            guard let block = byID[id] else { return nil }
            return DocumentTranslationContextBlock(
                id: id,
                text: block.spans.map(\.text).joined(),
                style: block.styleID,
                isReadOnly: true
            )
        }
        let after = plan.contextAfterBlockIDs.compactMap { id -> DocumentTranslationContextBlock? in
            guard let block = byID[id] else { return nil }
            return DocumentTranslationContextBlock(
                id: id,
                text: block.spans.map(\.text).joined(),
                style: block.styleID,
                isReadOnly: true
            )
        }
        let sourceAndContextText = (
            requestedBlocks.map(\.sourceText)
                + before.map(\.text)
                + after.map(\.text)
        ).joined(separator: "\n\n")
        let normalizedText = sourceAndContextText
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var seenGlossaryIDs = Set<String>()
        var seenGlossarySources = Set<String>()
        let filteredGlossary = documentState.profile.projectGlossary.filter { entry in
            let id = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = entry.source
                .precomposedStringWithCanonicalMapping
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard !seenGlossaryIDs.contains(id), !seenGlossarySources.contains(source) else {
                return false
            }
            let relevant = ([entry.source] + entry.variants).contains { term in
                let normalizedTerm = term
                    .precomposedStringWithCanonicalMapping
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                return !normalizedTerm.isEmpty && normalizedText.contains(normalizedTerm)
            }
            guard relevant else { return false }
            seenGlossaryIDs.insert(id)
            if !source.isEmpty { seenGlossarySources.insert(source) }
            return true
        }
        var compactProfile = documentState.profile
        compactProfile.projectGlossary = filteredGlossary
        compactProfile.translatorNotes = ""
        let filteredProtectedTerms = documentState.profile.protectedTerms.filter { term in
            let source = term.source
                .precomposedStringWithCanonicalMapping
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let translation = term.translation
                .precomposedStringWithCanonicalMapping
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return (!source.isEmpty && normalizedText.contains(source))
                || (!translation.isEmpty && normalizedText.contains(translation))
        }
        compactProfile.protectedTerms = filteredProtectedTerms
        let protectedTerms = filteredProtectedTerms
            .flatMap { [$0.source, $0.translation] }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let compactMemory = memory.map {
            DocumentTranslationMemory(
                glossary: [],
                protectedTerms: [],
                voiceRules: [],
                recentApprovedBlocks: $0.recentApprovedBlocks.suffix(2).map {
                    DocumentTranslationMemoryBlock(id: $0.id, source: "", target: $0.target)
                },
                chapterContext: $0.chapterContext,
                modelVersion: $0.modelVersion,
                promptVersion: $0.promptVersion
            )
        }
        return DocumentTranslationRequest(
            chunkId: plan.id,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            profile: compactProfile,
            protectedTokens: protectedTerms,
            knownStyleIDs: Array(Set(requestedBlocks.flatMap(\.styleIDs))).sorted(),
            readOnlyContextBefore: before,
            readOnlyContextAfter: after,
            blocks: requestedBlocks,
            memory: compactMemory
        )
    }
}

private struct CloudDocumentTranslationProvider: DocumentTranslationProvider {
    let provider: ActiveCloudTranslationProvider
    let engine: CloudTextTranslationEngine

    var id: String { provider.id }
    var capabilities: TranslationModelCapabilities {
        TranslationModelCapabilities(
            modelID: provider.model,
            contextWindowTokens: TranslationModelCapabilities.cloudDefault.contextWindowTokens,
            maxOutputTokens: TranslationModelCapabilities.cloudDefault.maxOutputTokens,
            supportsStructuredOutput: true
        )
    }

    func generate(prompt: DocumentTranslationPrompt) async throws -> String {
        try await engine.translateDocument(
            prompt: prompt.combinedText,
            provider: provider,
            maxOutputTokens: TranslationModelCapabilities.cloudDefault.maxOutputTokens
        )
    }
}

private struct MLXDocumentTranslationProvider: DocumentTranslationProvider {
    let model: ActiveMLXModel
    let engine: MLXTextGenerationEngine

    var id: String { model.id }
    var capabilities: TranslationModelCapabilities {
        TranslationModelCapabilities(
            modelID: model.id,
            contextWindowTokens: TranslationModelCapabilities.localDefault.contextWindowTokens,
            maxOutputTokens: TranslationModelCapabilities.localDefault.maxOutputTokens,
            supportsStructuredOutput: true
        )
    }

    func generate(prompt: DocumentTranslationPrompt) async throws -> String {
        try await engine.generateDocumentTranslation(
            prompt: prompt.combinedText,
            model: model,
            sourceLength: prompt.request.blocks.reduce(0) { $0 + $1.sourceText.count },
            maxTokens: prompt.budget?.reservedOutputTokens
        )
    }
}

extension DocumentTranslationEngine {
    static func live(
        settings: AppSettings,
        providerID: String,
        cloudEngine: CloudTextTranslationEngine = CloudTextTranslationEngine(),
        localEngine: MLXTextGenerationEngine = MLXTextGenerationEngine()
    ) throws -> DocumentTranslationEngine {
        if let provider = ActiveCloudTranslationProvider.resolve(settings: settings, providerID: providerID) {
            return DocumentTranslationEngine(provider: CloudDocumentTranslationProvider(provider: provider, engine: cloudEngine))
        }
        guard let model = NativeModelCatalog.activeMLXModel(settings: settings, providerID: providerID) else {
            throw DocumentTranslationEngineError.providerUnavailable(providerID)
        }
        return DocumentTranslationEngine(provider: MLXDocumentTranslationProvider(model: model, engine: localEngine))
    }
}
