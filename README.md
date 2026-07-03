# AI Projects Workspace

This folder is a workspace for multiple local projects. It is not itself an Electron, Swift, or Python application.

Application source belongs inside project folders such as `SmartScribe/Electron/`, `VaniScript/Electron/`, or `VaniScript/AppleSilicon/`. The workspace root should contain only workspace docs, git metadata, helper scripts, and project directories.

## Root Cleanliness Check

Run this from the workspace root if files look mixed together:

```bash
scripts/check-workspace-root-clean.sh
```

The script fails when common app source files are present at the root, for example `package.json`, `main.js`, `index.tsx`, `native/`, `assets/`, or `src/`.

