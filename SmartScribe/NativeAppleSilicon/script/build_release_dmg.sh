#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NativeSmartScribe"
DISPLAY_NAME="SmartScribe"
BUNDLE_ID="com.smartscribe.app"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
WORKER_NAME="NativeSmartScribePolishWorker"
WORKER_BINARY="$APP_MACOS/$WORKER_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
MLX_CHECKOUT="$ROOT_DIR/.build/checkouts/mlx-swift"
MLX_METAL_BUILD_DIR="$ROOT_DIR/.build/mlx-metal"
MLX_METALLIB_SOURCE="$MLX_METAL_BUILD_DIR/mlx/backend/metal/kernels/mlx.metallib"
MLX_METALLIB_DESTINATION="$APP_MACOS/mlx.metallib"
DEFAULT_CODESIGN_IDENTITY="NativeSmartScribe Local Development"

cd "$ROOT_DIR"

echo "=== Cleaning up existing processes ==="
pkill -f "NativeSmartScribe/Models/Polishing/HuggingFace/Direct" >/dev/null 2>&1 || true
pkill -x "$WORKER_NAME" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

echo "=== Building executable targets in Release configuration ==="
swift build -c release --arch arm64 --product "$APP_NAME"
swift build -c release --arch arm64 --product "$WORKER_NAME"
BUILD_BINARY="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"
BUILD_WORKER_BINARY="$(swift build -c release --arch arm64 --show-bin-path)/$WORKER_NAME"

metal_toolchain_id() {
  if printf '__METAL_VERSION__\n' | xcrun -sdk macosx metal -E -x metal -P - >/dev/null 2>&1; then
    echo ""
    return
  fi

  xcodebuild -showComponent MetalToolchain -json 2>/dev/null \
    | plutil -extract toolchainIdentifier raw -o - - 2>/dev/null || true
}

build_mlx_metallib() {
  local toolchain_id
  local metal_env
  toolchain_id="$(metal_toolchain_id)"

  if [[ -z "$toolchain_id" ]] \
    && ! printf '__METAL_VERSION__\n' | xcrun -sdk macosx metal -E -x metal -P - >/dev/null 2>&1; then
    cat >&2 <<'MESSAGE'
MLX Metal shader library is missing and the Xcode MetalToolchain is not available.
Install it with:
  xcodebuild -downloadComponent MetalToolchain
MESSAGE
    exit 1
  fi

  metal_env=()
  if [[ -n "$toolchain_id" ]]; then
    metal_env=(env TOOLCHAINS="$toolchain_id")
  fi

  echo "=== Building MLX Metal Library ==="
  if [[ ${#metal_env[@]} -gt 0 ]]; then
    "${metal_env[@]}" cmake \
      -S "$MLX_CHECKOUT/Source/Cmlx/mlx" \
      -B "$MLX_METAL_BUILD_DIR" \
      -DMLX_METAL_JIT=ON \
      -DMLX_BUILD_TESTS=OFF \
      -DMLX_BUILD_EXAMPLES=OFF \
      -DMLX_BUILD_PYTHON_BINDINGS=OFF \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_SYSTEM_VERSION" \
      -DFETCHCONTENT_SOURCE_DIR_METAL_CPP="$MLX_CHECKOUT/Source/Cmlx/metal-cpp" \
      -DFETCHCONTENT_SOURCE_DIR_JSON="$MLX_CHECKOUT/Source/Cmlx/json" \
      -DFETCHCONTENT_SOURCE_DIR_FMT="$MLX_CHECKOUT/Source/Cmlx/fmt"
    "${metal_env[@]}" cmake --build "$MLX_METAL_BUILD_DIR" --target mlx-metallib -j 8
  else
    cmake \
      -S "$MLX_CHECKOUT/Source/Cmlx/mlx" \
      -B "$MLX_METAL_BUILD_DIR" \
      -DMLX_METAL_JIT=ON \
      -DMLX_BUILD_TESTS=OFF \
      -DMLX_BUILD_EXAMPLES=OFF \
      -DMLX_BUILD_PYTHON_BINDINGS=OFF \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_SYSTEM_VERSION" \
      -DFETCHCONTENT_SOURCE_DIR_METAL_CPP="$MLX_CHECKOUT/Source/Cmlx/metal-cpp" \
      -DFETCHCONTENT_SOURCE_DIR_JSON="$MLX_CHECKOUT/Source/Cmlx/json" \
      -DFETCHCONTENT_SOURCE_DIR_FMT="$MLX_CHECKOUT/Source/Cmlx/fmt"
    cmake --build "$MLX_METAL_BUILD_DIR" --target mlx-metallib -j 8
  fi
}

if [[ ! -f "$MLX_METALLIB_SOURCE" ]]; then
  build_mlx_metallib
fi

echo "=== Preparing Release App Bundle ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_WORKER_BINARY" "$WORKER_BINARY"
cp "$MLX_METALLIB_SOURCE" "$MLX_METALLIB_DESTINATION"
chmod +x "$APP_BINARY"
chmod +x "$WORKER_BINARY"

mkdir -p "$APP_RESOURCES"

# Copy the native app icon and tray template assets into the bundle.
ICON_SRC="$ROOT_DIR/Sources/NativeSmartScribe/Resources/AppIcon.icns"
if [[ ! -f "$ICON_SRC" ]]; then
  ICON_SRC="$WORKSPACE_ROOT/assets/icons/icon.icns"
fi
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$APP_RESOURCES/AppIcon.icns"
fi

LOGO_SRC="$ROOT_DIR/Sources/NativeSmartScribe/Resources/New_Logo.svg"
if [[ ! -f "$LOGO_SRC" ]]; then
  LOGO_SRC="$WORKSPACE_ROOT/New_Logo.svg"
fi
if [[ -f "$LOGO_SRC" ]]; then
  cp "$LOGO_SRC" "$APP_RESOURCES/New_Logo.svg"
fi

for tray_asset in trayTemplate.png trayTemplate@2x.png; do
  tray_src="$WORKSPACE_ROOT/assets/icons/$tray_asset"
  if [[ -f "$tray_src" ]]; then
    cp "$tray_src" "$APP_RESOURCES/$tray_asset"
  fi
done

echo "=== Generating Info.plist ==="
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
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>SmartScribe needs microphone access to record and transcribe speech.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>SmartScribe uses on-device speech recognition to transcribe recorded audio.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>SmartScribe needs permission to paste transcribed text into the active app.</string>
</dict>
</plist>
PLIST

codesign_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "$CODESIGN_IDENTITY"
    return
  fi

  if /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/grep -q "\"$DEFAULT_CODESIGN_IDENTITY\""; then
    echo "$DEFAULT_CODESIGN_IDENTITY"
    return
  fi

  /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/awk -F '"' '/Apple Development|Developer ID Application/ { print $2; exit }'
}

SIGN_IDENTITY="$(codesign_identity)"
if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "warning: no stable code signing identity found; using ad-hoc signing."
  SIGN_IDENTITY="-"
fi

echo "=== Codesigning App Bundle ($SIGN_IDENTITY) ==="
/usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

echo "=== Creating DMG package ==="
DMG_TEMP_DIR="$RELEASE_DIR/dmg_temp"
rm -rf "$DMG_TEMP_DIR"
mkdir -p "$DMG_TEMP_DIR"

# Copy App Bundle to temporary packaging directory
cp -R "$APP_BUNDLE" "$DMG_TEMP_DIR/"

# Create symlink to /Applications
ln -s /Applications "$DMG_TEMP_DIR/Applications"

# Output DMG path
OUTPUT_DMG="$DIST_DIR/NativeSmartScribe.dmg"
rm -f "$OUTPUT_DMG"

echo "Creating raw DMG image..."
hdiutil create -fs HFS+ -srcfolder "$DMG_TEMP_DIR" -volname "$DISPLAY_NAME" -format UDRW "$DIST_DIR/temp.dmg"

echo "Compressing DMG image..."
hdiutil convert "$DIST_DIR/temp.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG"

# Clean up temporary images
rm -f "$DIST_DIR/temp.dmg"
rm -rf "$DMG_TEMP_DIR"

echo "=== DMG successfully created at: $OUTPUT_DMG ==="
ls -lh "$OUTPUT_DMG"
