#!/usr/bin/env bash
# Install SmartScribe.app into /Applications from a DMG (local path or latest private GitHub release).
set -euo pipefail

APP_NAME="SmartScribe"
VOLUME_NAME="SmartScribe"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
REPO="${SMARTSCRIBE_REPO:-Pavan-Gopa/SmartScribe}"
DMG_PATTERN="${SMARTSCRIBE_DMG_PATTERN:-SmartScribe*.dmg}"
OPEN_AFTER=0
FROM_GITHUB=0
DMG_PATH=""
MOUNT_POINT=""
TMP_DIR=""

usage() {
  cat <<'USAGE'
Usage:
  ./script/install.sh /path/to/SmartScribe.dmg [--open]
  ./script/install.sh --from-github [--open]

Options:
  --from-github   Download the latest SmartScribe*.dmg from the private GitHub release
                  (requires: gh auth login with access to the private repo)
  --open          Open the install folder after success
  -h, --help      Show this help

Environment:
  INSTALL_DIR              Install destination (default: /Applications)
  SMARTSCRIBE_REPO         GitHub repo (default: Pavan-Gopa/SmartScribe)
  SMARTSCRIBE_DMG_PATTERN  Release asset glob (default: SmartScribe*.dmg)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-github) FROM_GITHUB=1; shift ;;
    --open) OPEN_AFTER=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$DMG_PATH" ]]; then
        echo "error: unexpected argument: $1" >&2
        exit 2
      fi
      DMG_PATH="$1"
      shift
      ;;
  esac
done

if [[ "$FROM_GITHUB" -eq 1 && -n "$DMG_PATH" ]]; then
  echo "error: pass either a DMG path or --from-github, not both" >&2
  exit 2
fi

if [[ "$FROM_GITHUB" -eq 0 && -z "$DMG_PATH" ]]; then
  usage >&2
  exit 2
fi

cleanup() {
  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  fi
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ "$FROM_GITHUB" -eq 1 ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "error: GitHub CLI (gh) is required for --from-github" >&2
    exit 1
  fi
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/smartscribe-install.XXXXXX")"
  echo "=== Downloading latest $DMG_PATTERN from $REPO ==="
  gh release download -R "$REPO" -p "$DMG_PATTERN" -D "$TMP_DIR"
  DMG_PATH="$(find "$TMP_DIR" -maxdepth 1 -type f -name '*.dmg' | sort | head -n 1)"
  if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
    echo "error: no DMG asset matched $DMG_PATTERN in the latest release of $REPO" >&2
    exit 1
  fi
  echo "Using: $DMG_PATH"
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "error: DMG not found: $DMG_PATH" >&2
  exit 1
fi

echo "=== Attaching $DMG_PATH ==="
ATTACH_OUTPUT="$(hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountrandom "${TMPDIR:-/tmp}")"
MOUNT_POINT="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/\/Volumes\// { print $NF; exit }')"
if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT/$APP_NAME.app" ]]; then
  for candidate in "/Volumes/$VOLUME_NAME" /Volumes/SmartScribe*; do
    if [[ -d "$candidate/$APP_NAME.app" ]]; then
      MOUNT_POINT="$candidate"
      break
    fi
  done
fi

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT/$APP_NAME.app" ]]; then
  echo "error: could not find $APP_NAME.app inside the DMG" >&2
  exit 1
fi

DEST="$INSTALL_DIR/$APP_NAME.app"
echo "=== Installing to $DEST ==="
mkdir -p "$INSTALL_DIR"
if [[ -d "$DEST" ]]; then
  rm -rf "$DEST"
fi
ditto "$MOUNT_POINT/$APP_NAME.app" "$DEST"

if [[ ! -x "$DEST/Contents/MacOS/SmartScribe" ]]; then
  echo "warning: could not confirm executable Contents/MacOS/SmartScribe" >&2
fi

echo "=== Verifying signature (informational) ==="
codesign -dv --verbose=2 "$DEST" 2>&1 | sed -n '1,12p' || true
spctl -a -vv "$DEST" 2>&1 || true

echo "=== Installed: $DEST ==="
if [[ "$OPEN_AFTER" -eq 1 ]]; then
  open "$INSTALL_DIR"
fi
