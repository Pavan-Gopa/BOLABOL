#!/usr/bin/env bash
# A7 (ADR §5): short-TTL in-memory cache (default 60s) per provider id; force bypasses; invalidate().
# Session-only — nothing persisted.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudBalanceService.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re
text = Path("Sources/VaniScriptCore/CloudBalanceService.swift").read_text(encoding="utf-8")
if "ttl: TimeInterval = 60" not in text:
    raise SystemExit("FAIL: default TTL must be 60s")
if "private var cache:" not in text:
    raise SystemExit("FAIL: in-memory cache storage missing")
# force flag bypasses cache
if "force: Bool = false" not in text:
    raise SystemExit("FAIL: balance() must accept force flag")
if not re.search(r"if !force, let entry = cache\[", text):
    raise SystemExit("FAIL: cache hit must be gated on !force (force bypasses)")
if "func invalidate(providerID: String)" not in text:
    raise SystemExit("FAIL: invalidate(providerID:) missing")
# Session-only: no persistence APIs in the service.
for bad in ("UserDefaults", "NSKeyedArchiver", "write(to:", "FileManager"):
    if bad in text:
        raise SystemExit(f"FAIL: cache must be session-only, found persistence API: {bad}")
print("PASS: TTL=60s in-memory cache, force bypass, invalidate(), session-only (no persistence).")
PY
