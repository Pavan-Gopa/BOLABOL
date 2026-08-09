#!/usr/bin/env bash
# CPS acceptance + architecture document OBS-001…OBS-005.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
ACC="AI_Workflow_Kit/docs/CLOUD_PROVIDER_STABILIZATION_ACCEPTANCE.md"
ARCH="AI_Workflow_Kit/docs/CLOUD_PROVIDER_STABILIZATION_ARCHITECTURE.md"
[[ -f "$ACC" ]] || { echo "FAIL: $ACC missing"; exit 1; }
[[ -f "$ARCH" ]] || { echo "FAIL: $ARCH missing"; exit 1; }
grep -q "CPS-01" "$ACC" || { echo "FAIL: CPS-01 section missing in acceptance"; exit 1; }
grep -Eq "OBS-002" "$ACC" || { echo "FAIL: OBS-002 missing in acceptance"; exit 1; }
# Full registry is in architecture
for obs in OBS-001 OBS-002 OBS-003 OBS-004 OBS-005; do
  grep -q "$obs" "$ARCH" || { echo "FAIL: architecture missing $obs"; exit 1; }
done
grep -Eq "VERIFIED|root cause" "$ACC" || {
  echo "FAIL: acceptance missing root-cause/VERIFIED evidence"; exit 1
}
echo "PASS: CPS acceptance + OBS registry (architecture) present."
