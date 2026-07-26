#!/usr/bin/env bash
# QA/scripts/a2_record_per_model_key.sh — A2 (§6.2): statistics are keyed per
# `providerId:model`. Assert usageKey builds the composite key and falls back to a
# provider-only key for a blank model (never a dangling "provider:").
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Sources/VaniScriptCore/UsageRecorder.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq "public static func usageKey(providerId: String, model: String) -> String" "$FILE" \
  || { echo "FAIL: usageKey(providerId:model:) missing"; exit 1; }
# Composite key + blank-model fallback.
grep -Fq 'trimmedModel.isEmpty ? providerId : "\(providerId):\(trimmedModel)"' "$FILE" \
  || { echo "FAIL: usageKey must build providerId:model with blank-model fallback"; exit 1; }
# record() must key via usageKey (not ad-hoc string interpolation).
grep -Fq "let key = usageKey(providerId: providerId, model: model)" "$FILE" \
  || { echo "FAIL: record() must key the map via usageKey(...)"; exit 1; }

echo "PASS: usage statistics are keyed per providerId:model with a safe blank-model fallback."
