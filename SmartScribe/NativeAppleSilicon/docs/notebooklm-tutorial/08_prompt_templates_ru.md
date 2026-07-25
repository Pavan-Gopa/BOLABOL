# 07. Prompt Templates

## `08_prompts_01_variant_one.png`

Variant 1 prompt - лёгкая редактура диктовки. Он строго сохраняет язык, смысл и детализацию, убирая повторы, filler words и очевидные ошибки.

## `08_prompts_02_variant_two.png`

Variant 2 prompt - более сильная редактура. Он делает текст яснее и структурнее, но не должен добавлять факты, выводы или новый смысл.

## `08_prompts_03_markdown.png`

Markdown prompt превращает текст в clean Markdown: headings, paragraphs, lists, emphasis, code blocks - только если это реально уместно. Важно: prompt должен содержать `${transcription}`. Без placeholder приложение показывает предупреждение, потому что модель должна знать, куда вставлять исходный текст.

## Prompt slots

Для Variant 1 и Variant 2 есть слоты:

- `D` - default prompt.
- `1`, `2`, `3`, `4` - пользовательские варианты prompt.

На главном экране можно быстро переключать slot для выбранного варианта. Это удобно, если нужны разные стили: universal cleanup, technical text, devotional terms, meeting notes и так далее.

