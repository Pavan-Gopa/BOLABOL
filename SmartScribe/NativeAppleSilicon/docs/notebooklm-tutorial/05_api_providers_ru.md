# 04. API Providers

## `05_api_providers_settings.png`

Вкладка подключает cloud-провайдеры для text polishing:

- Google Gemini
- OpenAI
- Anthropic
- Custom OpenAI-Compatible

Для каждого провайдера есть API key и имя text model. Для custom provider также есть provider name и base URL.

## Что объяснить

- API provider используется для polishing и translation, не для локальной Whisper-транскрибации.
- Кнопка `Use for Polishing` выбирает provider как активный polishing engine.
- Provider считается configured, когда есть API key и модель.
- На screenshot ключ скрыт точками; реальный secret не виден.

## Когда использовать API

API полезен, если нужна более сильная модель, чем локальная MLX, или если локальная модель не установлена. Минус - текст отправляется внешнему провайдеру, поэтому приватные материалы лучше обрабатывать локально.

