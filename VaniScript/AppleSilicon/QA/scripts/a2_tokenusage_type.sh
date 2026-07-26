#!/usr/bin/env bash
# QA/scripts/a2_tokenusage_type.sh — A2 (§8.1): TokenUsage is the public value type
# carried out of the engines. Assert: public struct, Equatable + Sendable (crosses
# actor boundary), inputTokens/outputTokens fields, isEmpty, and a `+` operator for
# per-call accumulation.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Sources/VaniScriptCore/UsageRecorder.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq "public struct TokenUsage: Equatable, Sendable" "$FILE" \
  || { echo "FAIL: TokenUsage must be a public struct, Equatable + Sendable"; exit 1; }
grep -Fq "public var inputTokens: Int" "$FILE" || { echo "FAIL: TokenUsage.inputTokens missing"; exit 1; }
grep -Fq "public var outputTokens: Int" "$FILE" || { echo "FAIL: TokenUsage.outputTokens missing"; exit 1; }
grep -Fq "public var isEmpty: Bool" "$FILE" || { echo "FAIL: TokenUsage.isEmpty missing"; exit 1; }
grep -Fq "public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage" "$FILE" \
  || { echo "FAIL: TokenUsage `+` operator missing"; exit 1; }
grep -Fq "public init(inputTokens: Int, outputTokens: Int)" "$FILE" \
  || { echo "FAIL: TokenUsage public memberwise init missing"; exit 1; }

echo "PASS: TokenUsage is a public, Sendable value type with isEmpty and `+`."
