#!/usr/bin/env bash
# S1b remains a pure ranking helper; S1c and S2 may call it only from their
# dedicated views. The S2 call is checked more narrowly by check_s2_*.sh.
# ADR-018/019/020 GO surfaces are separately allowlisted below so this guard
# continues to catch accidental ASR wiring without rejecting accepted product
# routing, model settings, or engine UI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

RANKING_FILE="Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift"
ONBOARDING_VIEW="Sources/NativeBolabol/Views/OnboardingView.swift"
SETTINGS_VIEW="Sources/NativeBolabol/Views/Settings/LocalModelsSettingsView.swift"
FAILED=0

if [ ! -f "$RANKING_FILE" ]; then
  echo "FAIL: missing S1b ranking helper: $RANKING_FILE"
  exit 1
fi

if grep -nEi '^import (SwiftUI|AppKit|Cocoa|CoreML|FluidAudio|WhisperKit|MLX)$|TranscriptionEngine|EngineStore|ModelStore|Process\(' "$RANKING_FILE"; then
  echo "FAIL: S1b ranking helper contains UI/runtime wiring"
  FAILED=1
fi

while IFS= read -r line; do
  [ -n "$line" ] || continue
  if [[ "$line" == *"$RANKING_FILE"* ]]; then
    continue
  fi
  if [[ "$line" == "$ONBOARDING_VIEW:"* ]] && {
    [[ "$line" == *"OnboardingModelRecommendation.topThree("* ]] ||
    [[ "$line" == *"//"* ]]
  }; then
    continue
  fi
  if [[ "$line" == "$SETTINGS_VIEW:"* ]] && {
    [[ "$line" == *"OnboardingModelRecommendation.topThree("* ]] ||
    [[ "$line" == *"//"* ]]
  }; then
    continue
  fi
  echo "FAIL: S1b ranking symbol is used outside its pure helper or S1c view: $line"
  FAILED=1
done < <(grep -RIn --include='*.swift' -E 'OnboardingModelRecommendation|\.topThree\(' Sources || true)

while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in
    *OnboardingModelRecommendation.swift*) ;;
    *TranscriptionModelDescriptor.swift*) ;;
    *TranscriptionModelStore.swift*) ;;
    *TranscriptionEngineStore.swift*) ;;
    *AppText.swift*) ;;
    *helpBilingual*) ;;
    # S9: GO engine implementations and their accepted product surfaces are allowed
    *Engines/CanaryCoreMLEngine.swift*) ;;
    *Engines/GigaAMCoreMLEngine.swift*) ;;
    *Services/FloatingTranslationWindowManager.swift*) ;;
    *Services/HotkeySessionOverlayManager.swift*) ;;
    *Stores/TranscriptionEngineStore.swift*) ;;
    *Stores/TranscriptionModelStore.swift*) ;;
    *Views/ContentView.swift*) ;;
    *Views/Settings/HelpSettingsView.swift*) ;;
    *Views/Settings/HotkeySettingsView.swift*) ;;
    *Views/Settings/LocalModelsSettingsView.swift*) ;;
    *Views/TranslationModalView.swift*) ;;
    *NativeBolabolCore/Models/LanguagePickerOrder.swift*) ;;
    *NativeBolabolCore/Models/TranscriptionLanguageMode.swift*) ;;
    *NativeBolabolCore/Services/EngineProtocols.swift*) ;;
    *NativeBolabolCore/Services/TranscriptionLanguageRouting.swift*) ;;
    *)
      echo "FAIL: ASR candidate appears outside S1b/helper/catalog or help copy: $line"
      FAILED=1
      ;;
  esac
done < <(grep -RIni --include='*.swift' -E 'gigaam|canary' Sources || true)

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

echo "OK: S1b remains a pure ranking helper with allowlisted UI call sites and no runtime wiring"
