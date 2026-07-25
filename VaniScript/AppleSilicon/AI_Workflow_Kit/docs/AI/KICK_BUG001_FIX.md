# Kick: BUG-001 Fix — Electron MCP Token Auth + CORS Parity

> **Оркестратор:** Cline. **Тип:** Hotfix (QA BUG-001 + WARN-001).
> **Источник:** QA Full Cycle → BUG_REPORT.md
> **Working directory:** `cd "/Users/pavan/Documents/AI Projects/VaniScript/Electron"`

---

## System Prompt (вставь как роль / system prompt кодеру)

```
Ты — Implementation Engineer проекта VaniScript.

## Проект (кратко)
VaniScript — macOS (Swift 6 / SwiftUI, AppleSilicon/) + Electron (Electron/).
AI-провайдеры (Codex, Grok, Qwen) = CLI subprocess.
Локальный MCP server: AS :19790 (Swift), Electron :19789 (Node.js http).
Изолированный профиль `vaniscript_embedded`.

## Твоя роль
- Исправляешь BUG-001 и WARN-001 из QA BUG_REPORT.md.
- Пишешь ТОЛЬКО product-код в Electron/electron/main.js.
- НЕ трогаешь AppleSilicon/ код. НЕ трогаешь QA/ скрипты.
- Минимальный diff. Комментарии per TEAM_CONTRACT § Comments.

## Правила
- Токены: Graphify first (graphify explain --graph "$GRAPH")
  GRAPH="/Users/pavan/Documents/AI Projects/VaniScript/graphify-out/graph.json"
- После фикса: swift test (AS) + npm run compile (Electron) должны быть green.
- Коммит: fix(mcp): BUG-001 Electron MCP token auth + CORS parity
```
---

## Task (вставь как задание / user prompt кодеру)

```
## BUG-001 + WARN-001 Fix — Electron MCP Token Auth + CORS Parity

### Контекст
QA Full Cycle выявил 2 проблемы в Electron MCP server (Electron/electron/main.js):

**BUG-001 (Medium, Security):** Electron MCP server :19789 не проверяет токен
авторизации. AS server :19790 корректно возвращает 401 Unauthorized на запросы
без токена. Electron принимает любые подключения.

**WARN-001 (Low, Security):** Electron MCP server ставит
`Access-Control-Allow-Origin: *` вместо loopback-only origins (как AS).

### Референс: AS auth логика (McpContracts.swift:1148-1163)

AS проверяет авторизацию так:
- Нормализует headers (lowercase keys, trim values)
- Проверяет `Authorization: Bearer <token>` (case-insensitive prefix)
- Проверяет `x-vaniscript-mcp-token: <token>` (exact match)
- Возвращает false если accessToken пуст или не совпадает

AS генерирует токен: crypto random hex при старте сервера.

AS CORS:
- No Origin header → allow (native MCP client)
- Origin present → только loopback (127.0.0.1, ::1, localhost)

### Что исправить в Electron/electron/main.js

#### 1. Module-level переменная (перед startMcpServer)
```javascript
let mcpAccessToken = '';
```

#### 2. В startMcpServer() — генерация токена (в самом начале функции)
```javascript
mcpAccessToken = crypto.randomBytes(32).toString('hex');
log.info('MCP access token generated for this session');
```

#### 3. Auth helper (рядом со startMcpServer)
```javascript
function isMcpAuthorized(req) {
  if (!mcpAccessToken) return false;
  const auth = (req.headers['authorization'] || '').trim();
  if (auth.toLowerCase().startsWith('bearer ') &&
      auth.slice(7).trim() === mcpAccessToken) {
    return true;
  }
  const customHeader = (req.headers['x-vaniscript-mcp-token'] || '').trim();
  if (customHeader === mcpAccessToken) return true;
  return false;
}

function isLoopbackOrigin(origin) {
  try {
    const u = new URL(origin);
    const h = u.hostname.replace(/^\[|\]$/g, '').toLowerCase();
    return h === '127.0.0.1' || h === '::1' || h === 'localhost';
  } catch { return false; }
}
```

#### 4. CORS fix (замени строку ~3022)
Замени `res.setHeader('Access-Control-Allow-Origin', '*');` на:
```javascript
const origin = (req.headers['origin'] || '').trim();
if (!origin || isLoopbackOrigin(origin)) {
  res.setHeader('Access-Control-Allow-Origin', origin || '*');
} else {
  res.setHeader('Access-Control-Allow-Origin', 'http://127.0.0.1');
}
res.setHeader('Access-Control-Allow-Headers',
  'Content-Type, Authorization, x-vaniscript-mcp-token');
```

#### 5. Auth gate на /sse (ПЕРЕД res.writeHead(200, ...) на строке ~3033)
```javascript
if (!isMcpAuthorized(req)) {
  res.writeHead(401, { 'Content-Type': 'text/plain' });
  res.end('Unauthorized');
  return;
}
```

#### 6. Auth gate на /message (ПЕРЕД обработкой body на строке ~3055)
```javascript
if (!isMcpAuthorized(req)) {
  res.writeHead(401, { 'Content-Type': 'text/plain' });
  res.end('Unauthorized');
  return;
}
```

#### 7. Grok config — auth header (writeGrokProjectConfig ~3320)
В config template добавь headers строку:
```javascript
headers = { "x-vaniscript-mcp-token" = "${mcpAccessToken}" }
```

#### 8. Grok subprocess env (~3401)
В env объекта spawn добавь:
```javascript
VANISCRIPT_MCP_TOKEN: mcpAccessToken,
```

### Файлы для изменения
- `Electron/electron/main.js` — ЕДИНСТВЕННЫЙ файл

### НЕ трогать
- AppleSilicon/ — любой файл
- QA/ — любой файл
- Electron/src/ — любой файл

### Верификация
1. `cd "/Users/pavan/Documents/AI Projects/VaniScript/Electron" && npm run compile` — green
2. `cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon" && swift test` — green
3. QA скрипт `mcp_security_electron.sh` должен стать PASS
4. QA скрипт `electron_mcp_cors.sh` должен стать PASS или WARN cleared

### Коммит
```
fix(mcp): BUG-001 Electron MCP token auth + CORS parity

- Generate mcpAccessToken (crypto.randomBytes) at server start
- isMcpAuthorized() checks Bearer + x-vaniscript-mcp-token headers
- 401 on /sse and /message without valid token
- CORS: loopback-only origins (match AS isAllowedOrigin)
- Grok config: pass token via headers in config.toml
- Grok subprocess: VANISCRIPT_MCP_TOKEN in env

Matches AS McpServerConfiguration.isAuthorized() logic.
Closes BUG-001 + WARN-001 from QA Full Cycle.
```

### Сдача
1. Исправь код
2. Прогони верификацию
3. Коммит с сообщением выше
4. Скажи: «BUG-001 fixed — зови оркестратора»
```

---

Токены: Graphify first — MCP server "graphify" tools, или CLI:
graphify query|explain|path --graph "/Users/pavan/Documents/AI Projects/VaniScript/graphify-out/graph.json"
Skill: VaniScript/.agents/skills/graphify/SKILL.md. Не дампить дерево без graphify.
