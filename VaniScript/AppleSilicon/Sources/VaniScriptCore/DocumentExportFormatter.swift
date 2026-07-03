import Foundation

public enum DocumentExportFormatter {
    public static func sanitizeDocumentExportOutput(_ rawText: String) -> String {
        var text = rawText
            .replacingRegex(#"(?is)<think>.*?</think>"#)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let marked = text.firstRegexCapture(#"(?is)<<<DOCUMENT>>>\s*(.*?)(?:<<<END>>>|$)"#) {
            text = marked.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        text = text
            .replacingRegex(#"(?i)^```(?:markdown|md|srt|vtt|txt|text)?\s*"#)
            .replacingRegex(#"(?s)\s*```$"#)
            .replacingRegex(#"(?i)^\s*(?:Here is|Here's|Below is)[^\n]*:\s*"#)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }

    public static func buildDocumentExportPrompt(
        format: OutputFormat,
        targetLang: String,
        text: String,
        subtitleMaxCharsPerLine: Int = 42,
        subtitleMaxLines: Int = 2
    ) -> String {
        switch format {
        case .markdown:
            return """
            You are a formatting editor. Create a polished \(targetLang) Markdown document from the prepared transcript below.

            Hard rules:
            1. Do not rewrite, paraphrase, summarize, correct, remove, or add transcript content.
            2. Preserve the transcript text exactly, except removing timestamp markers if present.
            3. You may add Markdown structure only: title, metadata block, table of contents, section headings, bold emphasis for short labels, horizontal rules, and paragraph breaks.
            4. Divide the document by meaning. Section headings must describe the actual topic of the section, not merely copy the first sentence.
            5. Preserve all metadata at the top and localize metadata labels to the document language.
            6. Return only the Markdown document. No notes or explanations.

            For Russian Markdown use Russian labels such as "Дата", "Место", "Лектор", "Интервьюер / Участники", and "Содержание".

            <<<TRANSCRIPT>>>
            \(text)
            <<<DOCUMENT>>>
            """
        case .srt, .vtt:
            return """
            You are a professional subtitle formatter. Format the prepared transcript as valid \(format.rawValue).

            Hard rules:
            1. Do not rewrite, paraphrase, translate, correct, remove, or add spoken text.
            2. Keep timings accurate and monotonic. Preserve the provided timing boundaries as closely as possible.
            3. Prefer no more than \(subtitleMaxCharsPerLine) characters per line and no more than \(subtitleMaxLines) lines per subtitle cue.
            4. Break subtitles at natural phrase boundaries.
            5. Do not split proper names, titles, Sanskrit terms, or devotional names across subtitle cues or lines when avoidable.
            6. If a phrase would read badly when split, make the cue slightly shorter or longer rather than splitting the phrase awkwardly.
            7. Return only valid \(format.rawValue). No notes, no markdown fences, no explanations.

            <<<TRANSCRIPT>>>
            \(text)
            <<<\(format.rawValue)>>>
            """
        case .txt:
            return text
        }
    }

    public static func buildLocalMarkdownPartPrompt(
        text: String,
        targetLang: String,
        partIndex: Int,
        totalParts: Int
    ) -> String {
        """
        You are formatting part \(partIndex + 1) of \(totalParts) of a \(targetLang) Markdown document.

        Hard rules:
        1. Return only Markdown body sections for this fragment.
        2. Do not include document title, metadata, table of contents, "Содержание", "Contents", or horizontal rules.
        3. Do not rewrite, paraphrase, summarize, correct, remove, or add transcript content.
        4. Remove timestamp markers if present.
        5. Add only meaningful section headings and paragraph breaks.
        6. If the fragment continues a previous topic, use a continuation heading only when it is genuinely needed.
        7. No notes, no explanations, no markdown fences.

        <<<TRANSCRIPT_FRAGMENT>>>
        \(text)
        <<<DOCUMENT_PART>>>
        """
    }

    public static func splitDocumentExportInput(
        _ text: String,
        format: OutputFormat,
        maxChars: Int = 3_500
    ) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        switch format {
        case .srt:
            return splitBlocks(normalized, maxChars: maxChars)
        case .vtt:
            let body = normalized
                .replacingRegex(#"(?i)^WEBVTT\s*\n+"#)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return splitBlocks(body, maxChars: maxChars).map { "WEBVTT\n\n\($0)" }
        case .markdown:
            return splitBlocks(normalized, maxChars: maxChars)
        case .txt:
            return [normalized]
        }
    }

    public static func localDocumentBatchLimit(format: OutputFormat) -> Int {
        switch format {
        case .markdown:
            return 6_000
        case .srt, .vtt:
            return 4_500
        case .txt:
            return 12_000
        }
    }

    public static func combineDocumentExportParts(
        _ parts: [String],
        format: OutputFormat
    ) -> String {
        let cleaned = parts.map(sanitizeDocumentExportOutput).filter { !$0.isEmpty }

        switch format {
        case .srt:
            let cues = cleaned.flatMap {
                $0.components(separatedByRegex: #"\n{2,}"#)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            return cues.enumerated().map { index, cue in
                var lines = cue.components(separatedBy: "\n")
                if let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^\d+$"#, options: .regularExpression) != nil {
                    lines.removeFirst()
                }
                return ([String(index + 1)] + lines).joined(separator: "\n")
            }.joined(separator: "\n\n")
        case .vtt:
            let cues = cleaned
                .map { $0.replacingRegex(#"(?i)^WEBVTT\s*\n+"#).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            return cues.isEmpty ? "WEBVTT" : "WEBVTT\n\n\(cues)"
        case .markdown, .txt:
            return cleaned
                .joined(separator: "\n\n")
                .replacingRegex(#"\n{4,}"#, with: "\n\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public static func combineLocalMarkdownParts(
        parts: [String],
        sourceDocument: String,
        targetLang: String
    ) -> String {
        let shell = extractMarkdownShell(sourceDocument, targetLang: targetLang)
        let body = mergeMarkdownBodyParts(parts)
        let toc = markdownTOC(body: body, targetLang: targetLang)

        return [shell.title, shell.metadata, "---", toc, body]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .replacingRegex(#"\n{4,}"#, with: "\n\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func stripMarkdownDocumentShell(_ markdown: String) -> String {
        cleanMarkdownBody(markdown, sanitizeFirst: false)
    }

    public static func sanitizeLocalMarkdownBodyPart(_ rawText: String) -> String {
        cleanMarkdownBody(sanitizeDocumentExportOutput(rawText), sanitizeFirst: false)
    }

    private static func splitBlocks(_ text: String, maxChars: Int) -> [String] {
        let blocks = text
            .components(separatedByRegex: #"\n{2,}"#)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var batches: [String] = []
        var current = ""

        for block in blocks {
            for part in splitOversizedBlock(block, maxChars: maxChars) {
                let next = current.isEmpty ? part : "\(current)\n\n\(part)"
                if next.count <= maxChars {
                    current = next
                } else {
                    if !current.isEmpty { batches.append(current) }
                    current = part
                }
            }
        }

        if !current.isEmpty { batches.append(current) }
        return batches.isEmpty ? [text] : batches
    }

    private static func splitOversizedBlock(_ block: String, maxChars: Int) -> [String] {
        guard block.count > maxChars else { return [block] }

        let units = block
            .components(separatedByRegex: #"(?<=[.!?…。！？])\s+|\n+"#)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard units.count > 1 else {
            return stride(from: 0, to: block.count, by: maxChars).map { offset in
                let start = block.index(block.startIndex, offsetBy: offset)
                let end = block.index(start, offsetBy: min(maxChars, block.distance(from: start, to: block.endIndex)))
                return String(block[start..<end])
            }
        }

        var parts: [String] = []
        var current = ""
        for unit in units {
            if unit.count > maxChars {
                if !current.isEmpty {
                    parts.append(current)
                    current = ""
                }
                parts.append(contentsOf: splitOversizedBlock(unit, maxChars: maxChars))
                continue
            }

            let next = current.isEmpty ? unit : "\(current) \(unit)"
            if next.count <= maxChars {
                current = next
            } else {
                if !current.isEmpty { parts.append(current) }
                current = unit
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    private static func mergeMarkdownBodyParts(_ parts: [String]) -> String {
        var blocks: [String] = []
        for part in parts.map(sanitizeLocalMarkdownBodyPart).filter({ !$0.isEmpty }) {
            for block in part.components(separatedByRegex: #"\n{2,}"#).map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
                if let previous = blocks.last, normalizedBlock(previous) == normalizedBlock(block) {
                    continue
                }
                blocks.append(block)
            }
        }
        return blocks.joined(separator: "\n\n")
            .replacingRegex(#"\n{3,}"#, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedBlock(_ block: String) -> String {
        block
            .replacingRegex(#"^#+\s*"#)
            .replacingRegex(#"^\d+\.\s*"#)
            .replacingRegex(#"\s+"#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func extractMarkdownShell(_ markdown: String, targetLang: String) -> (title: String, metadata: String) {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let title = lines.first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# ") })?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "# \(defaultMarkdownTitle(targetLang))"
        let metadata = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(isMarkdownMetadataLine)
            .reduce(into: [String]()) { result, line in
                if !result.contains(line) { result.append(line) }
            }
            .joined(separator: "\n")
        return (title, metadata)
    }

    private static func cleanMarkdownBody(_ markdown: String, sanitizeFirst: Bool) -> String {
        let source = sanitizeFirst ? sanitizeDocumentExportOutput(markdown) : markdown
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var body: [String] = []
        var skippingContents = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.range(of: #"^#\s+"#, options: .regularExpression) != nil { continue }
            if trimmed.range(of: #"^---+$"#, options: .regularExpression) != nil { continue }
            if isMarkdownMetadataLine(trimmed) { continue }
            if isContentsHeading(trimmed) {
                skippingContents = true
                continue
            }
            if skippingContents {
                if trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) != nil {
                    skippingContents = false
                } else {
                    continue
                }
            }
            body.append(line)
        }

        return body.joined(separator: "\n")
            .replacingRegex(#"\n{3,}"#, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func markdownTOC(body: String, targetLang: String) -> String {
        let headings = body
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.range(of: #"^##\s+"#, options: .regularExpression) != nil && !isContentsHeading($0) }
            .map { $0.replacingRegex(#"^##\s+"#).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !headings.isEmpty else { return "" }
        let items = headings.enumerated()
            .map { index, heading in "\(index + 1). \(heading.replacingRegex(#"^\d+\.\s*"#))" }
            .joined(separator: "\n")
        return "## \(markdownContentsTitle(targetLang))\n\n\(items)"
    }

    private static func isMarkdownMetadataLine(_ line: String) -> Bool {
        line.range(
            of: #"^\s*(?:\*\*)?(?:Date|Location|Lecturer|Interviewer / Participants|Дата|Место|Лектор|Интервьюер / Участники)(?:\*\*)?\s*:"#,
            options: .regularExpression
        ) != nil
    }

    private static func isContentsHeading(_ line: String) -> Bool {
        line.range(of: #"^#{1,3}\s+(?:Содержание|Contents)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func markdownContentsTitle(_ targetLang: String) -> String {
        isRussianTarget(targetLang) ? "Содержание" : "Contents"
    }

    private static func defaultMarkdownTitle(_ targetLang: String) -> String {
        isRussianTarget(targetLang) ? "Транскрипция" : "Transcript"
    }

    private static func isRussianTarget(_ targetLang: String) -> Bool {
        targetLang.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^(ru|rus|russian|русский|русский язык)$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

private extension String {
    func replacingRegex(
        _ pattern: String,
        with replacement: String = "",
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return self }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: replacement)
    }

    func firstRegexCapture(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: range), match.numberOfRanges > 1 else {
            return nil
        }
        guard let captureRange = Range(match.range(at: 1), in: self) else { return nil }
        return String(self[captureRange])
    }

    func components(separatedByRegex pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [self] }
        let range = NSRange(startIndex..<endIndex, in: self)
        var lastEnd = startIndex
        var parts: [String] = []
        for match in regex.matches(in: self, options: [], range: range) {
            guard let matchRange = Range(match.range, in: self) else { continue }
            parts.append(String(self[lastEnd..<matchRange.lowerBound]))
            lastEnd = matchRange.upperBound
        }
        parts.append(String(self[lastEnd..<endIndex]))
        return parts
    }
}
