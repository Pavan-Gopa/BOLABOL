#!/bin/bash
#
# check_memory_safety.sh
# ---------------------------------------------------------------------------
# Swift memory-management review checker.
#
# Checks performed:
#   1. self captured strongly in escaping-style closures (completion
#      handlers, Task, Combine, notifications) without [weak self].    [WARNING]
#   2. delegate / dataSource properties not declared weak.             [WARNING]
#   3. Large value types (structs with many stored properties).        [WARNING]
#   4. unowned references that can crash if the target is gone.        [WARNING/ERROR]
#   5. Stored or returned closures capturing self strongly.            [WARNING]
#
# Usage:  ./check_memory_safety.sh <path/to/File.swift>
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

# --- Check 1: self captured strongly in escaping-style closures ------------
result=$(awk -v fp="$FILE_PATH" '
{ lines[NR] = $0 }
END {
    for (i = 1; i <= NR; i++) {
        code = lines[i]
        sub(/[[:space:]]\/\/.*$/, "", code)
        isOpener = (code ~ /(^|[^A-Za-z0-9_])Task[[:space:]]*(\.[[:space:]]*detached)?[[:space:]]*\{/ || code ~ /\.animate[[:space:]]*\(/ || code ~ /\.sink[[:space:]]*[\{(]/ || code ~ /addObserver/ || code ~ /NotificationCenter/ || code ~ /\.async[[:space:]]*\{/ || code ~ /completion[a-zA-Z]*[[:space:]]*:[[:space:]]*\{/ || code ~ /\.gesture[[:space:]]*\(/ || code ~ /receiveValue[[:space:]]*[\{(]/ || code ~ /\.task[[:space:]]*\{/ || code ~ /onReceive[[:space:]]*\(/ || code ~ /onChange[[:space:]]*\(/)
        if (isOpener && code !~ /\[[[:space:]]*(weak|unowned)/) {
            depth = 0; started = 0; hasself = 0; hasweak = 0
            for (j = i; j <= NR && j <= i + 60; j++) {
                b = lines[j]
                sub(/[[:space:]]\/\/.*$/, "", b)
                if (b ~ /\[[[:space:]]*(weak|unowned)[[:space:]]+self/) hasweak = 1
                if (b ~ /(^|[^A-Za-z0-9_])self([.?!]|[^A-Za-z0-9_]|$)/) hasself = 1
                tmp = b; ob = gsub(/\{/, "{", tmp)
                tmp = b; cb = gsub(/\}/, "}", tmp)
                depth += ob - cb
                if (ob > 0) started = 1
                if (started && depth <= 0) break
            }
            if (hasself && !hasweak) {
                printf "[WARNING] %s:%d: escaping closure captures self strongly; add [weak self] (or [unowned self]) to avoid a retain cycle\n", fp, i
            }
        }
    }
}
' "$FILE_PATH")
report "$result"

# --- Check 2: delegate / dataSource not weak -------------------------------
result=$(awk -v fp="$FILE_PATH" '
{
    code = $0
    sub(/[[:space:]]\/\/.*$/, "", code)
    if (code ~ /(^|[[:space:]])var[[:space:]]/ && code ~ /([Dd]elegate|[Dd]ataSource)/ && code !~ /(^|[[:space:]])weak[[:space:]]/ && code !~ /unowned/) {
        printf "[WARNING] %s:%d: delegate/dataSource property should be declared weak to avoid a retain cycle\n", fp, NR
    }
}
' "$FILE_PATH")
report "$result"

# --- Check 3: large value types --------------------------------------------
result=$(awk -v fp="$FILE_PATH" '
{ lines[NR] = $0 }
END {
    for (i = 1; i <= NR; i++) {
        code = lines[i]
        sub(/[[:space:]]\/\/.*$/, "", code)
        if (code ~ /(^|[[:space:]])struct[[:space:]]+[A-Za-z_]/ && code ~ /\{/) {
            depth = 0; started = 0; count = 0
            for (j = i; j <= NR; j++) {
                b = lines[j]
                sub(/[[:space:]]\/\/.*$/, "", b)
                if (depth == 1 && b ~ /^[[:space:]]*((public|private|fileprivate|internal|open|static|final|lazy|override|weak|unowned)[[:space:]]+)*(var|let)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:/ && b !~ /\{/) {
                    count++
                }
                tmp = b; ob = gsub(/\{/, "{", tmp)
                tmp = b; cb = gsub(/\}/, "}", tmp)
                depth += ob - cb
                if (ob > 0) started = 1
                if (started && depth <= 0) break
            }
            if (count > 10) {
                printf "[WARNING] %s:%d: struct has %d stored properties; large value types are expensive to copy, consider splitting\n", fp, i, count
            }
        }
    }
}
' "$FILE_PATH")
report "$result"

# --- Check 4: unowned references -------------------------------------------
result=$(awk -v fp="$FILE_PATH" '
{
    code = $0
    if (code ~ /unowned[[:space:]]*\([[:space:]]*unsafe[[:space:]]*\)/) {
        printf "[ERROR] %s:%d: unowned(unsafe) reference causes a crash (EXC_BAD_ACCESS) if the object is deallocated first\n", fp, NR
    } else if (code ~ /(^|[^A-Za-z_])unowned([^A-Za-z_(]|$)/) {
        printf "[WARNING] %s:%d: unowned reference crashes if the object is deallocated first; prefer weak unless lifetime is guaranteed\n", fp, NR
    }
}
' "$FILE_PATH")
report "$result"

# --- Check 5: stored / returned closures capturing self strongly -----------
result=$(awk -v fp="$FILE_PATH" '
{ lines[NR] = $0 }
END {
    for (i = 1; i <= NR; i++) {
        code = lines[i]
        sub(/[[:space:]]\/\/.*$/, "", code)
        isAssign = ((code ~ /(self\.)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*\{/ && code !~ /==/) || code ~ /return[[:space:]]+\{/)
        if (isAssign && code !~ /\[[[:space:]]*(weak|unowned)/) {
            depth = 0; started = 0; hasself = 0; hasweak = 0
            for (j = i; j <= NR && j <= i + 60; j++) {
                b = lines[j]
                sub(/[[:space:]]\/\/.*$/, "", b)
                if (b ~ /\[[[:space:]]*(weak|unowned)[[:space:]]+self/) hasweak = 1
                if (b ~ /(^|[^A-Za-z0-9_])self([.?!]|[^A-Za-z0-9_]|$)/) hasself = 1
                tmp = b; ob = gsub(/\{/, "{", tmp)
                tmp = b; cb = gsub(/\}/, "}", tmp)
                depth += ob - cb
                if (ob > 0) started = 1
                if (started && depth <= 0) break
            }
            if (hasself && !hasweak) {
                printf "[WARNING] %s:%d: stored or returned closure captures self strongly; use [weak self] to avoid a retain cycle\n", fp, i
            }
        }
    }
}
' "$FILE_PATH")
report "$result"

exit "$ISSUES_FOUND"
