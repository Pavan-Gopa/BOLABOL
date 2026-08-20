#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: verify_release_artifacts.sh VERSION BUILD_NUMBER [DIST_DIR]}"
BUILD_NUMBER="${2:?usage: verify_release_artifacts.sh VERSION BUILD_NUMBER [DIST_DIR]}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${3:-$ROOT_DIR/dist}"
BUNDLE_ID="com.vaniscript.apple-silicon"
TEAM_ID="438UQRF7JV"
DMG="$DIST_DIR/VaniScript-$VERSION.dmg"
GENERIC_DMG="$DIST_DIR/VaniScript.dmg"
ZIP="$DIST_DIR/VaniScript-$VERSION.zip"
GENERIC_ZIP="$DIST_DIR/VaniScript.zip"
MANIFEST="$DIST_DIR/VaniScript-$VERSION.manifest.json"
CHECKSUMS="$DIST_DIR/checksums.txt"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || { echo "error: invalid semantic version: $VERSION" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "error: invalid build number: $BUILD_NUMBER" >&2; exit 1; }
for artifact in "$GENERIC_DMG" "$DMG" "$ZIP" "$GENERIC_ZIP" "$MANIFEST" "$CHECKSUMS"; do
  [[ -s "$artifact" ]] || { echo "error: missing or empty release artifact: $artifact" >&2; exit 1; }
done

(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 -c "$(basename "$CHECKSUMS")"
)

manifest_value() {
  /usr/bin/plutil -extract "$1" raw -o - "$MANIFEST"
}

[[ "$(manifest_value schemaVersion)" == "1" ]] || { echo "error: unsupported manifest schema" >&2; exit 1; }
[[ "$(manifest_value bundleIdentifier)" == "$BUNDLE_ID" ]] || { echo "error: manifest bundle identifier mismatch" >&2; exit 1; }
[[ "$(manifest_value version)" == "$VERSION" ]] || { echo "error: manifest version mismatch" >&2; exit 1; }
[[ "$(manifest_value buildNumber)" == "$BUILD_NUMBER" ]] || { echo "error: manifest build number mismatch" >&2; exit 1; }
[[ "$(manifest_value minimumSystemVersion)" == "14.0" ]] || { echo "error: manifest minimum system version mismatch" >&2; exit 1; }
[[ "$(manifest_value architecture)" == "arm64" ]] || { echo "error: manifest architecture mismatch" >&2; exit 1; }
[[ "$(manifest_value artifacts.dmg.filename)" == "VaniScript.dmg" ]] || { echo "error: manifest DMG filename mismatch" >&2; exit 1; }
[[ "$(manifest_value artifacts.dmg.versionedFilename)" == "VaniScript-$VERSION.dmg" ]] || { echo "error: manifest versioned DMG filename mismatch" >&2; exit 1; }
[[ "$(manifest_value artifacts.updateZip.filename)" == "VaniScript-$VERSION.zip" ]] || { echo "error: manifest ZIP filename mismatch" >&2; exit 1; }
[[ "$(manifest_value artifacts.dmg.sha256)" == "$(/usr/bin/shasum -a 256 "$GENERIC_DMG" | /usr/bin/awk '{print $1}')" ]] || { echo "error: manifest DMG hash mismatch" >&2; exit 1; }
[[ "$(manifest_value artifacts.updateZip.sha256)" == "$(/usr/bin/shasum -a 256 "$ZIP" | /usr/bin/awk '{print $1}')" ]] || { echo "error: manifest ZIP hash mismatch" >&2; exit 1; }
/usr/bin/cmp -s "$GENERIC_DMG" "$DMG" || { echo "error: generic and versioned DMGs differ" >&2; exit 1; }

/usr/bin/codesign --verify --strict --verbose=2 "$GENERIC_DMG"
/usr/bin/codesign --verify --strict --verbose=2 "$DMG"
/usr/bin/xcrun stapler validate "$GENERIC_DMG"
/usr/bin/xcrun stapler validate "$DMG"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=4 "$GENERIC_DMG"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"

MOUNT_DIR="$(/usr/bin/mktemp -d)"
cleanup() {
  /usr/bin/hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  /bin/rm -rf "$MOUNT_DIR"
}
trap cleanup EXIT
/usr/bin/hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT_DIR" -quiet
APP="$MOUNT_DIR/VaniScript.app"
BINARY="$APP/Contents/MacOS/VaniScript"
[[ -x "$BINARY" ]] || { echo "error: mounted DMG does not contain VaniScript.app" >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/usr/sbin/spctl --assess --type execute --verbose=4 "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == "$BUNDLE_ID" ]] || { echo "error: app bundle identifier mismatch" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]] || { echo "error: app version mismatch" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$BUILD_NUMBER" ]] || { echo "error: app build number mismatch" >&2; exit 1; }
codesign_details="$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1)" && /usr/bin/grep -Fq "TeamIdentifier=$TEAM_ID" <<<"$codesign_details" || { echo "error: app TeamIdentifier mismatch" >&2; exit 1; }
[[ "$(/usr/bin/lipo -archs "$BINARY")" == "arm64" ]] || { echo "error: app executable is not arm64-only" >&2; exit 1; }
if /usr/bin/otool -L "$BINARY" | /usr/bin/grep -Eq '/Applications/Xcode|/DerivedData|/\.build/'; then
  echo "error: app executable has a local development dependency" >&2
  exit 1
fi
if /usr/bin/otool -l "$BINARY" | /usr/bin/grep -Eq '/Applications/Xcode|/DerivedData|/\.build/'; then
  echo "error: app executable has a local development rpath" >&2
  exit 1
fi

echo "Release artifacts verified: VaniScript $VERSION ($BUILD_NUMBER)"
