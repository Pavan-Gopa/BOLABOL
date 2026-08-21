#!/usr/bin/env bash
# Manage the additive Main-only context-economy experiment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ACTION="${1:-status}"
BRANCH="${WF_CONTEXT_ECONOMY_BRANCH:-experiment/context-economy-v3.2}"
UPSTREAM="${WF_UPSTREAM_URL:-https://github.com/Pavan-Gopa/Pavans-Workflow.git}"
STATE_HELPER="$SCRIPT_DIR/workflow_experiment_state.py"

case "$ACTION" in
  status)
    exec python3 "$STATE_HELPER" status "$PROJECT_ROOT"
    ;;
  doctor)
    exec python3 "$STATE_HELPER" doctor "$PROJECT_ROOT"
    ;;
  rollback)
    python3 "$STATE_HELPER" rollback "$PROJECT_ROOT"
    echo "Context-economy v3 rolled back."
    echo "The base workflow dashboard and native Agent Hub remain intact."
    echo "Product source, product tests, STATE/STEPS/DECISIONS, reports, and artifacts were not touched."
    echo "Restart OMP."
    ;;
  update)
    tmp_dir="$(mktemp -d -t pavans-context-economy-update.XXXXXX)"
    trap 'rm -rf "${tmp_dir:-}"' EXIT
    git clone -q --depth 1 --branch "$BRANCH" "$UPSTREAM" "$tmp_dir/pw"
    bash "$tmp_dir/pw/AI_Workflow_Kit/experiments/context-economy/install.sh" "$PROJECT_ROOT"
    echo "Main-only context-economy experiment updated. Restart OMP."
    ;;
  *)
    echo "Usage: bash AI_Workflow_Kit/script/workflow_experiment.sh [status|doctor|update|rollback]" >&2
    exit 2
    ;;
esac
