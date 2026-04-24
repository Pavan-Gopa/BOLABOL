# Native macOS SmartScribe Roadmap

> **For future implementation agents:** use `superpowers:writing-plans` for detailed task plans, then `superpowers:subagent-driven-development` or `superpowers:executing-plans` for task-by-task implementation.

**Goal:** Build a new macOS-only SmartScribe app in Swift, next to the existing Electron app, with native UI, local model management, fast on-device polishing, and a modern Apple design language.

**Architecture:** Keep the existing Electron version untouched. Create a new app under `NativeSmartScribe/` and rebuild the product as a native SwiftUI/AppKit macOS app. Treat transcription, polishing, model management, audio capture, notes, hotkeys, and overlay UI as separate services instead of one large application class.

**Confirmed Product Decisions:** folder/app name is `NativeSmartScribe`; GitHub repository should be private; minimum hardware target is Apple Silicon starting with M1, with no Intel support requirement.

**Initial Constraint:** `/Users/pavan/Documents/smartscribe` is currently not a git repository. Before branch/GitHub work, initialize git at the root, add a careful `.gitignore`, commit the Electron baseline, then create a dedicated native rewrite branch.

---

## Skill Set

- `build-macos-apps:swiftui-patterns`: SwiftUI scene structure, settings, split views, app state ownership.
- `build-macos-apps:liquid-glass`: modern macOS / Liquid Glass visual direction.
- `build-macos-apps:appkit-interop`: global hotkeys, menu bar, paste automation, window/overlay edges.
- `build-macos-apps:window-management`: main window, HUD/overlay windows, menu-bar behavior.
- `build-macos-apps:build-run-debug`: `xcodebuild`, run script, logs, launch verification.
- `build-macos-apps:telemetry`: unified logging for audio/model/polish pipeline diagnostics.
- `build-macos-apps:test-triage`: Swift/Xcode test failures during implementation.
- `build-macos-apps:signing-entitlements`: microphone, accessibility, app sandbox, model file access.
- `build-macos-apps:packaging-notarization`: distribution, signing, notarization, DMG.
- `github:github` and `github:yeet`: GitHub repo/branch/PR workflow when ready.
- `superpowers:writing-plans`: detailed implementation plans per phase.
- `superpowers:verification-before-completion`: verify builds/tests before claiming completion.

---

## Repository Strategy

1. Initialize git at `/Users/pavan/Documents/smartscribe`, not inside a nested folder.
2. Add `.gitignore` before the first commit to exclude `node_modules/`, `dist/`, `build/`, temporary files, local models, Xcode derived data, and downloaded model artifacts.
3. Commit the current Electron app as a baseline without functional edits.
4. Create branch `native-macos-rewrite`.
5. Create `NativeSmartScribe/` inside the root and keep all new Swift work there.
6. Create a GitHub repository after the baseline commit and push both `main` and `native-macos-rewrite`.

Confirmed GitHub creation target: private repository.

---

## Native App Shape

Confirmed folder:

```text
NativeSmartScribe/
  NativeSmartScribe.xcodeproj/
  NativeSmartScribe/
    App/
    Views/
    Models/
    Stores/
    Services/
    Engines/
    Support/
    Resources/
  NativeSmartScribeTests/
  script/build_and_run.sh
```

Use an Xcode macOS app project rather than a bare SwiftPM GUI package. This gives better control over app resources, entitlements, signing, package dependencies, and future distribution. Swift packages such as MLX Swift can still be added as dependencies.

---

## Product Architecture

- `App`: app entrypoint, scene definitions, app delegate bridge.
- `Views`: SwiftUI main window, sidebar, editor, settings, model manager, translation, overlay controls.
- `Stores`: persisted settings, notes/history, model state, usage/benchmark records.
- `Services`: audio capture, hotkey handling, clipboard/paste, file import, logging, permissions.
- `Engines/Transcription`: Whisper/Parakeet adapter first; later MLX/Core ML transcription options.
- `Engines/Polishing`: replace Ollama HTTP with in-app engines.
- `Engines/Models`: download, install, validate, warm up, benchmark, and remove models.

Core rule: no new 6,000-line root view. Every subsystem should have a narrow interface and tests where practical.

---

## Model / Inference Strategy

1. `PolishingEngine` is the primary rewrite target.
2. Start with a protocol-based engine boundary:
   - `MLXSwiftPolishingEngine` for fast Apple GPU / Metal local inference.
   - `CoreMLPolishingEngine` for models that can realistically run through Core ML and potentially ANE.
   - `FoundationModelsPolishingEngine` if the target macOS and Apple Intelligence constraints make it useful.
   - `CloudPolishingEngine` as optional fallback.
3. Do not assume MLX uses the Neural Engine. Treat MLX as the practical GPU/Metal path.
4. Treat ANE support as a measured Core ML path, not a promise. Add a benchmark screen showing actual backend, tokens/sec, load time, memory, and thermal behavior.
5. Keep transcription pluggable. Parakeet/Whisper are acceptable baseline engines because the user is not blocked by their current CPU/GPU behavior.

---

## UI Direction

Build a modern macOS app, not a web UI clone.

- Main window: `NavigationSplitView` with native sidebar/history and a detail editor.
- Toolbar: record, import audio, copy, translate, model selector, search, settings.
- Detail view: Raw / Variant 1 / Variant 2 as native segmented tabs or sections.
- Settings: native `Settings` scene with General, Audio, Transcription, Polishing, Models, Hotkey, Privacy.
- Overlay: small AppKit/SwiftUI HUD using system materials/glass for listening and processing states.
- Visual style: system materials first, Liquid Glass only for surfaces that benefit from it.

Avoid heavy custom chrome, always-on blur layers, and decorative glass everywhere.

---

## Implementation Phases

### Phase 0: Repo and Scaffold

- Initialize git, create baseline commit, branch `native-macos-rewrite`.
- Create `NativeSmartScribe/`.
- Scaffold Xcode macOS SwiftUI project.
- Add `script/build_and_run.sh` and Codex Run action.
- Verify app builds and opens.

### Phase 1: Native Shell

- Build main window, sidebar/detail layout, settings scene, toolbar, theme-safe materials.
- Add placeholder note data and local persistence.
- Add unified logging and simple diagnostics panel.

### Phase 2: Audio and Notes

- Implement microphone permission flow.
- Implement audio capture service and silence detection.
- Store raw recording metadata.
- Add file import path for audio.

### Phase 3: Transcription Baseline

- Add pluggable `TranscriptionEngine`.
- Start with the least risky local backend adapter.
- Preserve raw transcript behavior and language settings.
- Add timing and backend diagnostics.

### Phase 4: Native Polishing Engine

- Implement `PolishingEngine` protocol and prompt templates.
- Add local MLX Swift proof of concept.
- Add one fast local model path for V1/V2 polishing.
- Replace parallel duplicate polishing with a single structured generation where possible.
- Add benchmark and model warm-up.

### Phase 5: Core ML / ANE Track

- Research candidate polish models that can be converted and run well through Core ML.
- Add `CoreMLPolishingEngine` only after a small measurable prototype succeeds.
- Expose actual compute path as diagnostics, not marketing text.

### Phase 6: Feature Parity

- Hotkey recording and paste behavior.
- Translation flow.
- Model manager with download/remove/state.
- Usage stats and processing history.
- Error dialogs and recovery flows.

### Phase 7: Polish and Distribution

- UI refinement with Liquid Glass rules.
- Accessibility pass.
- Performance and thermal testing on Apple Silicon.
- Signing, entitlements, packaging, notarization.

---

## Immediate Next Step

Proceed with:

1. `NativeSmartScribe` as the folder and app name.
2. Private GitHub repository.
3. Apple Silicon only, starting with M1. Intel compatibility is out of scope.
