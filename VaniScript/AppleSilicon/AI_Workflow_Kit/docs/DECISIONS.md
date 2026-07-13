# DECISIONS — VaniScript multi-agent program

## D-2026-07-13 — Orchestration model

- Roles mirror **AuraSplitter / KirtanSplitter** `AI_Workflow_Kit`.
- Orchestrator: **Grok**. Implementation: **Hy3/Coder**. Verification: **Gemini 3.5 Flash**.
- File bus only: `STATE.yaml` + `FEEDBACK.md`.
- **Git checkpoint before every step and after every approved step** (commit + tag + push when possible).

## D-2026-07-13 — Product scope

1. **GROK_MCP first** (AS + Electron functional Grok).
2. **UI_AS second** — visual density **Apple Silicon only** (user override: no Electron redesign in this program).
3. Embedded Grok = CLI subprocess (Codex pattern), auth via `grok login`, no silent API fallback.
4. Isolation: ephemeral project MCP config; token in env only.

## D-2026-07-13 — Git root

- Workspace git root is `AI Projects/`.
- Checkpoint script scopes adds to `VaniScript/AppleSilicon/**` (and Electron when step says so).
- If remote push is DISABLED, local commit+tag is still mandatory; human pushes when able.

## D-2026-07-14 — GROK_MCP acceptance

- G6 is doc-only (no product features). Smoke checklist lives in `GROK_MCP_ACCEPTANCE.md`.
- Three accepted paths: (1) external Grok MCP via SSE — AS `19790`, Electron `19789`; (2) AS embedded chat for **Codex and Grok**; (3) Electron embedded Grok via the chat route selector + headless `grok` CLI.
- Invariants unchanged: no silent MCP→API fallback; isolated `vaniscript_embedded` MCP; token in child env only; Codex/Grok parity.

## Open

- (none yet)
