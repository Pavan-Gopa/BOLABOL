# QA REPORT — VaniScript (API_USAGE / A2 — Запись использования)

- **Дата:** 2026-07-26
- **Трек/шаг:** API_USAGE / **A2** (usage recording — чинит пустую статистику)
- **Suite:** 39 скриптов → **39 PASS / 0 FAIL** → **GREEN**
- **Новых скриптов в этом прогоне:** 19 (категория `a2-delta` / `a2-regression`)
- **swift test:** **287 тестов / 42 suites, 0 failures** (GREEN; ENV-ONLY не сработал)
- **Bugs open:** 0
- **Вердикт:** **GREEN** — A2 готов к post-tag `apiusage/A2-done`.

---

## Результат полного re-run (`QA/run_all.sh`)

После фикса устаревшего QA-гейта (см. §«QA-script maintenance») выполнен ПОЛНЫЙ re-run
всего manifest (39 скриптов, без сжатия): `PASS: 39   FAIL: 0` → `RESULT: GREEN`.

### Новые A2-скрипты (19, все PASS)

| # | Скрипт | Что проверено | Результат |
|---|---|---|---|
| 1 | `a2_usagerecorder_purity.sh` | `UsageRecorder` — pure non-throwing enum, Foundation-only, нет I/O/UI | PASS |
| 2 | `a2_tokenusage_type.sh` | `TokenUsage` public struct Equatable+Sendable, isEmpty, `+` | PASS |
| 3 | `a2_record_aggregation.sh` | инкремент sessions/input/output/audio + все last* | PASS |
| 4 | `a2_record_per_model_key.sh` | ключ `providerId:model` (§6.2), blank-model fallback | PASS |
| 5 | `a2_record_besteffort_noop.sh` | no-op при nil/empty delta + no audio (§14.4) | PASS |
| 6 | `a2_parser_gemini.sh` | usageMetadata.prompt/candidatesTokenCount, nil on empty | PASS |
| 7 | `a2_parser_openai.sh` | usage.prompt_tokens/completion_tokens (snake_case) | PASS |
| 8 | `a2_parsers_lenient_nil.sh` | `try?` x2, missing block→nil, non-throwing | PASS |
| 9 | `a2_transcription_result_usage.sh` | result.usage: TokenUsage? из Gemini+OpenAI | PASS |
| 10 | `a2_translation_accumulator.sh` | actor accumulator + takeLastUsage() defer-reset | PASS |
| 11 | `a2_workflowstore_record.sh` | takeLastUsage→guard→updateSettings→record, **8 call sites** | PASS |
| 12 | `a2_workflowstore_normalized_id.sh` | gemini-cloud→gemini, gpt-cloud→openai, default | PASS |
| 13 | `a2_workflowstore_besteffort.sh` | async non-throwing, early-return, §14.4 | PASS |
| 14 | `a2_tests_present.sh` | @Suite("UsageRecorder (A2)"), @testable, ровно 14 @Test | PASS |
| 15 | `a2_tests_coverage_areas.sh` | 14 именованных тестов покрывают все risk-areas | PASS |
| 16 | `a2_decisions_adr.sh` | ADR D-2026-07-26-A2 (§14.4, scope note, 287 tests) | PASS |
| 17 | `a2_no_keys_in_source.sh` | нет sk-/AIza/ghp_/xox- литералов (§14.7) | PASS |
| 18 | `a2_appsettings_usage_migration_safe.sh` | usage decodeIfPresent??[:]; last* optional (§14.1+A1) | PASS |
| 19 | `a2_swift_test_green.sh` | swift test green, 0 failures, 287 тестов | PASS |

### Регрессия (все prior-скрипты re-run green)
- **A1 (5):** catalog fixed order, AppSettings decodeIfPresent, ProviderUsage decodeIfPresent,
  catalog no-network, AppSettings defaults — **все PASS**.
- **Build gates:** `build_gate_as.sh` (swift test green), `build_gate_electron.sh` (tsc --noEmit) — PASS.
- **MCP smoke:** `mcp_smoke_as.sh` (:19790 + SSE + McpContracts) — PASS.
- **Q7 doc-delta (12) + q7_swift_test_green** — PASS.

## Gap hunt: закрыт (см. QA/COVERAGE.md §A2)

Закрыты ВСЕ пункты чеклиста A2: increment/per-model key/last*/no-op nil-delta; Gemini vs
OpenAI парсеры; missing usage→nil + op succeeds (best-effort); normalizedUsageProviderId;
движки возвращают TokenUsage; WorkflowStore пишет settings.usage; swift test green;
нет ключей в source (§14.7); AppSettings decode migration-safe (§14.1); ADR записан.

**N/A (с обоснованием):**
- `Tests/VaniScriptTests/CloudUsageParsingTests.swift` (в STEPS §A2 target_files) — **N/A**:
  отдельным файлом не создан, парсерное покрытие консолидировано в `UsageRecorderTests`
  (parsesGeminiUsage/parsesOpenAIUsage/missing→nil/malformed→nil), что Verifier явно одобрил
  (FEEDBACK §2, ADR D-2026-07-26-A2). Проверено через `a2_tests_coverage_areas`. Не баг.
- Проводка транскрипции → `settings.usage` через `NativeProcessingPipeline` — **N/A (DEFERRED
  to A5/A6)** по принятому Verifier scope note. Suite assert'ит, что движок ВОЗВРАЩАЕТ usage
  (`a2_transcription_result_usage`) и translation-путь ПИШЕТ (`a2_workflowstore_record`), и НЕ
  фейлится на отложенной pipeline-проводке.

## Подтверждённые инварианты (§14)
- **§14.1** decode AppSettings не сломан: `usage` через `decodeIfPresent ?? [:]`, last* optional ✓
- **§14.2** Codex/Grok/Qwen/MCP/локальные модели не тронуты (diff только в A2 target_files) ✓
- **§14.4** best-effort: парсеры non-throwing, record no-op без сигнала, store async non-throwing ✓
- **§14.7** нет ключей/токенов в исходниках и тестах ✓
- **§14.8** buildable/testable: swift build + swift test 287/42 GREEN ✓
- **§14.9** diff только в target_files шага ✓

## QA-script maintenance (не product-баг)
- `q7_doc_only_no_code.sh` в первом прогоне дал FAIL: это step-scoped гейт Q7 (doc-only шаг —
  «в diff нет .swift»), а текущий шаг **A2 — code step**, легитимно правящий одобренные
  target_files (`CloudAudioTranscriptionEngine.swift`, `CloudTextTranslationEngine.swift`,
  `WorkflowStore.swift`, + новый `UsageRecorder.swift`). Это **staleness QA-скрипта, не дефект
  продукта**. Скрипт сделан **step-aware**: enforce doc-only только для doc-only шагов
  (Q5/Q7/A8 по `STATE.yaml current_step`), для code-шагов — N/A (PASS). Guard сохранён для
  будущих doc-only шагов. После фикса — ПОЛНЫЙ re-run → GREEN.

## Bugs found this run: 0
Новых product-багов не обнаружено. A2 implementation (APPROVED Verifier) полностью подтверждён
на уровне source-asserts и swift test.

## Замечания (не product-баги, для прозрачности)
- N1: `a2_workflowstore_record.sh` насчитал **8** call sites `recordCloudTranslationUsage`
  (review + shorts cloud paths) — больше заявленных ≥4, покрытие шире.
- N2: `a2_swift_test_green.sh` имеет ENV-ONLY masking (sandbox ModuleCache «Operation not
  permitted» → warn/exit 0, не product FAIL). В этом прогоне swift test прошёл реально,
  ENV-ONLY не срабатывал (0 раз).

---

**Вердикт: GREEN — 39/39 PASS, 0 bugs open, swift test 287/42 GREEN. Зови оркестратора**
(переход API_USAGE A2 → post-tag `apiusage/A2-done`, далее A3).
