#!/usr/bin/env bash
# A3 security: no hardcoded API keys/tokens in SettingsView A3 surface (§14.7).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

if grep -Eq 'sk-[A-Za-z0-9]{10,}|AIza[0-9A-Za-z_-]{20,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-' "$FILE"; then
  echo "FAIL: possible hardcoded secret literal in SettingsView"
  exit 1
fi
echo "PASS: no hardcoded API key literals in SettingsView."
