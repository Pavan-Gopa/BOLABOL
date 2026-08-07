#!/usr/bin/env bash
# S1b remains a pure ranking helper. This guard owns ranking/scope only; ADR-
# 021/022 deep speech-translation absence belongs to its dedicated guard.
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

search_swift() {
    local pattern="$1"
    shift
    if [ "$SEARCH_TOOL" = "rg" ]; then
        rg --no-heading --line-number --color never -g '*.swift' -e "$pattern" "$@"
    else
        # Darwin grep does not provide --include; these roots contain product
        # source files for this scope scan.
        grep -RInE -- "$pattern" "$@"
    fi
}

collect_matches() {
    local pattern="$1"
    shift
    MATCHES=""
    if MATCHES="$(search_swift "$pattern" "$@" 2>&1)"; then
        return 0
    else
        local status=$?
        if [ "$status" -eq 1 ]; then
            MATCHES=""
            return 1
        fi
        echo "FAIL: search error for pattern $pattern: $MATCHES"
        return 2
    fi
}

validate_s1b() {
    local root="$1"
    local sources="$root/Sources"
    local ranking_file="$sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift"
    local onboarding_view="$sources/NativeBolabol/Views/OnboardingView.swift"
    local settings_view="$sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift"
    local failed=0

    if [ ! -d "$sources" ]; then
        echo "FAIL: product Sources directory is missing: $sources"
        return 1
    fi
    if ! resolve_search_tool; then
        return 1
    fi
    for file in "$ranking_file" "$onboarding_view" "$settings_view"; do
        if [ ! -f "$file" ]; then
            echo "FAIL: missing S1b scope file: $file"
            failed=1
        fi
    done
    if [ "$failed" -ne 0 ]; then
        return 1
    fi

    if collect_matches '^import (SwiftUI|AppKit|Cocoa|CoreML|FluidAudio|WhisperKit|MLX)$|TranscriptionEngine|EngineStore|ModelStore|Process\(' "$ranking_file"; then
        echo "FAIL: S1b ranking helper contains UI/runtime wiring"
        printf '%s\n' "$MATCHES"
        failed=1
    elif [ $? -eq 2 ]; then
        failed=1
    fi

    if collect_matches 'OnboardingModelRecommendation|\.topThree\(' "$sources"; then
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            if [[ "$line" == *"$ranking_file"* ]]; then
                continue
            fi
            if [[ "$line" == "$onboarding_view:"* ]] && {
                [[ "$line" == *"OnboardingModelRecommendation.topThree("* ]] ||
                [[ "$line" == *"//"* ]]
            }; then
                continue
            fi
            if [[ "$line" == "$settings_view:"* ]] && {
                [[ "$line" == *"OnboardingModelRecommendation.topThree("* ]] ||
                [[ "$line" == *"//"* ]]
            }; then
                continue
            fi
            echo "FAIL: S1b ranking symbol is used outside its pure helper or S1c view: $line"
            failed=1
        done <<< "$MATCHES"
    elif [ $? -eq 2 ]; then
        failed=1
    fi

    if collect_matches 'gigaam|canary' "$sources"; then
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            case "$line" in
                *OnboardingModelRecommendation.swift*) ;;
                *TranscriptionModelDescriptor.swift*) ;;
                *TranscriptionModelStore.swift*) ;;
                *TranscriptionEngineStore.swift*) ;;
                *AppText.swift*) ;;
                *helpBilingual*) ;;
                *Engines/CanaryCoreMLEngine.swift*) ;;
                *Engines/GigaAMCoreMLEngine.swift*) ;;
                *Services/FloatingTranslationWindowManager.swift*) ;;
                *Services/HotkeySessionOverlayManager.swift*) ;;
                *Stores/TranscriptionEngineStore.swift*) ;;
                *Stores/TranscriptionModelStore.swift*) ;;
                *Views/ContentView.swift*) ;;
                *Views/Settings/HelpSettingsView.swift*) ;;
                *Views/Settings/HotkeySettingsView.swift*) ;;
                *Views/Settings/LocalModelsSettingsView.swift*) ;;
                *Views/TranslationModalView.swift*) ;;
                *NativeBolabolCore/Models/LanguagePickerOrder.swift*) ;;
                *NativeBolabolCore/Models/TranscriptionLanguageMode.swift*) ;;
                *NativeBolabolCore/Services/EngineProtocols.swift*) ;;
                *NativeBolabolCore/Services/TranscriptionLanguageRouting.swift*) ;;
                *)
                    echo "FAIL: ASR candidate appears outside S1b/helper/catalog or help copy: $line"
                    failed=1
                    ;;
            esac
        done <<< "$MATCHES"
    elif [ $? -eq 2 ]; then
        failed=1
    fi

    if [ "$failed" -ne 0 ]; then
        return 1
    fi
    return 0
}

self_test() {
    local fixture
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-s1b-scope.XXXXXX")"
    trap 'rm -rf "${fixture:-}"' EXIT
    mkdir -p \
        "$fixture/Sources/NativeBolabolCore/Models" \
        "$fixture/Sources/NativeBolabol/Views/Settings"
    printf '%s\n' 'struct OnboardingModelRecommendation {}' \
        > "$fixture/Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift"
    printf '%s\n' 'struct OnboardingView {}' \
        > "$fixture/Sources/NativeBolabol/Views/OnboardingView.swift"
    printf '%s\n' 'struct LocalModelsSettingsView {}' \
        > "$fixture/Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift"

    if ! validate_s1b "$fixture"; then
        echo "FAIL: clean fixture was rejected"
        return 1
    fi
    echo "PASS: clean fixture"

    rm -rf "$fixture/Sources"
    if validate_s1b "$fixture"; then
        echo "FAIL: missing-Sources mutation was accepted"
        return 1
    fi
    echo "PASS: missing-Sources mutation"

    mkdir -p \
        "$fixture/Sources/NativeBolabolCore/Models" \
        "$fixture/Sources/NativeBolabol/Views/Settings"
    printf '%s\n' 'struct OnboardingModelRecommendation {}' \
        > "$fixture/Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift"
    printf '%s\n' 'struct OnboardingView {}' \
        > "$fixture/Sources/NativeBolabol/Views/OnboardingView.swift"
    printf '%s\n' 'struct LocalModelsSettingsView {}' \
        > "$fixture/Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift"
    if BOLABOL_QA_SEARCH_TOOL=missing validate_s1b "$fixture"; then
        echo "FAIL: missing-search-tool mutation was accepted"
        return 1
    fi
    echo "PASS: missing-search-tool mutation"

    printf '%s\n' 'import CoreML' >> "$fixture/Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift"
    if validate_s1b "$fixture"; then
        echo "FAIL: isolated S1b runtime-wiring mutation was accepted"
        return 1
    fi
    echo "PASS: negative mutation 1/1 S1b runtime wiring"
    echo "PASS: 1/1 S1b negative mutations executed"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

if validate_s1b "$ROOT"; then
    echo "OK: S1b remains a pure ranking helper with allowlisted UI call sites and no runtime wiring"
else
    exit 1
fi
