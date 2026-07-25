#!/usr/bin/env bash
# QA/run_all.sh — VaniScript QA suite runner (dev-workflow, not product code).
#
# Runs every enabled script in QA/manifest.json in order. Any non-zero exit → RED.
# The QA engineer owns the WHOLE app: build gates (AS + Electron), MCP smoke, and
# per-step delta scripts. Re-run the FULL suite after any product fix.
#
# Usage:
#   cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"
#   QA/run_all.sh
#
# Exit codes: 0 = all green; 1 = at least one suite failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLE_SILICON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$SCRIPT_DIR/manifest.json"

cd "$APPLE_SILICON_DIR"

if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 required to read manifest.json" >&2
  exit 1
fi

# Read enabled scripts (relative to QA/scripts/) in manifest order.
mapfile -t SCRIPTS < <(python3 - "$MANIFEST" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
for s in m.get("scripts", []):
    if s.get("enabled", True):
        print(s["path"])
PY
)

if [[ ${#SCRIPTS[@]} -eq 0 ]]; then
  echo "No enabled scripts in manifest.json"
  exit 0
fi

PASS=0
FAIL=0
FAILED_LIST=()

echo "=== VaniScript QA suite ($(date '+%Y-%m-%d %H:%M:%S')) ==="
for rel in "${SCRIPTS[@]}"; do
  script="$SCRIPT_DIR/scripts/$rel"
  echo ""
  echo "── RUN: $rel ──"
  if [[ ! -f "$script" ]]; then
    echo "MISSING: $script"
    FAIL=$((FAIL+1)); FAILED_LIST+=("$rel (missing)")
    continue
  fi
  if bash "$script"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); FAILED_LIST+=("$rel")
  fi
done

echo ""
echo "=== QA SUMMARY ==="
echo "PASS: $PASS   FAIL: $FAIL"
if [[ $FAIL -gt 0 ]]; then
  echo "FAILED suites:"
  for f in "${FAILED_LIST[@]}"; do echo "  - $f"; done
  echo "RESULT: RED — write QA/BUG_REPORT.md and call the orchestrator."
  exit 1
fi
echo "RESULT: GREEN — write QA/REPORT.md and call the orchestrator."
exit 0
