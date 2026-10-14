import Foundation

public enum ModelOutputSanitizer {
    public static func sanitize(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }

        if let marked = textBetween(cleaned, start: "<<<BEGIN>>>", end: "<<<END>>>") {
            cleaned = marked
        }

        if let inputRange = inputMarkerRange(in: cleaned) {
            let before = cleaned[..<inputRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let after = cleaned[inputRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned = after.isEmpty ? before : after
        }

        cleaned = unwrapCodeFence(cleaned)

        // Reasoning-tag rule: only a LEADING <think> block is model reasoning.
        // A reasoning boundary is only the first line whose trimmed text is
        // exactly </think> (case-insensitive; surrounding whitespace allowed).
        // Inline closers are prose and leave the string unchanged. When such
        // a boundary line exists and non-whitespace text follows it, keep only
        // that trailing text (trimmed); otherwise leave the string unchanged.
        let opensWithThink = cleaned.range(of: "<think>", options: [.anchored, .caseInsensitive]) != nil
        cleaned = stripLeadingThinkBlocks(cleaned)
        if !opensWithThink,
           let boundaryUpperBound = firstOwnLineClosingTagUpperBound(in: cleaned)
        {
            let after = String(cleaned[boundaryUpperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !after.isEmpty {
                cleaned = after
            }
        }

        // 3. Unmarked prose is returned unchanged: prompts forbid labels,
        //    so no delimiter extraction, first-word heuristics, preamble
        //    stripping, word replacement, or duplicate collapsing is applied
        //    here.
        cleaned = unwrapCodeFence(cleaned)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func textBetween(_ text: String, start: String, end: String) -> String? {
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end),
              startRange.upperBound <= endRange.lowerBound
        else {
            return nil
        }

        return text[startRange.upperBound..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLeadingThinkBlocks(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.range(of: "<think>", options: [.anchored, .caseInsensitive]) != nil {
            guard let close = result.range(of: "</think>", options: [.caseInsensitive]) else {
                return ""
            }
            result = String(result[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// Returns the index just past the first line whose trimmed text is exactly
    /// `</think>` (case-insensitive). Lines follow the platform line splitting
    /// (`\r\n`, `\n`, `\r`); any other character on the line disqualifies it.
    /// The index points at the line end (before its terminator); callers trim
    /// the trailing text, so the terminator never survives.
    private static func firstOwnLineClosingTagUpperBound(in text: String) -> String.Index? {
        var boundary: String.Index?
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byLines, .substringNotRequired]
        ) { _, lineRange, _, stop in
            if text[lineRange].trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("</think>") == .orderedSame
            {
                boundary = lineRange.upperBound
                stop = true
            }
        }
        return boundary
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
        let pattern = #"^```[^\s`]*\r?\n(?:([\s\S]*?)\r?\n)?```\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              match.numberOfRanges > 1
        else {
            return text
        }
        guard let range = Range(match.range(at: 1), in: text) else {
            return ""
        }

        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
