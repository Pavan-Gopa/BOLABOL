#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="VaniScript"
BUNDLE_ID="com.vaniscript.apple-silicon"
MIN_SYSTEM_VERSION="14.0"
BUILD_ID="${VANISCRIPT_BUILD_ID:-$(date -u +%Y%m%d%H%M%S)}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_MEDIA_BIN="$APP_BUNDLE/Contents/Resources/bin"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
VENDOR_BIN="$ROOT_DIR/Vendor/bin"
ELECTRON_ASSETS_DIR="${VANISCRIPT_ELECTRON_ASSETS_DIR:-$WORKSPACE_DIR/Electron/assets}"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --arch arm64 --product "$APP_NAME"
BUILD_BINARY="$(swift build --arch arm64 --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

# Copy Icon and Logo Assets to App Bundle Resources
copy_required_asset() {
  local source="$1"
  local target="$2"

  if [[ ! -f "$source" ]]; then
    echo "error: required app asset is missing: $source" >&2
    exit 1
  fi

  cp "$source" "$target"
}

copy_optional_asset() {
  local source="$1"
  local target="$2"

  if [[ -f "$source" ]]; then
    cp "$source" "$target"
  fi
}

copy_required_asset "$ELECTRON_ASSETS_DIR/icon.icns" "$APP_RESOURCES/AppIcon.icns"
copy_required_asset "$ELECTRON_ASSETS_DIR/icon.png" "$APP_RESOURCES/AppIcon.png"
copy_required_asset "$WORKSPACE_DIR/Shared/VaniScript_Logo.svg" "$APP_RESOURCES/VaniScript_Logo.svg"
copy_optional_asset "$WORKSPACE_DIR/Shared/VaniScript_Logo.png" "$APP_RESOURCES/VaniScript_Logo.png"
copy_optional_asset "$WORKSPACE_DIR/Shared/New_Logo.svg" "$APP_RESOURCES/New_Logo.svg"

if [[ -d "$ROOT_DIR/Sources/VaniScript/Resources/Fonts" ]]; then
  mkdir -p "$APP_RESOURCES/Fonts"
  cp "$ROOT_DIR"/Sources/VaniScript/Resources/Fonts/*.ttf "$APP_RESOURCES/Fonts/"
fi

if [[ ! -x "$VENDOR_BIN/yt-dlp" || ! -x "$VENDOR_BIN/ffmpeg" ]]; then
  echo "error: bundled media tools are missing." >&2
  echo "Run: ./script/install_media_tools.sh" >&2
  exit 1
fi

mkdir -p "$APP_MEDIA_BIN"
cp "$VENDOR_BIN/yt-dlp" "$APP_RESOURCES/bin/yt-dlp"
cp "$VENDOR_BIN/ffmpeg" "$APP_RESOURCES/bin/ffmpeg"
chmod 755 "$APP_RESOURCES/bin/yt-dlp" "$APP_RESOURCES/bin/ffmpeg"
/usr/bin/codesign --force --sign - "$APP_RESOURCES/bin/yt-dlp"
/usr/bin/codesign --force --sign - "$APP_RESOURCES/bin/ffmpeg"

# Locate and bundle precompiled mlx.metallib to prevent GPU/JIT shader runtime crashes
MLX_METALLIB=""
if [[ -f "/Users/pavan/.cache/uv/archive-v0/TACwTF-MNNR0LcPgtH6k7/mlx/lib/mlx.metallib" ]]; then
  MLX_METALLIB="/Users/pavan/.cache/uv/archive-v0/TACwTF-MNNR0LcPgtH6k7/mlx/lib/mlx.metallib"
else
  FOUND_METALLIB="$(find ~/.cache -name "mlx.metallib" 2>/dev/null | head -n 1)"
  if [[ -n "$FOUND_METALLIB" ]]; then
    MLX_METALLIB="$FOUND_METALLIB"
  fi
fi

if [[ -n "$MLX_METALLIB" ]]; then
  echo "Bundling precompiled MLX Metal library from: $MLX_METALLIB"
  cp "$MLX_METALLIB" "$APP_RESOURCES/mlx.metallib"
  cp "$MLX_METALLIB" "$APP_MACOS/mlx.metallib"
else
  echo "warning: mlx.metallib not found in cache. MLX text operations might crash." >&2
fi

ARCHS="$(/usr/bin/lipo -archs "$APP_BINARY")"
if [[ "$ARCHS" != "arm64" ]]; then
  echo "error: $APP_NAME must be Apple Silicon only. Found architectures: $ARCHS" >&2
  exit 1
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_ID</string>
  <key>VaniScriptBuildID</key>
  <string>$BUILD_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSArchitecturePriority</key>
  <array>
    <string>arm64</string>
  </array>
  <key>NSMicrophoneUsageDescription</key>
  <string>VaniScript needs microphone access to record and transcribe speech.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>VaniScript uses native speech components to transcribe recorded audio.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>VaniScript needs permission to paste transcribed text into the active app.</string>
</dict>
</plist>
PLIST

FORBIDDEN_PATTERN='python|node|node_modules|electron|chromium|llama|llamacpp'
if (cd "$APP_BUNDLE" && /usr/bin/find . -print | /usr/bin/grep -Eiq "$FORBIDDEN_PATTERN"); then
  echo "error: $APP_NAME.app contains non-native runtime artifacts:" >&2
  (cd "$APP_BUNDLE" && /usr/bin/find . -print | /usr/bin/grep -Ei "$FORBIDDEN_PATTERN") >&2
  exit 1
fi

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  *)
    echo "usage: $0 [run|--verify|--logs]" >&2
    exit 2
    ;;
esac
