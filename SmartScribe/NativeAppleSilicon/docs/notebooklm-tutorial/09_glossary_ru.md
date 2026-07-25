# 08. Glossary

## `09_glossary_01_settings.png`

Glossary - локальный словарь исправлений. Он не обучает Whisper и не bias-ит модель. Он применяется после распознавания или после перевода как deterministic text rewrite.

## Что видно на Settings screenshot

- `Use glossary` включает или выключает применение словаря.
- `Transcription` - язык исходной формы, например Russian.
- `Translation` - язык auto-translation формы, например English.
- Search и Category фильтруют entries.
- New Entry создаёт новое правило.
- Import / Export поддерживает JSON и CSV.
- Entry row содержит source form, translation form, category, variants, Merge Into, Save, Delete.

## `09_glossary_02_add_context_menu.png`

Выделенный текст в заметке открывает context menu с пунктом `Add to Glossary`. Это быстрый способ взять ошибочное распознавание из результата и добавить его как variant к правильной форме.

## `09_glossary_03_selected_text.png`

Показывает состояние перед добавлением: выбран фрагмент текста, который можно отправить в glossary workflow. В реальной работе пользователь выбирает неверно распознанный термин, открывает context menu и создаёт/обновляет glossary entry.

## Как glossary применяется

- В обычной транскрибации glossary применяется к source text.
- В translation workflow glossary может применяться к translated text через выбранный target language.
- Для имён, терминов и санскрит/IAST форм часто лучше хранить canonical source form и variants как ошибки распознавания.

## Пример объяснения

Если Whisper распознал термин неправильно, пользователь выделяет неправильный вариант, выбирает `Add to Glossary`, указывает правильную форму и категорию. После этого SmartScribe может автоматически заменять этот variant на canonical form.

