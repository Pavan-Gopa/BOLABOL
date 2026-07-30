#!/usr/bin/env bash
# Submit a signed SmartScribe.dmg to Apple notarization and staple the ticket.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_DMG="$ROOT_DIR/dist/SmartScribe.dmg"
DEFAULT_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-SmartScribe-Notary}"
TEAM_ID="${NOTARY_TEAM_ID:-438UQRF7JV}"

DMG_PATH="${1:-$DEFAULT_DMG}"
PROFILE="${2:-$DEFAULT_PROFILE}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "error: DMG not found: $DMG_PATH" >&2
  exit 1
fi

echo "=== Pre-flight: codesign on DMG ==="
codesign -dv --verbose=2 "$DMG_PATH" 2>&1 | sed -n '1,15p' || {
  echo "error: DMG is not signed. Run ./script/build_release_dmg.sh first." >&2
  exit 1
}

echo "=== Submitting for notarization (profile: $PROFILE) ==="
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  cat >&2 <<EOF
error: notarytool keychain profile "$PROFILE" is not configured.

Store credentials once, then re-run this script:

  # App-specific password (Apple ID):
  xcrun notarytool store-credentials "$PROFILE" \\
    --apple-id "you@example.com" \\
    --team-id "$TEAM_ID" \\
    --password "app-specific-password"

  # Or App Store Connect API key:
  xcrun notarytool store-credentials "$PROFILE" \\
    --key /path/to/AuthKey_XXXXXXXXXX.p8 \\
    --key-id "XXXXXXXXXX" \\
    --issuer "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

Environment overrides:
  NOTARY_KEYCHAIN_PROFILE  (default: SmartScribe-Notary)
  NOTARY_TEAM_ID           (default: $TEAM_ID)
EOF
  exit 1
fi

xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$PROFILE" \
  --wait

echo "=== Stapling notarization ticket ==="
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "=== Gatekeeper assessment ==="
spctl -a -vv -t install "$DMG_PATH"

echo "=== Notarization complete: $DMG_PATH ==="
ls -lh "$DMG_PATH"
shasum -a 256 "$DMG_PATH"
