# 06. General Settings

## `07_general_settings.png`

General содержит настройки внешнего вида, масштаба интерфейса, языка, HUD, логирования и troubleshooting.

## Что видно на screenshot

- Theme: Dark, Light, System.
- UI Font Size: общий масштаб интерфейса.
- Interface Language: язык интерфейса.
- Overlay HUD: размер, прозрачность, звук start/finish, громкость.
- Log Level: уровень логов.
- Troubleshooting: экспорт системных логов и reset general-настроек.

## Что объяснить

HUD-настройки не управляют главным окном. Они относятся к floating overlay, который появляется при hotkey recording. Если пользователь не использует hotkeys, HUD почти не виден.

Export System Logs сохраняет диагностические логи в `~/Library/Application Support/NativeSmartScribe/Logs/`. Это полезно для отладки проблем с записью, моделями или permissions.

