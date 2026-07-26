#!/usr/bin/env bash
# QA/scripts/a2_tests_coverage_areas.sh — A2 (Done §5): the 14 tests must cover the real
# risk areas: record increment, last*, per-model keys, audio-without-tokens, best-effort
# no-op (nil + empty delta), blank-model key, Gemini/OpenAI parsing, missing-usage -> nil,
# malformed -> nil, JSON round-trip, and TokenUsage arithmetic. Assert each test exists.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Tests/VaniScriptCoreTests/UsageRecorderTests.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

for fn in \
  recordsFreshTranslation \
  accumulatesRepeatedTransactions \
  keepsPerModelKeysDistinct \
  recordsAudioWithoutTokens \
  bestEffortNoOpOnNilDelta \
  bestEffortNoOpOnEmptyDelta \
  blankModelUsesProviderOnlyKey \
  parsesGeminiUsage \
  geminiMissingUsageReturnsNil \
  parsesOpenAIUsage \
  openAIMissingUsageReturnsNil \
  malformedJsonReturnsNil \
  roundTripParseRecordEncodeDecode \
  tokenUsageAddition; do
  grep -Fq "func $fn(" "$FILE" || { echo "FAIL: missing test case '$fn'"; exit 1; }
done

# The two parser wire formats must actually appear in the mock JSON.
grep -Fq "promptTokenCount" "$FILE" || { echo "FAIL: Gemini mock JSON (promptTokenCount) missing"; exit 1; }
grep -Fq "prompt_tokens" "$FILE" || { echo "FAIL: OpenAI mock JSON (prompt_tokens) missing"; exit 1; }

echo "PASS: UsageRecorderTests covers record/last*/per-model/best-effort/parsers/round-trip/arithmetic."
