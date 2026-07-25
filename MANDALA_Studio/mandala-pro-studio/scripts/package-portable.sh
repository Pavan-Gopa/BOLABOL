#!/usr/bin/env bash
# Build Mandala Studio and pack a shareable portable folder + zip.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT_DIR="$ROOT/release/MandalaStudio-Portable"
ZIP_PATH="$ROOT/release/MandalaStudio-Portable.zip"
PORTABLE_SRC="$ROOT/portable"

echo "==> Building production app..."
npm run build

if [ ! -f "$ROOT/dist/index.html" ]; then
  echo "ERROR: dist/index.html missing after build"
  exit 1
fi

echo "==> Assembling portable package..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/app"

# App files
cp -R "$ROOT/dist/." "$OUT_DIR/app/"

# Launchers + readme
cp "$PORTABLE_SRC/Start-Mandala.bat" "$OUT_DIR/"
cp "$PORTABLE_SRC/Start-Mandala.ps1" "$OUT_DIR/"
cp "$PORTABLE_SRC/Start-Mandala.command" "$OUT_DIR/"
cp "$PORTABLE_SRC/README.txt" "$OUT_DIR/"
chmod +x "$OUT_DIR/Start-Mandala.command"

# Zip (fresh)
echo "==> Creating zip..."
rm -f "$ZIP_PATH"
mkdir -p "$ROOT/release"
(
  cd "$ROOT/release"
  # Avoid macOS resource forks in zip when possible
  if command -v zip >/dev/null 2>&1; then
    zip -r -q "MandalaStudio-Portable.zip" "MandalaStudio-Portable" \
      -x "*.DS_Store" -x "*__MACOSX*"
  else
    echo "zip not found — folder is ready at: $OUT_DIR"
    exit 0
  fi
)

SIZE=$(du -h "$ZIP_PATH" | awk '{print $1}')
echo ""
echo "Done."
echo "  Folder: $OUT_DIR"
echo "  Zip:    $ZIP_PATH  ($SIZE)"
echo ""
echo "Send the zip to your wife. She unzips and double-clicks Start-Mandala.bat"
echo ""
