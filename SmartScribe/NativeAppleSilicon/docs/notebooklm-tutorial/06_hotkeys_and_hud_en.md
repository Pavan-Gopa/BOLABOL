# 06. Hotkeys and HUD: Dictation on Top of Any App

This section should be presented as a real user workflow: the user is inside another app, presses `Option+S`, dictates text, sees the HUD, stops recording, and receives the result in the chosen format.

## Screenshots in This Section

- `06_hotkeys_settings.png` - top of Hotkey settings: enable switch, `Alt+S`, `Alt+Shift+S`, recognition language, Accessibility Permission.
- `06_hotkeys_18_output_target_mode_settings.png` - bottom of Hotkey settings: `Target` and `Mode`.
- `06_hotkeys_19_hud_over_smartscribe_context_crop.png` - HUD in app context.
- `06_hotkeys_15_hud_recording_closeup_3x.png` - enlarged red recording HUD.
- `06_hotkeys_16_hud_processing_closeup_3x.png` - enlarged green processing HUD.
- `06_hotkeys_11_hud_recording_clean_window.png` and `06_hotkeys_13_hud_processing_clean_window.png` - original system captures of the small HUD panel without enlargement.

## What the HUD Is

`HUD` means heads-up display. In SmartScribe, it is a small floating overlay shown on top of the screen. It does not behave like a normal window and does not steal focus from the active app. The user can drag it with the mouse, and SmartScribe remembers the position for the next session.

Important for the video: the HUD does not display long text. It communicates state with color and waveform:

- red waveform - SmartScribe is recording;
- green waveform - recording has stopped and SmartScribe is processing the result;
- the panel is translucent, so the tutorial should show the enlarged close-up screenshots.

## `Option+S`: Normal Hotkey Recording

The user can be in any app: messenger, email, browser, notes, or text editor. The user places the cursor where the result should go and presses `Option+S`.

What happens:

1. SmartScribe remembers the active app and focused input field.
2. A red HUD appears.
3. Microphone recording starts.
4. Pressing `Option+S` again stops recording.
5. The HUD turns green: this is the transcription, polishing, and output-preparation stage.
6. The final text goes wherever `Output` is configured to send it.

## `Shift+Option+S`: Targeted Translation Hotkey

`Shift+Option+S` starts a similar workflow, but after transcription SmartScribe translates the result to the `Auto Translation Language` configured in Glossary/translation settings. This is useful when the user speaks in one language but wants the final text in another language.

Example narration: the user can dictate in Russian, press `Shift+Option+S`, and receive the result in English if Auto Translation Language is set to `English`.

## Output: Target and Mode

Screenshot: `06_hotkeys_18_output_target_mode_settings.png`

`Target` decides which text the hotkey workflow uses:

- `Raw` - direct transcription without polishing;
- `Variant 1` - lightly edited result;
- `Variant 2` - stronger editing and structuring.

`Mode` decides where the text goes:

- `Clipboard` - SmartScribe copies the result to the clipboard; the user pastes it manually;
- `Type into Active App` - SmartScribe inserts the result into the active app where the cursor was.

`Type into Active App` requires Accessibility Permission. Clipboard mode does not require Accessibility Permission.

## Suggested Narration

“The main advantage of hotkey mode is that I do not have to keep returning to the SmartScribe window. I can stay in any app, press `Option+S`, dictate, see the red recording HUD, stop the recording, see the green processing HUD, and receive the result as Raw, Variant 1, or Variant 2. The result can be copied to the clipboard or inserted directly into the active input field.”
