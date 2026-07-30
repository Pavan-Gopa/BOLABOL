# 99. Source Notes

Эти заметки помогают NotebookLM связать screenshots с внутренней логикой приложения.

## Основные файлы UI

- `Sources/NativeSmartScribe/Views/ContentView.swift` - главное окно, workflow записи, транскрибации, polishing, translation modal.
- `Sources/NativeSmartScribe/Views/NoteDetailView.swift` - detail pane, Raw / Variant 1 / Variant 2, нижняя панель действий.
- `Sources/NativeSmartScribe/Views/TranslationModalView.swift` - modal перевода.
- `Sources/NativeSmartScribe/Views/Settings/SettingsView.swift` - все вкладки Settings.
- `Sources/NativeSmartScribe/Views/Settings/LocalModelsSettingsView.swift` - модели транскрибации.
- `Sources/NativeSmartScribe/Views/Settings/PolishingSettingsView.swift` - локальные MLX polishing models.
- `Sources/NativeSmartScribe/Views/Settings/APIProvidersSettingsView.swift` - API providers.
- `Sources/NativeSmartScribe/Views/Settings/HotkeySettingsView.swift` - hotkeys, target, output mode, accessibility.
- `Sources/NativeSmartScribe/Views/Settings/GlossarySettingsView.swift` - glossary UI.
- `Sources/NativeSmartScribe/Views/Settings/PromptsSettingsView.swift` - prompt templates.
- `Sources/NativeSmartScribe/Views/Settings/StatisticsSettingsView.swift` - token usage.
- `Sources/NativeSmartScribe/Views/Settings/HelpSettingsView.swift` - встроенная справка.

## Основные модели и сервисы

- `TranscriptionModelDescriptor.swift` - каталог WhisperKit models.
- `PolishingModelDescriptor.swift` - каталог MLX models.
- `TranscriptionModelStore.swift` - download/use/delete логика для transcription models.
- `PolishingEngineStore.swift` - MLX/API provider selection и model preparation.
- `SharedModelsRoot.swift` - общий root локальных моделей.
- `GlossaryStore.swift` - import/export/apply glossary.
- `PromptTemplateStore.swift` - prompt slots.
- `HotkeySessionCoordinator.swift` и `HotkeyOutputTextResolver.swift` - hotkey session и выбор текста для output.

## Проверка

Материалы сняты после успешного запуска:

```bash
./script/build_and_run.sh --verify
```

