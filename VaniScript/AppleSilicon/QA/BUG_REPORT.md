# QA BUG REPORT — VaniScript (Q7 doc-only cycle)

- **Дата:** 2026-07-26
- **Трек/шаг:** QWEN_MCP / Q7 (doc-only + acceptance smoke)
- **Suite:** 15 скриптов → **15 PASS / 0 FAIL** → **GREEN** (re-run после фикса)
- **Bugs open:** 0
- **Статус:** **BUG-003 CLOSED** (re-run 2026-07-26 GREEN). Product-код не менялся;
  фикс — только документация (Coder добавил model id в ACCEPTANCE.md).

---

## BUG-003 — [CLOSED] ACCEPTANCE.md не содержал верифицированный model id `qwen3.8-max-preview`

> **CLOSED (2026-07-26, re-run GREEN).** Coder добавил model id в
> `QWEN_MCP_ACCEPTANCE.md` (строка 29: `model qwen3.8-max-preview (-m qwen3.8-max-preview)`).
> Детектор `q7_acceptance_real_paths.sh` теперь PASS (все 4 значения на месте).
> Полный re-run: 15/15 PASS.

- **Скрипт-детектор:** `QA/scripts/q7_acceptance_real_paths.sh`
- **Область:** документация (`AI_Workflow_Kit/docs/QWEN_MCP_ACCEPTANCE.md`), НЕ product-код.
- **Серьёзность:** Medium (doc-completeness; acceptance-чеклист неполон).
- **Симптом:** acceptance-документ заявляет «заполнен реальными путями/командами по факту Q1–Q6»,
  но не фиксирует верифицированный model id, хотя он указан в `DECISIONS.md`
  (D-2026-07-25 Q1, тег `[high]`: `qwen3.8-max-preview` через `-m qwen3.8-max-preview`)
  и в `README.md` (строка 23: `model qwen3.8-max-preview`).

**Фактический вывод скрипта:**
```
OK: real value present — '19790'
OK: real value present — '19789'
FAIL: real value missing — 'qwen3.8-max-preview'
OK: real value present — '/Users/pavan/.local/bin/qwen'
RESULT: FAIL (q7_acceptance_real_paths)
```

**Воспроизведение:**
```bash
cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"
grep -c 'qwen3.8-max-preview' AI_Workflow_Kit/docs/QWEN_MCP_ACCEPTANCE.md   # → 0
```

**Ожидаемое поведение:** `qwen3.8-max-preview` присутствует в ACCEPTANCE.md
(минимум 1 раз), чтобы acceptance поверхности №2 (embedded chat) явно фиксировал
модель, на которой прогонялся чат.

**Предлагаемый фикс (владелец — Coder, только .md):**
В секции «Путь 2 — Apple Silicon embedded Qwen chat» дополнить bullet про spawn CLI,
например:
> `- [x] Выбор Qwen → QwenAgentService spawn qwen CLI (Codex/Grok pattern), binary
>  /Users/pavan/.local/bin/qwen, model qwen3.8-max-preview (-m qwen3.8-max-preview)`

Либо добавить отдельный checked-bullet «Модель `qwen3.8-max-preview` (по данным Q1 discovery)».
После фикса re-run `QA/run_all.sh` → ожидается 15/15 GREEN.

---

## Прочие наблюдения (НЕ product-баги, зафиксированы для прозрачности)

### N1 — State-integrity: расхождение числа QA-скриптов
`STATE.yaml` и бриф заявляют «62 скрипта (47 старых + 15 Q6), все green», однако **на диске
в `QA/scripts/` существовал только `build_gate_as.sh`**, а `manifest.json` ссылался ещё на
2 файла (`build_gate_electron.sh`, `mcp_smoke_as.sh`), которых **не было** (запуск старого
manifest дал бы 2 ложных MISSING→FAIL). Перезапустить «62 старых скрипта» невозможно —
их нет. Предпринятое действие: реализованы 2 фантомных инфраскрипта, сохранён
`build_gate_as.sh`, добавлены 12 Q7-скриптов. Реальный suite = **15 скриптов**.
Это расхождение состояния, а не баг product-кода.

### N2 — QA-инфра фиксы (в зоне QA, сделаны в этом прогоне)
1. `QA/run_all.sh` использовал `mapfile` (bash 4+); macOS `/usr/bin/env bash` = **bash 3.2.57**
   → runner падал (`mapfile: command not found`), suite не исполнялся. Заменено на
   bash-3.2-совместимый `while read` loop. Без этого фикса ни один скрипт не запускался.
2. `QA/scripts/q7_swift_test_green.sh` изначально читал XCTest-сводку
   `Executed 0 tests, with 0 failures` (swift-testing печатает её при 0 XCTest-кейсов) и
   ложно падал с «no tests executed». Парсер переключён на swift-testing-сводку
   `Test run with 267 tests in 40 suites passed` (+ fallback на XCTest, + детект `N failures`).
   Теперь корректно: **267 тестов, 0 failures → PASS**.

---

## Сводка suite (15 скриптов)

| # | Скрипт | Результат |
|---|---|---|
| 1 | build_gate_as.sh | PASS (swift test 267/40) |
| 2 | build_gate_electron.sh | PASS (tsc --noEmit) |
| 3 | mcp_smoke_as.sh | PASS (static smoke :19790) |
| 4 | q7_acceptance_all_checked.sh | PASS (26 [x], 0 [ ], ИТОГ [PASS]) |
| 5 | q7_acceptance_3_surfaces.sh | PASS |
| 6 | **q7_acceptance_real_paths.sh** | **FAIL — BUG-003** |
| 7 | q7_acceptance_invariants.sh | PASS |
| 8 | q7_readme_qwen_provider.sh | PASS |
| 9 | q7_readme_no_rewrite.sh | PASS |
| 10 | q7_mcp_instructions_qwen.sh | PASS |
| 11 | q7_mcp_instructions_no_electron.sh | PASS (BUG-002 инвариант: 0 electron) |
| 12 | q7_decisions_adr_done.sh | PASS |
| 13 | q7_decisions_adr_format.sh | PASS (D-2026-07-26-Q7) |
| 14 | q7_doc_only_no_code.sh | PASS (только .md/.yaml в diff) |
| 15 | q7_swift_test_green.sh | PASS (267 тестов, 0 failures) |

**Вердикт: RED** — 1 реальный doc-баг (BUG-003). Product-код не менялся, `swift test` green,
инвариант BUG-002 соблюдён, doc-only gate чист. Требуется doc-фикс от Coder и re-run.
