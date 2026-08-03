#!/usr/bin/env bash
# checkpoint.sh — scoped git checkpoints for Bolabol workflow steps
#
# Scoped to Bolabol/ under the AI Projects monorepo — never git add -A on
# the monorepo root without path filter.
#
# Usage (from Bolabol product root):
#   ./AI_Workflow_Kit/script/checkpoint.sh pre B1
#   ./AI_Workflow_Kit/script/checkpoint.sh post B1 "short description"
#   ./AI_Workflow_Kit/script/checkpoint.sh list
#   ./AI_Workflow_Kit/script/checkpoint.sh rollback pre|post B1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOLABOL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PRODUCT_PREFIX="bolabol"
REL_BOLABOL="Bolabol"

die() { echo "error: $*" >&2; exit 1; }

# Resolve git root (monorepo or nested)
cd "$BOLABOL_ROOT"
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git work tree"
cd "$GIT_ROOT"

# Relative path of Bolabol product from git root
if [[ "$(basename "$BOLABOL_ROOT")" == "Bolabol" ]] && [[ "$GIT_ROOT" != "$BOLABOL_ROOT" ]]; then
  # Monorepo: stage Bolabol/
  STAGE_PATHS=("$REL_BOLABOL")
  # Allow alternate layout if Bolabol is not direct child name
  if [[ ! -d "$GIT_ROOT/$REL_BOLABOL" ]]; then
    # Compute relative path from git root to BOLABOL_ROOT
    REL_FROM_ROOT="${BOLABOL_ROOT#"$GIT_ROOT"/}"
    STAGE_PATHS=("$REL_FROM_ROOT")
  fi
else
  # Nested repo whose root is Bolabol
  STAGE_PATHS=(".")
fi

resolve_step() {
  local step="${1:-}"
  if [[ "$step" =~ ^B([0-9]|1[0-2])$ ]] \
    || [[ "$step" =~ ^S([0-9]|1[0-5])$ ]] \
    || [[ "$step" =~ ^S1(b|c)$ ]]; then
    return 0
  fi
  die "step must be B0..B12, S0..S15, S1b, or S1c; got: ${step:-empty}"
}

pre_tag_for()  { echo "${PRODUCT_PREFIX}/pre-${1}"; }
post_tag_for() { echo "${PRODUCT_PREFIX}/${1}-done"; }

has_remote_push() {
  local url
  url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -z "$url" ]]; then
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
  local p
  for p in "${STAGE_PATHS[@]}"; do
    if [[ "$p" == "." ]]; then
      git add -A -- .
    else
      git add -A -- "$p"
    fi
  done
}

commit_if_dirty_scoped() {
  local message="$1"
  stage_scoped
  if git diff --cached --quiet; then
    echo "nothing staged under Bolabol scope — no new commit"
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
  commit_if_dirty_scoped "chore(${PRODUCT_PREFIX}): checkpoint before ${step}"
  git tag -a "$tag" -m "Bolabol checkpoint before ${step}"
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
  commit_if_dirty_scoped "feat(${PRODUCT_PREFIX}): ${step} — ${detail}"
  git tag -a "$tag" -m "Bolabol ${step} done: ${detail}"
  echo "created tag $tag → $(git rev-parse --short HEAD)"
  push_all "$tag"
  echo "POST-CHECK DONE: $tag"
}

cmd_list() {
  echo "=== bolabol/* tags ==="
  git tag -l 'bolabol/*' --sort=creatordate
  echo "=== recent commits (15) ==="
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
  ./AI_Workflow_Kit/script/checkpoint.sh pre <B0..B12|S0..S15|S1b|S1c>
  ./AI_Workflow_Kit/script/checkpoint.sh post <B0..B12|S0..S15|S1b|S1c> [description]
  ./AI_Workflow_Kit/script/checkpoint.sh list
  ./AI_Workflow_Kit/script/checkpoint.sh rollback pre|post <B0..B12>

Stages only Bolabol/ under the monorepo (never whole AI Projects tree).
Tags: bolabol/pre-<step>, bolabol/<step>-done
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
