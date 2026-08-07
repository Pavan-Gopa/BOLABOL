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

FAILED=0

require_file() {
    if [ ! -f "$1" ]; then
        echo "FAIL: missing $1"
        FAILED=1
    fi
}

require_literal() {
    local file="$1"
    local needle="$2"
    local description="$3"
    if ! grep -qF "$needle" "$file"; then
        echo "FAIL: $description"
        FAILED=1
    fi
}

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
    if ! grep -qF "$marker" "$ENGINE_TEST" "$EDGE_TEST" "$RUNTIME_TEST"; then
        echo "FAIL: missing S9 test mapping: $marker"
        FAILED=1
    fi
done

# The old CoreMLEngineTests private chunk implementation must not return as a
# second contract; product static seams are the single chunking implementation.
if grep -qE 'private[[:space:]]+(nonisolated[[:space:]]+)?func[[:space:]]+chunk' "$LEGACY_TEST"; then
    echo "FAIL: legacy CoreMLEngineTests.swift still contains a private chunk helper"
    FAILED=1
fi

# Preserve the lightweight boundary guards and keep the security allowlist
# exactly at the two sanctioned pre-existing files.
bash "$NO_CANARY" >/dev/null || FAILED=1
bash "$NO_DOWNLOAD" >/dev/null || FAILED=1
allowlist_count="$(grep -cE '^ALLOWED_[A-Z]+=' "$NO_DOWNLOAD" || true)"
if [ "$allowlist_count" -ne 2 ]; then
    echo "FAIL: security download allowlist has $allowlist_count entries; expected exactly 2"
    FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
    echo "FAIL: S9 engine and regression contract has $FAILED failure(s)"
    exit 1
fi

echo "OK: S9 engines, language/chunk/error coverage, S8 storage presence, legacy-helper removal, and QA guards"
