import Foundation
import NaturalLanguage

/// Gates insertion on the real output language (ADR-029).
/// Replaces ScriptProfile and Cyrillic-regex heuristics.
public enum OutputLanguageVerifier {
    public enum Decision: Equatable, Sendable {
        case pass(detected: String?, confidence: Double)
        case fail(detected: String, confidence: Double)
        case inconclusive(detected: String?, confidence: Double)
    }

    /// Short-text rule: below this many letters the recognizer is unreliable.
    public static let inconclusiveLetterCount = 12

    public static func verify(
        text: String,
        targetCode: String,
        primaryCode: String? = nil,
        additionalCode: String? = nil
    ) -> Decision {
        let target = targetCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let stripped = strippingIdentifiersAndURLs(text)
        let letters = stripped.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .inconclusive(detected: nil, confidence: 0)
        }
        let recognizer = NLLanguageRecognizer()
        var constraints: [NLLanguage] = []
        for code in [target, primaryCode, additionalCode].compactMap({ $0 }) {
            let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let lang = NLLanguage(normalized)
            if !constraints.contains(lang) {
                constraints.append(lang)
            }
        }
        if !constraints.isEmpty {
            recognizer.languageConstraints = constraints
        }
        recognizer.processString(stripped)
        guard let top = recognizer.languageHypotheses(withMaximum: 1).first else {
            return .inconclusive(detected: nil, confidence: 0)
        }
        let detected = top.key.rawValue.lowercased()
        let confidence = top.value
        if letters.count < inconclusiveLetterCount {
            // Short text is decided by script alone: a match passes, a
            // mismatch is a miss so the pipeline continues the bounded
            // chain (strict retry → translation provider) instead of
            // silently inserting source-language output (S11 J2).
            if scriptMatches(detected: detected, target: target, text: stripped) {
                return .pass(detected: detected, confidence: confidence)
            }
            return .fail(detected: detected, confidence: confidence)
        }
        if detected == target {
            return confidence >= 0.5
                ? .pass(detected: detected, confidence: confidence)
                : .inconclusive(detected: detected, confidence: confidence)
        }
        return confidence >= 0.6
            ? .fail(detected: detected, confidence: confidence)
            : .inconclusive(detected: detected, confidence: confidence)
    }

    /// Removes URLs and code-like tokens (contain . _ / : = or digits, or
    /// interior capitals) that skew NLLanguageRecognizer on mixed dictation.
    public static func strippingIdentifiersAndURLs(_ text: String) -> String {
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let kept = tokens.filter { !isIdentifierLike($0) }
        let joined = kept.joined(separator: " ")
        if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return joined
    }

    private static func isIdentifierLike(_ token: String) -> Bool {
        let lower = token.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") {
            return true
        }
        if token.contains("@") { return true }
        let codeChars: Set<Character> = [".", "_", "/", ":", "=", "\\", "#", "<", ">", "(", ")"]
        if token.contains(where: { codeChars.contains($0) || $0.isNumber }) {
            // Keep short plain words with trailing punctuation (e.g. "build,").
            let lettersOnly = token.filter { $0.isLetter }
            if lettersOnly.count >= 3, !token.contains(where: { codeChars.contains($0) }) {
                return false
            }
            return true
        }
        // camelCase / interior capitals, e.g. NoteStore.enforceAudioArchiveLimit
        let letters = Array(token.filter { $0.isLetter })
        if letters.count >= 4 {
            let tail = letters.dropFirst()
            if tail.contains(where: { $0.isUppercase }) { return true }
        }
        return false
    }

    /// Short-text gate shared with the A-mode source lock: below
    /// `inconclusiveLetterCount` letters the recognizer is unreliable, so the
    /// first pass is kept instead of strict-retrying (S11 J2).
    public static func isShortText(_ text: String) -> Bool {
        let stripped = strippingIdentifiersAndURLs(text)
        let letters = stripped.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        return letters.count < inconclusiveLetterCount
    }

    private static func scriptMatches(detected: String, target: String, text: String) -> Bool {
        let cyrillicTargets: Set<String> = ["ru", "uk", "bg", "sr", "be", "mk"]
        let hasCyrillic = text.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil
        if cyrillicTargets.contains(target) {
            return hasCyrillic
        }
        if target == "en" {
            // The constrained recognizer reports `en` for any short text, so
            // `detected == target` must not override a wrong script (S11 J2):
            // any non-Latin letter is a miss. Latin-only and letterless text
            // (numbers, punctuation) still pass.
            if hasCyrillic { return false }
            return text.range(of: "[^\\p{Latin}\\P{L}]", options: .regularExpression) == nil
        }
        return detected == target
    }
}
