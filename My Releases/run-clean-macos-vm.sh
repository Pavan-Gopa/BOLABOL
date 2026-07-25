#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="${VM_NAME:-vani-clean}"

if ! command -v tart >/dev/null 2>&1; then
  echo "Tart is not installed."
  exit 1
fi

if ! tart list | awk 'NR > 1 { print $2 }' | grep -Fxq "${VM_NAME}"; then
  echo "VM '${VM_NAME}' does not exist yet."
  echo "Create it first with: ./create-clean-macos-vm.sh"
  exit 1
fi

echo "Starting VM '${VM_NAME}'..."
echo "Release files will be mounted read-only inside the VM at:"
echo "  /Volumes/My Shared Files/releases"
echo
echo "Inside the VM:"
echo "  1. Finish macOS setup."
echo "  2. Open Finder -> Locations -> My Shared Files -> releases."
echo "  3. Install SmartScribe.dmg, VaniScript.dmg, and VaniScript-Electron.dmg."
echo "  4. Run diagnose-vani-apps.sh from Terminal if a launch fails."
echo
tart run "${VM_NAME}" --dir "releases:${SCRIPT_DIR}:ro"
