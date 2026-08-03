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

require Sources/NativeBolabol/Services/GlobalHotkeyManager.swift
require Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift
require Sources/NativeBolabol/Services/HotkeyOutputDispatcher.swift
require Sources/NativeBolabolCore/Services/HotkeySessionCoordinator.swift
require Sources/NativeBolabolCore/Services/HotkeyOutputTextResolver.swift
require Sources/NativeBolabolCore/Models/HotkeySettings.swift
require Sources/NativeBolabol/Views/Settings/HotkeySettingsView.swift

# Default chords
if ! grep -q 'Option+S' Sources/NativeBolabolCore/Models/HotkeySettings.swift; then
  echo "FAIL: default primary hotkey Option+S missing"
  fail=1
fi

# HUD targets R/1/2
if ! grep -q 'hudLabel' Sources/NativeBolabolCore/Models/HotkeySettings.swift; then
  echo "FAIL: HotkeyTarget.hudLabel missing"
  fail=1
fi

# Spectrum for classic HUD
if ! grep -q 'classicListeningValues' Sources/NativeBolabolCore/Services/HUDSpectrumResponse.swift; then
  echo "FAIL: HUD spectrum response missing"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: hotkey + HUD surface"
