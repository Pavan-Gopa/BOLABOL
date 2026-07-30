#!/bin/bash
# check_error_handling.sh - Checks Swift error handling:
# - catch blocks that are empty or only contain comments
# - try? without apparent handling of the nil case
# - fatalError/preconditionFailure in non-test code
# - async functions using throwing try without do/catch or throws
# - catch let error where error is unused
# Usage: check_error_handling.sh FILE_PATH [FUNC_NAME]
# Output: [SEVERITY] file:line: message
# Exit 0 if no issues, exit 1 if issues found.
set -u

FILE_PATH="${1:-}"
FUNC_NAME="${2:-}"

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

awk -v f="$FILE_PATH" -v only="$FUNC_NAME" -v filepath="$FILE_PATH" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function clean(s) {
  gsub(/"[^"]*"/, "", s)
  sub(/\/\/.*/, "", s)
  return s
}
function is_blank_or_comment(s,    t) {
  t = trim(s)
  if (t == "") return 1
  if (t ~ /^\/\//) return 1
  if (t ~ /^\/\*/) return 1
  if (t ~ /^\*/) return 1
  if (t ~ /^\*\//) return 1
  if (t ~ /^\/\*.*\*\/$/) return 1
  return 0
}
function func_name(line,    s) {
  s = line
  sub(/.*func[ \t]+/, "", s)
  sub(/[({<[ \t:].*$/, "", s)
  gsub(/`/, "", s)
  return s
}
function find_brace_range(start,    j, s, tmp, open, close, balance) {
  found_brace = 0
  found_end = 0
  balance = 0
  for (j = start; j <= n; j++) {
    s = clean(lines[j])
    tmp = s
    open = gsub(/{/, "{", tmp)
    tmp = s
    close = gsub(/}/, "}", tmp)
    if (found_brace == 0) {
      if (open > 0) {
        found_brace = j
        balance = open - close
        if (balance <= 0) {
          found_end = j
          break
        }
      }
    } else {
      balance += open - close
      if (balance <= 0) {
        found_end = j
        break
      }
    }
  }
  if (found_brace != 0 && found_end == 0) found_end = n
}
{ lines[NR] = $0 }
END {
  issues = 0
  n = NR

  for (i = 1; i <= n; i++) {
    c = clean(lines[i])
    if (is_blank_or_comment(c)) continue

    if (c ~ /(^|[^A-Za-z0-9_])try[ \t]*\?/) {
      if (c !~ /(if|guard)[ \t]+(let|var|case)/ && c !~ /\?\?/ && c !~ /==[ \t]*nil/ && c !~ /!=[ \t]*nil/) {
        printf "[WARNING] %s:%d: try? produces optional without explicit nil handling here\n", f, i
        issues = 1
      }
    }

    if (filepath !~ /Tests?/ && c ~ /(^|[^A-Za-z0-9_])(fatalError|preconditionFailure)[ \t]*\(/) {
      printf "[WARNING] %s:%d: fatalError/preconditionFailure should be avoided in non-test code\n", f, i
      issues = 1
    }
  }

  for (i = 1; i <= n; i++) {
    line = clean(lines[i])
    if (line ~ /(^|[^A-Za-z0-9_])catch([ \t]*\{|[ \t]+[A-Za-z_])/) {
      find_brace_range(i)
      if (found_brace == 0) continue

      varname = ""
      if (match(line, /catch[ \t]+(let|var)[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        varname = substr(line, RSTART, RLENGTH)
        sub(/.*[ \t]/, "", varname)
      }

      has_stmt = 0
      uses_var = 0
      for (j = found_brace; j <= found_end; j++) {
        body = clean(lines[j])
        if (j == found_brace) sub(/^[^{]*\{/, "", body)
        if (j == found_end) sub(/\}.*$/, "", body)

        if (!is_blank_or_comment(body)) {
          has_stmt = 1
          if (varname != "") {
            re = "(^|[^A-Za-z0-9_])" varname "([^A-Za-z0-9_]|$)"
            if (body ~ re) uses_var = 1
          }
        }
      }

      if (!has_stmt) {
        printf "[WARNING] %s:%d: catch block is empty or contains only comments\n", f, i
        issues = 1
      } else if (varname != "" && !uses_var) {
        printf "[WARNING] %s:%d: caught error '\''%s'\'' is never used\n", f, i, varname
        issues = 1
      }
    }
  }

  for (i = 1; i <= n; i++) {
    line = clean(lines[i])
    if (line ~ /(^|[^A-Za-z0-9_])func[ \t]+[A-Za-z_`]/ && line ~ /(^|[^A-Za-z0-9_])async([^A-Za-z0-9_]|$)/ && line !~ /(^|[^A-Za-z0-9_])(throws|rethrows)([^A-Za-z0-9_]|$)/) {
      name = func_name(line)
      if (only != "" && name != only) continue

      find_brace_range(i)
      if (found_brace == 0) continue

      has_try = 0
      has_do = 0
      has_catch = 0
      for (j = found_brace; j <= found_end; j++) {
        s = clean(lines[j])
        if (j == found_brace) sub(/^[^{]*\{/, "", s)
        if (j == found_end) sub(/\}.*$/, "", s)
        if (is_blank_or_comment(s)) continue

        tmp = s
        gsub(/(^|[^A-Za-z0-9_])try[ \t]*[!?]/, "", tmp)
        if (tmp ~ /(^|[^A-Za-z0-9_])try([ \t]+[A-Za-z_]|$)/) has_try = 1
        if (s ~ /(^|[^A-Za-z0-9_])do([ \t]*\{|[ \t]|$)/) has_do = 1
        if (s ~ /(^|[^A-Za-z0-9_])catch([ \t]*\{|[ \t]|$)/) has_catch = 1
      }

      if (has_try && (!has_do || !has_catch)) {
        printf "[WARNING] %s:%d: async function '\''%s'\'' calls throwing try without do/catch or throws\n", f, i, name
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
