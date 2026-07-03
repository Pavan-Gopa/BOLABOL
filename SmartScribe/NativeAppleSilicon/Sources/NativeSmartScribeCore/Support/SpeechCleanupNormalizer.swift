import Foundation

public enum SpeechCleanupMode: Sendable {
    case lightCleanup
    case structuredCleanup
}

public enum SpeechCleanupNormalizer {
    public static func normalize(_ text: String, mode: SpeechCleanupMode) -> String {
        let whitespaceNormalized = normalizeWhitespace(in: text)
        guard !whitespaceNormalized.isEmpty else { return "" }

        let withoutFillers = removeCommonFillers(from: whitespaceNormalized)
        let withoutDuplicates = collapseAdjacentDuplicates(in: withoutFillers)
        let cleaned = cleanupPunctuationSpacing(in: withoutDuplicates)
        let sentenceNormalized = normalizeSentenceCase(in: cleaned)
        let punctuated = normalizeTerminalPunctuation(in: sentenceNormalized)

        switch mode {
        case .lightCleanup:
            return structureParagraphsIfNeeded(in: punctuated)
        case .structuredCleanup:
            return structureSentences(in: punctuated)
        }
    }

    private static func normalizeWhitespace(in text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeCommonFillers(from text: String) -> String {
        let fillerPatterns = [
            #"(?iu)(^|[\s,.;:!?()-])ну(?=$|[\s,.;:!?()-])"#,
            #"(?iu)(^|[\s,.;:!?()-])вот(?=$|[\s,.;:!?()-])"#,
            #"(?iu)(^|[\s,.;:!?()-])типа(?=$|[\s,.;:!?()-])"#,
            #"(?iu)(^|[\s,.;:!?()-])как бы(?=$|[\s,.;:!?()-])"#,
            #"(?iu)(^|[\s,.;:!?()-])um(?=$|[\s,.;:!?()-])"#,
            #"(?iu)(^|[\s,.;:!?()-])uh(?=$|[\s,.;:!?()-])"#,
            #"(?iu)(^|[\s,.;:!?()-])you know(?=$|[\s,.;:!?()-])"#,
            #"(?iu)(^|[\s,.;:!?()-])like(?=$|[\s,.;:!?()-])"#
        ]

        return fillerPatterns.reduce(text) { partial, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return partial
            }

            let range = NSRange(partial.startIndex..<partial.endIndex, in: partial)
            return regex.stringByReplacingMatches(
                in: partial,
                options: [],
                range: range,
                withTemplate: "$1"
            )
        }
    }

    private static func collapseAdjacentDuplicates(in text: String) -> String {
        guard !text.isEmpty else { return text }

        let tokens = text.split(separator: " ").map(String.init)
        var result: [String] = []

        for token in tokens {
            let normalizedToken = token.normalizedDuplicateToken
            if result.last?.normalizedDuplicateToken == normalizedToken {
                continue
            }
            result.append(token)
        }

        return result.joined(separator: " ")
    }

    private static func cleanupPunctuationSpacing(in text: String) -> String {
        var cleaned = text

        let regexReplacements: [(String, String)] = [
            (#"\s+([,.;:!?])"#, "$1"),
            (#"([,.;:!?])([^\s])"#, "$1 $2"),
            (#"\s{2,}"#, " "),
            (#"(, ){2,}"#, ", ")
        ]

        for (pattern, template) in regexReplacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                options: [],
                range: range,
                withTemplate: template
            )
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeSentenceCase(in text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = ""
        var capitalizeNext = true

        for character in text {
            if capitalizeNext, character.isLetter {
                result.append(String(character).uppercased())
                capitalizeNext = false
            } else {
                result.append(character)
                if character.isLetter {
                    capitalizeNext = false
                }
            }

            if ".!?".contains(character) {
                capitalizeNext = true
            }
        }

        return result
    }

    private static func normalizeTerminalPunctuation(in text: String) -> String {
        guard let last = text.last else { return text }
        if ".!?".contains(last) {
            return text
        }
        return text + "."
    }

    private static func structureParagraphsIfNeeded(in text: String) -> String {
        let sentences = splitAfterSentenceTerminators(in: text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard sentences.count >= 3 else { return text }

        var paragraphs: [String] = []
        var buffer: [String] = []
        var currentLength = 0

        for sentence in sentences {
            let projected = currentLength + sentence.count + (buffer.isEmpty ? 0 : 1)
            if projected > 120, !buffer.isEmpty {
                paragraphs.append(buffer.joined(separator: " "))
                buffer = [sentence]
                currentLength = sentence.count
            } else {
                buffer.append(sentence)
                currentLength = projected
            }
        }

        if !buffer.isEmpty {
            paragraphs.append(buffer.joined(separator: " "))
        }

        guard paragraphs.count > 1 else { return text }
        return paragraphs.joined(separator: "\n\n")
    }

    private static func structureSentences(in text: String) -> String {
        let sentences = splitAfterSentenceTerminators(in: text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard sentences.count > 1 else { return text }
        return sentences.joined(separator: "\n\n")
    }

    private static func splitAfterSentenceTerminators(in text: String) -> [String] {
        var sentences: [String] = []
        var current = ""

        for character in text {
            current.append(character)

            if ".!?".contains(character) {
                sentences.append(current)
                current = ""
            }
        }

        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentences.append(current)
        }

        return sentences
    }
}

private extension String {
    var normalizedDuplicateToken: String {
        lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }
}
