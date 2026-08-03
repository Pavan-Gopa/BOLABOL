# Bolabol release checklist

## Branch

```text
main
```

Repository: `https://github.com/Pavan-Gopa/Bolabol`.

## Build signed DMG

```bash
APP_VERSION=1.0.3 APP_BUILD=1 ./script/build_release_dmg.sh
# or with notarization in one step:
APP_VERSION=1.0.3 APP_BUILD=1 NOTARIZE=1 ./script/build_release_dmg.sh
```

Outputs:

- `dist/Bolabol.dmg` — signed (and optionally notarized) disk image  
- `dist/release/Bolabol.app` — app bundle  
- `dist/handoff/` — DMG + `install.sh` + `SHA256SUMS.txt`

Signing identity (preferred):

```text
Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV)
```

## Notarize with Apple

Credentials are **not** stored in the repo. Configure once on the build machine:

```bash
xcrun notarytool store-credentials "Bolabol-Notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "438UQRF7JV" \
  --password "APP_SPECIFIC_PASSWORD"
```

Then:

```bash
./script/notarize_dmg.sh dist/Bolabol.dmg
# or as part of the build:
NOTARIZE=1 ./script/build_release_dmg.sh
```

Verify:

```bash
spctl -a -vv -t install dist/Bolabol.dmg
xcrun stapler validate dist/Bolabol.dmg
```

## CLI install for recipients

```bash
./script/install.sh /path/to/Bolabol.dmg
./script/install.sh --from-github   # needs gh auth + private repo access
```

## GitHub release (published)

```bash
# Ensure remote stays private until you choose otherwise
gh repo view Pavan-Gopa/Bolabol --json isPrivate

# Push branch
git push -u origin HEAD

# Create / update a normal Latest release
gh release create v1.0.3 \
  dist/Bolabol.dmg \
  --title "Bolabol 1.0.3" \
  --notes-file docs/RELEASE_NOTES.md \
  --target main \
  --latest

# If the release already exists as a draft:
gh release edit v1.0.3 \
  --notes-file docs/RELEASE_NOTES.md \
  --draft=false \
  --prerelease=false \
  --latest=true
```

Do **not** run `gh repo edit --visibility public` unless you intend to open the repo.

## Smoke checks after install

1. Launch `/Applications/Bolabol.app`  
2. Onboarding / Help → Replay onboarding  
3. Settings → Local Models — list loads  
4. Record a short clip → Raw text appears  
5. Option+S HUD appears over another app  
6. With ≥2 polishing providers: scroll HUD → provider list; right-click provider → model menu  
7. API Providers — keys remain local; no keys pre-bundled in the app  
