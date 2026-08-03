#!/usr/bin/env bash
# HUD provider switcher (1.0.1) wiring contracts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
require_grep() {
  local file="$1"
  local pattern="$2"
  local msg="$3"
  if ! grep -qE "$pattern" "$file"; then
    echo "FAIL: $msg ($file)"
    fail=1
  fi
}

require_grep "Sources/NativeBolabolCore/Services/HUDProviderListComposer.swift" \
  "HUDProviderListComposer" "composer type exists"
require_grep "Sources/NativeBolabolCore/Services/HUDQuickSwitcherLayout.swift" \
  "rowIndex" "layout hit-testing exists"
require_grep "Sources/NativeBolabolCore/Services/ProviderQuickSwitcherModel.swift" \
  "applyScroll" "scroll model exists"
require_grep "Sources/NativeBolabol/Views/ContentView.swift" \
  "HUDProviderListComposer" "ContentView uses composer"
require_grep "Sources/NativeBolabol/Views/ProviderQuickSwitcher.swift" \
  "HUDQuickSwitcherLayout|QuickSwitcherLayout" "switcher uses layout"
require_grep "Sources/NativeBolabol/Views/ContentView.swift" \
  "handleOverlayProviderScroll|onScroll" "scroll handler wired"
require_grep "Sources/NativeBolabolCore/Services/AppText.swift" \
  "scroll" "help documents scroll (AppText)"

# Local.AI engine id consistency
if ! grep -q 'mlx-swift-local-model' Sources/NativeBolabolCore/Services/HUDProviderListComposer.swift; then
  echo "FAIL: Local.AI engine id missing from composer"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: HUD provider switcher contracts"
