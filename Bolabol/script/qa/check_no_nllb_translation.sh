#!/usr/bin/env bash
# Product-boundary guard: the retired NLLB/fake native text runtime must not
# reappear. Real CloudTextPolishingEngine and MLXSwiftPolishingEngine paths are
# intentionally allowed and are not part of this guard's forbidden vocabulary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
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

search_text() {
    local pattern="$1"
    shift
    if [ "$SEARCH_TOOL" = "rg" ]; then
        rg --no-heading --line-number --color never \
            -i -g '*.swift' -g '*.md' -g '*.sh' -e "$pattern" "$@"
    else
        # Avoid GNU-only --include so the fallback works with Darwin grep.
        grep -RIniE -- "$pattern" "$@"
    fi
}

validate_no_nllb() {
    local root="$1"
    local sources="$root/Sources"
    local paths=()
    local candidate

    if [ ! -d "$sources" ]; then
        echo "FAIL: product Sources directory is missing: $sources"
        return 1
    fi
    if ! resolve_search_tool; then
        return 1
    fi

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

    local forbidden='nllb|coremlnllb|nllb-200|texttranslationengine|bolabol_translation'
    local matches
    if matches="$(search_text "$forbidden" "${paths[@]}" 2>&1)"; then
        echo "FAIL: retired NLLB/fake native text-translation surface is still referenced"
        printf '%s\n' "$matches"
        return 1
    else
        local status=$?
        if [ "$status" -ne 1 ]; then
            echo "FAIL: search error while checking retired NLLB/fake runtime: $matches"
            return 1
        fi
    fi
    return 0
}

self_test() {
    local fixture
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-no-nllb.XXXXXX")"
    trap 'rm -rf "${fixture:-}"' EXIT

    mkdir -p "$fixture/Sources"
    printf '%s\n' \
        'struct CloudTextPolishingEngine {}' \
        'struct MLXSwiftPolishingEngine {}' \
        > "$fixture/Sources/Clean.swift"
    if ! validate_no_nllb "$fixture"; then
        echo "FAIL: clean text-provider fixture was rejected"
        return 1
    fi
    echo "PASS: clean fixture"

    rm -rf "$fixture/Sources"
    if validate_no_nllb "$fixture"; then
        echo "FAIL: missing-Sources mutation was accepted"
        return 1
    fi
    echo "PASS: missing-Sources mutation"

    mkdir -p "$fixture/Sources"
    printf '%s\n' 'struct Clean {}' > "$fixture/Sources/Clean.swift"
    if BOLABOL_QA_SEARCH_TOOL=missing validate_no_nllb "$fixture"; then
        echo "FAIL: missing-search-tool mutation was accepted"
        return 1
    fi
    echo "PASS: missing-search-tool mutation"

    printf '%s\n' 'struct CoreMLNLLBEngine {}' > "$fixture/Sources/Forbidden.swift"
    if validate_no_nllb "$fixture"; then
        echo "FAIL: negative NLLB mutation was accepted"
        return 1
    fi
    echo "PASS: negative mutation 1/1 retired NLLB runtime"
    echo "PASS: 1/1 no-NLLB negative mutations executed"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

if validate_no_nllb "$ROOT"; then
    echo "OK: NLLB/fake native text-translation product surface absent; real text providers preserved"
else
    exit 1
fi
