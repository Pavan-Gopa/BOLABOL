#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

APP_VERSION="${1:-}"
APP_BUILD="${2:-$(date +%Y%m%d%H%M)}"
ALLOW_DIRTY="${ALLOW_DIRTY:-0}"
FORCE_TAG="${FORCE_TAG:-0}"
DRAFT_ONLY="${DRAFT_ONLY:-0}"
VERIFY_REMOTE_HTTPS="${VERIFY_REMOTE_HTTPS:-1}"
AUTO_COMMIT_FEED="${AUTO_COMMIT_FEED:-1}"
echo "=== Bolabol Secure In-App Update Publisher ==="

# 1. Validate version and build numbers
if [[ -z "$APP_VERSION" ]]; then
  echo "Usage: $0 <version> [build_number]" >&2
  echo "Example: $0 1.0.5 2026081701" >&2
  exit 1
fi

if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Error: Version '$APP_VERSION' is not a valid semantic version (e.g. 1.0.5)." >&2
  exit 1
fi

if [[ ! "$APP_BUILD" =~ ^[0-9]+$ ]]; then
  echo "Error: Build number '$APP_BUILD' must be numeric." >&2
  exit 1
fi

TAG_NAME="v$APP_VERSION"
echo "Target Release: $APP_VERSION (Build: $APP_BUILD, Tag: $TAG_NAME)"

# 2. Check for clean working tree
if [[ "$ALLOW_DIRTY" != "1" ]]; then
  if command -v git >/dev/null 2>&1; then
    if ! git -C "$ROOT_DIR" diff-index --quiet HEAD -- 2>/dev/null; then
      echo "Error: Working directory contains uncommitted changes." >&2
      echo "Commit your changes or pass ALLOW_DIRTY=1 to proceed." >&2
      exit 1
    fi
  fi
fi

# 3. Check for existing git tag
if [[ "$FORCE_TAG" != "1" ]]; then
  if command -v git >/dev/null 2>&1; then
    if git -C "$ROOT_DIR" rev-parse "$TAG_NAME" >/dev/null 2>&1; then
      echo "Error: Git tag '$TAG_NAME' already exists. Use FORCE_TAG=1 to override." >&2
      exit 1
    fi
  fi
fi

# 4. Fail-closed: Validate feed deployment / HTTPS verification configuration
if [[ "$AUTO_COMMIT_FEED" != "1" && "$VERIFY_REMOTE_HTTPS" == "1" ]]; then
  echo "Error: Cannot verify remote HTTPS feed when feed deployment (AUTO_COMMIT_FEED) is disabled. Set VERIFY_REMOTE_HTTPS=0 for local-only dry runs." >&2
  exit 1
fi

# 4. Fail-closed: Validate Sparkle public key and GitHub CLI availability
if [[ -z "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  echo "Error: SPARKLE_PUBLIC_ED_KEY environment variable is required for release publishing." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: GitHub CLI ('gh') is required to publish updates but was not found in PATH." >&2
  exit 1
fi

# 5. Build and notarize release DMG
echo "=== Step 1/5: Building and Notarizing Release DMG ==="
export RELEASE_BUILD=1
export NOTARIZE=1
export APP_VERSION="$APP_VERSION"
export APP_BUILD="$APP_BUILD"

bash "$ROOT_DIR/script/build_release_dmg.sh" --notarize --release

if [[ ! -f "$DIST_DIR/BOLABOL.dmg" || ! -s "$DIST_DIR/BOLABOL.dmg" ]]; then
  echo "Error: Release DMG was not created at '$DIST_DIR/BOLABOL.dmg'." >&2
  exit 1
fi

# 6. Generate signed appcast for immutable release URL
echo "=== Step 2/5: Generating Signed Appcast with Immutable Tag URL ==="
IMMUTABLE_PREFIX="https://github.com/Pavan-Gopa/BOLABOL/releases/download/$TAG_NAME/"

DOWNLOAD_URL_PREFIX="$IMMUTABLE_PREFIX" \
APP_VERSION="$APP_VERSION" \
APP_BUILD="$APP_BUILD" \
bash "$ROOT_DIR/script/generate_update_appcast.sh" \
  "$DIST_DIR/BOLABOL.dmg" \
  "$DIST_DIR/appcast.xml"

if [[ ! -f "$DIST_DIR/appcast.xml" || ! -s "$DIST_DIR/appcast.xml" ]]; then
  echo "Error: Appcast XML was not created at '$DIST_DIR/appcast.xml'." >&2
  exit 1
fi

# 7. Verify release package and appcast integrity
echo "=== Step 3/5: Verifying Release Package and Appcast Integrity ==="
bash "$ROOT_DIR/script/check_updater_release.sh" "$DIST_DIR/BOLABOL.dmg" "$DIST_DIR/appcast.xml"
# 8. Create GitHub release draft
echo "=== Step 4/5: Uploading Release Artifacts to GitHub ==="
DRAFT_CREATED=0

cleanup_draft() {
  if [[ "$DRAFT_CREATED" == "1" && "$DRAFT_ONLY" == "0" ]]; then
    echo "warning: Publishing was interrupted. Attempting to clean up draft release '$TAG_NAME'..." >&2
    gh release delete "$TAG_NAME" --yes 2>/dev/null || true
  fi
}
trap cleanup_draft EXIT

NOTES_ARG=()
if [[ -f "$ROOT_DIR/docs/RELEASE_NOTES.md" ]]; then
  NOTES_ARG=(--notes-file "$ROOT_DIR/docs/RELEASE_NOTES.md")
else
  NOTES_ARG=(--notes "Bolabol release $APP_VERSION ($APP_BUILD)")
fi

RELEASE_ASSETS=("$DIST_DIR/BOLABOL.dmg")
if [[ -f "$DIST_DIR/handoff/SHA256SUMS.txt" ]]; then
  RELEASE_ASSETS+=("$DIST_DIR/handoff/SHA256SUMS.txt")
elif [[ -f "$DIST_DIR/SHA256SUMS.txt" ]]; then
  RELEASE_ASSETS+=("$DIST_DIR/SHA256SUMS.txt")
else
  mkdir -p "$DIST_DIR/handoff"
  (cd "$DIST_DIR" && shasum -a 256 "BOLABOL.dmg" > "$DIST_DIR/handoff/SHA256SUMS.txt")
  RELEASE_ASSETS+=("$DIST_DIR/handoff/SHA256SUMS.txt")
fi
LOCAL_SHA256="$(shasum -a 256 "$DIST_DIR/BOLABOL.dmg" | awk '{print $1}')"

echo "Creating GitHub release draft for $TAG_NAME..."
gh release create "$TAG_NAME" \
  "${RELEASE_ASSETS[@]}" \
  --title "Bolabol $APP_VERSION" \
  --draft \
  "${NOTES_ARG[@]}"

DRAFT_CREATED=1

if [[ "$DRAFT_ONLY" == "1" ]]; then
  echo "=== Draft release created successfully: $TAG_NAME (DRAFT_ONLY=1) ==="
  echo "Skipping repository appcast feed update because draft assets are not publicly accessible."
  exit 0
fi

echo "Publishing release $TAG_NAME..."
gh release edit "$TAG_NAME" --draft=false
DRAFT_CREATED=0

echo "Verifying published release and assets on GitHub..."
RELEASE_VIEW_INFO="$(gh release view "$TAG_NAME" --json tagName,isDraft,assets --jq '
  [
    (.tagName // ""),
    (if .isDraft == true then "true" elif .isDraft == false then "false" else "unknown" end),
    ([.assets[] | select(.name == "BOLABOL.dmg")] | length | tostring),
    ([.assets[] | select(.name == "BOLABOL.dmg") | .digest // ""] | first // "")
  ] | @tsv
' 2>/dev/null || true)"

if [[ -z "$RELEASE_VIEW_INFO" ]]; then
  echo "Error: Failed to verify published GitHub release '$TAG_NAME'." >&2
  exit 1
fi

VIEW_TAG_NAME=""
RELEASE_IS_DRAFT=""
DMG_ASSET_COUNT=""
RELEASE_ASSET_DIGEST=""
IFS=$'\t' read -r VIEW_TAG_NAME RELEASE_IS_DRAFT DMG_ASSET_COUNT RELEASE_ASSET_DIGEST <<< "$RELEASE_VIEW_INFO"

if [[ "$RELEASE_IS_DRAFT" != "false" ]]; then
  echo "Error: GitHub release '$TAG_NAME' is still in draft state after publishing (isDraft=$RELEASE_IS_DRAFT)." >&2
  exit 1
fi

if [[ "$VIEW_TAG_NAME" != "$TAG_NAME" ]]; then
  echo "Error: GitHub release tag mismatch: expected '$TAG_NAME', got '$VIEW_TAG_NAME'." >&2
  exit 1
fi

if [[ -z "$DMG_ASSET_COUNT" || "$DMG_ASSET_COUNT" -lt 1 ]]; then
  echo "Error: Published release '$TAG_NAME' is missing required asset 'BOLABOL.dmg'." >&2
  exit 1
fi

CLEAN_RELEASE_DIGEST="${RELEASE_ASSET_DIGEST#sha256:}"
CLEAN_RELEASE_DIGEST="${CLEAN_RELEASE_DIGEST#SHA256:}"
CLEAN_RELEASE_DIGEST="$(echo "$CLEAN_RELEASE_DIGEST" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
CLEAN_LOCAL_SHA="$(echo "$LOCAL_SHA256" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

if [[ -z "$CLEAN_RELEASE_DIGEST" ]]; then
  echo "Error: Published release '$TAG_NAME' asset 'BOLABOL.dmg' is missing required sha256 digest." >&2
  exit 1
fi

if [[ "$CLEAN_RELEASE_DIGEST" != "$CLEAN_LOCAL_SHA" ]]; then
  echo "Error: GitHub asset digest mismatch for BOLABOL.dmg." >&2
  exit 1
fi
echo "=== GitHub release $TAG_NAME published and verified successfully ==="

# 9. Copy appcast to repository feed location
# In the GitHub repo 'Pavan-Gopa/BOLABOL', the raw feed is served from 'Bolabol/appcast.xml'.
# When running inside the Bolabol package root ($ROOT_DIR), this corresponds to $ROOT_DIR/appcast.xml.
# When running from the parent git repository root, it corresponds to $GIT_TOPLEVEL/Bolabol/appcast.xml.
GIT_TOPLEVEL="$(git -C "$ROOT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$GIT_TOPLEVEL" && "$GIT_TOPLEVEL" != "$ROOT_DIR" && -d "$GIT_TOPLEVEL/Bolabol" ]]; then
  FEED_DEST="$GIT_TOPLEVEL/Bolabol/appcast.xml"
else
  FEED_DEST="$ROOT_DIR/appcast.xml"
fi

if [[ "$DRAFT_ONLY" == "1" ]]; then
  echo "=== Draft release created successfully: $TAG_NAME (DRAFT_ONLY=1) ==="
  echo "Skipping repository appcast feed update because draft assets are not publicly accessible."
else
  echo "=== Step 5/5: Updating repository feed at $FEED_DEST ==="
  mkdir -p "$(dirname "$FEED_DEST")"
  cp "$DIST_DIR/appcast.xml" "$FEED_DEST"
  if [[ ! -f "$FEED_DEST" || ! -s "$FEED_DEST" ]]; then
    echo "Error: Failed to write valid appcast to '$FEED_DEST'." >&2
    exit 1
  fi
  echo "    Repository feed updated successfully at $FEED_DEST"

  # Re-verify deployed feed file
  bash "$ROOT_DIR/script/check_updater_release.sh" "$DIST_DIR/BOLABOL.dmg" "$FEED_DEST"

  if [[ "$AUTO_COMMIT_FEED" == "1" ]]; then
    echo "Committing and pushing updated appcast feed..."
    git -C "$(dirname "$FEED_DEST")" add "$FEED_DEST"
    if ! git -C "$(dirname "$FEED_DEST")" diff --cached --quiet; then
      git -C "$(dirname "$FEED_DEST")" commit -m "chore(release): update Sparkle appcast for $TAG_NAME"
      git -C "$(dirname "$FEED_DEST")" push origin HEAD || {
        echo "Error: Failed to push updated appcast feed to remote repository." >&2
        exit 1
      }
    fi
  fi

  if [[ "$VERIFY_REMOTE_HTTPS" == "1" ]]; then
    PUBLIC_ASSET_URL="https://github.com/Pavan-Gopa/BOLABOL/releases/download/$TAG_NAME/BOLABOL.dmg"
    echo "Validating public asset availability over HTTPS: $PUBLIC_ASSET_URL"
    HTTP_STATUS="$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 15 "$PUBLIC_ASSET_URL" || true)"
    if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "302" ]]; then
      echo "Error: Published asset is not accessible over HTTPS (HTTP status: $HTTP_STATUS) at $PUBLIC_ASSET_URL." >&2
      exit 1
    fi
    echo "    Public asset URL verified (HTTP $HTTP_STATUS)."

    RAW_FEED_URL="https://raw.githubusercontent.com/Pavan-Gopa/BOLABOL/main/Bolabol/appcast.xml"
    echo "Validating raw repository appcast feed availability over HTTPS: $RAW_FEED_URL"
    FEED_HTTP_STATUS="$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 15 "$RAW_FEED_URL" || true)"
    if [[ "$FEED_HTTP_STATUS" != "200" ]]; then
      echo "Error: Published appcast feed is not accessible over HTTPS (HTTP status: $FEED_HTTP_STATUS) at $RAW_FEED_URL." >&2
      exit 1
    fi
    echo "    Raw repository appcast feed verified (HTTP $FEED_HTTP_STATUS)."
  fi
fi

echo "=== UPDATE PUBLISH PIPELINE COMPLETE ==="
echo "    Version: $APP_VERSION ($APP_BUILD)"
echo "    Tag:     $TAG_NAME"
echo "    Feed:    https://raw.githubusercontent.com/Pavan-Gopa/BOLABOL/main/Bolabol/appcast.xml"
