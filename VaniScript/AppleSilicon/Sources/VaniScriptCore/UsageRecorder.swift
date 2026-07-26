import Foundation

// MARK: - Role
//
// `UsageRecorder` is the pure, side-effect-free aggregation layer for API usage
// statistics (API_USAGE track, step A2 — see docs/API_USAGE_ARCHITECTURE.md §8).
//
// It owns two responsibilities and nothing else:
//   1. Parsing token counters out of raw provider API responses
//      (`parseGeminiUsage` / `parseOpenAIUsage`).
//   2. Aggregating a single transaction's `TokenUsage` delta into the persisted
//      `[String: ProviderUsage]` map (`record`).
//
// It must NOT perform I/O, touch settings persistence, or know about engines /
// stores. This purity is deliberate: it makes the recorder trivially unit-testable
// with mock JSON and mock usage maps (UsageRecorderTests), and lets callers treat
// usage recording as best-effort (invariant §14.4: a usage failure never fails the
// transcription/translation itself — callers simply pass `nil` and nothing is written).

/// Token counters extracted from one API response.
///
/// `nil` at the call site means "the provider did not return usage for this call"
/// (e.g. a whisper transcription without a usage block). In that case the recorder
/// does not increment token totals — statistics simply stay unchanged rather than
/// being polluted with zeros.
public struct TokenUsage: Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    /// True when both counters are zero — treated as "no meaningful usage".
    public var isEmpty: Bool { inputTokens == 0 && outputTokens == 0 }

    /// Sum two deltas. Engines that fan a single logical operation out into several
    /// HTTP calls (e.g. batched cue translation) accumulate per-call usage this way
    /// before handing a single delta to `record`.
    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens
        )
    }
}

public enum UsageRecorder {
    /// Aggregate one transaction into the usage map.
    ///
    /// - Parameters:
    ///   - usage: The persisted per-`providerId:model` statistics (mutated in place).
    ///   - providerId: Normalized provider id (e.g. `"gemini"`, `"openai"`) — keep in
    ///     sync with `estimateCost`'s provider keys so A6 cost display resolves.
    ///   - model: Model id used for the call. Combined with `providerId` to form the
    ///     dictionary key `"providerId:model"` (§6.2), giving per-model statistics.
    ///   - delta: Token counters for this call, or `nil` if the API returned none.
    ///   - audioMinutes: Minutes of audio processed (transcription); `0` for text ops.
    ///   - now: Injectable clock for deterministic tests.
    ///
    /// No-op when there is nothing to record (`delta` is nil/empty AND no audio), so
    /// a provider that omits usage never creates empty statistics entries.
    public static func record(
        into usage: inout [String: ProviderUsage],
        providerId: String,
        model: String,
        delta: TokenUsage?,
        audioMinutes: Double = 0,
        now: Date = Date()
    ) {
        let hasTokens = (delta?.isEmpty == false)
        let hasAudio = audioMinutes > 0
        // Best-effort contract: skip entirely when the call produced no signal.
        guard hasTokens || hasAudio else { return }

        let key = usageKey(providerId: providerId, model: model)
        let timestamp = iso8601Timestamp(from: now)

        var entry = usage[key] ?? ProviderUsage()
        entry.sessions += 1
        entry.inputTokens += delta?.inputTokens ?? 0
        entry.outputTokens += delta?.outputTokens ?? 0
        entry.audioMinutes += audioMinutes
        entry.lastUsed = timestamp
        entry.lastInputTokens = delta?.inputTokens
        entry.lastOutputTokens = delta?.outputTokens
        entry.lastModel = model
        entry.lastTransactionAt = timestamp
        usage[key] = entry
    }

    /// Dictionary key for per-model statistics. Falls back to just the provider id
    /// when the model is blank so we never produce a dangling `"provider:"` key.
    public static func usageKey(providerId: String, model: String) -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedModel.isEmpty ? providerId : "\(providerId):\(trimmedModel)"
    }

    // MARK: - Response parsers
    //
    // Parsers live here (not in the app-target engines) so they are reachable from
    // VaniScriptCore unit tests with mock JSON. Both are lenient: any decode failure
    // or missing usage block yields `nil` rather than throwing, because a usage read
    // must never break the surrounding request (invariant §14.4).

    /// Parse Gemini `generateContent` usage: `usageMetadata.promptTokenCount` (input)
    /// and `usageMetadata.candidatesTokenCount` (output).
    public static func parseGeminiUsage(from data: Data) -> TokenUsage? {
        guard let decoded = try? JSONDecoder().decode(GeminiUsageEnvelope.self, from: data),
              let meta = decoded.usageMetadata else {
            return nil
        }
        let usage = TokenUsage(
            inputTokens: meta.promptTokenCount ?? 0,
            outputTokens: meta.candidatesTokenCount ?? 0
        )
        return usage.isEmpty ? nil : usage
    }

    /// Parse OpenAI-compatible usage: `usage.prompt_tokens` (input) and
    /// `usage.completion_tokens` (output). Shared by OpenAI/Qwen/OpenRouter/Ollama.
    public static func parseOpenAIUsage(from data: Data) -> TokenUsage? {
        guard let decoded = try? JSONDecoder().decode(OpenAIUsageEnvelope.self, from: data),
              let usageBlock = decoded.usage else {
            return nil
        }
        let usage = TokenUsage(
            inputTokens: usageBlock.promptTokens ?? 0,
            outputTokens: usageBlock.completionTokens ?? 0
        )
        return usage.isEmpty ? nil : usage
    }

    // Minimal Decodable envelopes: only the usage fields are modeled so these parsers
    // stay independent of the full engine response types.
    private struct GeminiUsageEnvelope: Decodable {
        var usageMetadata: GeminiUsageMetadata?
    }

    private struct GeminiUsageMetadata: Decodable {
        var promptTokenCount: Int?
        var candidatesTokenCount: Int?
        var totalTokenCount: Int?
    }

    private struct OpenAIUsageEnvelope: Decodable {
        var usage: OpenAIUsageBlock?
    }

    private struct OpenAIUsageBlock: Decodable {
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    // ISO-8601 timestamp for `lastUsed`/`lastTransactionAt` (sortable, matches the
    // string format used elsewhere for provider timestamps). Built per call because
    // `ISO8601DateFormatter` is not `Sendable` and this type must stay concurrency-safe.
    private static func iso8601Timestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
