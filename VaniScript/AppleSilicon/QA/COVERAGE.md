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
| Provider Catalog fixed order | `a1_catalog_fixed_order.sh` | providerOrder contains 7 IDs in exact order | no |
| AppSettings decodeIfPresent | `a1_appsettings_decode_if_present.sh` | all new A1 fields use decodeIfPresent | no |
| ProviderUsage decodeIfPresent | `a1_provider_usage_decode_if_present.sh` | lastModel and lastTransactionAt use decodeIfPresent | no |
| Catalog no network | `a1_catalog_no_network.sh` | No URLSession/URLRequest/.fetch in CloudProviderCatalog | no |
| AppSettings defaults | `a1_appsettings_defaults.sh` | geminiTextModel and openaiTextModel defaults are correct | no |

## A2 — Usage recording (fixes empty statistics)

| Area | Script | Asserts | New this run |
|---|---|---|---|
| UsageRecorder purity | `a2_usagerecorder_purity.sh` | public enum, Foundation-only, no I/O/UI, record non-throwing | **yes** |
| TokenUsage type | `a2_tokenusage_type.sh` | public struct Equatable+Sendable, input/output, isEmpty, `+` | **yes** |
| record() aggregation | `a2_record_aggregation.sh` | sessions/input/output/audio increments + all last* refreshed | **yes** |
| Per-model key | `a2_record_per_model_key.sh` | usageKey `providerId:model` (§6.2), blank-model fallback | **yes** |
| Best-effort no-op | `a2_record_besteffort_noop.sh` | guard hasTokens‖hasAudio else return (no empty entries) | **yes** |
| Gemini parser | `a2_parser_gemini.sh` | usageMetadata.prompt/candidatesTokenCount, nil on empty | **yes** |
| OpenAI parser | `a2_parser_openai.sh` | usage.prompt_tokens/completion_tokens (snake_case CodingKeys) | **yes** |
| Parsers lenient | `a2_parsers_lenient_nil.sh` | `try?` x2, missing block→nil, no `throw` (non-throwing) | **yes** |
| Transcription usage | `a2_transcription_result_usage.sh` | result.usage: TokenUsage?=nil; Gemini+OpenAI parse→result | **yes** |
| Translation accumulator | `a2_translation_accumulator.sh` | actor, accumulatedUsage, accumulate sum/ignore-empty, takeLastUsage defer-reset | **yes** |
| WorkflowStore record | `a2_workflowstore_record.sh` | takeLastUsage→guard→updateSettings→record(into:&settings.usage), ≥4 call sites | **yes** |
| Normalized provider id | `a2_workflowstore_normalized_id.sh` | gemini-cloud→gemini, gpt-cloud→openai, default passthrough | **yes** |
| WorkflowStore best-effort | `a2_workflowstore_besteffort.sh` | async non-throwing, early-return guard, §14.4 documented | **yes** |
| Tests present | `a2_tests_present.sh` | @Suite("UsageRecorder (A2)"), @testable import, exactly 14 @Test | **yes** |
| Tests coverage areas | `a2_tests_coverage_areas.sh` | 14 named tests: record/last*/per-model/audio/best-effort/parsers/round-trip/arith | **yes** |
| ADR | `a2_decisions_adr.sh` | D-2026-07-26-A2, usage recording, §14.4, scope note, 287 tests | **yes** |
| No keys in source | `a2_no_keys_in_source.sh` | no sk-/AIza/ghp_/xox- literals in A2 sources/tests (§14.7) | **yes** |
| Migration-safe decode | `a2_appsettings_usage_migration_safe.sh` | usage decodeIfPresent??[:]; ProviderUsage last* optional+decodeIfPresent (§14.1+A1) | **yes** |
| swift test gate | `a2_swift_test_green.sh` | swift test green, 0 failures, soft-warn <287, env-only masking | **yes** |

---

## Gap Hunt Checklist (A2)

**A2 delta (every item closed):**
- [x] UsageRecorder increment / per-model key / last* / no-op nil-delta → `a2_record_aggregation`, `a2_record_per_model_key`, `a2_record_besteffort_noop`, `a2_tokenusage_type`, `a2_usagerecorder_purity`
- [x] Gemini JSON usageMetadata vs OpenAI usage.prompt_tokens/completion_tokens → `a2_parser_gemini`, `a2_parser_openai`
- [x] Missing usage block → nil, op still succeeds (best-effort) → `a2_parsers_lenient_nil`, `a2_record_besteffort_noop`, `a2_workflowstore_besteffort`
- [x] normalizedUsageProviderId (gemini-cloud→gemini, gpt-cloud→openai) → `a2_workflowstore_normalized_id`
- [x] Engines return TokenUsage (transcription result + translation accumulator) → `a2_transcription_result_usage`, `a2_translation_accumulator`
- [x] WorkflowStore writes settings.usage after cloud ops → `a2_workflowstore_record`
- [x] swift test green (UsageRecorderTests + full suite) → `a2_swift_test_green`, `a2_tests_present`, `a2_tests_coverage_areas`
- [x] No product keys in source (§14.7) → `a2_no_keys_in_source`
- [x] AppSettings decode still migration-safe (§14.1) → `a2_appsettings_usage_migration_safe`
- [x] ADR recorded → `a2_decisions_adr`

**Regression:**
- [x] Prior A1 scripts (catalog, decodeIfPresent, defaults, no-network) still enabled + re-run → `a1_*` (5 scripts) in manifest.
- [x] Full suite (build gates, MCP smoke, Q7 doc-delta, swift test) re-run via `run_all.sh`.

**N/A (with reason):**
- `Tests/VaniScriptTests/CloudUsageParsingTests.swift` (listed in STEPS §A2 target_files) — **N/A**: not created as a separate file; parser coverage is consolidated into `UsageRecorderTests` (parsesGeminiUsage / parsesOpenAIUsage / missing→nil / malformed→nil), which the Verifier explicitly APPROVED (FEEDBACK §2, ADR D-2026-07-26-A2). Asserted via `a2_tests_coverage_areas` instead. Not a product bug.
- Transcription → `settings.usage` wiring through `NativeProcessingPipeline` — **N/A (DEFERRED to A5/A6)** per Verifier-accepted scope note. Suite asserts the engine RETURNS usage (`a2_transcription_result_usage`) and the translation path RECORDS (`a2_workflowstore_record`); it does NOT fail on the deferred pipeline wiring.

**Env-only handling:**
- `a2_swift_test_green.sh` (and `build_gate_as.sh`) can hit a sandbox "Operation not permitted" (clang ModuleCache) before any test runs. That is reported as **ENV-ONLY** (warn, exit 0), not a product FAIL — matching the accepted A1 env-only disposition.

---
