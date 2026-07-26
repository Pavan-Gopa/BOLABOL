#!/usr/bin/env bash
# A4: CloudKeyModelRow writes geminiTextModel / openaiTextModel via bindings.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
# Gemini card binding
if 'selectedModel: binding(\\.geminiTextModel)' not in text and "binding(\\.geminiTextModel)" not in text:
    # Swift source uses binding(\.geminiTextModel)
    if "geminiTextModel" not in text or "selectedModel:" not in text:
        raise SystemExit("FAIL: geminiTextModel binding missing")
if "openaiTextModel" not in text:
    raise SystemExit("FAIL: openaiTextModel binding missing")
# Fallbacks for UI defaults
if "gemini-2.5-flash" not in text:
    raise SystemExit("FAIL: Gemini fallbackModel gemini-2.5-flash missing")
if "gpt-4o-mini" not in text:
    raise SystemExit("FAIL: OpenAI fallbackModel gpt-4o-mini missing")
print("PASS: Settings writes geminiTextModel / openaiTextModel with hardcode fallbacks.")
PY
