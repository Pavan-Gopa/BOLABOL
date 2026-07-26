#!/usr/bin/env bash
# A6: apiKeysTab provider cards intact (ProviderCardView, cloudProviderCard, CloudKeyModelRow).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
for needle in (
    "private struct ProviderCardView",
    "ProviderCardView(descriptor:",
    "cloudProviderCard",
    "CloudKeyModelRow",
    "CloudProviderCatalog.providers",
):
    if needle not in text:
        raise SystemExit(f"FAIL: provider-card marker missing: {needle}")
# Gemini/OpenAI/Anthropic cases still present
for cid in ("geminiID", "openaiID", "anthropicID", "qwenID", "openrouterID", "ollamaCloudID"):
    if f"CloudProviderCatalog.{cid}" not in text:
        raise SystemExit(f"FAIL: catalog id case missing: {cid}")
print("PASS: ProviderCardView + cloud cards intact after A6 stats rewrite.")
PY
