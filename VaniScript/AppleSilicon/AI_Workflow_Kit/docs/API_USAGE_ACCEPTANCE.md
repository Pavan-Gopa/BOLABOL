# API_USAGE — Acceptance smoke checklist

> Финальный acceptance трека `API_USAGE` (шаг A8, doc-only). По образцу
> `GROK_MCP_ACCEPTANCE.md` / `QWEN_MCP_ACCEPTANCE.md`. Проверяет **пять поверхностей**
> вкладки «API & Usage» (Apple Silicon only). Заполнено реальными путями/командами
> по факту A1–A7. Прогон без реальных API-ключей: сеть в тестах — моки
> (`CloudHTTPFetcher`), UI-пункты — ручной чеклист.

**Инварианты §14 (не нарушены):** AppSettings decode migration-safe; Codex/Grok/Qwen
chat + MCP + локальные модели не тронуты; никаких локальных серверов; usage — best-effort;
честная индикация Transcribing; реальный «$» только где провайдер отдаёт; ключей в
исходниках/логах/git нет; build/test green каждый шаг.

---

## Смоук-команды

```bash
cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"
swift build     # Build complete
swift test      # 331 tests in 47 suites — PASS
./script/build_and_run.sh   # ручной UI-прогон: Settings → API & Usage
```

- [x] `swift build` green
- [x] `swift test` green — **331 tests / 47 suites PASS** (0 failures)
- [x] Тесты не требуют сети/реальных ключей (моки `CloudHTTPFetcher`, fixtures)

---

## Поверхность 1 — Dropdown провайдеров (A3)

Источник правды: `Sources/VaniScriptCore/CloudProviderCatalog.swift` (A1).

- [x] Settings → «API & Usage» (`SettingsView.swift`, `apiKeysTab`) показывает dropdown
      провайдеров в фиксированном порядке каталога:
      `gemini, openai, anthropic, qwen, openrouter, ollama-cloud, custom`
- [x] Выбор провайдера открывает его карточку; порядок/набор задаётся только
      `CloudProviderCatalog.all` (единый источник правды)
- [x] Unit: `AppSettingsCloudFieldsTests` — порядок каталога, legacy decode → дефолты

## Поверхность 2 — Карточка провайдера: ключ, валидация, модели (A3/A4)

- [x] `cloudProviderCard` в `SettingsView.swift`: `ApiKeyInputRow` (ключ),
      `CloudKeyModelRow` (валидация ключа + выбор модели), budget slider
      (Qwen/OpenRouter), Base URL (Ollama Cloud), toggles
- [x] Валидация ключа — `Sources/VaniScriptCore/CloudKeyValidator.swift`
      (без сохранения/логирования ключа); списки моделей —
      `Sources/VaniScriptCore/CloudModelCatalog.swift` (`modelsEndpoint` из каталога)
- [x] Тумблер «Use for Transcribing» disabled + tooltip для qwen/openrouter/ollama-cloud
      (`capabilities.supportsTranscription == false` — честная индикация, §14.5)
- [x] Translation доступен при непустом ключе (`ProviderRegistry`, gating по ключу)
- [x] Unit: `ProviderRegistryCloudTests` (gating), `CloudProviderRoutingTests`
      (endpoints: Qwen DashScope `/compatible-mode/v1/chat/completions`,
      OpenRouter `/api/v1/chat/completions`, Ollama Cloud `{base}/v1/chat/completions`)

## Поверхность 3 — Запись usage (A2/A5)

- [x] `Sources/VaniScriptCore/UsageRecorder.swift`: агрегация по ключу
      `providerId:model`, `parseGeminiUsage` / `parseOpenAIUsage`, best-effort
      (сбой парсинга НЕ фейлит перевод/транскрипцию, §14.4)
- [x] `CloudTextTranslationEngine` / `CloudAudioTranscriptionEngine` возвращают
      `TokenUsage`; запись через существующий A2-путь покрывает и новые ids A5
      (engine ids = catalog ids, remap не нужен)
- [x] Ручной прогон: перевод через cloud-провайдера → карточка в статистике
      получает transactions/tokens (описание; без реального ключа — unit-моки)
- [x] Unit: `UsageRecorder`-тесты (агрегация, no-op без токенов, парсеры на fixtures)

## Поверхность 4 — Статистика UI (A6)

- [x] `Sources/VaniScript/Views/UsageStatisticsView.swift` (эталон Electron
      SettingsModal.tsx tab 7): Last Transaction Details (ISO-8601, бейдж
      `lastModel`), Summary активных провайдеров, per-model карточки
      (6 метрик: Prompt/Completion/Total tokens, Audio min, Estimated
      spent/remaining), Reset Statistics (`settings.usage = [:]`)
- [x] Дисклеймер EXACT: «Cost is an estimate based on locally counted text tokens;
      provider billing can differ.»
- [x] Пустое состояние: «No usage recorded yet.»
- [x] Данные только из `settings.usage` (A2/A5), UI-only — движки/registry не тронуты

## Поверхность 5 — Реальный баланс (A7)

- [x] `Sources/VaniScriptCore/CloudBalanceService.swift` (actor): `BalanceInfo` =
      `.usd` / `.planLimits` / `.unavailable`; TTL-кэш 60s; Refresh (`force`) обходит кэш
- [x] OpenRouter (`.openrouterCredits`): `GET /api/v1/credits` + `GET /api/v1/key`
      (Bearer), remaining = credits − usage, per-key cap `min(...)` →
      «$X remaining / $Y limit»
- [x] Ollama Cloud (`.ollamaPlan`): честная подпись «Plan-based (GPU time)», без фейковых «$»
- [x] Honesty guard: `.none`/`.estimated` (Gemini/OpenAI/Anthropic/Qwen/Custom) —
      БЕЗ сетевых запросов, `.unavailable` → UI показывает Estimated only (§14.6)
- [x] Ошибки сети/парсинга → тихий `.unavailable` (без крашей/алертов)
- [x] `CloudBalanceRow` в `SettingsView.swift` + `realBalanceSection` в
      `UsageStatisticsView.swift` — только для real-balance kinds при заданном ключе
- [x] Unit: suite `CloudBalanceService (A7)` — парсеры, per-key cap, no-fetch guard,
      quiet fallback (HTTP 401), TTL cache, force refresh (все на моках)

## Регрессия (не сломано)

- [x] AppSettings decode migration-safe (старые settings читаются; `decodeIfPresent`)
- [x] Codex/Grok/Qwen embedded chat, MCP server, WhisperKit/MLX не тронуты
- [x] QA A7: 133 PASS / 0 FAIL (19 a7-* scripts), bugs_open: 0

---

**ИТОГ: [PASS]** — все 5 поверхностей вкладки «API & Usage» реализованы (A1–A7)
и задокументированы; doc-only шаг A8 не меняет product-код. Smoke: `swift build`
green, `swift test` 331/47 green; инварианты §14 соблюдены.
