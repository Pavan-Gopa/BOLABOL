#!/usr/bin/env bash
# graphify_rebuild.sh — rebuild the VaniScript knowledge graph (agent token savings).
#
# Role: DEV-WORFLOW tool for building VaniScript with AI agents — NOT product code.
# Agents must prefer `graphify query / explain / path` over dumping whole trees
# or bulk greps (see TEAM_CONTRACT.md, Graphify rule).
#
# The graph covers the whole VaniScript product (AppleSilicon Swift + Electron TS
# + Shared) in ONE graph, mirroring the DialGent single-graph convention.
# Output: <VaniScript>/graphify-out/graph.json
#
# Usage (from anywhere):
#   ./AppleSilicon/AI_Workflow_Kit/script/graphify_rebuild.sh
#   ./AppleSilicon/AI_Workflow_Kit/script/graphify_rebuild.sh --force
#
# Requires: `graphify` on PATH (installed via `uv tool install graphifyy`).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# script/ -> AI_Workflow_Kit -> AppleSilicon -> VaniScript (product root)
VANI_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
OUT_DIR="$VANI_ROOT/graphify-out"
GRAPH_JSON="$OUT_DIR/graph.json"

cd "$VANI_ROOT"

if ! command -v graphify &>/dev/null; then
  echo "ERROR: graphify not on PATH." >&2
  echo "Install: uv tool install graphifyy" >&2
  exit 1
fi

EXTRA_ARGS=(--no-cluster)   # code extraction only, no LLM clustering (fast, deterministic)
if [[ "${1:-}" == "--force" ]] || [[ "${GRAPHIFY_FORCE:-}" == "1" ]]; then
  EXTRA_ARGS+=(--force)     # overwrite even if rebuild has fewer nodes (after big deletes)
fi

echo "Rebuilding VaniScript knowledge graph"
echo "  product root: $VANI_ROOT"
echo "  output:       $GRAPH_JSON"
mkdir -p "$OUT_DIR"

# `update` re-extracts code files (no LLM). Walks the product root so AppleSilicon
# (Swift), Electron (TS/JS) and Shared share one graph. Heavy media under UserData
# is not transcribed by `update` (that only happens in the full /graphify pipeline).
graphify update "$VANI_ROOT" "${EXTRA_ARGS[@]}"

if [[ -f "$GRAPH_JSON" ]]; then
  NODES=$(python3 -c "import json;g=json.load(open('$GRAPH_JSON'));print(len(g.get('nodes',g if isinstance(g,list) else [])))" 2>/dev/null || echo "?")
  echo "OK: graphify-out/graph.json ready (nodes≈$NODES)"
  echo "Query examples (from AppleSilicon/ working dir):"
  echo "  graphify explain \"McpServer\" --graph \"$GRAPH_JSON\""
  echo "  graphify path \"ChatSidebarView\" \"McpToolRegistry\" --graph \"$GRAPH_JSON\""
  echo "  graphify query \"how does the embedded Grok chat call MCP tools\" --graph \"$GRAPH_JSON\""
else
  echo "WARN: graph.json not found after update — inspect graphify output above." >&2
  exit 1
fi
