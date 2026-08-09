#!/usr/bin/env bash
# CPS sources must not embed live API keys.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
paths=(
  Sources/VaniScriptCore/CloudProviderCatalog.swift
  Sources/VaniScriptCore/CloudModelCatalog.swift
  Sources/VaniScriptCore/CloudKeyValidator.swift
  Sources/VaniScriptCore/CloudBalanceService.swift
  Sources/VaniScriptCore/ProviderRegistry.swift
  Sources/VaniScriptCore/UsageRecorder.swift
  Sources/VaniScript/Views/UsageStatisticsView.swift
  Sources/VaniScript/Views/SettingsView.swift
)
for f in "${paths[@]}"; do
  [[ -f "$f" ]] || continue
  if grep -EEq 'sk-[a-zA-Z0-9]{20,}|AIza[0-9A-Za-z_-]{20,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]+' "$f"; then
    echo "FAIL: possible live key material in $f"; exit 1
  fi
done
echo "PASS: no live API key material in CPS-related product sources."
