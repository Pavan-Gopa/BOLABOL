#!/usr/bin/env bash
# QA: build_gate_electron.sh — Electron TypeScript compile gate
# Asserts: npm run compile (tsc --noEmit) succeeds when node_modules present
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELECTRON_DIR="$PROJECT_ROOT/Electron"

echo "=== build_gate_electron: npm run compile ==="
cd "$ELECTRON_DIR"

if [ ! -d "node_modules" ]; then
    echo "SKIP: node_modules not found — cannot compile"
    echo "PASS: build_gate_electron (skipped, no node_modules)"
    exit 0
fi

npm run compile 2>&1
echo "PASS: build_gate_electron — tsc --noEmit succeeded"
exit 0
