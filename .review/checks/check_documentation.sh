#!/bin/bash
# check_documentation.sh - Checks Swift documentation:
# - public functions without doc comments (/// or /** */)
# - functions with parameters but no - Parameter: docs
# - functions with return values but no - Returns: docs
# - TODO/FIXME/HACK markers reported as INFO
# Usage: check_documentation.sh FILE_PATH [FUNC_NAME]
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
function clean(s) {
  gsub(/"[^"]*"/, "", s)
  sub(/\/\/.*/, "", s)
  return s
}
function func_name(line,    s) {
  s = line
  sub(/.*func[ \t]+/, "", s)
  sub(/[({<[ \t:].*$/, "", s)
  gsub(/`/, "", s)
  return s
}
{ lines[NR] = $0 }
END {
  issues = 0

  for (i = 1; i <= NR; i++) {
    t = lines[i]
    gsub(/"[^"]*"/, "", t)
    if (t ~ /\/\/.*(TODO|FIXME|HACK)/ || t ~ /\/\*.*(TODO|FIXME|HACK)/ || t ~ /^[ \t]*\*.*(TODO|FIXME|HACK)/) {
      printf "[INFO] %s:%d: documentation marker TODO/FIXME/HACK found\n", f, i
      issues = 1
    }
  }

  for (i = 1; i <= NR; i++) {
    line = clean(lines[i])
    if (line !~ /(^|[^A-Za-z0-9_])func[ \t]+[A-Za-z_`]/) continue

    name = func_name(line)
    if (name == "" || (only != "" && name != only)) continue

    is_public = (line ~ /(^|[^A-Za-z0-9_])(public|open)([^A-Za-z0-9_]|$)/)
    current_doc = (lines[i] ~ /^[ \t]*\/\/\// || lines[i] ~ /\/\*\*/)
    doc = ""

    for (j = i - 1; j >= 1 && j >= i - 100; j--) {
      prev = lines[j]
      if (prev ~ /^[ \t]*$/) break
      pt = trim(prev)
      if (pt ~ /^\}/) break

      pc = clean(prev)
      if (pc ~ /(^|[^A-Za-z0-9_])(func|class|struct|enum|protocol|var|let|init|subscript)[ \t]/ && prev !~ /@/) break

      doc = prev "\n" doc
      if (prev ~ /\/\*\*/) break
    }

    has_doc = current_doc || (doc ~ /\/\/\// || doc ~ /\/\*\*/ || doc ~ /\*\//)
    if (is_public && !has_doc) {
      printf "[WARNING] %s:%d: public function '\''%s'\'' has no documentation comment\n", f, i, name
      issues = 1
    }

    sig = lines[i]
    for (j = i + 1; j <= NR && j <= i + 50; j++) {
      sig = sig "\n" lines[j]
      if (lines[j] ~ /\{/ || lines[j] ~ /;/ || lines[j] ~ /^[ \t]*$/) break
    }

    sigc = sig
    gsub(/"[^"]*"/, "", sigc)
    gsub(/\/\/[^\n]*/, "", sigc)

    pcount = 0
    closepos = 0
    if (match(sigc, /\(/)) {
      start = RSTART
      depth = 0
      has = 0
      commas = 0
      m = length(sigc)
      for (c = start; c <= m; c++) {
        ch = substr(sigc, c, 1)
        if (ch == "(") {
          depth++
          continue
        }
        if (ch == ")") {
          depth--
          if (depth == 0) {
            closepos = c
            break
          }
          continue
        }
        if (depth == 1) {
          if (ch != " " && ch != "\t" && ch != "\n" && ch != "\r") has = 1
          if (ch == ",") commas++
        }
      }
      if (has) pcount = commas + 1
    }

    has_return = 0
    if (closepos > 0) {
      tail = substr(sigc, closepos + 1)
      if (tail ~ /->/) {
        match(tail, /->/)
        ret = substr(tail, RSTART + 2)
        split(ret, rparts, "{")
        ret = trim(rparts[1])
        if (ret != "" && ret !~ /^Void([^A-Za-z0-9_]|$)/ && ret !~ /^\(\)/) has_return = 1
      }
    }

    if (pcount > 0) {
      doc_copy = doc
      param_docs = gsub(/-[ \t]*[Pp]arameter[ \t]+[A-Za-z_`]/, "", doc_copy)
      has_params_section = (doc ~ /-[ \t]*[Pp]arameters[ \t]*:/)
      if (!has_params_section && param_docs < pcount) {
        printf "[WARNING] %s:%d: function '\''%s'\'' has %d parameter(s) but missing - Parameter docs\n", f, i, name, pcount
        issues = 1
      }
    }

    if (has_return && doc !~ /-[ \t]*[Rr]eturns[ \t]*:/) {
      printf "[WARNING] %s:%d: function '\''%s'\'' has a return value but missing - Returns docs\n", f, i, name
      issues = 1
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
