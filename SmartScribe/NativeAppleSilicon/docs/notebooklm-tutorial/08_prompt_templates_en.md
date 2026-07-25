# 07. Prompt Templates

## `08_prompts_01_variant_one.png`

Variant 1 is light dictation cleanup. It preserves language, meaning, and detail level while removing repeated words, filler words, and obvious errors.

## `08_prompts_02_variant_two.png`

Variant 2 is stronger editing. It makes the text clearer and more structured, but it should not add facts, conclusions, or new meaning.

## `08_prompts_03_markdown.png`

The Markdown prompt converts text into clean Markdown: headings, paragraphs, lists, emphasis, and code blocks only when appropriate. Important: the prompt must contain `${transcription}`. Without this placeholder, the app warns the user because the model would not know where to insert the source text.

## Prompt Slots

Variant 1 and Variant 2 have slots:

- `D` is the default prompt.
- `1`, `2`, `3`, `4` are custom prompt slots.

The main workspace can switch slots quickly. This is useful for different styles: universal cleanup, technical text, devotional terminology, meeting notes, and so on.

