#!/usr/bin/env bash
# Security guard: always verify SHA-256 integrity of S4b package.
# Unlike check_s4b_canary_fix.sh (which requires VERIFY_S4B_PACKAGE=1),
# this script always verifies and fails if any file mismatches.
#
# Rationale: Closes finding F2 (low) from SECURITY_REPORT.md.
# Scope: script/qa/** (allowed), does not modify Sources/**.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

PACKAGE="scratch/canary-1b-fix/package/bolabol-canary-1b-v2-coreml-r1"
MANIFEST="$PACKAGE/MANIFEST.json"

if [ ! -f "$MANIFEST" ]; then
    echo "SKIP: S4b package not present ($MANIFEST missing). Integrity check deferred."
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: jq is required for SHA verification"
    exit 1
fi

FAILED=0
TOTAL=0
VERIFIED=0

while IFS=$'\t' read -r relative expected_sha expected_size; do
    TOTAL=$((TOTAL + 1))
    actual="$PACKAGE/$relative"
    if [ ! -f "$actual" ]; then
        echo "FAIL: manifest file missing: $relative"
        FAILED=1
        continue
    fi
    observed_sha="$(shasum -a 256 "$actual" | awk '{print $1}')"
    observed_size="$(stat -f %z "$actual" 2>/dev/null || stat -c %s "$actual" 2>/dev/null)"

    if [ "$observed_sha" != "$expected_sha" ]; then
        echo "FAIL: SHA-256 mismatch: $relative"
        echo "  expected: $expected_sha"
        echo "  observed: $observed_sha"
        FAILED=1
        continue
    fi
    if [ "$observed_size" != "$expected_size" ]; then
        echo "FAIL: size mismatch: $relative (expected $expected_size, observed $observed_size)"
        FAILED=1
        continue
    fi
    VERIFIED=$((VERIFIED + 1))
done < <(jq -r '.files[] | [.path, .sha256, (.sizeBytes | tostring)] | @tsv' "$MANIFEST")

if [ "$FAILED" -ne 0 ]; then
    echo "FAIL: S4b package integrity check failed ($VERIFIED/$TOTAL verified)"
    exit 1
fi

echo "OK: S4b package integrity verified ($VERIFIED/$TOTAL files SHA-256 + size match)"
