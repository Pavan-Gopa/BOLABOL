# Bolabol 1.0.5 release checklist

## Branch

```text
main
```

Repository: `https://github.com/Pavan-Gopa/Bolabol`.

## Prerequisites

Keep the Sparkle private key in the macOS Keychain under the organization
account. The public key is safe to embed in the release `Info.plist`; never
commit or paste the private key.

```bash
export SPARKLE_ACCOUNT=bolabol
export SPARKLE_PUBLIC_ED_KEY="$("$PWD/.build/artifacts/sparkle/Sparkle/bin/generate_keys" --account bolabol -p)"
```

Required release credentials:

- Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV)
- `xcrun notarytool` profile `Bolabol-Notary`
- Authenticated GitHub CLI

## Build, sign, and notarize the DMG

```bash
RELEASE_BUILD=1 NOTARIZE=1 APP_VERSION=1.0.5 \
  ./script/build_release_dmg.sh --release --notarize
```

Outputs:

- `dist/BOLABOL.dmg` — signed and notarized disk image
- `dist/release/Bolabol.app` — signed release app bundle
- `dist/appcast.xml` — generated signed appcast
- `dist/handoff/` — DMG, installer helper, and `SHA256SUMS.txt`

The build embeds Sparkle 2.9.4, signs nested Sparkle code inside-out, and uses
the immutable update URL prefix:

```text
https://github.com/Pavan-Gopa/BOLABOL/releases/download/v1.0.5/
```

## Generate and validate the signed appcast

Use the exact `CFBundleVersion` printed by the release build:

```bash
APP_BUILD=202608171613 \
  ./script/generate_update_appcast.sh \
  dist/BOLABOL.dmg dist/appcast.xml

bash ./script/check_updater_release.sh \
  dist/BOLABOL.dmg dist/appcast.xml
```

The checker validates bundle identity/version, Sparkle feed configuration,
nested signatures, app and DMG Gatekeeper status, the stapled DMG ticket, XML
well-formedness, EdDSA signatures, exact DMG length, and the immutable enclosure
URL. It intentionally does not require a separate stapled ticket on the app
mounted from the DMG.

## Apple notarization credentials

Credentials are **not** stored in the repo. Configure once on the build machine:

```bash
xcrun notarytool store-credentials "Bolabol-Notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "438UQRF7JV" \
  --password "APP_SPECIFIC_PASSWORD"
```

Standalone notarization, when needed:

```bash
./script/notarize_dmg.sh dist/BOLABOL.dmg
spctl -a -vv -t install dist/BOLABOL.dmg
xcrun stapler validate dist/BOLABOL.dmg
```

## GitHub release

Confirm the repository visibility before publication:

```bash
gh repo view Pavan-Gopa/Bolabol --json isPrivate
```

Push the reviewed commit and tag, then create the release with the exact DMG,
checksum, and release notes:

```bash
git push -u origin HEAD
git push origin v1.0.5

gh release create v1.0.5 \
  dist/BOLABOL.dmg \
  dist/handoff/SHA256SUMS.txt \
  --title "Bolabol 1.0.5" \
  --notes-file docs/RELEASE_NOTES.md \
  --target main \
  --latest
```

If a draft already exists:

```bash
gh release edit v1.0.5 \
  --notes-file docs/RELEASE_NOTES.md \
  --draft=false \
  --prerelease=false \
  --latest=true
```

Do **not** run `gh repo edit --visibility public` unless you intend to open the
repository.

## In-app updater contract

- Sparkle 2.9.4 checks the stable signed GitHub appcast.
- The title-bar update action is user initiated; there is no silent forced
  installation.
- Updates are refused while active recording or app work cannot be quiesced.
- Cancellation or failure keeps the current installation and exposes retry or
  manual-install fallback.
- `1.0.5` is the updater bootstrap release; existing `1.0.4` installations
  require one final manual installation.
- Future updates must use the same bundle identity
  `com.bolabol.app`, Developer ID lineage, and immutable release asset names.

## Smoke checks after install

1. Launch `/Applications/Bolabol.app`.
2. Open Settings and confirm the glossary section loads.
3. Record a short clip and confirm raw text appears.
4. Check the title-bar update action with a signed newer appcast.
5. Verify cancellation during active recording preserves the current app.
6. Confirm API provider keys remain local and no secrets are bundled.
