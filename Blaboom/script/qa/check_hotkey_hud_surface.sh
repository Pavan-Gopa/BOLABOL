#!/usr/bin/env bash
# Hotkey + floating HUD product surface.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
require() {
  if [ ! -f "$1" ]; then
    echo "FAIL: missing $1"
    fail=1
  fi
}

require Sources/NativeBlaboom/Services/GlobalHotkeyManager.swift
require Sources/NativeBlaboom/Services/HotkeySessionOverlayManager.swift
require Sources/NativeBlaboom/Services/HotkeyOutputDispatcher.swift
require Sources/NativeBlaboomCore/Services/HotkeySessionCoordinator.swift
require Sources/NativeBlaboomCore/Services/HotkeyOutputTextResolver.swift
require Sources/NativeBlaboomCore/Models/HotkeySettings.swift
require Sources/NativeBlaboom/Views/Settings/HotkeySettingsView.swift

# Default chords
if ! grep -q 'Option+S' Sources/NativeBlaboomCore/Models/HotkeySettings.swift; then
  echo "FAIL: default primary hotkey Option+S missing"
  fail=1
fi

# HUD targets R/1/2
if ! grep -q 'hudLabel' Sources/NativeBlaboomCore/Models/HotkeySettings.swift; then
  echo "FAIL: HotkeyTarget.hudLabel missing"
  fail=1
fi

# Spectrum for classic HUD
if ! grep -q 'classicListeningValues' Sources/NativeBlaboomCore/Services/HUDSpectrumResponse.swift; then
  echo "FAIL: HUD spectrum response missing"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: hotkey + HUD surface"
