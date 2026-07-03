import Foundation

public enum TextSnippetRevision {
    public struct Result: Equatable, Sendable {
        public var text: String
        public var changed: Bool

        public init(text: String, changed: Bool) {
            self.text = text
            self.changed = changed
        }
    }

    public static func replaceSelectedText(
        in content: String,
        selectedText rawSelected: String,
        replacementText: String,
        contextText: String? = nil
    ) -> Result {
        let selected = rawSelected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else {
            return Result(text: content, changed: false)
        }

        let selectedBody = withoutLeadingTimestamps(selected)

        if let contextText, let contextRange = findNormalizedRange(in: content, needle: contextText) {
            let context = String(content[contextRange])
            if let selectedRange = findNormalizedRange(in: context, needle: selectedBody) {
                let replacement = bodyReplacement(replacementText)
                let contextStart = contextRange.lowerBound
                let absoluteStart = content.index(contextStart, offsetBy: context.distance(from: context.startIndex, to: selectedRange.lowerBound))
                let absoluteEnd = content.index(contextStart, offsetBy: context.distance(from: context.startIndex, to: selectedRange.upperBound))
                return Result(
                    text: String(content[..<absoluteStart]) + replacement + String(content[absoluteEnd...]),
                    changed: true
                )
            }
        }

        let exactNeedle = content.contains(rawSelected) ? rawSelected : selected
        if let exactRange = content.range(of: exactNeedle) {
            let replacement = preserveTimestampIfNeeded(original: selected, replacement: replacementText)
            return Result(
                text: String(content[..<exactRange.lowerBound]) + replacement + String(content[exactRange.upperBound...]),
                changed: true
            )
        }

        if let range = findNormalizedRange(in: content, needle: selectedBody) {
            let replacement = bodyReplacement(replacementText)
            return Result(
                text: String(content[..<range.lowerBound]) + replacement + String(content[range.upperBound...]),
                changed: true
            )
        }

        return Result(text: content, changed: false)
    }

    private static func normalizeSpaces(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func leadingTimestamp(_ value: String) -> String {
        guard let prefixRange = value.range(
            of: #"^\s*(\[(?:(?:\d+:)?\d{1,5}:\d{2}(?:[.,]\d{1,3})?)\])\s*"#,
            options: .regularExpression
        ) else {
            return ""
        }
        let prefix = String(value[prefixRange])
        return prefix.range(
            of: #"\[(?:(?:\d+:)?\d{1,5}:\d{2}(?:[.,]\d{1,3})?)\]"#,
            options: .regularExpression
        ).map { String(prefix[$0]) } ?? ""
    }

    private static func withoutLeadingTimestamps(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"^(?:\s*\[(?:(?:\d+:)?\d{1,5}:\d{2}(?:[.,]\d{1,3})?)\]\s*)+"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func collapseDuplicateLeadingTimestamps(_ value: String) -> String {
        guard let prefixRange = value.range(
            of: #"^(?:\s*\[(?:(?:\d+:)?\d{1,5}:\d{2}(?:[.,]\d{1,3})?)\]\s*)+"#,
            options: .regularExpression
        ) else {
            return value
        }
        let prefix = String(value[prefixRange])
        guard let firstTimestampRange = prefix.range(
            of: #"\[(?:(?:\d+:)?\d{1,5}:\d{2}(?:[.,]\d{1,3})?)\]"#,
            options: .regularExpression
        ) else {
            return value
        }
        let timestamp = String(prefix[firstTimestampRange])
        return "\(timestamp) \(value[prefixRange.upperBound...].trimmingCharacters(in: .whitespaces))"
    }

    private static func bodyReplacement(_ replacement: String) -> String {
        withoutLeadingTimestamps(collapseDuplicateLeadingTimestamps(replacement)).trimmingCharacters(in: .whitespaces)
    }

    private static func preserveTimestampIfNeeded(original: String, replacement: String) -> String {
        guard !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        let timestamp = leadingTimestamp(original)
        let cleanReplacement = collapseDuplicateLeadingTimestamps(replacement)
        guard !timestamp.isEmpty else {
            return cleanReplacement
        }
        return "\(timestamp) \(withoutLeadingTimestamps(cleanReplacement).trimmingCharacters(in: .whitespaces))"
    }

    private static func findNormalizedRange(in haystack: String, needle: String) -> Range<String.Index>? {
        let normalizedNeedle = normalizeSpaces(needle)
        guard !normalizedNeedle.isEmpty else { return nil }
        let needleChars = Array(normalizedNeedle)

        var start = haystack.startIndex
        while start < haystack.endIndex {
            if haystack[start].isWhitespace {
                start = haystack.index(after: start)
                continue
            }

            var sourceIndex = start
            var needleIndex = 0
            var lastSourceIndex = start

            while sourceIndex < haystack.endIndex, needleIndex < needleChars.count {
                let sourceChar = haystack[sourceIndex]
                let needleChar = needleChars[needleIndex]

                if sourceChar.isWhitespace {
                    while sourceIndex < haystack.endIndex, haystack[sourceIndex].isWhitespace {
                        sourceIndex = haystack.index(after: sourceIndex)
                    }
                    if needleChar == " " {
                        needleIndex += 1
                    }
                    continue
                }

                guard sourceChar == needleChar else {
                    break
                }
                lastSourceIndex = haystack.index(after: sourceIndex)
                sourceIndex = lastSourceIndex
                needleIndex += 1
            }

            if needleIndex == needleChars.count {
                return start..<lastSourceIndex
            }

            start = haystack.index(after: start)
        }

        return nil
    }
}
