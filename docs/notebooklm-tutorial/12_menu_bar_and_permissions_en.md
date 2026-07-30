# 11. macOS Menu Bar and Permissions

## `12_macos_app_menu.png`

This screenshot shows the standard macOS app menu for SmartScribe. It includes:

- About SmartScribe;
- Settings;
- Services;
- Hide SmartScribe;
- Quit SmartScribe.

## Status Item

The app code also creates a macOS menu bar status item. Its menu contains:

- `Open SmartScribe`
- `Hide SmartScribe`
- `Quit SmartScribe`

This matters because closing the main window does not quit the app. The window hides, while SmartScribe can keep running for the hotkey workflow.

## Permissions

SmartScribe uses several macOS permissions:

- Microphone for audio recording.
- Speech Recognition for on-device recognition.
- Apple Events for inserting text into the active app.
- Accessibility only for `Type into Active App`.

Clipboard mode does not need Accessibility. Direct typing into the active app requires Accessibility to be granted.

