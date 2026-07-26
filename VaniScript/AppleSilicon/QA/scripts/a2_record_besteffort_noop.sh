#!/usr/bin/env bash
# QA/scripts/a2_record_besteffort_noop.sh — A2 (invariant §14.4): record(...) is a no-op
# when the call produced no signal (nil/empty delta AND no audio), so a provider that
# omits usage never creates empty statistics entries. Assert the guard.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Sources/VaniScriptCore/UsageRecorder.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq "let hasTokens = (delta?.isEmpty == false)" "$FILE" \
  || { echo "FAIL: hasTokens derivation missing"; exit 1; }
grep -Fq "let hasAudio = audioMinutes > 0" "$FILE" \
  || { echo "FAIL: hasAudio derivation missing"; exit 1; }
grep -Fq "guard hasTokens || hasAudio else { return }" "$FILE" \
  || { echo "FAIL: best-effort no-op guard (hasTokens || hasAudio) missing"; exit 1; }

echo "PASS: record() is a best-effort no-op when there is no token/audio signal."
