# 01. Main Workspace

## `02_main_01_window_initial.png`

This is the main SmartScribe window. The left sidebar contains notes with dates and preview text. The right side shows the selected note: audio metadata, transcription model selector, polishing model selector, Raw / Variant 1 / Variant 2 tabs, the main text editor, and the bottom action bar.

Narration: SmartScribe behaves like a dictation notebook. Each recording becomes a note. The user can copy one note or copy all notes from the sidebar.

## `02_main_02_raw_tab.png`

Raw is the direct transcription output. It is the closest text to the audio before creative cleanup. Use it to check recognition quality and as the source for polishing.

## `02_main_03_variant_1_tab.png`

Variant 1 is light cleanup. It removes repeated words, filler words, and self-corrections while preserving language, meaning, and detail level. The upper-right buttons show prompt slots: `D`, `1`, `2`, `3`, `4`, plus `M` for Markdown.

## `02_main_04_variant_2_tab.png`

Variant 2 is the stronger rewrite. It aims for clearer structure and sharper wording. It should not translate or invent facts; it rewrites the same meaning more actively.

## `02_main_05_transcription_model_menu.png`

This menu selects the transcription model used in the workspace. It shows models that are already available. To install models, use Settings -> Local Models.

## `02_main_06_polishing_model_menu.png`

This menu selects the polishing engine. It can include:

- `Polishing Disabled`
- local MLX models such as Qwen
- API providers such as Google Gemini when configured

Narration: transcription model and polishing model are separate. The first recognizes audio; the second edits text.

