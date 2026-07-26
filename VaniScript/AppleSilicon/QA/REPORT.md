# QA REPORT — VaniScript (API_USAGE / A4 — Key validation + model catalog)

- **Дата:** 2026-07-26
- **Трек/шаг:** API_USAGE / **A4** (валидация ключа + автоподтягивание моделей)
- **Suite:** 81 скриптов → **81 PASS / 0 FAIL** → **GREEN**
- **Новых скриптов в этом прогоне:** **21** (категория `a4-delta` / `a4-regression`)
- **Адаптации A3 (step-aware):** **4** (`a3_no_a4_*`, `a3_gemini_openai_parity`, `a3_state_yaml_a3`, `a3_feedback_approved`)
- **swift test:** **308 tests / 44 suites, 0 failures** (GREEN)
- **swift build:** **Build complete!** (GREEN)
- **Bugs open:** 0
- **Вердикт:** **GREEN** — A4 готов к post-tag `apiusage/A4-done`.

---

## Результат полного re-run (`QA/run_all.sh`)

```
PASS: 81   FAIL: 0
RESULT: GREEN
```

Команда:

```bash
cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"
QA/run_all.sh
```

### Новые A4-скрипты (21, все PASS)

| # | Скрипт | Что проверено | Результат |
|---|---|---|---|
| 1 | `a4_key_validator_status_map.sh` | idle/checking/valid/invalid; 2xx/401/403/429/other | PASS |
| 2 | `a4_key_validator_empty_custom.sh` | empty → idle; custom → valid без сети | PASS |
| 3 | `a4_key_validator_uses_list_request.sh` | validate via `listRequest` + fetcher | PASS |
| 4 | `a4_catalog_parsers.sh` | OpenAI/Gemini/Ollama(+Anthropic shared) parsers + tests | PASS |
| 5 | `a4_catalog_dedup.sh` | de-dupe + empty drop | PASS |
| 6 | `a4_catalog_list_request_auth.sh` | Gemini `?key=`, Bearer, Anthropic x-api-key, Ollama tags | PASS |
| 7 | `a4_catalog_session_cache_fingerprint.sh` | session cache + keyFingerprint + invalidate | PASS |
| 8 | `a4_catalog_fetcher_injectable.sh` | CloudHTTPFetcher injectable; tests mock | PASS |
| 9 | `a4_settings_cloud_key_model_row.sh` | badge + Picker/editable+Retry | PASS |
| 10 | `a4_settings_writes_text_models.sh` | geminiTextModel / openaiTextModel bindings | PASS |
| 11 | `a4_settings_debounce.sh` | `.task(id:)` + 500ms; core timer-free | PASS |
| 12 | `a4_transcription_resolve_gemini_settings.sh` | Gemini from settings; whisper-1 deferred | PASS |
| 13 | `a4_translation_resolve_settings_fallback.sh` | settings + hardcode fallbacks | PASS |
| 14 | `a4_tests_present.sh` | 9 + 12 @Test; A4 suites | PASS |
| 15 | `a4_no_keys_in_source.sh` | no sk-/AIza secrets §14.7 | PASS |
| 16 | `a4_no_a5_engine_routing.sh` | no qwen/openrouter/ollama engine routing | PASS |
| 17 | `a4_no_a6_stats_rewrite.sh` | Cloud Usage Statistics intact | PASS |
| 18 | `a4_anthropic_readonly_whisper_ok.sh` | Anthropic ReadOnly + whisper-1 OK (not bugs) | PASS |
| 19 | `a4_feedback_approved.sh` | FEEDBACK A4 [APPROVED] | PASS |
| 20 | `a4_state_yaml_a4.sh` | current_step A4; impl+review approved | PASS |
| 21 | `a4_swift_test_green.sh` | 308 tests / 0 failures | PASS |

### Регрессия (все prior-скрипты re-run green)

- **Build gates:** `build_gate_as.sh` (swift test 308/44), `build_gate_electron.sh` (tsc --noEmit) — PASS.
- **MCP smoke:** `mcp_smoke_as.sh` (:19790 + SSE + McpContracts) — PASS.
- **Q7 doc-delta (12)** — PASS; `q7_doc_only_no_code` step-aware N/A for code step A4 — PASS.
- **Q7 / A2 / A4 swift test gates** — PASS (308 tests, 0 failures).
- **A1 (5):** catalog order, decodeIfPresent, defaults, no-network — PASS.
- **A2 (20):** UsageRecorder purity/parsers/record/WorkflowStore/tests/ADR/keys — PASS.
- **A3 (21):** UI reorg; step-aware N/A for A3-only negative gates; Gemini/OpenAI parity accepts CloudKeyModelRow on A4 — PASS.

## Gap hunt: закрыт (см. QA/COVERAGE.md §A4)

Закрыты ВСЕ пункты чеклиста A4:

- HTTP status map 2xx/401/403/429/other
- empty key → idle; custom → valid without network
- validate via listRequest; parsers OpenAI/Gemini/Ollama/Anthropic; dedup
- session cache + key fingerprint (no raw secret); injectable CloudHTTPFetcher
- CloudKeyModelRow badge + Picker/editable+Retry; debounce; writes text models
- transcription/translation resolve settings + hardcode fallbacks
- whisper-1 + Anthropic ReadOnly — Verifier scope OK (not product bugs)
- no A5 engine routing; no A6 stats rewrite; no secrets in source
- unit tests present; swift test 308 green; A1+A2+A3 regression PASS

## Scope notes (Verifier-accepted, not FAIL)

| Item | Disposition |
|---|---|
| Anthropic Text Model stays `ReadOnlyRow` | OK — no settings field / engine routing in A4 |
| OpenAI transcription hardcode `whisper-1` | OK — audio model; deferred to A5 audio-picker |
| No qwen/openrouter/ollama engine routing | Correctly out of A4 (A5) |
| Stats section not rewritten | Correctly out of A4 (A6) |

## Graphify

- Query first against `graphify-out/graph.json` (graph predates A4 nodes; source assert used as ground truth for new files).
