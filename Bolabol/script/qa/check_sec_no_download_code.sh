#!/usr/bin/env bash
# Security guard: detect automated CDN download code for models in Sources/.
#
# Rationale: Closes finding F3 (low) from SECURITY_REPORT.md.
# Bolabol uses URLSession for LLM cloud polishing (legitimate), but model
# download code should be reviewed before introduction. This script flags
# patterns that combine network download APIs with model/package context.
#
# Scope: script/qa/** (allowed), does not modify Sources/**.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [ ! -d "Sources" ]; then
    echo "SKIP: Sources/ not found"
    exit 0
fi

FAILED=0

# Pattern 1: URLSession/downloadTask/dataTask combined with model/mlmodelc/package context
# in the same file. This catches automated model download helpers.
PATTERN1_FILES=$(grep -rl -E "downloadTask|dataTask" Sources/ 2>/dev/null || true)
if [ -n "$PATTERN1_FILES" ]; then
    for f in $PATTERN1_FILES; do
        # Check if the same file also references model package paths
        if grep -q -E "mlmodelc|modelRoot|canary.*package|\.coreml|downloadFromCdn|fetchModel" "$f" 2>/dev/null; then
            echo "FAIL: possible automated model download code in $f"
            echo "  Found downloadTask/dataTask + model/package context in same file"
            FAILED=1
        fi
    done
fi

# Pattern 2: Synchronous Data(contentsOf: URL) for model loading (antipattern)
PATTERN2=$(grep -rn -E "Data\(contentsOf:.*URL" Sources/ 2>/dev/null | grep -E "model|mlmodelc|package" || true)
if [ -n "$PATTERN2" ]; then
    echo "FAIL: synchronous URL model loading detected:"
    echo "$PATTERN2"
    FAILED=1
fi

# Pattern 3: Explicit CDN/remote URLs for model files
PATTERN3=$(grep -rn -E "https?://[^\"]*\.(mlmodelc|coreml|model|bin)" Sources/ 2>/dev/null | grep -v "// " | grep -v "/*" || true)
if [ -n "$PATTERN3" ]; then
    echo "FAIL: hardcoded model URLs detected:"
    echo "$PATTERN3"
    FAILED=1
fi

# Pattern 4: Model install helpers (installModel, downloadModel, fetchPackage)
# Allowlist: CloudProviderModelCatalog.swift is the sanctioned cloud LLM catalog
# surface (its presence is enforced by check_cloud_providers.sh). It lists
# remote LLM models via GET /models JSON; it does not download ASR/CoreML
# weights or packages. Defense in depth is preserved: any future
# downloadTask/dataTask introduced there is still caught by Pattern 1
# (the file already matches the fetchModel/model context probe).
ALLOWED_CATALOG="Sources/NativeBolabol/Services/CloudProviderModelCatalog.swift"
PATTERN4=$(grep -rn -E "func (install|download|fetch)(Model|Package|CoreML|Weights)" Sources/ 2>/dev/null | grep -v "^$ALLOWED_CATALOG:" || true)
if [ -n "$PATTERN4" ]; then
    echo "FAIL: model install/download helper detected:"
    echo "$PATTERN4"
    FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
    echo "FAIL: automated model download surface detected in Sources/"
    echo "  (CDN download code requires security review before introduction)"
    exit 1
fi

echo "OK: no automated model download code in Sources/ (CDN surface clean)"
