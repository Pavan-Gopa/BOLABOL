import Foundation

public enum ModelOutputSanitizer {
    public static func sanitize(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }

        if let marked = textBetween(cleaned, start: "<<<BEGIN>>>", end: "<<<END>>>") {
            return marked
        }

        if let inputRange = inputMarkerRange(in: cleaned) {
            let before = cleaned[..<inputRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let after = cleaned[inputRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned = after.isEmpty ? before : after
        }

        // 1. Remove closed <think>…</think> blocks
        cleaned = cleaned.replacingOccurrences(
            of: #"(?s)<think>.*?</think>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Remove unclosed <think> blocks (model emitted <think> but never closed it)
        cleaned = cleaned.replacingOccurrences(
            of: #"(?s)<think>.*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        // 2b. Remove standalone unclosed thinking block ending with </think>
        //     (occurs when the <think> tag was part of the prompt prefix rather than model output)
        if let range = cleaned.range(of: "</think>", options: [.backwards, .caseInsensitive]) {
            cleaned = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 3. Strip plain-text thinking / reasoning sections that some models
        //    produce instead of (or in addition to) <think> tags.
        cleaned = stripPlainTextThinking(cleaned)

        let replacements: [(String, String)] = [
            (#"^<<>>\s*"#, ""),
            (#"^<<<<<>>>>\s*"#, ""),
            (#"^<<<.*?>>>\s*"#, ""),
            (#"^\*\*.*?\*\*\s*"#, ""),
            (#"^Variant\s+\d+\s*[:\-]?\s*"#, ""),
            (#"^Вариант\s+\d+\s*[:\-]?\s*"#, "")
        ]
        for (pattern, replacement) in replacements {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let preambles = [
            #"^\s*(ok|okay|sure)[\.,!\s-]*\b"#,
            #"^\s*i\s*(will|can|understand|understood|shall)\b[^\n]*\n*"#,
            #"^\s*(here is|here's)\b[^\n]*\n*"#,
            #"^\s*(processed|formatted)\s*text\s*[:\-]*\s*"#,
            #"^\s*(as requested|as you requested)\b[^\n]*\n*"#,
            #"^\s*let me\b[^\n]*\n*"#,
            #"^\s*i'll\b[^\n]*\n*"#,
            #"^\s*the\s+(cleaned|processed|enhanced)\s+text\s*[:\-]*\s*"#,
            #"^\s*(хорошо|конечно|понятно)[\.,!\s-]*"#
        ]
        for pattern in preambles {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        cleaned = unwrapCodeFence(cleaned)

        let wordFixes: [(String, String)] = [
            (#"\bfinally\b"#, "наконец"),
            (#"\bhorizon\b"#, "горизонт"),
            (#"\bhorizont?е\b"#, "горизонте"),
            (#"\breally\b"#, "действительно"),
            (#"\bmoment\b"#, "момент")
        ]
        for (pattern, replacement) in wordFixes {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func textBetween(_ text: String, start: String, end: String) -> String? {
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end),
              startRange.upperBound < endRange.lowerBound
        else {
            return nil
        }

        return text[startRange.upperBound..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func inputMarkerRange(in text: String) -> Range<String.Index>? {
        guard let startRange = text.range(of: "<<<INPUT>>>"),
              let endRange = text.range(of: "<<<END_INPUT>>>"),
              startRange.lowerBound < endRange.upperBound
        else {
            return nil
        }

        return startRange.lowerBound..<endRange.upperBound
    }

    private static func unwrapCodeFence(_ text: String) -> String {
        let pattern = #"^```[a-zA-Z]*\n([\s\S]*?)\n```\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else {
            return text
        }

        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes plain-text chain-of-thought sections produced by reasoning
    /// models (e.g. Qwen 3.5) that don't use `<think>` tags.
    ///
    /// Strategy (applied in order until one succeeds):
    /// 1. If a well-known "final answer" delimiter is present, take everything
    ///    after the LAST occurrence.
    /// 2. If the output opens with a recognisable chain-of-thought preamble
    ///    (e.g. "The user wants me to …", "Let me analyze …"), try to find
    ///    the actual answer after a delimiter; if none is found, take the
    ///    LAST paragraph of the output as the likely answer (rather than
    ///    returning empty).
    /// 3. Otherwise return the text unchanged.
    private static func stripPlainTextThinking(_ text: String) -> String {
        // ---- Final-answer delimiters ----
        // Models often write "Final Answer:", "Cleaned Text:", "Result:", etc.
        // before the actual content.
        let answerDelimiters = [
            #"(?m)^\s*\*{0,2}(?:Final(?:ized)?[\s_]?(?:Answer|Text|Output|Result|Version)|(?:Clean(?:ed)?|Polish(?:ed)?|Processed|Corrected|Refined|Edited|Improved|Rewritten|Enhanced)[\s_]?(?:Text|Output|Version|Result)|(?:Result|Output))\s*\*{0,2}\s*[:：]\s*"#
        ]
        for delimiter in answerDelimiters {
            if let answer = lastMatchTail(in: text, pattern: delimiter) {
                return stripWrappingQuotes(answer)
            }
        }

        // ---- Chain-of-thought preamble detection ----
        // Broader set of patterns that indicate the model is "thinking aloud"
        // rather than producing a direct answer.
        let cotPreambles: [String] = [
            // Explicit thinking headers
            #"^(?:\*{0,2})?(?:Thinking|Thought|Reasoning|Analysis|My\s+(?:Thinking|Thought|Analysis)|Process|Method|Approach)[\s_]?(?:Process|Steps?|Chain)?\s*(?:\*{0,2})?\s*[:：]?\s*"#,
            // "The user wants me to …" / "The user is asking …"
            #"^(?:The\s+user\s+(?:wants|is\s+asking|asked|needs|requires)|The\s+speaker\s+(?:is\s+)?(?:wants|asking|needs))"#,
            // "Let me …" / "I need to …" / "I'll …" / "I should …" / "I will …"
            #"^(?:Let\s+me\s|I\s+(?:need|should|will|shall|must|'ll|would\s+like|can|will\s+be))\s"#,
            // "First, …" / "Step 1:" / "1." at very start (numbered reasoning)
            #"^(?:First(?:ly)?\s*[,:\s]|Step\s+\d+\s*[:.\s]|\d+\.\s+\*{0,2}(?:Analyze|Identify|Read|Understand|Look|Check|Examine|Process|Clean|Review|Fix|Remove|Keep|Improve))"#,
            // "This appears to be …" / "This is a …" / "This text is …"
            #"^This\s+(?:appears?\s+to\s+be|is\s+(?:a\s+)?(?:spoken|dictated|transcri|short|long)|text\s+is|was\s+(?:a\s+)?(?:spoken|dictated))"#,
            // "Looking at …" / "Analyzing …" / "Reading the input …"
            #"^(?:Looking\s+(?:at|through)|Analyzing|Reading|Examine|Reviewing|Considering)\s+"#,
            // "Based on the input …" / "Given the text …"
            #"^(?:Based\s+on(?: the)?\s+(?:input|text|transcription|dictation)|Given\s+(?:the\s+)?(?:input|text|transcription))"#,
            // "I'll start by …" / "I'll begin by …"
            #"^(?:I'll\s+(?:start|begin|proceed|continue)|I\s+will\s+(?:start|begin|proceed))\s+(?:by\s+)?"#,
            // "To clean …" / "To process …" / "To improve …"
            #"^(?:To\s+(?:clean|process|improve|enhance|fix|remove|edit|rewrite|cleanse))"#,
            // "So the text …" / "Now the text …" / "Okay, …" / "Alright, …"
            #"^(?:So\s+(?:the|i)|Now\s+(?:the|i)|Okay,?\s+|Alright,?\s+)"#,
            // "The main goal is …" / "The objective is …"
            #"^(?:The\s+(?:main\s+)?(?:goal|objective|purpose|aim)\s+is\s+)"#,
            // Russian equivalents
            #"^(?:Пользователь\s+(?:хочет|просит|требует)|Давайте\s+|Мне\s+нужно\s+|Сначала\s+|Для\s+начала\s+)"#,
            // "Я буду…" / "Мне нужно…" / "Чтобы…" Russian
            #"^(?:Я\s+(?:буду|начал|приступлю)|Мне\s+нужно\s+|Чтобы\s+(?:очистить|обработать|улучшить)|Давайте\s+посмотрим)"#,
            // Additional patterns for models that write reasoning inline
            #"^(?:I'll\s+go\s+through|I\s+will\s+go\s+through|The\s+following\s+is)"#,
            #"^(?:The\s+key\s+steps\s+are|Here'?s\s+(?:what|how))"#,
            // Structured reasoning headers used by Qwopus/Opus-style fine-tunes
            // (echoes the input, then analyses it line by line).
            #"^(?:Input\s+text\s*[:：]|Analysis\s*[:：]|Checking\s+for\b)"#,
        ]

        let looksLikeCoT = cotPreambles.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }

        guard looksLikeCoT else { return text }

        // The whole output is (or starts with) chain-of-thought.
        // Try to find the actual answer after a trailing delimiter.
        let trailingDelimiters = [
            #"(?m)^\s*\*{0,2}(?:Goal|Final|Output|Result|Clean(?:ed)?[\s_]?(?:Text|Version)|Polish(?:ed)?[\s_]?(?:Text|Version)|Rewritten[\s_]?(?:Text|Version)|Enhanced[\s_]?(?:Text|Version)|Answer|Response)[\s_]?(?:is|here)?\s*\*{0,2}\s*[:：]?\s*"#,
            // "---" or "===" separator lines
            #"(?m)^[\-=]{3,}\s*$"#,
            // Cleaned/processed text markers
            #"(?m)^\s*(?:Cleaned|Processed|Edited)\s+text\s*[:：]\s*"#,
            // Russian "ответ" / "готово" markers
            #"(?m)^\s*(?:Ответ|Result|Resulting)\s*[:：]\s*"#,
        ]
        for td in trailingDelimiters {
            if let answer = lastMatchTail(in: text, pattern: td) {
                return stripWrappingQuotes(answer)
            }
        }

        // No delimiter found. Take the LAST substantial paragraph as the
        // likely answer. Models typically put the answer at the end after
        // their reasoning chain.
        if let lastParagraph = extractLastParagraph(text) {
            return stripWrappingQuotes(lastParagraph)
        }

        // Absolute fallback — return empty so the caller can decide what to do.
        return ""
    }

    /// Returns the trimmed text after the last match of `pattern`, or nil
    /// if there is no match or the text after the match is empty.
    private static func lastMatchTail(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var lastMatch: NSTextCheckingResult?
        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            lastMatch = match
        }
        guard let match = lastMatch,
              let range = Range(match.range, in: text) else { return nil }
        let answer = text[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return answer.isEmpty ? nil : answer
    }

    /// Extracts the last "paragraph" from the text — defined as the text
    /// after the last blank line (two or more newlines). If no blank line
    /// is found, returns nil (i.e. the text is a single paragraph).
    ///
    /// The paragraph must look like actual content (not a short label or
    /// a numbered step) to be accepted.
    private static func extractLastParagraph(_ text: String) -> String? {
        // Split on double-newline boundaries
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard paragraphs.count >= 2 else { return nil }

        // Take the last paragraph
        let last = paragraphs.last!

        // Reject if it looks like another reasoning step
        let reasoningPrefixes = [
            #"^\d+\.\s+"#,          // "1. …"
            #"^[-•]\s+"#,          // bullet point
            #"^Step\s+\d+"#,       // "Step 3"
            #"^(?:Note|Warning|Caveat|Disclaimer)\s*:"#,
            #"^(?:In summary|To summarize|In conclusion)\s*[,:]"#,
            // Reasoning section labels emitted by Qwopus/Opus-style models.
            // When the model is truncated mid-reasoning, its last paragraph is
            // one of these labels (e.g. "Checking for duplicates: - No repeated")
            // rather than the cleaned text — reject so the caller treats the
            // output as "no answer" instead of showing the reasoning fragment.
            #"^(?:Analysis|Checking|Input\s+text|Output\s+text|Reasoning|Thought|Thinking)\b"#,
        ]
        let looksLikeReasoning = reasoningPrefixes.contains { pattern in
            last.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        // Also reject very short paragraphs (< 20 chars) — likely just a label
        if looksLikeReasoning || last.count < 20 { return nil }

        return last
    }

    /// Removes surrounding quotation marks that some models wrap the answer in.
    private static func stripWrappingQuotes(_ text: String) -> String {
        var result = text
        let quotePatterns: [(String, String)] = [
            ("\"", "\""),
            ("\u{201C}", "\u{201D}"),  // ""
            ("\u{00AB}", "\u{00BB}"),  // «»
        ]
        for (open, close) in quotePatterns {
            if result.hasPrefix(open) && result.hasSuffix(close) && result.count > 2 {
                result = String(result.dropFirst(open.count).dropLast(close.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return result
    }
}
