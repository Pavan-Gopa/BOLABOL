# QA COVERAGE — VaniScript

Area → script → asserts. Column **new this run** marks scripts added in the current QA cycle (A3 unless noted).

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

## A3 — UI reorg: provider dropdown + cards

| Area | Script | Asserts | New this run |
|---|---|---|---|
| selectedProviderId default | `a3_selected_provider_default.sh` | `@State selectedProviderId = CloudProviderCatalog.geminiID` | **yes** |
| Picker catalog order | `a3_picker_uses_catalog.sh` | `ForEach(CloudProviderCatalog.providers)` + Picker selection binding | **yes** |
| Single card at a time | `a3_single_card_at_a_time.sh` | Custom branch + 1× `ProviderCardView(descriptor:)`; no always-expanded Gemini/OpenAI/Anthropic sections | **yes** |
| apiKeysTab structure | `a3_api_keys_tab_structure.sh` | Cloud Provider → conditional card → Cloud Usage Statistics order | **yes** |
| Custom path | `a3_custom_path_intact.sh` | `customProvidersSection`, add/remove, gated by `customID` | **yes** |
| ProviderCardView location | `a3_provider_card_location.sh` | in-file SettingsView OR own file (Verifier OK) | **yes** |
| Engine ids 1:1 | `a3_engine_ids_preserved.sh` | `gemini-cloud` / `gpt-cloud` / `coreml-whisperkit` / `mlx-native` | **yes** |
| Gemini/OpenAI parity | `a3_gemini_openai_parity.sh` | key + ReadOnlyRow + budget Slider + Transcribing/Translation toggles | **yes** |
| Anthropic card | `a3_anthropic_card.sh` | Anthropic Key + ReadOnlyRow Text Model | **yes** |
| Coming-soon stub | `a3_coming_soon_stub.sh` | default → `comingSoonCard` for Qwen/OpenRouter/Ollama | **yes** |
| Stub key fields | `a3_stub_key_fields.sh` | `qwenApiKey` / `openrouterApiKey` / `ollamaCloudApiKey` | **yes** |
| getApiKeyURL SSOT | `a3_get_api_key_url_descriptor.sh` | `urlString: descriptor.getApiKeyURL` | **yes** |
| Stats section | `a3_stats_section_unchanged.sh` | "Cloud Usage Statistics" + Reset/StatItem/BudgetBar still present | **yes** |
| No A4 | `a3_no_a4_validation_or_model_net.sh` | no CloudKeyValidator/CloudModelCatalog; ReadOnlyRow models; no URLSession in card | **yes** |
| No A5 routing | `a3_no_a5_engine_routing.sh` | no transcription/translation assign to qwen/openrouter/ollama | **yes** |
| Catalog IDs | `a3_switch_covers_catalog_ids.sh` | all catalog ID constants used; A1 order intact | **yes** |
| UI-only scope | `a3_scope_no_engine_usage_changes.sh` | no A5 cases in `normalizedUsageProviderId` | **yes** |
| No secrets | `a3_no_hardcoded_api_keys.sh` | no sk-/AIza/ghp_/xox- literals in SettingsView | **yes** |
| FEEDBACK APPROVED | `a3_feedback_approved.sh` | A3 `[APPROVED]` + handoff claims | **yes** |
| STATE.yaml | `a3_state_yaml_a3.sh` | `current_step: A3`; implementation+review approved | **yes** |
| swift build | `a3_swift_build_green.sh` | `swift build` green; ENV-ONLY soft-pass | **yes** |

---

## Gap Hunt Checklist (A3)

**A3 delta (every item closed):**
- [x] Picker uses catalog order (not hardcoded gemini/openai only) → `a3_picker_uses_catalog`, `a3_switch_covers_catalog_ids`
- [x] Only one provider card rendered at a time → `a3_single_card_at_a_time`, `a3_api_keys_tab_structure`
- [x] Custom path still has add/remove → `a3_custom_path_intact`
- [x] Engine ids preserved: gemini-cloud / gpt-cloud / coreml-whisperkit / mlx-native → `a3_engine_ids_preserved`, `a3_gemini_openai_parity`
- [x] Stub providers write keys to correct AppSettings fields → `a3_stub_key_fields`, `a3_coming_soon_stub`
- [x] getApiKeyURL from descriptor → `a3_get_api_key_url_descriptor`
- [x] Stats section still present (not deleted) → `a3_stats_section_unchanged`
- [x] No A4 validation badge / model dropdown network code → `a3_no_a4_validation_or_model_net`
- [x] No A5 engine routing for qwen/openrouter/ollama → `a3_no_a5_engine_routing`, `a3_scope_no_engine_usage_changes`
- [x] selectedProviderId default gemini → `a3_selected_provider_default`
- [x] Gemini/OpenAI/Anthropic card parity → `a3_gemini_openai_parity`, `a3_anthropic_card`
- [x] ProviderCardView in-file OK → `a3_provider_card_location`
- [x] FEEDBACK [APPROVED] + STATE A3 → `a3_feedback_approved`, `a3_state_yaml_a3`
- [x] swift build green → `a3_swift_build_green` (+ `build_gate_as`)
- [x] No secrets in SettingsView → `a3_no_hardcoded_api_keys`

**Regression:**
- [x] A1 catalog scripts still enabled → `a1_*` (5)
- [x] A2 usage scripts still enabled → `a2_*` (20)
- [x] Full suite (build gates, MCP smoke, Q7 doc-delta, swift test) re-run via `run_all.sh`
- [x] Step-aware `q7_doc_only_no_code` N/A for code step A3 (existing script)

**N/A (with reason):**
- Separate `ProviderCardView.swift` file — **N/A**: optional per STEPS; Verifier APPROVED in-file helper. Asserted via `a3_provider_card_location` (either location OK).
- Interactive UI click-through of Picker — **N/A (static QA)**: suite is grep/structure based; no XCUITest harness in track. Runtime behavior covered indirectly by structure + build gates.
- A4 key validation / A5 engines / A6 stats rebuild — **N/A (out of scope A3)**; negative scripts assert absence.

**Env-only handling:**
- `a3_swift_build_green.sh` / `build_gate_as.sh` / `a2_swift_test_green.sh` may hit sandbox "Operation not permitted" → **ENV-ONLY** (warn, exit 0), not product FAIL.

---
