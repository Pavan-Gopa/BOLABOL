#!/usr/bin/env bash
# QA/scripts/a2_workflowstore_normalized_id.sh — A2 (§8.3 / A6 prep): legacy engine
# provider ids are normalized to the keys estimateCost uses, so per-provider cost
# resolves later. Assert gemini-cloud -> gemini, gpt-cloud -> openai, default passthrough.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Sources/VaniScript/Stores/WorkflowStore.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq "private static func normalizedUsageProviderId(_ id: String) -> String" "$FILE" \
  || { echo "FAIL: normalizedUsageProviderId missing"; exit 1; }
grep -Fq 'case "gemini-cloud": return "gemini"' "$FILE" \
  || { echo "FAIL: gemini-cloud must normalize to gemini"; exit 1; }
grep -Fq 'case "gpt-cloud": return "openai"' "$FILE" \
  || { echo "FAIL: gpt-cloud must normalize to openai"; exit 1; }
grep -Fq "default: return id" "$FILE" \
  || { echo "FAIL: unknown provider ids must pass through unchanged"; exit 1; }
# The recorder must be fed the normalized id (not the raw legacy id).
grep -Fq "let providerId = Self.normalizedUsageProviderId(provider.id)" "$FILE" \
  || { echo "FAIL: recordCloudTranslationUsage must use the normalized provider id"; exit 1; }

echo "PASS: normalizedUsageProviderId maps gemini-cloud->gemini, gpt-cloud->openai, default passthrough."
