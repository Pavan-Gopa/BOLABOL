# Terminal MCP Server (Кастомный MCP-сервер для терминала и тестов)

Этот MCP-сервер (Model Context Protocol) предоставляет вашему AI-агенту (Claude Desktop, Cursor, Windsurf, ChatGPT, LibreChat и др.) полноценный доступ к терминалу для выполнения команд и запуска автотестов.

---

## 🚀 Возможности

1. **`execute_command`** — Выполнение любой консольной команды (bash/zsh/cmd) с поддержкой:
   - Задания рабочей директории (`cwd`).
   - Настройки таймаута выполнения (по умолчанию 120 сек, максимум 600 сек).
   - Передачи собственных переменных окружения (`env`).
   - Безопасного обрезания слишком длинного вывода (чтобы не перегружать контекст LLM).

2. **`run_tests`** — Специализированный инструмент для запуска тестов:
   - Автодетект тестовых фреймворков (**npm**, **pytest**, **swift test**, **cargo test**, **go test**, **make test**).
   - Фильтрация тестов по имени/файлу/маске (`test_filter`).
   - Понятная сводка вывода: статус (PASSED/FAILED), время выполнения, exit code, stdout/stderr.

3. **`get_terminal_info`** — Получение сведений о системе (ОС, CPU, память, установленные утилиты: Node, Python, Swift, Git, Cargo, Go и др.).

4. **`list_directory`** — Просмотр файлов в директории перед запуском команд.

5. **Два режима работы**:
   - **Stdio** (по умолчанию) — локальное подключение через stdin/stdout для десктоп-клиентов.
   - **SSE / HTTP** (`--port 3000`) — веб-сервер для подключения агентов по HTTP/SSE URL (`http://localhost:3000/sse`).

---

## 🛠 Сборка и Установка

### 1. Установка зависимостей и компиляция
```bash
cd "/Users/pavan/Documents/AI Projects/MCP-Terminal"
npm install
npm run build
```

Исполняемый файл находится по адресу:
```
/Users/pavan/Documents/AI Projects/MCP-Terminal/dist/index.js
```

---

## ⚙️ Как подключить MCP-сервер к вашему агенту

### Вариант 1: Claude Desktop
Отредактируйте конфиг Claude Desktop (`~/Library/Application Support/Claude/claude_desktop_config.json` на macOS):

```json
{
  "mcpServers": {
    "terminal": {
      "command": "node",
      "args": [
        "/Users/pavan/Documents/AI Projects/MCP-Terminal/dist/index.js"
      ]
    }
  }
}
```
*После сохранения перезапустите Claude Desktop.*

---

### Вариант 2: Cursor / Windsurf / VS Code (Continue)
В настройках MCP добавите новый сервер со следующими параметрами:
- **Name**: `terminal`
- **Type**: `command` (stdio)
- **Command**: `node`
- **Args**: `/Users/pavan/Documents/AI Projects/Bolabol/terminal-mcp-server/dist/index.js`

Или в файле `.mcp.json` / `mcp.json`:
```json
{
  "mcpServers": {
    "terminal": {
      "command": "node",
      "args": [
        "/Users/pavan/Documents/AI Projects/Bolabol/terminal-mcp-server/dist/index.js"
      ]
    }
  }
}
```

---

### Вариант 3: Удалённые агенты или веб-агенты через SSE (HTTP)
Если ваш агент подключается по URL (HTTP / Server-Sent Events):

Запустите сервер в режиме SSE:
```bash
node "/Users/pavan/Documents/AI Projects/Bolabol/terminal-mcp-server/dist/index.js" --port 3000
```

Укажите агенту URL подключения:
```
http://localhost:3000/sse
```

---

## 🧪 Пример взаимодействия с агентом

После подключения вы можете писать агенту прямо в чате:

- *"Запусти тесты проекта в текущей папке и скажи, всё ли прошло успешно."*
- *"Проверь статус git и запусти `npm test`."*
- *"Запусти pytest для файла `tests/test_auth.py` с таймаутом 60 секунд."*
- *"Узнай окружение системы через `get_terminal_info`."*

---

## 🔒 Безопасность
- Сервер выполняет команды от имени текущего пользователя в вашей локальной системе.
- Рекомендуется использовать только с доверенными AI-агентами.
