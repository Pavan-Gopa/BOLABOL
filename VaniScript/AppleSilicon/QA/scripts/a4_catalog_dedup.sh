#!/usr/bin/env bash
# A4: model list de-dupe preserves first-seen order and drops empties.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudModelCatalog.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
grep -q 'seen.insert' "$FILE" || grep -q 'Set<String>' "$FILE" || {
  echo "FAIL: de-dupe Set/seen missing in parse post-process"; exit 1
}
grep -q 'isEmpty' "$FILE" || {
  echo "FAIL: empty-id filter missing"; exit 1
}
TESTS="Tests/VaniScriptCoreTests/CloudModelCatalogTests.swift"
grep -q 'dedupesAndDropsEmpties' "$TESTS" || {
  echo "FAIL: dedupesAndDropsEmpties unit test missing"; exit 1
}
echo "PASS: catalog de-dupe + empty drop present (code + test)."
