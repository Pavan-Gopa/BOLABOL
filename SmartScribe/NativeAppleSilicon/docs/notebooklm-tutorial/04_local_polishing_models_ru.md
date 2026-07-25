# 03. Polishing: локальные MLX-модели

## `04_local_polishing_models_settings.png`

Эта вкладка отвечает за text polishing - улучшение уже распознанного текста. Здесь показаны локальные MLX-модели: Qwen 3.5 разных размеров и NVIDIA Nemotron-3 Nano. Вверху есть `Scan for Local Models`.

## Что такое polishing

Polishing не слушает аудио. Он берёт текст и применяет prompt: чистит диктовку, переписывает её в Variant 1 / Variant 2 или превращает в Markdown.

## Как выбирать модель

- `0.8B` - лёгкая тестовая модель, быстрая, но слабее по качеству.
- `2B` - быстрый вариант для короткого polishing.
- `4B` - рекомендуемый баланс качества и скорости.
- `9B` - выше качество, но медленнее и тяжелее.
- Nemotron-3 Nano 4B - компактная альтернативная модель.

## Scan for Local Models

Кнопка сканирует:

- общий корень `~/AI_LOCAL_MODELS/mlx`;
- Hugging Face cache `~/.cache/huggingface/hub`;
- `~/Documents`;
- `~/Downloads`.

Она добавляет совместимые локальные MLX text-generation модели в список. Удаление custom model удаляет только запись из списка, а не файлы модели на диске.

## Важное предупреждение

Reasoning/thinking модели могут выводить рассуждения в результате и работать медленнее. Для polishing лучше использовать instruct-модель без chain-of-thought.

