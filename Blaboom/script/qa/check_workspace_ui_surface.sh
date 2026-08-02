#!/usr/bin/env bash
# Main workspace UI: notes, sidebar, translation, onboarding, logos.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
require() {
  if [ ! -f "$1" ]; then
    echo "FAIL: missing $1"
    fail=1
  fi
}

require Sources/NativeBlaboom/Views/ContentView.swift
require Sources/NativeBlaboom/Views/SidebarView.swift
require Sources/NativeBlaboom/Views/NoteDetailView.swift
require Sources/NativeBlaboom/Views/TranslationModalView.swift
require Sources/NativeBlaboom/Views/OnboardingView.swift
require Sources/NativeBlaboom/Views/AudioPlaybackModalView.swift
require Sources/NativeBlaboom/Views/GlossaryDraftModal.swift
require Sources/NativeBlaboom/Views/GlossaryCategoryPicker.swift
require Sources/NativeBlaboom/Views/ProviderQuickSwitcher.swift
require Sources/NativeBlaboom/App/NativeBlaboomApp.swift
require Sources/NativeBlaboomCore/Stores/NoteStore.swift
require Sources/NativeBlaboomCore/Stores/GlossaryStore.swift

# Note variants
for needle in polishedVariantOne polishedVariantTwo rawText; do
  if ! grep -q "$needle" Sources/NativeBlaboomCore/Models/BlaboomNote.swift; then
    echo "FAIL: BlaboomNote missing $needle"
    fail=1
  fi
done

# Logos / branding
for f in \
  Sources/NativeBlaboom/Views/Components/BlaboomLogoView.swift \
  Sources/NativeBlaboom/Views/Components/BlaboomWordmarkView.swift \
  Sources/NativeBlaboom/Views/Components/BlaboomFullLogoView.swift; do
  require "$f"
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: workspace UI surface"
