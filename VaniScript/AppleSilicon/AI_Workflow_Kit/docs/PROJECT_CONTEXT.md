# Project Context

> Fill this once when dropping the kit into a new repo.  
> Orchestrator and workers treat this as the map of the territory.

## Identity

| | |
|--|--|
| **Product** | VaniScript Apple Silicon |
| **One-liner** | Native macOS workflow for media import/recording, transcription, translation, review, and export using local and explicitly configured cloud providers. |
| **Platform** | macOS 14+, Apple Silicon (`arm64`) |
| **Stack** | Swift 6, SwiftUI, AppKit, SwiftPM, WhisperKit/Core ML, MLX Swift, FluidAudio |
| **Current train / version** | Active native Apple Silicon application |
| **Project prefix** (git tags) | `vaniscript-as` |
| **Master plan file** | `docs/PRD-Document-Literary-Translation.md` + `AI_Workflow_Kit/docs/STEPS.md` S7–S13 |

## Architecture (one-liner)

SwiftUI/AppKit views → `WorkflowStore` orchestration → native processing, provider, MCP, and export services → `VaniScriptCore` domain models, contracts, and persistence.

## Repo map

```text
VaniScript/AppleSilicon/
├── Sources/VaniScript/        # executable app, views, stores, native services
├── Sources/VaniScriptCore/    # reusable domain models, contracts, provider logic
├── Tests/                     # app and core Swift tests
├── QA/                        # surface/contract QA and reports
├── script/                    # build, run, packaging, media-tool scripts
├── Assets/                    # application icons
├── AI_Workflow_Kit/           # orchestration state and scripts
├── .omp/                      # project agents, commands, role-model mappings
├── grilling/                  # discovery and decision skill
└── graphify-out/              # ignored local knowledge graph
```

**Git layout:** workspace repository rooted at `AI Projects`; this project is
the `VaniScript/AppleSilicon` subfolder. Checkpoints must stay scoped to this
stage path and must not include sibling projects.

## OMP workflow

Launch from this project root:

```bash
bash AI_Workflow_Kit/script/omp_workflow.sh
```

Project agents and primary/backup model aliases live in `.omp/`. The Human may
change any `modelRoles.workflow_*` mapping through `Alt+M` without changing role
instructions.

## Build / test commands

Always run from `VaniScript/AppleSilicon`:

```bash
swift build
swift test
bash QA/run_all.sh

# Build and launch the fresh native app
./script/build_and_run.sh

# Build/run verification mode
./script/build_and_run.sh --verify
```

## Key constraints

| Allowed | Forbidden |
|---------|-----------|
| Native Swift/SwiftUI/AppKit, Core ML/WhisperKit, MLX Swift, explicit CLI/cloud integrations | Electron, Node, or browser runtimes inside the native app |
| Secrets in settings, Keychain, or child-process environment | Secrets in sources, logs, Git, or workflow reports |
| Explicit provider selection and honest capability/error reporting | Silent MCP-chat → API fallback or fabricated provider balances/capabilities |

Additional hard rules for this product:

- Build only for Apple Silicon (`arm64`) and preserve the macOS 14 minimum.
- Do not modify the Electron VaniScript or SmartScribe sibling projects.
- Keep provider usage recording best-effort; telemetry failure must not break product operations.

## Workflow docs priority

1. Master plan file (if any)
2. `AI_Workflow_Kit/docs/AI/STATE.yaml`
3. `AI_Workflow_Kit/docs/STEPS.md`
4. `AI_Workflow_Kit/docs/DECISIONS.md`
5. This file

## Graphify

```bash
cd "<PROJECT_ROOT>"
bash AI_Workflow_Kit/script/graphify_rebuild.sh
graphify query "…" --graph graphify-out/graph.json
```

The rebuild attempts semantic extraction and falls back to local AST code-only
indexing when no supported LLM backend is configured.
