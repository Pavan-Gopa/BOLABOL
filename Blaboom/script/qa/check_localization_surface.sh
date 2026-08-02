#!/usr/bin/env bash
# Localization: AppText keys + UI languages must stay large.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

APPTEXT="Sources/NativeBlaboomCore/Services/AppText.swift"
GENERAL="Sources/NativeBlaboomCore/Models/GeneralSettings.swift"

key_count=$(grep -cE '^\s+case [a-zA-Z]' "$APPTEXT" || true)
if [ "${key_count:-0}" -lt 400 ]; then
  echo "FAIL: AppTextKey count too low ($key_count < 400)"
  exit 1
fi

# Required UI languages
for lang in english russian spanish german french italian portuguese chinese japanese korean arabic hindi ukrainian turkish polish; do
  if ! grep -q "case $lang" "$GENERAL"; then
    echo "FAIL: UILanguagePreference missing $lang"
    exit 1
  fi
done

# Onboarding + help key families
for prefix in onboarding help; do
  count=$(grep -cE "case ${prefix}" "$APPTEXT" || true)
  if [ "${count:-0}" -lt 10 ]; then
    echo "FAIL: too few ${prefix}* keys ($count)"
    exit 1
  fi
done

echo "OK: localization surface ($key_count AppText keys)"
