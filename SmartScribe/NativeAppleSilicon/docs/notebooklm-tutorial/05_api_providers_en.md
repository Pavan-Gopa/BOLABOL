# 04. API Providers

## `05_api_providers_settings.png`

This tab connects cloud providers for text polishing:

- Google Gemini
- OpenAI
- Anthropic
- Custom OpenAI-Compatible

Each provider has an API key and a text model. The custom provider also has a provider name and base URL.

## Narration Points

- API providers are used for polishing and translation, not for local Whisper transcription.
- `Use for Polishing` selects that provider as the active polishing engine.
- A provider is considered configured when it has an API key and model.
- The screenshot masks the API key with bullets; the real secret is not visible.

## When to Use API

Use an API when you need stronger text editing than local MLX or when no local polishing model is installed. The tradeoff is privacy: the text is sent to an external provider.

