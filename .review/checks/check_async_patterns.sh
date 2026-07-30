#!/bin/bash
#
# check_async_patterns.sh
# ---------------------------------------------------------------------------
# Swift async/await concurrency-pattern review checker.
#
# Checks performed:
#   1. Task { } / Task.detached bodies that use try without do/catch.  [WARNING]
#   2. Calls to Task.sleep / Task.yield missing await.                 [WARNING]
#   3. Task.sleep cancellation handling (try? swallow / no check).     [WARNING/INFO]
#   4. UI mutations performed inside background contexts
#      (Task.detached / DispatchQueue.global) off the main actor.      [WARNING]
#   5. async functions whose body never awaits.                        [WARNING]
#   6. DispatchQueue.main.async where @MainActor would be clearer.     [INFO]
#
# Usage:  ./check_async_patterns.sh <path/to/File.swift>
# Output: [SEVERITY] file:line: message
# Exit:   0 when no findings, 1 when at least one finding exists.
# Tools:  grep / awk only.
# ---------------------------------------------------------------------------
set -u

FILE_PATH="${1:-}"

if [ -z "$FILE_PATH" ]; then
    echo "Usage: $0 <swift_file>"
    exit 1
fi

if [ ! -f "$FILE_PATH" ]; then
    echo "File not found: $FILE_PATH"
    exit 1
fi

ISSUES_FOUND=0

report() {
    if [ -n "$1" ]; then
        printf '%s\n' "$1"
        ISSUES_FOUND=1
    fi
}

# --- Check 1: Task bodies that use try without do/catch --------------------
result=$(awk -v fp="$FILE_PATH" '
{ lines[NR] = $0 }
END {
    for (i = 1; i <= NR; i++) {
        code = lines[i]
        sub(/[[:space:]]\/\/.*$/, "", code)
        if (code ~ /(^|[^A-Za-z0-9_])Task[[:space:]]*(\.[[:space:]]*detached)?[[:space:]]*\{/) {
            depth = 0; started = 0; hastry = 0; hascatch = 0
            for (j = i; j <= NR && j <= i + 60; j++) {
                b = lines[j]
                sub(/[[:space:]]\/\/.*$/, "", b)
                if (b ~ /(^|[^A-Za-z0-9_])try([[:space:]]|\?|!)/) hastry = 1
                if (b ~ /(^|[^A-Za-z0-9_])catch([^A-Za-z0-9_]|$)/ || b ~ /do[[:space:]]*\{/) hascatch = 1
                tmp = b; ob = gsub(/\{/, "{", tmp)
                tmp = b; cb = gsub(/\}/, "}", tmp)
                depth += ob - cb
                if (ob > 0) started = 1
                if (started && depth <= 0) break
            }
            if (hastry && !hascatch) {
                printf "[WARNING] %s:%d: Task body uses try without do/catch; thrown errors may go unhandled\n", fp, i
            }
        }
    }
}
' "$FILE_PATH")
report "$result"

# --- Check 2: missing await on async Task calls ----------------------------
result=$(awk -v fp="$FILE_PATH" '
{
    code = $0
    sub(/[[:space:]]\/\/.*$/, "", code)
    if (code ~ /Task[[:space:]]*\.[[:space:]]*(sleep|yield)/ && code !~ /(^|[^A-Za-z0-9_])await([^A-Za-z0-9_]|$)/) {
        printf "[WARNING] %s:%d: missing await before an async Task call (Task.sleep / Task.yield)\n", fp, NR
    }
}
' "$FILE_PATH")
report "$result"

# --- Check 3: Task.sleep cancellation handling -----------------------------
result=$(awk -v fp="$FILE_PATH" '
{
    code = $0
    sub(/[[:space:]]\/\/.*$/, "", code)
    if (code ~ /try\?[[:space:]]+Task[[:space:]]*\.[[:space:]]*sleep/) {
        printf "[WARNING] %s:%d: Task.sleep cancellation error swallowed with try?; inspect Task.isCancelled after sleeping\n", fp, NR
    } else if (code ~ /Task[[:space:]]*\.[[:space:]]*sleep/ && code ~ /(^|[^A-Za-z0-9_])await([^A-Za-z0-9_]|$)/ && code !~ /isCancelled|checkCancellation/) {
        printf "[INFO] %s:%d: ensure cancellation is respected around Task.sleep (check Task.isCancelled)\n", fp, NR
    }
}
' "$FILE_PATH")
report "$result"

# --- Check 4: UI updates inside background contexts ------------------------
result=$(awk -v fp="$FILE_PATH" '
BEGIN { depth = 0; bg = 0; bgdepth = 0 }
{
    code = $0
    sub(/[[:space:]]\/\/.*$/, "", code)

    if (code ~ /Task[[:space:]]*\.[[:space:]]*detached/ || (code ~ /global\(\)/ && code ~ /async/)) {
        bg = 1; bgdepth = depth
    }

    if (bg && depth > bgdepth) {
        if (code ~ /\.text[[:space:]]*=/ || code ~ /\.image[[:space:]]*=/ || code ~ /\.backgroundColor[[:space:]]*=/ || code ~ /\.isHidden[[:space:]]*=/ || code ~ /\.isEnabled[[:space:]]*=/ || code ~ /\.alpha[[:space:]]*=/ || code ~ /addSubview/ || code ~ /removeFromSuperview/ || code ~ /reloadData/ || code ~ /setNeedsLayout/ || code ~ /layoutIfNeeded/ || code ~ /insertSubview/) {
            printf "[WARNING] %s:%d: UI update performed inside a background context; dispatch to the main actor (@MainActor / MainActor.run)\n", fp, NR
        }
    }

    tmp = code; ob = gsub(/\{/, "{", tmp)
    tmp = code; cb = gsub(/\}/, "}", tmp)
    depth += ob - cb
    if (bg && depth <= bgdepth) bg = 0
}
' "$FILE_PATH")
report "$result"

# --- Check 5: async functions that never await -----------------------------
result=$(awk -v fp="$FILE_PATH" '
{ lines[NR] = $0 }
END {
    for (i = 1; i <= NR; i++) {
        code = lines[i]
        sub(/[[:space:]]\/\/.*$/, "", code)
        if (code ~ /(^|[[:space:]])func[[:space:]]+[A-Za-z_]/ && code ~ /(^|[^A-Za-z0-9_])async([^A-Za-z0-9_]|$)/ && code ~ /\{/) {
            depth = 0; started = 0; hasawait = 0
            for (j = i; j <= NR; j++) {
                b = lines[j]
                sub(/[[:space:]]\/\/.*$/, "", b)
                if (b ~ /(^|[^A-Za-z0-9_])await([^A-Za-z0-9_]|$)/ || b ~ /async[[:space:]]+let/) hasawait = 1
                tmp = b; ob = gsub(/\{/, "{", tmp)
                tmp = b; cb = gsub(/\}/, "}", tmp)
                depth += ob - cb
                if (ob > 0) started = 1
                if (started && depth <= 0) break
            }
            if (!hasawait) {
                printf "[WARNING] %s:%d: async function never awaits; remove async unless required for a protocol or override\n", fp, i
            }
        }
    }
}
' "$FILE_PATH")
report "$result"

# --- Check 6: DispatchQueue.main.async where @MainActor is clearer ---------
result=$(awk -v fp="$FILE_PATH" '
{
    code = $0
    sub(/[[:space:]]\/\/.*$/, "", code)
    if (code ~ /DispatchQueue[[:space:]]*\.[[:space:]]*main[[:space:]]*\.[[:space:]]*async/) {
        printf "[INFO] %s:%d: DispatchQueue.main.async; consider @MainActor isolation instead of manual main-queue dispatch\n", fp, NR
    }
}
' "$FILE_PATH")
report "$result"

exit "$ISSUES_FOUND"
