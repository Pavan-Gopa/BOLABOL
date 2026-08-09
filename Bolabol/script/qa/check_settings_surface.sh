#!/usr/bin/env bash
# Settings UI must expose all product tabs and wire Core settings types.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SETTINGS_DIR="Sources/NativeBolabol/Views/Settings"
required_views=(
  SettingsView.swift
  GeneralSettingsView.swift
  APIProvidersSettingsView.swift
  HotkeySettingsView.swift
  GlossarySettingsView.swift
  LocalModelsSettingsView.swift
  PolishingSettingsView.swift
  PromptsSettingsView.swift
  HelpSettingsView.swift
)

missing=0
for f in "${required_views[@]}"; do
  if [ ! -f "$SETTINGS_DIR/$f" ]; then
    echo "MISSING settings view: $f"
    missing=1
  fi
done

# SettingsView must reference major tabs
for needle in General Hotkey Glossary Polishing Help API Prompt; do
  if ! grep -q "$needle" "$SETTINGS_DIR/SettingsView.swift"; then
    echo "SettingsView.swift may not reference tab: $needle"
    missing=1
  fi
done

# Core models backing settings
for model in GeneralSettings HotkeySettings APIProviderSettings GlossarySettings \
  PolishingModelSettings TranscriptionModelSettings PromptTemplateSettings UsageStatisticsSettings; do
  if ! find Sources/NativeBolabolCore -name "${model}.swift" | grep -q .; then
    echo "MISSING Core model: $model"
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  exit 1
fi
echo "OK: settings surface complete"
