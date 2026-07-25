# 99. Source Notes

These notes help NotebookLM connect screenshots with the app's internal logic.

## Main UI Files

- `Sources/NativeSmartScribe/Views/ContentView.swift` - main window, recording, transcription, polishing, translation modal workflow.
- `Sources/NativeSmartScribe/Views/NoteDetailView.swift` - detail pane, Raw / Variant 1 / Variant 2, bottom action bar.
- `Sources/NativeSmartScribe/Views/TranslationModalView.swift` - translation modal.
- `Sources/NativeSmartScribe/Views/Settings/SettingsView.swift` - Settings tabs.
- `Sources/NativeSmartScribe/Views/Settings/LocalModelsSettingsView.swift` - transcription models.
- `Sources/NativeSmartScribe/Views/Settings/PolishingSettingsView.swift` - local MLX polishing models.
- `Sources/NativeSmartScribe/Views/Settings/APIProvidersSettingsView.swift` - API providers.
- `Sources/NativeSmartScribe/Views/Settings/HotkeySettingsView.swift` - hotkeys, target, output mode, accessibility.
- `Sources/NativeSmartScribe/Views/Settings/GlossarySettingsView.swift` - glossary UI.
- `Sources/NativeSmartScribe/Views/Settings/PromptsSettingsView.swift` - prompt templates.
- `Sources/NativeSmartScribe/Views/Settings/StatisticsSettingsView.swift` - token usage.
- `Sources/NativeSmartScribe/Views/Settings/HelpSettingsView.swift` - built-in help.

## Main Models and Services

- `TranscriptionModelDescriptor.swift` - WhisperKit model catalog.
- `PolishingModelDescriptor.swift` - MLX model catalog.
- `TranscriptionModelStore.swift` - download/use/delete logic for transcription models.
- `PolishingEngineStore.swift` - MLX/API provider selection and model preparation.
- `SharedModelsRoot.swift` - shared local model root.
- `GlossaryStore.swift` - glossary import/export/apply.
- `PromptTemplateStore.swift` - prompt slots.
- `HotkeySessionCoordinator.swift` and `HotkeyOutputTextResolver.swift` - hotkey session and output text selection.

## Verification

The materials were captured after a successful launch:

```bash
./script/build_and_run.sh --verify
```

