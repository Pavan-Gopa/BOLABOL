#!/usr/bin/env bash
# S4b contract: Path B report, native probe, ignored package, and product
# boundary. Full byte/hash verification is available with VERIFY_S4B_PACKAGE=1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

REPORT="docs/asr/canary-1b/BOLABOL_COREML_SPIKE.md"
HARNESS="docs/canary/harness/CanarySmdesaiSpike.swift"
PACKAGE="scratch/canary-1b-fix/package/bolabol-canary-1b-v2-coreml-r1"
MANIFEST="$PACKAGE/MANIFEST.json"
FAILED=0

require_file() {
    local file="$1"
    [ -f "$file" ] || { echo "FAIL: missing $file"; FAILED=1; }
}

require_text() {
    local file="$1"
    local needle="$2"
    if ! grep -qF "$needle" "$file"; then
        echo "FAIL: $file missing: $needle"
        FAILED=1
    fi
}

require_file "$REPORT"
require_file "$HARNESS"
require_file "$MANIFEST"

if [ -f "$REPORT" ]; then
    grep -qE '^\*\*Status:\*\* GO' "$REPORT" || {
        echo "FAIL: S4b report lacks explicit GO status"
        FAILED=1
    }
    for section in "P0 Triage" "FluidAudio analysis" "Path Chosen" "Preflight Evidence" "Package" "S7+ Constraints"; do
        grep -q "$section" "$REPORT" || {
            echo "FAIL: S4b report lacks section: $section"
            FAILED=1
        }
    done
    require_text "$REPORT" "bolabol-canary-1b-v2-coreml-r1"
    require_text "$REPORT" "MEL_PREFLIGHT"
    require_text "$REPORT" "EOS"
fi

if [ -f "$HARNESS" ]; then
    for import in "import Accelerate" "import CoreML" "import Foundation"; do
        require_text "$HARNESS" "$import"
    done
    for contract in "NativeMelFrontend" "MLState" "makeState()" "audio_length" "mel_length" "encoder_length" "ASR_PREFLIGHT"; do
        require_text "$HARNESS" "$contract"
    done
    if grep -nE "python3|python[0-9.]*([[:space:]]|/)|pip3?([[:space:]]|$)|nemo|/usr/bin/env|Process\(|executableURL|launchPath" "$HARNESS"; then
        echo "FAIL: $HARNESS contains an external/Python inference path"
        FAILED=1
    fi
    hits=$(grep -n "Python" "$HARNESS" || true)
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in
            *//*Python*) ;;
            *) echo "FAIL: non-comment Python mention in $HARNESS: $line"; FAILED=1 ;;
        esac
    done <<< "$hits"
fi

if ! git check-ignore -q scratch/canary-1b-fix; then
    echo "FAIL: scratch/canary-1b-fix is not gitignored"
    FAILED=1
fi
if [ -n "$(git ls-files -- 'scratch/canary-1b-fix/**')" ]; then
    echo "FAIL: S4b package artifacts are tracked"
    FAILED=1
fi

if [ -f "$MANIFEST" ]; then
    jq -e '.packageId == "bolabol-canary-1b-v2-coreml-r1" and .frontend == "native-nemo-mel" and .minMacOS == "15.0" and (.files | length) > 0' "$MANIFEST" >/dev/null || {
        echo "FAIL: S4b MANIFEST metadata is invalid"
        FAILED=1
    }
    [ -d "$PACKAGE/canary_encoder.mlmodelc" ] || { echo "FAIL: package encoder missing"; FAILED=1; }
    [ -d "$PACKAGE/canary_cross_kv.mlmodelc" ] || { echo "FAIL: package cross KV missing"; FAILED=1; }
    [ -d "$PACKAGE/canary_decoder_kv.mlmodelc" ] || { echo "FAIL: package decoder KV missing"; FAILED=1; }
    [ -f "$PACKAGE/canary_spe.model" ] || { echo "FAIL: package tokenizer missing"; FAILED=1; }
    [ ! -e "$PACKAGE/canary_preprocessor.mlmodelc" ] || {
        echo "FAIL: failed Core ML preprocessor was packaged"
        FAILED=1
    }
fi

# Keep the older spike contracts visible and the product surface Canary-free.
bash "$ROOT/script/qa/check_b6_canary_spike.sh" || FAILED=1
bash "$ROOT/script/qa/check_no_canary_product.sh" || FAILED=1

if [ "${VERIFY_S4B_PACKAGE:-0}" = "1" ] && [ -f "$MANIFEST" ]; then
    while IFS=$'\t' read -r relative expected expected_size; do
        actual="$PACKAGE/$relative"
        [ -f "$actual" ] || { echo "FAIL: manifest file missing: $relative"; FAILED=1; continue; }
        observed="$(shasum -a 256 "$actual")"
        observed="${observed%% *}"
        observed_size="$(stat -f %z "$actual")"
        [ "$observed" = "$expected" ] || { echo "FAIL: SHA-256 mismatch: $relative"; FAILED=1; }
        [ "$observed_size" = "$expected_size" ] || { echo "FAIL: size mismatch: $relative"; FAILED=1; }
    done < <(jq -r '.files[] | [.path, .sha256, (.sizeBytes | tostring)] | @tsv' "$MANIFEST")
fi

if [ "$FAILED" -ne 0 ]; then
    echo "FAIL: S4b Canary fix/package contract broken"
    exit 1
fi

echo "OK: S4b Path B report, native harness, package boundary, and no-product contract hold"
