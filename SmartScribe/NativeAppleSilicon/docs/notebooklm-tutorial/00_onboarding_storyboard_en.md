# 00. SmartScribe: User Onboarding Storyboard

Use this file as the main NotebookLM script source. The other Markdown files and PNG screenshots explain individual screens. The video should follow the journey of a new user: install local models first, understand the main workspace, then learn the hotkey + HUD workflow and output into other apps.

## Step 1. Install a Local Transcription Model

The user starts in `Settings -> Local Models`.

Screenshot: `03_local_transcription_models_settings.png`

Narration: SmartScribe can download local WhisperKit/Core ML speech models directly from inside the app. These models convert audio into text. The user chooses a model, clicks `Download`, then clicks `Use` after installation. A model can also be removed with `Delete`. For Russian, mixed-language speech, and multilingual use cases, choose a multilingual model such as Whisper Large v3.

## Step 2. Install a Local Polishing Model

After speech recognition, SmartScribe can run a separate text-polishing layer.

Screenshot: `04_local_polishing_models_settings.png`

Narration: the polishing model is not the audio transcription model. It takes raw transcription and turns it into clean text: removing repetitions, improving structure, and preparing Variant 1 or Variant 2. Local polishing models are downloaded from inside the app, selected with `Use`, and removed with `Delete`.

## Step 3. Treat API Providers as Optional

Screenshot: `05_api_providers_settings.png`

Narration: SmartScribe can use local models first. API providers are optional and only matter if the user chooses an external polishing or translation provider. The core onboarding should emphasize the local-first workflow.

## Step 4. Return to the Main Workspace

Screenshots: `01_app_overview.png`, `02_main_01_window_initial.png`

Narration: the left sidebar contains notes and recordings. The right side shows the selected note. At the top, the user selects the transcription model and the polishing model. Below that are `Raw`, `Variant 1`, and `Variant 2`.

## Step 5. Record or Import Audio

Screenshots: `02_main_01_window_initial.png`, `02_main_05_transcription_model_menu.png`

Narration: SmartScribe can transcribe audio recorded in the app and audio files imported by the user. After transcription, the raw result is saved as a note. That raw result becomes the base for polishing.

## Step 6. Understand Raw, Variant 1, and Variant 2

Screenshots: `02_main_02_raw_tab.png`, `02_main_03_variant_1_tab.png`, `02_main_04_variant_2_tab.png`

Narration: `Raw` is the direct transcription. `Variant 1` is a light cleanup of dictation. `Variant 2` is stronger editing and structuring. The user chooses the result that fits the current task.

## Step 7. Customize Prompt Slots

Screenshots: `08_prompts_01_variant_one.png`, `08_prompts_02_variant_two.png`, `08_prompts_03_markdown.png`

Narration: Variant 1 and Variant 2 are controlled by prompt templates. The user can customize the default prompt, slots `1`, `2`, `3`, `4`, and the Markdown mode. This turns SmartScribe into a reusable writing workflow, not just a recorder.

## Step 8. Configure Glossary and Translation

Screenshots: `09_glossary_01_settings.png`, `09_glossary_02_add_context_menu.png`, `09_glossary_03_selected_text.png`, `10_translation_modal.png`

Narration: the glossary helps preserve important terms, names, and user-specific vocabulary. Translation can run on selected text or clipboard text. The Auto Translation Language is also used by the `Shift+Option+S` hotkey workflow.

## Step 9. Enable Hotkeys and Understand the HUD

Screenshots: `06_hotkeys_settings.png`, `06_hotkeys_18_output_target_mode_settings.png`, `06_hotkeys_19_hud_over_smartscribe_context_crop.png`, `06_hotkeys_15_hud_recording_closeup_3x.png`, `06_hotkeys_16_hud_processing_closeup_3x.png`

Narration: `Option+S` starts and stops hotkey recording. A small HUD appears as a floating overlay. A red HUD means recording; a green HUD means processing. The user can drag the HUD anywhere on the screen, and SmartScribe remembers the position. `Shift+Option+S` runs a similar workflow, but after transcription it translates the result to the Auto Translation Language from Glossary.

## Step 10. Choose Where the Hotkey Result Goes

Screenshot: `06_hotkeys_18_output_target_mode_settings.png`

Narration: in the `Output` section, the user chooses the `Target`: `Raw`, `Variant 1`, or `Variant 2`. The user also chooses the `Mode`: `Clipboard` or `Type into Active App`. Clipboard copies the result. Type into Active App inserts text into the app where the cursor was: a messenger, email, editor, browser, or notes app. This mode requires Accessibility Permission.

## Step 11. Adjust General Settings

Screenshot: `07_general_settings.png`

Narration: this screen controls interface language, theme, UI scale, HUD behavior, start/finish sounds, and volume. It is the personalization screen for the app.

## Step 12. Finish with Statistics, Help, and macOS Permissions

Screenshots: `11_statistics_settings.png`, `11_help_settings.png`, `12_macos_app_menu.png`

Narration: Statistics shows usage, Help summarizes the key workflow, and macOS permissions matter for system-level workflows: microphone access and Accessibility permission for typing into other apps.

## Core Message

SmartScribe is a native macOS Apple Silicon app for local transcription and local polishing. The user downloads models from inside the app, chooses the desired output (`Raw`, `Variant 1`, or `Variant 2`), and can work not only inside SmartScribe but also on top of any app using `Option+S`, the HUD, and output into the active window.
