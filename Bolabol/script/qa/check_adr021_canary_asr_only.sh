#!/usr/bin/env bash
# ADR-021/022 fail-closed product boundary. This guard owns the complete
# application-wide absence contract; positive engine behavior remains in S9.
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
        # Darwin grep has no --include; product Sources are Swift-only for
        # this guard, and the explicit files passed below are Swift files.
        grep -RInE -- "$pattern" "$@"
    fi
}

require_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "FAIL: missing required product file: $file"
        return 1
    fi
}

require_marker() {
    local file="$1"
    local pattern="$2"
    local description="$3"
    local output
    if output="$(search_swift "$pattern" "$file" 2>&1)"; then
        return 0
    else
        local status=$?
        if [ "$status" -eq 1 ]; then
            echo "FAIL: $description"
        else
            echo "FAIL: search error while checking $description: $output"
        fi
        return 1
    fi
}

forbid_marker() {
    local pattern="$1"
    local description="$2"
    shift 2
    local output
    if output="$(search_swift "$pattern" "$@" 2>&1)"; then
        echo "FAIL: $description"
        printf '%s\n' "$output"
        return 1
    else
        local status=$?
        if [ "$status" -eq 1 ]; then
            return 0
        fi
        echo "FAIL: search error while checking $description: $output"
        return 1
    fi
}

validate() {
    local root="$1"
    local sources="$root/Sources"
    local engine_protocols="$sources/NativeBolabolCore/Services/EngineProtocols.swift"
    local routing="$sources/NativeBolabolCore/Services/TranscriptionLanguageRouting.swift"
    local store="$sources/NativeBolabol/Stores/TranscriptionEngineStore.swift"
    local canary="$sources/NativeBolabol/Engines/CanaryCoreMLEngine.swift"
    local translation="$sources/NativeBolabol/Views/TranslationModalView.swift"
    local floating="$sources/NativeBolabol/Services/FloatingTranslationWindowManager.swift"
    local failed=0

    if [ ! -d "$sources" ]; then
        echo "FAIL: product Sources directory is missing: $sources"
        return 1
    fi
    if ! resolve_search_tool; then
        return 1
    fi

    for file in "$engine_protocols" "$routing" "$store" "$canary" "$translation" "$floating"; do
        require_file "$file" || failed=1
    done
    if [ "$failed" -ne 0 ]; then
        return 1
    fi

    if [ -e "$sources/NativeBolabol/Services/CanarySpeechTranslationRuntime.swift" ]; then
        echo "FAIL: forbidden CanarySpeechTranslationRuntime.swift exists"
        failed=1
    fi

    for marker in \
        '\.speechTranslation' \
        'makeSpeechTranslationSession' \
        'speechTranslationTargetLanguageCode' \
        'SpeechTranslationDirection' \
        'supportsSpeechTranslation' \
        'supportedSpeechTranslationDirections' \
        'isCanaryTargetSwitchable' \
        'toggledCanaryTarget' \
        'resolveTargetLanguage' \
        '\.ordinaryASR' \
        '\.whisperTarget\('; do
        if ! forbid_marker "$marker" "forbidden ADR-022 product marker remains: $marker" "$sources"; then
            failed=1
        fi
    done

    if ! forbid_marker 'targetLanguageCode' \
        "transcription request/routing/Canary target field remains" \
        "$engine_protocols" "$routing" "$store" "$canary"; then
        failed=1
    fi
    if ! forbid_marker 'translateToEnglish[[:space:]]*:[[:space:]]*true' \
        "Canary product contains a translation-flag request" "$canary"; then
        failed=1
    fi
    if ! forbid_marker 'Canary|SpeechTranslation|onCanaryTranslation|localCanaryPrefix' \
        "Translation modal contains a Canary provider/callback surface" "$translation"; then
        failed=1
    fi
    if ! forbid_marker 'Canary|SpeechTranslation|onCanaryTranslation|localCanaryPrefix' \
        "Floating Translation contains a Canary callback/dependency" "$floating"; then
        failed=1
    fi

    require_marker "$routing" 'case[[:space:]]+asr' \
        "closed .asr session operation is missing" || failed=1
    require_marker "$routing" 'case[[:space:]]+whisperTargetTranslation\(languageCode:[[:space:]]*String\)' \
        "typed Whisper target operation is missing" || failed=1
    require_marker "$routing" 'postASRTextTranslationTargetLanguageCode' \
        "explicit post-ASR text target is missing" || failed=1
    require_marker "$store" 'func[[:space:]]+makeSession' \
        "single makeSession factory is missing" || failed=1
    require_marker "$canary" 'validateASROnlyRequest' \
        "real Canary ASR-only validator is missing" || failed=1
    require_marker "$canary" 'guard[[:space:]]*!request\.translateToEnglish' \
        "Canary early translation rejection is missing" || failed=1
    require_marker "$canary" 'translationUnsupported' \
        "non-directional Canary translation error is missing" || failed=1

    if [ "$failed" -ne 0 ]; then
        return 1
    fi
    return 0
}

write_clean_fixture() {
    local fixture="$1"
    rm -rf "$fixture/Sources"
    mkdir -p \
        "$fixture/Sources/NativeBolabolCore/Services" \
        "$fixture/Sources/NativeBolabol/Stores" \
        "$fixture/Sources/NativeBolabol/Engines" \
        "$fixture/Sources/NativeBolabol/Views" \
        "$fixture/Sources/NativeBolabol/Services"
    printf '%s\n' \
        'struct TranscriptionRequest { var forcedLanguageCode: String?; var translateToEnglish: Bool }' \
        > "$fixture/Sources/NativeBolabolCore/Services/EngineProtocols.swift"
    printf '%s\n' \
        'enum TranscriptionSessionOperation { case asr; case whisperTargetTranslation(languageCode: String) }' \
        'let postASRTextTranslationTargetLanguageCode: String? = nil' \
        > "$fixture/Sources/NativeBolabolCore/Services/TranscriptionLanguageRouting.swift"
    printf '%s\n' 'func makeSession() {}' \
        > "$fixture/Sources/NativeBolabol/Stores/TranscriptionEngineStore.swift"
    printf '%s\n' \
        'enum CanaryError { case translationUnsupported }' \
        'func validateASROnlyRequest(_ request: TranscriptionRequest) throws {' \
        '    guard !request.translateToEnglish else { throw CanaryError.translationUnsupported }' \
        '}' \
        > "$fixture/Sources/NativeBolabol/Engines/CanaryCoreMLEngine.swift"
    printf '%s\n' 'struct TranslationModalView { let provider = "PolishingEngineStore" }' \
        > "$fixture/Sources/NativeBolabol/Views/TranslationModalView.swift"
    printf '%s\n' 'struct FloatingTranslationWindowManager {}' \
        > "$fixture/Sources/NativeBolabol/Services/FloatingTranslationWindowManager.swift"
}

self_test() {
    local fixture
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-adr021-guard.XXXXXX")"
    trap 'rm -rf "${fixture:-}"' EXIT
    local mutations=0

    write_clean_fixture "$fixture"
    if ! validate "$fixture"; then
        echo "FAIL: clean fixture was rejected"
        return 1
    fi
    echo "PASS: clean fixture"

    rm -rf "$fixture/Sources"
    if validate "$fixture"; then
        echo "FAIL: missing-Sources mutation was accepted"
        return 1
    fi
    echo "PASS: missing-Sources mutation"

    write_clean_fixture "$fixture"
    if BOLABOL_QA_SEARCH_TOOL=missing validate "$fixture"; then
        echo "FAIL: missing-search-tool mutation was accepted"
        return 1
    fi
    echo "PASS: missing-search-tool mutation"

    write_clean_fixture "$fixture"
    printf '%s\n' 'runtime' > "$fixture/Sources/NativeBolabol/Services/CanarySpeechTranslationRuntime.swift"
    if validate "$fixture"; then
        echo "FAIL: mutation CanarySpeechTranslationRuntime.swift was accepted"
        return 1
    fi
    mutations=$((mutations + 1)); echo "PASS: negative mutation $mutations/9 CanarySpeechTranslationRuntime.swift"

    write_clean_fixture "$fixture"
    printf '%s\n' 'let onCanaryTranslation = true' >> "$fixture/Sources/NativeBolabol/Views/TranslationModalView.swift"
    if validate "$fixture"; then
        echo "FAIL: mutation onCanaryTranslation was accepted"
        return 1
    fi
    mutations=$((mutations + 1)); echo "PASS: negative mutation $mutations/9 onCanaryTranslation"

    write_clean_fixture "$fixture"
    printf '%s\n' 'let localCanaryPrefix = "Canary"' >> "$fixture/Sources/NativeBolabol/Views/TranslationModalView.swift"
    if validate "$fixture"; then
        echo "FAIL: mutation localCanaryPrefix was accepted"
        return 1
    fi
    mutations=$((mutations + 1)); echo "PASS: negative mutation $mutations/9 localCanaryPrefix"

    write_clean_fixture "$fixture"
    printf '%s\n' 'let operation = .speechTranslation' >> "$fixture/Sources/NativeBolabolCore/Services/TranscriptionLanguageRouting.swift"
    if validate "$fixture"; then
        echo "FAIL: mutation .speechTranslation was accepted"
        return 1
    fi
    mutations=$((mutations + 1)); echo "PASS: negative mutation $mutations/9 .speechTranslation"

    write_clean_fixture "$fixture"
    printf '%s\n' 'func makeSpeechTranslationSession() {}' >> "$fixture/Sources/NativeBolabol/Stores/TranscriptionEngineStore.swift"
    if validate "$fixture"; then
        echo "FAIL: mutation makeSpeechTranslationSession was accepted"
        return 1
    fi
    mutations=$((mutations + 1)); echo "PASS: negative mutation $mutations/9 makeSpeechTranslationSession"

    write_clean_fixture "$fixture"
    printf '%s\n' 'let speechTranslationTargetLanguageCode: String? = nil' >> "$fixture/Sources/NativeBolabolCore/Services/TranscriptionLanguageRouting.swift"
    if validate "$fixture"; then
        echo "FAIL: mutation speechTranslationTargetLanguageCode was accepted"
        return 1
    fi
    mutations=$((mutations + 1)); echo "PASS: negative mutation $mutations/9 speechTranslationTargetLanguageCode"

    write_clean_fixture "$fixture"
    printf '%s\n' 'let targetLanguageCode = "fr"' >> "$fixture/Sources/NativeBolabol/Engines/CanaryCoreMLEngine.swift"
    if validate "$fixture"; then
        echo "FAIL: mutation Canary directional targetLanguageCode was accepted"
        return 1
    fi
    mutations=$((mutations + 1)); echo "PASS: negative mutation $mutations/9 Canary directional targetLanguageCode"

    write_clean_fixture "$fixture"
    printf '%s\n' 'let canaryRequest = TranscriptionRequest(translateToEnglish: true)' >> "$fixture/Sources/NativeBolabol/Engines/CanaryCoreMLEngine.swift"
    if validate "$fixture"; then
        echo "FAIL: mutation Canary request with translation flag was accepted"
        return 1
    fi
    mutations=$((mutations + 1)); echo "PASS: negative mutation $mutations/9 Canary request translation flag"

    write_clean_fixture "$fixture"
    printf '%s\n' 'let canaryProviderRow = "Canary"' >> "$fixture/Sources/NativeBolabol/Views/TranslationModalView.swift"
    if validate "$fixture"; then
        echo "FAIL: mutation Canary provider row was accepted"
        return 1
    fi
    mutations=$((mutations + 1)); echo "PASS: negative mutation $mutations/9 Canary provider row"

    if [ "$mutations" -ne 9 ]; then
        echo "FAIL: executed $mutations/9 required negative mutations"
        return 1
    fi
    echo "PASS: 9/9 ADR-021 negative mutations executed"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

if validate "$ROOT"; then
    echo "OK: ADR-021 Canary ASR-only deep contract is absent and fail-closed"
else
    exit 1
fi
