#!/bin/bash
# check_force_unwrap.sh - Checks dangerous Swift patterns:
# - force unwrap (!) on optionals
# - force try (try!)
# - force cast (as!)
# - implicitly unwrapped optionals in non-IBOutlet contexts
# Usage: check_force_unwrap.sh FILE_PATH [FUNC_NAME]
# Output: [SEVERITY] file:line: message
# Exit 0 if no issues, exit 1 if issues found.
set -u

FILE_PATH="${1:-}"
FUNC_NAME="${2:-}"

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

awk -v f="$FILE_PATH" '
function clean(s) {
  gsub(/"[^"]*"/, "", s)
  sub(/\/\/.*/, "", s)
  return s
}
function count_regex(s, re,    cnt) {
  cnt = 0
  while (match(s, re)) {
    cnt++
    s = substr(s, RSTART + RLENGTH)
  }
  return cnt
}
BEGIN {
  issues = 0
  incomment = 0
  prev_raw = ""
}
{
  raw = $0
  line = raw
  gsub(/"[^"]*"/, "", line)

  if (incomment) {
    if (line ~ /\*\//) {
      sub(/.*\*\//, "", line)
      incomment = 0
    } else {
      prev_raw = raw
      next
    }
  }

  while (line ~ /\/\*[^*]*\*\//) {
    sub(/\/\*[^*]*\*\//, "", line)
  }
  if (line ~ /\/\*/) {
    sub(/\/\*.*$/, "", line)
    incomment = 1
  }

  line = clean(line)
  if (line ~ /^[ \t]*$/) {
    prev_raw = raw
    next
  }

  try_count = count_regex(line, /(^|[^A-Za-z0-9_])try[ \t]*!/)
  for (k = 0; k < try_count; k++) {
    printf "[ERROR] %s:%d: force try (try!) is unsafe; use do/catch or try? instead\n", f, NR
    issues = 1
  }

  cast_count = count_regex(line, /(^|[^A-Za-z0-9_])as[ \t]*!/)
  for (k = 0; k < cast_count; k++) {
    printf "[ERROR] %s:%d: force cast (as!) is unsafe; use conditional cast (as?) instead\n", f, NR
    issues = 1
  }

  is_iuo_decl = 0
  if (raw !~ /@IBOutlet/ && prev_raw !~ /@IBOutlet/ && line ~ /(^|[^A-Za-z0-9_])(let|var)[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*:[ \t]*[^=]*!([^=]|$)/) {
    is_iuo_decl = 1
    printf "[WARNING] %s:%d: implicitly unwrapped optional should be avoided outside @IBOutlet contexts\n", f, NR
    issues = 1
  }

  tmp = line
  gsub(/(^|[^A-Za-z0-9_])try[ \t]*!/, "", tmp)
  gsub(/(^|[^A-Za-z0-9_])as[ \t]*!/, "", tmp)
  if (is_iuo_decl) {
    sub(/:[ \t]*[^=]*!([^=]|$)/, "", tmp)
  }

  u = tmp
  unwrap_count = 0
  while (match(u, /[A-Za-z0-9_)\]]!([^=]|$)/)) {
    start = RSTART
    len = RLENGTH
    keyword = 0

    if (start >= 3 && substr(u, start - 2, 3) == "try") {
      pre = start - 3
      if (pre == 0 || substr(u, pre, 1) !~ /[A-Za-z0-9_]/) keyword = 1
    }
    if (!keyword && start >= 2 && substr(u, start - 1, 2) == "as") {
      pre = start - 2
      if (pre == 0 || substr(u, pre, 1) !~ /[A-Za-z0-9_]/) keyword = 1
    }

    if (!keyword) unwrap_count++
    u = substr(u, start + len)
  }

  for (k = 0; k < unwrap_count; k++) {
    printf "[ERROR] %s:%d: force unwrap (!) is unsafe; use if-let, guard-let, or nil-coalescing instead\n", f, NR
    issues = 1
  }

  prev_raw = raw
}
END {
  exit issues
}
' "$FILE_PATH" 2>/dev/null

status=$?
if [ "$status" -eq 0 ]; then
  exit 0
fi
exit 1
