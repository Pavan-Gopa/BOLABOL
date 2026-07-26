#!/usr/bin/env bash
# A3: engine ids preserved 1:1 — gemini-cloud / gpt-cloud / coreml-whisperkit / mlx-native.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

# Isolate ProviderCardView struct
python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
start = text.find("private struct ProviderCardView")
if start < 0:
    raise SystemExit("FAIL: ProviderCardView struct missing")
# until next private struct
rest = text[start:]
end_rel = rest.find("\nprivate struct ApiKeyInputRow")
if end_rel < 0:
    end_rel = rest.find("\nprivate struct ", 1)
card = rest[:end_rel] if end_rel > 0 else rest
required = [
    '"gemini-cloud"',
    '"gpt-cloud"',
    '"coreml-whisperkit"',
    '"mlx-native"',
]
for s in required:
    if s not in card:
        raise SystemExit(f"FAIL: engine id {s} missing from ProviderCardView")
# Gemini toggles use gemini-cloud + local fallbacks
if 'transcriptionProvider' not in card or 'translationProvider' not in card:
    raise SystemExit("FAIL: transcription/translation provider toggles missing from ProviderCardView")
print("PASS: engine ids gemini-cloud/gpt-cloud/coreml-whisperkit/mlx-native preserved in ProviderCardView.")
PY
