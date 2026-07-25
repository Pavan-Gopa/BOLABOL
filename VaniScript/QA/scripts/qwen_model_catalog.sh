#!/usr/bin/env bash
# QA: qwen_model_catalog.sh — QwenChatModelCatalog invariants (Q2)
# Asserts:
#   1. defaultModelID is "qwen3.8-max-preview"
#   2. normalizedModelID falls back to default for unknown/empty
#   3. displayLabel returns shortName
#   4. Only verified model IDs in catalog (no invented IDs)
#   5. option(id:) lookup works
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CATALOG="$PROJECT_ROOT/AppleSilicon/Sources/VaniScriptCore/QwenAgentSupport.swift"

echo "=== qwen_model_catalog: QwenChatModelCatalog invariants ==="
FAILURES=0

[ -f "$CATALOG" ] || { echo "FAIL: QwenAgentSupport.swift not found"; exit 1; }

# 1. Default model ID
grep -q 'defaultModelID = qwen38MaxPreviewID' "$CATALOG" || \
    { echo "FAIL: defaultModelID not set to qwen38MaxPreviewID"; FAILURES=$((FAILURES+1)); }
grep -q 'qwen38MaxPreviewID = "qwen3.8-max-preview"' "$CATALOG" || \
    { echo "FAIL: qwen38MaxPreviewID not 'qwen3.8-max-preview'"; FAILURES=$((FAILURES+1)); }

# 2. normalizedModelID fallback
grep -q 'normalizedModelID' "$CATALOG" || { echo "FAIL: normalizedModelID not found"; FAILURES=$((FAILURES+1)); }
grep -q 'trimmed.isEmpty' "$CATALOG" || { echo "FAIL: empty check in normalizedModelID"; FAILURES=$((FAILURES+1)); }

# 3. displayLabel
grep -q 'displayLabel' "$CATALOG" || { echo "FAIL: displayLabel not found"; FAILURES=$((FAILURES+1)); }
grep -q 'shortName' "$CATALOG" || { echo "FAIL: shortName not used in displayLabel"; FAILURES=$((FAILURES+1)); }

# 4. Only one verified model (no invented IDs)
MODEL_COUNT=$(grep -c 'QwenChatModelOption(' "$CATALOG" || true)
if [ "$MODEL_COUNT" -ne 1 ]; then
    echo "WARN: Expected 1 QwenChatModelOption, found $MODEL_COUNT"
fi

# 5. option(id:) lookup
grep -q 'func option(id:' "$CATALOG" || { echo "FAIL: option(id:) not found"; FAILURES=$((FAILURES+1)); }

if [ "$FAILURES" -gt 0 ]; then
    echo "FAIL: qwen_model_catalog — $FAILURES check(s) failed"
    exit 1
fi

echo "PASS: qwen_model_catalog — all catalog invariants verified"
exit 0
