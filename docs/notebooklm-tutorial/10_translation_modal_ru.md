# 09. Translation Modal

## `10_translation_modal.png`

Translation modal открывается из нижней панели главного окна. Он переводит выделенный текст или clipboard. В screenshot показаны provider, target language, original panel, translated panel, record button, refresh и translate button.

## Что объяснить

- Provider может быть локальной MLX-моделью или API provider.
- Target Language выбирается из списка или вводится вручную.
- Original можно редактировать.
- Translated отображает результат и может быть скопирован.
- Record внутри modal позволяет надиктовать текст именно для перевода.
- Glossary может применяться к переводу по target language.

## Отличие от Variant 1 / Variant 2

Variant 1 и Variant 2 редактируют текст в том же языке. Translation modal меняет язык результата. Это отдельный workflow.

