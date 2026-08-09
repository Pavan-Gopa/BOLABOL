#!/usr/bin/env bash
# ProviderUsage.lastPurpose + UsageRecorder.purpose for STT vs translation stats.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
AS="Sources/VaniScriptCore/AppSettings.swift"
UR="Sources/VaniScriptCore/UsageRecorder.swift"
[[ -f "$AS" && -f "$UR" ]] || { echo "FAIL: source missing"; exit 1; }
grep -q "lastPurpose" "$AS" || { echo "FAIL: ProviderUsage.lastPurpose missing"; exit 1; }
grep -q "purpose" "$UR" || { echo "FAIL: UsageRecorder.record purpose param missing"; exit 1; }
grep -Eq 'lastPurpose = purpose|entry\.lastPurpose = purpose' "$UR" || {
  echo "FAIL: record() does not write lastPurpose"; exit 1
}
echo "PASS: lastPurpose usage field + recorder wiring present."
