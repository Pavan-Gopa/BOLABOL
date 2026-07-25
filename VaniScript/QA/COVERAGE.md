# VaniScript QA Coverage Matrix

> Q6 QA cycle — 2026-07-25
> 62 scripts across 8 categories (A–H): 47 prior + 15 Q6 delta

## Coverage Map

| Area | Script | Asserts | New |
|------|--------|---------|:---:|
| **A. Build Gates** | | | |
| AS swift build | `build_gate_as.sh` | swift build exit 0 | ✅ |
| Electron tsc | `build_gate_electron.sh` | npm run compile exit 0 | ✅ |
| **B. MCP Server** | | | |
| AS SSE :19790 | `mcp_smoke_as.sh` | /sse, port 19790, tools/list, JSON-RPC | ✅ |
| Electron SSE :19789 | `mcp_smoke_electron.sh` | /sse, port 19789, /message, bridge | ✅ |
| AS token auth | `mcp_security_as.sh` | 401, Bearer, x-vaniscript-mcp-token, canStart | ✅ |
| Electron token auth | `mcp_security_electron.sh` | token check on /sse,/message (EXPECTED FAIL) | ✅ |
| Isolation/scopes | `mcp_isolation.sh` | vaniscript_embedded, McpPermissionSet, safe-mode | ✅ |
| Bridge token | `mcp_bridge_token.sh` | env var, settings fallback, header, port | ✅ |
| AS CORS/Origin | `mcp_cors_origin.sh` | isAllowedOrigin, nil-origin, loopback | ✅ |
| **C. Providers** | | | |
| Codex tests | `provider_codex_tests.sh` | CodexAgentSupportTests green | ✅ |
| Grok tests | `provider_grok_tests.sh` | GrokAgentSupportTests green | ✅ |
| Qwen tests | `provider_qwen_tests.sh` | QwenAgentSupportTests green | ✅ |
| Codex CLI flags | `provider_codex_flags.sh` | exec, --ephemeral, --json, --sandbox, MCP config | ✅ |
| Grok CLI flags | `provider_grok_flags.sh` | --prompt-file, --output-format, --reasoning-effort | ✅ |
| CLI absent errors | `provider_cli_absent.sh` | notInstalled errors, command -v lookup | ✅ |
| No fallback | `provider_no_fallback.sh` | no URLSession in agent services | ✅ |
| Error types | `provider_error_types.sh` | QwenAgentError 5 cases, Sendable | ✅ |
| **D. Settings/Routes** | | | |
| Settings decode | `settings_decode.sh` | UniversalSettingsTests, codex/grok/qwen fields | ✅ |
| Backward compat | `settings_backward_compat.sh` | decodeIfPresent, catalog defaults | ✅ |
| SettingsView | `settings_view_agents.sh` | agent refs, mcpServerEnabled, permissions | ✅ |
| Route selector | `routes_selector.sh` | ChatRoute, codex/grok/qwen guard, dispatch | ✅ |
| **E. Security** | | | |
| No tokens in argv | `security_no_tokens_argv.sh` | accessToken not in process.arguments | ✅ |
| Token env only | `security_token_env_only.sh` | token via environment, no file write | ✅ |
| Contract tests | `security_contract_tests.sh` | McpSecurityContractTests green | ✅ |
| Secrets snapshot | `security_secrets_snapshot.sh` | snapshot excludes secrets | ✅ |
| **F. Q2 Delta (Qwen)** | | | |
| NDJSON parser | `qwen_parser_ndjson.sh` | system/assistant/result, fallback chain | ✅ |
| Model catalog | `qwen_model_catalog.sh` | defaultModelID, normalizedModelID, displayLabel | ✅ |
| Safe mode | `qwen_safe_mode.sh` | --safe-mode, no --trust/--cwd, prompt | ✅ |
| No reasoning | `qwen_no_reasoning.sh` | no reasoningEffort, contrast Codex/Grok | ✅ |
| CLI flags | `qwen_cli_flags.sh` | -p, -o stream-json, -m | ✅ |
| Workspace | `qwen_workspace_isolation.sh` | QwenAgentWorkspace, 0o700 | ✅ |
| **G. Regression** | | | |
| Electron Grok | `electron_grok_embedded.sh` | vaniscript_embedded, port, no fallback | ✅ |
| Electron CORS | `electron_mcp_cors.sh` | CORS headers, wildcard warn, 127.0.0.1 | ✅ |
| Full swift test | `regression_swift_test.sh` | all 257 tests green | ✅ |
| Tool count | `regression_mcp_tools_count.sh` | >= 120 tools, key tools present | ✅ |
| Profiles | `regression_profiles.sh` | 7 profiles, setupText, default=codex | ✅ |
| Test count | `regression_test_count.sh` | >= 39 test files, key files exist | ✅ |
| **H. Q6 Delta (in-app API hardening)** | | | |
| Public API surface | `q6_streaming_api_surface.sh` | QwenStreamingProvider/Chunk/Error/Provider/HistoryItem public + Kind cases | ✅ |
| Error surface | `q6_error_cases.sh` | 5 cases (.cliMissing/.notLoggedIn/.mcpUnavailable/.cancelled/.upstream) + LocalizedError/Sendable/Equatable | ✅ |
| Cancel SIGTERM | `q6_cancel_sigterm.sh` | kill(-pid,SIGTERM)+terminate fallback, idempotent, isRunning guard | ✅ |
| No zombie | `q6_no_zombie.sh` | register-before-start ordering, proceed guard, activeProcess cleared x2 | ✅ |
| Async-safe lock | `q6_oslock_async_safe.sh` | OSAllocatedUnfairLock, no NSLock in code, import os, lock.withLock | ✅ |
| Streaming NDJSON | `q6_ndjson_parser.sh` | assistant.message.content[].text/tool_use -> .text/.toolUse/.done chunks | ✅ |
| Token env only | `q6_token_env_only.sh` | token never in argv, only via qwenEnvironment(accessToken:) | ✅ |
| No silent fallback | `q6_no_silent_fallback.sh` | .mcpUnavailable thrown, no URLSession, guard before spawn | ✅ |
| HistoryItem public | `q6_history_item_public.sh` | public in Core, duplicate removed from service, import VaniScriptCore | ✅ |
| Helpers internal | `q6_helpers_internal.sh` | service helpers internal (not private), Core helpers public | ✅ |
| Login detection | `q6_login_detection.sh` | stderr "login" hint -> .notLoggedIn, else .upstream(exit code) | ✅ |
| .done exactly once | `q6_done_exactly_once.sh` | single .done yield + finish(), finish(throwing:) on error | ✅ |
| No UI changes | `q6_no_ui_changes.sh` | ChatSidebarView/SettingsView/Views untouched; only 3 Q6 code files | ✅ |
| BUG-002 reword | `q6_bug002_electron.sh` | grep -ci electron MCP_INSTRUCTIONS.md == 0, "desktop web build" present | ✅ |
| Q6 test coverage | `q6_test_coverage.sh` | 6 Q6 @Test funcs present, QwenAgentSupportTests (13 tests) green | ✅ |

## Gap Hunt — Q6 (all items closed)

**Delta (Q6 in-app API):**
- Happy path streaming -> `q6_streaming_api_surface`, `q6_ndjson_parser`, `q6_done_exactly_once`
- Error / invalid / 4xx -> `q6_error_cases`, `q6_login_detection`
- Missing dependency / CLI absent (.cliMissing) -> `q6_error_cases`, `provider_cli_absent`
- Auth not-logged-in (.notLoggedIn, token env only) -> `q6_login_detection`, `q6_token_env_only`, `security_token_env_only`
- MCP integration (ephemeral config, token env, no silent fallback) -> `q6_no_silent_fallback`, `qwen_mcp_wiring`
- Isolation (vaniscript_embedded only) -> `mcp_isolation`, `qwen_workspace_isolation`
- Concurrency / cancel / idempotency (process-group kill, no zombie) -> `q6_cancel_sigterm`, `q6_no_zombie`, `q6_oslock_async_safe`
- Backward compat (Codex/Grok unchanged) -> `provider_codex_flags`, `provider_grok_flags`, `q6_no_ui_changes`

**Full regression:** build gates (AS+Electron), MCP SSE (:19790/:19789), tools, settings decode,
routes selector, no fallback, checkpoints, no tokens in argv/source — all covered by the 47 prior scripts (re-run green).

**Per-symbol aggression:** every new public Q6 symbol has a dedicated assert
(QwenStreamingProvider, QwenChatChunk{.text/.toolUse/.done}, QwenChatError x5, QwenChatProvider,
QwenChatHistoryItem, qwenExecutableURL/embeddedWorkspaceURL/writeIsolatedMcpConfig/qwenEnvironment/qwenChatPrompt).

**BUG-002 (prereq):** closed — `q6_bug002_electron.sh` asserts 0 "Electron" occurrences.

## Known Issues

1. **Electron MCP NO token auth** — `mcp_security_electron.sh` EXPECTED FAIL
   - AS :19790 requires token (401); Electron :19789 accepts any connection
   - Severity: Medium (loopback-only, but parity gap)
2. **Electron MCP CORS wildcard** — `electron_mcp_cors.sh` WARN
   - `Access-Control-Allow-Origin: *` vs AS loopback-only origin
   - Severity: Low (loopback-only)
