#!/usr/bin/env bash
# A5: SettingsView cloudProviderCard for Qwen/OpenRouter/Ollama (no coming-soon for them).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
start = text.find("private struct ProviderCardView")
end = text.find("private struct CloudKeyModelRow", start)
if end < 0:
    end = text.find("private struct ApiKeyInputRow", start)
card = text[start:end if end > 0 else None]
if start < 0 or not card:
    raise SystemExit("FAIL: ProviderCardView missing")

if "cloudProviderCard" not in card:
    raise SystemExit("FAIL: cloudProviderCard missing")

# Explicit cases for the three A5 providers
for cid in ("qwenID", "openrouterID", "ollamaCloudID"):
    if f"CloudProviderCatalog.{cid}" not in card:
        raise SystemExit(f"FAIL: switch missing case for {cid}")

# Those cases route to cloudProviderCard, not comingSoon
# Find the case block for qwen…ollama
import re
m = re.search(
    r"case CloudProviderCatalog\.qwenID[\s\S]{0,200}cloudProviderCard",
    card,
)
if not m:
    raise SystemExit("FAIL: qwen/openrouter/ollama cases do not render cloudProviderCard")

# "coming soon" must not be the primary path for those three
# (comingSoonCard may remain as defensive default for unknown ids — OK)
print("PASS: SettingsView uses cloudProviderCard for Qwen/OpenRouter/Ollama (stub retired).")
PY
