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

require Sources/NativeBolabol/Views/ContentView.swift
require Sources/NativeBolabol/Views/SidebarView.swift
require Sources/NativeBolabol/Views/NoteDetailView.swift
require Sources/NativeBolabol/Views/TranslationModalView.swift
require Sources/NativeBolabol/Views/OnboardingView.swift
require Sources/NativeBolabol/Views/AudioPlaybackModalView.swift
require Sources/NativeBolabol/Views/GlossaryDraftModal.swift
require Sources/NativeBolabol/Views/GlossaryCategoryPicker.swift
require Sources/NativeBolabol/Views/ProviderQuickSwitcher.swift
require Sources/NativeBolabol/App/NativeBolabolApp.swift
require Sources/NativeBolabolCore/Stores/NoteStore.swift
require Sources/NativeBolabolCore/Stores/GlossaryStore.swift

# Note variants
for needle in polishedVariantOne polishedVariantTwo rawText; do
  if ! grep -q "$needle" Sources/NativeBolabolCore/Models/BolabolNote.swift; then
    echo "FAIL: BolabolNote missing $needle"
    fail=1
  fi
done

# Logos / branding
for f in \
  Sources/NativeBolabol/Views/Components/BolabolLogoView.swift \
  Sources/NativeBolabol/Views/Components/BolabolWordmarkView.swift; do
  require "$f"
done
require Sources/NativeBolabol/Resources/Logos/BOLABOL_LOGO_Full.svg

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK: workspace UI surface"
