#!/usr/bin/env bash
# Security guard: model/package download destinations must be protected
# against path traversal. Pins the hardened Bolabol CDN manifest contract
# (reject "..", absolute paths, empty components; SHA-256 verify every file)
# so a future change cannot silently drop the sanitization.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TRANSCRIPTION_STORE="Sources/NativeBolabol/Stores/TranscriptionModelStore.swift"
POLISHING_STORE="Sources/NativeBolabol/Stores/PolishingEngineStore.swift"
SHARED_MODELS_ROOT="Sources/NativeBolabolCore/Services/SharedModelsRoot.swift"
POLISHING_POLICY="Sources/NativeBolabolCore/Services/PolishingRequestPolicy.swift"
SECURITY_TESTS="Tests/NativeBolabolCoreTests/SecuritySurfaceRegressionTests.swift"

require_literal() {
    local file="$1"
    local needle="$2"
    local message="$3"
    local failed_ref="$4"
    if ! grep -qF -- "$needle" "$file"; then
        echo "FAIL: $message"
        eval "$failed_ref=1"
    fi
}

validate_path_safety() {
    local root="$1"
    local transcription_store="$root/$TRANSCRIPTION_STORE"
    local polishing_store="$root/$POLISHING_STORE"
    local shared_models_root="$root/$SHARED_MODELS_ROOT"
    local polishing_policy="$root/$POLISHING_POLICY"
    local security_tests="$root/$SECURITY_TESTS"
    local failed=0

    for required_file in \
        "$transcription_store" \
        "$polishing_store" \
        "$shared_models_root" \
        "$polishing_policy" \
        "$security_tests"; do
        if [ ! -f "$required_file" ]; then
            echo "FAIL: required security surface file not found: $required_file"
            failed=1
        fi
    done
    [ "$failed" -eq 0 ] || return 1

    # 1. Manifest file entries must be validated before use.
    require_literal "$transcription_store" "isSafeManifestFile" \
        "manifest file safety predicate (isSafeManifestFile) missing" failed

    # 2. The predicate must reject dot-dot traversal components.
    require_literal "$transcription_store" 'components.contains("..")' \
        "manifest predicate no longer rejects '..' path components" failed

    # 3. The predicate must reject absolute paths.
    require_literal "$transcription_store" 'path.hasPrefix("/")' \
        "manifest predicate no longer rejects absolute paths" failed

    # 4. Both Hugging Face tree seams must validate all remote paths before
    # constructing local destinations, and reject with typed errors.
    require_literal "$transcription_store" \
        'guard fileItems.allSatisfy({ ModelDownloadPathPolicy.isSafe($0.path) })' \
        "transcription Hugging Face preflight path validation missing" failed
    require_literal "$transcription_store" \
        'TranscriptionModelDownloadError.invalidRemotePath' \
        "typed transcription unsafe-path error missing" failed
    require_literal "$polishing_store" \
        'guard entries.allSatisfy({ ModelDownloadPathPolicy.isSafe($0.path) })' \
        "polishing Hugging Face preflight path validation missing" failed
    require_literal "$polishing_store" \
        'ModelDownloadPathPolicy.isSafe(entry.path)' \
        "polishing destination path validation missing" failed
    require_literal "$polishing_store" \
        'PolishingModelDownloadError.invalidRemotePath' \
        "typed polishing unsafe-path error missing" failed

    # 5. Every downloaded CDN file must pass SHA-256 verification.
    if ! grep -q "verifyFileSHA256" "$transcription_store"; then
        echo "FAIL: SHA-256 verification helper missing"
        failed=1
    fi
    local sha_calls
    sha_calls="$(grep -c "verifyFileSHA256(localFileURL" "$transcription_store" || true)"
    if [ "${sha_calls:-0}" -lt 1 ]; then
        echo "FAIL: downloaded CDN files are no longer SHA-256 verified"
        failed=1
    fi

    # 6. Manifests must be validated before any file is written from them.
    if ! grep -q "validatedManifest" "$transcription_store"; then
        echo "FAIL: validatedManifest gate missing"
        failed=1
    fi

    # 7. Manifest hash fields must be shape-checked (64 hex chars).
    if ! grep -q "hash.count == 64" "$transcription_store"; then
        echo "FAIL: manifest SHA-256 shape check missing"
        failed=1
    fi

    # 8. Remote polishing downloads do not need executable Python artifacts.
    if grep -qF -- '"*.py"' "$polishing_store"; then
        echo "FAIL: MLX download patterns still include *.py"
        failed=1
    fi

    # 9. Existing symlink components must be checked before interpreting a
    # model URL, including when the tail does not exist yet.
    require_literal "$shared_models_root" "symlinkSafeURL" \
        "missing-tail symlink-safe resolver missing" failed
    require_literal "$shared_models_root" "destinationOfSymbolicLink" \
        "symlink component walk missing" failed

    # 10. User transcription cannot close the literal wrapper delimiter.
    require_literal "$polishing_policy" 'of: "</transcription>"' \
        "transcription delimiter scan missing" failed
    require_literal "$polishing_policy" '\u{200D}' \
        "transcription delimiter neutralization missing" failed

    # 11. Regression tests must cover the missing-tail and delimiter seams.
    require_literal "$security_tests" "missingTailSymlinkEscapeRejected" \
        "missing-tail symlink regression test missing" failed
    require_literal "$security_tests" "closingDelimiterIsNeutralized" \
        "delimiter regression test missing" failed
    require_literal "$security_tests" "huggingFaceTraversalFailsClosed" \
        "Hugging Face no-write regression test missing" failed

    [ "$failed" -eq 0 ]
}

self_test() {
    local fixture
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-path-safety.XXXXXX")"
    trap 'rm -rf "$fixture"' RETURN
    mkdir -p \
        "$fixture/Sources/NativeBolabol/Stores" \
        "$fixture/Sources/NativeBolabolCore/Services" \
        "$fixture/Tests/NativeBolabolCoreTests"

    cat > "$fixture/$TRANSCRIPTION_STORE" <<'EOF'
private func isSafeManifestFile(_ file: BolabolPackageManifestFile) -> Bool {
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    return !path.isEmpty
        && !path.hasPrefix("/")
        && !components.contains("..")
        && !components.contains("")
}
let manifest = try validatedManifest(data: data, packageID: packageID)
guard verifyFileSHA256(localFileURL, expectedHash: file.sha256) else { throw }
if fileManager.fileExists(atPath: localFileURL.path),
   verifyFileSHA256(localFileURL, expectedHash: file.sha256) { }
guard hash.count == 64 else { return false }
let fileItems = items.filter { $0.type == "file" }
guard fileItems.allSatisfy({ ModelDownloadPathPolicy.isSafe($0.path) }) else { throw TranscriptionModelDownloadError.invalidRemotePath($0.path) }
guard ModelDownloadPathPolicy.isSafe(item.path) else { throw TranscriptionModelDownloadError.invalidRemotePath(item.path) }
EOF

    cat > "$fixture/$POLISHING_STORE" <<'EOF'
let entries = try JSONDecoder().decode([DirectHuggingFaceTreeEntry].self, from: data)
guard entries.allSatisfy({ ModelDownloadPathPolicy.isSafe($0.path) }) else { throw PolishingModelDownloadError.invalidRemotePath($0.path) }
guard ModelDownloadPathPolicy.isSafe(entry.path) else { throw PolishingModelDownloadError.invalidRemotePath(entry.path) }
private static let mlxModelDownloadPatterns = ["*.safetensors", "*.model"]
EOF

    cat > "$fixture/$SHARED_MODELS_ROOT" <<'EOF'
private static func symlinkSafeURL() -> URL? {
    _ = try? fileManager.destinationOfSymbolicLink(atPath: path)
    return nil
}
EOF

    cat > "$fixture/$POLISHING_POLICY" <<'EOF'
let safeUserContent = rendered.userContent.replacingOccurrences(
    of: "</transcription>",
    with: "<\u{200D}/transcription>"
)
EOF

    cat > "$fixture/$SECURITY_TESTS" <<'EOF'
func missingTailSymlinkEscapeRejected() {}
func closingDelimiterIsNeutralized() {}
func huggingFaceTraversalFailsClosed() {}
EOF

    validate_path_safety "$fixture" >/dev/null || {
        echo "FAIL: valid path-safety fixture was rejected"
        return 1
    }

    # Negative: drop the dot-dot rejection.
    cp "$fixture/$TRANSCRIPTION_STORE" "$fixture/transcription.swift.original"
    sed -i '' 's/!components.contains("..")/true/' "$fixture/$TRANSCRIPTION_STORE"
    if validate_path_safety "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted manifest without '..' rejection"
        return 1
    fi
    cp "$fixture/transcription.swift.original" "$fixture/$TRANSCRIPTION_STORE"

    # Negative: drop each remote Hugging Face preflight validation.
    cp "$fixture/$TRANSCRIPTION_STORE" "$fixture/transcription.swift.bak"
    sed -i '' 's/ModelDownloadPathPolicy.isSafe(\$0.path)/true/' "$fixture/$TRANSCRIPTION_STORE"
    if validate_path_safety "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted transcription HF path without preflight"
        return 1
    fi
    cp "$fixture/transcription.swift.bak" "$fixture/$TRANSCRIPTION_STORE"

    cp "$fixture/$POLISHING_STORE" "$fixture/polishing.swift.bak"
    sed -i '' 's/ModelDownloadPathPolicy.isSafe(\$0.path)/true/' "$fixture/$POLISHING_STORE"
    if validate_path_safety "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted polishing HF path without preflight"
        return 1
    fi
    cp "$fixture/polishing.swift.bak" "$fixture/$POLISHING_STORE"

    # Negative: restore the forbidden Python artifact pattern.
    printf '\n"*.py"\n' >> "$fixture/$POLISHING_STORE"
    if validate_path_safety "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted *.py download pattern"
        return 1
    fi
    cp "$fixture/polishing.swift.bak" "$fixture/$POLISHING_STORE"

    # Negative: remove the missing-tail symlink walk.
    cp "$fixture/$SHARED_MODELS_ROOT" "$fixture/shared-root.swift.bak"
    sed -i '' '/destinationOfSymbolicLink/d' "$fixture/$SHARED_MODELS_ROOT"
    if validate_path_safety "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted missing-tail symlink omission"
        return 1
    fi
    cp "$fixture/shared-root.swift.bak" "$fixture/$SHARED_MODELS_ROOT"

    # Negative: remove the delimiter escape marker.
    cp "$fixture/$POLISHING_POLICY" "$fixture/policy.swift.bak"
    sed -i '' 's/with: "<.*\/transcription>"/with: "<\/transcription>"/' "$fixture/$POLISHING_POLICY"
    if validate_path_safety "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted unescaped transcription delimiter"
        return 1
    fi

    echo "OK: download path safety guard negative self-test (SEC-001..004)"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

if ! validate_path_safety "$ROOT"; then
    echo "FAIL: model download path traversal protection is incomplete"
    exit 1
fi

echo "OK: download paths reject traversal, symlink escapes, and delimiter/pattern regressions"
