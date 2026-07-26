#!/usr/bin/env bash
# A3: Anthropic card — key + ReadOnlyRow model (no budget/toggles required for A3).
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
if "anthropicCard" not in card and 'CloudProviderCatalog.anthropicID' not in card:
    raise SystemExit("FAIL: anthropic card branch missing")
if 'ApiKeyInputRow(title: "Anthropic Key"' not in card:
    raise SystemExit("FAIL: Anthropic Key row missing")
if "anthropicKey" not in card:
    raise SystemExit("FAIL: anthropicKey binding missing")
if 'ReadOnlyRow(title: "Text Model"' not in card:
    raise SystemExit("FAIL: Anthropic Text Model ReadOnlyRow missing")
# Anthropic should appear as a dedicated case
if "case CloudProviderCatalog.anthropicID" not in card and "anthropicCard" not in card:
    raise SystemExit("FAIL: anthropic case/card missing from switch")
print("PASS: Anthropic card has key + ReadOnlyRow model.")
PY
