#!/usr/bin/env bash
# S8 feature contract for GO model install, presence, integrity, resume, and UI.
# This is intentionally source-level for TranscriptionModelStore because the
# SwiftPM test target only exposes NativeBolabolCore, not the executable target.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

DESCRIPTOR="Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift"
STORE="Sources/NativeBolabol/Stores/TranscriptionModelStore.swift"
SETTINGS="Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift"
CATALOG_TEST="Tests/NativeBolabolCoreTests/TranscriptionModelCatalogTests.swift"
S8_TEST="Tests/NativeBolabolCoreTests/S8DownloadContractTests.swift"
PRESENCE_TEST="Tests/NativeBolabolCoreTests/ModelPresenceVerificationTests.swift"
ENGINE_STORE="Sources/NativeBolabol/Stores/TranscriptionEngineStore.swift"
HUD_STORE="Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift"
SECURITY_GUARD="script/qa/check_sec_no_download_code.sh"

FAILED=0

fail() {
    echo "FAIL: $1"
    FAILED=1
}

require_file() {
    if [ ! -f "$1" ]; then
        fail "missing $1"
    fi
}

require_text() {
    local file="$1"
    local needle="$2"
    local description="$3"
    if ! grep -qF "$needle" "$file"; then
        fail "$description"
    fi
}

for file in \
    "$DESCRIPTOR" \
    "$STORE" \
    "$SETTINGS" \
    "$CATALOG_TEST" \
    "$S8_TEST" \
    "$PRESENCE_TEST" \
    "$ENGINE_STORE" \
    "$HUD_STORE" \
    "$SECURITY_GUARD"; do
    require_file "$file"
done

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi

# Exact install sources and the NeMo-origin negative guard.
require_text "$DESCRIPTOR" \
    '.huggingFace(repositoryID: "aufklarer/Canary-180M-Flash-CoreML")' \
    "Canary Flash must map to the authorized HF Core ML repository"
require_text "$DESCRIPTOR" \
    '.huggingFace(repositoryID: "huggingfinger0/gigaam-v3-coreml")' \
    "GigaAM must map to the authorized HF Core ML repository"
require_text "$DESCRIPTOR" \
    'packageID: "bolabol-canary-1b-v2-coreml-r1"' \
    "Canary 1B must map to the explicit Bolabol CDN package"
require_text "$S8_TEST" \
    's8GoInstallSourcesNeverUseUpstreamModelRepositoryIDs' \
    "S8 tests must guard against using NeMo modelRepositoryID values"

# Storage must use SharedModelsRoot subpaths, not the old Parakeet directory.
for path in 'canary/1b-v2' 'canary/180m-flash' 'gigaam/v3-rnnt'; do
    require_text "$DESCRIPTOR" "return \"$path\"" "missing exact GO storage subpath $path"
done
require_text "$STORE" 'SharedModelsRoot.resolve' "GO destinations must resolve below SharedModelsRoot"
if grep -qE 'case \.fluidAudioCoreML, \.canaryCoreML|case \.fluidAudioCoreML, \.gigaAMCoreML' "$STORE"; then
    fail "GO backends must not reuse the Parakeet destination branch"
fi

# Presence must be a complete-folder check, including each package's actual
# model bundles and tokenizer/vocabulary. The 1B package deliberately has no
# preprocessor bundle.
presence_block="$(awk '
/private func isCompleteGOModelFolder/ { capture = 1 }
capture { print }
capture && /private func performGOModelDownload/ { exit }
' "$STORE")"
for marker in \
    'fileManager.contentsOfDirectory' \
    'hasCompiledModel' \
    'name.hasSuffix(".mlmodelc")' \
    'canary_spe.model' \
    'vocab.json' \
    'vocab.txt' \
    'tokenizer.json' \
    'manifest.json'; do
    if [[ "$presence_block" != *"$marker"* ]]; then
        fail "GO presence check is missing $marker"
    fi
done
if [[ "$presence_block" != *'return requiredItems.isSubset(of: visible)'* ]]; then
    fail "GO presence must reject a folder missing any required asset"
fi
for required_bundle in \
    'canary_encoder.mlmodelc' \
    'canary_cross_kv.mlmodelc' \
    'canary_decoder_kv.mlmodelc' \
    'CanaryEncoder.mlmodelc' \
    'CanaryPrefill.mlmodelc' \
    'CanaryDecoder.mlmodelc' \
    'Encoder.mlmodelc' \
    'Predictor.mlmodelc' \
    'JointDecision.mlmodelc'; do
    if [[ "$presence_block" != *"$required_bundle"* ]]; then
        fail "GO presence check must require the complete bundle $required_bundle"
    fi
done
if [[ "$presence_block" == *"canary_preprocessor.mlmodelc"* ]]; then
    fail "1B presence check must not require the excluded preprocessor bundle"
fi
require_text "$PRESENCE_TEST" \
    's8PresenceFixturesRejectEmptyFoldersAndIncompleteModelAssets' \
    "S8 tests must cover empty and incomplete presence fixtures"

# Download integrity and resume hooks.
for marker in \
    'switch model.installSource' \
    'MANIFEST.json' \
    'JSONDecoder().decode' \
    'currentSize == expectedSize' \
    'verifyFileSHA256(localFileURL, expectedHash: file.sha256)' \
    'try? fileManager.removeItem(at: localFileURL)' \
    'InputStream(url: fileURL)' \
    'SHA256()' \
    'bufferSize = 65536'; do
    require_text "$STORE" "$marker" "download contract is missing $marker"
done

# Disk threshold and Settings state rendering.
require_text "$SETTINGS" 'model.capabilities.approxDownloadBytes > 1_000_000_000' \
    "Settings must guard downloads above the 1 GB threshold"
require_text "$SETTINGS" '.alert("Large Model Download"' \
    "Settings must show the large-model confirmation"
for state in \
    'case .notDownloaded:' \
    'case .downloading:' \
    'case .downloaded:' \
    'case .failed:' \
    'ProgressView(value: state.progressFraction)' \
    'Label(generalSettingsStore.text(.retry)'; do
    require_text "$SETTINGS" "$state" "Settings state contract is missing $state"
done
require_text "$S8_TEST" \
    's8CanaryOneBAdvertisesPackageSizeAboveDiskWarningThreshold' \
    "S8 tests must cover the 1B disk-warning threshold"
if grep -qF 'will be introduced in S8' "$STORE"; then
    fail "S8 placeholder error text still leaks the step id"
fi

# Existing WhisperKit/FluidAudio and HUD-A paths remain present.
require_text "$CATALOG_TEST" \
    'nativeTranscriptionCatalogPreservesExistingWhisperKitAndFluidAudioDescriptors' \
    "existing WhisperKit/FluidAudio catalog regression coverage is missing"
require_text "$ENGINE_STORE" 'case .whisperKitCoreML:' \
    "WhisperKit engine routing is missing"
require_text "$ENGINE_STORE" 'case .fluidAudioCoreML:' \
    "FluidAudio/Parakeet engine routing is missing"
require_text "$HUD_STORE" 'languageMode: TranscriptionLanguageMode = .auto' \
    "HUD auto-language default is missing"
require_text "$HUD_STORE" 'state.languageMode == .auto ? "A"' \
    "HUD A label regression guard is missing"

# The lightweight QA allowlist may exempt only the sanctioned model store and
# the pre-existing cloud catalog. Any third exemption widens the guard.
require_text "$SECURITY_GUARD" \
    'ALLOWED_CATALOG="Sources/NativeBolabol/Services/CloudProviderModelCatalog.swift"' \
    "security guard cloud-catalog allowlist changed"
require_text "$SECURITY_GUARD" \
    'ALLOWED_STORE="Sources/NativeBolabol/Stores/TranscriptionModelStore.swift"' \
    "security guard model-store allowlist missing"
allowlist_count="$(grep -cE '^ALLOWED_[A-Z]+=' "$SECURITY_GUARD" || true)"
if [ "$allowlist_count" -ne 2 ]; then
    fail "security guard allowlist has $allowlist_count entries; expected exactly 2"
fi
bash script/qa/check_no_canary_product.sh >/dev/null || fail "authorized/NO-GO source guard failed"
bash script/qa/check_sec_no_download_code.sh >/dev/null || fail "download-code guard failed"

# Small offline MANIFEST fixture: validate schema, size, SHA mismatch detection,
# and deletion behavior without making a network request.
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-s8-manifest.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT
payload="$fixture_dir/payload.bin"
manifest="$fixture_dir/MANIFEST.json"
printf 'bolabol-s8-fixture\n' > "$payload"
expected_sha="$(shasum -a 256 "$payload" | awk '{print $1}')"
expected_size="$(stat -f %z "$payload" 2>/dev/null || stat -c %s "$payload")"
printf '{"packageId":"bolabol-canary-1b-v2-coreml-r1","files":[{"path":"payload.bin","sha256":"%s","sizeBytes":%s}]}\n' \
    "$expected_sha" "$expected_size" > "$manifest"

if command -v jq >/dev/null 2>&1; then
    jq -e '.packageId == "bolabol-canary-1b-v2-coreml-r1" and (.files | length) == 1 and .files[0].sizeBytes > 0' "$manifest" >/dev/null \
        || fail "offline MANIFEST fixture did not parse"
else
    fail "jq is required for the offline MANIFEST fixture"
fi

printf 'corrupted\n' > "$payload"
corrupt_sha="$(shasum -a 256 "$payload" | awk '{print $1}')"
if [ "$corrupt_sha" = "$expected_sha" ]; then
    fail "offline corruption fixture did not change the SHA-256"
fi
rm -f "$payload"
if [ -e "$payload" ]; then
    fail "offline corruption fixture was not deleted"
fi

if [ "$FAILED" -ne 0 ]; then
    echo "FAIL: S8 download/presence contract has $FAILED failure(s)"
    exit 1
fi

echo "OK: S8 download, complete-folder presence, integrity, resume, progress, regression, and QA contracts"
