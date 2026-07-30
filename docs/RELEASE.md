# SmartScribe release checklist

## Branch

Use the post–code-review line:

```text
codex/parakeet-bonsai
```

Key commits:

- `a0e48ed` — Parakeet + Bonsai local models  
- `5052c9d` / `a86f0d6` / `77d93eb` — runtime fixes  
- `d050b8f` — automated code review pipeline  
- `041fbdc` — resolve code review findings (5549 → 141)

Repository: `https://github.com/Pavan-Gopa/SmartScribe` (**must remain private**).

## Build signed DMG

```bash
./script/build_release_dmg.sh
# optional version pin:
APP_VERSION=1.0.0 APP_BUILD=1 ./script/build_release_dmg.sh
```

Outputs:

- `dist/SmartScribe.dmg` — signed disk image  
- `dist/release/SmartScribe.app` — app bundle  
- `dist/handoff/` — DMG + `install.sh` + `SHA256SUMS.txt`

Signing identity (preferred):

```text
Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV)
```

## Notarize with Apple

Credentials are **not** stored in the repo. Configure once on the build machine:

```bash
xcrun notarytool store-credentials "SmartScribe-Notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "438UQRF7JV" \
  --password "APP_SPECIFIC_PASSWORD"
```

Then:

```bash
./script/notarize_dmg.sh dist/SmartScribe.dmg
# or as part of the build:
NOTARIZE=1 ./script/build_release_dmg.sh
```

Verify:

```bash
spctl -a -vv -t install dist/SmartScribe.dmg
xcrun stapler validate dist/SmartScribe.dmg
```

## CLI install for recipients

```bash
./script/install.sh /path/to/SmartScribe.dmg
./script/install.sh --from-github   # needs gh auth + private repo access
```

## GitHub release (private)

```bash
# Ensure remote stays private
gh repo view Pavan-Gopa/SmartScribe --json isPrivate

# Push branch
git push -u origin codex/parakeet-bonsai

# Create a private release with assets
gh release create v1.0.0 \
  dist/handoff/SmartScribe.dmg \
  dist/handoff/install.sh \
  dist/handoff/SHA256SUMS.txt \
  --title "SmartScribe 1.0.0" \
  --notes-file docs/RELEASE_NOTES.md \
  --target codex/parakeet-bonsai
```

Do **not** run `gh repo edit --visibility public`.

## Smoke checks after install

1. Launch `/Applications/SmartScribe.app`  
2. Onboarding / Help → Replay onboarding  
3. Settings → Local Models — list loads  
4. Record a short clip → Raw text appears  
5. Option+S HUD appears over another app  
6. API Providers — keys remain local; polish optional  
