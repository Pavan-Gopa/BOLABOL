# VaniScript Electron Migration Steps

**Source of Truth:** `docs/apple-silicon-feature-parity-plan/docs/VANISCRIPT_APPLE_SILICON_TO_ELECTRON_MIGRATION_PLAN.md` in the Electron repository.

## P0 — Baseline and characterization
- [x] [FND-00] Baseline build/test inventory: Setup build matrix and characterization suite. Gate: Clean CI on 3 OS.

## P1 — Foundation
- [x] [FND-01] Shared schemas/errors: `shared/contracts`. Gate: Runtime validation tests.
- [x] [FND-02] Typed preload/IPC: Narrow versioned bridge. Gate: Invalid payload/sender tests.
- [x] [FND-03] Main module split: bootstrap/services/ipc/workers. Gate: Legacy smoke parity.
- [x] [SEC-01] Browser sandbox/CSP: `sandbox: true`, policy handlers. Gate: Electron security tests.
- [x] [NAV-01] Route/projection stores: bounded feature mounting. Gate: Navigation perf test.

## P2 — State/data/platform foundation
- [x] [SET-01] Settings disk store: atomic JSON/migrations. Gate: corrupt/restart tests.
- [x] [SET-02] Credential vault: secret refs/adapters. Gate: no plaintext assertion.
- [x] [SET-03] Legacy localStorage migration: one-shot handshake. Gate: rollback/retry test.
- [x] [SET-04] Settings UI parity: 9 sections + usage. Gate: persistence/E2E.
- [x] [PROJ-01] Project v3 model/migrator: media/document union. Gate: fixture parity.
- [x] [PROJ-02] Atomic project store: revisions/recovery. Gate: crash/conflict tests.
- [x] [PROJ-03] Bundle import/export: manifest/checksums. Gate: malicious archive suite.
- [x] [CAP-01] Platform capability registry: reason/remediation/backend. Gate: matrix tests.
- [x] [PRV-01] Cloud provider catalog/router: Gemini/OpenAI/Anthropic/Qwen/OpenRouter/Ollama/custom. Gate: table-driven routing tests.
- [x] [MOD-01] Local model manager: scan/download/verify/relocate. Gate: partial/corrupt/disk tests.

## P3A — Document lane
- [ ] [DOC-01] Document import/preflight: DOCX/PDF/RTF/TXT/MD normalized state. Gate: golden imports.
- [ ] [DOC-02] Document project persistence: archive/languages/freshness. Gate: reopen/bundle tests.
- [ ] [DOC-03] Semantic chunk planner: stable block chunk plans. Gate: deterministic fixtures.
- [ ] [DOC-04] Translation coordinator: pause/repair/commit. Gate: failure/revision tests.
- [ ] [DOC-05] Editorial editor core: ProseMirror schema/transactions/undo. Gate: mutation tests.
- [ ] [DOC-06] Multi-language/review: language tabs/status/approval. Gate: language isolation tests.
- [ ] [DOC-07] Selection/find/replace/proofread: atomic edits/revision guards. Gate: stale-response tests.
- [ ] [DOC-08] Document exports: DOCX/TXT/MD/PDF. Gate: round-trip golden suite.

## P3B — Batch lane
- [ ] [BAT-01] Batch domain/SQLite: profiles/jobs/checkpoints/events. Gate: migration/transaction tests.
- [ ] [BAT-02] Folder access/watchers: adapters/reconciliation. Gate: event duplication tests.
- [ ] [BAT-03] Stability/path safety: fingerprint/confinement. Gate: symlink/case fuzz suite.
- [ ] [BAT-04] Scheduler/recovery: claim/run/checkpoint/retry. Gate: crash/restart tests.
- [ ] [BAT-05] Atomic companion writer: safe `.txt` output/receipts. Gate: collision tests.
- [ ] [BAT-06] Separate Batch workspace: button/queue/details/controls. Gate: 10k virtualization E2E.

## P3C — MCP/Agents lane
- [ ] [MCP-01] Server/auth/audit: loopback MCP runtime. Gate: network/auth tests.
- [ ] [MCP-02] Read tool catalog: project/transcript/document/help reads. Gate: schema tests.
- [ ] [MCP-03] Mutation/processing tools: permissions/confirmation/revision. Gate: stale/deny tests.
- [ ] [MCP-04] Agent clients: Codex/Grok/Qwen stream/cancel. Gate: mock protocol tests.
- [ ] [MCP-05] Assistant UI/integrations: sidebar/dictation/send selection. Gate: E2E/tool confirmation.

## P3D — Update lane
- [ ] [UPD-01] Update state/readiness: blockers/receipts/quit prep. Gate: state/failure tests.
- [ ] [UPD-02] Platform updater adapters: mac/win/linux behavior. Gate: fake feed/tamper tests.
- [ ] [UPD-03] Updates Settings/UI: check/download/install UX. Gate: component/E2E.

## P3E — Media extraction/parity lane
- [ ] [MED-01] Media coordinator extraction: processing state machine. Gate: existing media E2E.
- [ ] [MED-02] Review/multi-language parity: variants/stale/reprocess. Gate: review tests.
- [ ] [MED-03] Export/project parity: formats/bundles/naming. Gate: golden exports.
- [ ] [SHT-01] Shorts plan/state parity: persisted plans/languages. Gate: plan fixture tests.
- [ ] [SHT-02] Visual render contract: immutable render plan/cancel. Gate: frame/render smoke.

## P4 — Integration/hardening
- [ ] [HLP-01] Help/onboarding catalog: EN/RU search/context/tours. Gate: data/search tests.
- [ ] [OBS-01] Usage/logging/diagnostics: redacted observability. Gate: secret/text leak tests.
- [ ] [PERF-01] Large-project optimization: budgets/virtualization. Gate: regression report.
- [ ] [QA-01] Cross-edition fixture suite: shared parity gate. Gate: both repos pass.
- [ ] [QA-02] Cross-platform E2E/packaging: release qualification. Gate: 3-OS report.

## P5 — Release
- [ ] [REL-01] Signed build matrix: notarized/signed artifacts. Gate: clean VM install.
- [ ] [REL-02] Feed/release pipeline: staged metadata publication. Gate: upgrade rehearsal.
