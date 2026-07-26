#!/usr/bin/env bash
# A3: ProviderCardView may live in SettingsView.swift (file-private) OR separate file.
# Both OK per Verifier; at least one must define the card.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

in_settings=0
in_own=0
grep -q 'struct ProviderCardView' Sources/VaniScript/Views/SettingsView.swift && in_settings=1
if [[ -f Sources/VaniScript/Views/ProviderCardView.swift ]]; then
  grep -q 'struct ProviderCardView' Sources/VaniScript/Views/ProviderCardView.swift && in_own=1
fi
if [[ $in_settings -eq 0 && $in_own -eq 0 ]]; then
  echo "FAIL: ProviderCardView not defined in SettingsView.swift or ProviderCardView.swift"
  exit 1
fi
echo "PASS: ProviderCardView present (in_settings=$in_settings, own_file=$in_own)."
