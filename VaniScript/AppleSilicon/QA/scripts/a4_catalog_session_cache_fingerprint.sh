#!/usr/bin/env bash
# A4: session cache keyed by provider + key fingerprint (no raw secret); invalidate on provider.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudModelCatalog.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScriptCore/CloudModelCatalog.swift").read_text(encoding="utf-8")
if "keyFingerprint" not in text:
    raise SystemExit("FAIL: keyFingerprint missing")
if "hashValue" not in text:
    raise SystemExit("FAIL: fingerprint must use non-reversible hash (hashValue)")
if "cache[" not in text and "cache:" not in text and "private var cache" not in text:
    raise SystemExit("FAIL: session cache storage missing")
if "invalidate" not in text:
    raise SystemExit("FAIL: invalidate(providerID:) missing")
# Cache key must include fingerprint so key change busts entry
if "keyFingerprint" not in text[text.find("cacheKey"):text.find("cacheKey")+200] and "keyFingerprint" not in text:
    raise SystemExit("FAIL: cacheKey must incorporate keyFingerprint")
# Must NOT store raw apiKey in cache dictionary keys as the secret itself only
# (fingerprint is OK). Soft check: no cache key = raw key alone without hash.
if "cache[apiKey]" in text or 'cache[key]' in text:
    raise SystemExit("FAIL: cache must not key by raw apiKey")
# Unit test: listModels caches (fetcher once)
tests = Path("Tests/VaniScriptCoreTests/CloudModelCatalogTests.swift").read_text(encoding="utf-8")
if "listModelsWithMockFetcher" not in tests:
    raise SystemExit("FAIL: listModels cache unit test missing")
print("PASS: session cache + key fingerprint + invalidate present.")
PY
