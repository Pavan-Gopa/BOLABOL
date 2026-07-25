#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${PORT:-8765}"

bridge_ip="$(ifconfig bridge100 2>/dev/null | awk '/inet / { print $2; exit }' || true)"
wifi_ip="$(ipconfig getifaddr en0 2>/dev/null || true)"

echo "Serving release files from:"
echo "  ${SCRIPT_DIR}"
echo
echo "Try these URLs inside the VM:"
if [[ -n "${bridge_ip}" ]]; then
  echo "  http://${bridge_ip}:${PORT}/"
fi
if [[ -n "${wifi_ip}" && "${wifi_ip}" != "${bridge_ip}" ]]; then
  echo "  http://${wifi_ip}:${PORT}/"
fi
echo
echo "If macOS asks about incoming connections for Python, allow it."
echo
cd "${SCRIPT_DIR}"
python3 -m http.server "${PORT}" --bind 0.0.0.0
