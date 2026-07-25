# 02. Local Models: локальная транскрибация

## `03_local_transcription_models_settings.png`

Эта вкладка отвечает за локальные WhisperKit/Core ML модели для распознавания речи. Вверху показана активная модель, ниже - каталог доступных моделей с кнопками `Download`, `Use`, `Delete` и статусом `Selected`.

## Что объяснить в видео

- Эти модели нужны именно для аудио -> текст.
- Они работают локально на Apple Silicon через WhisperKit/Core ML.
- `Whisper Small` быстрее и легче.
- `Whisper Medium` балансирует качество и скорость.
- `Whisper Large v3` / `Large v3 Turbo` дают более высокое качество для multilingual-сценариев.
- English-only модели подходят для английской речи; multilingual модели нужны для русского, смешанной речи и других языков.

## Где лежат модели

Код использует общий корень локальных моделей:

- переменная окружения `AI_LOCAL_MODELS_DIR`, если задана;
- конфиг `~/Library/Application Support/AILocalModels/config.json`, если есть;
- по умолчанию `~/AI_LOCAL_MODELS/whisperkit`;
- legacy fallback внутри `~/Library/Application Support/NativeSmartScribe/Models/Transcription/WhisperKit`.

## Безопасность

Загрузка модели - сетевое действие и может занимать сотни мегабайт или гигабайты. В tutorial лучше показывать, где нажимать, но не запускать загрузку без необходимости.

