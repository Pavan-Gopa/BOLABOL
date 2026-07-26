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

## A1 — Discovery + data model

| Area | Script | Asserts | New this run |
|---|---|---|---|
| Provider Catalog fixed order | `a1_catalog_fixed_order.sh` | providerOrder contains 7 IDs in exact order | **yes** |
| AppSettings decodeIfPresent | `a1_appsettings_decode_if_present.sh` | all new A1 fields use decodeIfPresent | **yes** |
| ProviderUsage decodeIfPresent | `a1_provider_usage_decode_if_present.sh` | lastModel and lastTransactionAt use decodeIfPresent | **yes** |
| Catalog no network | `a1_catalog_no_network.sh` | No URLSession/URLRequest/.fetch in CloudProviderCatalog | **yes** |
| AppSettings defaults | `a1_appsettings_defaults.sh` | geminiTextModel and openaiTextModel defaults are correct | **yes** |

---

## Gap Hunt Checklist (A1)

**A1 delta:**
- [x] Happy path (models exist, decode properly, order is correct) → `a1_catalog_fixed_order.sh`, `a1_appsettings_defaults.sh`
- [x] Error / invalid input / backward compat (decodeIfPresent) → `a1_appsettings_decode_if_present.sh`, `a1_provider_usage_decode_if_present.sh`
- [x] Isolation (no network in catalog) → `a1_catalog_no_network.sh`
- [x] swift test green → `build_gate_as.sh`

**Full regression (prior scripts):**
- [x] Re-run all prior scripts — keeping all Q7 scripts enabled in manifest.json to prevent regressions.
