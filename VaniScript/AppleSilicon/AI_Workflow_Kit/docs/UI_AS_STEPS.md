# UI_AS — Apple Silicon visual density (after GROK_DONE)

> **Track:** `UI_AS`  
> **Scope:** **Apple Silicon only** — Electron visual redesign is out of scope  
> **Git:** `ui/pre-Un` / `ui/Un-done`  
> **Extra gate:** after Gemini APPROVED, Orchestrator visual check when practical  

## Overview

| Step | Name |
|------|------|
| **U0** | Density tokens in `VaniScriptTheme` |
| **U1** | Compact `SliderRow` / `OptionalSliderRow` |
| **U2** | VisualClipEditor inspector / toolbar density |
| **U3** | App chrome density (optional) |
| **UI_DONE** | Acceptance |

Do **not** change crop/timeline/render logic — chrome only.

---

## U0 — Theme density tokens

### Цель
Единая шкала spacing / control height / radius.

### Требования
1. Extend `VaniScriptTheme` with density tokens (e.g. space4/6/8/12, controlHeight 22–28, radius 8–12).
2. No mass restyle of all screens yet — tokens available for later steps.
3. Keep accent orange + glass aesthetic.

### target_files
- `Sources/VaniScript/Theme/VaniScriptTheme.swift`

### Не делать
- VisualClipEditor logic, Electron CSS

---

## U1 — Compact sliders

### Цель
`SliderRow` / `OptionalSliderRow` выглядят тоньше и современнее.

### target_files
- `Sources/VaniScript/Views/VisualClipEditorView.swift` (slider components section only)

### Не делать
- Timeline engine, export, Electron

---

## U2 — Visual editor inspector density

### Цель
Меньше padding, quieter tabs, denser inspector — без поломки preview/hotkeys.

### target_files
- `Sources/VaniScript/Views/VisualClipEditorView.swift`

### Visual acceptance
- [ ] Sliders usable, labels not clipped
- [ ] 9:16 preview OK
- [ ] Light/dark OK

---

## U3 — App chrome (optional)

### Цель
Sidebars / Settings / Chat / **Export** density aligned with editor.

### Требования
1. Apply `VaniScriptTheme.Density` tokens to chrome spacing (padding, control heights, radii) on:
   - Sidebars, main shell (`ContentView`)
   - Settings
   - Chat sidebar
   - **Export workspace** (`ExportWorkspaceView`) — controls grid, cards, buttons, section spacing
2. No export pipeline / shorts planner / render logic changes — chrome only.
3. Apple Silicon only; no Electron visual pass.

### target_files
- `Sources/VaniScript/Views/SidebarView.swift`
- `Sources/VaniScript/Views/ContentView.swift`
- `Sources/VaniScript/Views/SettingsView.swift`
- `Sources/VaniScript/Views/ChatSidebarView.swift`
- `Sources/VaniScript/Views/ExportWorkspaceView.swift`
- `Sources/VaniScript/Theme/VaniScriptTheme.swift` (if needed)

### Не делать
- Electron redesign
- MCP/Grok logic beyond spacing/chrome
- Shorts render / export algorithm changes

---

## UI_DONE

Human + orchestrator sign-off; no further auto steps.
