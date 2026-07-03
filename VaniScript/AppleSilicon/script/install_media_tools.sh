#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_BIN="$ROOT_DIR/Vendor/bin"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$VENDOR_BIN"

echo "Downloading yt-dlp_macos..."
/usr/bin/curl -L --fail --show-error \
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" \
  -o "$VENDOR_BIN/yt-dlp"

echo "Downloading ffmpeg for macOS Apple Silicon..."
/usr/bin/curl -L --fail --show-error \
  "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip" \
  -o "$TMP_DIR/ffmpeg.zip"

/usr/bin/ditto -x -k "$TMP_DIR/ffmpeg.zip" "$TMP_DIR/ffmpeg"
FFMPEG_BIN="$(/usr/bin/find "$TMP_DIR/ffmpeg" -type f -name ffmpeg | /usr/bin/head -n 1)"
if [[ -z "$FFMPEG_BIN" ]]; then
  echo "error: ffmpeg.zip did not contain an ffmpeg executable" >&2
  exit 1
fi

cp "$FFMPEG_BIN" "$VENDOR_BIN/ffmpeg"
chmod 755 "$VENDOR_BIN/yt-dlp" "$VENDOR_BIN/ffmpeg"

/usr/bin/xattr -d com.apple.quarantine "$VENDOR_BIN/yt-dlp" >/dev/null 2>&1 || true
/usr/bin/xattr -d com.apple.quarantine "$VENDOR_BIN/ffmpeg" >/dev/null 2>&1 || true
/usr/bin/codesign --force --sign - "$VENDOR_BIN/yt-dlp" >/dev/null 2>&1 || true
/usr/bin/codesign --force --sign - "$VENDOR_BIN/ffmpeg" >/dev/null 2>&1 || true

echo "Installed media tools:"
/usr/bin/file "$VENDOR_BIN/yt-dlp"
/usr/bin/file "$VENDOR_BIN/ffmpeg"
