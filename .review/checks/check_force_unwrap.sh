#!/bin/bash
# check_force_unwrap.sh - Checks dangerous Swift patterns:
# - force try (try!)
# - force cast (as!)
# - force unwrap (identifier! or )! or ]!)
# - implicitly unwrapped optionals (var x: Type!) outside @IBOutlet
# Usage: check_force_unwrap.sh FILE_PATH [FUNC_NAME]
# Output: [SEVERITY] file:line: message
# Exit 0 if no issues, exit 1 if issues found.
set -u

FILE_PATH="${1:-}"
FUNC_NAME="${2:-}"

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

ISSUES=0

# Strip comments and strings, then search for patterns
# Use grep -n for line numbers, filter out comment-only lines

# 1. force try: try!
while IFS=: read -r lineno content; do
  # Skip if inside a comment
  stripped=$(echo "$content" | sed 's|//.*||')
  if echo "$stripped" | grep -q 'try!'; then
    echo "[ERROR] ${FILE_PATH}:${lineno}: force try (try!) is unsafe; use do/catch or try? instead"
    ISSUES=1
  fi
done < <(grep -n 'try!' "$FILE_PATH" 2>/dev/null)

# 2. force cast: as!
while IFS=: read -r lineno content; do
  stripped=$(echo "$content" | sed 's|//.*||')
  if echo "$stripped" | grep -q 'as!'; then
    echo "[ERROR] ${FILE_PATH}:${lineno}: force cast (as!) is unsafe; use conditional cast (as?) instead"
    ISSUES=1
  fi
done < <(grep -n 'as!' "$FILE_PATH" 2>/dev/null)

# 3. force unwrap: word)! or word]! or identifier! (not !=, not !==)
# Match: alphanumeric/underscore/) ] followed by ! NOT followed by =
while IFS=: read -r lineno content; do
  stripped=$(echo "$content" | sed 's|//.*||' | sed 's|"[^"]*"||g')
  # Skip lines that are just boolean negation: guard !x, if !x, while !x
  if echo "$stripped" | grep -qE '(guard|if|while|return|let|var|case)[[:space:]]+!'; then
    # This is boolean negation, skip unless there's also a real force unwrap
    cleaned=$(echo "$stripped" | sed -E 's/(guard|if|while|return|let|var|case)[[:space:]]+!//g')
    if echo "$cleaned" | grep -qE '[A-Za-z0-9_)\]][[:space:]]*![^=]'; then
      echo "[ERROR] ${FILE_PATH}:${lineno}: force unwrap (!) is unsafe; use if-let, guard-let, or nil-coalescing instead"
      ISSUES=1
    fi
  elif echo "$stripped" | grep -qE '[A-Za-z0-9_)\]][[:space:]]*![^=]'; then
    # Exclude != !== and logical not patterns
    # Remove known safe patterns: !=, !==, !condition after keywords
    cleaned=$(echo "$stripped" | sed -E 's/!=[=]?//g')
    if echo "$cleaned" | grep -qE '[A-Za-z0-9_)\]][[:space:]]*![[:space:]]*[^=[:space:]]'; then
      echo "[ERROR] ${FILE_PATH}:${lineno}: force unwrap (!) is unsafe; use if-let, guard-let, or nil-coalescing instead"
      ISSUES=1
    fi
  fi
done < <(grep -nE '[A-Za-z0-9_)\]][[:space:]]*!' "$FILE_PATH" 2>/dev/null | grep -v '!=' | grep -v '@IBOutlet')

# 4. Implicitly unwrapped optionals: var/let x: Type! (not @IBOutlet)
while IFS=: read -r lineno content; do
  # Check previous line for @IBOutlet
  prev=$((lineno - 1))
  prev_line=$(sed -n "${prev}p" "$FILE_PATH")
  if echo "$prev_line" | grep -q '@IBOutlet'; then
    continue
  fi
  if echo "$content" | grep -q '@IBOutlet'; then
    continue
  fi
  echo "[WARNING] ${FILE_PATH}:${lineno}: implicitly unwrapped optional should be avoided outside @IBOutlet contexts"
  ISSUES=1
done < <(grep -nE '(let|var)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*[A-Za-z_][A-Za-z0-9_<>,.[:space:]]*!' "$FILE_PATH" 2>/dev/null | grep -v '@IBOutlet' | grep -v '!=')

exit $ISSUES
