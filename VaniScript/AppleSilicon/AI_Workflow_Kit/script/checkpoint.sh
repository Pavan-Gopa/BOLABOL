#!/usr/bin/env bash
# Git checkpoints for GROK_MCP (G0–G6), UI_AS (U0–U3) and QWEN_MCP (Q0–Q7).
# Scoped to VaniScript paths — never git add -A on the whole AI Projects monorepo.
#
# Usage:
#   ./AI_Workflow_Kit/script/checkpoint.sh pre G1
#   ./AI_Workflow_Kit/script/checkpoint.sh post G1 "short description"
#   ./AI_Workflow_Kit/script/checkpoint.sh pre Q1
#   ./AI_Workflow_Kit/script/checkpoint.sh post Q1 "short description"
#   ./AI_Workflow_Kit/script/checkpoint.sh list
#   ./AI_Workflow_Kit/script/checkpoint.sh rollback pre|post G1
set -euo pipefail

AS_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Git root may be monorepo (AI Projects) or a nested repo.
cd "$AS_ROOT"
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: not inside a git work tree" >&2
  exit 1
}
cd "$GIT_ROOT"

# Paths relative to git root to stage (Apple Silicon always; Electron optional via ENV).
REL_AS="VaniScript/AppleSilicon"
REL_ELECTRON="VaniScript/Electron"
INCLUDE_ELECTRON="${CHECKPOINT_INCLUDE_ELECTRON:-0}"

die() { echo "error: $*" >&2; exit 1; }

resolve_step() {
  local step="${1:-}"
  if [[ "$step" =~ ^G[0-6]$|^GROK_DONE$ ]]; then
    TRACK_PREFIX="grok"
    TRACK_LABEL="GROK_MCP"
  elif [[ "$step" =~ ^U[0-3]$|^UI_DONE$ ]]; then
    TRACK_PREFIX="ui"
    TRACK_LABEL="UI_AS"
  elif [[ "$step" =~ ^Q[0-7]$|^QWEN_DONE$ ]]; then
    TRACK_PREFIX="qwen"
    TRACK_LABEL="QWEN_MCP"
  else
    die "step must be G0..G6, GROK_DONE, U0..U3, UI_DONE, Q0..Q7, or QWEN_DONE; got: ${step:-empty}"
  fi
}

pre_tag_for() {
  local step="$1"
  resolve_step "$step"
  echo "${TRACK_PREFIX}/pre-${step}"
}

post_tag_for() {
  local step="$1"
  resolve_step "$step"
  echo "${TRACK_PREFIX}/${step}-done"
}

has_remote_push() {
  local url
  url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -z "$url" ]]; then
    # try first remote
    url="$(git remote -v 2>/dev/null | awk '/\(push\)/{print $2; exit}')"
  fi
  [[ -n "$url" && "$url" != "DISABLED" && "$url" != *"DISABLED"* ]]
}

push_all() {
  local tag="$1"
  if has_remote_push; then
    local remote
    remote="$(git remote | head -1)"
    echo "→ git push $remote HEAD"
    git push -u "$remote" HEAD || echo "warn: push branch failed — local commit/tag kept"
    echo "→ git push $remote $tag"
    git push "$remote" "$tag" || echo "warn: push tag failed — local tag kept"
  else
    echo "warn: no pushable remote (DISABLED or missing) — commit/tag are LOCAL ONLY"
    echo "      human: enable remote and run: git push && git push --tags"
  fi
}

stage_scoped() {
  # Stage Apple Silicon tree; optionally Electron.
  if [[ -d "$GIT_ROOT/$REL_AS" ]]; then
    git add -A -- "$REL_AS"
  else
    # If git root IS AppleSilicon (nested in future)
    git add -A -- .
  fi
  if [[ "$INCLUDE_ELECTRON" == "1" && -d "$GIT_ROOT/$REL_ELECTRON" ]]; then
    git add -A -- "$REL_ELECTRON"
  fi
}

commit_if_dirty_scoped() {
  local message="$1"
  stage_scoped
  if git diff --cached --quiet; then
    echo "nothing staged under VaniScript scope — no new commit"
    return 0
  fi
  git commit -m "$message"
  echo "committed: $message"
}

cmd_pre() {
  local step="$1"
  resolve_step "$step"
  local tag
  tag="$(pre_tag_for "$step")"
  if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "tag $tag already exists → $(git rev-parse --short "$tag")"
    echo "skipping pre-commit (checkpoint already taken)"
    return 0
  fi
  commit_if_dirty_scoped "chore(${TRACK_PREFIX}): checkpoint before ${step}"
  git tag -a "$tag" -m "${TRACK_LABEL} checkpoint before ${step}"
  echo "created tag $tag → $(git rev-parse --short HEAD)"
  push_all "$tag"
  echo "PRE-CHECK DONE: $tag"
}

cmd_post() {
  local step="$1"
  local detail="${2:-done}"
  resolve_step "$step"
  local tag
  tag="$(post_tag_for "$step")"
  if git rev-parse "$tag" >/dev/null 2>&1; then
    die "tag $tag already exists — refuse to overwrite. Delete manually if intentional."
  fi
  commit_if_dirty_scoped "feat(${TRACK_PREFIX}): ${step} — ${detail}"
  git tag -a "$tag" -m "${TRACK_LABEL} ${step} approved: ${detail}"
  echo "created tag $tag → $(git rev-parse --short HEAD)"
  push_all "$tag"
  echo "POST-CHECK DONE: $tag"
}

cmd_list() {
  echo "=== grok/* tags ==="
  git tag -l 'grok/*' --sort=creatordate
  echo "=== ui/* tags ==="
  git tag -l 'ui/*' --sort=creatordate
  echo "=== qwen/* tags ==="
  git tag -l 'qwen/*' --sort=creatordate
  echo "=== recent commits ==="
  git log --oneline --decorate -15
}

cmd_rollback() {
  local kind="$1"
  local step="$2"
  resolve_step "$step"
  local tag
  case "$kind" in
    pre) tag="$(pre_tag_for "$step")" ;;
    post|done) tag="$(post_tag_for "$step")" ;;
    *) die "rollback kind must be pre|post, got: $kind" ;;
  esac
  git rev-parse "$tag" >/dev/null 2>&1 || die "missing tag $tag"
  echo "WARNING: hard reset to $tag ($(git rev-parse --short "$tag"))"
  echo "Uncommitted work will be lost. Press Ctrl+C within 3s to abort..."
  sleep 3
  git reset --hard "$tag"
  echo "reset to $tag"
}

usage() {
  cat <<'EOF'
Usage:
  ./AI_Workflow_Kit/script/checkpoint.sh pre <G0..G6|U0..U3|Q0..Q7>
  ./AI_Workflow_Kit/script/checkpoint.sh post <G0..G6|U0..U3|Q0..Q7> [description]
  ./AI_Workflow_Kit/script/checkpoint.sh list
  ./AI_Workflow_Kit/script/checkpoint.sh rollback pre|post <step>

Env:
  CHECKPOINT_INCLUDE_ELECTRON=1  also stage VaniScript/Electron
EOF
}

main() {
  local action="${1:-}"
  shift || true
  case "$action" in
    pre) cmd_pre "${1:-}" ;;
    post) cmd_post "${1:-}" "${2:-done}" ;;
    list) cmd_list ;;
    rollback) cmd_rollback "${1:-}" "${2:-}" ;;
    -h|--help|help|"") usage; exit 0 ;;
    *) die "unknown action: $action" ;;
  esac
}

main "$@"
