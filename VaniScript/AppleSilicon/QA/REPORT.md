# QA REPORT — VaniScript (API_USAGE / A7 — Реальный баланс, адаптер OpenRouter first)

- **Дата:** 2026-07-26
- **Трек/шаг:** API_USAGE / **A7** (Real balance adapter — OpenRouter first)
- **Контекст прогона:** re-validation A7-покрытия при терминальном `current_step: API_USAGE_DONE`
  (трек завершён: A1–A8 done, A8 doc-only). STATE/FEEDBACK/ADR/§A7 сверены.
- **Suite:** 133 скрипта → **133 PASS / 0 FAIL** → **GREEN**
- **swift test:** **331 tests / 47 suites, 0 failures** (GREEN) — совпадает с ADR D-2026-07-26-A7 и FEEDBACK
- **swift build:** covered via `build_gate_as` (GREEN)
- **A7-скриптов:** **19** (категория `a7-*`), все PASS
- **Bugs open:** 0
- **Вердикт:** **GREEN**

---

## Что произошло в этом прогоне

Первый полный прогон дал **129 PASS / 4 FAIL**. Все 4 падения — **QA-maintenance, не баги
продукта** (product-код не менялся; swift test 331 GREEN): четыре step-aware скрипта
распознавали только литералы A7/A8/A9+, но **не терминальное состояние трека
`API_USAGE_DONE`**, поэтому ложно шли по pre-A7/pre-A6 ветке и падали на уже существующем
`CloudBalanceService` / актуальном STATE.

| Script | Причина падения (by design) | Фикс (QA maintenance) |
|---|---|---|
| `a5_no_a6_stats_no_a7_balance.sh` | «CloudBalanceService present (A7 out of scope)» | a6_or_later + 2×A7+ allowance теперь признают `API_USAGE_DONE` |
| `a6_no_a7_balance.sh` | «CloudBalanceService present (A7 out of scope for A6)» | a7_or_later detector признаёт `API_USAGE_DONE` → проверяет A7-контракт |
| `a6_state_yaml_a6.sh` | «current_step is not A6 (got API_USAGE_DONE)» | soft N/A при шаге после A6 (включая `API_USAGE_DONE`) |
| `a7_state_yaml_a7.sh` | «current_step is not A7 (got API_USAGE_DONE)» | soft N/A при шаге после A7 (включая `API_USAGE_DONE`) |

После правок повторный полный прогон: **133 PASS / 0 FAIL → GREEN**.

## Результат полного re-run (`QA/run_all.sh`)

```
PASS: 133   FAIL: 0
RESULT: GREEN
```

Команда:

```bash
cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"
QA/run_all.sh
```

## A7-скрипты (19, все PASS)

| # | Скрипт | Что проверено | Результат |
|---|---|---|---|
| 1 | `a7_balance_service_present.sh` | CloudBalanceService.swift: actor + BalanceProvider + провайдеры + A7-маркеры | PASS |
| 2 | `a7_balance_info_cases.sh` | BalanceInfo `.usd`/`.planLimits`/`.unavailable`, Equatable+Sendable | PASS |
| 3 | `a7_openrouter_parsers.sh` | `/api/v1/credits` + `/api/v1/key` (Bearer); чистые parseCredits/parseKey; typed error | PASS |
| 4 | `a7_openrouter_mapping.sh` | remaining = credits−usage; per-key cap через min(); total = keyLimit ?? credits | PASS |
| 5 | `a7_ollama_plan_based.sh` | Ollama → `.planLimits("Plan-based (GPU time)")`, никогда `.usd` | PASS |
| 6 | `a7_honesty_guard_no_fetch.sh` | `.none`/`.estimated` → nil → `.unavailable` без сети; пустой ключ OpenRouter без сети | PASS |
| 7 | `a7_quiet_fallback.sh` | CloudBalanceError typed; do/catch → `.unavailable`; non-2xx → `.requestFailed` | PASS |
| 8 | `a7_ttl_cache_force.sh` | TTL=60s in-memory; force bypass; invalidate(); session-only (без персиста) | PASS |
| 9 | `a7_http_fetcher_injected.sh` | сеть только через инжектируемый CloudHTTPFetcher (A4); нет прямого URLSession | PASS |
| 10 | `a7_catalog_balance_kinds.sh` | openrouter=credits, ollama=plan, gemini/openai/anthropic/qwen/custom=estimated | PASS |
| 11 | `a7_settings_balance_row.sh` | CloudBalanceRow module-visible, gated, `.usd`/`.planLimits`/`Estimated only`, lazy+Refresh | PASS |
| 12 | `a7_usage_stats_real_balance.sh` | realBalanceSection переиспользует CloudBalanceRow, gated by kind+key | PASS |
| 13 | `a7_no_fake_usd_estimated.sh` | нет фейковых $ для estimated; A6-дисклеймер цел; баланс только для real kinds | PASS |
| 14 | `a7_tests_present.sh` | @Suite("CloudBalanceService (A7)"): parsers/cap/Ollama/guard/quiet/cache/force, мок-сеть | PASS |
| 15 | `a7_no_keys_in_source.sh` | нет sk-/AIza/ghp_/xox- в A7 источниках/тестах (§14.7) | PASS |
| 16 | `a7_adr_present.sh` | ADR D-2026-07-26-A7 с формами OpenRouter + honesty + 331 tests | PASS |
| 17 | `a7_feedback_approved.sh` | FEEDBACK A7 [APPROVED] + handoff claims | PASS |
| 18 | `a7_state_yaml_a7.sh` | step-aware: A7 gate либо soft N/A на `API_USAGE_DONE` | PASS |
| 19 | `a7_swift_test_green.sh` | 331 tests / 0 failures | PASS |

## Регрессия (все prior-скрипты re-run green)

- **Build gates:** `build_gate_as.sh`, `build_gate_electron.sh` — PASS.
- **MCP smoke:** `mcp_smoke_as.sh` — PASS.
- **Q7 doc-delta (12)** — PASS.
- **A1 (5)** — PASS. **A2 (20)** — PASS. **A3 (21)** — PASS. **A4 (21)** — PASS.
- **A5 (17)** — PASS; `a5_no_a6_stats_no_a7_balance` step-aware (stats N/A на A6+, balance OK на A7+).
- **A6 (18)** — PASS; `a6_no_a7_balance` step-aware (balance-half N/A → A7-контракт).

## Scope / N/A (Verifier OK, not bugs)

- **Баланс только для real-balance провайдеров** (OpenRouter/Ollama); Gemini/Anthropic/Qwen — Estimated only (нет API).
- **Нет фейковых «$»** для `.estimated`; тихий fallback `.unavailable` при ошибке.
- **Live network** — N/A в QA (нет ключей): парсеры/сервис на мок-JSON; honesty guard гарантирует no-fetch.
- Interactive UI click-through (Refresh) — static QA only; логика покрыта `CloudBalanceServiceTests` (мок-сеть e2e).

## Graphify

- Graph-first: запрошен `graphify-out/graph.json` по BalanceKind / CloudProviderDescriptor / CloudProviderCatalog / ProviderCardView перед написанием скриптов.
- Product: `CloudBalanceService` (actor) роутит по `balanceKind`; `CloudBalanceRow` переиспользуется между SettingsView-карточками и UsageStatisticsView.

## Deliverables (QA only)

- `QA/scripts/a7_*.sh` (19)
- Step-aware terminal-state fix: `a5_no_a6_stats_no_a7_balance.sh`, `a6_no_a7_balance.sh`, `a6_state_yaml_a6.sh`, `a7_state_yaml_a7.sh` (4)
- `QA/manifest.json` (133 enabled)
- `QA/COVERAGE.md` (A7 section + gap checklist + terminal-state maintenance note)
- `QA/REPORT.md` (this file)

## Orchestrator handoff

- **qa.status:** green
- **bugs_open:** 0
- **next_actor:** orchestrator
- **Note:** трек API_USAGE_DONE; A7 re-validation GREEN. Никаких product-изменений — только QA step-aware maintenance.
