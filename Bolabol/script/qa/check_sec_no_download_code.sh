#!/usr/bin/env bash
# Security guard: detect unreviewed automated model/package download code in
# Sources/. Sanctioned stores stay allowlisted, but new download surfaces fail.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ALLOWED_CATALOG="Sources/NativeBolabol/Services/CloudProviderModelCatalog.swift"
ALLOWED_STORE="Sources/NativeBolabol/Stores/TranscriptionModelStore.swift"

validate_download_surface() {
    local root="$1"
    local sources="$root/Sources"
    local failed=0

    if [ ! -d "$sources" ]; then
        echo "FAIL: Sources/ not found under $root"
        return 1
    fi
    if ! command -v grep >/dev/null 2>&1; then
        echo "FAIL: grep is required for the download-surface guard"
        return 1
    fi

    while IFS= read -r file; do
        [ -n "$file" ] || continue
        local relative="${file#"$root/"}"
        [ "$relative" = "$ALLOWED_STORE" ] && continue
        if grep -qE 'mlmodelc|modelRoot|canary.*package|\.coreml|downloadFromCdn|fetchModel' "$file"; then
            echo "FAIL: possible automated model download code in $relative"
            failed=1
        fi
    done < <(grep -RIl --include='*.swift' -E 'downloadTask|dataTask' "$sources" || true)

    local matches
    matches="$(grep -RIn --include='*.swift' -E 'Data\(contentsOf:[[:space:]]*URL\(string:[[:space:]]*"https?://' "$sources" \
        | grep -Ei 'model|mlmodelc|package' || true)"
    if [ -n "$matches" ]; then
        echo "FAIL: synchronous URL model loading detected:"
        echo "$matches"
        failed=1
    fi

    matches="$(grep -RIn --include='*.swift' -E 'https?://[^"[:space:]]+\.(mlmodelc|coreml|model|bin)([^[:alnum:]_]|$)' "$sources" \
        | grep -Ev '^[^:]+:[0-9]+:[[:space:]]*//' || true)"
    if [ -n "$matches" ]; then
        echo "FAIL: hardcoded model URLs detected:"
        echo "$matches"
        failed=1
    fi

    matches="$(grep -RIn --include='*.swift' -E 'func[[:space:]]+(install|download|fetch)(Model|Package|CoreML|Weights)' "$sources" \
        | grep -v "^$sources/${ALLOWED_CATALOG#Sources/}:" \
        | grep -v "^$sources/${ALLOWED_STORE#Sources/}:" || true)"
    if [ -n "$matches" ]; then
        echo "FAIL: unauthorized model install/download helper detected:"
        echo "$matches"
        failed=1
    fi

    [ "$failed" -eq 0 ]
}

self_test() {
    local fixture
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-download-guard.XXXXXX")"
    trap 'rm -rf "$fixture"' RETURN
    mkdir -p \
        "$fixture/Sources/NativeBolabol/Services" \
        "$fixture/Sources/NativeBolabol/Stores"

    cat > "$fixture/Sources/NativeBolabol/Services/CloudProviderModelCatalog.swift" <<'EOF'
func fetchModels() { requestJSONCatalog() }
EOF
    cat > "$fixture/Sources/NativeBolabol/Stores/TranscriptionModelStore.swift" <<'EOF'
func downloadModelPackage() { downloadTaskForReviewedPackage() }
EOF
    printf '%s\n' 'func ordinaryCloudRequest() { dataTaskForText() }' \
        > "$fixture/Sources/NativeBolabol/Services/OrdinaryCloud.swift"

    validate_download_surface "$fixture" >/dev/null || {
        echo "FAIL: valid download-guard fixture was rejected"
        return 1
    }

    cat > "$fixture/Sources/NativeBolabol/Services/Unreviewed.swift" <<'EOF'
func request() { downloadTaskForNetwork() }
let package = "weights.mlmodelc"
EOF
    if validate_download_surface "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted downloadTask plus model context"
        return 1
    fi
    rm "$fixture/Sources/NativeBolabol/Services/Unreviewed.swift"

    printf '%s\n' 'let weights = "https://example.invalid/model.bin"' \
        > "$fixture/Sources/NativeBolabol/Services/HardcodedURL.swift"
    if validate_download_surface "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted a hardcoded model URL"
        return 1
    fi
    rm "$fixture/Sources/NativeBolabol/Services/HardcodedURL.swift"

    printf '%s\n' 'func downloadModelWeights() {}' \
        > "$fixture/Sources/NativeBolabol/Services/UnauthorizedHelper.swift"
    if validate_download_surface "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted an unauthorized download helper"
        return 1
    fi

    echo "OK: model download guard negative self-test"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

if ! validate_download_surface "$ROOT"; then
    echo "FAIL: automated model download surface detected in Sources/"
    echo "  (model/package download code requires review before introduction)"
    exit 1
fi

echo "OK: no unreviewed automated model download code in Sources/"
