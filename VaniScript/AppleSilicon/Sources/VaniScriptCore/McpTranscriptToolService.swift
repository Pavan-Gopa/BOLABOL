import Foundation

public struct McpTranscriptMutation {
    public var workflow: WorkflowState
    public var message: String
    public var details: [String: Any]
}

@MainActor
public enum McpTranscriptToolService {
    public static let supportedToolNames: Set<String> = [
        "replace_transcript_text",
        "batch_update_chunk_text",
        "update_cue_text",
        "insert_cue",
        "delete_cue",
        "split_cue",
        "merge_cues",
        "batch_approve_chunks",
    ]

    public static func execute(
        name: String,
        arguments: [String: Any],
        workflow: WorkflowState,
        confirmationStore: McpConfirmationStore
    ) throws -> McpTranscriptMutation {
        switch name {
        case "replace_transcript_text":
            return try replaceTranscriptText(
                arguments: arguments,
                workflow: workflow,
                confirmationStore: confirmationStore
            )
        case "batch_update_chunk_text":
            return try batchUpdateChunkText(arguments: arguments, workflow: workflow)
        case "update_cue_text":
            return try updateCueText(arguments: arguments, workflow: workflow)
        case "insert_cue":
            return try insertCue(arguments: arguments, workflow: workflow)
        case "delete_cue":
            return try deleteCue(arguments: arguments, workflow: workflow)
        case "split_cue":
            return try splitCue(arguments: arguments, workflow: workflow)
        case "merge_cues":
            return try mergeCues(arguments: arguments, workflow: workflow)
        case "batch_approve_chunks":
            return try batchApproveChunks(arguments: arguments, workflow: workflow)
        default:
            throw toolError(code: -4, message: "Unknown transcript tool \(name)")
        }
    }
}

private extension McpTranscriptToolService {
    static func replaceTranscriptText(
        arguments: [String: Any],
        workflow: WorkflowState,
        confirmationStore: McpConfirmationStore
    ) throws -> McpTranscriptMutation {
        var updatedWorkflow = workflow
        guard var session = updatedWorkflow.session else {
            throw toolError(code: -1, message: "No active VaniScript session")
        }
        guard let query = nonEmptyString(arguments["query"]), query.count <= 500 else {
            throw toolError(code: -2, message: "query is required and must contain no more than 500 characters")
        }
        guard let replacement = arguments["replacement"] as? String, replacement.count <= 20_000 else {
            throw toolError(code: -2, message: "replacement must be a string containing no more than 20,000 characters")
        }
        let side = try transcriptSide(arguments["side"])
        let language = nonEmptyString(arguments["language"]) ?? session.selectedTranslationLanguage
        if side == "translated", language == nil {
            throw toolError(code: -2, message: "No translated language is active. Select one or provide language.")
        }
        let caseSensitive = arguments["caseSensitive"] as? Bool ?? false
        let wholeWord = arguments["wholeWord"] as? Bool ?? false
        let regex = try replacementRegex(query: query, caseSensitive: caseSensitive, wholeWord: wholeWord)
        let preview = replacementPreview(regex: regex, side: side, language: language, session: session)
        let revision = McpProjectRevision.make(workflow: workflow)
        let fingerprint = [
            query,
            replacement,
            side,
            language ?? "",
            String(caseSensitive),
            String(wholeWord),
        ].joined(separator: "\u{1f}")
        let dryRun = arguments["dryRun"] as? Bool ?? true

        if dryRun {
            let token = confirmationStore.issue(
                operation: "replace_transcript_text",
                fingerprint: fingerprint,
                projectRevision: revision
            )
            return McpTranscriptMutation(
                workflow: workflow,
                message: "Previewed \(preview.matchCount) replacement(s) in \(preview.affectedChunkIDs.count) segment(s)",
                details: [
                    "dryRun": true,
                    "matchCount": preview.matchCount,
                    "affectedChunkIds": preview.affectedChunkIDs,
                    "previews": preview.items,
                    "confirmationToken": token,
                    "confirmationExpiresInSec": 120,
                ]
            )
        }

        guard let expectedRevision = nonEmptyString(arguments["expectedRevision"]),
              expectedRevision == revision else {
            throw toolError(code: -6, message: "STALE_REVISION: Apply requires the projectRevision returned with the dry-run preview.")
        }
        guard let confirmationToken = nonEmptyString(arguments["confirmationToken"]),
              confirmationStore.consume(
                token: confirmationToken,
                operation: "replace_transcript_text",
                fingerprint: fingerprint,
                projectRevision: revision
              ) else {
            throw toolError(code: -7, message: "CONFIRMATION_REQUIRED: Run the same replacement with dryRun=true and use its unexpired confirmationToken.")
        }

        let replacementTemplate = NSRegularExpression.escapedTemplate(for: replacement)
        var replacementCount = 0
        for chunkIndex in session.chunks.indices {
            var chunk = session.chunks[chunkIndex]
            switch side {
            case "original":
                if var cues = chunk.originalCues, !cues.isEmpty {
                    for cueIndex in cues.indices {
                        replacementCount += replaceMatches(regex, template: replacementTemplate, text: &cues[cueIndex].text)
                        cues[cueIndex].words = NativeLLMPromptBuilder.approximateWords(for: cues[cueIndex].text, source: cues[cueIndex])
                    }
                    chunk.originalCues = cues
                    chunk.original = cues.map(\.text).joined(separator: " ")
                } else {
                    replacementCount += replaceMatches(regex, template: replacementTemplate, text: &chunk.original)
                }
            case "translated":
                guard let language else { continue }
                var cues = chunk.translationCues(for: language)
                if !cues.isEmpty {
                    for cueIndex in cues.indices {
                        replacementCount += replaceMatches(regex, template: replacementTemplate, text: &cues[cueIndex].text)
                        cues[cueIndex].words = NativeLLMPromptBuilder.approximateWords(for: cues[cueIndex].text, source: cues[cueIndex])
                    }
                    let text = cues.map(\.text).joined(separator: "\n")
                    chunk.translated = text
                    chunk.setTranslation(text, language: language, provider: session.translationProvider, cues: cues)
                } else {
                    var text = chunk.translationText(for: language) ?? chunk.translated
                    replacementCount += replaceMatches(regex, template: replacementTemplate, text: &text)
                    chunk.translated = text
                    chunk.setTranslation(text, language: language, provider: session.translationProvider)
                }
            default:
                break
            }
            if preview.affectedChunkIDs.contains(McpEntityIdentifier.chunkID(chunk)) {
                chunk.status = .done
            }
            session.chunks[chunkIndex] = chunk
        }
        session.normalizeTranslationArchive()
        updatedWorkflow.session = session
        return McpTranscriptMutation(
            workflow: updatedWorkflow,
            message: "Replaced \(replacementCount) occurrence(s)",
            details: [
                "dryRun": false,
                "replacementCount": replacementCount,
                "affectedChunkIds": preview.affectedChunkIDs,
            ]
        )
    }

    static func batchUpdateChunkText(
        arguments: [String: Any],
        workflow: WorkflowState
    ) throws -> McpTranscriptMutation {
        var updatedWorkflow = workflow
        guard var session = updatedWorkflow.session else {
            throw toolError(code: -1, message: "No active VaniScript session")
        }
        guard let updates = arguments["updates"] as? [[String: Any]],
              !updates.isEmpty,
              updates.count <= 100 else {
            throw toolError(code: -2, message: "updates must contain between 1 and 100 items")
        }

        var resolved = [(Int, String?, String?)]()
        var seen = Set<Int>()
        for update in updates {
            let chunkIndex = try resolveChunkIndex(arguments: update, session: session)
            guard seen.insert(chunkIndex).inserted else {
                throw toolError(code: -2, message: "Each chunkId may appear only once in an atomic batch")
            }
            let original = update["original"] as? String
            let translated = update["translated"] as? String
            guard original != nil || translated != nil else {
                throw toolError(code: -2, message: "Each update must contain original and/or translated text")
            }
            resolved.append((chunkIndex, original, translated))
        }

        let language = session.selectedTranslationLanguage
        for (chunkIndex, original, translated) in resolved {
            if let original {
                session.chunks[chunkIndex].original = original
                session.chunks[chunkIndex].originalCues = nil
            }
            if let translated {
                session.chunks[chunkIndex].translated = translated
                if let language {
                    session.chunks[chunkIndex].setTranslation(
                        translated,
                        language: language,
                        provider: session.translationProvider
                    )
                }
            }
            session.chunks[chunkIndex].status = .done
        }
        updatedWorkflow.session = session
        return McpTranscriptMutation(
            workflow: updatedWorkflow,
            message: "Updated \(resolved.count) segment(s) atomically",
            details: ["updatedChunkIds": resolved.map { McpEntityIdentifier.chunkID(session.chunks[$0.0]) }]
        )
    }

    static func updateCueText(
        arguments: [String: Any],
        workflow: WorkflowState
    ) throws -> McpTranscriptMutation {
        try mutateCues(arguments: arguments, workflow: workflow, operation: "Updated cue text") { cues, cueIndex, _ in
            guard let text = arguments["text"] as? String else {
                throw toolError(code: -2, message: "text must be a string")
            }
            cues[cueIndex].text = text
            cues[cueIndex].words = NativeLLMPromptBuilder.approximateWords(for: text, source: cues[cueIndex])
        }
    }

    static func insertCue(
        arguments: [String: Any],
        workflow: WorkflowState
    ) throws -> McpTranscriptMutation {
        var updatedWorkflow = workflow
        guard var session = updatedWorkflow.session else {
            throw toolError(code: -1, message: "No active VaniScript session")
        }
        let chunkIndex = try resolveChunkIndex(arguments: arguments, session: session)
        let side = try transcriptSide(arguments["side"])
        let language = nonEmptyString(arguments["language"]) ?? session.selectedTranslationLanguage
        var cues = try cues(for: side, language: language, chunk: session.chunks[chunkIndex])
        guard let insertAt = McpToolArguments.wholeNumber(arguments["insertAt"]),
              insertAt >= 0,
              insertAt <= cues.count,
              let startSec = finiteDouble(arguments["startSec"]),
              let endSec = finiteDouble(arguments["endSec"]),
              let text = arguments["text"] as? String else {
            throw toolError(code: -2, message: "insertAt, startSec, endSec, and text are required")
        }
        try validateInsertedTiming(startSec: startSec, endSec: endSec, insertAt: insertAt, cues: cues, chunk: session.chunks[chunkIndex])
        let cue = TranscriptCue(startSec: startSec, endSec: endSec, text: text)
        var timedCue = cue
        timedCue.words = NativeLLMPromptBuilder.approximateWords(for: text, source: cue)
        cues.insert(timedCue, at: insertAt)
        update(chunk: &session.chunks[chunkIndex], side: side, language: language, cues: cues, provider: session.translationProvider)
        updatedWorkflow.session = session
        return McpTranscriptMutation(
            workflow: updatedWorkflow,
            message: "Inserted cue \(insertAt) in segment \(session.chunks[chunkIndex].index + 1)",
            details: ["cueId": McpEntityIdentifier.cueID(chunk: session.chunks[chunkIndex], side: side, index: insertAt)]
        )
    }

    static func deleteCue(
        arguments: [String: Any],
        workflow: WorkflowState
    ) throws -> McpTranscriptMutation {
        try mutateCues(arguments: arguments, workflow: workflow, operation: "Deleted cue") { cues, cueIndex, _ in
            cues.remove(at: cueIndex)
        }
    }

    static func splitCue(
        arguments: [String: Any],
        workflow: WorkflowState
    ) throws -> McpTranscriptMutation {
        try mutateCues(arguments: arguments, workflow: workflow, operation: "Split cue") { cues, cueIndex, _ in
            guard let splitOffset = McpToolArguments.wholeNumber(arguments["splitAtCharacter"]) else {
                throw toolError(code: -2, message: "splitAtCharacter is required")
            }
            let original = cues[cueIndex]
            let characters = Array(original.text)
            guard splitOffset > 0, splitOffset < characters.count else {
                throw toolError(code: -2, message: "splitAtCharacter must be strictly inside the cue text")
            }
            let firstText = String(characters[..<splitOffset]).trimmingCharacters(in: .whitespacesAndNewlines)
            let secondText = String(characters[splitOffset...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !firstText.isEmpty, !secondText.isEmpty else {
                throw toolError(code: -2, message: "The split must leave non-empty text on both sides")
            }
            let splitSec = finiteDouble(arguments["splitSec"]) ?? ((original.startSec + original.endSec) / 2)
            guard splitSec > original.startSec + 0.01, splitSec < original.endSec - 0.01 else {
                throw toolError(code: -2, message: "splitSec must be strictly inside the cue timing")
            }
            var first = TranscriptCue(startSec: original.startSec, endSec: splitSec, text: firstText)
            var second = TranscriptCue(startSec: splitSec, endSec: original.endSec, text: secondText)
            first.words = NativeLLMPromptBuilder.approximateWords(for: firstText, source: first)
            second.words = NativeLLMPromptBuilder.approximateWords(for: secondText, source: second)
            cues.replaceSubrange(cueIndex...cueIndex, with: [first, second])
        }
    }

    static func mergeCues(
        arguments: [String: Any],
        workflow: WorkflowState
    ) throws -> McpTranscriptMutation {
        try mutateCues(arguments: arguments, workflow: workflow, operation: "Merged adjacent cues", cueIDKey: "firstCueId", cueIndexKey: "firstCueIndex") { cues, firstIndex, _ in
            let secondIndex = firstIndex + 1
            guard cues.indices.contains(secondIndex) else {
                throw toolError(code: -2, message: "The first cue must have an adjacent next cue")
            }
            let first = cues[firstIndex]
            let second = cues[secondIndex]
            let text = [first.text, second.text]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            var merged = TranscriptCue(startSec: first.startSec, endSec: second.endSec, text: text)
            merged.words = NativeLLMPromptBuilder.approximateWords(for: text, source: merged)
            cues.replaceSubrange(firstIndex...secondIndex, with: [merged])
        }
    }

    static func batchApproveChunks(
        arguments: [String: Any],
        workflow: WorkflowState
    ) throws -> McpTranscriptMutation {
        var updatedWorkflow = workflow
        guard var session = updatedWorkflow.session else {
            throw toolError(code: -1, message: "No active VaniScript session")
        }
        guard let chunkIDs = arguments["chunkIds"] as? [String],
              !chunkIDs.isEmpty,
              chunkIDs.count <= 500,
              let approved = arguments["approved"] as? Bool else {
            throw toolError(code: -2, message: "chunkIds and approved are required")
        }
        let uniqueIDs = Array(Set(chunkIDs))
        guard uniqueIDs.count == chunkIDs.count else {
            throw toolError(code: -2, message: "chunkIds must not contain duplicates")
        }
        let indexes = try chunkIDs.map { try resolveChunkIndex(arguments: ["chunkId": $0], session: session) }
        for index in indexes {
            session.chunks[index].approved = approved
        }
        updatedWorkflow.session = session
        return McpTranscriptMutation(
            workflow: updatedWorkflow,
            message: "Updated approval for \(indexes.count) segment(s)",
            details: ["chunkIds": chunkIDs, "approved": approved]
        )
    }
}

private extension McpTranscriptToolService {
    struct ReplacementPreview {
        let matchCount: Int
        let affectedChunkIDs: [String]
        let items: [[String: Any]]
    }

    static func mutateCues(
        arguments: [String: Any],
        workflow: WorkflowState,
        operation: String,
        cueIDKey: String = "cueId",
        cueIndexKey: String = "cueIndex",
        mutation: (inout [TranscriptCue], Int, ChunkData) throws -> Void
    ) throws -> McpTranscriptMutation {
        var updatedWorkflow = workflow
        guard var session = updatedWorkflow.session else {
            throw toolError(code: -1, message: "No active VaniScript session")
        }
        let chunkIndex = try resolveChunkIndex(arguments: arguments, session: session)
        let side = try transcriptSide(arguments["side"])
        let language = nonEmptyString(arguments["language"]) ?? session.selectedTranslationLanguage
        var cues = try cues(for: side, language: language, chunk: session.chunks[chunkIndex])
        let cueIndex = try resolveCueIndex(
            arguments: arguments,
            cueIDKey: cueIDKey,
            cueIndexKey: cueIndexKey,
            chunk: session.chunks[chunkIndex],
            side: side,
            cues: cues
        )
        try mutation(&cues, cueIndex, session.chunks[chunkIndex])
        update(chunk: &session.chunks[chunkIndex], side: side, language: language, cues: cues, provider: session.translationProvider)
        updatedWorkflow.session = session
        return McpTranscriptMutation(
            workflow: updatedWorkflow,
            message: "\(operation) in segment \(session.chunks[chunkIndex].index + 1)",
            details: [
                "chunkId": McpEntityIdentifier.chunkID(session.chunks[chunkIndex]),
                "side": side,
                "cueCount": cues.count,
            ]
        )
    }

    static func update(
        chunk: inout ChunkData,
        side: String,
        language: String?,
        cues: [TranscriptCue],
        provider: String
    ) {
        if side == "original" {
            chunk.originalCues = cues
            chunk.original = cues.map(\.text).joined(separator: " ")
        } else if let language {
            let text = cues.map(\.text).joined(separator: "\n")
            chunk.translated = text
            chunk.setTranslation(text, language: language, provider: provider, cues: cues)
        }
        chunk.status = .done
    }

    static func cues(for side: String, language: String?, chunk: ChunkData) throws -> [TranscriptCue] {
        if side == "original" {
            return chunk.originalCues ?? []
        }
        guard let language else {
            throw toolError(code: -2, message: "No translated language is active. Select one or provide language.")
        }
        return chunk.translationCues(for: language)
    }

    static func resolveChunkIndex(arguments: [String: Any], session: SessionState) throws -> Int {
        guard let chunkID = nonEmptyString(arguments["chunkId"]),
              let stableIndex = McpEntityIdentifier.chunkIndex(from: chunkID),
              let arrayIndex = session.chunks.firstIndex(where: { $0.index == stableIndex }) else {
            throw toolError(code: -3, message: "Unknown or missing chunkId. Call list_chunks for valid stable IDs.")
        }
        return arrayIndex
    }

    static func resolveCueIndex(
        arguments: [String: Any],
        cueIDKey: String,
        cueIndexKey: String,
        chunk: ChunkData,
        side: String,
        cues: [TranscriptCue]
    ) throws -> Int {
        if let cueID = nonEmptyString(arguments[cueIDKey]) {
            guard let cueIndex = cues.indices.first(where: {
                McpEntityIdentifier.cueID(chunk: chunk, side: side, index: $0) == cueID
            }) else {
                throw toolError(code: -3, message: "Unknown \(cueIDKey). Call get_chunk_cues for valid stable IDs.")
            }
            return cueIndex
        }
        guard let cueIndex = McpToolArguments.wholeNumber(arguments[cueIndexKey]),
              cues.indices.contains(cueIndex) else {
            throw toolError(code: -2, message: "Provide \(cueIDKey) from get_chunk_cues or a valid zero-based \(cueIndexKey).")
        }
        return cueIndex
    }

    static func validateInsertedTiming(
        startSec: Double,
        endSec: Double,
        insertAt: Int,
        cues: [TranscriptCue],
        chunk: ChunkData
    ) throws {
        guard startSec >= chunk.startSec,
              endSec <= chunk.endSec,
              endSec > startSec + 0.01 else {
            throw toolError(code: -2, message: "Cue timing must be positive and remain inside the segment range")
        }
        if insertAt > 0, startSec < cues[insertAt - 1].endSec {
            throw toolError(code: -2, message: "Inserted cue overlaps the previous cue")
        }
        if insertAt < cues.count, endSec > cues[insertAt].startSec {
            throw toolError(code: -2, message: "Inserted cue overlaps the next cue")
        }
    }

    static func replacementPreview(
        regex: NSRegularExpression,
        side: String,
        language: String?,
        session: SessionState
    ) -> ReplacementPreview {
        var matchCount = 0
        var affectedChunkIDs = [String]()
        var items = [[String: Any]]()
        for chunk in session.chunks {
            let text: String
            if side == "original" {
                let cues = chunk.originalCues ?? []
                text = cues.isEmpty ? chunk.original : cues.map(\.text).joined(separator: " ")
            } else {
                let cues = chunk.translationCues(for: language)
                text = cues.isEmpty ? (chunk.translationText(for: language) ?? chunk.translated) : cues.map(\.text).joined(separator: "\n")
            }
            let ranges = regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range)
            guard !ranges.isEmpty else { continue }
            let id = McpEntityIdentifier.chunkID(chunk)
            matchCount += ranges.count
            affectedChunkIDs.append(id)
            if items.count < 20 {
                items.append([
                    "chunkId": id,
                    "displayNumber": chunk.index + 1,
                    "matchCount": ranges.count,
                    "snippet": previewSnippet(text: text, match: ranges[0]),
                ])
            }
        }
        return ReplacementPreview(matchCount: matchCount, affectedChunkIDs: affectedChunkIDs, items: items)
    }

    static func replaceMatches(
        _ regex: NSRegularExpression,
        template: String,
        text: inout String
    ) -> Int {
        let range = NSRange(location: 0, length: (text as NSString).length)
        let count = regex.numberOfMatches(in: text, range: range)
        guard count > 0 else { return 0 }
        text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
        return count
    }

    static func replacementRegex(
        query: String,
        caseSensitive: Bool,
        wholeWord: Bool
    ) throws -> NSRegularExpression {
        let escaped = NSRegularExpression.escapedPattern(for: query)
        let pattern = wholeWord ? "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])" : escaped
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw toolError(code: -2, message: "Invalid replacement query")
        }
    }

    static func transcriptSide(_ value: Any?) throws -> String {
        guard let side = nonEmptyString(value)?.lowercased(),
              side == "original" || side == "translated" else {
            throw toolError(code: -2, message: "side must be original or translated")
        }
        return side
    }

    static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func finiteDouble(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let result = number.doubleValue
            return result.isFinite ? result : nil
        }
        if let number = value as? Double, number.isFinite { return number }
        if let number = value as? Int { return Double(number) }
        return nil
    }

    static func previewSnippet(text: String, match: NSRange) -> String {
        let source = text as NSString
        let start = max(0, match.location - 60)
        let end = min(source.length, NSMaxRange(match) + 60)
        let raw = source.substring(with: NSRange(location: start, length: end - start))
        return raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func toolError(code: Int, message: String) -> NSError {
        NSError(domain: "VaniScriptMCP", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
