import Foundation
import VaniScriptCore

enum McpReadToolService {
    static let supportedToolNames: Set<String> = [
        "get_capabilities",
        "get_ui_state",
        "get_processing_status",
        "validate_active_project",
        "list_help_topics",
        "get_help_topic",
        "search_help",
        "get_contextual_help",
        "get_onboarding_checklist",
        "list_chunks",
        "get_chunk",
        "get_chunk_cues",
        "search_transcript",
        "get_unrecognized_fragments",
        "list_translation_languages",
    ]

    static func execute(
        name: String,
        arguments: [String: Any],
        workflow: WorkflowState,
        permissions: McpPermissionSet
    ) throws -> [String: Any] {
        switch name {
        case "get_capabilities":
            return capabilities(workflow: workflow, permissions: permissions)
        case "get_ui_state":
            return uiState(workflow: workflow)
        case "get_processing_status":
            return processingStatus(workflow: workflow)
        case "validate_active_project":
            return validateProject(workflow: workflow)
        case "list_help_topics":
            return listHelpTopics(arguments: arguments)
        case "get_help_topic":
            return try getHelpTopic(arguments: arguments)
        case "search_help":
            return try searchHelp(arguments: arguments)
        case "get_contextual_help":
            return contextualHelp(arguments: arguments, workflow: workflow)
        case "get_onboarding_checklist":
            return onboardingChecklist(arguments: arguments)
        case "list_chunks":
            return try listChunks(arguments: arguments, workflow: workflow)
        case "get_chunk":
            return try getChunk(arguments: arguments, workflow: workflow)
        case "get_chunk_cues":
            return try getChunkCues(arguments: arguments, workflow: workflow)
        case "search_transcript":
            return try searchTranscript(arguments: arguments, workflow: workflow)
        case "get_unrecognized_fragments":
            return try unrecognizedFragments(arguments: arguments, workflow: workflow)
        case "list_translation_languages":
            return try translationLanguages(workflow: workflow)
        default:
            throw toolError(code: -4, message: "Unknown read tool \(name)")
        }
    }
}

private extension McpReadToolService {
    static func capabilities(
        workflow: WorkflowState,
        permissions: McpPermissionSet
    ) -> [String: Any] {
        let definitions = McpToolRegistry.definitions(permissions: permissions)
        let toolsByScope = Dictionary(grouping: definitions, by: \.access)
            .mapValues { $0.map(\.name) }
        return [
            "server": "VaniScript",
            "currentScreen": workflow.screen.rawValue,
            "hasSource": !workflow.sourceFile.isEmpty,
            "hasActiveSession": workflow.session != nil,
            "allowMutatingTools": permissions.allows(.edit),
            "permissions": permissions.safeDictionary,
            "availableToolCount": definitions.count,
            "toolsByScope": Dictionary(uniqueKeysWithValues: toolsByScope.map { ($0.key.rawValue, $0.value) }),
            "groups": [
                ["id": "help", "label": "Help & Onboarding", "available": true],
                ["id": "project-state", "label": "Project State", "available": true],
                ["id": "review", "label": "Transcript Review", "available": workflow.session != nil],
                ["id": "shorts", "label": "Shorts", "available": workflow.session != nil],
                ["id": "project-editing", "label": "Project Editing", "available": permissions.allows(.edit)],
                ["id": "processing", "label": "Processing", "available": permissions.allows(.processing)],
                ["id": "files", "label": "Files & Export", "available": permissions.allows(.files)],
                ["id": "network", "label": "Network & Models", "available": permissions.allows(.network)],
                ["id": "destructive", "label": "Destructive Actions", "available": permissions.allows(.destructive)],
            ],
        ]
    }

    static func uiState(workflow: WorkflowState) -> [String: Any] {
        var result: [String: Any] = [
            "screen": workflow.screen.rawValue,
            "screenTitle": workflow.screen.title,
            "hasSource": !workflow.sourceFile.isEmpty,
            "sourceFileName": workflow.sourceFileName,
            "durationSec": workflow.durationSec,
            "hasActiveSession": workflow.session != nil,
            "processingMessage": workflow.processingMessage,
            "processingProgress": clampedProgress(workflow.processingProgress),
        ]

        if let session = workflow.session {
            result["selectedTranslationLanguage"] = session.selectedTranslationLanguage ?? ""
            result["availableTranslationLanguages"] = session.availableTranslationLanguages ?? []
            result["shortsPlanCount"] = session.shortsPlans?.count ?? 0
            result["chunkCount"] = session.chunks.count
            result["approvedChunkCount"] = session.chunks.filter(\.approved).count
            if session.chunks.indices.contains(session.currentChunkIndex) {
                let chunk = session.chunks[session.currentChunkIndex]
                result["currentChunk"] = chunkSummary(chunk, arrayIndex: session.currentChunkIndex)
            }
        }
        return result
    }

    static func validateProject(workflow: WorkflowState) -> [String: Any] {
        var issues: [[String: Any]] = []
        guard let session = workflow.session else {
            return [
                "valid": false,
                "issueCount": 1,
                "issues": [["severity": "error", "code": "NO_ACTIVE_PROJECT", "message": "No active project is open."]],
            ]
        }
        if let source = session.sourceFile, !source.isEmpty, !FileManager.default.fileExists(atPath: source) {
            issues.append(["severity": "error", "code": "SOURCE_MEDIA_MISSING", "message": "The source media file is not available."])
        }
        for (arrayIndex, chunk) in session.chunks.enumerated() {
            let chunkID = McpEntityIdentifier.chunkID(chunk)
            if !chunk.startSec.isFinite || !chunk.endSec.isFinite || chunk.startSec < 0 || chunk.endSec <= chunk.startSec {
                issues.append(["severity": "error", "code": "INVALID_CHUNK_RANGE", "entityId": chunkID, "message": "Segment timing is invalid."])
            }
            if arrayIndex > 0, chunk.startSec < session.chunks[arrayIndex - 1].startSec {
                issues.append(["severity": "error", "code": "UNSORTED_CHUNKS", "entityId": chunkID, "message": "Segments are not ordered by start time."])
            }
            if chunk.status == .done, chunk.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(["severity": "warning", "code": "EMPTY_TRANSCRIPT", "entityId": chunkID, "message": "Completed segment has no transcript text."])
            }
            for (cueIndex, cue) in (chunk.originalCues ?? []).enumerated() where cue.startSec < chunk.startSec || cue.endSec > chunk.endSec || cue.endSec <= cue.startSec {
                issues.append([
                    "severity": "error",
                    "code": "INVALID_CUE_RANGE",
                    "entityId": McpEntityIdentifier.cueID(chunk: chunk, side: "original", index: cueIndex),
                    "message": "Source cue timing is outside its segment.",
                ])
            }
        }
        for plan in session.shortsPlans ?? [] {
            let start = ShortsPlanner.parseTimestampToSeconds(plan.start)
            let end = ShortsPlanner.parseTimestampToSeconds(plan.end)
            if start < 0 || end <= start || (session.durationSec > 0 && end > session.durationSec) {
                issues.append(["severity": "error", "code": "INVALID_SHORTS_RANGE", "entityId": plan.id, "message": "Shorts plan timing is outside the source media."])
            }
            if plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(["severity": "warning", "code": "EMPTY_SHORTS_TITLE", "entityId": plan.id, "message": "Shorts plan title is empty."])
            }
        }
        return [
            "valid": !issues.contains { ($0["severity"] as? String) == "error" },
            "issueCount": issues.count,
            "issues": issues,
            "chunkCount": session.chunks.count,
            "shortsPlanCount": session.shortsPlans?.count ?? 0,
        ]
    }

    static func processingStatus(workflow: WorkflowState) -> [String: Any] {
        let currentChunk = workflow.session.flatMap { session -> ChunkData? in
            guard session.chunks.indices.contains(session.currentChunkIndex) else { return nil }
            return session.chunks[session.currentChunkIndex]
        }

        let state: String
        if workflow.screen == .processing || currentChunk?.status == .processing {
            state = "running"
        } else if currentChunk?.status == .error {
            state = "error"
        } else if workflow.processingProgress >= 1 {
            state = "completed"
        } else {
            state = "idle"
        }

        var result: [String: Any] = [
            "state": state,
            "screen": workflow.screen.rawValue,
            "progress": clampedProgress(workflow.processingProgress),
            "message": workflow.processingMessage,
        ]
        if let session = workflow.session {
            result["totalChunks"] = session.chunks.count
            result["completedChunks"] = session.chunks.filter { $0.status == .done }.count
            result["failedChunks"] = session.chunks.filter { $0.status == .error }.count
            if let currentChunk {
                result["currentChunkId"] = chunkID(currentChunk)
                result["currentDisplayNumber"] = currentChunk.index + 1
                result["currentChunkStatus"] = currentChunk.status.rawValue
            }
        }
        return result
    }

    static func listHelpTopics(arguments: [String: Any]) -> [String: Any] {
        let language = helpLanguage(arguments)
        let category = arguments["category"] as? String
        let topics = VaniScriptHelpCatalog.list(category: category, language: language)
        let categories = Array(Set(VaniScriptHelpCatalog.list(language: language).map(\.category))).sorted()
        return [
            "language": language.rawValue,
            "categories": categories,
            "topics": topics.map(helpTopicSummary),
            "count": topics.count,
        ]
    }

    static func getHelpTopic(arguments: [String: Any]) throws -> [String: Any] {
        guard let topicID = nonEmptyString(arguments["topicId"]) else {
            throw toolError(code: -2, message: "topicId is required. Call list_help_topics or search_help first.")
        }
        let language = helpLanguage(arguments)
        guard let topic = VaniScriptHelpCatalog.topic(id: topicID, language: language) else {
            throw toolError(code: -3, message: "Help topic not found: \(topicID)")
        }
        return helpTopicDictionary(topic)
    }

    static func searchHelp(arguments: [String: Any]) throws -> [String: Any] {
        guard let query = nonEmptyString(arguments["query"]) else {
            throw toolError(code: -2, message: "query is required and cannot be empty")
        }
        let language = helpLanguage(arguments)
        let limit = clampedInteger(arguments["limit"], default: 5, range: 1...10)
        let topics = VaniScriptHelpCatalog.search(query: query, language: language, limit: limit)
        return [
            "query": query,
            "language": language.rawValue,
            "matches": topics.map(helpTopicDictionary),
            "matchCount": topics.count,
        ]
    }

    static func contextualHelp(
        arguments: [String: Any],
        workflow: WorkflowState
    ) -> [String: Any] {
        let language = helpLanguage(arguments)
        let context = VaniScriptHelpCatalog.contextualHelp(
            screen: workflow.screen,
            hasSource: !workflow.sourceFile.isEmpty,
            hasSession: workflow.session != nil,
            processingProgress: workflow.processingProgress,
            hasShortsPlans: !(workflow.session?.shortsPlans?.isEmpty ?? true),
            language: language
        )
        return [
            "language": language.rawValue,
            "screen": context.screen,
            "title": context.title,
            "summary": context.summary,
            "nextActions": context.nextActions,
            "recommendedTopicIds": context.recommendedTopicIDs,
        ]
    }

    static func onboardingChecklist(arguments: [String: Any]) -> [String: Any] {
        let language = helpLanguage(arguments)
        let checklist = VaniScriptHelpCatalog.onboardingChecklist(language: language)
        return [
            "language": language.rawValue,
            "title": checklist.title,
            "summary": checklist.summary,
            "steps": checklist.steps.enumerated().map { index, step in
                ["number": index + 1, "instruction": step] as [String: Any]
            },
            "topicIds": checklist.topicIDs,
        ]
    }

    static func listChunks(
        arguments: [String: Any],
        workflow: WorkflowState
    ) throws -> [String: Any] {
        let session = try activeSession(workflow)
        let cursor = clampedInteger(arguments["cursor"], default: 0, range: 0...Int.max)
        let limit = clampedInteger(arguments["limit"], default: 20, range: 1...100)
        let statusFilter = (arguments["status"] as? String)?.lowercased()
        let approvedFilter = arguments["approved"] as? Bool

        let filtered = session.chunks.enumerated().filter { _, chunk in
            if let statusFilter, chunk.status.rawValue != statusFilter { return false }
            if let approvedFilter, chunk.approved != approvedFilter { return false }
            return true
        }
        let start = min(cursor, filtered.count)
        let end = min(start + limit, filtered.count)
        let page = filtered[start..<end]
        return [
            "chunks": page.map { chunkSummary($0.element, arrayIndex: $0.offset) },
            "cursor": start,
            "nextCursor": end < filtered.count ? end : NSNull(),
            "hasMore": end < filtered.count,
            "totalMatching": filtered.count,
            "totalChunks": session.chunks.count,
        ]
    }

    static func getChunk(
        arguments: [String: Any],
        workflow: WorkflowState
    ) throws -> [String: Any] {
        let session = try activeSession(workflow)
        let resolved = try resolveChunk(arguments: arguments, session: session)
        let chunk = resolved.chunk
        var result = chunkSummary(chunk, arrayIndex: resolved.arrayIndex)
        result["original"] = chunk.original
        result["translated"] = chunk.translationText(for: session.selectedTranslationLanguage) ?? chunk.translated
        result["selectedTranslationLanguage"] = session.selectedTranslationLanguage ?? ""
        result["availableTranslationLanguages"] = session.availableTranslationLanguages ?? []
        result["unrecognizedFragments"] = chunk.unrecognizedFragments ?? []
        result["originalCueCount"] = chunk.originalCues?.count ?? 0
        result["translationCueCount"] = chunk.translationCues(for: session.selectedTranslationLanguage).count
        return result
    }

    static func getChunkCues(
        arguments: [String: Any],
        workflow: WorkflowState
    ) throws -> [String: Any] {
        let session = try activeSession(workflow)
        let resolved = try resolveChunk(arguments: arguments, session: session)
        let side = ((arguments["side"] as? String) ?? "original").lowercased()
        guard side == "original" || side == "translated" else {
            throw toolError(code: -2, message: "side must be original or translated")
        }

        let requestedLanguage = nonEmptyString(arguments["language"])
        let language = requestedLanguage ?? session.selectedTranslationLanguage
        let cues = side == "original"
            ? (resolved.chunk.originalCues ?? [])
            : resolved.chunk.translationCues(for: language)
        let cueItems = cues.enumerated().map { index, cue in
            [
                "cueId": cueID(chunk: resolved.chunk, side: side, index: index),
                "cueIndex": index,
                "startSec": cue.startSec,
                "endSec": cue.endSec,
                "text": cue.text,
                "wordCount": cue.words?.count ?? 0,
            ] as [String: Any]
        }
        return [
            "chunkId": chunkID(resolved.chunk),
            "displayNumber": resolved.chunk.index + 1,
            "side": side,
            "language": side == "translated" ? (language ?? "") : session.sourceLang,
            "cues": cueItems,
            "count": cueItems.count,
        ]
    }

    static func searchTranscript(
        arguments: [String: Any],
        workflow: WorkflowState
    ) throws -> [String: Any] {
        let session = try activeSession(workflow)
        guard let query = nonEmptyString(arguments["query"]), query.count <= 500 else {
            throw toolError(code: -2, message: "query is required and must contain no more than 500 characters")
        }
        let side = ((arguments["side"] as? String) ?? "all").lowercased()
        guard ["all", "original", "translated"].contains(side) else {
            throw toolError(code: -2, message: "side must be all, original, or translated")
        }
        let caseSensitive = arguments["caseSensitive"] as? Bool ?? false
        let wholeWord = arguments["wholeWord"] as? Bool ?? false
        let limit = clampedInteger(arguments["limit"], default: 50, range: 1...100)

        var matches = [[String: Any]]()
        var truncated = false
        searchLoop: for (arrayIndex, chunk) in session.chunks.enumerated() {
            let candidates: [(String, String)] = [
                ("original", chunk.original),
                ("translated", chunk.translationText(for: session.selectedTranslationLanguage) ?? chunk.translated),
            ]
            for (candidateSide, text) in candidates where side == "all" || side == candidateSide {
                for range in matchRanges(
                    query: query,
                    text: text,
                    caseSensitive: caseSensitive,
                    wholeWord: wholeWord
                ) {
                    if matches.count >= limit {
                        truncated = true
                        break searchLoop
                    }
                    matches.append([
                        "chunkId": chunkID(chunk),
                        "chunkIndex": arrayIndex,
                        "displayNumber": chunk.index + 1,
                        "side": candidateSide,
                        "startSec": chunk.startSec,
                        "endSec": chunk.endSec,
                        "matchStart": range.location,
                        "matchLength": range.length,
                        "snippet": snippet(text: text, match: range),
                    ])
                }
            }
        }

        return [
            "query": query,
            "side": side,
            "matches": matches,
            "matchCount": matches.count,
            "truncated": truncated,
            "limit": limit,
        ]
    }

    static func unrecognizedFragments(
        arguments: [String: Any],
        workflow: WorkflowState
    ) throws -> [String: Any] {
        let session = try activeSession(workflow)
        let requestedChunkID = nonEmptyString(arguments["chunkId"])
        let chunks: [(offset: Int, element: ChunkData)]
        if let requestedChunkID {
            let resolved = try resolveChunk(arguments: ["chunkId": requestedChunkID], session: session)
            chunks = [(resolved.arrayIndex, resolved.chunk)]
        } else {
            chunks = Array(session.chunks.enumerated())
        }
        let items = chunks.compactMap { arrayIndex, chunk -> [String: Any]? in
            let fragments = chunk.unrecognizedFragments ?? []
            guard !fragments.isEmpty else { return nil }
            return [
                "chunkId": chunkID(chunk),
                "chunkIndex": arrayIndex,
                "displayNumber": chunk.index + 1,
                "fragments": fragments,
                "count": fragments.count,
            ]
        }
        return [
            "chunks": items,
            "affectedChunkCount": items.count,
            "fragmentCount": items.reduce(0) { partial, item in
                partial + ((item["count"] as? Int) ?? 0)
            },
        ]
    }

    static func translationLanguages(workflow: WorkflowState) throws -> [String: Any] {
        let session = try activeSession(workflow)
        return [
            "activeLanguage": session.selectedTranslationLanguage ?? "",
            "availableLanguages": session.availableTranslationLanguages ?? [],
            "supportedLanguages": [
                "Russian", "Czech", "French", "German", "Polish", "English",
                "Hindi", "Spanish", "Swedish", "Italian", "Portuguese", "Dutch",
                "Afrikaans", "Bengali", "Bulgarian", "Croatian", "Greek", "Gujarati",
                "Hungarian", "Korean", "Norwegian", "Romanian", "Slovak", "Slovenian",
                "Telugu", "Ukrainian", "Yoruba",
            ],
            "targetLanguage": session.targetLang,
            "translationProvider": session.translationProvider,
        ]
    }
}

private extension McpReadToolService {
    struct ResolvedChunk {
        let arrayIndex: Int
        let chunk: ChunkData
    }

    static func activeSession(_ workflow: WorkflowState) throws -> SessionState {
        guard let session = workflow.session else {
            throw toolError(code: -1, message: "No active VaniScript session")
        }
        return session
    }

    static func resolveChunk(
        arguments: [String: Any],
        session: SessionState
    ) throws -> ResolvedChunk {
        if let rawID = nonEmptyString(arguments["chunkId"]) {
            guard let numericID = McpEntityIdentifier.chunkIndex(from: rawID),
                  let arrayIndex = session.chunks.firstIndex(where: { $0.index == numericID })
            else {
                throw toolError(code: -3, message: "Unknown chunkId \(rawID). Call list_chunks for valid IDs.")
            }
            return ResolvedChunk(arrayIndex: arrayIndex, chunk: session.chunks[arrayIndex])
        }

        guard let arrayIndex = McpToolArguments.wholeNumber(arguments["chunkIndex"]),
              session.chunks.indices.contains(arrayIndex)
        else {
            throw toolError(code: -2, message: "Provide chunkId from list_chunks or a valid zero-based chunkIndex.")
        }
        return ResolvedChunk(arrayIndex: arrayIndex, chunk: session.chunks[arrayIndex])
    }

    static func chunkSummary(_ chunk: ChunkData, arrayIndex: Int) -> [String: Any] {
        [
            "chunkId": chunkID(chunk),
            "chunkIndex": arrayIndex,
            "displayNumber": chunk.index + 1,
            "startSec": chunk.startSec,
            "endSec": chunk.endSec,
            "durationSec": chunk.durationSec,
            "status": chunk.status.rawValue,
            "approved": chunk.approved,
            "originalPreview": preview(chunk.original),
            "translatedPreview": preview(chunk.translated),
        ]
    }

    static func chunkID(_ chunk: ChunkData) -> String {
        McpEntityIdentifier.chunkID(chunk)
    }

    static func cueID(chunk: ChunkData, side: String, index: Int) -> String {
        McpEntityIdentifier.cueID(chunk: chunk, side: side, index: index)
    }

    static func preview(_ value: String, limit: Int = 180) -> String {
        let compact = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard compact.count > limit else { return compact }
        return String(compact.prefix(limit)) + "..."
    }

    static func helpLanguage(_ arguments: [String: Any]) -> VaniScriptHelpLanguage {
        VaniScriptHelpLanguage(rawValueOrDefault: arguments["language"] as? String)
    }

    static func helpTopicSummary(_ topic: VaniScriptLocalizedHelpTopic) -> [String: Any] {
        [
            "topicId": topic.id,
            "category": topic.category,
            "screen": topic.screen ?? "",
            "title": topic.title,
            "summary": topic.summary,
        ]
    }

    static func helpTopicDictionary(_ topic: VaniScriptLocalizedHelpTopic) -> [String: Any] {
        [
            "topicId": topic.id,
            "category": topic.category,
            "screen": topic.screen ?? "",
            "title": topic.title,
            "summary": topic.summary,
            "requirements": topic.requirements,
            "steps": topic.steps.enumerated().map { index, step in
                ["number": index + 1, "instruction": step] as [String: Any]
            },
            "troubleshooting": topic.troubleshooting,
            "relatedTopicIds": topic.relatedTopicIDs,
        ]
    }

    static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func clampedInteger(
        _ value: Any?,
        default defaultValue: Int,
        range: ClosedRange<Int>
    ) -> Int {
        guard let parsed = McpToolArguments.wholeNumber(value) else { return defaultValue }
        return min(range.upperBound, max(range.lowerBound, parsed))
    }

    static func clampedProgress(_ progress: Double) -> Double {
        max(0, min(1, progress.isFinite ? progress : 0))
    }

    static func matchRanges(
        query: String,
        text: String,
        caseSensitive: Bool,
        wholeWord: Bool
    ) -> [NSRange] {
        guard !text.isEmpty else { return [] }
        let escaped = NSRegularExpression.escapedPattern(for: query)
        let pattern = wholeWord ? "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])" : escaped
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range)
    }

    static func snippet(text: String, match: NSRange) -> String {
        let source = text as NSString
        let padding = 70
        let start = max(0, match.location - padding)
        let end = min(source.length, NSMaxRange(match) + padding)
        let raw = source.substring(with: NSRange(location: start, length: end - start))
        let compact = raw
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return (start > 0 ? "..." : "") + compact + (end < source.length ? "..." : "")
    }

    static func toolError(code: Int, message: String) -> NSError {
        NSError(
            domain: "VaniScriptMCP",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
