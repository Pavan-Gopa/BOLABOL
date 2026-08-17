#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

DMG_PATH="${1:-$DIST_DIR/BOLABOL.dmg}"
OUTPUT_APPCAST="${2:-$DIST_DIR/appcast.xml}"
APP_VERSION="${APP_VERSION:-1.0.5}"
APP_BUILD="${APP_BUILD:-$(date +%Y%m%d%H%M)}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/Pavan-Gopa/BOLABOL/releases/download/v${APP_VERSION}/}"

echo "=== Bolabol Sparkle Appcast Generator ==="

# 1. Fail-closed: Validate exact DMG presence
if [[ ! -f "$DMG_PATH" ]]; then
  echo "Error: Release DMG not found at '$DMG_PATH'." >&2
  exit 1
fi

DMG_FILENAME="$(basename "$DMG_PATH")"
DMG_LENGTH="$(stat -f%z "$DMG_PATH" 2>/dev/null || wc -c < "$DMG_PATH" | tr -d ' ')"

if [[ -z "$DMG_LENGTH" || "$DMG_LENGTH" -le 0 ]]; then
  echo "Error: Invalid or zero-byte DMG at '$DMG_PATH'." >&2
  exit 1
fi

# 2. Locate Sparkle generate_appcast tool
find_sparkle_tool() {
  local tool_name="$1"
  if [[ -n "${SPARKLE_BIN_DIR:-}" && -x "$SPARKLE_BIN_DIR/$tool_name" ]]; then
    echo "$SPARKLE_BIN_DIR/$tool_name"
    return
  fi

  if command -v "$tool_name" >/dev/null 2>&1; then
    command -v "$tool_name"
    return
  fi

  local candidate_paths=(
    "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/$tool_name"
    "$ROOT_DIR/.build/checkouts/Sparkle/bin/$tool_name"
    "/opt/homebrew/opt/sparkle/bin/$tool_name"
    "/usr/local/opt/sparkle/bin/$tool_name"
  )

  for path in "${candidate_paths[@]}"; do
    if [[ -x "$path" ]]; then
      echo "$path"
      return
    fi
  done
}

GEN_TOOL="$(find_sparkle_tool "generate_appcast" || true)"

if [[ -z "$GEN_TOOL" ]]; then
  echo "Error: Sparkle tool 'generate_appcast' not found." >&2
  echo "Ensure Sparkle tools are installed or set SPARKLE_BIN_DIR." >&2
  exit 1
fi

# 3. Fail-closed: Validate private key or Keychain account credentials
KEY_ARGS=()
TEMP_KEY_FILE=""

cleanup() {
  if [[ -n "$TEMP_KEY_FILE" && -f "$TEMP_KEY_FILE" ]]; then
    rm -f "$TEMP_KEY_FILE"
  fi
}
trap cleanup EXIT

if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
    echo "Error: Private key file '$SPARKLE_PRIVATE_KEY_FILE' does not exist." >&2
    exit 1
  fi
  KEY_ARGS=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
elif [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  TEMP_KEY_FILE="$(mktemp)"
  chmod 600 "$TEMP_KEY_FILE"
  echo "$SPARKLE_ED_PRIVATE_KEY" > "$TEMP_KEY_FILE"
  KEY_ARGS=(--ed-key-file "$TEMP_KEY_FILE")
elif [[ -n "${SPARKLE_ACCOUNT:-}" || -n "${SPARKLE_KEYCHAIN_ACCOUNT:-}" ]]; then
  ACCOUNT_NAME="${SPARKLE_ACCOUNT:-${SPARKLE_KEYCHAIN_ACCOUNT:-}}"
  KEY_ARGS=(--account "$ACCOUNT_NAME")
else
  echo "Error: No Sparkle Ed25519 private key or keychain account specified." >&2
  echo "Set SPARKLE_PRIVATE_KEY_FILE, SPARKLE_ED_PRIVATE_KEY, or SPARKLE_ACCOUNT." >&2
  exit 1
fi

# 4. Generate appcast using Sparkle tooling
STAGE_DIR="$(mktemp -d)"
stage_cleanup() {
  cleanup
  rm -rf "$STAGE_DIR"
}
trap stage_cleanup EXIT

cp "$DMG_PATH" "$STAGE_DIR/$DMG_FILENAME"

echo "=== Running Sparkle generate_appcast ==="
"$GEN_TOOL" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  "${KEY_ARGS[@]}" \
  "$STAGE_DIR"

if [[ ! -f "$STAGE_DIR/appcast.xml" || ! -s "$STAGE_DIR/appcast.xml" ]]; then
  echo "Error: generate_appcast did not produce a valid appcast.xml in '$STAGE_DIR'." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_APPCAST")"
cp "$STAGE_DIR/appcast.xml" "$OUTPUT_APPCAST"

# 5. Validate generated appcast output
if [[ ! -f "$OUTPUT_APPCAST" || ! -s "$OUTPUT_APPCAST" ]]; then
  echo "Error: Generated appcast output at '$OUTPUT_APPCAST' is missing or empty." >&2
  exit 1
fi

if ! grep -q "sparkle:edSignature" "$OUTPUT_APPCAST" && ! grep -q "edSignature" "$OUTPUT_APPCAST"; then
  echo "Error: Generated appcast is missing Ed25519 signature." >&2
  exit 1
fi

if grep -q "latest/download" "$OUTPUT_APPCAST"; then
  echo "Error: Generated appcast contains forbidden mutable latest/download enclosure URL." >&2
  exit 1
fi

echo "=== Appcast generated successfully ==="
echo "    File: $OUTPUT_APPCAST"
echo "    Version: $APP_VERSION ($APP_BUILD)"
echo "    Prefix: $DOWNLOAD_URL_PREFIX"
