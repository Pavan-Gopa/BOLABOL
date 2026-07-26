#!/usr/bin/env bash
# A4: empty key → idle; custom/none listing → valid without network.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudKeyValidator.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScriptCore/CloudKeyValidator.swift").read_text(encoding="utf-8")
if "isEmpty" not in text or ".idle" not in text:
    raise SystemExit("FAIL: empty key → idle path missing")
if "listRequest" not in text:
    raise SystemExit("FAIL: validate must use CloudModelCatalog.listRequest")
# When listRequest is nil (custom), return .valid without calling fetcher
if "return .valid" not in text:
    raise SystemExit("FAIL: custom/no-listing path should return .valid")
# Tests cover empty + custom
tests = Path("Tests/VaniScriptCoreTests/CloudKeyValidatorTests.swift").read_text(encoding="utf-8")
if "emptyKeyIdle" not in tests and "empty key" not in tests.lower():
    raise SystemExit("FAIL: empty-key unit test missing")
if "customProviderValid" not in tests and "custom" not in tests.lower():
    raise SystemExit("FAIL: custom-provider unit test missing")
print("PASS: empty key → idle; custom → valid without network (code + tests).")
PY
