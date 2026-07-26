#!/usr/bin/env bash
# QA/scripts/a2_translation_accumulator.sh — A2 (§8.1): CloudTextTranslationEngine is an
# actor that accumulates per-call usage across the several HTTP calls one logical
# operation may fan out into, then exposes takeLastUsage() (read-and-reset). Assert the
# accumulator, the sum/ignore-empty fold, the defer-reset, and that generate* feeds it.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Sources/VaniScript/Services/CloudTextTranslationEngine.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq "actor CloudTextTranslationEngine" "$FILE" \
  || { echo "FAIL: CloudTextTranslationEngine must be an actor (serialized usage mutations)"; exit 1; }
grep -Fq "private var accumulatedUsage: TokenUsage?" "$FILE" \
  || { echo "FAIL: accumulatedUsage accumulator missing"; exit 1; }
grep -Fq "private func accumulate(_ delta: TokenUsage?)" "$FILE" \
  || { echo "FAIL: accumulate(_:) fold missing"; exit 1; }
# nil/empty deltas ignored; non-empty summed.
grep -Fq "guard let delta, !delta.isEmpty else { return }" "$FILE" \
  || { echo "FAIL: accumulate must ignore nil/empty deltas"; exit 1; }
grep -Fq "accumulatedUsage = (accumulatedUsage ?? TokenUsage(inputTokens: 0, outputTokens: 0)) + delta" "$FILE" \
  || { echo "FAIL: accumulate must SUM deltas via TokenUsage.+"; exit 1; }
# takeLastUsage reads and resets exactly once.
grep -Fq "func takeLastUsage() -> TokenUsage?" "$FILE" \
  || { echo "FAIL: takeLastUsage() missing"; exit 1; }
grep -Fq "defer { accumulatedUsage = nil }" "$FILE" \
  || { echo "FAIL: takeLastUsage must reset the accumulator via defer"; exit 1; }
# generate* paths feed the accumulator from the Core parsers.
grep -Fq "accumulate(UsageRecorder.parseGeminiUsage(from: data))" "$FILE" \
  || { echo "FAIL: Gemini generate path must accumulate parsed usage"; exit 1; }
grep -Fq "accumulate(UsageRecorder.parseOpenAIUsage(from: data))" "$FILE" \
  || { echo "FAIL: OpenAI generate path must accumulate parsed usage"; exit 1; }

echo "PASS: translation engine accumulates per-call usage and exposes a read-and-reset takeLastUsage()."
