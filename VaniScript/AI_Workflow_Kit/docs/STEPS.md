# VaniScript Electron Migration Steps

**Source of Truth:** `docs_VANISCRIPT_APPLE_SILICON_TO_ELECTRON_MIGRATION_PLAN.md` (§19 execution plan, §20 work packages) in the `VaniScript-Electron` repository.

## P0 — Baseline and characterization

**Goal:** Reproducible build/test baseline of the shipped Electron product before any structural migration work.

**Depends on:** none

**Do:**
- [x] [P0.D1] Baseline build/test inventory: build matrix and characterization suite

### Objective gates
- [x] [P0.O1] Clean CI on 3 OS

### Judgment gates
- [x] [P0.J1] Characterization suite captures real product behavior, not aspirational coverage

## P1 — Foundation

**Goal:** Shared contracts, typed IPC bridge, modular main process, sandboxed windows, and navigation stores as the stable base for all feature lanes.

**Depends on:** P0

**Do:**
- [x] [P1.D1] Shared schemas/errors/events in `shared/contracts`
- [x] [P1.D2] Typed preload/IPC facade: narrow versioned bridge
- [x] [P1.D3] Main module split: bootstrap/services/ipc/workers
- [x] [P1.D4] Sandboxed BrowserWindow with CSP policy handlers
- [x] [P1.D5] Route/projection stores: bounded feature mounting

### Objective gates
- [x] [P1.O1] Legacy media flows pass through the new bridge or legacy adapter
- [x] [P1.O2] Runtime validation, invalid payload/sender, security, and navigation perf tests pass

### Judgment gates
- [x] [P1.J1] Renderer cannot reach Node outside the typed bridge (no layer bypass)
- [x] [P1.J2] Sandbox/CSP cannot be silently weakened by feature code

## P2 — State/data/platform foundation

**Goal:** Durable settings/vault/storage, project v3 model with atomic store and bundles, capability registry, and provider/model catalogs — localStorage no longer a source of truth.

**Depends on:** P1

**Do:**
- [x] [P2.D1] Settings disk store: atomic JSON/migrations
- [x] [P2.D2] Credential vault: secret refs/adapters
- [x] [P2.D3] Legacy localStorage migration: one-shot handshake
- [x] [P2.D4] Settings UI parity: 9 sections + usage
- [x] [P2.D5] Project v3 model/migrator: media/document union
- [x] [P2.D6] Atomic project store: revisions/recovery
- [x] [P2.D7] Bundle import/export: manifest/checksums
- [x] [P2.D8] Platform capability registry: reason/remediation/backend
- [x] [P2.D9] Cloud provider catalog/router: Gemini/OpenAI/Anthropic/Qwen/OpenRouter/Ollama/custom
- [x] [P2.D10] Local model manager: scan/download/verify/relocate

### Objective gates
- [x] [P2.O1] Restart, corrupt-store, migration, and archive tests pass
- [x] [P2.O2] Settings no longer depends on localStorage as source of truth

### Judgment gates
- [x] [P2.J1] No plaintext secrets at rest; vault refs only
- [x] [P2.J2] Project migrations recoverable; atomicity holds under crash/conflict

## P3A — Document lane

**Goal:** Port document projects and editorial workflow: import/preflight, persistence, chunk/translation coordination, ProseMirror editor, multi-language review, exports.

**Depends on:** P2

**Do:**
- [ ] [P3A.D1] Document import/preflight: DOCX/PDF/RTF/TXT/MD normalized state
- [ ] [P3A.D2] Document project persistence: archive/languages/freshness
- [ ] [P3A.D3] Semantic chunk planner: stable block chunk plans
- [ ] [P3A.D4] Translation coordinator: pause/repair/commit
- [ ] [P3A.D5] Editorial editor core: ProseMirror schema/transactions/undo
- [ ] [P3A.D6] Multi-language/review: language tabs/status/approval
- [ ] [P3A.D7] Selection/find/replace/proofread: atomic edits/revision guards
- [ ] [P3A.D8] Document exports: DOCX/TXT/MD/PDF

### Objective gates
- [ ] [P3A.O1] Golden import/export fixtures pass for DOCX/PDF/RTF/TXT/MD
- [ ] [P3A.O2] Persistence/restart and language isolation tests pass
- [ ] [P3A.O3] Editor mutation, undo, and stale-response tests pass

### Judgment gates
- [ ] [P3A.J1] Source documents remain immutable; normalized state is derived
- [ ] [P3A.J2] Persistence contract matches accepted v3 archive architecture
- [ ] [P3A.J3] Malformed/hostile inputs fail safe without hangs or data loss

## P3B — Batch lane

**Goal:** SQLite-backed batch domain with folder watchers, scheduler/recovery, safe companion output, and a separate Batch workspace.

**Depends on:** P2

**Do:**
- [ ] [P3B.D1] Batch domain/SQLite: profiles/jobs/checkpoints/events
- [ ] [P3B.D2] Folder access/watchers: adapters/reconciliation
- [ ] [P3B.D3] Stability/path safety: fingerprint/confinement
- [ ] [P3B.D4] Scheduler/recovery: claim/run/checkpoint/retry
- [ ] [P3B.D5] Atomic companion writer: safe `.txt` output/receipts
- [ ] [P3B.D6] Separate Batch workspace: button/queue/details/controls

### Objective gates
- [ ] [P3B.O1] Migration/transaction and crash/restart recovery tests pass
- [ ] [P3B.O2] 10k-row virtualization E2E passes

### Judgment gates
- [ ] [P3B.J1] Symlink/case fuzz cannot escape path confinement
- [ ] [P3B.J2] Companion `.txt` writes are collision-safe and receipted

## P3C — MCP/Agents lane

**Goal:** Loopback MCP runtime with auth/audit, read-then-mutation tool catalog, Codex/Grok/Qwen agent clients, and assistant UI integration.

**Depends on:** P2

**Do:**
- [ ] [P3C.D1] Server/auth/audit: loopback MCP runtime
- [ ] [P3C.D2] Read tool catalog: project/transcript/document/help reads
- [ ] [P3C.D3] Mutation/processing tools: permissions/confirmation/revision
- [ ] [P3C.D4] Agent clients: Codex/Grok/Qwen stream/cancel
- [ ] [P3C.D5] Assistant UI/integrations: sidebar/dictation/send selection

### Objective gates
- [ ] [P3C.O1] Network/auth and tool schema tests pass
- [ ] [P3C.O2] Stale/deny tests confirm mutations require confirmation and revision guards

### Judgment gates
- [ ] [P3C.J1] Every mutation is permission-gated and audit-logged
- [ ] [P3C.J2] Agent streams cancel cleanly without orphaned processes

## P3D — Update lane

**Goal:** Update state/readiness service, platform updater adapters, and updates Settings/UI behind a signed release pipeline.

**Depends on:** P1

**Do:**
- [ ] [P3D.D1] Update state/readiness: blockers/receipts/quit prep
- [ ] [P3D.D2] Platform updater adapters: mac/win/linux behavior
- [ ] [P3D.D3] Updates Settings/UI: check/download/install UX

### Objective gates
- [ ] [P3D.O1] State/failure and fake feed/tamper tests pass
- [ ] [P3D.O2] Check/download/install component/E2E passes

### Judgment gates
- [ ] [P3D.J1] Updates never destroy unsaved user work (quit prep honored)
- [ ] [P3D.J2] Tampered or unsigned feeds are rejected

## P3E — Media extraction/parity lane

**Goal:** Extract media coordinators from `App.tsx` with provider/model routing, review/multi-language parity, export naming/bundles, and shorts persistence/render contract.

**Depends on:** P2

**Do:**
- [ ] [P3E.D1] Media coordinator extraction: processing state machine
- [ ] [P3E.D2] Review/multi-language parity: variants/stale/reprocess
- [ ] [P3E.D3] Export/project parity: formats/bundles/naming
- [ ] [P3E.D4] Shorts plan/state parity: persisted plans/languages
- [ ] [P3E.D5] Visual render contract: immutable render plan/cancel

### Objective gates
- [ ] [P3E.O1] Existing media E2E and review tests pass after extraction
- [ ] [P3E.O2] Golden exports and shorts plan fixture tests pass

### Judgment gates
- [ ] [P3E.J1] Extraction preserves observable media behavior (parity)
- [ ] [P3E.J2] Render plans immutable once started; cancel is safe

## P4 — Integration/hardening

**Goal:** Cross-feature hardening: help/onboarding, redacted observability, large-project performance, cross-edition fixtures, cross-platform E2E/packaging.

**Depends on:** P3A, P3B, P3C, P3D, P3E

**Do:**
- [ ] [P4.D1] Help/onboarding catalog: EN/RU search/context/tours
- [ ] [P4.D2] Usage/logging/diagnostics: redacted observability
- [ ] [P4.D3] Large-project optimization: budgets/virtualization
- [ ] [P4.D4] Cross-edition fixture suite: shared parity gate
- [ ] [P4.D5] Cross-platform E2E/packaging: release qualification

### Objective gates
- [ ] [P4.O1] Secret/text leak tests pass; performance regression report within budgets
- [ ] [P4.O2] Both editions pass shared fixtures; 3-OS release qualification report produced

### Judgment gates
- [ ] [P4.J1] Observability redacts secrets by default, not by opt-in
- [ ] [P4.J2] Performance budgets are enforced, not only measured

## P5 — Release

**Goal:** Signed/notarized build matrix and staged feed/release pipeline through alpha, beta, and stable rollout.

**Depends on:** P4

**Do:**
- [ ] [P5.D1] Signed build matrix: notarized/signed artifacts
- [ ] [P5.D2] Feed/release pipeline: staged metadata publication

### Objective gates
- [ ] [P5.O1] Clean VM install on each OS
- [ ] [P5.O2] Upgrade rehearsal from Electron 1.0.0 succeeds

### Judgment gates
- [ ] [P5.J1] User data preserved across upgrade/migration
- [ ] [P5.J2] Rollback path exists for staged rollout
