#!/usr/bin/env bash
# A4: CloudHTTPFetcher injectable; CloudHTTP.live default; tests inject mocks.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudModelCatalog.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
grep -q 'typealias CloudHTTPFetcher' "$FILE" || {
  echo "FAIL: CloudHTTPFetcher typealias missing"; exit 1
}
grep -q 'CloudHTTP' "$FILE" || {
  echo "FAIL: CloudHTTP.live missing"; exit 1
}
grep -q 'fetcher:' "$FILE" || {
  echo "FAIL: CloudModelCatalog must accept fetcher injection"; exit 1
}
# Validator also injectable
V="Sources/VaniScriptCore/CloudKeyValidator.swift"
grep -q 'fetcher:' "$V" || {
  echo "FAIL: CloudKeyValidator must accept fetcher injection"; exit 1
}
# Tests inject fetcher
grep -q 'CloudModelCatalog(fetcher:' Tests/VaniScriptCoreTests/CloudModelCatalogTests.swift || {
  echo "FAIL: catalog tests must inject fetcher"; exit 1
}
grep -q 'CloudKeyValidator(fetcher:' Tests/VaniScriptCoreTests/CloudKeyValidatorTests.swift || {
  echo "FAIL: validator tests must inject fetcher"; exit 1
}
echo "PASS: CloudHTTPFetcher injectable on catalog + validator (tests mock network)."
