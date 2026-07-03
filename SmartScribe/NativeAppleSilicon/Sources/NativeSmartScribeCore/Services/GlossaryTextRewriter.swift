import Foundation

public enum GlossaryTextRewriter {
    public enum Target: Sendable {
        case source
        case translation
    }

    public struct Result: Equatable, Sendable {
        public var text: String
        public var count: Int

        public init(text: String, count: Int) {
            self.text = text
            self.count = count
        }
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var regexCache: [String: NSRegularExpression] = [:]

    public static func apply(
        to text: String,
        entries: [GlossaryEntry],
        target: Target,
        translationLanguage: String? = nil
    ) -> Result {
        var nextText = text
        var count = 0

        for entry in entries {
            let replacement = replacement(
                for: entry,
                target: target,
                translationLanguage: translationLanguage
            )
            guard !replacement.isEmpty else { continue }

            let variants = variants(for: entry, target: target, replacement: replacement)
            for variant in variants.sorted(by: { $0.count > $1.count }) {
                guard nextText.localizedCaseInsensitiveContains(variant) else {
                    continue
                }

                let pattern = #"(?<![\p{L}\p{N}_])"#
                    + NSRegularExpression.escapedPattern(for: variant)
                    + #"(?![\p{L}\p{N}_])"#
                guard let regex = cachedRegex(for: pattern) else {
                    continue
                }

                let range = NSRange(nextText.startIndex..<nextText.endIndex, in: nextText)
                let matches = regex.matches(in: nextText, range: range)
                guard !matches.isEmpty else { continue }

                count += matches.count
                nextText = regex.stringByReplacingMatches(
                    in: nextText,
                    range: NSRange(nextText.startIndex..<nextText.endIndex, in: nextText),
                    withTemplate: replacement
                )
            }
        }

        return Result(text: nextText, count: count)
    }

    private static func cachedRegex(for pattern: String) -> NSRegularExpression? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = regexCache[pattern] {
            return cached
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        regexCache[pattern] = regex
        return regex
    }

    private static func replacement(
        for entry: GlossaryEntry,
        target: Target,
        translationLanguage: String?
    ) -> String {
        switch target {
        case .source:
            return entry.source.trimmingCharacters(in: .whitespacesAndNewlines)
        case .translation:
            if let translationLanguage {
                if let localized = localizedTranslation(for: entry, language: translationLanguage) {
                    return localized
                }
                let hasNamedTranslations = entry.translations.keys.contains { key in
                    key.localizedCaseInsensitiveCompare("Default") != .orderedSame
                }
                return hasNamedTranslations
                    ? ""
                    : entry.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return entry.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func variants(
        for entry: GlossaryEntry,
        target: Target,
        replacement: String
    ) -> [String] {
        let oppositeCorrect = target == .source ? entry.translation : entry.source
        let candidates = entry.variants + [oppositeCorrect] + Array(entry.translations.values)
        let replacementKey = replacement.lowercased()
        var seen = Set<String>()

        return candidates.compactMap { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = clean.lowercased()
            guard !clean.isEmpty, key != replacementKey, !seen.contains(key) else {
                return nil
            }
            seen.insert(key)
            return clean
        }
    }

    private static func localizedTranslation(
        for entry: GlossaryEntry,
        language: String
    ) -> String? {
        let cleanLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLanguage.isEmpty else { return nil }

        guard let value = entry.translations.first(where: { key, _ in
            key.localizedCaseInsensitiveCompare(cleanLanguage) == .orderedSame
        })?.value else {
            return nil
        }

        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanValue.isEmpty ? nil : cleanValue
    }
}
