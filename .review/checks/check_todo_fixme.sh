#!/bin/bash
#
# check_todo_fixme.sh
# ---------------------------------------------------------------------------
# Technical-debt marker review checker.
#
# Checks performed:
#   1. TODO comments.                                                  [INFO]
#   2. FIXME comments.                                                 [WARNING]
#   3. HACK comments.                                                  [WARNING]
#   4. XXX comments.                                                   [ERROR]
#   5. Commented-out code blocks (3+ consecutive comment lines that
#      look like code).                                                [INFO]
#   6. print / debugPrint statements outside #if DEBUG regions.        [WARNING]
#
# Usage:  ./check_todo_fixme.sh <path/to/File.swift>
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

# --- Checks 1-4: TODO / FIXME / HACK / XXX markers -------------------------
result=$(awk -v fp="$FILE_PATH" '
{
    line = $0
    if (line ~ /(^|[^A-Za-z0-9_])TODO([^A-Za-z0-9_]|$)/)  printf "[INFO] %s:%d: TODO comment found; track and resolve before release\n", fp, NR
    if (line ~ /(^|[^A-Za-z0-9_])FIXME([^A-Za-z0-9_]|$)/) printf "[WARNING] %s:%d: FIXME comment found; a known defect needs attention\n", fp, NR
    if (line ~ /(^|[^A-Za-z0-9_])HACK([^A-Za-z0-9_]|$)/)  printf "[WARNING] %s:%d: HACK comment found; temporary workaround should be cleaned up\n", fp, NR
    if (line ~ /(^|[^A-Za-z0-9_])XXX([^A-Za-z0-9_]|$)/)   printf "[ERROR] %s:%d: XXX comment found; critical issue flagged in code\n", fp, NR
}
' "$FILE_PATH")
report "$result"

# --- Check 5: commented-out code blocks (3+ consecutive comment lines) -----
result=$(awk -v fp="$FILE_PATH" '
{
    isComment = ($0 ~ /^[[:space:]]*\/\// && $0 !~ /^[[:space:]]*\/\/\//)
    if (isComment) {
        if (run == 0) start = NR
        run++
        if ($0 ~ /[;{}=()]|[[:space:]](return|func|let|var|if|for|while|guard|self)[[:space:]]/) hascode = 1
    } else {
        if (run >= 3 && hascode) printf "[INFO] %s:%d: commented-out code block (%d consecutive comment lines); remove if obsolete\n", fp, start, run
        run = 0; hascode = 0
    }
}
END {
    if (run >= 3 && hascode) printf "[INFO] %s:%d: commented-out code block (%d consecutive comment lines); remove if obsolete\n", fp, start, run
}
' "$FILE_PATH")
report "$result"

# --- Check 6: print / debugPrint outside #if DEBUG -------------------------
result=$(awk -v fp="$FILE_PATH" '
BEGIN { indebug = 0 }
{
    if ($0 ~ /^[[:space:]]*#if[[:space:]]+DEBUG/) indebug = 1
    else if ($0 ~ /^[[:space:]]*#endif/) indebug = 0

    code = $0
    if (code ~ /^[[:space:]]*\/\//) next
    if (!indebug && code ~ /(^|[^A-Za-z0-9_.])(print|debugPrint)[[:space:]]*\(/) {
        printf "[WARNING] %s:%d: print/debugPrint statement; remove before release or guard with #if DEBUG\n", fp, NR
    }
}
' "$FILE_PATH")
report "$result"

exit "$ISSUES_FOUND"
