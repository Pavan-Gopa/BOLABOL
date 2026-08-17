#!/usr/bin/env bash
set -euo pipefail

SWIFT_PRODUCT_NAME="NativeBolabol"
APP_NAME="Bolabol"
DISPLAY_NAME="Bolabol"
BUNDLE_ID="com.bolabol.app"
MIN_SYSTEM_VERSION="14.0"
# Marketing / build versions embedded in Info.plist (override with env).
APP_VERSION="${APP_VERSION:-1.0.5}"
APP_BUILD="${APP_BUILD:-$(date +%Y%m%d%H%M)}"
SU_FEED_URL="${SU_FEED_URL:-https://raw.githubusercontent.com/Pavan-Gopa/BOLABOL/main/Bolabol/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
RELEASE_BUILD="${RELEASE_BUILD:-0}"

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

# Parse command line flags
SHOULD_NOTARIZE="${NOTARIZE:-0}"
for arg in "$@"; do
  case "$arg" in
    --notarize)
      SHOULD_NOTARIZE="1"
      ;;
    --release)
      RELEASE_BUILD="1"
      ;;
  esac
done

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
  local xcode_developer_dir
  xcode_developer_dir="$(xcode-select -p 2>/dev/null || true)"
  local metal_version
  metal_version="$(xcrun metal --version 2>/dev/null | head -n 1 || true)"
  echo "$xcode_developer_dir | $metal_version"
}

build_mlx_metallib() {
  if [[ ! -d "$MLX_CHECKOUT" ]]; then
    echo "warning: mlx-swift checkout not found at $MLX_CHECKOUT. Skipping mlx.metallib compilation."
    return
  fi

  local metallib_generator="$MLX_CHECKOUT/generate_metallib.sh"
  if [[ ! -f "$metallib_generator" ]]; then
    echo "warning: generate_metallib.sh not found in $MLX_CHECKOUT. Skipping mlx.metallib compilation."
    return
  fi

  local marker_file="$MLX_METAL_BUILD_DIR/.metal_toolchain"
  local current_toolchain
  current_toolchain="$(metal_toolchain_id)"
  local cached_toolchain=""
  if [[ -f "$marker_file" ]]; then
    cached_toolchain="$(cat "$marker_file" 2>/dev/null || true)"
  fi

  if [[ -f "$MLX_METALLIB_SOURCE" && "$cached_toolchain" == "$current_toolchain" ]]; then
    echo "=== Reusing cached mlx.metallib from $MLX_METALLIB_SOURCE ==="
    return
  fi

  echo "=== Compiling native MLX metal kernels for release bundle ==="
  mkdir -p "$MLX_METAL_BUILD_DIR"
  rm -f "$MLX_METALLIB_SOURCE"

  local build_log="$MLX_METAL_BUILD_DIR/build.log"
  if ! bash "$metallib_generator" "$MLX_METAL_BUILD_DIR" >"$build_log" 2>&1; then
    echo "warning: failed to build mlx.metallib. Build output:"
    cat "$build_log"
    return
  fi

  if [[ -f "$MLX_METALLIB_SOURCE" ]]; then
    echo "$current_toolchain" >"$marker_file"
    echo "=== mlx.metallib built successfully at $MLX_METALLIB_SOURCE ==="
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
if [[ -f "$MLX_METALLIB_SOURCE" ]]; then
  cp "$MLX_METALLIB_SOURCE" "$MLX_METALLIB_DESTINATION"
fi
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
  <key>SUFeedURL</key>
  <string>$SU_FEED_URL</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>21600</integer>
  <key>SUAutomaticallyUpdate</key>
  <true/>
  <key>SURequireSignedFeed</key>
  <true/>
  <key>SUVerifyUpdateBeforeExtraction</key>
  <true/>
$(if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then echo "  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>"; fi)
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

# Fail-closed checks for official release mode
if [[ "$RELEASE_BUILD" == "1" ]]; then
  echo "=== Verifying RELEASE_BUILD=1 Fail-Closed Gates ==="
  if [[ "$SIGN_IDENTITY" == "-" || ! "$SIGN_IDENTITY" =~ "Developer ID Application" ]]; then
    echo "Error: RELEASE_BUILD=1 requires a valid Developer ID Application signing identity, got: '$SIGN_IDENTITY'." >&2
    exit 1
  fi
  if [[ "$SHOULD_NOTARIZE" != "1" ]]; then
    echo "Error: RELEASE_BUILD=1 requires NOTARIZE=1 / --notarize." >&2
    exit 1
  fi
  if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "Error: RELEASE_BUILD=1 requires non-empty SPARKLE_PUBLIC_ED_KEY." >&2
    exit 1
  fi
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
  mkdir -p "$APP_FRAMEWORKS"

  local swift_library
  swift_library="$(xcrun swift-stdlib-tool --print 2>/dev/null | grep 'libswiftCompatibilitySpan.dylib' | head -n 1 || true)"
  if [[ -n "$swift_library" && -f "$swift_library" ]]; then
    echo "=== Embedding Swift 6.2 compatibility runtime: $(basename "$swift_library") ==="
    cp "$swift_library" "$APP_FRAMEWORKS/"
    install_name_tool -id "@executable_path/../Frameworks/libswiftCompatibilitySpan.dylib" "$APP_FRAMEWORKS/libswiftCompatibilitySpan.dylib" 2>/dev/null || true
  fi

  local xcode_developer_dir
  xcode_developer_dir="$(xcode-select -p 2>/dev/null || true)"
  local xcode_swift62_rpath="$xcode_developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx"

  for bin in "$APP_BINARY" "$WORKER_BINARY"; do
    if [[ -f "$bin" ]]; then
      install_name_tool -add_rpath "@executable_path/../Frameworks" "$bin" 2>/dev/null || true
      if [[ -n "$xcode_developer_dir" ]]; then
        install_name_tool -delete_rpath "$xcode_swift62_rpath" "$bin" 2>/dev/null || true
      fi
    fi
  done

  while IFS= read -r -d '' dylib; do
    codesign_release "$dylib"
  done < <(find "$APP_FRAMEWORKS" -type f -name '*.dylib' -print0)
}

embed_sparkle_framework() {
  local sparkle_framework_src
  sparkle_framework_src="$(find "$ROOT_DIR/.build" -name "Sparkle.framework" -type d | grep "macos-arm64_x86_64" | head -n 1 || true)"
  if [[ -z "$sparkle_framework_src" ]]; then
    sparkle_framework_src="$(find "$ROOT_DIR/.build" -name "Sparkle.framework" -type d | head -n 1 || true)"
  fi

  if [[ -z "$sparkle_framework_src" || ! -d "$sparkle_framework_src" ]]; then
    if [[ "$RELEASE_BUILD" == "1" ]]; then
      echo "Error: Exact Sparkle.framework not found in build directory." >&2
      exit 1
    else
      echo "warning: Sparkle.framework not found in build directory."
      return
    fi
  fi

  echo "=== Embedding Sparkle framework from $sparkle_framework_src using ditto ==="
  mkdir -p "$APP_FRAMEWORKS"
  rm -rf "$APP_FRAMEWORKS/Sparkle.framework"
  /usr/bin/ditto "$sparkle_framework_src" "$APP_FRAMEWORKS/Sparkle.framework"

  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY" 2>/dev/null || true

  # Fail closed if binary is not linked against Sparkle
  if ! otool -L "$APP_BINARY" 2>/dev/null | grep -q "Sparkle.framework"; then
    echo "Error: NativeBolabol binary is not linked against Sparkle.framework." >&2
    exit 1
  fi

  echo "=== Codesigning Sparkle framework inside-out ==="
  if [[ -d "$APP_FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices" ]]; then
    for xpc in "$APP_FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices/"*.xpc; do
      if [[ -d "$xpc" ]]; then
        codesign_release "$xpc"
      fi
    done
  fi
  if [[ -f "$APP_FRAMEWORKS/Sparkle.framework/Versions/B/Autoupdate" ]]; then
    codesign_release "$APP_FRAMEWORKS/Sparkle.framework/Versions/B/Autoupdate"
  fi
  if [[ -d "$APP_FRAMEWORKS/Sparkle.framework/Versions/B/Updater.app" ]]; then
    codesign_release "$APP_FRAMEWORKS/Sparkle.framework/Versions/B/Updater.app"
  fi
  codesign_release "$APP_FRAMEWORKS/Sparkle.framework/Versions/B"
}

embed_sparkle_framework

embed_swift_runtime

echo "=== Codesigning App Bundle ($SIGN_IDENTITY) ==="
codesign_release "$WORKER_BINARY"
if [[ -f "$MLX_METALLIB_DESTINATION" ]]; then
  codesign_release "$MLX_METALLIB_DESTINATION"
fi
codesign_release "$APP_BUNDLE" "$ENTITLEMENTS_FILE"

echo "=== Creating DMG package ==="
DMG_TEMP_DIR="$RELEASE_DIR/dmg_temp"
rm -rf "$DMG_TEMP_DIR"
mkdir -p "$DMG_TEMP_DIR"

# Copy App Bundle to temporary packaging directory using ditto to preserve symlinks and permissions
/usr/bin/ditto "$APP_BUNDLE" "$DMG_TEMP_DIR/$APP_NAME.app"

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
  echo "=== Signing DMG package ($SIGN_IDENTITY) ==="
  /usr/bin/codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUTPUT_DMG"
fi

if [[ "$SHOULD_NOTARIZE" == "1" ]]; then
  echo "=== Submitting DMG to Apple Notary Service ==="
  if [[ -f "$ROOT_DIR/script/notarize_dmg.sh" ]]; then
    bash "$ROOT_DIR/script/notarize_dmg.sh" "$OUTPUT_DMG"
  else
    echo "Error: script/notarize_dmg.sh not found but NOTARIZE=1 was requested." >&2
    exit 1
  fi
fi

# Release handoff folder (checksums + install helper copy for recipients)
HANDOFF_DIR="$DIST_DIR/handoff"
mkdir -p "$HANDOFF_DIR"
cp "$OUTPUT_DMG" "$HANDOFF_DIR/BOLABOL.dmg"
if [[ -f "$ROOT_DIR/script/install.sh" ]]; then
  cp "$ROOT_DIR/script/install.sh" "$HANDOFF_DIR/install.sh"
  chmod +x "$HANDOFF_DIR/install.sh"
fi
(
  cd "$HANDOFF_DIR"
  shasum -a 256 "BOLABOL.dmg" > "SHA256SUMS.txt"
)

echo "=== DMG successfully created at: $OUTPUT_DMG ==="
echo "    Version: $APP_VERSION ($APP_BUILD)"
echo "    Identity: $SIGN_IDENTITY"
echo "    Handoff: $HANDOFF_DIR"
ls -lh "$OUTPUT_DMG" "$HANDOFF_DIR/BOLABOL.dmg"
cat "$HANDOFF_DIR/SHA256SUMS.txt"
