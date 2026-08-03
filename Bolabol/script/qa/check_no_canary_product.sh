#!/usr/bin/env bash
# ADR-012 invariant: zero Canary PRODUCT surface (no false capabilities).
#  1) Package.swift: no canary product/target/module naming surface anywhere.
#  2) Sources/: "canary" is tolerated ONLY as B4 i18n help copy —
#     AppText.swift locale maps and helpBilingual* key references (e.g.
#     HelpSettingsView rendering .helpBilingualCanary). Any other canary hit
#     (engine type, backend case, catalog entry, module) fails.
# Structural complement to the catalog unit test
# (nativeTranscriptionCatalogDoesNotContainCanaryProductOrBackend) and
# check_b6_canary_spike.sh (docs NO-GO). No product Sources touched.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FAILED=0

# 1. Package.swift: canary forbidden in products, targets, and dependencies.
if grep -in "canary" Package.swift; then
  echo "FAIL: canary product/module/target name found in Package.swift"
  FAILED=1
fi

# 2. Sources/: canary allowed only as i18n help copy (AppText.swift maps or
#    helpBilingual* key references). Everything else is a product leak.
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in
    *AppText.swift*) continue ;;
    *helpBilingual*) continue ;;
    *) echo "FAIL: canary outside i18n help copy: $line"; FAILED=1 ;;
  esac
done < <(grep -rin "canary" Sources --include='*.swift' || true)

if [ "$FAILED" -ne 0 ]; then
  echo "FAIL: ADR-012 no-product-Canary contract broken"
  exit 1
fi

echo "OK: zero Canary product/module surface (ADR-012) — i18n help copy only"
