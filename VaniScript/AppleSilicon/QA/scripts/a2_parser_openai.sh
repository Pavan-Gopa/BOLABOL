#!/usr/bin/env bash
# QA/scripts/a2_parser_openai.sh — A2 (§8.1): parseOpenAIUsage extracts OpenAI-compatible
# usage.prompt_tokens (input) / usage.completion_tokens (output), shared by
# OpenAI/Qwen/OpenRouter/Ollama. Assert the snake_case CodingKeys and nil-on-empty.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Sources/VaniScriptCore/UsageRecorder.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq "public static func parseOpenAIUsage(from data: Data) -> TokenUsage?" "$FILE" \
  || { echo "FAIL: parseOpenAIUsage(from:) -> TokenUsage? missing"; exit 1; }
grep -Fq "var usage: OpenAIUsageBlock?" "$FILE" \
  || { echo "FAIL: OpenAI envelope must model a usage block"; exit 1; }
# Wire format is snake_case; assert the CodingKeys mapping (not Swift camelCase).
grep -Fq 'case promptTokens = "prompt_tokens"' "$FILE" \
  || { echo "FAIL: prompt_tokens CodingKey mapping missing"; exit 1; }
grep -Fq 'case completionTokens = "completion_tokens"' "$FILE" \
  || { echo "FAIL: completion_tokens CodingKey mapping missing"; exit 1; }
grep -Fq "inputTokens: usageBlock.promptTokens ?? 0" "$FILE" \
  || { echo "FAIL: OpenAI input must map prompt_tokens"; exit 1; }
grep -Fq "outputTokens: usageBlock.completionTokens ?? 0" "$FILE" \
  || { echo "FAIL: OpenAI output must map completion_tokens"; exit 1; }

echo "PASS: parseOpenAIUsage reads usage.prompt_tokens/completion_tokens (snake_case)."
