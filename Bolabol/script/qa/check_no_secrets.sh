#!/usr/bin/env bash
# Fail if likely API keys / secrets appear in tracked source (not UserData).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Patterns that should never be committed in Sources/Tests/script.
PATTERNS=(
  'sk-[a-zA-Z0-9]{20,}'
  'sk-or-[a-zA-Z0-9]{20,}'
  'AIza[0-9A-Za-z_-]{30,}'
  'xai-[a-zA-Z0-9]{20,}'
  '-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----'
)

FOUND=0
for pat in "${PATTERNS[@]}"; do
  # shellcheck disable=SC2086
  if grep -RInE --include='*.swift' --include='*.sh' --include='*.md' --include='*.plist' \
      --exclude-dir='.build' --exclude-dir='dist' --exclude-dir='UserData' \
      --exclude-dir='graphify-out' --exclude-dir='__pycache__' \
      -e "$pat" Sources Tests script Package.swift 2>/dev/null | grep -v 'example\|placeholder\|test-key\|sk-test\|sk-legacy\|sk-sp-test\|sk-qwen\|"sk-' >/dev/null; then
    # Re-print for diagnosis (allow common test fixtures).
    hits=$(grep -RInE --include='*.swift' --include='*.sh' \
      --exclude-dir='.build' --exclude-dir='dist' \
      -e "$pat" Sources Tests script 2>/dev/null | grep -vE 'sk-test|sk-legacy|sk-sp-test|sk-qwen|sk-or"|apiKey.*=.*"g"|fixture|placeholder|example' || true)
    if [ -n "$hits" ]; then
      echo "Possible secret pattern matched: $pat"
      echo "$hits" | head -20
      FOUND=1
    fi
  fi
done

if [ "$FOUND" -ne 0 ]; then
  echo "FAIL: possible secrets in source"
  exit 1
fi
echo "OK: no secret-like strings in Sources/Tests/script"
