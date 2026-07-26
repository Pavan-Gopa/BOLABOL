#!/usr/bin/env bash
set -euo pipefail

FILE="Sources/VaniScriptCore/CloudProviderCatalog.swift"
if grep -q "URLSession\|URLRequest\|\.fetch" "$FILE"; then
  echo "FAIL: CloudProviderCatalog contains network calls, it should only be data."
  exit 1
fi
echo "PASS: CloudProviderCatalog is pure data."
