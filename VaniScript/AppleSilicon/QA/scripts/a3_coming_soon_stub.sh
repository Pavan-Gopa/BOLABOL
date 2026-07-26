#!/usr/bin/env bash
# A3: Qwen/OpenRouter/Ollama use coming-soon stub (key field + note).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
start = text.find("private struct ProviderCardView")
end = text.find("private struct ApiKeyInputRow", start)
card = text[start:end if end > 0 else None]
if "comingSoonCard" not in card:
    raise SystemExit("FAIL: comingSoonCard missing")
if "coming soon" not in card.lower():
    raise SystemExit("FAIL: 'coming soon' copy missing from stub")
# default case routes to stub
if "default:" not in card or "comingSoonCard" not in card:
    raise SystemExit("FAIL: default switch case should render comingSoonCard")
# switch covers gemini/openai/anthropic explicitly
for cid in ("geminiID", "openaiID", "anthropicID"):
    if f"CloudProviderCatalog.{cid}" not in card:
        raise SystemExit(f"FAIL: switch missing case for {cid}")
print("PASS: Qwen/OpenRouter/Ollama use coming-soon stub via default case.")
PY
