#!/bin/bash
# check_naming.sh - Checks Swift naming conventions:
# - functions should be camelCase (not snake_case, not PascalCase)
# - types should be PascalCase
# - constants should not use ALL_CAPS
# - Boolean variables/functions should use is/has/should/can prefix
# Usage: check_naming.sh FILE_PATH [FUNC_NAME]
# Output: [SEVERITY] file:line: message
# Exit 0 if no issues, exit 1 if issues found.
set -u

FILE_PATH="${1:-}"
FUNC_NAME="${2:-}"

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

awk -v f="$FILE_PATH" -v only="$FUNC_NAME" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function extract_func_name(line,    s) {
  s = line
  sub(/.*func[ \t]+/, "", s)
  sub(/[({<[ \t:].*$/, "", s)
  gsub(/`/, "", s)
  return s
}
function extract_type_name(line,    s) {
  s = line
  sub(/.*(class|struct|enum|protocol|typealias|actor)[ \t]+/, "", s)
  sub(/[({<[ \t:].*$/, "", s)
  gsub(/`/, "", s)
  return s
}
function has_bool_prefix(name) {
  return (name ~ /^(is|has|should|can)[A-Z0-9_]/ || name ~ /^(is|has|should|can)$/)
}
{ lines[NR] = $0 }
END {
  issues = 0
  for (i = 1; i <= NR; i++) {
    raw = lines[i]
    line = raw
    gsub(/"[^"]*"/, "", line)
    sub(/\/\/.*/, "", line)
    t = trim(line)
    if (t == "" || t ~ /^\/\*/ || t ~ /^\*/) continue

    if (line ~ /(^|[^A-Za-z0-9_])func[ \t]+[A-Za-z_`]/) {
      name = extract_func_name(line)
      if (name != "" && (only == "" || name == only)) {
        if (name ~ /_/) {
          printf "[WARNING] %s:%d: function name '\''%s'\'' should be camelCase, not snake_case\n", f, i, name
          issues = 1
        } else if (name ~ /^[A-Z]/) {
          printf "[WARNING] %s:%d: function name '\''%s'\'' should be camelCase, not PascalCase\n", f, i, name
          issues = 1
        }
        if (line ~ /->[ \t]*Bool([^A-Za-z0-9_]|$)/ && !has_bool_prefix(name)) {
          printf "[WARNING] %s:%d: Boolean function '\''%s'\'' should start with is/has/should/can\n", f, i, name
          issues = 1
        }
      }
    }

    if (line !~ /func[ \t]/ && line ~ /(^|[^A-Za-z0-9_])(class|struct|enum|protocol|typealias|actor)[ \t]+[A-Za-z_`]/) {
      name = extract_type_name(line)
      if (name != "") {
        if (name ~ /_/) {
          printf "[WARNING] %s:%d: type name '\''%s'\'' should be PascalCase, not snake_case\n", f, i, name
          issues = 1
        } else if (name ~ /^[a-z]/) {
          printf "[WARNING] %s:%d: type name '\''%s'\'' should be PascalCase\n", f, i, name
          issues = 1
        }
      }
    }

    if (line ~ /(^|[^A-Za-z0-9_])(let|var)[ \t]+/ && match(line, /(^|[^A-Za-z0-9_])(let|var)[ \t]+/)) {
      s = substr(line, RSTART + RLENGTH)
      n = split(s, parts, ",")
      for (p = 1; p <= n; p++) {
        part = parts[p]
        sub(/[:=].*$/, "", part)
        name = trim(part)
        sub(/[ \t]+.*$/, "", name)
        gsub(/`/, "", name)
        if (name ~ /^[A-Z][A-Z0-9_]*$/ && length(name) > 1) {
          printf "[WARNING] %s:%d: constant '\''%s'\'' should not use ALL_CAPS\n", f, i, name
          issues = 1
        }
      }
    }

    if (line ~ /(^|[^A-Za-z0-9_])(let|var)[ \t]+[A-Za-z_`][A-Za-z0-9_`]*[ \t]*:[ \t]*Bool([^A-Za-z0-9_]|$)/) {
      name = line
      sub(/.*(^|[^A-Za-z0-9_])(let|var)[ \t]+/, "", name)
      sub(/[ \t]*:.*$/, "", name)
      name = trim(name)
      gsub(/`/, "", name)
      if (name != "" && !has_bool_prefix(name)) {
        printf "[WARNING] %s:%d: Boolean variable '\''%s'\'' should start with is/has/should/can\n", f, i, name
        issues = 1
      }
    }
  }
  exit issues
}
' "$FILE_PATH" 2>/dev/null

status=$?
if [ "$status" -eq 0 ]; then
  exit 0
fi
exit 1
