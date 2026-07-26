#!/usr/bin/env bash
# A5: ProviderRegistryCloudTests + CloudProviderRoutingTests present with suites.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

for f in \
  Tests/VaniScriptCoreTests/ProviderRegistryCloudTests.swift \
  Tests/VaniScriptCoreTests/CloudProviderRoutingTests.swift; do
  [[ -f "$f" ]] || { echo "FAIL: $f missing"; exit 1; }
done

grep -q 'Provider registry — A5 cloud providers' Tests/VaniScriptCoreTests/ProviderRegistryCloudTests.swift || {
  echo "FAIL: ProviderRegistryCloudTests suite missing"; exit 1
}
grep -q 'CloudChatRouter — A5 routing' Tests/VaniScriptCoreTests/CloudProviderRoutingTests.swift || {
  echo "FAIL: CloudProviderRoutingTests suite missing"; exit 1
}

r_count=$(grep -c '@Test' Tests/VaniScriptCoreTests/ProviderRegistryCloudTests.swift || true)
c_count=$(grep -c '@Test' Tests/VaniScriptCoreTests/CloudProviderRoutingTests.swift || true)
[[ "$r_count" -ge 4 ]] || { echo "FAIL: expected ≥4 ProviderRegistryCloud @Test, got $r_count"; exit 1; }
[[ "$c_count" -ge 6 ]] || { echo "FAIL: expected ≥6 CloudProviderRouting @Test, got $c_count"; exit 1; }
echo "PASS: A5 unit test files present (registry=$r_count, routing=$c_count @Test)."
