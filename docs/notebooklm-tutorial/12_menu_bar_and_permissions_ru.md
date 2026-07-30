# 11. macOS Menu Bar и permissions

## `12_macos_app_menu.png`

Показывает стандартное macOS app menu для SmartScribe. Здесь доступны:

- About SmartScribe;
- Settings;
- Services;
- Hide SmartScribe;
- Quit SmartScribe.

## Status item

По коду приложение также создаёт status item в macOS menu bar. Меню status item содержит:

- `Open SmartScribe`
- `Hide SmartScribe`
- `Quit SmartScribe`

Это полезно, потому что главное окно при закрытии не завершает приложение; оно скрывается, а SmartScribe может продолжать жить в menu bar для hotkey workflow.

## Permissions

SmartScribe использует несколько macOS permissions:

- Microphone - для записи аудио.
- Speech Recognition - для on-device speech recognition.
- Apple Events - для вставки текста в активное приложение.
- Accessibility - только для режима `Type into Active App`.

Если пользователь выбирает Clipboard mode, Accessibility permission не нужна. Если он хочет, чтобы SmartScribe печатал текст прямо в активное приложение, Accessibility должна быть granted.

