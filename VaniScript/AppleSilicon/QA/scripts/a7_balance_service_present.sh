#!/usr/bin/env bash
# A7 (§11): CloudBalanceService.swift present in VaniScriptCore — actor + protocol + role header.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudBalanceService.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing (A7 real-balance adapter)"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScriptCore/CloudBalanceService.swift").read_text(encoding="utf-8")
need = [
    "import Foundation",
    "public actor CloudBalanceService",
    "public protocol BalanceProvider",
    "func fetchBalance(apiKey: String) async throws -> BalanceInfo",
    "OpenRouterBalanceProvider",
    "OllamaCloudBalanceProvider",
]
for n in need:
    if n not in text:
        raise SystemExit(f"FAIL: CloudBalanceService.swift missing: {n}")
if "A7" not in text:
    raise SystemExit("FAIL: A7 role marker missing in CloudBalanceService.swift")
# Service must not be a view/struct — it is an actor (concurrency-safe cache).
if "public actor CloudBalanceService" not in text:
    raise SystemExit("FAIL: CloudBalanceService must be an actor")
print("PASS: CloudBalanceService.swift present (actor + BalanceProvider + providers + A7 markers).")
PY
