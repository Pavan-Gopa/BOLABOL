#!/usr/bin/env bash
# QA/scripts/build_gate_electron.sh — Electron compile gate.
# Runs `npm run compile` (tsc --noEmit) in the Electron app. Skips gracefully
# (SKIP, exit 0) when node_modules is absent so the suite stays runnable on a
# fresh checkout. Exit 0 = green/skip. Dev-workflow QA script, not product code.

set -uo pipefail

AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ELECTRON_DIR="$(cd "$AS_DIR/../Electron" 2>/dev/null && pwd || true)"

echo "Electron build gate"

if [[ -z "${ELECTRON_DIR:-}" || ! -d "$ELECTRON_DIR" ]]; then
  echo "SKIP: Electron dir not found next to AppleSilicon — nothing to compile."
  exit 0
fi
cd "$ELECTRON_DIR"
echo "cwd: $ELECTRON_DIR"

if [[ ! -f package.json ]]; then
  echo "SKIP: no package.json in Electron dir."
  exit 0
fi

if [[ ! -d node_modules ]]; then
  echo "SKIP: node_modules absent (run 'npm install' to enable the Electron compile gate)."
  exit 0
fi

if ! command -v npm &>/dev/null; then
  echo "SKIP: npm not on PATH."
  exit 0
fi

if npm run compile 2>&1 | tail -40; then
  echo "OK: npm run compile (tsc --noEmit) green"
  exit 0
fi

echo "FAIL: npm run compile failed"
exit 1
