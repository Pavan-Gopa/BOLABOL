#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${VM_NAME:-vani-clean}"
DISK_SIZE_GB="${DISK_SIZE_GB:-80}"
CPU_COUNT="${CPU_COUNT:-4}"
MEMORY_MB="${MEMORY_MB:-8192}"
DISPLAY="${DISPLAY:-1920x1200}"
MIN_FREE_GB="${MIN_FREE_GB:-75}"

if ! command -v tart >/dev/null 2>&1; then
  echo "Tart is not installed. Install it first with: brew install cirruslabs/cli/tart"
  exit 1
fi

FREE_GB="$(df -g / | awk 'NR == 2 { print $4 }')"
if [[ -z "${FREE_GB}" || "${FREE_GB}" -lt "${MIN_FREE_GB}" ]]; then
  echo "Not enough free disk space to create the VM safely."
  echo "Available: ${FREE_GB:-unknown} GiB"
  echo "Required: at least ${MIN_FREE_GB} GiB"
  exit 1
fi

if tart list | awk 'NR > 1 { print $2 }' | grep -Fxq "${VM_NAME}"; then
  echo "VM '${VM_NAME}' already exists."
  echo "Run it with: ./run-clean-macos-vm.sh"
  exit 0
fi

echo "Creating clean macOS VM '${VM_NAME}'..."
echo "Disk: ${DISK_SIZE_GB} GB, CPU: ${CPU_COUNT}, Memory: ${MEMORY_MB} MB"
tart create "${VM_NAME}" --from-ipsw latest --disk-size "${DISK_SIZE_GB}" --disk-format asif
tart set "${VM_NAME}" --cpu "${CPU_COUNT}" --memory "${MEMORY_MB}" --display "${DISPLAY}"

echo
echo "VM '${VM_NAME}' is ready."
echo "Start it with: ./run-clean-macos-vm.sh"
