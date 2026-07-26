#!/usr/bin/env bash
# A4: CloudKeyValidator.validate reuses CloudModelCatalog.listRequest (same endpoints/auth as §9.1).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudKeyValidator.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
grep -q 'CloudModelCatalog.listRequest' "$FILE" || {
  echo "FAIL: validate must call CloudModelCatalog.listRequest"; exit 1
}
grep -q 'fetcher(request)' "$FILE" || grep -q 'fetcher(' "$FILE" || {
  echo "FAIL: validate must invoke injected fetcher"; exit 1
}
grep -q 'status(forHTTPStatus' "$FILE" || {
  echo "FAIL: validate must map HTTP via status(forHTTPStatus:)"; exit 1
}
echo "PASS: CloudKeyValidator.validate uses listRequest + fetcher + status map."
