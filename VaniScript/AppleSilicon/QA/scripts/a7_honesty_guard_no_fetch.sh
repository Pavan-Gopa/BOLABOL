#!/usr/bin/env bash
# A7 (ADR §4 honesty guard): .none/.estimated providers map to nil provider → .unavailable
# WITHOUT network; empty OpenRouter key → .unavailable no-fetch.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudBalanceService.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re
text = Path("Sources/VaniScriptCore/CloudBalanceService.swift").read_text(encoding="utf-8")
# provider(for:) returns nil for .none/.estimated
if not re.search(r"case \.none, \.estimated:", text):
    raise SystemExit("FAIL: provider(for:) must handle .none/.estimated")
if "return nil" not in text:
    raise SystemExit("FAIL: .none/.estimated must map to nil provider (no fetch)")
# balance() guards nil provider → .unavailable before any network
if not re.search(r"guard let provider = provider\(for: descriptor\) else \{ return \.unavailable \}", text):
    raise SystemExit("FAIL: balance() must guard nil provider → .unavailable (no network)")
# empty OpenRouter key → .unavailable, no fetch
if ".openrouterCredits" not in text or "trimmedKey.isEmpty" not in text:
    raise SystemExit("FAIL: empty OpenRouter key must short-circuit to .unavailable")
print("PASS: honesty guard — .none/.estimated nil-provider no-fetch; empty key no-fetch.")
PY
