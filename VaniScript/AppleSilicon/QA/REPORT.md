# QA REPORT — VaniScript (API_USAGE / A3 — UI reorg: dropdown + cards)

- **Дата:** 2026-07-26
- **Трек/шаг:** API_USAGE / **A3** (единый dropdown провайдеров + условные карточки)
- **Suite:** 60 скриптов → **60 PASS / 0 FAIL** → **GREEN**
- **Новых скриптов в этом прогоне:** **21** (категория `a3-delta` / `a3-regression`)
- **swift test:** **287 тестов / 42 suites, 0 failures** (GREEN)
- **swift build:** **Build complete!** (GREEN)
- **Bugs open:** 0
- **Вердикт:** **GREEN** — A3 готов к post-tag `apiusage/A3-done`.

---

## Результат полного re-run (`QA/run_all.sh`)

Полный re-run всего manifest (60 скриптов, без сжатия):

```
PASS: 60   FAIL: 0
RESULT: GREEN
```

Команда:

```bash
cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"
QA/run_all.sh
```

### Новые A3-скрипты (21, все PASS)

| # | Скрипт | Что проверено | Результат |
|---|---|---|---|
| 1 | `a3_selected_provider_default.sh` | `@State selectedProviderId = CloudProviderCatalog.geminiID` | PASS |
| 2 | `a3_picker_uses_catalog.sh` | `ForEach(CloudProviderCatalog.providers)` + Picker binding | PASS |
| 3 | `a3_single_card_at_a_time.sh` | 1× `ProviderCardView(descriptor:)`; no always-expanded sections | PASS |
| 4 | `a3_api_keys_tab_structure.sh` | Cloud Provider → conditional card → Cloud Usage Statistics | PASS |
| 5 | `a3_custom_path_intact.sh` | `customProvidersSection` add/remove, gated by `customID` | PASS |
| 6 | `a3_provider_card_location.sh` | ProviderCardView in SettingsView (in-file OK) | PASS |
| 7 | `a3_engine_ids_preserved.sh` | `gemini-cloud` / `gpt-cloud` / `coreml-whisperkit` / `mlx-native` | PASS |
| 8 | `a3_gemini_openai_parity.sh` | key + ReadOnlyRow + budget Slider + Transcribing/Translation | PASS |
| 9 | `a3_anthropic_card.sh` | Anthropic Key + ReadOnlyRow Text Model | PASS |
| 10 | `a3_coming_soon_stub.sh` | default → `comingSoonCard` for Qwen/OpenRouter/Ollama | PASS |
| 11 | `a3_stub_key_fields.sh` | `qwenApiKey` / `openrouterApiKey` / `ollamaCloudApiKey` | PASS |
| 12 | `a3_get_api_key_url_descriptor.sh` | `urlString: descriptor.getApiKeyURL` (4 call sites) | PASS |
| 13 | `a3_stats_section_unchanged.sh` | Cloud Usage Statistics + Reset/StatItem/BudgetBar intact | PASS |
| 14 | `a3_no_a4_validation_or_model_net.sh` | no CloudKeyValidator/CloudModelCatalog/URLSession in card | PASS |
| 15 | `a3_no_a5_engine_routing.sh` | no transcription/translation assign to qwen/openrouter/ollama | PASS |
| 16 | `a3_switch_covers_catalog_ids.sh` | all catalog IDs referenced; A1 fixed order intact | PASS |
| 17 | `a3_scope_no_engine_usage_changes.sh` | no A5 cases in WorkflowStore normalizedUsageProviderId | PASS |
| 18 | `a3_no_hardcoded_api_keys.sh` | no sk-/AIza/ghp_/xox- literals (§14.7) | PASS |
| 19 | `a3_feedback_approved.sh` | FEEDBACK A3 `[APPROVED]` + handoff claims | PASS |
| 20 | `a3_state_yaml_a3.sh` | `current_step: A3`; implementation+review approved | PASS |
| 21 | `a3_swift_build_green.sh` | `swift build` green | PASS |

### Регрессия (все prior-скрипты re-run green)

- **Build gates:** `build_gate_as.sh` (swift test 287/42), `build_gate_electron.sh` (tsc --noEmit) — PASS.
- **MCP smoke:** `mcp_smoke_as.sh` (:19790 + SSE + McpContracts) — PASS.
- **Q7 doc-delta (12)** — PASS; `q7_doc_only_no_code` step-aware N/A for code step A3 — PASS.
- **Q7 / A2 swift test gates** — PASS (287 tests, 0 failures).
- **A1 (5):** catalog order, decodeIfPresent, defaults, no-network — PASS.
- **A2 (20):** UsageRecorder purity/parsers/record/WorkflowStore/tests/ADR/keys — PASS.

## Gap hunt: закрыт (см. QA/COVERAGE.md §A3)

Закрыты ВСЕ пункты чеклиста A3:

- Picker uses catalog order (not hardcoded gemini/openai only)
- Only one provider card rendered at a time
- Custom path still has add/remove custom providers
- Engine ids preserved: gemini-cloud / gpt-cloud / coreml-whisperkit / mlx-native
- Stub providers write keys to correct AppSettings fields
- getApiKeyURL from descriptor
- Stats section still present (not deleted)
- No A4 validation badge / model dropdown network code
- No A5 engine routing for qwen/openrouter/ollama
- selectedProviderId default gemini; Gemini/OpenAI/Anthropic card parity
- ProviderCardView in-file OK; FEEDBACK [APPROVED]; swift build green
- No secrets in SettingsView

**N/A (с обоснованием):**

- Separate `ProviderCardView.swift` — **N/A**: optional per STEPS; Verifier APPROVED in-file helper (`a3_provider_card_location`).
- Interactive UI click-through of Picker — **N/A (static QA)**: suite is structure/grep based; no XCUITest harness in track.
- A4 key validation / A5 engines / A6 stats rebuild — **N/A (out of scope A3)**; negative scripts assert absence.

## Подтверждённые инварианты (§14)

- **§14.1** AppSettings decode not touched by A3 (UI only) ✓
- **§14.2** Codex/Grok/Qwen/MCP/local models not broken; engine routing for new providers deferred A5 ✓
- **§14.7** no keys/tokens in SettingsView source ✓
- **§14.8** buildable/testable: swift build + swift test 287/42 GREEN ✓
- **§14.9** product delta scoped to SettingsView UI + FEEDBACK/STATE docs ✓

## Product surface (asserted, not modified)

- `Sources/VaniScript/Views/SettingsView.swift`
  - `@State selectedProviderId` default `geminiID`
  - `apiKeysTab`: single Picker over `CloudProviderCatalog.providers`
  - Custom → `customProvidersSection`; else `ProviderCardView(descriptor:)`
  - ProviderCardView in-file (file-private helpers)
  - Gemini/OpenAI: key + ReadOnlyRow model + budget Slider + toggles 1:1
  - Anthropic: key + ReadOnlyRow model
  - Qwen/OpenRouter/Ollama: key + coming soon → correct AppSettings fields
  - «Cloud Usage Statistics» UNCHANGED (A6)

## Handoff

- **next_actor:** orchestrator
- **Recommendation:** post-tag `apiusage/A3-done`; advance track to A4 when ready.
- **Bugs:** none opened this run. Historical `QA/BUG_REPORT.md` remains A1-stale; current status is this REPORT.

---

**Готово. QA green. Скажи оркестратору: статус**
