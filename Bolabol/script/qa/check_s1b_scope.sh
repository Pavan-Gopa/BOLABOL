#!/usr/bin/env bash
# S1b must remain a pure ranking helper: no S1c UI or ASR runtime wiring.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

RANKING_FILE="Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift"
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
  case "$line" in
    *OnboardingModelRecommendation.swift*) ;;
    *)
      echo "FAIL: S1b ranking symbol is used outside its pure helper: $line"
      FAILED=1
      ;;
  esac
done < <(grep -RIn --include='*.swift' -E 'OnboardingModelRecommendation|\.topThree\(' Sources || true)

while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in
    *OnboardingModelRecommendation.swift*) ;;
    *AppText.swift*) ;;
    *helpBilingual*) ;;
    *)
      echo "FAIL: ASR candidate appears outside S1b/helper or help copy: $line"
      FAILED=1
      ;;
  esac
done < <(grep -RIni --include='*.swift' -E 'gigaam|canary' Sources || true)

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

echo "OK: S1b remains a pure ranking helper with no S1c/runtime wiring"
