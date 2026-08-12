#!/usr/bin/env bash
# S9 engine and regression contract. This complements executable-target tests
# with source-level checks for the spike constraints that need Core ML/runtime
# symbols or are unavailable on the current OS during unit tests.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

CANARY="Sources/NativeBolabol/Engines/CanaryCoreMLEngine.swift"
GIGAAM="Sources/NativeBolabol/Engines/GigaAMCoreMLEngine.swift"
DESCRIPTOR="Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift"
STORE="Sources/NativeBolabol/Stores/TranscriptionModelStore.swift"
LEGACY_TEST="Tests/NativeBolabolCoreTests/CoreMLEngineTests.swift"
ENGINE_TEST="Tests/NativeBolabolCoreTests/EngineConstructionTests.swift"
EDGE_TEST="Tests/NativeBolabolCoreTests/S9EngineEdgeCaseTests.swift"
RUNTIME_TEST="Tests/NativeBolabolCoreTests/S9RuntimeSmokeTests.swift"
S8_TEST="Tests/NativeBolabolCoreTests/S8DownloadContractTests.swift"
NO_CANARY="script/qa/check_no_canary_product.sh"
NO_DOWNLOAD="script/qa/check_sec_no_download_code.sh"
SEARCH_TOOL=""

FAILED=0

require_file() {
    if [ ! -f "$1" ]; then
        echo "FAIL: missing $1"
        FAILED=1
    fi
}

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

if [ "${1:-}" != "--self-test" ]; then
    if [ ! -d "$ROOT/Sources" ]; then
        echo "FAIL: product Sources directory is missing: $ROOT/Sources"
        exit 1
    fi
    if ! resolve_search_tool; then
        exit 1
    fi
fi

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
    local description="$3"
    local output
    if output="$(search_fixed "$needle" "$file" 2>&1)"; then
        return 0
    else
        local status=$?
        if [ "$status" -eq 1 ]; then
            echo "FAIL: $description"
        else
            echo "FAIL: search error while checking $description: $output"
        fi
        FAILED=1
        return 1
    fi
}

validate_asr_only_boundary() {
    local root="$1"
    local sources="$root/Sources"
    local canary="$sources/NativeBolabol/Engines/CanaryCoreMLEngine.swift"
    local edge_test="$root/Tests/NativeBolabolCoreTests/S9EngineEdgeCaseTests.swift"
    if [ ! -d "$sources" ]; then
        echo "FAIL: product Sources directory is missing: $sources"
        return 1
    fi
    if ! resolve_search_tool; then
        return 1
    fi
    local failed=0
    for file in "$canary" "$edge_test"; do
        if [ ! -f "$file" ]; then
            echo "FAIL: missing ASR-only validator/test file: $file"
            failed=1
        fi
    done
    if [ "$failed" -ne 0 ]; then
        return 1
    fi
    local output
    for pair in \
        "$canary|validateASROnlyRequest" \
        "$canary|guard !request.translateToEnglish" \
        "$canary|case translationUnsupported" \
        "$edge_test|canaryRejectsWhisperTranslationFlagBeforeEngineWork"; do
        local file="${pair%%|*}"
        local marker="${pair#*|}"
        if output="$(search_fixed "$marker" "$file" 2>&1)"; then
            :
        else
            local status=$?
            if [ "$status" -eq 1 ]; then
                echo "FAIL: missing real Canary ASR-only boundary marker: $marker"
            else
                echo "FAIL: search error while checking Canary ASR-only marker $marker: $output"
            fi
            failed=1
        fi
    done
    [ "$failed" -eq 0 ]
}

self_test() {
    local fixture
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-s9-contract.XXXXXX")"
    trap 'rm -rf "${fixture:-}"' EXIT
    mkdir -p \
        "$fixture/Sources/NativeBolabol/Engines" \
        "$fixture/Tests/NativeBolabolCoreTests"
    printf '%s\n' \
        'func validateASROnlyRequest(_ request: TranscriptionRequest) throws {' \
        '    guard !request.translateToEnglish else { throw Error.translationUnsupported }' \
        '}' \
        'enum Error { case translationUnsupported }' \
        > "$fixture/Sources/NativeBolabol/Engines/CanaryCoreMLEngine.swift"
    printf '%s\n' 'func canaryRejectsWhisperTranslationFlagBeforeEngineWork() {}' \
        > "$fixture/Tests/NativeBolabolCoreTests/S9EngineEdgeCaseTests.swift"

    if ! validate_asr_only_boundary "$fixture"; then
        echo "FAIL: clean fixture was rejected"
        return 1
    fi
    echo "PASS: clean fixture"

    rm -rf "$fixture/Sources"
    if validate_asr_only_boundary "$fixture"; then
        echo "FAIL: missing-Sources mutation was accepted"
        return 1
    fi
    echo "PASS: missing-Sources mutation"

    mkdir -p "$fixture/Sources/NativeBolabol/Engines"
    printf '%s\n' \
        'func validateASROnlyRequest(_ request: TranscriptionRequest) throws {}' \
        > "$fixture/Sources/NativeBolabol/Engines/CanaryCoreMLEngine.swift"
    if BOLABOL_QA_SEARCH_TOOL=missing validate_asr_only_boundary "$fixture"; then
        echo "FAIL: missing-search-tool mutation was accepted"
        return 1
    fi
    echo "PASS: missing-search-tool mutation"

    printf '%s\n' \
        'func validateASROnlyRequest(_ request: TranscriptionRequest) throws {}' \
        'enum Error { case translationUnsupported }' \
        > "$fixture/Sources/NativeBolabol/Engines/CanaryCoreMLEngine.swift"
    if validate_asr_only_boundary "$fixture"; then
        echo "FAIL: Canary translation-acceptance mutation was accepted"
        return 1
    fi
    echo "PASS: negative mutation 1/1 Canary ASR-only validator"
    echo "PASS: 1/1 S9 negative mutations executed"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

for file in \
    "$CANARY" \
    "$GIGAAM" \
    "$DESCRIPTOR" \
    "$STORE" \
    "$LEGACY_TEST" \
    "$ENGINE_TEST" \
    "$EDGE_TEST" \
    "$RUNTIME_TEST" \
    "$S8_TEST" \
    "$NO_CANARY" \
    "$NO_DOWNLOAD"; do
    require_file "$file"
done

validate_asr_only_boundary "$ROOT" || FAILED=1

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi

# Canary Flash + Path B constraints.
for marker in \
    'config.computeUnits = .cpuAndNeuralEngine' \
    '@available(macOS 15.0, *)' \
    'canary_spe.model' \
    'SentencePieceModel' \
    'pathBDecoderPositionArray(position: position)' \
    '"token": MLFeatureValue(multiArray: try makeI32([token]))' \
    'let a = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .int32)' \
    'hasPrefix("<|")' \
    'replacingOccurrences(of:' \
    'makeState()' \
    'mel_length' \
    'encoder_length' \
    'Self.chunk(samples: samples, maxSamples: maxChunkSamples)'; do
    require_literal "$CANARY" "$marker" "Canary engine is missing S9 marker: $marker"
done

# BUG-003 regression must exercise the product position seam and retain the
# decoder token contract: pos is rank-1 [1], while token remains rank-2 [1, 1].
for marker in \
    'let input = try CanaryCoreMLEngine.pathBDecoderPositionArray(position: position)' \
    '#expect(input.dataType == .int32)' \
    '#expect(input.shape.map(\.intValue) == [1])' \
    '#expect(input[0].intValue == position)'; do
    require_literal "$RUNTIME_TEST" "$marker" "BUG-003 product regression is missing: $marker"
done

# GigaAM HTK/RNNT constraints.
for marker in \
    'config.computeUnits = .cpuAndNeuralEngine' \
    'GigaAMMelFrontend' \
    'sampleRate = 16_000' \
    'windowSamples = 480_000' \
    'fresh state per chunk' \
    'validEncoderFrames' \
    'let blankID = 1024' \
    'case .float16:'; do
    require_literal "$GIGAAM" "$marker" "GigaAM engine is missing S9 marker: $marker"
done

# Descriptor and S8 storage/presence integration.
for path in 'return "canary/1b-v2"' 'return "canary/180m-flash"' 'return "gigaam/v3-rnnt"'; do
    require_literal "$DESCRIPTOR" "$path" "S8 storage root mapping is missing: $path"
done
for bundle in \
    'canary_encoder.mlmodelc' \
    'canary_cross_kv.mlmodelc' \
    'canary_decoder_kv.mlmodelc' \
    'CanaryEncoder.mlmodelc' \
    'CanaryPrefill.mlmodelc' \
    'CanaryDecoder.mlmodelc' \
    'Encoder.mlmodelc' \
    'Predictor.mlmodelc' \
    'JointDecision.mlmodelc'; do
    require_literal "$STORE" "$bundle" "complete GO-folder presence is missing: $bundle"
done
require_literal "$STORE" 'return requiredItems.isSubset(of: visible)' \
    "GO presence must reject incomplete folders"
require_literal "$EDGE_TEST" 'storeResolvesAllGOModelsFromS8StorageRoots' \
    "S9 store integration test is missing"
require_literal "$EDGE_TEST" 'storeRejectsEveryIncompleteGOModelFolder' \
    "S9 incomplete-folder regression test is missing"

# Test mapping for all three GO models, exact chunk limits, language matrix,
# missing-model paths, and the macOS 15/14 gate.
for marker in \
    'constructsCanaryFlashCoreMLEngine' \
    'constructsCanary1BCoreMLEngine' \
    'constructsGigaAMCoreMLEngine' \
    'canaryFlashChunkingProductCode' \
    'canary1BChunkingProductCode' \
    'gigaAMChunkingProductCode' \
    'canary1BLanguageMatrixCoversExplicit25LanguageASRSources' \
    'canaryFlashLanguageMatrixAcceptsAllASRSourceLanguages' \
    'gigaAMLanguageValidationViaProductCode' \
    'everyGOEngineRejectsAMissingModelDirectory' \
    'canary1BUsesMacOS15GateBeforeLoadingTheModel' \
    'canary1BOfflineDictationProducesTextWhenScratchIsEnabled'; do
    local_mapping=""
    if local_mapping="$(search_fixed "$marker" "$ENGINE_TEST" "$EDGE_TEST" "$RUNTIME_TEST" 2>&1)"; then
        :
    else
        mapping_status=$?
        if [ "$mapping_status" -eq 1 ]; then
            echo "FAIL: missing S9 test mapping: $marker"
        else
            echo "FAIL: search error while checking S9 test mapping $marker: $local_mapping"
        fi
        FAILED=1
    fi
done

# The old CoreMLEngineTests private chunk implementation must not return as a
# second contract; product static seams are the single chunking implementation.
legacy_chunk_matches=""
if legacy_chunk_matches="$(search_regex 'private[[:space:]]+(nonisolated[[:space:]]+)?func[[:space:]]+chunk' "$LEGACY_TEST" 2>&1)"; then
    echo "FAIL: legacy CoreMLEngineTests.swift still contains a private chunk helper"
    printf '%s\n' "$legacy_chunk_matches"
    FAILED=1
else
    legacy_status=$?
    if [ "$legacy_status" -gt 1 ]; then
        echo "FAIL: search error while checking legacy chunk helper: $legacy_chunk_matches"
        FAILED=1
    fi
fi

# Preserve the lightweight boundary guards and keep the security allowlist
# exactly at the two sanctioned pre-existing files.
bash "$NO_CANARY" >/dev/null || FAILED=1
bash "$NO_DOWNLOAD" >/dev/null || FAILED=1
allowlist_matches=""
if allowlist_matches="$(search_regex '^ALLOWED_[A-Z]+=' "$NO_DOWNLOAD" 2>&1)"; then
    allowlist_count="$(printf '%s\n' "$allowlist_matches" | wc -l | tr -d '[:space:]')"
else
    allowlist_status=$?
    if [ "$allowlist_status" -eq 1 ]; then
        allowlist_count=0
    else
        echo "FAIL: search error while counting security download allowlist: $allowlist_matches"
        allowlist_count=-1
        FAILED=1
    fi
fi
if [ "$allowlist_count" -ne 2 ]; then
    echo "FAIL: security download allowlist has $allowlist_count entries; expected exactly 2"
    FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
    echo "FAIL: S9 engine and regression contract has $FAILED failure(s)"
    exit 1
fi

echo "OK: S9 engines, language/chunk/error coverage, S8 storage presence, legacy-helper removal, and QA guards"
