#!/usr/bin/env bash
set -euo pipefail

SWIFT_PRODUCT_NAME="NativeBolabol"
APP_NAME="Bolabol"
DISPLAY_NAME="Bolabol"
BUNDLE_ID="com.bolabol.app"
MIN_SYSTEM_VERSION="14.0"
# Marketing / build versions embedded in Info.plist (override with env).
APP_VERSION="${APP_VERSION:-1.0.4}"
APP_BUILD="${APP_BUILD:-$(date +%Y%m%d%H%M)}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
WORKER_NAME="NativeBolabolPolishWorker"
WORKER_BINARY="$APP_MACOS/$WORKER_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS_FILE="$ROOT_DIR/script/release.entitlements"
MLX_CHECKOUT="$ROOT_DIR/.build/checkouts/mlx-swift"
MLX_METAL_BUILD_DIR="$ROOT_DIR/.build/mlx-metal"
MLX_METALLIB_SOURCE="$MLX_METAL_BUILD_DIR/mlx/backend/metal/kernels/mlx.metallib"
MLX_METALLIB_DESTINATION="$APP_MACOS/mlx.metallib"
DEFAULT_DEVELOPER_ID_IDENTITY="Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV)"
DEFAULT_CODESIGN_IDENTITY="NativeBolabol Local Development"

cd "$ROOT_DIR"

echo "=== Cleaning up existing processes ==="
pkill -f "NativeBolabol/Models/Polishing/HuggingFace/Direct" >/dev/null 2>&1 || true
pkill -x "$WORKER_NAME" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "$SWIFT_PRODUCT_NAME" >/dev/null 2>&1 || true

echo "=== Building executable targets in Release configuration ==="
swift build -c release --arch arm64 --product "$SWIFT_PRODUCT_NAME"
swift build -c release --arch arm64 --product "$WORKER_NAME"
BUILD_BINARY="$(swift build -c release --arch arm64 --show-bin-path)/$SWIFT_PRODUCT_NAME"
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
ICON_SRC="$ROOT_DIR/Sources/NativeBolabol/Resources/AppIcon.icns"
if [[ ! -f "$ICON_SRC" ]]; then
  ICON_SRC="$WORKSPACE_ROOT/assets/icons/icon.icns"
fi
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$APP_RESOURCES/AppIcon.icns"
fi

APP_LOGOS="$APP_RESOURCES/Logos"
mkdir -p "$APP_LOGOS"
for svg_name in BOLABOL_LOGO.svg BOLABOL_LOGO_Full.svg BOLABOL_Wordmark.svg BOLABOL_status_bar_icon.svg; do
  svg_src="$ROOT_DIR/Sources/NativeBolabol/Resources/Logos/$svg_name"
  if [[ -f "$svg_src" ]]; then
    cp "$svg_src" "$APP_LOGOS/$svg_name"
  fi
done

# Ship the exact BOLABOL license inside the application bundle so
# Settings > License can display the controlling legal text offline.
LICENSE_SRC="$ROOT_DIR/Sources/NativeBolabol/Resources/BOLABOL_LICENSE.txt"
if [[ -f "$LICENSE_SRC" ]]; then
  cp "$LICENSE_SRC" "$APP_RESOURCES/BOLABOL_LICENSE.txt"
else
  echo "error: bundled BOLABOL license is missing: $LICENSE_SRC" >&2
  exit 1
fi

# Preserve third-party license notices for every SwiftPM checkout that
# participates in the build. This keeps binary redistribution notices
# alongside the app without maintaining a fragile hand-written list.
THIRD_PARTY_NOTICES="$APP_RESOURCES/THIRD_PARTY_NOTICES.txt"
{
  echo "BOLABOL Third-Party Notices"
  echo "Generated from the Swift Package Manager checkouts used for this build."
  echo
  for checkout in "$ROOT_DIR/.build/checkouts"/*; do
    [[ -d "$checkout" ]] || continue
    project_name="$(basename "$checkout")"
    while IFS= read -r license_file; do
      [[ -n "$license_file" ]] || continue
      echo "===============================================================================" 
      echo "$project_name / $(basename "$license_file")"
      echo "===============================================================================" 
      cat "$license_file"
      echo
    done < <(find "$checkout" -maxdepth 1 -type f       \( -iname 'LICENSE' -o -iname 'LICENSE.*' -o -iname 'COPYING' -o -iname 'COPYING.*' \)       -print | sort)
  done
} > "$THIRD_PARTY_NOTICES"

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
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Bolabol needs microphone access to record and transcribe speech.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Bolabol needs permission to paste transcribed text into the active app.</string>
</dict>
</plist>
PLIST

codesign_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "$CODESIGN_IDENTITY"
    return
  fi

  if /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/grep -q "\"$DEFAULT_DEVELOPER_ID_IDENTITY\""; then
    echo "$DEFAULT_DEVELOPER_ID_IDENTITY"
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

codesign_release() {
  local target="$1"
  local entitlements="${2:-}"

  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    if [[ -n "$entitlements" ]]; then
      /usr/bin/codesign --force --sign - --entitlements "$entitlements" "$target"
    else
      /usr/bin/codesign --force --sign - "$target"
    fi
    return
  fi

  if [[ -n "$entitlements" ]]; then
    /usr/bin/codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" --entitlements "$entitlements" "$target"
  else
    /usr/bin/codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$target"
  fi
}

embed_swift_runtime() {
  local xcode_swift62_rpath="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx"
  local framework_swift_library="@executable_path/../Frameworks/libswiftCompatibilitySpan.dylib"
  local executable

  echo "=== Embedding Swift runtime compatibility libraries ==="
  mkdir -p "$APP_FRAMEWORKS"
  while IFS= read -r swift_library; do
    [[ -z "$swift_library" ]] && continue
    cp "$swift_library" "$APP_FRAMEWORKS/"
  done < <(xcrun swift-stdlib-tool --print \
    --scan-executable "$APP_BINARY" \
    --scan-executable "$WORKER_BINARY" \
    --platform macosx | sort -u)

  for executable in "$APP_BINARY" "$WORKER_BINARY"; do
    if otool -L "$executable" | grep -q '@rpath/libswiftCompatibilitySpan.dylib'; then
      install_name_tool \
        -change '@rpath/libswiftCompatibilitySpan.dylib' \
        "$framework_swift_library" \
        "$executable"
    fi

    if otool -l "$executable" | grep -Fq "$xcode_swift62_rpath"; then
      install_name_tool -delete_rpath "$xcode_swift62_rpath" "$executable"
    fi
  done

  while IFS= read -r -d '' dylib; do
    codesign_release "$dylib"
  done < <(find "$APP_FRAMEWORKS" -type f -name '*.dylib' -print0)
}

embed_swift_runtime

echo "=== Codesigning App Bundle ($SIGN_IDENTITY) ==="
codesign_release "$WORKER_BINARY"
codesign_release "$MLX_METALLIB_DESTINATION"
codesign_release "$APP_BUNDLE" "$ENTITLEMENTS_FILE"

echo "=== Creating DMG package ==="
DMG_TEMP_DIR="$RELEASE_DIR/dmg_temp"
rm -rf "$DMG_TEMP_DIR"
mkdir -p "$DMG_TEMP_DIR"

# Copy App Bundle to temporary packaging directory
cp -R "$APP_BUNDLE" "$DMG_TEMP_DIR/"

# Create symlink to /Applications
ln -s /Applications "$DMG_TEMP_DIR/Applications"

# Output DMG path
OUTPUT_DMG="$DIST_DIR/BOLABOL.dmg"
rm -f "$OUTPUT_DMG" "$DIST_DIR/Bolabol.dmg"

echo "Creating raw DMG image..."
hdiutil create -fs HFS+ -srcfolder "$DMG_TEMP_DIR" -volname "$DISPLAY_NAME" -format UDRW "$DIST_DIR/temp.dmg"

echo "Compressing DMG image..."
hdiutil convert "$DIST_DIR/temp.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG"

# Clean up temporary images
rm -f "$DIST_DIR/temp.dmg"
rm -rf "$DMG_TEMP_DIR"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  echo "=== Codesigning DMG package ($SIGN_IDENTITY) ==="
  /usr/bin/codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUTPUT_DMG"
fi

# Optional: submit to Apple notarization when NOTARIZE=1 or --notarize is passed.
SHOULD_NOTARIZE="${NOTARIZE:-0}"
for arg in "$@"; do
  if [[ "$arg" == "--notarize" ]]; then
    SHOULD_NOTARIZE=1
  fi
done

if [[ "$SHOULD_NOTARIZE" == "1" ]]; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "error: cannot notarize an ad-hoc signed build" >&2
    exit 1
  fi
  echo "=== Notarizing DMG ==="
  "$ROOT_DIR/script/notarize_dmg.sh" "$OUTPUT_DMG"
fi

# Release handoff folder (checksums + install helper copy for recipients)
HANDOFF_DIR="$DIST_DIR/handoff"
mkdir -p "$HANDOFF_DIR"
cp "$OUTPUT_DMG" "$HANDOFF_DIR/BOLABOL.dmg"
cp "$ROOT_DIR/script/install.sh" "$HANDOFF_DIR/install.sh"
chmod +x "$HANDOFF_DIR/install.sh"
(
  cd "$HANDOFF_DIR"
  shasum -a 256 BOLABOL.dmg install.sh > SHA256SUMS.txt
)

echo "=== DMG successfully created at: $OUTPUT_DMG ==="
echo "    Version: $APP_VERSION ($APP_BUILD)"
echo "    Identity: $SIGN_IDENTITY"
echo "    Handoff: $HANDOFF_DIR"
ls -lh "$OUTPUT_DMG" "$HANDOFF_DIR/BOLABOL.dmg"
cat "$HANDOFF_DIR/SHA256SUMS.txt"
