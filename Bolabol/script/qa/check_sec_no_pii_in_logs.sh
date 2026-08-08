#!/usr/bin/env bash
# Security guard: unified-log statements must not interpolate secrets or raw
# user dictation/note text. Extracts every NativeBolabolLog statement
# (balanced parentheses, multi-line aware) and scans the interpolated
# identifiers. print()/NSLog are forbidden in product sources outright.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

FORBIDDEN_INTERPOLATIONS='apiKey|api_key|secret|password|credential|credentials|accessToken|access_token|rawText|transcribedText|noteText|dictationText|polishedText|userText'

extract_log_statements() {
    # Prints every NativeBolabolLog statement (joined multi-line) in a file.
    awk '
        /NativeBolabolLog\./ && depth == 0 { capture = 1; depth = 0; stmt = "" }
        capture == 1 {
            stmt = stmt "\n" $0
            n = gsub(/\(/, "(")
            m = gsub(/\)/, ")")
            depth += n - m
            if (depth <= 0 && stmt ~ /\)/) { print stmt; capture = 0; stmt = ""; depth = 0 }
        }
    ' "$1"
}

validate_no_pii_logging() {
    local root="$1"
    local sources="$root/Sources"
    local failed=0

    if [ ! -d "$sources" ]; then
        echo "FAIL: Sources/ not found under $root"
        return 1
    fi

    # 1. No print()/NSLog in product sources (unstructured leaks).
    local direct
    direct="$(grep -RInE '(^|[[:space:]])print\(|NSLog\(' --include='*.swift' "$sources" || true)"
    if [ -n "$direct" ]; then
        echo "FAIL: print()/NSLog found in product sources:"
        echo "$direct"
        failed=1
    fi

    # 2. Log statements must not interpolate secrets or raw user text.
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        local relative="${file#"$root/"}"
        local hits
        hits="$(extract_log_statements "$file" \
            | grep -nE '[\\][(]('"$FORBIDDEN_INTERPOLATIONS"')([ ,.]|\)|$)' || true)"
        if [ -n "$hits" ]; then
            echo "FAIL: sensitive interpolation inside log statement in $relative:"
            echo "$hits"
            failed=1
        fi
    done < <(grep -RIl "NativeBolabolLog" --include='*.swift' "$sources" || true)

    [ "$failed" -eq 0 ]
}

self_test() {
    local fixture
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-pii-log.XXXXXX")"
    trap 'rm -rf "$fixture"' RETURN
    mkdir -p "$fixture/Sources/App"

    cat > "$fixture/Sources/App/Clean.swift" <<'EOF'
import Foundation
func clean() {
    NativeBolabolLog.transcription.info(
        "Dispatch length=\(text.count, privacy: .public) mode=\(mode.rawValue, privacy: .public)"
    )
    NativeBolabolLog.models.error("Download failed for \(modelID, privacy: .public)")
}
EOF
    validate_no_pii_logging "$fixture" >/dev/null || {
        echo "FAIL: clean fixture was rejected"
        return 1
    }

    cat > "$fixture/Sources/App/Leak.swift" <<'EOF'
import Foundation
func leak() {
    NativeBolabolLog.transcription.info("key=\(apiKey, privacy: .public)")
}
EOF
    if validate_no_pii_logging "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted apiKey logging"
        return 1
    fi
    rm "$fixture/Sources/App/Leak.swift"

    cat > "$fixture/Sources/App/TextLeak.swift" <<'EOF'
import Foundation
func leak() {
    NativeBolabolLog.polishing.error(
        "polish failed text=\(rawText)"
    )
}
EOF
    if validate_no_pii_logging "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted rawText logging"
        return 1
    fi
    rm "$fixture/Sources/App/TextLeak.swift"

    cat > "$fixture/Sources/App/Print.swift" <<'EOF'
func debug() { print("debug") }
EOF
    if validate_no_pii_logging "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted print() in sources"
        return 1
    fi

    echo "OK: PII logging guard negative self-test"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

if ! validate_no_pii_logging "$ROOT"; then
    echo "FAIL: sensitive data can reach the unified log"
    exit 1
fi

echo "OK: no secrets or raw user text are interpolated into log statements"
