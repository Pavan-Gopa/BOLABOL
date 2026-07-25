# 00. SmartScribe: пользовательский onboarding для видео

Этот файл нужен NotebookLM как главный сценарий. Остальные Markdown-файлы и PNG раскрывают отдельные экраны. Логика видео должна идти не по меню приложения, а по пути нового пользователя: сначала подготовить локальные модели, затем понять рабочее окно, затем освоить hotkey + HUD и вставку результата в другие приложения.

## Step 1. Установить локальную модель транскрибации

Сначала пользователь открывает `Settings -> Local Models`.

Кадр: `03_local_transcription_models_settings.png`

Что сказать: SmartScribe умеет скачивать локальные WhisperKit/Core ML модели прямо из приложения. Это модели для аудио -> текст. Пользователь выбирает модель, нажимает `Download`, после установки нажимает `Use`. Ненужную модель можно удалить кнопкой `Delete`. Для русского, смешанной речи и многоязычных сценариев нужны multilingual-модели, например Whisper Large v3.

## Step 2. Установить локальную модель polishing

После распознавания речи нужен отдельный слой редактирования текста.

Кадр: `04_local_polishing_models_settings.png`

Что сказать: polishing model - это не модель распознавания аудио. Она берёт raw transcription и превращает его в чистый текст: убирает повторы, исправляет структуру, готовит Variant 1 или Variant 2. Локальные polishing-модели скачиваются из программы, выбираются кнопкой `Use` и удаляются кнопкой `Delete`.

## Step 3. Понять, что API - опционально

Кадр: `05_api_providers_settings.png`

Что сказать: приложение может работать через локальные модели, а API-провайдеры используются только если пользователь сам хочет подключить внешний polishing/translation provider. В базовом local-first сценарии сначала показываем именно локальные модели.

## Step 4. Вернуться в главное окно

Кадры: `01_app_overview.png`, `02_main_01_window_initial.png`

Что сказать: слева находится список notes/записей, справа - выбранная запись. В верхней части пользователь выбирает transcription model и polishing model. Ниже находятся вкладки `Raw`, `Variant 1`, `Variant 2`.

## Step 5. Записать или импортировать аудио

Кадры: `02_main_01_window_initial.png`, `02_main_05_transcription_model_menu.png`

Что сказать: SmartScribe может транскрибировать запись, сделанную в приложении, а также аудиофайл. После транскрибации raw-результат сохраняется как заметка. Это база, от которой строятся варианты polishing.

## Step 6. Понять Raw, Variant 1 и Variant 2

Кадры: `02_main_02_raw_tab.png`, `02_main_03_variant_1_tab.png`, `02_main_04_variant_2_tab.png`

Что сказать: `Raw` - это исходная транскрибация. `Variant 1` - аккуратная чистка диктовки. `Variant 2` - более сильная редактура и структурирование. Пользователь может выбрать, какой результат использовать дальше.

## Step 7. Настроить prompt slots

Кадры: `08_prompts_01_variant_one.png`, `08_prompts_02_variant_two.png`, `08_prompts_03_markdown.png`

Что сказать: Variant 1 и Variant 2 управляются prompt templates. Пользователь может настроить default prompt и дополнительные слоты `1`, `2`, `3`, `4`, а также Markdown-режим. Это делает SmartScribe не просто диктофоном, а системой для разных форматов текста.

## Step 8. Настроить glossary и перевод

Кадры: `09_glossary_01_settings.png`, `09_glossary_02_add_context_menu.png`, `09_glossary_03_selected_text.png`, `10_translation_modal.png`

Что сказать: glossary помогает сохранять правильные термины, имена и собственные словари пользователя. Перевод можно запускать для выделенного текста или clipboard, выбирая нужный язык. Auto Translation Language используется также в hotkey-сценарии с `Shift+Option+S`.

## Step 9. Включить hotkeys и понять HUD

Кадры: `06_hotkeys_settings.png`, `06_hotkeys_18_output_target_mode_settings.png`, `06_hotkeys_19_hud_over_smartscribe_context_crop.png`, `06_hotkeys_15_hud_recording_closeup_3x.png`, `06_hotkeys_16_hud_processing_closeup_3x.png`

Что сказать: `Option+S` запускает и останавливает hotkey-запись. На экране появляется маленький HUD - floating overlay. Красный HUD означает запись, зелёный HUD означает обработку. HUD можно перетаскивать мышью по экрану; приложение запоминает позицию. `Shift+Option+S` запускает похожий сценарий, но после распознавания переводит результат на Auto Translation Language из Glossary.

## Step 10. Выбрать, куда попадёт результат hotkey

Кадр: `06_hotkeys_18_output_target_mode_settings.png`

Что сказать: в блоке `Output` пользователь выбирает `Target`: `Raw`, `Variant 1` или `Variant 2`. Также выбирается `Mode`: `Clipboard` или `Type into Active App`. Clipboard просто кладёт результат в буфер обмена. Type into Active App вставляет текст в приложение, где был курсор: мессенджер, email, редактор, браузер, заметки. Для этого режима нужен Accessibility Permission.

## Step 11. Настроить общие параметры

Кадр: `07_general_settings.png`

Что сказать: здесь находятся язык интерфейса, тема, размер UI, параметры HUD, звуки начала/окончания и громкость. Это экран персонализации поведения приложения.

## Step 12. Завершить обзор: статистика, Help и macOS permissions

Кадры: `11_statistics_settings.png`, `11_help_settings.png`, `12_macos_app_menu.png`

Что сказать: статистика показывает использование, Help напоминает ключевые шаги, а macOS permissions важны для системных сценариев: микрофон, Screen/Accessibility permission для вставки в другие приложения.

## Главная мысль видео

SmartScribe - это native macOS Apple Silicon приложение для локальной транскрибации и локального polishing. Пользователь скачивает модели прямо из приложения, выбирает нужный результат (`Raw`, `Variant 1`, `Variant 2`) и может работать не только внутри SmartScribe, но и поверх любого приложения через `Option+S`, HUD и вставку результата в активное окно.
