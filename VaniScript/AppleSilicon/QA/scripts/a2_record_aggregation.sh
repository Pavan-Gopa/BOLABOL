#!/usr/bin/env bash
# QA/scripts/a2_record_aggregation.sh — A2 (§8.2): record(...) aggregates one
# transaction into the persisted [String: ProviderUsage] map. Assert the signature and
# that it increments sessions/input/output/audio and refreshes every last* field.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Sources/VaniScriptCore/UsageRecorder.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq "into usage: inout [String: ProviderUsage]" "$FILE" \
  || { echo "FAIL: record(into: inout [String: ProviderUsage]) signature missing"; exit 1; }
for sym in "providerId: String" "model: String" "delta: TokenUsage?" "audioMinutes: Double" "now: Date"; do
  grep -Fq "$sym" "$FILE" || { echo "FAIL: record(...) parameter '$sym' missing"; exit 1; }
done

# Aggregation body.
for body in \
  "entry.sessions += 1" \
  "entry.inputTokens += delta?.inputTokens ?? 0" \
  "entry.outputTokens += delta?.outputTokens ?? 0" \
  "entry.audioMinutes += audioMinutes" \
  "entry.lastUsed = timestamp" \
  "entry.lastInputTokens = delta?.inputTokens" \
  "entry.lastOutputTokens = delta?.outputTokens" \
  "entry.lastModel = model" \
  "entry.lastTransactionAt = timestamp" \
  "usage[key] = entry"; do
  grep -Fq "$body" "$FILE" || { echo "FAIL: record body missing '$body'"; exit 1; }
done

echo "PASS: UsageRecorder.record increments sessions/tokens/audio and refreshes last* fields."
