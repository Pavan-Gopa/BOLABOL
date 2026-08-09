#!/usr/bin/env bash
# Qwen listModels overlay (subscription model ids).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudModelCatalog.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
for m in "qwen3.8-max-preview" "qwen3.7-plus" "qwen3.7-max"; do
  grep -q "$m" "$FILE" || { echo "FAIL: Qwen subscription model missing: $m"; exit 1; }
done
grep -q "CloudProviderCatalog.qwenID" "$FILE" || { echo "FAIL: qwen overlay not gated by qwenID"; exit 1; }
echo "PASS: Qwen subscription model overlay present (qwen3.8/3.7 family)."
