# AGENTS.md

This directory is an `AI Projects` workspace. Keep application code inside the owning project folder and do not place app source files in the workspace root.

## Project Map

- `SmartScribe/Electron/` - Electron SmartScribe. Run Node/Electron commands from this folder.
- `SmartScribe/NativeAppleSilicon/` - native Swift/SwiftUI SmartScribe local workspace data.
- `VaniScript/Electron/` - Electron VaniScript nested git repository.
- `VaniScript/AppleSilicon/` - native Swift/SwiftUI VaniScript local workspace.
- `VaniScript/AudioEngine/` - VaniScript audio-engine prototype/tooling.
- `Chunker/` - Audio Chunker nested git repository.
- `KirtanPlugin/` - Kirtan plugin project.
- `MindOcean/` - MindOcean standalone git repository.
- `ZerdaProject/` - Zerda project files.
- `Antigravity/` - standalone Antigravity workspace.
- `KirtanSplitter/` - local kirtan/audio splitting prototype.
- `ModelAssets/`, `Research/`, `SmartScribe/UserData/`, and `VaniScript/UserData/` - local data/reference material, intentionally ignored by this workspace repository.

## Working Rules

- Do not run `npm`, `swift`, `xcodebuild`, `electron-builder`, or package scripts from this workspace root.
- Before working on an app, `cd` into the owning project folder.
- Keep generated artifacts inside the owning project folder.
- Do not move files across projects unless the task is explicitly about workspace organization.
- Preserve nested git repositories as nested projects.
- If app-looking files appear in this root, run `scripts/check-workspace-root-clean.sh` and move them into the correct project folder before continuing.

## Useful Commands

```bash
cd SmartScribe/Electron && npm run compile
cd VaniScript/Electron && npm run build
cd VaniScript/AppleSilicon && swift test
```

