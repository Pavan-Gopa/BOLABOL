#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
SWIFT_PRODUCT_NAME="VaniScript"
APP_BUNDLE_NAME="VaniScript"
APP_EXECUTABLE_NAME="VaniScript"
BUNDLE_ID="com.vaniscript.apple-silicon"
MIN_SYSTEM_VERSION="14.0"
BUILD_ID="${VANISCRIPT_BUILD_ID:-$(date -u +%Y%m%d%H%M%S)}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_BUNDLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_MEDIA_BIN="$APP_BUNDLE/Contents/Resources/bin"
APP_BINARY="$APP_MACOS/$APP_EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
VENDOR_BIN="$ROOT_DIR/Vendor/bin"
APPLE_SILICON_ASSETS_DIR="$ROOT_DIR/Assets"
ELECTRON_ASSETS_DIR="${VANISCRIPT_ELECTRON_ASSETS_DIR:-$WORKSPACE_DIR/Electron/assets}"

cd "$ROOT_DIR"

pkill -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1 || true
pkill -x "VaniScriptAS" >/dev/null 2>&1 || true

swift build --arch arm64 --product "$SWIFT_PRODUCT_NAME"
BUILD_BINARY="$(swift build --arch arm64 --show-bin-path)/$SWIFT_PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
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
cp "$VENDOR_BIN/yt-dlp" "$APP_RESOURCES/bin/yt-dlp"
cp "$VENDOR_BIN/ffmpeg" "$APP_RESOURCES/bin/ffmpeg"
chmod 755 "$APP_RESOURCES/bin/yt-dlp" "$APP_RESOURCES/bin/ffmpeg"
/usr/bin/codesign --force --sign - "$APP_RESOURCES/bin/yt-dlp"
/usr/bin/codesign --force --sign - "$APP_RESOURCES/bin/ffmpeg"

# Build and bundle the pinned MLX Swift checkout's official Metal library.
MLX_SWIFT_CHECKOUT="$ROOT_DIR/.build/checkouts/mlx-swift"
MLX_SOURCE_DIR="$MLX_SWIFT_CHECKOUT/Source/Cmlx/mlx"
MLX_METAL_KERNELS_CMAKE="$MLX_SOURCE_DIR/mlx/backend/metal/kernels/CMakeLists.txt"
MLX_METALLIB_BUILD_DIR="$ROOT_DIR/.build/mlx-metallib"
MLX_METALLIB="$MLX_METALLIB_BUILD_DIR/mlx/backend/metal/kernels/mlx.metallib"

if [[ ! -f "$MLX_METAL_KERNELS_CMAKE" ]]; then
  echo "error: pinned mlx-swift checkout does not contain MLX's official Metal build definition: $MLX_METAL_KERNELS_CMAKE" >&2
  exit 1
fi

if ! CMAKE_BIN="$(command -v cmake)"; then
  echo "error: CMake is required to build MLX's Metal library." >&2
  exit 1
fi

if ! C_COMPILER_BIN="$(/usr/bin/xcrun --sdk macosx --find clang)"; then
  echo "error: the macOS C compiler is unavailable." >&2
  exit 1
fi

if ! CXX_COMPILER_BIN="$(/usr/bin/xcrun --sdk macosx --find clang++)"; then
  echo "error: the macOS C++ compiler is unavailable." >&2
  exit 1
fi

if ! METAL_COMPILER_BIN="$(/usr/bin/xcrun --sdk macosx --find metal)"; then
  echo "error: the macOS Metal compiler is unavailable." >&2
  exit 1
fi

if ! METALLIB_COMPILER_BIN="$(/usr/bin/xcrun --sdk macosx --find metallib)"; then
  echo "error: the macOS Metal library linker is unavailable." >&2
  exit 1
fi

if [[ ! -x "$CMAKE_BIN" || ! -x "$C_COMPILER_BIN" || ! -x "$CXX_COMPILER_BIN" || ! -x "$METAL_COMPILER_BIN" || ! -x "$METALLIB_COMPILER_BIN" ]]; then
  echo "error: the required MLX Metal build toolchain is not executable." >&2
  exit 1
fi

rm -rf "$MLX_METALLIB_BUILD_DIR"
"$CMAKE_BIN" \
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
"$CMAKE_BIN" --build "$MLX_METALLIB_BUILD_DIR" --target mlx-metallib --parallel

if [[ ! -f "$MLX_METALLIB" || ! -s "$MLX_METALLIB" ]]; then
  echo "error: MLX's official Metal build did not produce a non-empty library: $MLX_METALLIB" >&2
  exit 1
fi

install_mlx_metallib() {
  local destination="$1"

  cp "$MLX_METALLIB" "$destination"
  if [[ ! -s "$destination" ]] || ! /usr/bin/cmp -s "$MLX_METALLIB" "$destination"; then
    echo "error: failed to install MLX Metal library at: $destination" >&2
    exit 1
  fi
}

install_mlx_metallib "$APP_RESOURCES/mlx.metallib"
install_mlx_metallib "$APP_MACOS/mlx.metallib"

ARCHS="$(/usr/bin/lipo -archs "$APP_BINARY")"
if [[ "$ARCHS" != "arm64" ]]; then
  echo "error: $APP_BUNDLE_NAME must be Apple Silicon only. Found architectures: $ARCHS" >&2
  exit 1
fi

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

SPARKLE_FRAMEWORK_SRC="$ROOT_DIR/.build/arm64-apple-macosx/debug/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK_SRC" ]]; then
  SPARKLE_FRAMEWORK_SRC="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi
if [[ ! -d "$SPARKLE_FRAMEWORK_SRC" ]]; then
  echo "error: Sparkle.framework was not found in debug build artifacts." >&2
  exit 1
fi
/usr/bin/ditto "$SPARKLE_FRAMEWORK_SRC" "$APP_FRAMEWORKS/Sparkle.framework"
if ! /usr/bin/otool -l "$APP_BINARY" | /usr/bin/grep -Fq '@executable_path/../Frameworks'; then
  /usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
fi

FORBIDDEN_PATTERN='python|node|node_modules|electron|chromium|llama|llamacpp'
if (cd "$APP_BUNDLE" && /usr/bin/find . -print | /usr/bin/grep -Eiq "$FORBIDDEN_PATTERN"); then
  echo "error: $APP_BUNDLE_NAME.app contains non-native runtime artifacts:" >&2
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
    pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_EXECUTABLE_NAME\""
    ;;
  *)
    echo "usage: $0 [run|--verify|--logs]" >&2
    exit 2
    ;;
esac
