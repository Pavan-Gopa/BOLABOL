# 08. Glossary

## `09_glossary_01_settings.png`

Glossary is a local correction dictionary. It does not train Whisper and does not bias the recognition model. It is applied after recognition or after translation as deterministic text rewriting.

## Settings Screenshot

- `Use glossary` enables or disables glossary rewriting.
- `Transcription` is the source language form, such as Russian.
- `Translation` is the auto-translation language form, such as English.
- Search and Category filter entries.
- New Entry creates a new rule.
- Import / Export supports JSON and CSV.
- Each entry row has source form, translation form, category, variants, Merge Into, Save, and Delete.

## `09_glossary_02_add_context_menu.png`

Selected text in a note opens a context menu with `Add to Glossary`. This is the fast path for taking a misrecognized word from the result and adding it as a variant of the correct form.

## `09_glossary_03_selected_text.png`

This shows the state before adding: a text fragment is selected and ready for the glossary workflow. In real use, the user selects the wrong recognition, opens the context menu, and creates or updates a glossary entry.

## How Glossary Is Applied

- Normal transcription applies the glossary to source text.
- Translation workflow can apply the glossary to translated text using the selected target language.
- For names, technical terms, and Sanskrit/IAST forms, it is often best to keep a canonical source form and store ASR mistakes as variants.

## Example Explanation

If Whisper recognizes a term incorrectly, the user selects the wrong version, chooses `Add to Glossary`, enters the correct form and category, and SmartScribe can replace that variant automatically in future output.

