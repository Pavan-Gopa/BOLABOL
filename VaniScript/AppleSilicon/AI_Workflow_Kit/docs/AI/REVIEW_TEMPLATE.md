# Шаблон проверки (Verification Template)

Verification Engineer (**Gemini 3.5 Flash**) заполняет эту структуру в `FEEDBACK.md` на каждый review.

Проверяемый шаг: смотри `STATE.yaml` → `current_step`  
Требования шага: `GROK_MCP_STEPS.md` или `UI_AS_STEPS.md` (тот же шаг)

---

### 1. Сборка и интеграция
- Собирается / тестируется ли проект после этих изменений? (Да/Нет/Не применимо)
- Не нарушают ли изменения Codex path, MCP server, settings decode?
*Комментарий:* ...

### 2. Логика и соответствие плану
- Выполнены ли все требования **текущего** шага?
- Нет ли самодеятельности (код из G(n+1)/U(n+1) на шаге G(n)/U(n))?
- Соблюдены ли `target_files`?
*Комментарий:* ...

### 3. Безопасность и контракты
- Нет ли хардкода MCP token / API keys?
- Нет ли silent fallback MCP chat → API?
- Isolated MCP / scopes не ослаблены без требования шага?
- (QWEN_MCP) Token только в env дочернего процесса? Codex/Grok/MCP server/settings не сломаны?
*Комментарий:* ...

### 4. Комментарии и читаемость (TEAM_CONTRACT § Comments)
- Новые модули/типы имеют короткий role header (слой, что владеет, must-not)?
- Non-obvious logic объяснена ПОЧЕМУ (не пересказ кода)?
- Async/cancel/ownership notes где релевантно?
- Нет шумных/устаревших комментариев?
*Комментарий:* ...
*(Отсутствие essential comments на новом нетривиальном коде = CHANGES_REQUESTED.)*

### 5. (если changes_requested) Конкретный список правок
1. ...
2. ...

---

**ИТОГОВЫЙ СТАТУС:** [APPROVED] или [CHANGES_REQUESTED]
