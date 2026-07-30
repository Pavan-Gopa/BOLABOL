#!/bin/bash
#
# check_access_control.sh
# ---------------------------------------------------------------------------
# Swift access-control review checker.
#
# Checks performed:
#   1. Public types whose members have no explicit access modifier
#      (such members default to internal and may need to be public).   [WARNING]
#   2. private members in files that also declare extensions
#      (verify accessibility; fileprivate may be required).            [INFO]
#   3. open classes that expose no open override points.               [WARNING]
#
# Usage:  ./check_access_control.sh <path/to/File.swift>
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

# --- Check 1: public type members missing explicit access modifiers --------
result=$(awk -v fp="$FILE_PATH" '
function ltrim(s) { sub(/^[[:space:]]+/, "", s); return s }
BEGIN { depth = 0; inpub = 0; pdepth = 0 }
{
    code = $0
    sub(/[[:space:]]\/\/.*$/, "", code)

    if (code ~ /(^|[[:space:]])public[[:space:]]+(final[[:space:]]+)?(class|struct|enum|actor|protocol)[[:space:]]/) {
        inpub = 1
        pdepth = depth
    }

    if (inpub && depth == pdepth + 1) {
        t = ltrim(code)
        isMember = (t ~ /^(func|var|let|init|subscript)[[:space:](?!]/) || (t ~ /^(static|final|lazy|override|class|mutating|convenience|required|indirect)[[:space:]]+(func|var|let|init|subscript)/)
        hasAccess = (code ~ /(^|[[:space:]])(public|private|fileprivate|internal|open)[[:space:]]/)
        if (isMember && !hasAccess) {
            printf "[WARNING] %s:%d: member of a public type has no explicit access modifier (defaults to internal); mark public if it is API\n", fp, NR
        }
    }

    tmp = code; ob = gsub(/\{/, "{", tmp)
    tmp = code; cb = gsub(/\}/, "}", tmp)
    depth += ob - cb
    if (inpub && depth <= pdepth) inpub = 0
}
' "$FILE_PATH")
report "$result"

# --- Check 2: private members in files that contain extensions -------------
if grep -Eq '(^|[[:space:]])extension[[:space:]]+[A-Za-z_]' "$FILE_PATH"; then
    result=$(awk -v fp="$FILE_PATH" '
    {
        code = $0
        if (code ~ /(^|[[:space:]])private[[:space:]]+(func|var|let|init|subscript|class|struct|enum)/ && code !~ /fileprivate/) {
            printf "[INFO] %s:%d: private member in a file that contains extensions; confirm it is not needed from an extension (consider fileprivate)\n", fp, NR
        }
    }
    ' "$FILE_PATH")
    report "$result"
fi

# --- Check 3: open classes without open override points --------------------
open_classes=$(grep -Ec '(^|[[:space:]])open[[:space:]]+class[[:space:]]' "$FILE_PATH")
open_members=$(grep -Ec '(^|[[:space:]])open[[:space:]]+((override|class|final)[[:space:]]+)*(func|var|init|subscript)' "$FILE_PATH")
if [ "$open_classes" -gt 0 ] && [ "$open_members" -eq 0 ]; then
    result=$(awk -v fp="$FILE_PATH" '
    {
        if ($0 ~ /(^|[[:space:]])open[[:space:]]+class[[:space:]]/) {
            printf "[WARNING] %s:%d: open class exposes no open override points (open func/var/init); subclasses cannot override any member\n", fp, NR
        }
    }
    ' "$FILE_PATH")
    report "$result"
fi

exit "$ISSUES_FOUND"
