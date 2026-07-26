# QA COVERAGE — VaniScript

Area → script → asserts. Column **new this run** marks scripts added in the current QA cycle (A7 unless noted).

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

## A4 — Key validation + auto model catalog

| Area | Script | Asserts | New this run |
|---|---|---|---|
| Status map | `a4_key_validator_status_map.sh` | idle/checking/valid/invalid; 2xx→valid, 401/403→invalid, 429→valid, other→invalid | **yes** |
| Empty / custom | `a4_key_validator_empty_custom.sh` | empty key → idle; custom listing-unsupported → valid without network | **yes** |
| listRequest reuse | `a4_key_validator_uses_list_request.sh` | validate via `CloudModelCatalog.listRequest` + fetcher + status map | **yes** |
| Parsers | `a4_catalog_parsers.sh` | OpenAI `data[].id`, Gemini strip `models/`, Ollama `models[].name`, Anthropic shared | **yes** |
| Dedup | `a4_catalog_dedup.sh` | Set/seen de-dupe + empty drop; unit test | **yes** |
| listRequest auth | `a4_catalog_list_request_auth.sh` | Gemini `?key=`, Bearer, Anthropic `x-api-key`, Ollama `/api/tags` | **yes** |
| Cache fingerprint | `a4_catalog_session_cache_fingerprint.sh` | session cache + `keyFingerprint` (hashValue) + invalidate; no raw key | **yes** |
| Injectable fetcher | `a4_catalog_fetcher_injectable.sh` | `CloudHTTPFetcher` on catalog + validator; tests mock | **yes** |
| CloudKeyModelRow UI | `a4_settings_cloud_key_model_row.sh` | badge Checking/Valid/Invalid + Picker/editable+Retry | **yes** |
| Settings writes | `a4_settings_writes_text_models.sh` | `geminiTextModel` / `openaiTextModel` bindings + fallbacks | **yes** |
| Debounce | `a4_settings_debounce.sh` | `.task(id: apiKey)` + 500ms; core timer-free | **yes** |
| Transcription resolve | `a4_transcription_resolve_gemini_settings.sh` | Gemini from settings; whisper-1 deferred OK | **yes** |
| Translation resolve | `a4_translation_resolve_settings_fallback.sh` | gemini/openai settings + hardcode fallbacks | **yes** |
| Tests present | `a4_tests_present.sh` | CloudKeyValidatorTests (9) + CloudModelCatalogTests (12) | **yes** |
| No secrets | `a4_no_keys_in_source.sh` | no sk-/AIza/ghp_/xox- in A4 sources/tests | **yes** |
| No A5 routing | `a4_no_a5_engine_routing.sh` | no qwen/openrouter/ollama engine cases | **yes** |
| No A6 stats rewrite | `a4_no_a6_stats_rewrite.sh` | Cloud Usage Statistics section still present | **yes** |
| Verifier scope OK | `a4_anthropic_readonly_whisper_ok.sh` | Anthropic ReadOnly + whisper-1 — not bugs | **yes** |
| FEEDBACK | `a4_feedback_approved.sh` | A4 `[APPROVED]` + handoff claims | **yes** |
| STATE.yaml | `a4_state_yaml_a4.sh` | `current_step: A4`; implementation+review approved | **yes** |
| swift test gate | `a4_swift_test_green.sh` | green; soft-warn <308; ENV-ONLY soft-pass | **yes** |

### A3 regression adaptations (this run)

| Script | Change |
|---|---|
| `a3_no_a4_validation_or_model_net.sh` | step-aware N/A when `current_step` ≥ A4 |
| `a3_gemini_openai_parity.sh` | A4+ accepts `CloudKeyModelRow` + text-model bindings |
| `a3_state_yaml_a3.sh` | step-aware N/A when not A3 |
| `a3_feedback_approved.sh` | historical A3 APPROVED search when step > A3 |

---

## Gap Hunt Checklist (A4)

**A4 delta (every item closed):**
- [x] HTTP status map: 2xx valid, 401/403 invalid, 429 valid, other invalid → `a4_key_validator_status_map`
- [x] empty key → idle; custom → valid without network → `a4_key_validator_empty_custom`
- [x] validate via listRequest → `a4_key_validator_uses_list_request`
- [x] parsers: models/ strip Gemini; data[].id OpenAI; Ollama models[].name; Anthropic shared → `a4_catalog_parsers`
- [x] dedup + empties → `a4_catalog_dedup`
- [x] listRequest auth shapes → `a4_catalog_list_request_auth`
- [x] cache invalidates on key change (fingerprint) → `a4_catalog_session_cache_fingerprint`
- [x] CloudHTTPFetcher injectable → `a4_catalog_fetcher_injectable`
- [x] CloudKeyModelRow badge + Picker/editable+Retry; debounce → `a4_settings_*`
- [x] writes geminiTextModel / openaiTextModel → `a4_settings_writes_text_models`
- [x] resolve Gemini from settings; whisper-1 OK deferred → `a4_transcription_resolve_gemini_settings`, `a4_anthropic_readonly_whisper_ok`
- [x] resolve translation settings + hardcode fallback → `a4_translation_resolve_settings_fallback`
- [x] tests present → `a4_tests_present`, `a4_swift_test_green`
- [x] no sk-/AIza keys in source → `a4_no_keys_in_source`
- [x] no A5 qwen/openrouter/ollama engine routing → `a4_no_a5_engine_routing`
- [x] no A6 stats section rewrite → `a4_no_a6_stats_rewrite`
- [x] FEEDBACK APPROVED + STATE A4 → `a4_feedback_approved`, `a4_state_yaml_a4`

**Regression:**
- [x] A1 scripts still enabled → `a1_*` (5)
- [x] A2 scripts still enabled → `a2_*` (20)
- [x] A3 scripts still enabled (step-aware where needed) → `a3_*` (21)
- [x] Full suite (build gates, MCP smoke, Q7, swift test) re-run via `run_all.sh`

**N/A (with reason):**
- Anthropic CloudKeyModelRow / settings field — **N/A (Verifier OK)**: Anthropic stays ReadOnly; no engine routing for Anthropic text model in A4. Asserted via `a4_anthropic_readonly_whisper_ok`.
- OpenAI transcription using `openaiTextModel` — **N/A (Verifier OK)**: whisper-1 is audio model; deferred to A5 audio-picker. Asserted via `a4_transcription_resolve_gemini_settings` + `a4_anthropic_readonly_whisper_ok`.
- Interactive UI click-through of validation badge — **N/A (static QA)**: suite is source/structure + unit tests with mocked HTTP.

**Env-only handling:**
- `a4_swift_test_green.sh` / `a2_swift_test_green.sh` / `build_gate_as.sh` may hit sandbox "Operation not permitted" → **ENV-ONLY** (warn, exit 0), not product FAIL.

---

## A5 — Qwen / OpenRouter / Ollama Cloud full integration

| Area | Script | Asserts | New this run |
|---|---|---|---|
| Translation gating | `a5_registry_translation_gating.sh` | key-present → options; tests empty/whitespace/present | **yes** |
| No transcription options | `a5_registry_no_transcription.sh` | supportsTranscription=false for three; registry gate | **yes** |
| Router endpoints | `a5_cloud_chat_router_endpoints.sh` | DashScope/OpenRouter/Ollama /v1 + Bearer | **yes** |
| Model fallback | `a5_cloud_chat_router_model_fallback.sh` | settings override vs default; blank key → nil | **yes** |
| Translation engine | `a5_translation_engine_routing.sh` | CloudChatRouter resolve; generateOpenAICompatible; parseOpenAIUsage | **yes** |
| Transcription honest | `a5_transcription_no_new_cases.sh` | no qwen/openrouter/ollama resolve cases | **yes** |
| Settings card | `a5_settings_cloud_provider_card.sh` | cloudProviderCard for three (stub retired) | **yes** |
| Settings fields | `a5_settings_key_model_budget_baseurl.sh` | CloudKeyModelRow; budget Qwen/OR; Base URL Ollama | **yes** |
| Transcribing UX | `a5_settings_transcribing_disabled.sh` | disabled+tooltip; Translation when key | **yes** |
| Unit tests | `a5_tests_present.sh` | ProviderRegistryCloudTests + CloudProviderRoutingTests | **yes** |
| ADR | `a5_decisions_adr.sh` | D-2026-07-26-A5 endpoints/capabilities/ids | **yes** |
| FEEDBACK | `a5_feedback_approved.sh` | A5 `[APPROVED]` + handoff claims | **yes** |
| STATE.yaml | `a5_state_yaml_a5.sh` | `current_step: A5`; implementation+review approved | **yes** |
| Out of scope | `a5_no_a6_stats_no_a7_balance.sh` | stats section intact; no CloudBalanceService | **yes** |
| No secrets | `a5_no_keys_in_source.sh` | no sk-/AIza/ghp_/xox- in A5 sources/tests | **yes** |
| Verifier scope OK | `a5_verifier_scope_ok.sh` | pipeline usage deferred; Ollama list base catalog | **yes** |
| swift test gate | `a5_swift_test_green.sh` | green; soft-warn <320; ENV-ONLY soft-pass | **yes** |

### A3/A4 regression adaptations (this run)

| Script | Change |
|---|---|
| `a3_coming_soon_stub.sh` | A5+ accepts `cloudProviderCard` + explicit qwen/openrouter/ollama cases |
| `a3_no_a5_engine_routing.sh` | step-aware N/A when `current_step` ≥ A5 |
| `a4_no_a5_engine_routing.sh` | step-aware N/A when `current_step` ≥ A5 |
| `a4_state_yaml_a4.sh` | step-aware N/A when not A4 |
| `a4_feedback_approved.sh` | historical A4 APPROVED search when step > A4 |
| `a4_anthropic_readonly_whisper_ok.sh` | slice only `anthropicCard` body (ignore A5 MARK comment mentioning CloudKeyModelRow) |

---

## Gap Hunt Checklist (A5)

**A5 delta (every item closed):**
- [x] Registry translation gating empty/non-empty key → `a5_registry_translation_gating`
- [x] No transcription registry entries (supportsTranscription false) → `a5_registry_no_transcription`
- [x] Router URL/headers per provider (no real network) → `a5_cloud_chat_router_endpoints`
- [x] Model fallback vs settings override → `a5_cloud_chat_router_model_fallback`
- [x] Translation engine shared path + usage → `a5_translation_engine_routing`
- [x] Transcription engine no dead cases → `a5_transcription_no_new_cases`
- [x] Settings cloudProviderCard / CloudKeyModelRow / budget / base URL / toggles → `a5_settings_*`
- [x] Tests present → `a5_tests_present`, `a5_swift_test_green`
- [x] ADR + FEEDBACK + STATE → `a5_decisions_adr`, `a5_feedback_approved`, `a5_state_yaml_a5`
- [x] No A6 stats rewrite; no A7 balance → `a5_no_a6_stats_no_a7_balance`
- [x] No API keys in source → `a5_no_keys_in_source`
- [x] Verifier OK (pipeline defer, Ollama list base) → `a5_verifier_scope_ok`

**Regression:**
- [x] A1–A4 scripts still enabled (step-aware where needed) → full `run_all.sh`
- [x] A3 coming-soon / no-A5-routing adapted for A5 product state

**N/A (with reason):**
- Real network calls to Qwen/OpenRouter/Ollama — **N/A (static QA + unit mocks)**; router pure functions + mocked catalog/validator tests.
- Transcription audio for new providers — **N/A (honest capabilities false)**; asserted via `a5_transcription_no_new_cases` + registry gate.
- A6 stats UI rewrite / A7 balance service — **N/A (out of scope A5)**; negative scripts assert absence.
- NativeProcessingPipeline transcription usage wiring — **N/A (DEFERRED, Verifier OK)**; asserted via `a5_verifier_scope_ok`.

**Env-only handling:**
- `a5_swift_test_green.sh` / prior swift gates / `build_gate_as.sh` may hit sandbox "Operation not permitted" → **ENV-ONLY** (warn, exit 0), not product FAIL.

---

## A6 — Usage statistics UI (Electron tab 7)

| Area | Script | Asserts | New this run |
|---|---|---|---|
| View present | `a6_usage_statistics_view_present.sh` | UsageStatisticsView.swift + struct + A6 markers | **yes** |
| Settings wiring | `a6_settings_wired.sh` | UsageStatisticsView() in apiKeysTab; old section gone | **yes** |
| Last Transaction | `a6_last_transaction.sh` | max lastTransactionAt, lastModel, Prompt/Completion/Total | **yes** |
| Active summary | `a6_active_providers_summary.sh` | Transcribing/Translation + providerDisplayName + legacy ids | **yes** |
| Per-model cards | `a6_per_model_cards.sh` | N transactions, 6 metrics, estimateCost, remaining | **yes** |
| Disclaimer | `a6_disclaimer_exact.sh` | exact Electron disclaimer string | **yes** |
| Reset + empty | `a6_reset_and_empty_state.sh` | usage = [:]; «No usage recorded yet.» | **yes** |
| Old section gone | `a6_old_section_removed.sh` | no Cloud Usage Statistics SettingsSection; no StatItem/BudgetBar/estimateCost | **yes** |
| Title | `a6_cloud_api_usage_title.sh` | Cloud API Usage section title | **yes** |
| No A7 | `a6_no_a7_balance.sh` | no CloudBalanceService; no network in UsageStatisticsView | **yes** |
| UI-only scope | `a6_ui_only_scope.sh` | engines/registry/UsageRecorder not redefined in view | **yes** |
| Provider cards | `a6_provider_cards_intact.sh` | ProviderCardView + cloud cards intact | **yes** |
| No secrets | `a6_no_keys_in_source.sh` | no sk-/AIza in A6 sources | **yes** |
| FEEDBACK | `a6_feedback_approved.sh` | A6 `[APPROVED]` + handoff claims | **yes** |
| STATE.yaml | `a6_state_yaml_a6.sh` | `current_step: A6`; implementation+review approved | **yes** |
| swift test gate | `a6_swift_test_green.sh` | green; soft-warn <320; ENV-ONLY soft-pass | **yes** |

### A3/A4/A5 regression adaptations (this run)

| Script | Change |
|---|---|
| `a3_stats_section_unchanged.sh` | A6+ expects UsageStatisticsView; old section retired by design |
| `a3_api_keys_tab_structure.sh` | A6+ stats slot = UsageStatisticsView() after provider card |
| `a4_no_a6_stats_rewrite.sh` | step-aware N/A when `current_step` ≥ A6 |
| `a5_no_a6_stats_no_a7_balance.sh` | stats half N/A on A6+; still enforce no A7 balance |
| `a5_state_yaml_a5.sh` | step-aware N/A when not A5 |
| `a5_feedback_approved.sh` | historical A5 APPROVED when step > A5 |

---

## Gap Hunt Checklist (A6)

**A6 delta (every item closed):**
- [x] UsageStatisticsView present + wired in apiKeysTab → `a6_usage_statistics_view_present`, `a6_settings_wired`
- [x] Last Transaction (max lastTransactionAt, lastModel badge, Prompt/Completion/Total) → `a6_last_transaction`
- [x] Summary Transcribing / Translation + legacy id normalize → `a6_active_providers_summary`
- [x] Per-model cards: N transactions, 6 metrics, estimateCost, remaining vs budget → `a6_per_model_cards`
- [x] Exact disclaimer string → `a6_disclaimer_exact`
- [x] Reset → usage = [:]; empty state → `a6_reset_and_empty_state`
- [x] Old «Cloud Usage Statistics» + dead StatItem/BudgetBar/estimateCost removed → `a6_old_section_removed`, `a6_cloud_api_usage_title`
- [x] Provider cards intact → `a6_provider_cards_intact`
- [x] No A7 balance network → `a6_no_a7_balance`
- [x] UI only (no engines/registry/UsageRecorder rewrite) → `a6_ui_only_scope`
- [x] No keys in source → `a6_no_keys_in_source`
- [x] FEEDBACK APPROVED + STATE A6 → `a6_feedback_approved`, `a6_state_yaml_a6`
- [x] swift test green (320+) → `a6_swift_test_green` (+ `build_gate_as`)

**Regression:**
- [x] A1–A5 scripts still enabled (step-aware where needed) → full `run_all.sh`
- [x] Old stats-unchanged asserts inverted/N/A for A6+ → a3/a4/a5 adaptations above

**N/A (with reason):**
- Interactive UI click-through of Reset / empty state — **N/A (static QA)**: suite is source/structure based; no XCUITest harness.
- A7 real balance / network credits — **N/A (out of scope A6)**; negative script `a6_no_a7_balance`.
- Engine/UsageRecorder changes — **N/A (UI only)**; asserted via `a6_ui_only_scope`.
- lastModel badge as Electron superset — **N/A (Verifier OK)**: prefers lastModel with provider-name fallback; asserted via `a6_last_transaction`.

**Env-only handling:**
- `a6_swift_test_green.sh` / prior swift gates / `build_gate_as.sh` may hit sandbox "Operation not permitted" → **ENV-ONLY** (warn, exit 0), not product FAIL.

---

## A7 — Real balance adapter (OpenRouter first)

| Area | Script | Asserts | New this run |
|---|---|---|---|
| Service present | `a7_balance_service_present.sh` | CloudBalanceService.swift: `public actor` + `BalanceProvider` + OpenRouter/Ollama providers + A7 markers | **yes** |
| BalanceInfo | `a7_balance_info_cases.sh` | `.usd(remaining:total:)` / `.planLimits(label:detail:)` / `.unavailable`, Equatable+Sendable | **yes** |
| OpenRouter parsers | `a7_openrouter_parsers.sh` | GET `/api/v1/credits` + `/api/v1/key` (Bearer); pure `parseCredits`/`parseKey`; typed `unparsableResponse` | **yes** |
| OpenRouter mapping | `a7_openrouter_mapping.sh` | remaining = credits−usage; per-key cap `min(accountRemaining,keyRemaining)`; total = `keyLimit ?? credits` | **yes** |
| Ollama plan | `a7_ollama_plan_based.sh` | `.planLimits("Plan-based (GPU time)")`, never a `.usd` (no fake $) | **yes** |
| Honesty guard | `a7_honesty_guard_no_fetch.sh` | `.none`/`.estimated` → nil provider → `.unavailable` no-fetch; empty OpenRouter key no-fetch | **yes** |
| Quiet fallback | `a7_quiet_fallback.sh` | `CloudBalanceError` typed; balance() do/catch → `.unavailable`; non-2xx → `.requestFailed` | **yes** |
| TTL cache | `a7_ttl_cache_force.sh` | TTL=60s in-memory per provider id; `force` bypass; `invalidate()`; session-only (no persistence) | **yes** |
| Injected fetcher | `a7_http_fetcher_injected.sh` | network only via injected `CloudHTTPFetcher` (A4 reuse); no direct `URLSession` in service | **yes** |
| Catalog kinds | `a7_catalog_balance_kinds.sh` | openrouter=`.openrouterCredits`, ollama=`.ollamaPlan`, gemini/openai/anthropic/qwen/custom=`.estimated` | **yes** |
| Settings row | `a7_settings_balance_row.sh` | `CloudBalanceRow` module-visible; gated to real kinds; `.usd`/`.planLimits`/`Estimated only`; lazy `.task(id:)`+Refresh | **yes** |
| Stats section | `a7_usage_stats_real_balance.sh` | `realBalanceSection` reuses `CloudBalanceRow`; gated by kind + configured (non-empty) key | **yes** |
| No fake $ | `a7_no_fake_usd_estimated.sh` | no fake $ for `.estimated`; A6 disclaimer intact; balance gated to real kinds | **yes** |
| Tests present | `a7_tests_present.sh` | `@Suite("CloudBalanceService (A7)")`: parsers/cap/Ollama/guard/quiet/cache/force on mocked network | **yes** |
| No secrets | `a7_no_keys_in_source.sh` | no sk-/AIza/ghp_/xox- in A7 sources/tests (§14.7) | **yes** |
| ADR | `a7_adr_present.sh` | `D-2026-07-26-A7` with OpenRouter shapes + honesty rules + 331 tests | **yes** |
| FEEDBACK | `a7_feedback_approved.sh` | FEEDBACK A7 `[APPROVED]` + handoff claims | **yes** |
| STATE.yaml | `a7_state_yaml_a7.sh` | `current_step: A7`; implementation+review approved; target_files mention CloudBalanceService | **yes** |
| swift test gate | `a7_swift_test_green.sh` | green; soft-warn <331; ENV-ONLY soft-pass | **yes** |

### A6 regression adaptation (this run)

| Script | Change |
|---|---|
| `a6_no_a7_balance.sh` | step-aware: pre-A7 strict (no balance service); A7+ balance half N/A → assert `CloudBalanceRow` reuse + no direct `URLSession` in UsageStatisticsView |
| `a5_no_a6_stats_no_a7_balance.sh` | already step-aware (verified PASS at A7): stats half N/A on A6+; balance half OK on A7+ |

> **Terminal-state maintenance (re-validation at current_step = API_USAGE_DONE):**
> the track advanced past A8 to its terminal API_USAGE_DONE state, which the original
> A-digit step detectors (A7 / A8 / A9-plus literals) did not recognise. Four scripts
> were extended to also treat API_USAGE_DONE as ">= A6 / >= A7" (QA maintenance, not a
> product bug; product code untouched):
> - `a5_no_a6_stats_no_a7_balance.sh` (a6_or_later detector + two A7+ allowances)
> - `a6_no_a7_balance.sh` (a7_or_later detector)
> - `a6_state_yaml_a6.sh` (soft N/A past A6)
> - `a7_state_yaml_a7.sh` (soft N/A past A7)

---

## Gap Hunt Checklist (A7)

**A7 delta (every item closed):**
- [x] CloudBalanceService actor + BalanceProvider + BalanceInfo cases → `a7_balance_service_present`, `a7_balance_info_cases`
- [x] OpenRouter credits+key parsers (Bearer, typed errors) → `a7_openrouter_parsers`
- [x] OpenRouter mapping: credits−usage, per-key `min()` cap (never over-report), total = keyLimit ?? credits → `a7_openrouter_mapping`
- [x] Ollama plan-based label, never a fake $ → `a7_ollama_plan_based`
- [x] Honesty guard: `.none`/`.estimated` no-fetch; empty key no-fetch → `a7_honesty_guard_no_fetch`
- [x] Quiet fallback: errors → `.unavailable`, no crash → `a7_quiet_fallback`
- [x] TTL=60s cache + force bypass + invalidate + session-only → `a7_ttl_cache_force`
- [x] Network only via injected `CloudHTTPFetcher` (no direct URLSession) → `a7_http_fetcher_injected`
- [x] Catalog balanceKind mapping (real vs estimated) → `a7_catalog_balance_kinds`
- [x] SettingsView CloudBalanceRow gated + module-visible + lazy/Refresh → `a7_settings_balance_row`
- [x] UsageStatisticsView realBalanceSection reuses row, kind+key gated → `a7_usage_stats_real_balance`
- [x] No fake $ for estimated providers; A6 estimated path intact → `a7_no_fake_usd_estimated`
- [x] Unit tests present (mocked network) → `a7_tests_present`
- [x] No keys in source → `a7_no_keys_in_source`
- [x] ADR + FEEDBACK APPROVED + STATE A7 → `a7_adr_present`, `a7_feedback_approved`, `a7_state_yaml_a7`
- [x] swift test green (331+) → `a7_swift_test_green` (+ `build_gate_as`)

**Regression:**
- [x] A1–A6 scripts still enabled (step-aware where needed) → full `run_all.sh`
- [x] `a6_no_a7_balance` inverted to step-aware for A7+ (QA maintenance, not product bug)
- [x] `a5_no_a6_stats_no_a7_balance` already step-aware (verified PASS at A7)
- [x] Terminal-state fix: a5/a6 no-balance + a6/a7 state_yaml now recognise API_USAGE_DONE as >=A6/>=A7 (re-run GREEN 133/0)

**N/A (with reason):**
- Interactive UI click-through of Refresh / balance row — **N/A (static QA)**: no XCUITest harness; logic covered via `CloudBalanceServiceTests` mocked-network e2e.
- Live OpenRouter/Ollama network calls — **N/A (no keys in QA)**: parsers/service exercised on mocked JSON; honesty guard asserts no-fetch for estimated providers.
- Balance for Gemini/Anthropic/Qwen — **N/A (out of scope A7)**: no API; asserted estimated-only via `a7_no_fake_usd_estimated` + `a7_catalog_balance_kinds`.

**Env-only handling:**
- `a7_swift_test_green.sh` / `build_gate_as.sh` may hit sandbox "Operation not permitted" → **ENV-ONLY** (warn, exit 0), not product FAIL.

---
