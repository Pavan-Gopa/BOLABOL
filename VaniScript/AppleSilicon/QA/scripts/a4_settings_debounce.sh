#!/usr/bin/env bash
# A4: validation debounce via .task(id: apiKey) + 500ms sleep (cancel on key change).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
grep -q '\.task(id: apiKey)' "$FILE" || {
  echo "FAIL: .task(id: apiKey) debounce host missing"; exit 1
}
grep -Eq '500_000_000|nanoseconds: 500' "$FILE" || {
  echo "FAIL: 500ms debounce sleep missing"; exit 1
}
# Core has no timer — debounce lives in UI
if grep -Eq 'Timer|DispatchQueue.main.asyncAfter' Sources/VaniScriptCore/CloudKeyValidator.swift; then
  echo "FAIL: CloudKeyValidator must not own debounce timers"; exit 1
fi
echo "PASS: UI debounce (.task(id:) + 500ms) present; core stays timer-free."
