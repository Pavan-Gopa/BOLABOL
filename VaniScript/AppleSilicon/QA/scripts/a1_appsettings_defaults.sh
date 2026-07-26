#!/usr/bin/env bash
set -euo pipefail

FILE="Sources/VaniScriptCore/AppSettings.swift"
if ! grep -q 'geminiTextModel: String = "gemini-2.5-flash"' "$FILE"; then
  echo "FAIL: geminiTextModel default is wrong."
  exit 1
fi
if ! grep -q 'openaiTextModel: String = "gpt-4o-mini"' "$FILE"; then
  echo "FAIL: openaiTextModel default is wrong."
  exit 1
fi
echo "PASS: AppSettings model defaults are correct."
