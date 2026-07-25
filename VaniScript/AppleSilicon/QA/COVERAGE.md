# QA COVERAGE — VaniScript

Area → script → asserts. Column **new this run** marks scripts added in the Q7 cycle.

## Build gates & MCP smoke

| Area | Script | Asserts | New this run |
|---|---|---|---|
| AppleSilicon build/test | `build_gate_as.sh` | `swift test` green (fallback `swift build`) | no |
| Electron compile | `build_gate_electron.sh` | `npm run compile` (tsc --noEmit); SKIP if no node_modules | **yes** (implemented; was a phantom manifest entry) |
| MCP server SSE :19790 | `mcp_smoke_as.sh` | mcp_bridge.py `PORT=19790` + SSE; `McpContracts.defaultEndpoint=…19790/sse` | **yes** (implemented as deterministic static smoke; was a phantom manifest entry) |

## Q7 — Doc-only delta (QWEN_MCP_ACCEPTANCE.md)

| Area | Script | Asserts | New this run |
|---|---|---|---|
| Acceptance checklist | `q7_acceptance_all_checked.sh` | all `[x]`, no `[ ]`, verdict `ИТОГ: [PASS]` | **yes** |
| Acceptance surfaces | `q7_acceptance_3_surfaces.sh` | "External Qwen MCP", "Apple Silicon embedded", "Electron embedded" | **yes** |
| Acceptance real values | `q7_acceptance_real_paths.sh` | 19790, 19789, `qwen3.8-max-preview`, `/Users/pavan/.local/bin/qwen` | **yes** |
| Acceptance invariants | `q7_acceptance_invariants.sh` | "no silent fallback", "token", "vaniscript_embedded", "Codex/Grok" | **yes** |

## Q7 — Doc-only delta (README.md)

| Area | Script | Asserts | New this run |
|---|---|---|---|
| README provider | `q7_readme_qwen_provider.sh` | `- **Qwen**` provider bullet present | **yes** |
| README no-rewrite | `q7_readme_no_rewrite.sh` | original `## Direction`, `## Local Run` preserved | **yes** |

## Q7 — Doc-only delta (MCP_INSTRUCTIONS.md)

| Area | Script | Asserts | New this run |
|---|---|---|---|
| MCP Qwen section | `q7_mcp_instructions_qwen.sh` | "External Qwen CLI", 19790, 19789 | **yes** |
| MCP no-electron (BUG-002) | `q7_mcp_instructions_no_electron.sh` | `grep -ci electron == 0` | **yes** |

## Q7 — Doc-only delta (DECISIONS.md)

| Area | Script | Asserts | New this run |
|---|---|---|---|
| ADR done | `q7_decisions_adr_done.sh` | "QWEN_MCP track complete", "QWEN_DONE" | **yes** |
| ADR format | `q7_decisions_adr_format.sh` | `D-2026-07-26-Q7` (or `D-<date>-Q7`) | **yes** |

## Q7 — Gates

| Area | Script | Asserts | New this run |
|---|---|---|---|
| Doc-only gate | `q7_doc_only_no_code.sh` | pending diff under AppleSilicon/ has no `.swift/.js/.ts/.py` code | **yes** |
| swift test regression | `q7_swift_test_green.sh` | 0 failures, non-empty run; soft-warn if count < 267 | **yes** |

---

## Gap Hunt Checklist (Q7)

**Q7 delta:**
- [x] ACCEPTANCE.md: all boxes `[x]`, verdict PASS → `q7_acceptance_all_checked.sh`
- [x] ACCEPTANCE.md: 3 surfaces described → `q7_acceptance_3_surfaces.sh`
- [x] ACCEPTANCE.md: real values (19790, 19789, qwen binary, model) → `q7_acceptance_real_paths.sh`
- [x] ACCEPTANCE.md: invariants mentioned → `q7_acceptance_invariants.sh`
- [x] README.md: Qwen as provider → `q7_readme_qwen_provider.sh`
- [x] README.md: original content not deleted → `q7_readme_no_rewrite.sh`
- [x] MCP_INSTRUCTIONS.md: Qwen section current → `q7_mcp_instructions_qwen.sh`
- [x] MCP_INSTRUCTIONS.md: no "Electron" (BUG-002) → `q7_mcp_instructions_no_electron.sh`
- [x] DECISIONS.md: ADR QWEN_MCP done → `q7_decisions_adr_done.sh` + `q7_decisions_adr_format.sh`
- [x] Doc-only: no code changes in diff → `q7_doc_only_no_code.sh`
- [x] swift test green → `q7_swift_test_green.sh` (+ `build_gate_as.sh`)

**Full regression (prior scripts):**
- [x] Re-run all prior scripts — N/A-as-stated / reason: the brief and STATE.yaml claim
  "62 scripts (47 old + 15 Q6)", but **only `build_gate_as.sh` existed on disk** and the
  manifest referenced two more (`build_gate_electron.sh`, `mcp_smoke_as.sh`) that were
  **missing** (running the old manifest would have produced 2 false MISSING→FAIL). We cannot
  re-run scripts that do not exist. Action taken: implemented the 2 phantom infra scripts so
  the declared suite is real, kept `build_gate_as.sh`, and added the 12 Q7 delta scripts.
  Current real suite = **15 scripts**. Discrepancy recorded in QA/REPORT.md as a state-integrity
  observation (not a product-code bug).

## Notes / adaptations
- `qwen/pre-Q7` git ref does not exist; Q7 edits are **uncommitted** working-tree changes.
  `q7_doc_only_no_code.sh` therefore inspects `git diff HEAD` scoped to `AppleSilicon/`.
- `mcp_smoke_as.sh` is a deterministic **static** smoke (no live SSE probe) to keep the suite
  idempotent and non-flaky per QA rules.
