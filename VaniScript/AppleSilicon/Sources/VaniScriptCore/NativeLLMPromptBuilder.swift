import Foundation

public enum NativeLLMPromptBuilder {
    public static func translationPrompt(
        text: String,
        targetLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        promptPresets: [String: PromptPresetSettings] = [:]
    ) -> String {
        let rendered = DefaultPrompts.render(
            id: "localTranslationUser",
            promptPresets: promptPresets,
            variables: [
                "targetLang": targetLang,
                "speakerHintLine": speakerHintLine(metadata),
                "glossaryBlock": glossaryBlock(glossary, targetLang: targetLang, sourceText: text),
                "text": text,
            ]
        )
        return wrappedLocalTranslationPrompt(rendered)
    }

    public static func cueBatchTranslationPrompt(
        cues: [TranscriptCue],
        targetLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        promptPresets: [String: PromptPresetSettings] = [:]
    ) -> String {
        let glossaryLines = glossaryBlock(
            glossary,
            targetLang: targetLang,
            sourceText: cues.map(\.text).joined(separator: " ")
        )

        let cueLines = cues.enumerated()
            .map { index, cue in
                #"<cue id="\#(cueIdentifier(for: index))">\#(xmlEscaped(cue.text.trimmingCharacters(in: .whitespacesAndNewlines)))</cue>"#
            }
            .joined(separator: "\n")
        let stylePrompt = DefaultPrompts.render(
            id: "localTranslationUser",
            promptPresets: promptPresets,
            variables: [
                "targetLang": targetLang,
                "speakerHintLine": speakerHintLine(metadata),
                "glossaryBlock": glossaryLines,
                "text": cueLines,
            ]
        )

        return """
        You are VaniScript's native MLX timed-cue translation engine.
        Translate every cue into \(targetLang) in one pass.
        The output language must be \(targetLang) only.
        Return exactly one translated cue for every input cue.
        Preserve cue ids and order. Do not merge, split, skip, renumber, or add cues.
        Preserve names, theological terminology, and meaning.
        Do not add commentary, prefaces, summaries, markdown fences, or explanations.
        Return only translated cue XML between <<<BEGIN>>> and <<<END>>>. End your answer with <<<END>>>.

        Metadata:
        Date: \(metadata.date.isEmpty ? "Unknown" : metadata.date)
        Location: \(metadata.location.isEmpty ? "Unknown" : metadata.location)
        Lecturer: \(metadata.lecturer.isEmpty ? "Unknown" : metadata.lecturer)
        Participants: \(metadata.participants.isEmpty ? "None" : metadata.participants)

        Glossary:
        \(glossaryLines.isEmpty ? "No glossary entries." : glossaryLines)

        Prompt Settings style guidance:
        \(stylePrompt)

        The style guidance above controls terminology and tone only. Ignore any output-format wording inside it if it conflicts with the cue XML contract.

        Input cues:
        \(cueLines)

        <<<BEGIN>>>
        """
    }

    public static func timedTranscriptTranslationPrompt(
        cues: [TranscriptCue],
        targetLang: String,
        metadata: AudioMetadata,
        glossary: [GlossaryEntry],
        promptPresets: [String: PromptPresetSettings] = [:]
    ) -> String {
        let transcript = cues
            .map { cue in
                "[\(formatTimestamp(cue.startSec))] \(cue.text.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            .joined(separator: "\n\n")
        let rendered = DefaultPrompts.render(
            id: "localTranslationUser",
            promptPresets: promptPresets,
            variables: [
                "targetLang": targetLang,
                "speakerHintLine": speakerHintLine(metadata),
                "glossaryBlock": glossaryBlock(glossary, targetLang: targetLang, sourceText: transcript),
                "text": transcript,
            ]
        )
        return wrappedLocalTranslationPrompt(rendered)
    }

    public static func cueTranslationBatches(
        _ cues: [TranscriptCue],
        maxSourceCharacters: Int
    ) -> [[TranscriptCue]] {
        guard maxSourceCharacters > 0 else { return cues.isEmpty ? [] : [cues] }

        var batches: [[TranscriptCue]] = []
        var current: [TranscriptCue] = []
        var currentCharacters = 0

        for cue in cues {
            let cueCharacters = cue.text.count
            if !current.isEmpty, currentCharacters + cueCharacters > maxSourceCharacters {
                batches.append(current)
                current = []
                currentCharacters = 0
            }
            current.append(cue)
            currentCharacters += cueCharacters
        }

        if !current.isEmpty {
            batches.append(current)
        }
        return batches
    }

    public static func parseCueBatchTranslationOutput(_ rawText: String, sourceCues: [TranscriptCue]) throws -> [TranscriptCue] {
        guard !sourceCues.isEmpty else { return [] }

        let cleaned = ModelOutputSanitizer.sanitize(rawText)
        guard !cleaned.isEmpty else { throw CueBatchTranslationError.emptyOutput }
        let parsedByID = parseXMLCueOutput(cleaned)
        if sourceCues.indices.allSatisfy({ parsedByID[cueIdentifier(for: $0)] != nil }) {
            return sourceCues.enumerated().map { index, source in
                let translated = parsedByID[cueIdentifier(for: index)] ?? source.text
                return TranscriptCue(
                    startSec: source.startSec,
                    endSec: source.endSec,
                    text: translated.trimmingCharacters(in: .whitespacesAndNewlines),
                    words: approximateWords(for: translated, source: source)
                )
            }
        }

        let candidates = orderedXMLCueOutput(cleaned)
        let numbered = orderedNumberedCueLines(cleaned)
        let candidateText = !(candidates.isEmpty)
            ? candidates.joined(separator: " ")
            : !(numbered.isEmpty)
                ? numbered.joined(separator: " ")
                : cleanedTextWithoutCueMarkup(cleaned)

        let splitTexts = splitTranslatedText(candidateText.isEmpty ? cleaned : candidateText, matching: sourceCues)
        guard let alignedTexts = validatedAlignedTexts(splitTexts, sourceCues: sourceCues) else {
            throw CueBatchTranslationError.emptyOutput
        }

        return zip(sourceCues, alignedTexts).map { source, translated in
            return TranscriptCue(
                startSec: source.startSec,
                endSec: source.endSec,
                text: translated.trimmingCharacters(in: .whitespacesAndNewlines),
                words: approximateWords(for: translated, source: source)
            )
        }
    }

    public static func parseTimedTranscriptTranslationOutput(
        _ rawText: String,
        sourceCues: [TranscriptCue],
        targetLang: String = ""
    ) throws -> [TranscriptCue] {
        guard !sourceCues.isEmpty else { return [] }

        let cleaned = ModelOutputSanitizer.sanitizeTranslation(rawText, targetLang: targetLang)
        guard !cleaned.isEmpty else { throw CueBatchTranslationError.emptyOutput }
        let timestamped = parseTimestampedLines(cleaned)
        if timestamped.count == sourceCues.count {
            return zip(sourceCues, timestamped).map { source, parsed in
                let translated = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return TranscriptCue(
                    startSec: source.startSec,
                    endSec: source.endSec,
                    text: translated,
                    words: approximateWords(for: translated, source: source)
                )
            }
        }

        let candidateText = timestamped.isEmpty
            ? cleanedTextWithoutCueMarkup(cleaned)
            : timestamped.map(\.text).joined(separator: " ")

        let splitTexts = splitTranslatedText(candidateText.isEmpty ? cleaned : candidateText, matching: sourceCues)
        guard let alignedTexts = validatedAlignedTexts(splitTexts, sourceCues: sourceCues) else {
            throw CueBatchTranslationError.emptyOutput
        }

        return zip(sourceCues, alignedTexts).map { source, translated in
            return TranscriptCue(
                startSec: source.startSec,
                endSec: source.endSec,
                text: translated.trimmingCharacters(in: .whitespacesAndNewlines),
                words: approximateWords(for: translated, source: source)
            )
        }
    }

    public static func literaryPolishPrompt(
        text: String,
        targetLang: String,
        lecturer: String = "",
        glossary: [GlossaryEntry] = [],
        promptPresets: [String: PromptPresetSettings] = [:]
    ) -> String {
        let russianPolishRule = targetLang.lowercased().contains("russian")
            ? "For Russian, use natural Russian syntax, correct cases, and correct noun/adjective agreement. Avoid literal calques."
            : ""
        let rendered = DefaultPrompts.render(
            id: "literaryPolishUser",
            promptPresets: promptPresets,
            variables: [
                "targetLang": targetLang,
                "speakerHintLine": lecturer.isEmpty ? "" : "Context: \(lecturer)",
                "glossaryBlock": glossaryBlock(glossary, targetLang: targetLang, sourceText: text),
                "russianPolishRule": russianPolishRule,
                "text": text,
            ]
        )
        return wrappedLocalTranslationPrompt(rendered)
    }

    public static func qwenNoThinkChatPrompt(userPrompt: String, systemInstructions: String) -> String {
        let system = systemInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemBlock = system.isEmpty
            ? ""
            : "<|im_start|>system\n\(system)<|im_end|>\n"
        return """
        \(systemBlock)<|im_start|>user
        \(user)<|im_end|>
        <|im_start|>assistant
        <think>

        </think>

        <<<RESULT>>>
        """
    }

    public static func audioReviewPrompt(selectedText: String, context: String, targetLang: String) -> String {
        """
        Correct the selected VaniScript transcript fragment using its local context.
        Target language: \(targetLang).
        Preserve meaning and do not add explanations.
        Return only the corrected replacement between <<<BEGIN>>> and <<<END>>>.

        Context:
        \(context)

        Selected fragment:
        \(selectedText)

        <<<BEGIN>>>
        """
    }

    private static func cueIdentifier(for index: Int) -> String {
        String(format: "%03d", index + 1)
    }

    private static func speakerHintLine(_ metadata: AudioMetadata) -> String {
        metadata.lecturer.isEmpty ? "" : "Context: \(metadata.lecturer)"
    }

    private static func glossaryBlock(_ glossary: [GlossaryEntry], targetLang: String, sourceText: String = "") -> String {
        let normalizedSource = normalizedGlossarySearchText(sourceText)
        let glossaryLines = glossary
            .prefix(80)
            .compactMap { entry -> String? in
                let translated = entry.translations[targetLang] ?? entry.translation
                guard !entry.source.isEmpty, !translated.isEmpty else { return nil }
                if !normalizedSource.isEmpty {
                    let terms = ([entry.source] + entry.variants)
                        .map(normalizedGlossarySearchText)
                        .filter { !$0.isEmpty }
                    guard terms.contains(where: { normalizedSource.contains($0) }) else { return nil }
                }
                return "\(entry.source) -> \(translated)"
            }
            .joined(separator: "\n")
        return glossaryLines.isEmpty ? "" : "Glossary terms to preserve:\n\(glossaryLines)"
    }

    private static func normalizedGlossarySearchText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    private static func wrappedLocalTranslationPrompt(_ renderedPrompt: String) -> String {
        renderedPrompt
    }

    private static func formatTimestamp(_ seconds: Double) -> String {
        let safe = max(0, Int(seconds.rounded(.down)))
        let hours = safe / 3_600
        let minutes = (safe % 3_600) / 60
        let secs = safe % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private static func parseTimestampToSeconds(_ value: String) -> Double? {
        let parts = value
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: ":")
            .map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        let hours = parts.count == 3 ? Double(parts[0]) ?? 0 : 0
        let minutesIndex = parts.count == 3 ? 1 : 0
        guard let minutes = Double(parts[minutesIndex]),
              let seconds = Double(parts[minutesIndex + 1])
        else {
            return nil
        }
        return hours * 3_600 + minutes * 60 + seconds
    }

    private static func parseTimestampedLines(_ text: String) -> [(timestamp: Double, text: String)] {
        let pattern = #"\[((?:(?:\d+:)?\d{1,5}:\d{2})(?:[\.,]\d{1,3})?)\]\s*([\s\S]*?)(?=(?:\n\s*)?\[(?:(?:\d+:)?\d{1,5}:\d{2})(?:[\.,]\d{1,3})?\]|\z)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsText = text as NSString
        return regex
            .matches(in: text, range: NSRange(location: 0, length: nsText.length))
            .compactMap { match -> (timestamp: Double, text: String)? in
                guard match.numberOfRanges == 3,
                      let timestamp = parseTimestampToSeconds(nsText.substring(with: match.range(at: 1)))
                else {
                    return nil
                }
                let body = nsText.substring(with: match.range(at: 2))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return body.isEmpty ? nil : (timestamp, body)
            }
    }

    private static func parseXMLCueOutput(_ text: String) -> [String: String] {
        let pattern = #"<cue\s+id=["']([^"']+)["']\s*>(.*?)</cue>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return [:]
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var output: [String: String] = [:]
        for match in matches where match.numberOfRanges == 3 {
            let id = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let translated = nsText.substring(with: match.range(at: 2))
            output[id] = xmlUnescaped(translated)
        }
        return output
    }

    private static func orderedXMLCueOutput(_ text: String) -> [String] {
        let pattern = #"<cue(?:\s+id=["'][^"']+["'])?\s*>(.*?)</cue>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        return regex
            .matches(in: text, range: NSRange(location: 0, length: nsText.length))
            .compactMap { match -> String? in
                guard match.numberOfRanges == 2 else { return nil }
                let translated = xmlUnescaped(nsText.substring(with: match.range(at: 1)))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return translated.isEmpty ? nil : translated
            }
    }

    private static func parseNumberedCueLines(_ text: String) -> [String: String] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var output: [String: String] = [:]
        for line in lines {
            guard let match = line.range(of: #"^\[?(\d{1,4})\]?[\.:\)\-]?\s+(.+)$"#, options: .regularExpression) else {
                continue
            }
            let prefix = String(line[match])
            let parts = prefix.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard parts.count == 2 else { continue }
            let digits = parts[0].filter(\.isNumber)
            guard let number = Int(digits), number > 0 else { continue }
            output[cueIdentifier(for: number - 1)] = String(parts[1])
        }
        return output
    }

    private static func orderedNumberedCueLines(_ text: String) -> [String] {
        let keyed = parseNumberedCueLines(text)
        return keyed.keys.sorted().compactMap { keyed[$0] }
    }

    private static func cleanedTextWithoutCueMarkup(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"</?cue(?:\s+id=["'][^"']+["'])?\s*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func splitTranslatedText(_ text: String, matching sourceCues: [TranscriptCue]) -> [String] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        guard sourceCues.count > 1 else { return [clean] }

        let lines = clean
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.count == sourceCues.count {
            return lines
        }

        let words = clean.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return Array(repeating: clean, count: sourceCues.count) }

        let sourceWeights = sourceCues.map { max(1, $0.text.count) }
        let totalWeight = max(1, sourceWeights.reduce(0, +))
        var output: [String] = []
        var cursor = 0
        for index in sourceCues.indices {
            let remainingCues = sourceCues.count - index
            let remainingWords = words.count - cursor
            let idealCount = index == sourceCues.indices.last
                ? remainingWords
                : max(1, Int((Double(words.count) * Double(sourceWeights[index]) / Double(totalWeight)).rounded()))
            let count = min(max(1, idealCount), max(1, remainingWords - remainingCues + 1))
            let end = min(words.count, cursor + count)
            output.append(words[cursor..<end].joined(separator: " "))
            cursor = end
        }

        if cursor < words.count, !output.isEmpty {
            output[output.count - 1] += " " + words[cursor...].joined(separator: " ")
        }
        return output
    }

    private static func validatedAlignedTexts(_ texts: [String], sourceCues: [TranscriptCue]) -> [String]? {
        guard texts.count == sourceCues.count else { return nil }
        let trimmed = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard trimmed.allSatisfy({ !$0.isEmpty }) else { return nil }

        let translatedWords = trimmed.flatMap { $0.split(whereSeparator: \.isWhitespace) }.count
        let sourceWords = sourceCues.flatMap { $0.text.split(whereSeparator: \.isWhitespace) }.count
        guard translatedWords >= min(sourceCues.count, max(1, sourceWords / 10)) else {
            return nil
        }
        return trimmed
    }

    public static func approximateWords(for translatedText: String, source: TranscriptCue) -> [TranscriptWord]? {
        guard source.words != nil else { return nil }
        let words = translatedText
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }

        let duration = max(0.05, source.endSec - source.startSec)
        let step = duration / Double(words.count)
        return words.enumerated().map { index, word in
            let start = source.startSec + Double(index) * step
            let end = index == words.count - 1 ? source.endSec : min(source.endSec, start + step)
            return TranscriptWord(startSec: start, endSec: max(start + 0.03, end), text: word)
        }
    }

    private static func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func xmlUnescaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

public enum CueBatchTranslationError: Error, LocalizedError, Equatable {
    case missingCue(id: String)
    case emptyOutput

    public var errorDescription: String? {
        switch self {
        case let .missingCue(id):
            "MLX did not return timed cue \(id)."
        case .emptyOutput:
            "MLX returned no usable translation text."
        }
    }
}

public enum ModelOutputSanitizer {
    public static func sanitizeTranslation(_ rawText: String, targetLang: String) -> String {
        let text = sanitize(rawText)
        guard !containsVisibleReasoning(text, targetLang: targetLang) else {
            return ""
        }
        return text
    }

    public static func sanitize(_ rawText: String) -> String {
        sanitize(rawText, skipTimestampedLatinLines: true)
    }

    public static func sanitizeTranscript(_ rawText: String) -> String {
        sanitize(rawText, skipTimestampedLatinLines: false)
    }

    private static func sanitize(_ rawText: String, skipTimestampedLatinLines: Bool) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown blocks if they wrap the entire text
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: #"^```[A-Za-z0-9_-]*\s*"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
        }

        // Strip <think>...</think> tags (both complete and incomplete)
        text = text.replacingOccurrences(of: #"(?i)<think>[\s\S]*?</think>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)<think>[\s\S]*?(?=(?:\[\d{1,5}:\d{2}\]|[\u0400-\u04FF]))"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)<think>[\s\S]*$"#, with: "", options: .regularExpression)

        // Strip ansi color codes
        text = text.replacingOccurrences(of: #"\x1b\[[0-9;]*m"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<|im_end|>", with: "")

        // Strip llama cpp terminal noise (generate:, performance stats, memory stats, available commands, prompt duplication)
        text = text.replacingOccurrences(of: #"(?i)^[\s\S]*?generate:[^\n]*\n+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)common_perf_print:[\s\S]*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)common_memory_breakdown_print:[\s\S]*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)\s*\[end of text\]\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)[\s\S]*?available commands:\s*[\s\S]*?(?=\n\s*(?:Context:|You are translating|Transcript:|[\u0400-\u04FF]|\[\d{1,5}:\d{2}\]))"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)[\s\S]*?You are translating a verbatim transcript into [^\n]+\.?"#, with: "", options: .regularExpression)

        // Strip duplicate Transcript: block or duplicate translation prefixes
        text = text.replacingOccurrences(of: #"(?i)[\s\S]*?Transcript:\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)^[\s\S]*?\n\s*[A-Za-z][A-Za-z -]+ translation:\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)\bExiting\.\.\.\s*$"#, with: "", options: .regularExpression)

        // Strip assistant: prefix or translation prefix
        text = text.replacingOccurrences(of: #"(?i)^\s*(assistant|translation|(?:revised|polished|improved|edited|final)\s+(?:russian|translation)|russian|русский|перевод)\s*:\s*"#, with: "", options: .regularExpression)

        // Handle <<<RESULT>>>...<<<END>>> if they are present in the output
        if text.range(of: #"(?i)<<<RESULT>>>\s*([\s\S]*?)(?:<<<END>>>|$)"#, options: .regularExpression) != nil {
            if let resultBegin = text.range(of: "<<<RESULT>>>") {
                text = String(text[resultBegin.upperBound...])
            }
            if let endBegin = text.range(of: "<<<END>>>") {
                text = String(text[..<endBegin.lowerBound])
            }
        } else {
            // strip <<<BEGIN>>> and <<<END>>> if they exist as fallback
            if let beginRange = text.range(of: "<<<BEGIN>>>") {
                text = String(text[beginRange.upperBound...])
            }
            if let endRange = text.range(of: "<<<END>>>") {
                text = String(text[..<endRange.lowerBound])
            }
        }

        // Clean up translation prefixes like "Russian: ..."
        if text.range(of: #"(?i)(?:^|\n)\s*(?:Russian|Русский|Translation|Перевод)\s*:\s*([\s\S]*)$"#, options: .regularExpression) != nil {
            if let colonIndex = text.range(of: ":") {
                text = String(text[colonIndex.upperBound...])
            }
        }

        let rawLines = text.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        for line in rawLines {
            let cleanedLine = line.replacingOccurrences(of: #"(?i)^\s*(?:(?:Revised|Polished|Improved|Edited|Final)\s+)?(?:Russian|Русский|Translation|Перевод)\s*:\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)

            // Check if line should be skipped
            if cleanedLine.isEmpty {
                continue
            }
            // Skip lines that are exactly prefixes
            let prefixPattern = #"(?i)^\s*(?:(?:Revised|Polished|Improved|Edited|Final)\s+)?(?:Russian|Русский|Translation|Перевод)\s*:?\s*$"#
            if cleanedLine.range(of: prefixPattern, options: .regularExpression) != nil {
                continue
            }
            // If the line contains a timestamp and contains only English letters (but no Cyrillic), and the target is Russian, skip it to prevent english leakage in russian translation
            let hasTimestamp = cleanedLine.range(of: #"^\[\d{1,5}:\d{2}\]"#, options: .regularExpression) != nil
            let hasLatin = cleanedLine.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
            let hasCyrillic = cleanedLine.range(of: #"[\u0400-\u04FF]"#, options: .regularExpression) != nil
            if skipTimestampedLatinLines && hasTimestamp && hasLatin && !hasCyrillic {
                continue
            }

            cleanedLines.append(cleanedLine)
        }

        // Deduplicate identical consecutive lines
        var deduped: [String] = []
        for line in cleanedLines {
            if deduped.last != line {
                deduped.append(line)
            }
        }

        return deduped.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsVisibleReasoning(_ text: String, targetLang: String) -> Bool {
        let target = targetLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard target != "english", target != "en" else { return false }

        let lowered = text.lowercased()
        let reasoningMarkers = [
            "i should",
            "i'll",
            "i will",
            "i need",
            "i can",
            "i think",
            "looking at",
            "given that",
            "the user",
            "the instruction",
            "this is a mantra",
            "this is a reference",
            "previous one",
            "entry for this",
            "translate it as",
            "should probably",
            "probably be kept",
            "based on the context",
            "there's no specific",
            "there is no specific",
            "wait,",
        ]

        return reasoningMarkers.contains { lowered.contains($0) }
    }
}
