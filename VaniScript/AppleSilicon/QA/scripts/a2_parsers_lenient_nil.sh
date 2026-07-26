#!/usr/bin/env bash
# QA/scripts/a2_parsers_lenient_nil.sh — A2 (invariant §14.4): both usage parsers are
# lenient — any decode failure or missing usage block yields nil rather than throwing,
# because a usage read must never break the surrounding request. Assert `try?` decode,
# optional return, explicit nil on missing block, and no `throw` in the parser bodies.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Sources/VaniScriptCore/UsageRecorder.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

# Lenient decode via try? for both envelopes.
n_try="$(grep -Fc "try? JSONDecoder().decode" "$FILE")"
[[ "$n_try" -ge 2 ]] || { echo "FAIL: expected >=2 lenient 'try? JSONDecoder().decode' (Gemini+OpenAI), got $n_try"; exit 1; }

# Missing usage block -> nil for both parsers.
grep -Fq "let meta = decoded.usageMetadata else {" "$FILE" \
  || { echo "FAIL: Gemini parser must guard on missing usageMetadata -> nil"; exit 1; }
grep -Fq "let usageBlock = decoded.usage else {" "$FILE" \
  || { echo "FAIL: OpenAI parser must guard on missing usage block -> nil"; exit 1; }

# Parsers must never throw: no `throw ` statement in the file (they return optionals).
if grep -Eq "(^|[^a-zA-Z])throw " "$FILE"; then
  echo "FAIL: UsageRecorder parsers must be non-throwing (no 'throw' statements)"; exit 1
fi

echo "PASS: both usage parsers are lenient (try?, optional, nil on missing block, non-throwing)."
