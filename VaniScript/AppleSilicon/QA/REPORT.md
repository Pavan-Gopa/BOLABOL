# QA REPORT — VaniScript (CLOUD_PROVIDER_STABILIZATION / CPS-01 + product fix)

- **Дата:** 2026-08-02
- **Трек/шаг:** `CLOUD_PROVIDER_STABILIZATION` / **CPS-01** (+ product remediation)
- **Suite:** **150** скриптов → **150 PASS / 0 FAIL** → **GREEN**
- **swift test:** **331 tests / 47 suites, 0 failures** (GREEN)
- **swift build --target VaniScript:** GREEN
- **Bugs open:** 0
- **Вердикт:** **GREEN**

---

## Прогоны

| Прогон | Результат |
|--------|-----------|
| Baseline (до fix) | 106 PASS / 27 FAIL |
| После CPS-скриптов + step-aware | 128 PASS / 22 FAIL |
| После product fix (этот) | **150 PASS / 0 FAIL** |

```bash
cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"
QA/run_all.sh
# PASS: 150   FAIL: 0
# RESULT: GREEN
```

---

## Product-фиксы (кратко)

1. **Disclaimer A6** — точная строка estimated cost в `UsageStatisticsView`
2. **Anthropic** — снова в `providerOrder` + `providers` + `anthropicCard` (key + ReadOnly model)
3. **Gemini/OpenAI** — titles ключей + budget sliders
4. **Статистика A6/A7** — Last Transaction Details, Transcribing/Translation summary, `usageCard`, remaining vs budget, `realBalanceSection`
5. **Qwen budget** + honesty toggles (`cloudProviderToggles`)
6. **CloudChatRouter** — `qwenDefaultChatCompletionsURL` + openrouter model fields
7. **keyFingerprint** — non-reversible hash (`Hasher` + `hashValue`)

Подробности: `QA/BUG_REPORT.md` (закрытые BUG-CPS-001…004).
