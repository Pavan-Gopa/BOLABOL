#!/bin/bash
#
# check_swift6_concurrency.sh
# ---------------------------------------------------------------------------
# Swift 6 strict-concurrency review checker.
#
# Checks performed:
#   1. Non-Sendable reference types that may cross actor boundaries
#      (detached tasks, and classes in concurrency-using files).       [WARNING/INFO]
#   2. Escaping closures / closure properties missing @Sendable.       [WARNING]
#   3. Global mutable state without synchronization.                   [WARNING]
#   4. UI-related types missing @MainActor.                            [WARNING]
#   5. Shared mutable state (mutable statics) as a data-race risk.     [WARNING]
#
# Usage:  ./check_swift6_concurrency.sh <path/to/File.swift>
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

# --- Check 1: non-Sendable types crossing actor boundaries -----------------
result=$(awk -v fp="$FILE_PATH" '
{
    lines[NR] = $0
    if ($0 ~ /Task[[:space:]]*\{/ || $0 ~ /Task[[:space:]]*\./ || $0 ~ /(^|[^A-Za-z0-9_])await([^A-Za-z0-9_]|$)/ || $0 ~ /(^|[[:space:]])actor[[:space:]]/ || $0 ~ /@MainActor/ || $0 ~ /(^|[^A-Za-z0-9_])async([^A-Za-z0-9_]|$)/) conc = 1
}
END {
    for (i = 1; i <= NR; i++) {
        code = lines[i]
        sub(/[[:space:]]\/\/.*$/, "", code)
        prev = (i > 1) ? lines[i - 1] : ""

        if (code ~ /Task[[:space:]]*\.[[:space:]]*detached/) {
            printf "[WARNING] %s:%d: detached task crosses actor boundaries; ensure every captured value is Sendable\n", fp, i
        }

        if (conc && code ~ /(^|[[:space:]])(final[[:space:]]+|public[[:space:]]+|open[[:space:]]+|internal[[:space:]]+|private[[:space:]]+|fileprivate[[:space:]]+)*class[[:space:]]+[A-Za-z_]/ && code !~ /Sendable/ && code !~ /@MainActor/ && prev !~ /@MainActor/) {
            printf "[INFO] %s:%d: class is not Sendable; instances must not cross actor boundaries unless isolated or marked @unchecked Sendable\n", fp, i
        }
    }
}
' "$FILE_PATH")
report "$result"

# --- Check 2: escaping closures missing @Sendable --------------------------
result=$(awk -v fp="$FILE_PATH" '
{
    code = $0
    sub(/[[:space:]]\/\/.*$/, "", code)
    if (code ~ /(^|[[:space:]])(var|let)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*\(.*\)[[:space:]]*->/ && code !~ /@Sendable/) {
        printf "[WARNING] %s:%d: stored closure property should be marked @Sendable for Swift 6 strict concurrency\n", fp, NR
    }
    if (code ~ /@escaping[[:space:]]+\(/ && code !~ /@Sendable/) {
        printf "[WARNING] %s:%d: @escaping closure parameter is not @Sendable; sending it across isolation is unsafe\n", fp, NR
    }
}
' "$FILE_PATH")
report "$result"

# --- Check 3: global mutable state -----------------------------------------
result=$(awk -v fp="$FILE_PATH" '
{
    code = $0
    sub(/[[:space:]]\/\/.*$/, "", code)
    if (code ~ /^(public[[:space:]]+|internal[[:space:]]+|private[[:space:]]+|fileprivate[[:space:]]+)?var[[:space:]]+[A-Za-z_]/) {
        printf "[WARNING] %s:%d: global mutable state; isolate in an actor or protect with synchronization, or make it immutable\n", fp, NR
    }
}
' "$FILE_PATH")
report "$result"

# --- Check 4: UI-related types missing @MainActor --------------------------
result=$(awk -v fp="$FILE_PATH" '
{ lines[NR] = $0 }
END {
    for (i = 1; i <= NR; i++) {
        code = lines[i]
        sub(/[[:space:]]\/\/.*$/, "", code)
        prev = (i > 1) ? lines[i - 1] : ""
        if (code ~ /(^|[[:space:]])(final[[:space:]]+|public[[:space:]]+|open[[:space:]]+|internal[[:space:]]+|private[[:space:]]+|fileprivate[[:space:]]+)*(class|struct)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*(View|ViewController|Controller|Cell|Screen)([^A-Za-z0-9_]|$)/ && code !~ /@MainActor/ && prev !~ /@MainActor/) {
            printf "[WARNING] %s:%d: UI-related type should be annotated @MainActor for Swift 6 safety\n", fp, i
        }
    }
}
' "$FILE_PATH")
report "$result"

# --- Check 5: shared mutable state (mutable statics) -----------------------
result=$(awk -v fp="$FILE_PATH" '
{
    code = $0
    sub(/[[:space:]]\/\/.*$/, "", code)
    if (code ~ /(^|[[:space:]])static[[:space:]]+var[[:space:]]/) {
        printf "[WARNING] %s:%d: mutable static state is a potential data race under Swift 6; isolate in an actor or protect with synchronization\n", fp, NR
    }
}
' "$FILE_PATH")
report "$result"

exit "$ISSUES_FOUND"
