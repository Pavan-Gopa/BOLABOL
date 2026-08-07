#!/usr/bin/env bash
# Product-boundary guard: the retired NLLB/Core ML text-translation package
# must not reappear in application sources, tests, docs, or build metadata.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

validate_no_nllb() {
    local root="$1"
    local paths=()
    local candidate
    for candidate in \
        "$root/Sources" \
        "$root/Tests" \
        "$root/docs" \
        "$root/README.md" \
        "$root/Package.swift" \
        "$root/script/build_and_run.sh" \
        "$root/script/build_release_dmg.sh"; do
        [ -e "$candidate" ] && paths+=("$candidate")
    done
    if [ "${#paths[@]}" -eq 0 ]; then
        echo "FAIL: no product paths found for NLLB boundary scan"
        return 1
    fi

    local matches
    matches="$(grep -RIn \
        --include='*.swift' \
        --include='*.md' \
        --include='*.sh' \
        -Ei 'nllb|coremlnllb|nllb-200|translationmodel|texttranslationengine|bolabol_translation' \
        "${paths[@]}" || true)"
    if [ -n "$matches" ]; then
        echo "FAIL: retired NLLB text-translation surface is still referenced"
        echo "$matches"
        return 1
    fi
}

self_test() {
    local fixture
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-no-nllb.XXXXXX")"
    trap 'rm -rf "$fixture"' RETURN
    mkdir -p "$fixture/Sources"
    printf '%s\n' 'struct NativeTextTranslationBoundary {}' > "$fixture/Sources/Clean.swift"

    validate_no_nllb "$fixture" >/dev/null || {
        echo "FAIL: valid no-NLLB fixture was rejected"
        return 1
    }

    printf '%s\n' 'struct CoreMLNLLBEngine {}' > "$fixture/Sources/Forbidden.swift"
    if validate_no_nllb "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted a retired NLLB runtime"
        return 1
    fi

    echo "OK: retired NLLB boundary negative self-test"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

validate_no_nllb "$ROOT"
echo "OK: NLLB text-translation product surface removed"
