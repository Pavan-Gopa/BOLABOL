#!/usr/bin/env bash
# graphify_rebuild.sh — rebuild Blaboom knowledge graph (agent token savings)
#
# Dev-workflow tool — NOT product code. Agents prefer:
#   graphify query | explain | path
# over dumping whole Sources trees.
#
# Usage (from Blaboom product root):
#   ./AI_Workflow_Kit/script/graphify_rebuild.sh
#   ./AI_Workflow_Kit/script/graphify_rebuild.sh --force
#
# Requires: `graphify` on PATH (e.g. uv tool install graphifyy)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLABOOM_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$BLABOOM_ROOT/graphify-out"
GRAPH_JSON="$OUT_DIR/graph.json"

cd "$BLABOOM_ROOT"

if ! command -v graphify &>/dev/null; then
  echo "ERROR: graphify not on PATH." >&2
  echo "Install: uv tool install graphifyy" >&2
  exit 1
fi

EXTRA_ARGS=(--no-cluster)
if [[ "${1:-}" == "--force" ]] || [[ "${GRAPHIFY_FORCE:-}" == "1" ]]; then
  EXTRA_ARGS+=(--force)
fi

echo "Rebuilding Blaboom knowledge graph"
echo "  product root: $BLABOOM_ROOT"
echo "  output:       $GRAPH_JSON"
mkdir -p "$OUT_DIR"

# Update code graph under Blaboom only (not whole monorepo).
graphify update "$BLABOOM_ROOT" "${EXTRA_ARGS[@]}"

if [[ -f "$GRAPH_JSON" ]]; then
  NODES=$(python3 -c "import json;g=json.load(open('$GRAPH_JSON'));print(len(g.get('nodes',g if isinstance(g,list) else [])))" 2>/dev/null || echo "?")
  echo "OK: graphify-out/graph.json ready (nodes≈$NODES)"
  echo "Query examples:"
  echo "  graphify explain \"AppText\" --graph \"$GRAPH_JSON\""
  echo "  graphify path \"OnboardingView\" \"GeneralSettingsStore\" --graph \"$GRAPH_JSON\""
  echo "  graphify query \"where is transcription language stored\" --graph \"$GRAPH_JSON\""
else
  echo "WARN: graph.json not found after update — inspect graphify output above." >&2
  exit 1
fi
