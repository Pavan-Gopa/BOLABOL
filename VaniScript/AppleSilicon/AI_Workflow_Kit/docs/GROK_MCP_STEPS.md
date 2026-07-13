# GROK_MCP — step cards

> **Track:** `GROK_MCP`  
> **Roles:** Grok orchestrator · Hy3 implementer · Gemini 3.5 Flash reviewer  
> **Git:** `grok/pre-Gn` before Hy3; `grok/Gn-done` after Gemini APPROVED + orchestrator post  

G0 (kit bootstrap) is orchestrator-only and is already done when this file exists.

## Overview

| Step | Name |
|------|------|
| **G1** | External Grok MCP profile (Apple Silicon) |
| **G2** | Grok agent support + output parser + tests |
| **G3** | GrokAgentService (AS embedded CLI) |
| **G4** | Chat multi-agent (AS): Grok \| Codex |
| **G5** | Electron Grok (functional; no UI redesign) |
| **G6** | Acceptance smoke → GROK_DONE |

---

## G1 — External Grok MCP profile (AS)

### Цель
Добавить Grok как **внешний** MCP-клиент рядом с Codex/Claude/Cursor/Antigravity.

### Требования
1. `McpClientProfileID.grok` + `displayName` "Grok" + `symbolName`.
2. `McpAgentProfileCatalog.setupText` для Grok:
   - stdio bridge: `grok mcp add vaniscript --transport stdio -- python3 "<bridge>"` (или эквивалент по CLI);
   - SSE/HTTP: endpoint `http://127.0.0.1:19790/sse` + `Authorization: Bearer <token>` via `-H`.
3. `McpClientClassifier`: client/user-agent containing `grok` → profile `grok`.
4. Settings → Agents: профиль в списке, Copy Setup работает (если UI итерирует `McpAgentProfileCatalog.all` — проверить switch exhaustiveness).
5. `MCP_INSTRUCTIONS.md` (AppleSilicon): секция **Grok**.
6. Onboarding copy: упомянуть Grok среди trusted clients (`OnboardingTourState.swift`), если список явный.
7. Тесты: classifier + setupText/normalized ID, если есть соседние тесты для Codex/profiles.

### Не делать
- GrokAgentService / embedded chat
- ChatSidebar multi-agent
- Electron product code
- UI density / VisualClipEditor redesign

### target_files
- `Sources/VaniScriptCore/McpContracts.swift`
- `Sources/VaniScript/Views/SettingsView.swift` (только если нужен exhaustiveness / UI не из catalog)
- `Sources/VaniScript/Models/OnboardingTourState.swift`
- `MCP_INSTRUCTIONS.md`
- `Tests/VaniScriptCoreTests/McpSecurityContractTests.swift` (или NEW profile tests рядом с существующими)

### Done
- Profile visible + setup copy correct; `swift test` / `swift build` green; no G2+ code

---

## G2 — Grok agent support + parser + tests

### Цель
Парсер/каталог моделей Grok (зеркало `CodexAgentSupport`), без launch process.

### Требования
1. NEW `Sources/VaniScriptCore/GrokAgentSupport.swift`:
   - `GrokChatModelCatalog` (как минимум `grok-4.5`, optional fast/composer ids from `grok models`);
   - `GrokAgentRun` + `GrokAgentOutputParser` for headless `--output-format streaming-json` / `json` (fixture-based; capture real schema if needed).
2. Normalize model id / display label helpers.
3. Unit tests mirror `CodexAgentSupportTests`.

### Не делать
- Process launch / ChatSidebar / Settings UI wiring (G3–G4)
- Electron

### target_files
- `Sources/VaniScriptCore/GrokAgentSupport.swift` (NEW)
- `Tests/VaniScriptCoreTests/GrokAgentSupportTests.swift` (NEW)
- optional fixture under `Tests/…` if needed

### Done
- Parser tests pass; catalog normalize covered

---

## G3 — GrokAgentService (AS embedded)

### Цель
Headless Grok CLI → isolated MCP `vaniscript_embedded` → chat response (зеркало `CodexAgentService`).

### Требования
1. NEW `Sources/VaniScript/Services/GrokAgentService.swift`.
2. Resolve executable: `~/.grok/bin/grok`, `/usr/local/bin/grok`, `/opt/homebrew/bin/grok`, PATH.
3. Isolated workspace dir + project MCP config **only** `vaniscript_embedded` (no user global MCP inheritance).
4. Token only in child env (`VANISCRIPT_MCP_TOKEN` or equivalent).
5. System prompt aligned with Codex embedded rules (help tools, confirmation, language).
6. Errors: MCP off, CLI missing, not logged in — clear; **no** Gemini fallback.
7. Model/effort from settings fields introduced here or in G4 — prefer introduce settings fields in G4 if Chat needs them; G3 may accept `AppSettings` stubs.

### Не делать
- ChatSidebar UI switch (G4)
- Electron
- UI redesign

### target_files
- `Sources/VaniScript/Services/GrokAgentService.swift` (NEW)
- `Sources/VaniScriptCore/AppSettings.swift` (only if required for model IDs used by service)
- related tests if pure helpers extracted to Core

### Done
- Service callable; isolation documented in code comments; builds

---

## G4 — Chat multi-agent (AS)

### Цель
MCP chat route works for **Codex and Grok** based on preferred agent.

### Требования
1. Remove hard gate `mcpPreferredAgentID == codex` only; allow `grok`.
2. Model menu for Grok when agent is Grok.
3. Settings persistence: `grokChatModelID` (+ effort if applicable).
4. Help text: MCP route powered by active agent (Codex **or** Grok).
5. Codex path still works unchanged.
6. No silent API fallback.

### target_files
- `Sources/VaniScript/Views/ChatSidebarView.swift`
- `Sources/VaniScriptCore/AppSettings.swift`
- `Sources/VaniScript/Views/SettingsView.swift` (if needed)
- tests for settings decode defaults if pattern exists

### Done
- Both agents selectable; smoke logic correct

---

## G5 — Electron Grok (functional)

### Цель
Electron: docs + embedded/headless Grok MCP path; **no visual redesign**.

### Требования
1. `Electron/MCP_INSTRUCTIONS.md` — Grok section (port **19789**).
2. Chat: MCP | API routes if missing; MCP + Grok uses CLI headless via main process IPC.
3. Wire tools through existing MCP IPC (`onMcpCallTool` / `executeMcpTool`).
4. API route remains Gemini when selected; no silent fallback.
5. Minimal UI chrome only for route/agent — no density redesign.

### working_root
- `VaniScript/Electron/` (nested git may apply)

### target_files
- `Electron/MCP_INSTRUCTIONS.md`
- `Electron/electron/main.js`
- `Electron/electron/preload.js`
- `Electron/src/components/ChatSidebar.tsx`
- `Electron/src/App.tsx` / `types.ts` as needed

### Done
- Functional smoke documented; Electron tests for new helpers if any

---

## G6 — Acceptance smoke

### Цель
Checklist + docs polish; mark GROK_DONE.

### Требования
1. Short acceptance checklist in `AI_Workflow_Kit/docs/DECISIONS.md` or `GROK_MCP_ACCEPTANCE.md` (NEW if needed).
2. Manual smoke items listed for human: external `grok mcp`, embedded chat AS, Electron path.
3. No new product features.

### target_files
- `AI_Workflow_Kit/docs/DECISIONS.md` and/or NEW acceptance note
- minor doc fixes in MCP_INSTRUCTIONS if gaps found

### Done
- Checklist complete → orchestrator sets GROK_DONE

---

## GROK_DONE

Open track **UI_AS** only after human confirms / orchestrator advances.
