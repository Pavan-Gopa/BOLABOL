# 02. Local Models: Local Transcription

## `03_local_transcription_models_settings.png`

This tab manages local WhisperKit/Core ML speech recognition models. The top area shows the active model. The list below shows available models with `Download`, `Use`, `Delete`, and `Selected` states.

## Narration Points

- These models are for audio -> text.
- They run locally on Apple Silicon through WhisperKit/Core ML.
- `Whisper Small` is faster and lighter.
- `Whisper Medium` balances quality and speed.
- `Whisper Large v3` / `Large v3 Turbo` improve quality for multilingual use.
- English-only models are for English speech; multilingual models are for Russian, mixed speech, and other languages.

## Model Location

The code resolves the shared local model root in this order:

- `AI_LOCAL_MODELS_DIR`, if set;
- `~/Library/Application Support/AILocalModels/config.json`, if present;
- default `~/AI_LOCAL_MODELS/whisperkit`;
- legacy fallback under `~/Library/Application Support/NativeSmartScribe/Models/Transcription/WhisperKit`.

## Safety

Downloading a model uses the network and can require hundreds of megabytes or gigabytes. In a tutorial, show where the button is, but avoid starting a real download unless needed.

