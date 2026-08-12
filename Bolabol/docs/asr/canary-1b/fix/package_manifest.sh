#!/usr/bin/env bash
# Generate the immutable file inventory for a Bolabol-hosted spike package.
# This is offline packaging tooling only; it is not part of the app runtime.
set -euo pipefail

PACKAGE_DIR="${1:?usage: package_manifest.sh <package-directory>}"
MANIFEST="$PACKAGE_DIR/MANIFEST.json"
TEMP="$MANIFEST.tmp"

PACKAGE_ID="$(basename "$PACKAGE_DIR")"
printf '{\n  "packageId": "%s",\n  "modelFamily": "canary-1b-v2",\n  "frontend": "native-nemo-mel",\n  "windowSeconds": 15,\n  "sampleRate": 16000,\n  "minMacOS": "15.0",\n  "license": "see LICENSE.txt",\n  "upstreamWeights": "nvidia/canary-1b-v2",\n  "created": "%s",\n  "files": [\n' \
  "$PACKAGE_ID" "$(date -u +%Y-%m-%d)" > "$TEMP"

first=true
while IFS= read -r file; do
    case "$file" in
        "$MANIFEST"|"$TEMP") continue ;;
    esac
    relative="${file#"$PACKAGE_DIR/"}"
    checksum="$(shasum -a 256 "$file")"
    checksum="${checksum%% *}"
    size="$(stat -f %z "$file")"
    if [ "$first" = true ]; then
        first=false
    else
        printf ',\n' >> "$TEMP"
    fi
    printf '    {"path": "%s", "sha256": "%s", "sizeBytes": %s}' \
        "$relative" "$checksum" "$size" >> "$TEMP"
done < <(find "$PACKAGE_DIR" -type f | sort)

printf '\n  ]\n}\n' >> "$TEMP"
mv "$TEMP" "$MANIFEST"
printf 'Wrote %s\n' "$MANIFEST"
