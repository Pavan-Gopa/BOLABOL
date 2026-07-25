#!/usr/bin/env bash
# cline_graphify_mcp.sh — wire Graphify as an MCP server for Cline (VaniScript).
#
# Agents building VaniScript should see Graphify tools (query/path/explain) via
# MCP when connected; the shell CLI (`graphify ... --graph <graph.json>`) is the
# always-available fallback. This is a DEV-WORFLOW convenience, not product code.
#
# Usage:
#   ./AppleSilicon/AI_Workflow_Kit/script/cline_graphify_mcp.sh            # write MCP config
#   ./AppleSilicon/AI_Workflow_Kit/script/cline_graphify_mcp.sh --rebuild  # refresh graph + config
#   ./AppleSilicon/AI_Workflow_Kit/script/cline_graphify_mcp.sh --status   # show config paths
#
# After running: fully quit and restart Cline so the MCP server reloads.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VANI_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
GRAPH_JSON="$VANI_ROOT/graphify-out/graph.json"

# Python that has the graphify module (uv tool install graphifyy). Override with GRAPHIFY_PY.
GRAPHIFY_PY="${GRAPHIFY_PY:-$HOME/.local/share/uv/tools/graphifyy/bin/python}"
CLINE_SETTINGS="$HOME/.cline/data/settings/cline_mcp_settings.json"
CLINE_MCP_JSON="$HOME/.cline/mcp.json"

cmd_status() {
  echo "VaniScript root: $VANI_ROOT"
  echo "Graph JSON:      $GRAPH_JSON ( $( [[ -f "$GRAPH_JSON" ]] && echo OK || echo MISSING ) )"
  echo "Graphify python: $GRAPHIFY_PY ( $( [[ -x "$GRAPHIFY_PY" ]] && echo OK || echo MISSING ) )"
  echo "Cline settings:  $CLINE_SETTINGS ( $( [[ -f "$CLINE_SETTINGS" ]] && echo present || echo absent ) )"
  echo "Cline mcp.json:  $CLINE_MCP_JSON ( $( [[ -f "$CLINE_MCP_JSON" ]] && echo present || echo absent ) )"
  if [[ -f "$CLINE_SETTINGS" ]]; then
    echo "--- cline_mcp_settings.json ---"
    cat "$CLINE_SETTINGS"
  fi
}

write_config() {
  # Safe merge: update ONLY mcpServers.graphify, preserve every other server
  # (e.g. palmier-pro). Never overwrite the whole file blindly.
  local target="$1"
  mkdir -p "$(dirname "$target")"
  GRAPHIFY_PY="$GRAPHIFY_PY" GRAPH_JSON="$GRAPH_JSON" python3 - "$target" <<'PY'
import json, os, sys
target = sys.argv[1]
py = os.environ["GRAPHIFY_PY"]
graph = os.environ["GRAPH_JSON"]
entry = {
    "disabled": False,
    "timeout": 60,
    "type": "stdio",
    "command": py,
    "args": ["-m", "graphify.serve", graph],
    "env": {},
}
try:
    with open(target) as f:
        cfg = json.load(f)
    if not isinstance(cfg, dict):
        cfg = {}
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}
servers = cfg.setdefault("mcpServers", {})
servers["graphify"] = entry  # upsert; other servers untouched
with open(target, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
  echo "Wrote (merged) $target"
}

cmd_install() {
  if [[ ! -x "$GRAPHIFY_PY" ]]; then
    echo "ERROR: graphify python not found at $GRAPHIFY_PY" >&2
    echo "Install: uv tool install graphifyy   (or set GRAPHIFY_PY)" >&2
    exit 1
  fi
  if [[ ! -f "$GRAPH_JSON" ]]; then
    echo "WARN: $GRAPH_JSON missing — running rebuild..."
    "$SCRIPT_DIR/graphify_rebuild.sh" || true
  fi
  if [[ ! -f "$GRAPH_JSON" ]]; then
    echo "ERROR: still no graph.json — run graphify_rebuild.sh first." >&2
    exit 1
  fi
  write_config "$CLINE_SETTINGS"
  write_config "$CLINE_MCP_JSON"
  echo ""
  echo "Done. Fully quit Cline and restart; the 'graphify' MCP server should appear."
  echo "After big code changes: rerun graphify_rebuild.sh, then reconnect MCP."
  echo "Note: the MCP server loads graph.json at process start."
}

case "${1:-}" in
  --status) cmd_status ;;
  --rebuild)
    "$SCRIPT_DIR/graphify_rebuild.sh"
    cmd_install
    ;;
  ""|--install) cmd_install ;;
  *) echo "Usage: $0 [--install|--rebuild|--status]" >&2; exit 2 ;;
esac
