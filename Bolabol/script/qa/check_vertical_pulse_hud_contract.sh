#!/usr/bin/env bash
# VERTICAL-PULSE-HUD contract: typed Canary source switching, ASR-only safety,
# right-click language semantics, and anchored Vertical Pulse geometry.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

require_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "FAIL: missing VERTICAL-PULSE-HUD contract file: $file"
    return 1
  fi
}

require_text() {
  local file="$1"
  local needle="$2"
  if ! grep -qF "$needle" "$file"; then
    echo "FAIL: $file missing: $needle"
    return 1
  fi
}

validate_contract() {
  local root="$1"
  local routing="$root/Sources/NativeBolabolCore/Services/TranscriptionLanguageRouting.swift"
  local layout="$root/Sources/NativeBolabolCore/Services/HUDQuickSwitcherLayout.swift"
  local store="$root/Sources/NativeBolabol/Stores/TranscriptionEngineStore.swift"
  local content="$root/Sources/NativeBolabol/Views/ContentView.swift"
  local overlay="$root/Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift"
  local picker="$root/Sources/NativeBolabol/Views/HUDLanguagePickerPopoverView.swift"
  local failed=0

  for file in "$routing" "$layout" "$store" "$content" "$overlay" "$picker"; do
    require_file "$file" || failed=1
  done
  [ "$failed" -eq 0 ] || return 1

  for contract in \
    'public let sourceLanguageOverride: String?' \
    'public let isAdditional: Bool' \
    'isAdditionalLanguage' \
    'sourceChoices.count > 1 ? .switchable : .fixed' \
    'languageControlEnabled: sourceChoices.count > 1' \
    'supportedCodes.contains(override)' \
    'replacingCanarySource' \
    'codes = normalizedDistinctCodes(supportedSourceCodes)' \
    'translateToEnglish: false' \
    'postASRTextTranslationTargetLanguageCode: nil'; do
    require_text "$routing" "$contract" || failed=1
  done

  # Fix Attempt 3: the target picker must use the complete 25-language catalog,
  # Auto + catalog for Whisper/Cloud, and explicit sources (no Auto) for Canary.
  for contract in \
    'completeTargetCatalog' \
    'CanaryLanguageCatalog.oneBV2LanguageCodes' \
    'flashSourceCatalog' \
    'case targetLanguageSelection' \
    'case explicitASRSource' \
    'case (.canaryCoreML, .targetLanguageSelection)' \
    'purpose: PickerPurpose = .explicitASRSource' \
    'codes = completeTargetCatalog' \
    'includesAutomatic = true'; do
    require_text "$routing" "$contract" || failed=1
  done

  for contract in \
    'sourceLanguageOverride: String? = nil' \
    'sourceLanguageOverride: sourceLanguageOverride'; do
    require_text "$store" "$contract" || failed=1
  done

  for contract in \
    'HUDLanguageMenuPolicy.nextCode' \
    'replacePendingCanarySession' \
    'TranscriptionSessionResolver.replacingCanarySource' \
    'applyHUDAdditionalLanguageSelection' \
    'onLanguageRightClick: handleOverlayLanguageRightClick' \
    'HUDLanguageMenuPolicy.options' \
    'purpose = .explicitASRSource' \
    'purpose = .targetLanguageSelection'; do
    require_text "$content" "$contract" || failed=1
  done

  for contract in \
    'event.type == .rightMouseUp' \
    'onLanguageRightClick' \
    'languageControlHitRect' \
    'HUDQuickSwitcherLayout.anchoredPanelFrame' \
    'HUDQuickSwitcherLayout.screenCapsuleFrame' \
    'HUDQuickSwitcherLayout.verticalControlHitFrame' \
    'showsHumorControl' \
    'updateTrackedCapsuleAfterExternalMove' \
    'laidOutCapsuleScreenFrame = nil' \
    'visibleFrame: visibleFrame' \
    'HUDCircularControlHitShape' \
    'controlHitMargin' \
    'controlHitShape' \
    'contentShape'; do
    require_text "$overlay" "$contract" || failed=1
  done

  # Fix Attempt 5: the AppKit interactive guard must share the circular hit
  # region with the SwiftUI Button instead of a rectangular corner-accepting formula.
  for contract in \
    'HUDQuickSwitcherLayout.verticalControlHitRegion' \
    'HUDVerticalControlHitRegion' \
    'isClickInLanguageControl' \
    'isClickInTargetControl' \
    'region.contains(pointX: Double(point.x), pointY: Double(point.y))'; do
    require_text "$overlay" "$contract" || failed=1
  done

  if ! (grep -A 8 'func finishHotkeySessionIfNeeded' "$content" 2>/dev/null || true) | grep -qF 'languagePickerController.invalidateForFinishedHotkeySession()'; then
    echo "FAIL: finishHotkeySessionIfNeeded does not invalidate the language picker popover"
    failed=1
  fi
  delegate_task="$(awk '
      /PopoverDelegate \{ \[weak self\] in/ { in_delegate = 1 }
      in_delegate && /popover\.delegate = delegate/ { in_delegate = 0 }
      in_delegate && /Task \{/ { hit = 1 }
      END { print hit + 0 }
    ' "$content")"
  if [ "$delegate_task" = "1" ]; then
    echo "FAIL: popoverDidClose cleanup is deferred inside a Task (stale-callback window)"
    failed=1
  fi

  for contract in \
    'verticalPulsePanelWidth' \
    'promptSlotCount = 5' \
    'HUDOverlayFrame' \
    'mainCapsuleFrame' \
    'anchoredPanelFrame' \
    'screenCapsuleFrame' \
    'AppText.localizedSpeechLanguageName' \
    'controlHitMargin' \
    'verticalControlHitFrame' \
    'HUDVerticalControlSlot' \
    'func controlDiameter(for scale' \
    'languagePickerMaxWidth = 196.0'; do
    require_text "$layout" "$contract" || failed=1
  done

  # The picker popover must stay compact (was 280pt before the rejection).
  require_text "$picker" 'maxWidth: 196' || failed=1
  require_text "$picker" 'option.isAdditional' || failed=1
  if grep -qF 'maxWidth: 280' "$picker"; then
    echo "FAIL: picker popover still uses the oversized 280pt max width"
    failed=1
  fi

  if grep -qF 'promptBar.offset' "$overlay"; then
    echo "FAIL: prompt row uses an offset instead of panel geometry"
    failed=1
  fi
  if grep -qF 'animator().setFrame' "$overlay"; then
    echo "FAIL: panel frame animation can double-move the main capsule"
    failed=1
  fi
  if grep -qF '.transition(.move' "$overlay"; then
    echo "FAIL: accessory move transition can reflow the main capsule"
    failed=1
  fi
  if grep -qF 'case .canaryCoreML:' "$content" \
      && ! grep -qF 'replacePendingCanarySession' "$content"; then
    echo "FAIL: Canary language callback has no immutable pending-session replacement"
    failed=1
  fi
  if (grep -A 35 'func handleOverlayLanguageSelection' "$content" 2>/dev/null || true) | grep -qF 'generalSettingsStore.speechLanguages ='; then
    echo "FAIL: handleOverlayLanguageSelection mutates persisted speechLanguages settings"
    failed=1
  fi
  if ! grep -qF 'didChangeScreenParametersNotification' "$content"; then
    echo "FAIL: ContentView missing display change parameter observer for popover dismissal"
    failed=1
  fi
  if ! (grep -A 3 'case (.canaryCoreML, .targetLanguageSelection)' "$routing" 2>/dev/null || true) | grep -qF 'return []'; then
    echo "FAIL: HUDLanguageMenuPolicy allows targetLanguageSelection for Canary Core ML"
    failed=1
  fi
  [ "$failed" -eq 0 ]
}

self_test() {
  local fixture
  fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-vertical-pulse.XXXXXX")"
  trap 'rm -rf "$fixture"' RETURN
  mkdir -p \
    "$fixture/Sources/NativeBolabolCore/Services" \
    "$fixture/Sources/NativeBolabol/Stores" \
    "$fixture/Sources/NativeBolabol/Views" \
    "$fixture/Sources/NativeBolabol/Services"

  cp "$ROOT/Sources/NativeBolabolCore/Services/TranscriptionLanguageRouting.swift" "$fixture/Sources/NativeBolabolCore/Services/"
  cp "$ROOT/Sources/NativeBolabolCore/Services/HUDQuickSwitcherLayout.swift" "$fixture/Sources/NativeBolabolCore/Services/"
  cp "$ROOT/Sources/NativeBolabol/Stores/TranscriptionEngineStore.swift" "$fixture/Sources/NativeBolabol/Stores/"
  cp "$ROOT/Sources/NativeBolabol/Views/ContentView.swift" "$fixture/Sources/NativeBolabol/Views/"
  cp "$ROOT/Sources/NativeBolabol/Views/HUDLanguagePickerPopoverView.swift" "$fixture/Sources/NativeBolabol/Views/"
  cp "$ROOT/Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift" "$fixture/Sources/NativeBolabol/Services/"

  validate_contract "$fixture" >/dev/null || {
    echo "FAIL: valid VERTICAL-PULSE-HUD fixture was rejected"
    return 1
  }

  grep -vF 'sourceLanguageOverride: String? = nil' \
    "$fixture/Sources/NativeBolabol/Stores/TranscriptionEngineStore.swift" \
    > "$fixture/store.invalid"
  mv "$fixture/store.invalid" "$fixture/Sources/NativeBolabol/Stores/TranscriptionEngineStore.swift"
  if validate_contract "$fixture" >/dev/null; then
    echo "FAIL: negative self-test accepted a missing typed store override"
    return 1
  fi
  cp "$ROOT/Sources/NativeBolabol/Stores/TranscriptionEngineStore.swift" "$fixture/Sources/NativeBolabol/Stores/"

  grep -vF 'HUDLanguageMenuPolicy.nextCode' \
    "$fixture/Sources/NativeBolabol/Views/ContentView.swift" \
    > "$fixture/content.invalid"
  mv "$fixture/content.invalid" "$fixture/Sources/NativeBolabol/Views/ContentView.swift"
  if validate_contract "$fixture" >/dev/null; then
    echo "FAIL: negative self-test accepted missing HUDLanguageMenuPolicy.nextCode"
    return 1
  fi
  cp "$ROOT/Sources/NativeBolabol/Views/ContentView.swift" "$fixture/Sources/NativeBolabol/Views/"

  sed -i '' 's/func handleOverlayLanguageSelection.*/func handleOverlayLanguageSelection(_ code: String, popoverID: UUID) {\n        generalSettingsStore.speechLanguages = languages/' "$fixture/Sources/NativeBolabol/Views/ContentView.swift"
  if validate_contract "$fixture" >/dev/null; then
    echo "FAIL: negative self-test accepted speechLanguages settings mutation in selection handler"
    return 1
  fi
  cp "$ROOT/Sources/NativeBolabol/Views/ContentView.swift" "$fixture/Sources/NativeBolabol/Views/"

  grep -vF 'maxWidth: 196' \
    "$fixture/Sources/NativeBolabol/Views/HUDLanguagePickerPopoverView.swift" \
    > "$fixture/picker.invalid" || true
  mv "$fixture/picker.invalid" "$fixture/Sources/NativeBolabol/Views/HUDLanguagePickerPopoverView.swift"
  printf 'maxWidth: 280\n' >> "$fixture/Sources/NativeBolabol/Views/HUDLanguagePickerPopoverView.swift"
  if validate_contract "$fixture" >/dev/null; then
    echo "FAIL: negative self-test accepted oversized 280pt picker width"
    return 1
  fi
  cp "$ROOT/Sources/NativeBolabol/Views/HUDLanguagePickerPopoverView.swift" "$fixture/Sources/NativeBolabol/Views/"

  grep -vF 'HUDQuickSwitcherLayout.verticalControlHitRegion' \
    "$fixture/Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift" \
    > "$fixture/overlay.invalid"
  mv "$fixture/overlay.invalid" "$fixture/Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift"
  if validate_contract "$fixture" >/dev/null; then
    echo "FAIL: negative self-test accepted a rectangular-only AppKit hit guard"
    return 1
  fi
  cp "$ROOT/Sources/NativeBolabol/Services/HotkeySessionOverlayManager.swift" "$fixture/Sources/NativeBolabol/Services/"

  awk 'BEGIN { in_finish = 0 }
    /private func finishHotkeySessionIfNeeded/ { in_finish = 1 }
    in_finish && /^        languagePickerController\.invalidateForFinishedHotkeySession\(\)$/ { next }
    { print }
    in_finish && /^    }$/ { in_finish = 0 }' \
    "$fixture/Sources/NativeBolabol/Views/ContentView.swift" \
    > "$fixture/content.finish.invalid"
  mv "$fixture/content.finish.invalid" "$fixture/Sources/NativeBolabol/Views/ContentView.swift"
  if validate_contract "$fixture" >/dev/null; then
    echo "FAIL: negative self-test accepted finish path that leaves the popover logically live"
    return 1
  fi
  cp "$ROOT/Sources/NativeBolabol/Views/ContentView.swift" "$fixture/Sources/NativeBolabol/Views/"

  sed -i '' 's/let delegate = PopoverDelegate { \[weak self\] in/let delegate = PopoverDelegate { [weak self] in\n            Task { @MainActor in/' \
    "$fixture/Sources/NativeBolabol/Views/ContentView.swift"
  if validate_contract "$fixture" >/dev/null; then
    echo "FAIL: negative self-test accepted deferred popoverDidClose cleanup"
    return 1
  fi

  echo "OK: VERTICAL-PULSE-HUD negative self-test"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

validate_contract "$ROOT"
echo "OK: VERTICAL-PULSE-HUD typed routing, right-click, ASR-only, and anchored geometry contracts"
