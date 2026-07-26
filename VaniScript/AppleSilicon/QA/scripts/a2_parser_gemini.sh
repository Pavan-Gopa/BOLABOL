#!/usr/bin/env bash
# QA/scripts/a2_parser_gemini.sh — A2 (§8.1): parseGeminiUsage extracts Gemini
# generateContent usage: usageMetadata.promptTokenCount (input) / candidatesTokenCount
# (output). Assert the parser reads those exact fields and yields nil on empty usage.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Sources/VaniScriptCore/UsageRecorder.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq "public static func parseGeminiUsage(from data: Data) -> TokenUsage?" "$FILE" \
  || { echo "FAIL: parseGeminiUsage(from:) -> TokenUsage? missing"; exit 1; }
grep -Fq "var usageMetadata: GeminiUsageMetadata?" "$FILE" \
  || { echo "FAIL: Gemini envelope must model usageMetadata"; exit 1; }
grep -Fq "var promptTokenCount: Int?" "$FILE" || { echo "FAIL: promptTokenCount field missing"; exit 1; }
grep -Fq "var candidatesTokenCount: Int?" "$FILE" || { echo "FAIL: candidatesTokenCount field missing"; exit 1; }
grep -Fq "inputTokens: meta.promptTokenCount ?? 0" "$FILE" \
  || { echo "FAIL: Gemini input must map promptTokenCount"; exit 1; }
grep -Fq "outputTokens: meta.candidatesTokenCount ?? 0" "$FILE" \
  || { echo "FAIL: Gemini output must map candidatesTokenCount"; exit 1; }
# Empty usage -> nil (do not pollute stats with zeros).
grep -Fq "return usage.isEmpty ? nil : usage" "$FILE" \
  || { echo "FAIL: parseGeminiUsage must return nil for empty usage"; exit 1; }

echo "PASS: parseGeminiUsage reads usageMetadata prompt/candidatesTokenCount, nil on empty."
