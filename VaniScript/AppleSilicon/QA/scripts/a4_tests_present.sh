#!/usr/bin/env bash
# A4: CloudModelCatalogTests + CloudKeyValidatorTests present with expected suites.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

for f in \
  Tests/VaniScriptCoreTests/CloudKeyValidatorTests.swift \
  Tests/VaniScriptCoreTests/CloudModelCatalogTests.swift; do
  [[ -f "$f" ]] || { echo "FAIL: $f missing"; exit 1; }
done

grep -q '@Suite("CloudKeyValidator (A4)")' Tests/VaniScriptCoreTests/CloudKeyValidatorTests.swift || {
  echo "FAIL: CloudKeyValidator (A4) suite missing"; exit 1
}
grep -q '@Suite("CloudModelCatalog parsers (A4)")' Tests/VaniScriptCoreTests/CloudModelCatalogTests.swift || {
  echo "FAIL: CloudModelCatalog parsers (A4) suite missing"; exit 1
}

v_count=$(grep -c '@Test' Tests/VaniScriptCoreTests/CloudKeyValidatorTests.swift || true)
c_count=$(grep -c '@Test' Tests/VaniScriptCoreTests/CloudModelCatalogTests.swift || true)
[[ "$v_count" -ge 8 ]] || { echo "FAIL: expected ≥8 CloudKeyValidator @Test, got $v_count"; exit 1; }
[[ "$c_count" -ge 10 ]] || { echo "FAIL: expected ≥10 CloudModelCatalog @Test, got $c_count"; exit 1; }
echo "PASS: A4 unit test files present (validator=$v_count, catalog=$c_count @Test)."
