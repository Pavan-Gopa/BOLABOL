#!/usr/bin/env bash
# QA: build_gate_as.sh — Apple Silicon swift build gate
# Asserts: swift build succeeds for VaniScriptAppleSilicon package
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AS_DIR="$PROJECT_ROOT/AppleSilicon"

echo "=== build_gate_as: swift build ==="
cd "$AS_DIR"
swift build 2>&1
echo "PASS: build_gate_as — swift build succeeded"
exit 0
