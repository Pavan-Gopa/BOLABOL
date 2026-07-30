#!/bin/bash
# check_complexity.sh - Checks Swift function complexity:
# - functions longer than 50 lines = WARNING
# - functions longer than 100 lines = ERROR
# - more than 5 parameters = WARNING
# - more than 8 parameters = ERROR
# - nesting depth greater than 4 levels = WARNING (indentation based)
# Usage: check_complexity.sh FILE_PATH [FUNC_NAME]
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
function indent_width(line,    i, c, w, n) {
  w = 0
  n = length(line)
  for (i = 1; i <= n; i++) {
    c = substr(line, i, 1)
    if (c == " ") w++
    else if (c == "\t") w += 4
    else break
  }
  return w
}
function strip_noise(s) {
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
  n = NR
  for (i = 1; i <= n; i++) {
    line = strip_noise(lines[i])
    t = trim(line)
    if (t == "" || t ~ /^\/\*/ || t ~ /^\*/) continue
    if (line !~ /(^|[^A-Za-z0-9_])func[ \t]+[A-Za-z_`]/) continue
    name = func_name(line)
    if (name == "" || (only != "" && name != only)) continue

    brace = 0
    end = 0
    balance = 0
    for (j = i; j <= n; j++) {
      s = strip_noise(lines[j])
      tmp = s
      open = gsub(/{/, "{", tmp)
      tmp = s
      close = gsub(/}/, "}", tmp)
      if (brace == 0) {
        if (open > 0) {
          brace = j
          balance = open - close
          if (balance <= 0) {
            end = j
            break
          }
        }
      } else {
        balance += open - close
        if (balance <= 0) {
          end = j
          break
        }
      }
    }
    if (brace == 0) continue
    if (end == 0) end = n

    len = end - i + 1
    if (len > 100) {
      printf "[ERROR] %s:%d: function '\''%s'\'' is %d lines long (threshold 100)\n", f, i, name, len
      issues = 1
    } else if (len > 50) {
      printf "[WARNING] %s:%d: function '\''%s'\'' is %d lines long (threshold 50)\n", f, i, name, len
      issues = 1
    }

    sig = ""
    for (j = i; j <= brace; j++) sig = sig strip_noise(lines[j]) "\n"
    pcount = 0
    if (match(sig, /\(/)) {
      depth = 0
      has = 0
      commas = 0
      m = length(sig)
      for (c = RSTART; c <= m; c++) {
        ch = substr(sig, c, 1)
        if (ch == "(") {
          depth++
          continue
        }
        if (ch == ")") {
          depth--
          if (depth == 0) break
          continue
        }
        if (depth == 1) {
          if (ch != " " && ch != "\t" && ch != "\n" && ch != "\r") has = 1
          if (ch == ",") commas++
        }
      }
      if (has) pcount = commas + 1
    }

    if (pcount > 8) {
      printf "[ERROR] %s:%d: function '\''%s'\'' has %d parameters (threshold 8)\n", f, i, name, pcount
      issues = 1
    } else if (pcount > 5) {
      printf "[WARNING] %s:%d: function '\''%s'\'' has %d parameters (threshold 5)\n", f, i, name, pcount
      issues = 1
    }

    base = indent_width(lines[i])
    badline = 0
    baddepth = 0
    for (j = brace + 1; j < end; j++) {
      s = lines[j]
      if (s ~ /^[ \t]*$/) continue
      t = trim(strip_noise(s))
      if (t == "" || t ~ /^\/\// || t ~ /^\/\*/ || t ~ /^\*/) continue
      w = indent_width(s)
      rel = w - base
      if (rel < 0) rel = 0
      depth = int(rel / 4)
      if (depth > 4 && badline == 0) {
        badline = j
        baddepth = depth
      }
    }
    if (badline > 0) {
      printf "[WARNING] %s:%d: function '\''%s'\'' exceeds nesting depth 4 (approx level %d)\n", f, badline, name, baddepth
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
