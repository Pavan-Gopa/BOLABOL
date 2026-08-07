#!/usr/bin/env bash
# HUD humor/prompt production wiring guard. Unit tests cover pure behavior; this
# check keeps the three user entry points and the listening snapshot wired.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

validate_contract() {
  local root="$1"
  local content="$root/Sources/NativeBolabol/Views/ContentView.swift"
  local sidebar="$root/Sources/NativeBolabol/Views/SidebarView.swift"
  local playback="$root/Sources/NativeBolabol/Views/AudioPlaybackModalView.swift"
  local overlay="$root/Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift"
  local failed=0

  for file in "$content" "$sidebar" "$playback" "$overlay"; do
    if [ ! -f "$file" ]; then
      echo "FAIL: missing HUD humor/prompt contract file: $file"
      failed=1
    fi
  done
  [ "$failed" -eq 0 ] || return 1

  for file in "$content" "$sidebar" "$playback"; do
    if ! grep -qF 'PolishingWorkflow.make(' "$file"; then
      echo "FAIL: user polish entry point bypasses PolishingWorkflow.make: $file"
      failed=1
    fi
  done

  local level_observer
  level_observer="$(grep -F -A8 '.onChange(of: hotkeySettingsStore.settings.humorLevel)' "$content" || true)"
  if ! grep -qF 'updatePendingHotkeyHumorSession(level: level)' <<<"$level_observer"; then
    echo "FAIL: Settings humor-level changes during listening do not update the pending snapshot"
    failed=1
  fi

  for marker in \
    '.allowsHitTesting(HUDInteractionPolicy.allowsHitTesting' \
    '.accessibilityHidden(HUDInteractionPolicy.isAccessibilityHidden' \
    '.accessibilityAdjustableAction' \
    'state.promptSlotChangeHandler?(slot)'; do
    if ! grep -qF "$marker" "$overlay"; then
      echo "FAIL: HUD prompt/humor interaction contract is missing: $marker"
      failed=1
    fi
  done

  [ "$failed" -eq 0 ]
}

self_test() {
  local fixture
  fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-hud-contract.XXXXXX")"
  trap 'rm -rf "$fixture"' RETURN
  mkdir -p \
    "$fixture/Sources/NativeBolabol/Views" \
    "$fixture/Sources/NativeBolabol/Services"

  for file in ContentView.swift SidebarView.swift AudioPlaybackModalView.swift; do
    printf '%s\n' 'PolishingWorkflow.make(' > "$fixture/Sources/NativeBolabol/Views/$file"
  done
  cat >> "$fixture/Sources/NativeBolabol/Views/ContentView.swift" <<'EOF'
.onChange(of: hotkeySettingsStore.settings.humorLevel) { _, level in
  if audioRecorder.isRecording {
    updatePendingHotkeyHumorSession(level: level)
  }
}
EOF
  cat > "$fixture/Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift" <<'EOF'
.allowsHitTesting(HUDInteractionPolicy.allowsHitTesting
.accessibilityHidden(HUDInteractionPolicy.isAccessibilityHidden
.accessibilityAdjustableAction
state.promptSlotChangeHandler?(slot)
EOF

  validate_contract "$fixture" >/dev/null || {
    echo "FAIL: valid HUD contract fixture was rejected"
    return 1
  }

  printf '%s\n' '// missing factory' > "$fixture/Sources/NativeBolabol/Views/SidebarView.swift"
  if validate_contract "$fixture" >/dev/null; then
    echo "FAIL: negative self-test accepted a missing production factory"
    return 1
  fi
  printf '%s\n' 'PolishingWorkflow.make(' > "$fixture/Sources/NativeBolabol/Views/SidebarView.swift"

  grep -vF 'updatePendingHotkeyHumorSession(level: level)' \
    "$fixture/Sources/NativeBolabol/Views/ContentView.swift" \
    > "$fixture/ContentView.invalid"
  mv "$fixture/ContentView.invalid" "$fixture/Sources/NativeBolabol/Views/ContentView.swift"
  if validate_contract "$fixture" >/dev/null; then
    echo "FAIL: negative self-test accepted a stale listening snapshot"
    return 1
  fi

  echo "OK: HUD humor/prompt contract negative self-test"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

validate_contract "$ROOT"
echo "OK: HUD humor/prompt production factory, pending snapshot, hit-testing, and accessibility contracts"
