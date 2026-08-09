#!/usr/bin/env bash
# OBS-005: Anthropic must be in catalog + Settings card.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
python3 - <<'PY'
from pathlib import Path
import re
cat = Path("Sources/VaniScriptCore/CloudProviderCatalog.swift").read_text(encoding="utf-8")
m = re.search(r'providerOrder:\s*\[String\]\s*=\s*\[(.*?)\]', cat, re.S)
order = re.findall(r'(\w+ID)', m.group(1) if m else "")
providers_start = cat.find("static let providers")
providers_end = cat.find("/// Descriptor lookup", providers_start)
providers_block = cat[providers_start:providers_end if providers_end > 0 else providers_start + 8000]
has_anthropic_desc = bool(re.search(r'id:\s*anthropicID', providers_block))
anthropic_in_order = "anthropicID" in order
sv = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
has_card = "anthropicCard" in sv or "case CloudProviderCatalog.anthropicID" in sv
print(f"INFO: order={order} desc={has_anthropic_desc} card={has_card}")
if anthropic_in_order and has_anthropic_desc and has_card:
    print("PASS: Anthropic restored in catalog order + providers + Settings card (OBS-005 surface).")
    raise SystemExit(0)
raise SystemExit("FAIL: OBS-005 — Anthropic missing from catalog and/or Settings card.")
PY
