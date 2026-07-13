import Foundation

public struct McpGlossaryMutation {
    public var workflow: WorkflowState
    public var message: String
    public var details: [String: Any]
}

@MainActor
public enum McpGlossaryToolService {
    public static let supportedToolNames: Set<String> = [
        "list_glossary_entries",
        "search_glossary",
        "create_glossary_entry",
        "update_glossary_entry",
        "delete_glossary_entry",
        "apply_glossary_entry",
        "apply_glossary_all",
        "import_glossary",
        "export_glossary",
    ]

    public static func execute(
        name: String,
        arguments: [String: Any],
        workflow: WorkflowState,
        confirmationStore: McpConfirmationStore
    ) throws -> McpGlossaryMutation {
        switch name {
        case "list_glossary_entries":
            return list(arguments: arguments, workflow: workflow)
        case "search_glossary":
            return try search(arguments: arguments, workflow: workflow)
        case "create_glossary_entry":
            return try create(arguments: arguments, workflow: workflow)
        case "update_glossary_entry":
            return try update(arguments: arguments, workflow: workflow)
        case "delete_glossary_entry":
            return try delete(arguments: arguments, workflow: workflow, confirmationStore: confirmationStore)
        case "apply_glossary_entry":
            return try apply(arguments: arguments, workflow: workflow, confirmationStore: confirmationStore, allEntries: false)
        case "apply_glossary_all":
            return try apply(arguments: arguments, workflow: workflow, confirmationStore: confirmationStore, allEntries: true)
        case "import_glossary":
            return try importEntries(arguments: arguments, workflow: workflow)
        case "export_glossary":
            return try exportEntries(workflow: workflow)
        default:
            throw error(-4, "Unknown glossary tool \(name)")
        }
    }
}

private extension McpGlossaryToolService {
    static func list(arguments: [String: Any], workflow: WorkflowState) -> McpGlossaryMutation {
        let offset = max(0, McpToolArguments.wholeNumber(arguments["cursor"]) ?? 0)
        let limit = max(1, min(200, McpToolArguments.wholeNumber(arguments["limit"]) ?? 50))
        let category = string(arguments["category"])?.lowercased()
        let filtered = workflow.settings.glossary.filter { entry in
            category == nil || entry.category?.lowercased() == category
        }
        let page = Array(filtered.dropFirst(offset).prefix(limit))
        return unchanged(
            workflow,
            message: "Listed \(page.count) glossary entries",
            details: [
                "entries": page.map(dictionary),
                "cursor": offset,
                "nextCursor": offset + page.count,
                "hasMore": offset + page.count < filtered.count,
                "total": filtered.count,
            ]
        )
    }

    static func search(arguments: [String: Any], workflow: WorkflowState) throws -> McpGlossaryMutation {
        guard let query = string(arguments["query"]), query.count <= 300 else {
            throw error(-2, "query is required and must contain no more than 300 characters")
        }
        let limit = max(1, min(100, McpToolArguments.wholeNumber(arguments["limit"]) ?? 30))
        let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let entries = workflow.settings.glossary.filter { entry in
            ([entry.source, entry.translation, entry.category ?? ""] + entry.variants + Array(entry.translations.values))
                .contains { value in
                    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(needle)
                }
        }.prefix(limit)
        return unchanged(
            workflow,
            message: "Found \(entries.count) glossary entries",
            details: ["entries": entries.map(dictionary), "query": query]
        )
    }

    static func create(arguments: [String: Any], workflow: WorkflowState) throws -> McpGlossaryMutation {
        var updated = workflow
        let entry = try decodedEntry(arguments, existing: nil)
        guard !updated.settings.glossary.contains(where: { $0.id == entry.id }) else {
            throw error(-2, "Glossary entry id already exists")
        }
        updated.settings.glossary.append(entry)
        return changed(updated, message: "Created glossary entry", details: ["entry": dictionary(entry)])
    }

    static func update(arguments: [String: Any], workflow: WorkflowState) throws -> McpGlossaryMutation {
        var updated = workflow
        guard let entryID = string(arguments["entryId"]),
              let index = updated.settings.glossary.firstIndex(where: { $0.id == entryID }) else {
            throw error(-3, "Unknown glossary entryId")
        }
        let entry = try decodedEntry(arguments, existing: updated.settings.glossary[index])
        updated.settings.glossary[index] = entry
        return changed(updated, message: "Updated glossary entry", details: ["entry": dictionary(entry)])
    }

    static func delete(
        arguments: [String: Any],
        workflow: WorkflowState,
        confirmationStore: McpConfirmationStore
    ) throws -> McpGlossaryMutation {
        guard let entryID = string(arguments["entryId"]),
              let index = workflow.settings.glossary.firstIndex(where: { $0.id == entryID }) else {
            throw error(-3, "Unknown glossary entryId")
        }
        let revision = McpProjectRevision.make(workflow: workflow)
        let dryRun = arguments["dryRun"] as? Bool ?? true
        if dryRun {
            let token = confirmationStore.issue(
                operation: "delete_glossary_entry",
                fingerprint: entryID,
                projectRevision: revision
            )
            return unchanged(
                workflow,
                message: "Previewed glossary entry deletion",
                details: [
                    "dryRun": true,
                    "entry": dictionary(workflow.settings.glossary[index]),
                    "confirmationToken": token,
                    "confirmationExpiresInSec": 120,
                ]
            )
        }
        try consumeConfirmation(
            arguments: arguments,
            operation: "delete_glossary_entry",
            fingerprint: entryID,
            revision: revision,
            store: confirmationStore
        )
        var updated = workflow
        let removed = updated.settings.glossary.remove(at: index)
        return changed(updated, message: "Deleted glossary entry", details: ["entryId": removed.id])
    }

    static func apply(
        arguments: [String: Any],
        workflow: WorkflowState,
        confirmationStore: McpConfirmationStore,
        allEntries: Bool
    ) throws -> McpGlossaryMutation {
        guard workflow.session != nil else { throw error(-1, "No active VaniScript session") }
        let entries: [GlossaryEntry]
        if allEntries {
            entries = workflow.settings.glossary
        } else {
            guard let entryID = string(arguments["entryId"]),
                  let entry = workflow.settings.glossary.first(where: { $0.id == entryID }) else {
                throw error(-3, "Unknown glossary entryId")
            }
            entries = [entry]
        }
        guard !entries.isEmpty else { throw error(-3, "The glossary is empty") }

        let scope = string(arguments["scope"]) ?? "currentChunk"
        guard ["currentChunk", "selectedChunks", "project"].contains(scope) else {
            throw error(-2, "scope must be currentChunk, selectedChunks, or project")
        }
        let side = string(arguments["side"]) ?? "both"
        guard ["source", "translation", "both"].contains(side) else {
            throw error(-2, "side must be source, translation, or both")
        }
        let chunkIDs = (arguments["chunkIds"] as? [String]) ?? []
        if scope == "selectedChunks", chunkIDs.isEmpty {
            throw error(-2, "chunkIds is required for selectedChunks scope")
        }

        var previewWorkflow = workflow
        let summary = try rewrite(
            workflow: &previewWorkflow,
            entries: entries,
            scope: scope,
            side: side,
            chunkIDs: Set(chunkIDs)
        )
        let revision = McpProjectRevision.make(workflow: workflow)
        let operation = allEntries ? "apply_glossary_all" : "apply_glossary_entry"
        let fingerprint = ([operation, scope, side] + entries.map(\.id).sorted() + chunkIDs.sorted()).joined(separator: "\u{1f}")
        let dryRun = arguments["dryRun"] as? Bool ?? true
        if dryRun {
            let token = confirmationStore.issue(operation: operation, fingerprint: fingerprint, projectRevision: revision)
            return unchanged(
                workflow,
                message: "Previewed \(summary.replacementCount) glossary replacement(s)",
                details: [
                    "dryRun": true,
                    "replacementCount": summary.replacementCount,
                    "affectedChunkIds": summary.affectedChunkIDs,
                    "confirmationToken": token,
                    "confirmationExpiresInSec": 120,
                ]
            )
        }
        try consumeConfirmation(
            arguments: arguments,
            operation: operation,
            fingerprint: fingerprint,
            revision: revision,
            store: confirmationStore
        )
        return changed(
            previewWorkflow,
            message: "Applied \(summary.replacementCount) glossary replacement(s)",
            details: [
                "replacementCount": summary.replacementCount,
                "affectedChunkIds": summary.affectedChunkIDs,
            ]
        )
    }

    static func importEntries(arguments: [String: Any], workflow: WorkflowState) throws -> McpGlossaryMutation {
        guard let rawEntries = arguments["entries"] as? [[String: Any]], !rawEntries.isEmpty, rawEntries.count <= 5_000 else {
            throw error(-2, "entries must contain between 1 and 5,000 glossary objects")
        }
        var updated = workflow
        var entriesByID = Dictionary(uniqueKeysWithValues: updated.settings.glossary.map { ($0.id, $0) })
        var imported = 0
        for rawEntry in rawEntries {
            let candidate = try decodedEntry(rawEntry, existing: rawEntry["id"].flatMap { entriesByID[$0 as? String ?? ""] })
            entriesByID[candidate.id] = candidate
            imported += 1
        }
        updated.settings.glossary = entriesByID.values.sorted {
            $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending
        }
        return changed(updated, message: "Imported \(imported) glossary entries", details: ["importedCount": imported])
    }

    static func exportEntries(workflow: WorkflowState) throws -> McpGlossaryMutation {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(workflow.settings.glossary)
        let json = String(decoding: data, as: UTF8.self)
        return unchanged(
            workflow,
            message: "Prepared \(workflow.settings.glossary.count) glossary entries",
            details: [
                "fileName": "vaniscript-glossary.json",
                "mimeType": "application/json",
                "entryCount": workflow.settings.glossary.count,
                "json": json,
            ]
        )
    }

    struct RewriteSummary {
        var replacementCount = 0
        var affectedChunkIDs: [String] = []
    }

    static func rewrite(
        workflow: inout WorkflowState,
        entries: [GlossaryEntry],
        scope: String,
        side: String,
        chunkIDs: Set<String>
    ) throws -> RewriteSummary {
        guard var session = workflow.session else { throw error(-1, "No active VaniScript session") }
        var summary = RewriteSummary()
        for index in session.chunks.indices {
            let chunkID = McpEntityIdentifier.chunkID(session.chunks[index])
            let included: Bool
            switch scope {
            case "currentChunk": included = index == session.currentChunkIndex
            case "selectedChunks": included = chunkIDs.contains(chunkID)
            default: included = true
            }
            guard included else { continue }
            let count = rewrite(chunk: &session.chunks[index], entries: entries, side: side)
            if count > 0 {
                summary.replacementCount += count
                summary.affectedChunkIDs.append(chunkID)
                session.chunks[index].status = .done
            }
        }
        if scope == "selectedChunks" {
            let known = Set(session.chunks.map(McpEntityIdentifier.chunkID))
            let unknown = chunkIDs.subtracting(known)
            if !unknown.isEmpty { throw error(-3, "Unknown chunkId: \(unknown.sorted().joined(separator: ", "))") }
        }
        workflow.session = session
        return summary
    }

    static func rewrite(chunk: inout ChunkData, entries: [GlossaryEntry], side: String) -> Int {
        var total = 0
        if side != "translation" {
            let text = GlossaryTextRewriter.apply(to: chunk.original, entries: entries, target: .source)
            chunk.original = text.text
            total += text.count
            if let cues = chunk.originalCues {
                let result = GlossaryTextRewriter.apply(to: cues, entries: entries, target: .source)
                chunk.originalCues = result.0
                if result.1 > 0 { chunk.original = result.0.map(\.text).joined(separator: " ") }
                total += result.1
            }
            if let formats = chunk.originalFormats {
                chunk.originalFormats = rewrite(formats: formats, entries: entries, target: .source, total: &total)
            }
        }
        if side != "source" {
            let text = GlossaryTextRewriter.apply(to: chunk.translated, entries: entries, target: .translation)
            chunk.translated = text.text
            total += text.count
            if let formats = chunk.translatedFormats {
                chunk.translatedFormats = rewrite(formats: formats, entries: entries, target: .translation, total: &total)
            }
            if var archive = chunk.translationsByLanguage {
                for key in archive.keys {
                    guard var variant = archive[key] else { continue }
                    let result = GlossaryTextRewriter.apply(to: variant.text, entries: entries, target: .translation)
                    variant.text = result.text
                    total += result.count
                    if let cues = variant.cues {
                        let cueResult = GlossaryTextRewriter.apply(to: cues, entries: entries, target: .translation)
                        variant.cues = cueResult.0
                        if cueResult.1 > 0 { variant.text = cueResult.0.map(\.text).joined(separator: "\n") }
                        total += cueResult.1
                    }
                    if let formats = variant.formats {
                        variant.formats = rewrite(formats: formats, entries: entries, target: .translation, total: &total)
                    }
                    variant.updatedAt = timestamp()
                    archive[key] = variant
                }
                chunk.translationsByLanguage = archive
            }
        }
        return total
    }

    static func rewrite(
        formats: LanguageResult,
        entries: [GlossaryEntry],
        target: GlossaryTextRewriter.Target,
        total: inout Int
    ) -> LanguageResult {
        var copy = formats
        for keyPath in [\LanguageResult.txt, \.srt, \.vtt, \.markdown] {
            guard let value = copy[keyPath: keyPath] else { continue }
            let result = GlossaryTextRewriter.apply(to: value, entries: entries, target: target)
            copy[keyPath: keyPath] = result.text
            total += result.count
        }
        return copy
    }

    static func decodedEntry(_ values: [String: Any], existing: GlossaryEntry?) throws -> GlossaryEntry {
        let source = string(values["source"]) ?? existing?.source ?? ""
        guard !source.isEmpty, source.count <= 500 else {
            throw error(-2, "source is required and must contain no more than 500 characters")
        }
        let translation = (values["translation"] as? String) ?? existing?.translation ?? source
        guard translation.count <= 2_000 else { throw error(-2, "translation is too long") }
        let variants = normalizedVariants(values["variants"] as? [String] ?? existing?.variants ?? [source])
        guard variants.count <= 100 else { throw error(-2, "variants may contain no more than 100 values") }
        let rawTranslations = values["translations"] as? [String: Any]
        let translations = rawTranslations?.reduce(into: [String: String]()) { result, item in
            if let value = item.value as? String, !item.key.isEmpty, value.count <= 2_000 {
                result[item.key] = value
            }
        } ?? existing?.translations ?? [:]
        let now = timestamp()
        return GlossaryEntry(
            id: string(values["id"]) ?? existing?.id ?? UUID().uuidString.lowercased(),
            variants: variants,
            source: source,
            translation: translation,
            category: (values["category"] as? String) ?? existing?.category,
            translations: translations,
            remember: values["remember"] as? Bool ?? existing?.remember ?? true,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }

    static func normalizedVariants(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = clean.lowercased()
            guard !clean.isEmpty, clean.count <= 500, seen.insert(key).inserted else { return nil }
            return clean
        }
    }

    static func consumeConfirmation(
        arguments: [String: Any],
        operation: String,
        fingerprint: String,
        revision: String,
        store: McpConfirmationStore
    ) throws {
        guard string(arguments["expectedRevision"]) == revision else {
            throw error(-6, "STALE_REVISION: Apply requires the revision returned by the preview.")
        }
        guard let token = string(arguments["confirmationToken"]),
              store.consume(token: token, operation: operation, fingerprint: fingerprint, projectRevision: revision) else {
            throw error(-7, "CONFIRMATION_REQUIRED: Run the same operation with dryRun=true and use its unexpired confirmationToken.")
        }
    }

    static func dictionary(_ entry: GlossaryEntry) -> [String: Any] {
        [
            "id": entry.id,
            "variants": entry.variants,
            "source": entry.source,
            "translation": entry.translation,
            "category": entry.category ?? "",
            "translations": entry.translations,
            "remember": entry.remember,
            "createdAt": entry.createdAt,
            "updatedAt": entry.updatedAt,
        ]
    }

    static func unchanged(_ workflow: WorkflowState, message: String, details: [String: Any]) -> McpGlossaryMutation {
        McpGlossaryMutation(workflow: workflow, message: message, details: details)
    }

    static func changed(_ workflow: WorkflowState, message: String, details: [String: Any]) -> McpGlossaryMutation {
        McpGlossaryMutation(workflow: workflow, message: message, details: details)
    }

    static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    static func error(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "McpGlossaryToolService", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
