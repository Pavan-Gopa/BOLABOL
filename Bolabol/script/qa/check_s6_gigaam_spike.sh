#!/usr/bin/env bash
# S6 GigaAM v3 Core ML spike contract: report + native Swift harness only.
# This is deliberately separate from the B6/S4/S5 Canary guard so prior spike
# contracts remain independently visible and cannot be weakened by S6 changes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

DOC="docs/asr/gigaam-v3/COREML_SPIKE.md"
HARNESS="docs/asr/gigaam-v3/GigaAMCoreMLSpike.swift"
FAILED=0

require_literal() {
  local file="$1"
  local needle="$2"
  local message="$3"
  if ! grep -qF "$needle" "$file"; then
    echo "FAIL: $file $message"
    FAILED=1
  fi
}

[ -f "$DOC" ] || { echo "FAIL: $DOC not found"; FAILED=1; }
[ -f "$HARNESS" ] || { echo "FAIL: $HARNESS not found"; FAILED=1; }

if [ -f "$DOC" ]; then
  grep -qE "^\*\*Status:\*\* GO([[:space:]]|$)" "$DOC" || {
    echo "FAIL: $DOC lacks the expected explicit GO status"
    FAILED=1
  }
  for section in "Environment" "Artifact audit" "Load" "Short RU audio ASR" "Latency" "Language" "Chunking" "No Python" "Verdict"; do
    grep -qi "$section" "$DOC" || {
      echo "FAIL: $DOC lacks checklist section: $section"
      FAILED=1
    }
  done
  grep -qi "huggingfinger0/gigaam-v3-coreml" "$DOC" || {
    echo "FAIL: $DOC does not identify the selected candidate"
    FAILED=1
  }
  for constraint in "16 kHz" "30 s" "true valid" "reset RNNT predictor state" "blank id 1024" "S7+" "no product"; do
    grep -qi "$constraint" "$DOC" || {
      echo "FAIL: $DOC lacks S6/S7+ boundary constraint: $constraint"
      FAILED=1
    }
  done
fi

if [ -f "$HARNESS" ]; then
  for import in "import Accelerate" "import CoreML" "import Foundation"; do
    require_literal "$HARNESS" "$import" "is missing native import: $import"
  done
  for contract in \
    "let windowFrames = 3_000" \
    "let windowSamples = 480_000" \
    "let processedSamples = min(samples.count, windowSamples)" \
    "let validFrames = min(windowFrames, ((processedSamples - nFFT) / hopLength) + 1)" \
    "let validEncoderFrames = min(totalEncoderFrames, max(1, (validFrames + 3) / 4))" \
    "let blankID = 1024" \
    "if token == blankID" \
    "var hasState = false" \
    "hidden = try predictorState(nextHidden, hiddenSize: 320)" \
    "cell = try predictorState(nextCell, hiddenSize: 320)" \
    "validFrames: extracted.validFrames"; do
    require_literal "$HARNESS" "$contract" "is missing harness contract: $contract"
  done
  if grep -nE "python3|python[0-9.]*([[:space:]]|/)|pip3?([[:space:]]|$)|nemo|/usr/bin/env|Process\(|executableURL|launchPath" "$HARNESS"; then
    echo "FAIL: $HARNESS contains an external/Python inference path"
    FAILED=1
  fi
  hits=$(grep -n "Python" "$HARNESS" || true)
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *//*Python*) ;;
      *) echo "FAIL: $HARNESS has a non-comment Python mention: $line"; FAILED=1 ;;
    esac
  done <<< "$hits"
fi

if ! git check-ignore -q scratch/gigaam-spike; then
  echo "FAIL: scratch/gigaam-spike is not gitignored"
  FAILED=1
fi

tracked_spike_files=$(git ls-files -- 'scratch/gigaam-spike/**')
if [ -n "$tracked_spike_files" ]; then
  echo "FAIL: scratch/gigaam-spike contains tracked artifacts:"
  printf '%s\n' "$tracked_spike_files"
  FAILED=1
fi

# S6 must not turn the spike candidate into a product capability. Reuse the
# existing Canary/S1b boundary checks and add the stricter GigaAM source rule.
if ! bash "$ROOT/script/qa/check_no_canary_product.sh"; then
  FAILED=1
fi
if ! bash "$ROOT/script/qa/check_s1b_scope.sh"; then
  FAILED=1
fi
if grep -in "gigaam" Package.swift; then
  echo "FAIL: GigaAM product/package wiring found in Package.swift"
  FAILED=1
fi
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in
    *Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift*) ;;
    *Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift*) ;;
    *Sources/NativeBolabol/Stores/TranscriptionModelStore.swift*) ;;
    *Sources/NativeBolabol/Stores/TranscriptionEngineStore.swift*) ;;
    *) echo "FAIL: GigaAM product reference outside catalog/backend surface: $line"; FAILED=1 ;;
  esac
done < <(grep -RIni --include='*.swift' "gigaam" Sources || true)
if [ "$FAILED" -ne 0 ]; then
  echo "FAIL: S6 GigaAM spike contract broken"
  exit 1
fi

echo "OK: S6 GigaAM spike report + native harness + length/window + product-boundary contract holds"
