# QA REPORT — VaniScript (API_USAGE / A7 — Реальный баланс, адаптер OpenRouter first)

- **Дата:** 2026-07-26
- **Трек/шаг:** API_USAGE / **A7** (Real balance adapter — OpenRouter first)
- **Suite:** 133 скриптов → **133 PASS / 0 FAIL** → **GREEN**
- **Новых скриптов в этом прогоне:** **19** (категория `a7-*`)
- **Адаптации регрессии (step-aware):** **1** (`a6_no_a7_balance`); `a5_no_a6_stats_no_a7_balance` уже был step-aware (проверен, PASS)
- **swift test:** **331 tests / 47 suites, 0 failures** (GREEN) — совпадает с ADR/FEEDBACK
- **swift build:** covered via `build_gate_as` / prior gates (GREEN)
- **Bugs open:** 0
- **Вердикт:** **GREEN** — A7 готов к post-tag `apiusage/A7-done`.

---

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

### Новые A7-скрипты (19, все PASS)

| # | Скрипт | Что проверено | Результат |
|---|---|---|---|
| 1 | `a7_balance_service_present.sh` | CloudBalanceService.swift: actor + BalanceProvider + провайдеры + A7-маркеры | PASS |
| 2 | `a7_balance_info_cases.sh` | BalanceInfo `.usd`/`.planLimits`/`.unavailable`, Equatable+Sendable | PASS |
| 3 | `a7_openrouter_parsers.sh` | `/api/v1/credits` + `/api/v1/key` (Bearer); чистые parseCredits/parseKey; typed error | PASS |
| 4 | `a7_openrouter_mapping.sh` | remaining = credits−usage; per-key cap `min(...)`; total = keyLimit ?? credits | PASS |
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
| 18 | `a7_state_yaml_a7.sh` | current_step A7; implementation+review approved; target_files → CloudBalanceService | PASS |
| 19 | `a7_swift_test_green.sh` | 331 tests / 0 failures | PASS |

### Регрессия (все prior-скрипты re-run green)

- **Build gates:** `build_gate_as.sh`, `build_gate_electron.sh` — PASS.
- **MCP smoke:** `mcp_smoke_as.sh` — PASS.
- **Q7 doc-delta (12)** — PASS.
- **A1 (5)** — PASS.
- **A2 (20)** — PASS.
- **A3 (21)** — PASS.
- **A4 (21)** — PASS.
- **A5 (17)** — PASS; `a5_no_a6_stats_no_a7_balance` step-aware (balance half OK на A7+).
- **A6 (18)** — PASS; `a6_no_a7_balance` адаптирован под A7+.

### Адаптация регрессии (не баг продукта)

| Script | Change |
|---|---|
| `a6_no_a7_balance.sh` | step-aware: pre-A7 строго (нет balance-сервиса); A7+ balance-half N/A → проверяем reuse `CloudBalanceRow` + нет прямого `URLSession` в UsageStatisticsView |

> Примечание: `a5_no_a6_stats_no_a7_balance.sh` уже был step-aware и прошёл без правок
> (проверено: balance-half = OK на A7+). Это QA-сопровождение, а не баг продукта.

### Scope / N/A (Verifier OK, not bugs)

- **Баланс только для real-balance провайдеров** (OpenRouter/Ollama); Gemini/Anthropic/Qwen — Estimated only (нет API).
- **Нет фейковых «$»** для `.estimated`; тихий fallback `.unavailable` при ошибке.
- **Live network** — N/A в QA (нет ключей): парсеры/сервис на мок-JSON; honesty guard гарантирует no-fetch.
- Interactive UI click-through (Refresh) — static QA only; логика покрыта `CloudBalanceServiceTests` (мок-сеть e2e).

### Graphify

- Queried graph (`graphify-out/graph.json`) for BalanceKind / CloudProviderDescriptor / CloudProviderCatalog / ProviderCardView before writing scripts.
- Product: `CloudBalanceService` (actor) routes by `balanceKind`; `CloudBalanceRow` shared between SettingsView cards и UsageStatisticsView.

### Deliverables (QA only)

- `QA/scripts/a7_*.sh` (19)
- Step-aware update to `a6_no_a7_balance.sh` (1)
- `QA/manifest.json` (133 enabled)
- `QA/COVERAGE.md` (A7 section + gap checklist)
- `QA/REPORT.md` (this file)

### Orchestrator handoff

- **qa.status:** green
- **bugs_open:** 0
- **next_actor:** orchestrator
- **Recommended:** post-tag `apiusage/A7-done`, advance STATE to A8, `next_actor` per TEAM_CONTRACT.

