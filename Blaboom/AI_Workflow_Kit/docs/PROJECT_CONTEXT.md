# Blaboom — Project Context

## Identity

**Blaboom** — native macOS dictation / transcription / polishing app for Apple Silicon.  
Local speech engines (WhisperKit, Parakeet / FluidAudio, **Canary Core ML** in 1.0.3) + MLX/cloud text polish.  
Notarized Developer ID distribution (not App Store).

| | |
|--|--|
| **Product** | Blaboom |
| **Current train** | **1.0.3** — bilingual speech languages + Canary Core ML |
| **Platform** | macOS 14+, arm64 |
| **Stack** | Swift 6, SwiftUI, SPM (`Package.swift`) |
| **Master plan** | `BLABOOM_1.0.3_IMPLEMENTATION_PLAN.md` (only full plan) |

## Architecture (one-liner)

SwiftUI app (`NativeBlaboom`) → Core domain/services (`NativeBlaboomCore`) → local ASR engines + polish worker (`NativeBlaboomPolishWorker` / MLX) → notes / HUD / hotkeys / insert.

## Repo map

```
Blaboom/
├── BLABOOM_1.0.3_IMPLEMENTATION_PLAN.md   # authoritative plan for 1.0.3
├── Package.swift                          # SPM package NativeBlaboom
├── Sources/
│   ├── NativeBlaboom/                     # App, Views, Stores (app-layer), Services
│   ├── NativeBlaboomCore/                 # Models, domain services, glossary/notes
│   └── NativeBlaboomPolishWorker/         # MLX polish sidecar process
├── Tests/NativeBlaboomCoreTests/
├── script/                                # build_and_run, notarize, qa/*
├── docs/                                  # RELEASE, RELEASE_NOTES, screenshots
├── graphify-out/                          # knowledge graph (dev workflow)
└── AI_Workflow_Kit/                       # this orchestration kit
    ├── docs/
    │   ├── AI/                            # STATE, ORCHESTRATOR, kicks, FEEDBACK
    │   ├── BLABOOM_STEPS.md               # step cards B0–B12
    │   ├── DECISIONS.md
    │   └── PROJECT_CONTEXT.md             # this file
    └── script/
        ├── checkpoint.sh                  # scoped git tags (Blaboom/ only)
        └── graphify_rebuild.sh
```

**Git root:** parent monorepo `AI Projects/` (not a nested Blaboom-only repo).  
Checkpoint script stages **only** `Blaboom/` paths — never `git add -A` on the monorepo root.

## Build / test commands

Always `cd` into Blaboom first:

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"

# Unit / package tests (Core)
swift test

# Run app (dev)
./script/build_and_run.sh

# Versioned build
APP_VERSION=1.0.3 ./script/build_and_run.sh

# QA surface scripts
./script/qa/run_all.sh

# Release DMG (when ready)
./script/build_release_dmg.sh
./script/notarize_dmg.sh
```

## Key constraints (1.0.3)

| Allowed | Forbidden |
|---------|-----------|
| Core ML (Canary, WhisperKit, Parakeet) | Python / NeMo / PyTorch in runtime |
| MLX **only** for text polish worker | ONNX Runtime, pip/venv sidecars |
| Swift / AVFoundation / Accelerate | Fake product data / silent architecture rewrites |
| Primary + **additional** speech languages | Calling additional «target always output» |

- Marketing / `APP_VERSION`: **1.0.3** (not «1.3»).
- Parakeet / Whisper keep **auto-detect (HUD A)** by default.
- Canary: **no auto**; HUD **primary letter ↔ additional letter**.
- Workers **do not** `git commit` / `git push` — only Orchestrator checkpoints.

## Workflow docs priority

1. `BLABOOM_1.0.3_IMPLEMENTATION_PLAN.md`
2. `AI_Workflow_Kit/docs/AI/STATE.yaml`
3. `AI_Workflow_Kit/docs/BLABOOM_STEPS.md`
4. `AI_Workflow_Kit/docs/DECISIONS.md`
5. This file

## Graphify (token savings)

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"
./AI_Workflow_Kit/script/graphify_rebuild.sh
graphify query "…" --graph graphify-out/graph.json
```

Agents query the graph **before** bulk-reading Sources.
