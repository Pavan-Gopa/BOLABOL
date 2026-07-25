# QA REPORT — VaniScript (Q7 doc-only cycle, re-run after BUG-003 fix)

- **Дата:** 2026-07-26
- **Трек/шаг:** QWEN_MCP / Q7 (doc-only + acceptance smoke)
- **Suite:** 15 скриптов → **15 PASS / 0 FAIL** → **GREEN**
- **Bugs open:** 0
- **Вердикт:** **GREEN** — трек QWEN_MCP готов к переходу `QWEN_MCP → QWEN_DONE`.

---

## Результат re-run (после фикса BUG-003)

Фикс: кодер добавил `qwen3.8-max-preview` в `QWEN_MCP_ACCEPTANCE.md`
(строка 29: `model qwen3.8-max-preview (-m qwen3.8-max-preview)`).
Полный re-run `QA/run_all.sh` (все 15 скриптов, без новых скриптов):

| # | Скрипт | Результат |
|---|---|---|
| 1 | build_gate_as.sh | PASS (swift test 267 тестов / 40 suites, 0 failures) |
| 2 | build_gate_electron.sh | PASS (tsc --noEmit) |
| 3 | mcp_smoke_as.sh | PASS (static smoke :19790 + SSE + McpContracts) |
| 4 | q7_acceptance_all_checked.sh | PASS (26 [x], 0 [ ], ИТОГ [PASS]) |
| 5 | q7_acceptance_3_surfaces.sh | PASS (External/AS embedded/Electron embedded) |
| 6 | **q7_acceptance_real_paths.sh** | **PASS** (19790, 19789, qwen3.8-max-preview, qwen binary) — **BUG-003 CLOSED** |
| 7 | q7_acceptance_invariants.sh | PASS (no silent fallback / token / vaniscript_embedded / Codex-Grok) |
| 8 | q7_readme_qwen_provider.sh | PASS (- **Qwen** bullet) |
| 9 | q7_readme_no_rewrite.sh | PASS (Direction, Local Run сохранены) |
| 10 | q7_mcp_instructions_qwen.sh | PASS (External Qwen CLI, 19790, 19789) |
| 11 | q7_mcp_instructions_no_electron.sh | PASS (BUG-002 инвариант: 0 electron) |
| 12 | q7_decisions_adr_done.sh | PASS (QWEN_MCP track complete, QWEN_DONE) |
| 13 | q7_decisions_adr_format.sh | PASS (D-2026-07-26-Q7) |
| 14 | q7_doc_only_no_code.sh | PASS (только .md/.yaml в diff под AppleSilicon/) |
| 15 | q7_swift_test_green.sh | PASS (267 тестов, 0 failures) |

**Итог прогона:** `PASS: 15   FAIL: 0` → `RESULT: GREEN`.

## Подтверждённые инварианты
- **BUG-002:** `grep -ci electron AppleSilicon/MCP_INSTRUCTIONS.md == 0` ✓
- **doc-only gate:** в diff под `AppleSilicon/` только `.md`/`.yaml`, ни одного `.swift/.js/.ts/.py` ✓
- **swift test:** 267 тестов / 40 suites, 0 failures ✓
- **ACCEPTANCE:** все чекбоксы `[x]`, `ИТОГ: [PASS]`, 3 поверхности, реальные пути + модель ✓
- **ADR:** `D-2026-07-26-Q7 — QWEN_MCP track complete`, статус `QWEN_DONE` ✓

## Закрытые баги
- **BUG-003 — CLOSED.** ACCEPTANCE.md теперь содержит верифицированный model id
  `qwen3.8-max-preview`. Детектор `q7_acceptance_real_paths.sh` проходит.

## Замечания (не product-баги, для прозрачности; см. BUG_REPORT.md §N1/N2)
- N1: расхождение «62 скрипта» в STATE.yaml vs реальный suite (15). Реальный suite собран
  из существующих на диске скриптов + 12 Q7 delta + 2 реализованных фантомных инфраскрипта.
- N2: в прошлом прогоне почищены QA-инфра баги (run_all.sh bash 3.2 `mapfile`;
  парсер swift-testing в q7_swift_test_green.sh).

---

**Вердикт: GREEN — 15/15 PASS, 0 bugs open. Зови оркестратора** (переход `QWEN_MCP → QWEN_DONE`).
