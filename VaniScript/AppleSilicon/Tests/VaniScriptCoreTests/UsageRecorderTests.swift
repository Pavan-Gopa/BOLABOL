import Testing
import Foundation
@testable import VaniScriptCore

// A2 (API_USAGE): unit tests for the pure usage-recording layer.
//  - `record` aggregation: sessions/token/audio increments, last* fields, per-model key.
//  - Response parsers: Gemini usageMetadata + OpenAI usage blocks, and the "no usage
//    block → nil" best-effort path.
//  - Best-effort invariant (§14.4): a nil/empty delta with no audio records nothing.
// These are pure data tests (no engines, no network) mirroring the A1 test style.
@Suite("UsageRecorder (A2)")
struct UsageRecorderTests {

    // Fixed clock so timestamp assertions are deterministic.
    private var fixedNow: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    // MARK: - record()

    @Test("records a translation transaction into a fresh usage map")
    func recordsFreshTranslation() throws {
        var usage: [String: ProviderUsage] = [:]
        UsageRecorder.record(
            into: &usage,
            providerId: "gemini",
            model: "gemini-2.5-flash",
            delta: TokenUsage(inputTokens: 100, outputTokens: 40),
            audioMinutes: 0,
            now: fixedNow
        )

        let entry = try #require(usage["gemini:gemini-2.5-flash"])
        #expect(entry.sessions == 1)
        #expect(entry.inputTokens == 100)
        #expect(entry.outputTokens == 40)
        #expect(entry.audioMinutes == 0)
        #expect(entry.lastInputTokens == 100)
        #expect(entry.lastOutputTokens == 40)
        #expect(entry.lastModel == "gemini-2.5-flash")
        #expect(!entry.lastUsed.isEmpty)
        #expect(entry.lastTransactionAt == entry.lastUsed)
    }

    @Test("accumulates repeated transactions on the same provider:model key")
    func accumulatesRepeatedTransactions() throws {
        var usage: [String: ProviderUsage] = [:]
        let delta = TokenUsage(inputTokens: 10, outputTokens: 5)
        UsageRecorder.record(into: &usage, providerId: "openai", model: "gpt-4o-mini", delta: delta, now: fixedNow)
        UsageRecorder.record(into: &usage, providerId: "openai", model: "gpt-4o-mini", delta: delta, now: fixedNow)

        let entry = try #require(usage["openai:gpt-4o-mini"])
        #expect(entry.sessions == 2)
        #expect(entry.inputTokens == 20)
        #expect(entry.outputTokens == 10)
        // last* reflect the most recent single transaction, not the running total.
        #expect(entry.lastInputTokens == 10)
        #expect(entry.lastOutputTokens == 5)
    }

    @Test("keeps per-model statistics under distinct keys")
    func keepsPerModelKeysDistinct() {
        var usage: [String: ProviderUsage] = [:]
        UsageRecorder.record(into: &usage, providerId: "gemini", model: "gemini-2.5-flash",
                             delta: TokenUsage(inputTokens: 1, outputTokens: 1), now: fixedNow)
        UsageRecorder.record(into: &usage, providerId: "gemini", model: "gemini-2.5-pro",
                             delta: TokenUsage(inputTokens: 2, outputTokens: 2), now: fixedNow)

        #expect(usage.count == 2)
        #expect(usage["gemini:gemini-2.5-flash"]?.inputTokens == 1)
        #expect(usage["gemini:gemini-2.5-pro"]?.inputTokens == 2)
    }

    @Test("records audio minutes even when the provider returned no token usage")
    func recordsAudioWithoutTokens() throws {
        var usage: [String: ProviderUsage] = [:]
        UsageRecorder.record(into: &usage, providerId: "openai", model: "whisper-1",
                             delta: nil, audioMinutes: 3.5, now: fixedNow)

        let entry = try #require(usage["openai:whisper-1"])
        #expect(entry.sessions == 1)
        #expect(entry.inputTokens == 0)
        #expect(entry.outputTokens == 0)
        #expect(entry.audioMinutes == 3.5)
        #expect(entry.lastInputTokens == nil)
        #expect(entry.lastOutputTokens == nil)
    }

    @Test("best-effort: nil delta with no audio records nothing")
    func bestEffortNoOpOnNilDelta() {
        var usage: [String: ProviderUsage] = [:]
        UsageRecorder.record(into: &usage, providerId: "gemini", model: "gemini-2.5-flash",
                             delta: nil, audioMinutes: 0, now: fixedNow)
        #expect(usage.isEmpty)
    }

    @Test("best-effort: an empty (zero) delta with no audio records nothing")
    func bestEffortNoOpOnEmptyDelta() {
        var usage: [String: ProviderUsage] = [:]
        UsageRecorder.record(into: &usage, providerId: "gemini", model: "gemini-2.5-flash",
                             delta: TokenUsage(inputTokens: 0, outputTokens: 0), now: fixedNow)
        #expect(usage.isEmpty)
    }

    @Test("blank model falls back to a provider-only key")
    func blankModelUsesProviderOnlyKey() {
        var usage: [String: ProviderUsage] = [:]
        UsageRecorder.record(into: &usage, providerId: "openai", model: "  ",
                             delta: TokenUsage(inputTokens: 1, outputTokens: 1), now: fixedNow)
        #expect(usage["openai"] != nil)
    }

    // MARK: - Gemini usage parsing

    @Test("parses Gemini usageMetadata token counts")
    func parsesGeminiUsage() throws {
        let json = """
        {
          "candidates": [{"content": {"parts": [{"text": "hola"}]}}],
          "usageMetadata": {"promptTokenCount": 321, "candidatesTokenCount": 45, "totalTokenCount": 366}
        }
        """
        let usage = try #require(UsageRecorder.parseGeminiUsage(from: Data(json.utf8)))
        #expect(usage.inputTokens == 321)
        #expect(usage.outputTokens == 45)
    }

    @Test("returns nil when Gemini response has no usageMetadata")
    func geminiMissingUsageReturnsNil() {
        let json = """
        {"candidates": [{"content": {"parts": [{"text": "hola"}]}}]}
        """
        #expect(UsageRecorder.parseGeminiUsage(from: Data(json.utf8)) == nil)
    }

    // MARK: - OpenAI-compatible usage parsing

    @Test("parses OpenAI-compatible usage token counts")
    func parsesOpenAIUsage() throws {
        let json = """
        {
          "choices": [{"message": {"role": "assistant", "content": "hola"}}],
          "usage": {"prompt_tokens": 200, "completion_tokens": 80, "total_tokens": 280}
        }
        """
        let usage = try #require(UsageRecorder.parseOpenAIUsage(from: Data(json.utf8)))
        #expect(usage.inputTokens == 200)
        #expect(usage.outputTokens == 80)
    }

    @Test("returns nil when OpenAI response has no usage block (e.g. whisper-1)")
    func openAIMissingUsageReturnsNil() {
        let json = """
        {"text": "transcribed text without a usage block"}
        """
        #expect(UsageRecorder.parseOpenAIUsage(from: Data(json.utf8)) == nil)
    }

    @Test("returns nil for malformed JSON rather than throwing")
    func malformedJsonReturnsNil() {
        let garbage = Data("not json".utf8)
        #expect(UsageRecorder.parseGeminiUsage(from: garbage) == nil)
        #expect(UsageRecorder.parseOpenAIUsage(from: garbage) == nil)
    }

    // MARK: - End-to-end round-trip (parse → record → persist)

    @Test("parsed Gemini usage records and survives a ProviderUsage round-trip")
    func roundTripParseRecordEncodeDecode() throws {
        let json = """
        {"usageMetadata": {"promptTokenCount": 12, "candidatesTokenCount": 7}}
        """
        let delta = UsageRecorder.parseGeminiUsage(from: Data(json.utf8))
        var usage: [String: ProviderUsage] = [:]
        UsageRecorder.record(into: &usage, providerId: "gemini", model: "gemini-2.5-flash",
                             delta: delta, now: fixedNow)

        let encoded = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode([String: ProviderUsage].self, from: encoded)
        let entry = try #require(decoded["gemini:gemini-2.5-flash"])
        #expect(entry.inputTokens == 12)
        #expect(entry.outputTokens == 7)
        #expect(entry.lastModel == "gemini-2.5-flash")
    }

    // MARK: - TokenUsage arithmetic

    @Test("TokenUsage addition sums both counters")
    func tokenUsageAddition() {
        let sum = TokenUsage(inputTokens: 3, outputTokens: 4) + TokenUsage(inputTokens: 10, outputTokens: 1)
        #expect(sum.inputTokens == 13)
        #expect(sum.outputTokens == 5)
        #expect(!sum.isEmpty)
        #expect(TokenUsage(inputTokens: 0, outputTokens: 0).isEmpty)
    }
}
