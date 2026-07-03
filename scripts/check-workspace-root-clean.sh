#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

bad_entries="
assets
audio-recorder-worklet.js
entitlements.mac.plist
index.css
index.html
index.js
index.tsx
jfk.wav
main.js
native
new icons
overlay.html
package-lock.json
package.json
parakeet.js
parakeet.worker.js
parakeet_cpu_integration
parakeet_mlx
preload.js
prompt.tsx
public
release
smoke-strong.js
smoke.js
src
stream-endpointed.js
stream-from-file.js
test-fork.js
test-whisper.js
transcription.fork.js
tsconfig.json
vite.config.ts
whisper.d.ts
"

found=0
printf '%s\n' "$bad_entries" | while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    if [ -e "$ROOT_DIR/$entry" ]; then
        printf 'Root clutter detected: %s\n' "$entry" >&2
        found=1
    fi
done

if printf '%s\n' "$bad_entries" | while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    [ ! -e "$ROOT_DIR/$entry" ] || exit 1
done; then
    printf 'Workspace root is clean.\n'
else
    printf 'Move app files into the owning project folder before continuing.\n' >&2
    exit 1
fi

