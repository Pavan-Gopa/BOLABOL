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

    public static func apply(to text: String, entries: [GlossaryEntry], target: Target) -> Result {
        var nextText = text
        var count = 0

        for entry in entries {
            let replacement = replacement(for: entry, target: target)
            guard !replacement.isEmpty else { continue }

            let variants = variants(for: entry, target: target, replacement: replacement)
            for variant in variants.sorted(by: { $0.count > $1.count }) {
                guard nextText.localizedCaseInsensitiveContains(variant) else {
                    continue
                }

                let pattern = #"(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: variant) + #"(?![\p{L}\p{N}_])"#
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

    public static func apply(to cues: [TranscriptCue], entries: [GlossaryEntry], target: Target) -> ([TranscriptCue], Int) {
        var total = 0
        let rewritten = cues.map { cue in
            let result = apply(to: cue.text, entries: entries, target: target)
            total += result.count
            guard result.count > 0 else { return cue }
            return TranscriptCue(
                startSec: cue.startSec,
                endSec: cue.endSec,
                text: result.text,
                words: approximateWords(for: result.text, source: cue)
            )
        }
        return (rewritten, total)
    }

    private static func replacement(for entry: GlossaryEntry, target: Target) -> String {
        switch target {
        case .source:
            entry.source.trimmingCharacters(in: .whitespacesAndNewlines)
        case .translation:
            entry.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func variants(for entry: GlossaryEntry, target: Target, replacement: String) -> [String] {
        let oppositeCorrect = target == .source ? entry.translation : entry.source
        let candidates = entry.variants + [oppositeCorrect]
        var seen = Set<String>()
        return candidates.compactMap { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = clean.lowercased()
            let replacementKey = replacement.lowercased()
            guard !clean.isEmpty, key != replacementKey, !seen.contains(key) else {
                return nil
            }
            seen.insert(key)
            return clean
        }
    }

    private static func approximateWords(for text: String, source: TranscriptCue) -> [TranscriptWord] {
        let splitWords = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !splitWords.isEmpty else { return [] }
        let duration = max(0.05, source.endSec - source.startSec)
        let step = duration / Double(splitWords.count)
        return splitWords.enumerated().map { index, word in
            let start = source.startSec + Double(index) * step
            let end = index == splitWords.count - 1 ? source.endSec : min(source.endSec, start + step)
            return TranscriptWord(startSec: start, endSec: max(start + 0.03, end), text: word)
        }
    }
}
