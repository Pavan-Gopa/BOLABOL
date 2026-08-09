#!/usr/bin/env bash
# A3: Gemini/OpenAI cards — key + model row + budget Slider + Transcribing/Translation toggles 1:1.
# Step-aware model row:
#   A3  → ReadOnlyRow "Text Model"
#   A4+ → CloudKeyModelRow (validation badge + model Picker/combo) writing geminiTextModel/openaiTextModel
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

STATE_FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
current_step=""
if [[ -f "$STATE_FILE" ]]; then
  current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_-]+).*/\1/p' "$STATE_FILE" | head -1)"
fi

python3 - "$current_step" <<'PY'
import re, sys
from pathlib import Path
step = (sys.argv[1] or "A3").strip()
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
start = text.find("private struct ProviderCardView")
end = text.find("private struct ApiKeyInputRow", start)
card = text[start:end if end > 0 else None]
if start < 0 or not card:
    raise SystemExit("FAIL: ProviderCardView missing")

# Shared parity bits (A3 and later)
for n in (
    'ApiKeyInputRow(title: "Gemini Key"',
    'ApiKeyInputRow(title: "OpenAI Key"',
    'SliderRow(title: "Gemini Budget"',
    'SliderRow(title: "OpenAI Budget"',
    "gemini-cloud",
    "gpt-cloud",
    "coreml-whisperkit",
    "mlx-native",
    "Use for Transcribing",
    "Use for Translation",
    "geminiKey",
    "openaiKey",
    "geminiBudgetUsd",
    "openaiBudgetUsd",
):
    if n not in card:
        raise SystemExit(f"FAIL: Gemini/OpenAI card missing: {n}")

# Model row evolves at A4
if step in ("A3", ""):
    if 'ReadOnlyRow(title: "Text Model"' not in card:
        raise SystemExit("FAIL: A3 expected ReadOnlyRow Text Model in Gemini/OpenAI cards")
    print("PASS: Gemini/OpenAI cards have key + ReadOnlyRow + budget Slider + toggles (A3).")
else:
    # A4+: CloudKeyModelRow with bindings to text model settings
    if "CloudKeyModelRow" not in card:
        raise SystemExit("FAIL: A4+ expected CloudKeyModelRow in Gemini/OpenAI cards")
    if "geminiTextModel" not in card:
        raise SystemExit("FAIL: Gemini CloudKeyModelRow must bind geminiTextModel")
    if "openaiTextModel" not in card:
        raise SystemExit("FAIL: OpenAI CloudKeyModelRow must bind openaiTextModel")
    print(f"PASS: Gemini/OpenAI cards have key + CloudKeyModelRow + budget Slider + toggles (step={step}).")
PY
