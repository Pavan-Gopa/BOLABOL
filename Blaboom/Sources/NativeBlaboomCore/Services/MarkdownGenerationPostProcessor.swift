import Foundation

public enum MarkdownGenerationPostProcessor {
    public static func ensureVisibleMarkdown(
        _ modelOutput: String,
        sourceText: String
    ) -> String {
        let trimmedOutput = modelOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseText = trimmedOutput.isEmpty ? trimmedSource : trimmedOutput

        guard !baseText.isEmpty else { return "" }
        guard !hasVisibleMarkdown(baseText) else { return modelOutput }

        if let listMarkdown = sequentialListMarkdown(
            from: baseText,
            sourceText: trimmedSource
        ) {
            return listMarkdown
        }

        return """
        \(genericHeading(for: baseText + "\n" + trimmedSource))

        \(baseText)
        """
    }

    private static func hasVisibleMarkdown(_ text: String) -> Bool {
        let linePatterns = [
            #"(?m)^\s{0,3}#{1,6}\s+\S"#,
            #"(?m)^\s{0,3}[-*+]\s+\S"#,
            #"(?m)^\s{0,3}\d+[\.)]\s+\S"#,
            #"(?m)^\s{0,3}>\s+\S"#,
            #"(?m)^\s{0,3}- \[[ xX]\]\s+\S"#,
            #"(?m)^\s*\|?(?:\s*:?-{3,}:?\s*\|)+\s*$"#
        ]

        if text.contains("```") || text.contains("`") || text.contains("**") {
            return true
        }

        return linePatterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression]) != nil
        }
    }

    private static func sequentialListMarkdown(
        from text: String,
        sourceText: String
    ) -> String? {
        let combined = "\(sourceText)\n\(text)"
        let items = sentenceFragments(from: text)
            .map(cleanListItem)
            .filter { $0.count >= 3 }

        guard items.count >= 2 else { return nil }
        guard containsSequenceCue(combined) || items.count >= 3 else { return nil }

        let heading = planHeading(for: combined)
        let list = items.enumerated().map { index, item in
            "\(index + 1). \(item)"
        }

        return ([heading, ""] + list).joined(separator: "\n")
    }

    private static func sentenceFragments(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(
                of: #"[ \t]+"#,
                with: " ",
                options: .regularExpression
            )

        let pattern = #"[^.!?\n;]+(?:[.!?;]+|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [normalized]
        }

        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = regex.matches(in: normalized, range: nsRange)
        return matches.compactMap { match in
            guard let range = Range(match.range, in: normalized) else { return nil }
            return String(normalized[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".!?;"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func cleanListItem(_ item: String) -> String {
        var cleaned = item.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            #"(?i)^(?:first|then|next|after that|finally)[,:\s-]+"#,
            #"(?i)^(?:сначала|потом|затем|дальше|далее|после этого|во-первых|во вторых|во-вторых)[,:\s-]+"#
        ]

        for prefix in prefixes {
            cleaned = cleaned.replacingOccurrences(
                of: prefix,
                with: "",
                options: [.regularExpression]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let first = cleaned.first else { return cleaned }
        return String(first).uppercased() + cleaned.dropFirst()
    }

    private static func containsSequenceCue(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")

        let cues = [
            "first",
            "then",
            "next",
            "after that",
            "finally",
            "plan",
            "checklist",
            "sequence",
            "сначала",
            "потом",
            "затем",
            "дальше",
            "далее",
            "после этого",
            "во-первых",
            "во вторых",
            "во-вторых",
            "план",
            "список",
            "шаг"
        ]

        return cues.contains { normalized.contains($0) }
    }

    private static func genericHeading(for text: String) -> String {
        containsCyrillic(text) ? "## Текст" : "## Text"
    }

    private static func planHeading(for text: String) -> String {
        containsCyrillic(text) ? "## План" : "## Plan"
    }

    private static func containsCyrillic(_ text: String) -> Bool {
        text.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil
    }
}
