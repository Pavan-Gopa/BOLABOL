#!/usr/bin/env bash
# A3: Qwen/OpenRouter/Ollama used coming-soon stub (key field + note).
# Step-aware:
#   A3–A4 → default → comingSoonCard for Qwen/OpenRouter/Ollama
#   A5+   → explicit cases → cloudProviderCard; comingSoonCard remains defensive fallback only
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

# switch covers gemini/openai/anthropic explicitly (all steps)
for cid in ("geminiID", "openaiID", "anthropicID"):
    if f"CloudProviderCatalog.{cid}" not in card:
        raise SystemExit(f"FAIL: switch missing case for {cid}")

# A5+ steps: A5 and later (A5, A6, A7, A8, …)
a5_or_later = bool(re.match(r"^A([5-9]|\d{2,})$", step)) or step in (
    "A5", "A6", "A7", "A8", "APIUSAGE_DONE", "API_USAGE_DONE", "CPS", "CPS-01", "CPS-02", "CPS-03", "CPS-04", "CPS-05", "CPS-06", "CPS-07", "CPS-08", "CPS-09", "CPS-10", "CLOUD_PROVIDER_STABILIZATION", "CPS", "CPS-01", "CPS-02", "CPS-03", "CPS-04", "CPS-05", "CPS-06", "CPS-07", "CPS-08", "CPS-09", "CPS-10", "CLOUD_PROVIDER_STABILIZATION",
)

if a5_or_later:
    if "cloudProviderCard" not in card:
        raise SystemExit("FAIL: A5+ expects cloudProviderCard for Qwen/OpenRouter/Ollama")
    for cid in ("qwenID", "openrouterID", "ollamaCloudID"):
        if f"CloudProviderCatalog.{cid}" not in card:
            raise SystemExit(f"FAIL: A5+ switch missing explicit case for {cid}")
    # Defensive fallback may still exist for unknown ids
    if "comingSoonCard" not in card:
        raise SystemExit("FAIL: comingSoonCard defensive fallback missing")
    print(f"PASS: A5+ cloudProviderCard for Qwen/OpenRouter/Ollama (step={step}; stub retired).")
else:
    if "comingSoonCard" not in card:
        raise SystemExit("FAIL: comingSoonCard missing")
    if "coming soon" not in card.lower():
        raise SystemExit("FAIL: 'coming soon' copy missing from stub")
    if "default:" not in card or "comingSoonCard" not in card:
        raise SystemExit("FAIL: default switch case should render comingSoonCard")
    print(f"PASS: Qwen/OpenRouter/Ollama use coming-soon stub via default case (step={step}).")
PY
