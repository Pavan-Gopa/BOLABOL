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
*Комментарий:* ...

### 4. (если changes_requested) Конкретный список правок
1. ...
2. ...

---

**ИТОГОВЫЙ СТАТУС:** [APPROVED] или [CHANGES_REQUESTED]
