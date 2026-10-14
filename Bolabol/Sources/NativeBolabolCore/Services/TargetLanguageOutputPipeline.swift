import Foundation

/// Verified target-language output chain (ADR-029, Q3a/Q5a).
///
/// V1/V2 + active target: polish(target) → verify → strict polish → verify →
/// translation provider on polished text (else Raw) → verify → source fallback
/// (requested polished variant if polishing succeeded, otherwise Raw).
/// Raw + native ASR: verify only, never an LLM.
public enum TargetLanguageOutputPipeline {
    public enum OutcomeKind: String, Equatable, Sendable {
        case translated
        case sourceFallback
        case verifiedNative
    }

    public struct Outcome: Equatable, Sendable {
        public var text: String
        public var verifiedCode: String?
        public var kind: OutcomeKind
        /// Translation path used, e.g. provider id or "strict-polish".
        public var via: String?
        /// Machine-readable fallback reason for the ledger + note badge.
        public var reason: String?

        public init(text: String, verifiedCode: String?, kind: OutcomeKind, via: String? = nil, reason: String? = nil) {
            self.text = text
            self.verifiedCode = verifiedCode
            self.kind = kind
            self.via = via
            self.reason = reason
        }
    }

    public struct Context: Sendable {
        public var snapshot: HotkeyLanguageSnapshot
        public var requestedVariant: ProcessingVariant
        public var primaryCode: String?
        public var additionalCode: String?
        public var budget: CloudKeyFailover.TimeBudget
        public var startedAt: Date

        public init(
            snapshot: HotkeyLanguageSnapshot,
            requestedVariant: ProcessingVariant,
            primaryCode: String? = nil,
            additionalCode: String? = nil,
            budget: CloudKeyFailover.TimeBudget = .default,
            startedAt: Date = Date()
        ) {
            self.snapshot = snapshot
            self.requestedVariant = requestedVariant
            self.primaryCode = primaryCode
            self.additionalCode = additionalCode
            self.budget = budget
            self.startedAt = startedAt
        }

        func remaining() -> TimeInterval {
            max(0, budget.hardCapSeconds - Date().timeIntervalSince(startedAt))
        }
    }

    public typealias PolishStep = @Sendable (_ text: String, _ strict: Bool) async throws -> String
    public typealias TranslateStep = @Sendable (_ text: String, _ targetCode: String) async throws -> String
    public typealias VerifyStep = @Sendable (_ text: String) -> OutputLanguageVerifier.Decision

    /// Runs the bounded chain. `polishText` is the polished variant text when
    /// polishing succeeded; nil when polishing failed/timed out.
    public static func run(
        rawText: String,
        polishText: String?,
        polishSucceeded: Bool,
        context: Context,
        polish: PolishStep? = nil,
        translate: TranslateStep? = nil,
        verify: VerifyStep? = nil
    ) async -> Outcome {
        let snapshot = context.snapshot
        let target = snapshot.targetCode?.lowercased()
        let verifier: VerifyStep = verify ?? { text in
            guard let target else {
                return .pass(detected: nil, confidence: 0)
            }
            return OutputLanguageVerifier.verify(
                text: text,
                targetCode: target,
                primaryCode: context.primaryCode,
                additionalCode: context.additionalCode
            )
        }
        func isPass(_ decision: OutputLanguageVerifier.Decision) -> Bool {
            // Inconclusive short/mixed text must not block insertion; only an
            // explicit wrong-language verdict continues the chain.
            if case .fail = decision { return false }
            return true
        }
        func verifiedCode(_ decision: OutputLanguageVerifier.Decision) -> String? {
            switch decision {
            case .pass(let detected, _): return detected ?? target
            case .inconclusive(let detected, _): return detected ?? target
            case .fail: return nil
            }
        }
        func fallback(reason: String) -> Outcome {
            // Q3a: requested polished variant if polishing succeeded, else Raw.
            // Raw transcript is never overwritten by translation.
            if polishSucceeded, let polishText, !polishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return Outcome(text: polishText, verifiedCode: nil, kind: .sourceFallback, reason: reason)
            }
            return Outcome(text: rawText, verifiedCode: nil, kind: .sourceFallback, reason: reason)
        }

        guard snapshot.wantsTarget, let target else {
            return Outcome(text: rawText, verifiedCode: nil, kind: .verifiedNative)
        }

        // Raw + native ASR: verify only, never call an LLM.
        if snapshot.mechanism == .nativeASR || snapshot.hotkeyTarget == .raw {
            let decision = verifier(rawText)
            if isPass(decision) {
                return Outcome(text: rawText, verifiedCode: verifiedCode(decision), kind: .verifiedNative)
            }
            return Outcome(text: rawText, verifiedCode: nil, kind: .sourceFallback, reason: "native-asr-wrong-language")
        }

        // V1/V2 polishing path. First-try polish output arrives via polishText;
        // verify it before any retry/translation spend.
        if let polishText, !polishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let first = verifier(polishText)
            if isPass(first) {
                return Outcome(text: polishText, verifiedCode: verifiedCode(first), kind: .translated, via: "polish")
            }
            // Strict retry once, raced against the chain cap. A throw — or a
            // still-wrong language — is a translation failure, not "no
            // polished text": fall through so the provider still runs on the
            // polished source text (Q3a).
            if let polish, context.remaining() > 0 {
                do {
                    let strict = try await CloudKeyFailover.withTimeout(seconds: context.remaining()) {
                        try await polish(rawText, true)
                    }
                    let decision = verifier(strict)
                    if isPass(decision) {
                        return Outcome(text: strict, verifiedCode: verifiedCode(decision), kind: .translated, via: "strict-polish")
                    }
                } catch {
                    // Fall through to the translation provider below.
                }
            }
            // Translation provider on polished text, else Raw. The step
            // (including its key failover) shares `translationSeconds`,
            // capped by the chain cap; in-flight work is cancelled at the cap.
            let sourceForTranslation = polishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? rawText : polishText
            if let translate, context.remaining() > 0 {
                do {
                    let translated = try await CloudKeyFailover.withTimeout(
                        seconds: min(context.budget.translationSeconds, context.remaining())
                    ) {
                        try await translate(sourceForTranslation, target)
                    }
                    let decision = verifier(translated)
                    if isPass(decision) {
                        return Outcome(text: translated, verifiedCode: verifiedCode(decision), kind: .translated, via: "translation-provider")
                    }
                    return fallback(reason: "translation-wrong-language")
                } catch {
                    if context.remaining() <= 0 {
                        return fallback(reason: "deadline")
                    }
                    return fallback(reason: "translation-error")
                }
            }
            if context.remaining() <= 0 {
                return fallback(reason: "deadline")
            }
            return fallback(reason: "polish-wrong-language")
        }

        // No polished text at all (polish failed): provider on Raw, else fallback.
        if let translate, context.remaining() > 0 {
            do {
                let translated = try await CloudKeyFailover.withTimeout(
                    seconds: min(context.budget.translationSeconds, context.remaining())
                ) {
                    try await translate(rawText, target)
                }
                let decision = verifier(translated)
                if isPass(decision) {
                    return Outcome(text: translated, verifiedCode: verifiedCode(decision), kind: .translated, via: "translation-provider")
                }
                return fallback(reason: "translation-wrong-language")
            } catch {
                if context.remaining() <= 0 {
                    return fallback(reason: "deadline")
                }
                return fallback(reason: "translation-error")
            }
        }
        if context.remaining() <= 0 {
            return fallback(reason: "deadline")
        }
        return fallback(reason: "polish-failed")
    }
}
