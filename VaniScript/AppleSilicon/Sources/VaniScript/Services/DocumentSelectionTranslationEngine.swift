import CryptoKit
import Foundation
import VaniScriptCore


public struct DocumentSelectionTranslationPrompt: Equatable, Sendable {
    public let request: DocumentSelectionTranslationRequest
    public let renderedText: String

    public init(request: DocumentSelectionTranslationRequest) {
        self.request = request
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let requestJSON = (try? encoder.encode(request)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        self.renderedText = """
        SYSTEM CONTRACT:
        Translate only the selected target fragment. Return exactly one JSON object and no markdown, commentary, or additional fields.
        The response schema is \(DocumentSelectionTranslationContract.schema). It must contain schema, operationId, and replacementText only.
        Never return block IDs, span IDs, style, colour, policy, offsets, or surrounding target text.

        USER REQUEST:
        \(requestJSON)
        """
    }
}

public protocol DocumentSelectionTranslationProvider: Sendable {
    var id: String { get }
    func generate(prompt: DocumentSelectionTranslationPrompt) async throws -> String
}

/// Closure-backed provider used by deterministic tests and custom app adapters.
public struct DocumentSelectionTranslationProviderAdapter: DocumentSelectionTranslationProvider, Sendable {
    public let id: String
    private let generator: @Sendable (DocumentSelectionTranslationPrompt) async throws -> String

    public init(
        id: String = "mock",
        generate: @escaping @Sendable (DocumentSelectionTranslationPrompt) async throws -> String
    ) {
        self.id = id
        self.generator = generate
    }

    public func generate(prompt: DocumentSelectionTranslationPrompt) async throws -> String {
        try await generator(prompt)
    }
}

public struct DocumentSelectionTranslationOutcome: Equatable, Sendable {
    public let operationID: String
    public let providerID: String
    public let blockID: String
    public let replacementUTF16Length: Int
    public let warningCodes: [String]

    public init(
        operationID: String,
        providerID: String,
        blockID: String,
        replacementUTF16Length: Int,
        warningCodes: [String] = []
    ) {
        self.operationID = operationID
        self.providerID = providerID
        self.blockID = blockID
        self.replacementUTF16Length = replacementUTF16Length
        self.warningCodes = warningCodes
    }
}

public enum DocumentSelectionTranslationEngineError: LocalizedError, Equatable, Sendable {
    case unsupportedSide
    case emptySelection
    case crossBlockSelection
    case missingSourceBlock(String)
    case missingTargetBlock(String)
    case missingTargetHash(String)
    case selectionChanged(String)
    case mixedFormatting
    case providerUnavailable(String)
    case providerFailure(String)
    case invalidResponse(String)
    case validationFailed([String])
    case staleResponse(String)
    case mutationFailure

    public var errorDescription: String? {
        switch self {
        case .unsupportedSide:
            "Retranslate Selection with AI is available only in the translated document pane."
        case .emptySelection:
            "Select text inside one document block before asking AI to retranslate it."
        case .crossBlockSelection:
            "Select text inside one document block; cross-block AI retranslation is disabled."
        case .missingSourceBlock:
            "The trusted source block for this selection is unavailable."
        case .missingTargetBlock:
            "The translated block for this selection is unavailable."
        case .missingTargetHash:
            "The selection does not have a current block revision; no replacement was applied."
        case .selectionChanged:
            "The selected text changed before the AI request could be applied."
        case .mixedFormatting:
            "This selection contains mixed formatting that cannot be inherited safely; review it manually."
        case .providerUnavailable:
            "The selected editing provider is unavailable. Check its configuration and try again."
        case .providerFailure:
            "The selected editing provider failed. The original selection was preserved."
        case .invalidResponse:
            "The AI response did not match the required selection translation format."
        case .validationFailed:
            "The AI response failed local validation. The original selection was preserved."
        case .staleResponse:
            "Text changed while AI was working — review suggestion; the newer edit was not overwritten."
        case .mutationFailure:
            "The validated AI replacement could not be applied. The original selection was preserved."
        }
    }
}

/// Builds, validates, stale-checks, and applies one target selection replacement.
///
/// The provider receives only structural context. Application of the returned text
/// is deferred until the caller's canonical DocumentState mutation callback runs.
public struct DocumentSelectionTranslationEngine: Sendable {
    private let provider: any DocumentSelectionTranslationProvider
    private let validator: DocumentSelectionTranslationValidator

    public init(
        provider: any DocumentSelectionTranslationProvider,
        validator: DocumentSelectionTranslationValidator = DocumentSelectionTranslationValidator()
    ) {
        self.provider = provider
        self.validator = validator
    }

    public var providerID: String { provider.id }

    public static func isEligible(_ snapshot: DocumentTextSelectionSnapshot) -> Bool {
        guard snapshot.side == .translation,
              !snapshot.selectedText.isEmpty,
              !snapshot.fragments.isEmpty
        else { return false }
        return Set(snapshot.fragments.map(\.blockID)).count == 1
    }

    /// Builds a request without performing a provider call. Resolution is based
    /// exclusively on private span/block identity carried by the snapshot.
    public func makeRequest(
        snapshot: DocumentTextSelectionSnapshot,
        sourceBlocks: [DocumentBlock],
        targetBlocks: [TranslatedBlock],
        profile: DocumentTranslationProfile,
        targetLanguage: String
    ) throws -> DocumentSelectionTranslationRequest {
        guard snapshot.side == .translation else { throw DocumentSelectionTranslationEngineError.unsupportedSide }
        guard !snapshot.selectedText.isEmpty, !snapshot.fragments.isEmpty else {
            throw DocumentSelectionTranslationEngineError.emptySelection
        }
        let blockIDs = Set(snapshot.fragments.map(\.blockID))
        guard blockIDs.count == 1, let blockID = blockIDs.first else {
            throw DocumentSelectionTranslationEngineError.crossBlockSelection
        }
        guard let sourceBlock = sourceBlocks.first(where: { $0.id == blockID }) else {
            throw DocumentSelectionTranslationEngineError.missingSourceBlock(blockID)
        }
        guard let targetBlock = targetBlocks.first(where: { $0.sourceBlockID == blockID || $0.id == blockID }) else {
            throw DocumentSelectionTranslationEngineError.missingTargetBlock(blockID)
        }

        let targetSpans = resolvedTargetSpans(targetBlock)
        let ranges = try selectionRanges(snapshot: snapshot, targetSpans: targetSpans, blockID: blockID)
        let currentSelectedText = try selectedText(for: ranges, in: targetSpans)
        guard currentSelectedText == snapshot.selectedText else {
            throw DocumentSelectionTranslationEngineError.selectionChanged(blockID)
        }

        let fingerprints = snapshot.fragments.map(FormattingFingerprint.init(fragment:))
        if Set(fingerprints).count > 1 {
            throw DocumentSelectionTranslationEngineError.mixedFormatting
        }

        let sourceByID = Dictionary(uniqueKeysWithValues: sourceBlock.spans.map { ($0.id, $0) })
        let mappedCandidates: [DocumentSelectionSourceSpan] = snapshot.fragments.compactMap { fragment in
            guard let spanID = fragment.spanID, let sourceSpan = sourceByID[spanID] else { return nil }
            return DocumentSelectionSourceSpan(id: sourceSpan.id, text: sourceSpan.text, styleKey: sourceSpan.styleKey)
        }
        let mappedSourceSpans = mappedCandidates.uniquedByID()
        let sourceText = sourceBlock.spans.map(\.text).joined()
        let sourceAlignment: DocumentSelectionSourceAlignment
        let sourceContext: String
        if mappedCandidates.count == snapshot.fragments.count {
            sourceAlignment = .mappedSpans
            sourceContext = mappedSourceSpans.map(\.text).joined()
        } else {
            sourceAlignment = .blockContext
            sourceContext = sourceText
        }


        let targetText = targetSpans.map(\.text).joined()
        let absoluteRange = absoluteSelectionRange(snapshot: snapshot, targetSpans: targetSpans)
        let prefix = boundedPrefix(in: targetText, before: absoluteRange.location, limit: 120)
        let suffix = boundedSuffix(in: targetText, after: absoluteRange.location + absoluteRange.length, limit: 120)

        var protectedTokens = snapshot.fragments
            .filter { $0.translationPolicy == .protect }
            .map(\.text)
            .filter { !$0.isEmpty }
        protectedTokens += sourceBlock.spans
            .filter { $0.translationPolicy == .protect }
            .map(\.text)
            .filter { !$0.isEmpty }
        for term in profile.protectedTerms {
            let targetTerm = term.translation.isEmpty ? term.source : term.translation
            if !targetTerm.isEmpty,
               snapshot.selectedText.localizedCaseInsensitiveContains(targetTerm)
                || sourceContext.localizedCaseInsensitiveContains(term.source)
            {
                protectedTokens.append(targetTerm)
            }
        }
        protectedTokens = stableUnique(protectedTokens)

        let glossary = profile.projectGlossary.prefix(64).map { entry in
            DocumentSelectionGlossaryHint(
                id: entry.id,
                source: entry.source,
                translation: entry.translations[targetLanguage] ?? entry.translation
            )
        }
        let sourceHash = sourceBlock.sourceHash.isEmpty ? stableHash(sourceText) : sourceBlock.sourceHash
        return DocumentSelectionTranslationRequest(
            operationID: snapshot.operationID.uuidString,
            targetLanguage: targetLanguage,
            sourceBlockID: blockID,
            sourceBlockHash: sourceHash,
            sourceContext: sourceContext,
            sourceSpans: mappedSourceSpans,
            sourceAlignment: sourceAlignment,
            selectedTargetText: snapshot.selectedText,
            targetPrefix: prefix,
            targetSuffix: suffix,
            protectedTokens: protectedTokens,
            glossary: glossary
        )
    }

    public func execute(
        snapshot: DocumentTextSelectionSnapshot,
        sourceBlocks: [DocumentBlock],
        targetBlocks: [TranslatedBlock],
        profile: DocumentTranslationProfile,
        targetLanguage: String,
        currentTargetBlock: @escaping @MainActor @Sendable (String) -> TranslatedBlock?,
        apply: @escaping @MainActor @Sendable (TranslatedBlock) -> Void
    ) async throws -> DocumentSelectionTranslationOutcome {
        let request = try makeRequest(
            snapshot: snapshot,
            sourceBlocks: sourceBlocks,
            targetBlocks: targetBlocks,
            profile: profile,
            targetLanguage: targetLanguage
        )
        guard let targetBlock = targetBlocks.first(where: {
            $0.sourceBlockID == request.sourceBlockID || $0.id == request.sourceBlockID
        }) else {
            throw DocumentSelectionTranslationEngineError.missingTargetBlock(request.sourceBlockID)
        }
        let initialSpans = resolvedTargetSpans(targetBlock)
        let expectedTargetHash = snapshot.blockHashes[request.sourceBlockID]
        guard let expectedTargetHash, !expectedTargetHash.isEmpty else {
            throw DocumentSelectionTranslationEngineError.missingTargetHash(request.sourceBlockID)
        }
        guard stableHash(initialSpans.map(\.text).joined()) == expectedTargetHash else {
            throw DocumentSelectionTranslationEngineError.staleResponse(request.sourceBlockID)
        }

        let rawResponse: String
        do {
            rawResponse = try await provider.generate(prompt: DocumentSelectionTranslationPrompt(request: request))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DocumentSelectionTranslationEngineError.providerFailure(provider.id)
        }

        let response: DocumentSelectionTranslationResponse
        do {
            response = try DocumentSelectionTranslationResponse.decodeStrict(Data(rawResponse.utf8))
        } catch {
            throw DocumentSelectionTranslationEngineError.invalidResponse("invalidJSON")
        }
        let validation = validator.validate(response: response, request: request)
        guard validation.isValid else {
            throw DocumentSelectionTranslationEngineError.validationFailed(validation.errors.map(\.code))
        }

        guard let currentBlock = await currentTargetBlock(request.sourceBlockID) else {
            throw DocumentSelectionTranslationEngineError.missingTargetBlock(request.sourceBlockID)
        }
        let currentSpans = resolvedTargetSpans(currentBlock)
        guard stableHash(currentSpans.map(\.text).joined()) == expectedTargetHash else {
            throw DocumentSelectionTranslationEngineError.staleResponse(request.sourceBlockID)
        }
        let currentRanges = try selectionRanges(snapshot: snapshot, targetSpans: currentSpans, blockID: request.sourceBlockID)
        guard (try selectedText(for: currentRanges, in: currentSpans)) == snapshot.selectedText else {
            throw DocumentSelectionTranslationEngineError.staleResponse(request.sourceBlockID)
        }
        guard currentFormattingMatches(snapshot: snapshot, targetSpans: currentSpans) else {
            throw DocumentSelectionTranslationEngineError.staleResponse(request.sourceBlockID)
        }

        let updatedSpans: [RichTextSpan]
        do {
            updatedSpans = try DocumentRichTextMutation.replace(
                spans: currentSpans,
                selection: rangesForMutation(snapshot: snapshot, targetSpans: currentSpans),
                with: response.replacementText,
                policy: .inheritExisting
            )
        } catch {
            throw DocumentSelectionTranslationEngineError.mutationFailure
        }
        var updatedBlock = currentBlock
        updatedBlock.spans = updatedSpans
        updatedBlock.text = updatedSpans.map(\.text).joined()
        await apply(updatedBlock)

        return DocumentSelectionTranslationOutcome(
            operationID: request.operationID,
            providerID: provider.id,
            blockID: request.sourceBlockID,
            replacementUTF16Length: (response.replacementText as NSString).length,
            warningCodes: validation.warnings.map(\.code)
        )
    }

    private struct FormattingFingerprint: Hashable {
        let styleKey: String
        let traits: Set<InlineTrait>
        let policy: SpanTranslationPolicy
        let color: String?

        init(fragment: DocumentTextFragment) {
            self.styleKey = fragment.styleKey
            self.traits = fragment.traits
            self.policy = fragment.translationPolicy
            self.color = fragment.foregroundColorHex
        }
        init(
            styleKey: String,
            traits: Set<InlineTrait>,
            policy: SpanTranslationPolicy,
            color: String?
        ) {
            self.styleKey = styleKey
            self.traits = traits
            self.policy = policy
            self.color = color
        }

    }

    private func resolvedTargetSpans(_ block: TranslatedBlock) -> [RichTextSpan] {
        if !block.spans.isEmpty { return block.spans }
        guard !block.text.isEmpty else { return [] }
        return [RichTextSpan(id: "selection-target-\(block.sourceBlockID)", text: block.text)]
    }

    private func selectionRanges(
        snapshot: DocumentTextSelectionSnapshot,
        targetSpans: [RichTextSpan],
        blockID: String
    ) throws -> [DocumentSpanRange] {
        guard !targetSpans.isEmpty else { throw DocumentSelectionTranslationEngineError.missingTargetBlock(blockID) }
        let targetIDs = Set(targetSpans.map(\.id))
        let syntheticID = targetSpans.count == 1 ? targetSpans[0].id : nil
        return try snapshot.fragments.map { fragment in
            guard fragment.blockID == blockID else {
                throw DocumentSelectionTranslationEngineError.crossBlockSelection
            }
            let spanID = fragment.spanID ?? syntheticID
            guard let spanID, targetIDs.contains(spanID) else {
                throw DocumentSelectionTranslationEngineError.selectionChanged(blockID)
            }
            let span = targetSpans.first { $0.id == spanID }!
            let safe = DocumentRichTextMutation.safeUTF16Range(in: span.text, requestedRange: fragment.utf16RangeInSpan)
            guard safe.length > 0 else { throw DocumentSelectionTranslationEngineError.emptySelection }
            return DocumentSpanRange(spanID: spanID, utf16Range: safe)
        }
    }

    private func rangesForMutation(
        snapshot: DocumentTextSelectionSnapshot,
        targetSpans: [RichTextSpan]
    ) -> [DocumentSpanRange] {
        let syntheticID = targetSpans.count == 1 ? targetSpans[0].id : nil
        return snapshot.fragments.compactMap { fragment in
            guard let spanID = fragment.spanID ?? syntheticID else { return nil }
            return DocumentSpanRange(spanID: spanID, utf16Range: fragment.utf16RangeInSpan)
        }
    }

    private func selectedText(for ranges: [DocumentSpanRange], in spans: [RichTextSpan]) throws -> String {
        try ranges.map { range in
            guard let span = spans.first(where: { $0.id == range.spanID }) else { throw DocumentSelectionTranslationEngineError.selectionChanged(range.spanID) }
            let safe = DocumentRichTextMutation.safeUTF16Range(in: span.text, requestedRange: range.utf16Range)
            guard safe.length > 0 else { throw DocumentSelectionTranslationEngineError.emptySelection }
            return (span.text as NSString).substring(with: safe)
        }.joined()
    }

    private func currentFormattingMatches(
        snapshot: DocumentTextSelectionSnapshot,
        targetSpans: [RichTextSpan]
    ) -> Bool {
        snapshot.fragments.allSatisfy { fragment in
            guard let spanID = fragment.spanID ?? (targetSpans.count == 1 ? targetSpans[0].id : nil),
                  let span = targetSpans.first(where: { $0.id == spanID })
            else { return false }
            return FormattingFingerprint(fragment: fragment)
                == FormattingFingerprint(
                    styleKey: span.styleKey,
                    traits: span.traits,
                    policy: span.translationPolicy,
                    color: span.foregroundColorHex
                )
        }
    }

    private func absoluteSelectionRange(
        snapshot: DocumentTextSelectionSnapshot,
        targetSpans: [RichTextSpan]
    ) -> NSRange {
        var offsets: [String: Int] = [:]
        var cursor = 0
        for span in targetSpans {
            offsets[span.id] = cursor
            cursor += (span.text as NSString).length
        }
        let starts = snapshot.fragments.compactMap { fragment -> Int? in
            let spanID = fragment.spanID ?? (targetSpans.count == 1 ? targetSpans[0].id : nil)
            guard let spanID, let offset = offsets[spanID] else { return nil }
            return offset + fragment.utf16RangeInSpan.location
        }
        let ends = snapshot.fragments.compactMap { fragment -> Int? in
            let spanID = fragment.spanID ?? (targetSpans.count == 1 ? targetSpans[0].id : nil)
            guard let spanID, let offset = offsets[spanID] else { return nil }
            return offset + fragment.utf16RangeInSpan.location + fragment.utf16RangeInSpan.length
        }
        guard let start = starts.min(), let end = ends.max(), end >= start else { return NSRange(location: 0, length: 0) }
        return NSRange(location: start, length: end - start)
    }

    private func boundedPrefix(in text: String, before offset: Int, limit: Int) -> String {
        let ns = text as NSString
        let end = max(0, min(offset, ns.length))
        let start = max(0, end - limit)
        return ns.substring(with: NSRange(location: start, length: end - start))
    }

    private func boundedSuffix(in text: String, after offset: Int, limit: Int) -> String {
        let ns = text as NSString
        let start = max(0, min(offset, ns.length))
        let end = min(ns.length, start + limit)
        return ns.substring(with: NSRange(location: start, length: end - start))
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func stableHash(_ value: String) -> String {
        DocumentSelectionTranslationHash.sha256(value)
    }

}

private extension Array where Element == DocumentSelectionSourceSpan {
    func uniquedByID() -> [DocumentSelectionSourceSpan] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}

private enum DocumentSelectionTranslationHash {
    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct LiveCloudSelectionTranslationProvider: DocumentSelectionTranslationProvider {
    let provider: ActiveCloudTranslationProvider
    let engine: CloudTextTranslationEngine

    var id: String { provider.id }

    func generate(prompt: DocumentSelectionTranslationPrompt) async throws -> String {
        try await engine.translateDocument(
            prompt: prompt.renderedText,
            provider: provider,
            maxOutputTokens: 2_048
        )
    }
}

private struct LiveMLXSelectionTranslationProvider: DocumentSelectionTranslationProvider {
    let model: ActiveMLXModel
    let engine: MLXTextGenerationEngine

    var id: String { model.id }

    func generate(prompt: DocumentSelectionTranslationPrompt) async throws -> String {
        try await engine.generateDocumentTranslation(
            prompt: prompt.renderedText,
            model: model,
            sourceLength: prompt.request.sourceContext.count + prompt.request.selectedTargetText.count,
            maxTokens: 2_048
        )
    }
}

public extension DocumentSelectionTranslationEngine {
    /// Uses the same provider ID resolution and cloud/local adapters as document
    /// retranslation. No second provider list or settings selection is introduced.
    static func live(settings: AppSettings, providerID: String) throws -> DocumentSelectionTranslationEngine {
        if let cloud = ActiveCloudTranslationProvider.resolve(settings: settings, providerID: providerID) {
            return DocumentSelectionTranslationEngine(
                provider: LiveCloudSelectionTranslationProvider(
                    provider: cloud,
                    engine: CloudTextTranslationEngine()
                )
            )
        }
        guard let model = NativeModelCatalog.activeMLXModel(settings: settings, providerID: providerID) else {
            throw DocumentSelectionTranslationEngineError.providerUnavailable(providerID)
        }
        return DocumentSelectionTranslationEngine(
            provider: LiveMLXSelectionTranslationProvider(
                model: model,
                engine: MLXTextGenerationEngine()
            )
        )
    }
}
