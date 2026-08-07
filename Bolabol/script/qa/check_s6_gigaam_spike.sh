#!/usr/bin/env bash
# S6 GigaAM v3 Core ML spike contract: report + native Swift harness only.
# The spike evidence remains separate from the ADR-021 Canary guard.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SEARCH_TOOL=""

resolve_search_tool() {
    case "${BOLABOL_QA_SEARCH_TOOL:-}" in
        missing)
            echo "FAIL: search tool was forced missing"
            return 1
            ;;
        rg)
            if ! command -v rg >/dev/null 2>&1; then
                echo "FAIL: required search tool rg is unavailable"
                return 1
            fi
            SEARCH_TOOL="rg"
            ;;
        grep)
            if ! command -v grep >/dev/null 2>&1; then
                echo "FAIL: required search tool grep is unavailable"
                return 1
            fi
            SEARCH_TOOL="grep"
            ;;
        *)
            if command -v rg >/dev/null 2>&1; then
                SEARCH_TOOL="rg"
            elif command -v grep >/dev/null 2>&1; then
                SEARCH_TOOL="grep"
            else
                echo "FAIL: neither rg nor grep is available"
                return 1
            fi
            ;;
    esac
}

search_fixed() {
    local needle="$1"
    shift
    if [ "$SEARCH_TOOL" = "rg" ]; then
        rg --no-heading --line-number --color never -F -e "$needle" "$@"
    else
        grep -RInF -- "$needle" "$@"
    fi
}

search_regex() {
    local pattern="$1"
    shift
    if [ "$SEARCH_TOOL" = "rg" ]; then
        rg --no-heading --line-number --color never -e "$pattern" "$@"
    else
        grep -RInE -- "$pattern" "$@"
    fi
}

require_literal() {
    local file="$1"
    local needle="$2"
    local message="$3"
    local output
    if output="$(search_fixed "$needle" "$file" 2>&1)"; then
        return 0
    else
        local status=$?
        if [ "$status" -eq 1 ]; then
            echo "FAIL: $file $message"
        else
            echo "FAIL: search error while checking $file $message: $output"
        fi
        return 1
    fi
}

require_regex() {
    local file="$1"
    local pattern="$2"
    local message="$3"
    local output
    if output="$(search_regex "$pattern" "$file" 2>&1)"; then
        return 0
    else
        local status=$?
        if [ "$status" -eq 1 ]; then
            echo "FAIL: $file $message"
        else
            echo "FAIL: search error while checking $file $message: $output"
        fi
        return 1
    fi
}

forbid_regex() {
    local file="$1"
    local pattern="$2"
    local message="$3"
    local output
    if output="$(search_regex "$pattern" "$file" 2>&1)"; then
        echo "FAIL: $file $message"
        printf '%s\n' "$output"
        return 1
    else
        local status=$?
        if [ "$status" -eq 1 ]; then
            return 0
        fi
        echo "FAIL: search error while checking $file $message: $output"
        return 1
    fi
}

validate_giga_invariant() {
    local root="$1"
    local sources="$root/Sources"
    local giga="$sources/NativeBolabol/Engines/GigaAMCoreMLEngine.swift"
    if [ ! -d "$sources" ]; then
        echo "FAIL: product Sources directory is missing: $sources"
        return 1
    fi
    if ! resolve_search_tool; then
        return 1
    fi
    if [ ! -f "$giga" ]; then
        echo "FAIL: missing GigaAM engine source: $giga"
        return 1
    fi
    local failed=0
    require_regex "$giga" 'guard[[:space:]]+let language = request\.forcedLanguageCode' \
        "GigaAM must require an explicit source language" || failed=1
    require_regex "$giga" 'guard[[:space:]]+supported\.contains\(language\)' \
        "GigaAM must validate the explicit source against its capability" || failed=1
    require_regex "$giga" 'guard[[:space:]]*!request\.translateToEnglish' \
        "GigaAM translation rejection must remain" || failed=1
    if [ "$failed" -ne 0 ]; then
        return 1
    fi
}

validate_spike() {
    local failed=0
    local doc="docs/asr/gigaam-v3/COREML_SPIKE.md"
    local harness="docs/asr/gigaam-v3/GigaAMCoreMLSpike.swift"
    local descriptor="Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift"
    local package="Package.swift"

    if [ ! -d "$ROOT/Sources" ]; then
        echo "FAIL: product Sources directory is missing"
        return 1
    fi
    if ! resolve_search_tool; then
        return 1
    fi
    validate_giga_invariant "$ROOT" || failed=1

    [ -f "$doc" ] || { echo "FAIL: $doc not found"; failed=1; }
    [ -f "$harness" ] || { echo "FAIL: $harness not found"; failed=1; }
    [ -f "$descriptor" ] || { echo "FAIL: $descriptor not found"; failed=1; }
    [ -f "$package" ] || { echo "FAIL: $package not found"; failed=1; }

    if [ -f "$doc" ]; then
        require_regex "$doc" '^\*\*Status:\*\* GO([[:space:]]|$)' \
            "lacks the expected explicit GO status" || failed=1
        for section in "Environment" "Artifact audit" "Load" "Short RU audio ASR" "Latency" "Language" "Chunking" "No Python" "Verdict"; do
            require_regex "$doc" "$section" "lacks checklist section: $section" || failed=1
        done
        require_regex "$doc" 'huggingfinger0/gigaam-v3-coreml' \
            "does not identify the selected candidate" || failed=1
        for constraint in "16 kHz" "30 s" "true valid" "reset RNNT predictor state" "blank id 1024" "S7+" "NO product|no product"; do
            require_regex "$doc" "$constraint" "lacks S6/S7+ boundary constraint: $constraint" || failed=1
        done
    fi

    if [ -f "$harness" ]; then
        for import in "import Accelerate" "import CoreML" "import Foundation"; do
            require_literal "$harness" "$import" "is missing native import: $import" || failed=1
        done
        for contract in \
            "let windowFrames = 3_000" \
            "let windowSamples = 480_000" \
            "let processedSamples = min(samples.count, windowSamples)" \
            "let validFrames = min(windowFrames, ((processedSamples - nFFT) / hopLength) + 1)" \
            "let validEncoderFrames = min(totalEncoderFrames, max(1, (validFrames + 3) / 4))" \
            "let blankID = 1024" \
            "if token == blankID" \
            "var hasState = false" \
            "hidden = try predictorState(nextHidden, hiddenSize: 320)" \
            "cell = try predictorState(nextCell, hiddenSize: 320)" \
            "validFrames: extracted.validFrames"; do
            require_literal "$harness" "$contract" "is missing harness contract: $contract" || failed=1
        done
        if ! forbid_regex "$harness" 'python3|python[0-9.]*([[:space:]]|/)|pip3?([[:space:]]|$)|nemo|/usr/bin/env|Process\(|executableURL|launchPath' \
            "contains an external/Python inference path"; then
            failed=1
        fi
        if collect_matches="$(search_regex 'Python' "$harness" 2>&1)"; then
            while IFS= read -r line; do
                [ -n "$line" ] || continue
                case "$line" in
                    *//*Python*) ;;
                    *) echo "FAIL: $harness has a non-comment Python mention: $line"; failed=1 ;;
                esac
            done <<< "$collect_matches"
        else
            local status=$?
            if [ "$status" -ne 1 ]; then
                echo "FAIL: search error while checking Python mentions: $collect_matches"
                failed=1
            fi
        fi
    fi

    if ! git check-ignore -q scratch/gigaam-spike; then
        echo "FAIL: scratch/gigaam-spike is not gitignored"
        failed=1
    fi
    local tracked_spike_files
    tracked_spike_files="$(git ls-files -- 'scratch/gigaam-spike/**')"
    if [ -n "$tracked_spike_files" ]; then
        echo "FAIL: scratch/gigaam-spike contains tracked artifacts:"
        printf '%s\n' "$tracked_spike_files"
        failed=1
    fi

    bash "$ROOT/script/qa/check_no_canary_product.sh" >/dev/null || failed=1
    bash "$ROOT/script/qa/check_s1b_scope.sh" >/dev/null || failed=1
    if [ -f "$package" ] && collect_matches="$(search_regex 'gigaam' "$package" 2>&1)"; then
        echo "FAIL: GigaAM product/package wiring found in Package.swift"
        printf '%s\n' "$collect_matches"
        failed=1
    elif [ "$?" -gt 1 ]; then
        echo "FAIL: search error while checking Package.swift"
        failed=1
    fi

    if collect_matches="$(search_regex 'gigaam' "$ROOT/Sources" 2>&1)"; then
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            case "$line" in
                *Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift*) ;;
                *Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift*) ;;
                *Sources/NativeBolabol/Stores/TranscriptionModelStore.swift*) ;;
                *Sources/NativeBolabol/Stores/TranscriptionEngineStore.swift*) ;;
                *Sources/NativeBolabol/Engines/GigaAMCoreMLEngine.swift*) ;;
                *Sources/NativeBolabol/Views/ContentView.swift*) ;;
                *Sources/NativeBolabol/Views/Settings/HelpSettingsView.swift*) ;;
                *Sources/NativeBolabol/Views/Settings/HotkeySettingsView.swift*) ;;
                *Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift*) ;;
                *Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift*) ;;
                *Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift*) ;;
                *Sources/NativeBolabolCore/Models/TranscriptionLanguageMode.swift*) ;;
                *Sources/NativeBolabolCore/Services/AppText.swift*) ;;
                *Sources/NativeBolabolCore/Services/TranscriptionLanguageRouting.swift*) ;;
                *) echo "FAIL: GigaAM product reference outside catalog/backend surface: $line"; failed=1 ;;
            esac
        done <<< "$collect_matches"
    elif [ "$?" -gt 1 ]; then
        echo "FAIL: search error while scanning GigaAM product references"
        failed=1
    fi

    if [ "$failed" -ne 0 ]; then
        echo "FAIL: S6 GigaAM spike contract broken"
        return 1
    fi
    return 0
}

self_test() {
    local fixture
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-s6-gigaam.XXXXXX")"
    trap 'rm -rf "${fixture:-}"' EXIT
    mkdir -p "$fixture/Sources/NativeBolabol/Engines"
    printf '%s\n' \
        'guard let language = request.forcedLanguageCode else { throw Error.missing }' \
        'guard supported.contains(language) else { throw Error.unsupported }' \
        'guard !request.translateToEnglish else { throw Error.translationUnsupported }' \
        > "$fixture/Sources/NativeBolabol/Engines/GigaAMCoreMLEngine.swift"
    if ! validate_giga_invariant "$fixture"; then
        echo "FAIL: clean Giga invariant fixture was rejected"
        return 1
    fi
    echo "PASS: clean fixture"

    rm -rf "$fixture/Sources"
    if validate_giga_invariant "$fixture"; then
        echo "FAIL: missing-Sources mutation was accepted"
        return 1
    fi
    echo "PASS: missing-Sources mutation"

    mkdir -p "$fixture/Sources/NativeBolabol/Engines"
    printf '%s\n' 'guard let language = request.forcedLanguageCode else { throw Error.missing }' \
        > "$fixture/Sources/NativeBolabol/Engines/GigaAMCoreMLEngine.swift"
    if BOLABOL_QA_SEARCH_TOOL=missing validate_giga_invariant "$fixture"; then
        echo "FAIL: missing-search-tool mutation was accepted"
        return 1
    fi
    echo "PASS: missing-search-tool mutation"

    printf '%s\n' \
        'guard let language = request.forcedLanguageCode else { throw Error.missing }' \
        'guard supported.contains(language) else { throw Error.unsupported }' \
        > "$fixture/Sources/NativeBolabol/Engines/GigaAMCoreMLEngine.swift"
    if validate_giga_invariant "$fixture"; then
        echo "FAIL: Giga translation-acceptance mutation was accepted"
        return 1
    fi
    echo "PASS: negative mutation 1/1 Giga translation acceptance"
    echo "PASS: 1/1 Giga negative mutations executed"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

if ! validate_spike; then
    exit 1
fi
echo "OK: S6 GigaAM spike report + native harness + fixed-RU/translation-rejection boundary holds"
