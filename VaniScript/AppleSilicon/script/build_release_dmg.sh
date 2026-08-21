#!/usr/bin/env bash
set -euo pipefail

SWIFT_PRODUCT_NAME="VaniScript"
APP_BUNDLE_NAME="VaniScript"
APP_EXECUTABLE_NAME="VaniScript"
BUNDLE_ID="com.vaniscript.apple-silicon"
MIN_SYSTEM_VERSION="14.0"
DEFAULT_DEVELOPER_ID_IDENTITY="Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV)"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_BUNDLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_MEDIA_BIN="$APP_RESOURCES/bin"
APP_BINARY="$APP_MACOS/$APP_EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS_FILE="$ROOT_DIR/script/release.entitlements"
VENDOR_BIN="$ROOT_DIR/Vendor/bin"
APPLE_SILICON_ASSETS_DIR="$ROOT_DIR/Assets"
ELECTRON_ASSETS_DIR="${VANISCRIPT_ELECTRON_ASSETS_DIR:-$WORKSPACE_DIR/Electron/assets}"

# Parse optional arguments
DEBUG_MODE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      DEBUG_MODE=1
      shift
      ;;
    --version)
      VANISCRIPT_VERSION="$2"
      shift 2
      ;;
    --build-number)
      VANISCRIPT_BUILD_NUMBER="$2"
      shift 2
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "${VANISCRIPT_DEBUG_PACKAGING:-0}" == "1" || "${ALLOW_ADHOC_SIGNING:-0}" == "1" ]]; then
  DEBUG_MODE=1
fi


# Semantic Version validation (SemVer X.Y.Z or X.Y.Z-prerelease)
VERSION="${VANISCRIPT_VERSION:-1.0.0}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "error: VANISCRIPT_VERSION must be a valid semantic version (e.g. 1.0.0). Found: '$VERSION'" >&2
  exit 1
fi

# Strict numeric build number validation
BUILD_NUMBER="${VANISCRIPT_BUILD_NUMBER:-${VANISCRIPT_BUILD_ID:-}}"
if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(date -u +%Y%m%d%H%M%S)"
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "error: VANISCRIPT_BUILD_NUMBER must be a strictly numeric string (e.g. 100 or $(date -u +%Y%m%d%H%M%S)). Found: '$BUILD_NUMBER'" >&2
  exit 1
fi

cd "$ROOT_DIR"

echo "=== Release Configuration ==="
echo "App Name:         $APP_BUNDLE_NAME"
echo "Bundle ID:        $BUNDLE_ID"
echo "Semantic Version: $VERSION"
echo "Build Number:     $BUILD_NUMBER"
echo "Debug Mode:       $DEBUG_MODE"

echo "=== Resolving Codesigning Identity ==="
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

  /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/awk -F '"' '/Developer ID Application/ { print $2; exit }'
}

SIGN_IDENTITY="$(codesign_identity)"
if [[ -z "$SIGN_IDENTITY" ]]; then
  if [[ "$DEBUG_MODE" -ne 1 ]]; then
    echo "error: production release packaging requires a valid Developer ID Application codesigning identity." >&2
    echo "No Developer ID Application identity found in keychain." >&2
    echo "For local debug packaging without Developer ID, pass --debug or set VANISCRIPT_DEBUG_PACKAGING=1." >&2
    exit 1
  fi
  echo "warning: no Developer ID Application identity found; using ad-hoc signing for debug packaging." >&2
  SIGN_IDENTITY="-"
fi

if [[ "$SIGN_IDENTITY" == "-" && "$DEBUG_MODE" -ne 1 ]]; then
  echo "error: ad-hoc signing ('-') is not permitted for production release packaging." >&2
  echo "Production release packaging requires a valid Developer ID Application codesigning identity." >&2
  echo "For local debug packaging without Developer ID, pass --debug or set VANISCRIPT_DEBUG_PACKAGING=1." >&2
  exit 1
fi
if [[ "$DEBUG_MODE" -ne 1 && -z "${VANISCRIPT_SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  echo "error: production release packaging requires VANISCRIPT_SPARKLE_PUBLIC_ED_KEY before signing." >&2
  exit 1
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

echo "=== Cleaning up existing processes ==="
pkill -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1 || true
pkill -x "VaniScriptAS" >/dev/null 2>&1 || true

echo "=== Building $APP_BUNDLE_NAME in Release configuration ==="
swift build -c release --arch arm64 --product "$SWIFT_PRODUCT_NAME"
BUILD_BINARY="$(swift build -c release --arch arm64 --show-bin-path)/$SWIFT_PRODUCT_NAME"

echo "=== Preparing Release App Bundle ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

copy_required_asset() {
  local source="$1"
  local target="$2"

  if [[ ! -f "$source" ]]; then
    echo "error: required app asset is missing: $source" >&2
    if [[ "$source" == "$ELECTRON_ASSETS_DIR"* ]]; then
      echo "Set VANISCRIPT_ELECTRON_ASSETS_DIR to the folder containing icon.icns and icon.png." >&2
    fi
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

copy_required_asset "$APPLE_SILICON_ASSETS_DIR/AppIconAS.icns" "$APP_RESOURCES/AppIcon.icns"
copy_required_asset "$APPLE_SILICON_ASSETS_DIR/AppIconAS.png" "$APP_RESOURCES/AppIcon.png"
copy_required_asset "$APPLE_SILICON_ASSETS_DIR/VaniScript_Logo.svg" "$APP_RESOURCES/VaniScript_Logo.svg"

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
cp "$VENDOR_BIN/yt-dlp" "$APP_MEDIA_BIN/yt-dlp"
cp "$VENDOR_BIN/ffmpeg" "$APP_MEDIA_BIN/ffmpeg"
chmod 755 "$APP_MEDIA_BIN/yt-dlp" "$APP_MEDIA_BIN/ffmpeg"

# Pinned MLX Swift Metal library bundling
MLX_SWIFT_CHECKOUT="$ROOT_DIR/.build/checkouts/mlx-swift"
MLX_SOURCE_DIR="$MLX_SWIFT_CHECKOUT/Source/Cmlx/mlx"
MLX_METALLIB_BUILD_DIR="$ROOT_DIR/.build/mlx-metallib"
MLX_METALLIB="$MLX_METALLIB_BUILD_DIR/mlx/backend/metal/kernels/mlx.metallib"

if [[ ! -f "$MLX_METALLIB" || ! -s "$MLX_METALLIB" ]]; then
  echo "=== Building MLX Metal library from pinned checkout ==="
  if [[ ! -d "$MLX_SOURCE_DIR" ]]; then
    echo "error: pinned mlx-swift checkout not found at $MLX_SWIFT_CHECKOUT." >&2
    echo "Run 'swift package resolve' to populate dependencies." >&2
    exit 1
  fi
  if ! command -v cmake >/dev/null 2>&1; then
    echo "error: CMake is required to build MLX's Metal library." >&2
    exit 1
  fi
  C_COMPILER_BIN="$(/usr/bin/xcrun --sdk macosx --find clang 2>/dev/null || true)"
  CXX_COMPILER_BIN="$(/usr/bin/xcrun --sdk macosx --find clang++ 2>/dev/null || true)"
  METAL_COMPILER_BIN="$(/usr/bin/xcrun --sdk macosx --find metal 2>/dev/null || true)"
  METALLIB_COMPILER_BIN="$(/usr/bin/xcrun --sdk macosx --find metallib 2>/dev/null || true)"
  if [[ -z "$C_COMPILER_BIN" || -z "$CXX_COMPILER_BIN" || -z "$METAL_COMPILER_BIN" || -z "$METALLIB_COMPILER_BIN" ]]; then
    echo "error: required Xcode Metal/Clang build toolchain is missing." >&2
    exit 1
  fi

  rm -rf "$MLX_METALLIB_BUILD_DIR"
  cmake \
    -S "$MLX_SOURCE_DIR" \
    -B "$MLX_METALLIB_BUILD_DIR" \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_C_COMPILER="$C_COMPILER_BIN" \
    -D CMAKE_CXX_COMPILER="$CXX_COMPILER_BIN" \
    -D CMAKE_OSX_ARCHITECTURES=arm64 \
    -D CMAKE_OSX_DEPLOYMENT_TARGET="$MIN_SYSTEM_VERSION" \
    -D FETCHCONTENT_FULLY_DISCONNECTED=ON \
    -D "FETCHCONTENT_SOURCE_DIR_METAL_CPP=$MLX_SWIFT_CHECKOUT/Source/Cmlx/metal-cpp" \
    -D "FETCHCONTENT_SOURCE_DIR_JSON=$MLX_SWIFT_CHECKOUT/Source/Cmlx/json" \
    -D "FETCHCONTENT_SOURCE_DIR_FMT=$MLX_SWIFT_CHECKOUT/Source/Cmlx/fmt" \
    -D MLX_BUILD_METAL=ON \
    -D MLX_METAL_JIT=OFF \
    -D MLX_BUILD_CPU=OFF \
    -D MLX_BUILD_CUDA=OFF \
    -D MLX_BUILD_TESTS=OFF \
    -D MLX_BUILD_EXAMPLES=OFF \
    -D MLX_BUILD_BENCHMARKS=OFF \
    -D MLX_BUILD_PYTHON_BINDINGS=OFF \
    -D MLX_BUILD_GGUF=OFF \
    -D MLX_BUILD_SAFETENSORS=OFF \
    -D MLX_USE_CCACHE=OFF
  cmake --build "$MLX_METALLIB_BUILD_DIR" --target mlx-metallib --parallel
fi

if [[ ! -f "$MLX_METALLIB" || ! -s "$MLX_METALLIB" ]]; then
  echo "error: MLX Metal library build failed or produced empty file: $MLX_METALLIB" >&2
  exit 1
fi

echo "Bundling precompiled MLX Metal library from: $MLX_METALLIB"
cp "$MLX_METALLIB" "$APP_RESOURCES/mlx.metallib"
cp "$MLX_METALLIB" "$APP_MACOS/mlx.metallib"

ARCHS="$(/usr/bin/lipo -archs "$APP_BINARY")"
if [[ "$ARCHS" != "arm64" ]]; then
  echo "error: $APP_BUNDLE_NAME must be Apple Silicon only. Found architectures: $ARCHS" >&2
  exit 1
fi

echo "=== Generating Info.plist ==="
cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_BUNDLE_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_BUNDLE_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>VaniScriptBuildID</key>
  <string>$BUILD_NUMBER</string>
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
  <key>SUFeedURL</key>
  <string>https://github.com/Pavan-Gopa/VaniScript/releases/latest/download/appcast.xml</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <false/>
</dict>
</plist>
PLIST

if [[ -n "${VANISCRIPT_SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  echo "Injecting SUPublicEDKey into Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $VANISCRIPT_SPARKLE_PUBLIC_ED_KEY" "$INFO_PLIST"
fi
FORBIDDEN_PATTERN='python|node|node_modules|electron|chromium|llama|llamacpp'
if (cd "$APP_BUNDLE" && /usr/bin/find . -print | /usr/bin/grep -Eiq "$FORBIDDEN_PATTERN"); then
  echo "error: $APP_BUNDLE_NAME.app contains non-native runtime artifacts:" >&2
  (cd "$APP_BUNDLE" && /usr/bin/find . -print | /usr/bin/grep -Ei "$FORBIDDEN_PATTERN") >&2
  exit 1
fi

echo "=== Embedding Sparkle.framework ==="
SPARKLE_FRAMEWORK_SRC=""
if [[ -d "$ROOT_DIR/.build/arm64-apple-macosx/release/Sparkle.framework" ]]; then
  SPARKLE_FRAMEWORK_SRC="$ROOT_DIR/.build/arm64-apple-macosx/release/Sparkle.framework"
elif [[ -d "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" ]]; then
  SPARKLE_FRAMEWORK_SRC="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
else
  FOUND_SPARKLE="$(find "$ROOT_DIR/.build" -type d -name "Sparkle.framework" 2>/dev/null | head -n 1)"
  if [[ -n "$FOUND_SPARKLE" ]]; then
    SPARKLE_FRAMEWORK_SRC="$FOUND_SPARKLE"
  fi
fi

if [[ -z "$SPARKLE_FRAMEWORK_SRC" || ! -d "$SPARKLE_FRAMEWORK_SRC" ]]; then
  echo "error: Sparkle.framework was not found in build artifacts. Ensure 'swift build -c release' succeeded." >&2
  exit 1
fi

rm -rf "$APP_FRAMEWORKS/Sparkle.framework"
ditto "$SPARKLE_FRAMEWORK_SRC" "$APP_FRAMEWORKS/Sparkle.framework"

# Ensure binary resolves @executable_path/../Frameworks
if ! otool -l "$APP_BINARY" | grep -Fq '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
fi

embed_swift_runtime() {
  local xcode_swift62_rpath="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx"
  local framework_swift_library="@executable_path/../Frameworks/libswiftCompatibilitySpan.dylib"
  local executable="$APP_BINARY"

  echo "=== Embedding Swift runtime compatibility libraries ==="
  mkdir -p "$APP_FRAMEWORKS"
  while IFS= read -r swift_library; do
    [[ -z "$swift_library" ]] && continue
    cp "$swift_library" "$APP_FRAMEWORKS/"
  done < <(xcrun swift-stdlib-tool --print \
    --scan-executable "$executable" \
    --platform macosx | sort -u)

  if otool -L "$executable" | grep -q '@rpath/libswiftCompatibilitySpan.dylib'; then
    install_name_tool \
      -change '@rpath/libswiftCompatibilitySpan.dylib' \
      "$framework_swift_library" \
      "$executable"
  fi

  if otool -l "$executable" | grep -Fq "$xcode_swift62_rpath"; then
    install_name_tool -delete_rpath "$xcode_swift62_rpath" "$executable"
  fi

  while IFS= read -r -d '' dylib; do
    codesign_release "$dylib"
  done < <(find "$APP_FRAMEWORKS" -type f -name '*.dylib' -print0)
}

embed_swift_runtime

echo "=== Codesigning App Bundle ($SIGN_IDENTITY) ==="
codesign_release "$APP_MEDIA_BIN/yt-dlp"
codesign_release "$APP_MEDIA_BIN/ffmpeg"
if [[ -f "$APP_RESOURCES/mlx.metallib" ]]; then
  codesign_release "$APP_RESOURCES/mlx.metallib"
fi
if [[ -f "$APP_MACOS/mlx.metallib" ]]; then
  codesign_release "$APP_MACOS/mlx.metallib"
fi

# Codesign Sparkle framework nested components inside-out
if [[ -d "$APP_FRAMEWORKS/Sparkle.framework/Versions/Current/XPCServices" ]]; then
  for xpc in "$APP_FRAMEWORKS/Sparkle.framework/Versions/Current/XPCServices/"*.xpc; do
    if [[ -d "$xpc" ]]; then
      codesign_release "$xpc"
    fi
  done
fi
if [[ -f "$APP_FRAMEWORKS/Sparkle.framework/Versions/Current/Autoupdate" ]]; then
  codesign_release "$APP_FRAMEWORKS/Sparkle.framework/Versions/Current/Autoupdate"
fi
if [[ -d "$APP_FRAMEWORKS/Sparkle.framework/Versions/Current/Updater.app" ]]; then
  codesign_release "$APP_FRAMEWORKS/Sparkle.framework/Versions/Current/Updater.app"
fi
codesign_release "$APP_FRAMEWORKS/Sparkle.framework"

codesign_release "$APP_BUNDLE" "$ENTITLEMENTS_FILE"

echo "=== Verifying App Bundle signature ==="
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "=== Creating DMG package ==="
mkdir -p "$DIST_DIR"
DMG_TEMP_DIR="$RELEASE_DIR/dmg_temp"
rm -rf "$DMG_TEMP_DIR"
mkdir -p "$DMG_TEMP_DIR"
cp -R "$APP_BUNDLE" "$DMG_TEMP_DIR/"
ln -s /Applications "$DMG_TEMP_DIR/Applications"

OUTPUT_DMG="$DIST_DIR/VaniScript.dmg"
VERSIONED_DMG="$DIST_DIR/VaniScript-$VERSION.dmg"
rm -f "$OUTPUT_DMG" "$VERSIONED_DMG" "$DIST_DIR/temp.dmg"

hdiutil create -fs HFS+ -srcfolder "$DMG_TEMP_DIR" -volname "$APP_BUNDLE_NAME" -format UDRW "$DIST_DIR/temp.dmg"
hdiutil convert "$DIST_DIR/temp.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG"
rm -f "$DIST_DIR/temp.dmg"
rm -rf "$DMG_TEMP_DIR"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  echo "=== Codesigning DMG package ($SIGN_IDENTITY) ==="
  /usr/bin/codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUTPUT_DMG"
fi

NOTARIZE_REQUESTED="${VANISCRIPT_NOTARIZE:-${NOTARIZE:-0}}"
if [[ "$DEBUG_MODE" -ne 1 ]]; then
  NOTARIZE_REQUESTED=1
fi

if [[ "$NOTARIZE_REQUESTED" == "1" ]]; then
  echo "=== Notarizing Final Signed DMG ==="
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "error: cannot notarize an ad-hoc signed release." >&2
    exit 1
  fi

  NOTARY_ARGS=()
  NOTARY_PROFILE="${KEYCHAIN_PROFILE:-${NOTARY_KEYCHAIN_PROFILE:-}}"
  if [[ -n "$NOTARY_PROFILE" ]]; then
    NOTARY_ARGS+=(--keychain-profile "$NOTARY_PROFILE")
  elif [[ -n "${APPLE_API_KEY_PATH:-}" && -n "${APPLE_API_KEY_ID:-}" ]]; then
    NOTARY_ARGS+=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID")
    if [[ -n "${APPLE_API_ISSUER:-}" ]]; then
      NOTARY_ARGS+=(--issuer "$APPLE_API_ISSUER")
    fi
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_PASSWORD:-${APPLE_ID_PASSWORD:-}}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    NOTARY_ARGS+=(--apple-id "$APPLE_ID" --password "${APPLE_PASSWORD:-${APPLE_ID_PASSWORD:-}}" --team-id "$APPLE_TEAM_ID")
  else
    echo "error: notarization credentials missing. Set KEYCHAIN_PROFILE/NOTARY_KEYCHAIN_PROFILE, Apple API-key inputs, or APPLE_ID, APPLE_PASSWORD, and APPLE_TEAM_ID." >&2
    exit 1
  fi

  NOTARY_RESULT="$(mktemp)"
  trap 'rm -f "$NOTARY_RESULT"' EXIT
  /usr/bin/xcrun notarytool submit "$OUTPUT_DMG" "${NOTARY_ARGS[@]}" --wait --output-format plist >"$NOTARY_RESULT"
  NOTARY_STATUS="$(/usr/libexec/PlistBuddy -c 'Print :status' "$NOTARY_RESULT" 2>/dev/null || true)"
  if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
    echo "error: Apple notarization did not accept the final DMG (status: ${NOTARY_STATUS:-unknown})." >&2
    exit 1
  fi
  rm -f "$NOTARY_RESULT"
  trap - EXIT

  echo "=== Stapling and Validating Final DMG ==="
  /usr/bin/xcrun stapler staple "$OUTPUT_DMG"
  /usr/bin/xcrun stapler validate "$OUTPUT_DMG"
  /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=4 "$OUTPUT_DMG"
elif [[ "$DEBUG_MODE" -ne 1 ]]; then
  echo "error: production release packaging requires notarization and stapling." >&2
  exit 1
fi

/usr/bin/ditto "$OUTPUT_DMG" "$VERSIONED_DMG"
if [[ "$NOTARIZE_REQUESTED" == "1" ]]; then
  /usr/bin/xcrun stapler validate "$VERSIONED_DMG"
  /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=4 "$VERSIONED_DMG"
fi

echo "=== Creating Sparkle Update ZIP package ==="
OUTPUT_ZIP="$DIST_DIR/VaniScript-$VERSION.zip"
GENERIC_ZIP="$DIST_DIR/VaniScript.zip"
rm -f "$OUTPUT_ZIP" "$GENERIC_ZIP"

# Create self-contained arm64 update ZIP preserving resource forks and symlinks
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$OUTPUT_ZIP"
ln -sf "$(basename "$OUTPUT_ZIP")" "$GENERIC_ZIP"

echo "=== Generating Release Manifest and Checksums ==="
DMG_SHA256="$(shasum -a 256 "$OUTPUT_DMG" | awk '{print $1}')"
DMG_SIZE="$(stat -f%z "$OUTPUT_DMG" 2>/dev/null || wc -c < "$OUTPUT_DMG" | tr -d ' ')"

ZIP_SHA256="$(shasum -a 256 "$OUTPUT_ZIP" | awk '{print $1}')"
ZIP_SIZE="$(stat -f%z "$OUTPUT_ZIP" 2>/dev/null || wc -c < "$OUTPUT_ZIP" | tr -d ' ')"

MANIFEST_FILE="$DIST_DIR/VaniScript-$VERSION.manifest.json"
cat >"$MANIFEST_FILE" <<MANIFEST
{
  "schemaVersion": 1,
  "bundleIdentifier": "$BUNDLE_ID",
  "version": "$VERSION",
  "buildNumber": "$BUILD_NUMBER",
  "minimumSystemVersion": "$MIN_SYSTEM_VERSION",
  "architecture": "arm64",
  "artifacts": {
    "dmg": {
      "filename": "$(basename "$OUTPUT_DMG")",
      "versionedFilename": "$(basename "$VERSIONED_DMG")",
      "sha256": "$DMG_SHA256",
      "size": $DMG_SIZE
    },
    "updateZip": {
      "filename": "$(basename "$OUTPUT_ZIP")",
      "genericFilename": "$(basename "$GENERIC_ZIP")",
      "sha256": "$ZIP_SHA256",
      "size": $ZIP_SIZE
    }
  }
}
MANIFEST

CHECKSUMS_FILE="$DIST_DIR/checksums.txt"
(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$OUTPUT_DMG")" "$(basename "$VERSIONED_DMG")" "$(basename "$OUTPUT_ZIP")" "$(basename "$GENERIC_ZIP")" "$(basename "$MANIFEST_FILE")" > "$CHECKSUMS_FILE"
)

echo "=== Release Artifacts Generated Successfully ==="
echo "DMG:        $OUTPUT_DMG ($DMG_SIZE bytes, SHA-256: $DMG_SHA256)"
echo "Update ZIP: $OUTPUT_ZIP ($ZIP_SIZE bytes, SHA-256: $ZIP_SHA256)"
echo "Manifest:   $MANIFEST_FILE"
echo "Checksums:  $CHECKSUMS_FILE"
