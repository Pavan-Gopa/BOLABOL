#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

if [[ $# -lt 2 ]]; then
  echo "Error: Both DMG path and Appcast XML path arguments are required." >&2
  echo "Usage: check_updater_release.sh <path-to-dmg> <path-to-appcast.xml>" >&2
  exit 1
fi

DMG_PATH="$1"
APPCAST_PATH="$2"

if [[ -z "$DMG_PATH" ]]; then
  echo "Error: Release DMG path argument is required." >&2
  exit 1
fi

if [[ -z "$APPCAST_PATH" ]]; then
  echo "Error: Appcast XML path argument is required." >&2
  exit 1
fi
echo "=== Bolabol Updater Release Verification ==="
echo "Target DMG: $DMG_PATH"

# 1. Validate DMG file presence
if [[ ! -f "$DMG_PATH" ]]; then
  echo "Error: Release DMG '$DMG_PATH' not found." >&2
  exit 1
fi

if [[ ! -f "$APPCAST_PATH" ]]; then
  echo "Error: Appcast XML file '$APPCAST_PATH' not found." >&2
  exit 1
fi

DMG_SIZE="$(stat -f%z "$DMG_PATH" 2>/dev/null || wc -c < "$DMG_PATH" | tr -d ' ')"
if [[ -z "$DMG_SIZE" || "$DMG_SIZE" -le 0 ]]; then
  echo "Error: DMG file is empty or invalid size." >&2
  exit 1
fi

# 2. Mount DMG to temporary mount point
MOUNT_POINT="$(mktemp -d /tmp/bolabol_dmg_check.XXXXXX)"

cleanup() {
  if mount | grep -q "$MOUNT_POINT"; then
    hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$MOUNT_POINT"
}
trap cleanup EXIT

echo "=== Mounting DMG for inspection ==="
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -readonly -quiet

APP_PATH="$MOUNT_POINT/Bolabol.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: 'Bolabol.app' not found at root of mounted DMG '$MOUNT_POINT'." >&2
  exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Error: Info.plist not found in '$APP_PATH'." >&2
  exit 1
fi

echo "=== Validating Bundle Identity and Metadata ==="
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || true)"
BUNDLE_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$INFO_PLIST" 2>/dev/null || true)"
VERSION_SHORT="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || true)"
VERSION_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || true)"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$INFO_PLIST" 2>/dev/null || true)"

if [[ "$BUNDLE_ID" != "com.bolabol.app" ]]; then
  echo "Error: Unexpected CFBundleIdentifier '$BUNDLE_ID' (expected 'com.bolabol.app')." >&2
  exit 1
fi

if [[ "$BUNDLE_NAME" != "Bolabol" ]]; then
  echo "Error: Unexpected CFBundleName '$BUNDLE_NAME' (expected 'Bolabol')." >&2
  exit 1
fi

if [[ -z "$VERSION_SHORT" || -z "$VERSION_BUILD" ]]; then
  echo "Error: Missing CFBundleShortVersionString or CFBundleVersion in Info.plist." >&2
  exit 1
fi

echo "    Bundle ID: $BUNDLE_ID"
echo "    App Name:  $BUNDLE_NAME"
echo "    Version:   $VERSION_SHORT ($VERSION_BUILD)"

echo "=== Validating Sparkle Feed and Security Configuration ==="
SU_FEED="$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$INFO_PLIST" 2>/dev/null || true)"
SU_AUTO_CHECK="$(/usr/libexec/PlistBuddy -c "Print :SUEnableAutomaticChecks" "$INFO_PLIST" 2>/dev/null || true)"
SU_AUTO_UPDATE="$(/usr/libexec/PlistBuddy -c "Print :SUAutomaticallyUpdate" "$INFO_PLIST" 2>/dev/null || true)"
SU_INTERVAL="$(/usr/libexec/PlistBuddy -c "Print :SUScheduledCheckInterval" "$INFO_PLIST" 2>/dev/null || true)"
SU_SIGNED_FEED="$(/usr/libexec/PlistBuddy -c "Print :SURequireSignedFeed" "$INFO_PLIST" 2>/dev/null || true)"
SU_VERIFY_EXTRACT="$(/usr/libexec/PlistBuddy -c "Print :SUVerifyUpdateBeforeExtraction" "$INFO_PLIST" 2>/dev/null || true)"
SU_PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$INFO_PLIST" 2>/dev/null || true)"

EXPECTED_FEED="https://raw.githubusercontent.com/Pavan-Gopa/BOLABOL/main/Bolabol/appcast.xml"
if [[ "$SU_FEED" != "$EXPECTED_FEED" ]]; then
  echo "Error: SUFeedURL mismatch. Got '$SU_FEED', expected '$EXPECTED_FEED'." >&2
  exit 1
fi

if [[ "$SU_AUTO_CHECK" != "true" ]]; then
  echo "Error: SUEnableAutomaticChecks is not true." >&2
  exit 1
fi

if [[ "$SU_AUTO_UPDATE" != "true" ]]; then
  echo "Error: SUAutomaticallyUpdate is not true." >&2
  exit 1
fi

if [[ "$SU_INTERVAL" != "21600" ]]; then
  echo "Error: SUScheduledCheckInterval is '$SU_INTERVAL' (expected 21600 seconds = 6 hours)." >&2
  exit 1
fi

if [[ "$SU_SIGNED_FEED" != "true" ]]; then
  echo "Error: SURequireSignedFeed is not true." >&2
  exit 1
fi

if [[ "$SU_VERIFY_EXTRACT" != "true" ]]; then
  echo "Error: SUVerifyUpdateBeforeExtraction is not true." >&2
  exit 1
fi

echo "    Feed URL:                 $SU_FEED"
echo "    Automatic Checks:         $SU_AUTO_CHECK"
echo "    Automatic Update:         $SU_AUTO_UPDATE"
echo "    Check Interval:           $SU_INTERVAL s"
echo "    Require Signed Feed:      $SU_SIGNED_FEED"
echo "    Verify Before Extraction: $SU_VERIFY_EXTRACT"
if [[ -z "$SU_PUBLIC_KEY" ]]; then
  echo "Error: SUPublicEDKey is missing or empty in '$INFO_PLIST'." >&2
  exit 1
fi
echo "    Public Ed25519 Key:       [Present]"

echo "=== Validating Binaries and Sparkle Framework Linkage ==="
MAIN_BIN="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
WORKER_BIN="$APP_PATH/Contents/MacOS/NativeBolabolPolishWorker"
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"

if [[ ! -x "$MAIN_BIN" ]]; then
  echo "Error: Main executable '$MAIN_BIN' does not exist or is not executable." >&2
  exit 1
fi

if [[ ! -x "$WORKER_BIN" ]]; then
  echo "Error: Worker executable '$WORKER_BIN' does not exist or is not executable." >&2
  exit 1
fi

if [[ ! -d "$SPARKLE_FW" ]]; then
  echo "Error: Sparkle.framework not found in '$APP_PATH/Contents/Frameworks'." >&2
  exit 1
fi

if ! otool -L "$MAIN_BIN" 2>/dev/null | grep -q "Sparkle.framework"; then
  echo "Error: Main binary '$MAIN_BIN' is not dynamically linked against Sparkle.framework." >&2
  exit 1
fi

echo "=== Validating Code Signatures and Nested Components ==="
/usr/bin/codesign --verify --deep --strict --verbose=1 "$APP_PATH"

echo "=== Validating Gatekeeper and Notarization Status ==="
spctl -a -vv --type execute "$APP_PATH"
spctl -a -vv --type install "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
# 6. Mandatory: Validate Appcast XML Document
echo "=== Step 6/6: Validating Appcast XML Document: $APPCAST_PATH ==="

if ! command -v xmllint >/dev/null 2>&1; then
  echo "Error: Required native XML validator 'xmllint' is not available." >&2
  exit 1
fi

if ! xmllint --noout "$APPCAST_PATH" 2>/dev/null; then
  echo "Error: Appcast XML at '$APPCAST_PATH' is malformed or invalid XML." >&2
  exit 1
fi

# Sparkle XML namespace verification
if ! grep -q "xmlns:sparkle=" "$APPCAST_PATH"; then
  echo "Error: Appcast is missing Sparkle XML namespace declaration (xmlns:sparkle)." >&2
  exit 1
fi

# Sparkle signed-feed comment block verification (SURequireSignedFeed)
if ! grep -q "<!-- sparkle-signatures:" "$APPCAST_PATH"; then
  echo "Error: Appcast is missing mandatory Sparkle signed-feed comment block (<!-- sparkle-signatures:)." >&2
  exit 1
fi

SPARKLE_SIG_BLOCK="$(sed -n '/<!-- sparkle-signatures:/,/-->/p' "$APPCAST_PATH")"
if [[ -z "$SPARKLE_SIG_BLOCK" ]]; then
  echo "Error: Appcast is missing mandatory Sparkle signed-feed comment block (<!-- sparkle-signatures:)." >&2
  exit 1
fi

FEED_ED_SIG="$(echo "$SPARKLE_SIG_BLOCK" | grep -E 'edSignature:[[:space:]]*[A-Za-z0-9+/=]+' | sed -E 's/.*edSignature:[[:space:]]*([A-Za-z0-9+/=]+).*/\1/' | tr -d '\r\n[:space:]' || true)"
if [[ -z "$FEED_ED_SIG" ]]; then
  echo "Error: Sparkle signed-feed block is missing non-empty 'edSignature:'." >&2
  exit 1
fi

FEED_SIG_LEN="$(echo "$SPARKLE_SIG_BLOCK" | grep -E 'length:[[:space:]]*[0-9]+' | sed -E 's/.*length:[[:space:]]*([0-9]+).*/\1/' | tr -d '\r\n[:space:]' || true)"
if [[ -z "$FEED_SIG_LEN" || ! "$FEED_SIG_LEN" =~ ^[0-9]+$ || "$FEED_SIG_LEN" -le 0 ]]; then
  echo "Error: Sparkle signed-feed block is missing valid numeric 'length:'." >&2
  exit 1
fi
# Extract and validate sparkle:version (matches CFBundleVersion / VERSION_BUILD)
APPCAST_BUILD="$(xmllint --xpath "string((//*[local-name()='item']/*[local-name()='version'])[1]/text())" "$APPCAST_PATH" 2>/dev/null || true)"
if [[ -z "$APPCAST_BUILD" ]]; then
  APPCAST_BUILD="$(xmllint --xpath "string((//enclosure)[1]/@*[local-name()='version'])" "$APPCAST_PATH" 2>/dev/null || true)"
fi

if [[ -z "$APPCAST_BUILD" ]]; then
  echo "Error: Appcast is missing 'sparkle:version' in item/enclosure." >&2
  exit 1
fi

if [[ "$APPCAST_BUILD" != "$VERSION_BUILD" ]]; then
  echo "Error: Appcast sparkle:version '$APPCAST_BUILD' does not match mounted app CFBundleVersion '$VERSION_BUILD'." >&2
  exit 1
fi

# Extract and validate sparkle:shortVersionString (matches CFBundleShortVersionString / VERSION_SHORT)
APPCAST_SHORT_VERSION="$(xmllint --xpath "string((//*[local-name()='item']/*[local-name()='shortVersionString'])[1]/text())" "$APPCAST_PATH" 2>/dev/null || true)"
if [[ -z "$APPCAST_SHORT_VERSION" ]]; then
  APPCAST_SHORT_VERSION="$(xmllint --xpath "string((//enclosure)[1]/@*[local-name()='shortVersionString'])" "$APPCAST_PATH" 2>/dev/null || true)"
fi

if [[ -z "$APPCAST_SHORT_VERSION" ]]; then
  echo "Error: Appcast is missing 'sparkle:shortVersionString' in item/enclosure." >&2
  exit 1
fi

if [[ "$APPCAST_SHORT_VERSION" != "$VERSION_SHORT" ]]; then
  echo "Error: Appcast sparkle:shortVersionString '$APPCAST_SHORT_VERSION' does not match mounted app CFBundleShortVersionString '$VERSION_SHORT'." >&2
  exit 1
fi

# Extract and validate enclosure EdDSA signature
ENC_SIG="$(xmllint --xpath "string((//enclosure)[1]/@*[local-name()='edSignature'])" "$APPCAST_PATH" 2>/dev/null || true)"
if [[ -z "$ENC_SIG" ]]; then
  ENC_SIG="$(xmllint --xpath "string((//*[local-name()='edSignature'])[1]/text())" "$APPCAST_PATH" 2>/dev/null || true)"
fi

if [[ -z "$ENC_SIG" ]]; then
  echo "Error: Appcast enclosure is missing required EdDSA signature (sparkle:edSignature)." >&2
  exit 1
fi

# Extract and validate enclosure length (must match exact DMG byte size)
ENC_LEN="$(xmllint --xpath "string((//enclosure)[1]/@length)" "$APPCAST_PATH" 2>/dev/null || true)"
if [[ -z "$ENC_LEN" ]]; then
  echo "Error: Appcast enclosure is missing 'length' attribute." >&2
  exit 1
fi

if [[ "$ENC_LEN" != "$DMG_SIZE" ]]; then
  echo "Error: Appcast enclosure length '$ENC_LEN' does not match exact DMG byte size '$DMG_SIZE'." >&2
  exit 1
fi

# Extract and validate enclosure URL
ENC_URL="$(xmllint --xpath "string((//enclosure)[1]/@url)" "$APPCAST_PATH" 2>/dev/null || true)"
if [[ -z "$ENC_URL" ]]; then
  echo "Error: Appcast enclosure is missing 'url' attribute." >&2
  exit 1
fi

if [[ "$ENC_URL" == *"latest/download"* ]]; then
  echo "Error: Appcast enclosure URL contains forbidden mutable 'latest/download'." >&2
  exit 1
fi

EXPECTED_ENC_URL="https://github.com/Pavan-Gopa/BOLABOL/releases/download/v${VERSION_SHORT}/BOLABOL.dmg"
if [[ "$ENC_URL" != "$EXPECTED_ENC_URL" ]]; then
  echo "Error: Appcast enclosure URL '$ENC_URL' does not match immutable target '$EXPECTED_ENC_URL'." >&2
  exit 1
fi

echo "    Appcast well-formed XML verified."
echo "    Appcast Sparkle namespace verified."
echo "    Appcast signed-feed block verified (edSignature and length: $FEED_SIG_LEN)."
echo "    Appcast sparkle:version verified ($APPCAST_BUILD)."
echo "    Appcast sparkle:shortVersionString verified ($APPCAST_SHORT_VERSION)."
echo "    Appcast EdDSA enclosure signature verified."
echo "    Appcast enclosure length verified ($ENC_LEN bytes)."
echo "    Appcast immutable enclosure URL verified ($ENC_URL)."
echo "=== ALL UPDATER RELEASE CHECKS PASSED ==="
