# QA REPORT — green

**Step:** Q6 — In-app API hardening (streaming / cancel / errors + tests)
**Date:** 2026-07-25
**Verdict:** 🟢 GREEN — run_all PASS (62 PASS / 0 FAIL / 0 SKIP)

## Scripts this run: 62 (15 new)

New Q6 delta scripts (category H-q6delta):
1. `q6_streaming_api_surface.sh` — 5 public types (QwenStreamingProvider/QwenChatChunk/QwenChatError/QwenChatProvider/QwenChatHistoryItem) + Kind cases .text/.toolUse/.done
2. `q6_error_cases.sh` — 5 error cases (.cliMissing/.notLoggedIn/.mcpUnavailable/.cancelled/.upstream) + LocalizedError/Sendable/Equatable
3. `q6_cancel_sigterm.sh` — kill(-pid, SIGTERM) + process.terminate() fallback, idempotent cancel, isRunning guard
4. `q6_no_zombie.sh` — register-before-start ordering (reg line 431 < run line 481), proceed guard, activeProcess cleared x2
5. `q6_oslock_async_safe.sh` — OSAllocatedUnfairLock used, no NSLock in code, import os, lock.withLock
6. `q6_ndjson_parser.sh` — streaming assistant.message.content[].text/tool_use -> .text/.toolUse/.done chunks
7. `q6_token_env_only.sh` — token never in argv ([-p,-o stream-json,-m] only), only via qwenEnvironment(accessToken:)
8. `q6_no_silent_fallback.sh` — .mcpUnavailable thrown on !canStart, no URLSession, guard before spawn
9. `q6_history_item_public.sh` — QwenChatHistoryItem public in VaniScriptCore, duplicate removed from QwenAgentService
10. `q6_helpers_internal.sh` — service helpers internal (not private), Core helpers public free functions
11. `q6_login_detection.sh` — stderr "login" hint -> .notLoggedIn, else .upstream(exit code)
12. `q6_done_exactly_once.sh` — single .done yield + finish(), finish(throwing:) on error
13. `q6_no_ui_changes.sh` — ChatSidebarView/SettingsView/Views untouched; only 3 Q6 code files modified
14. `q6_bug002_electron.sh` — grep -ci electron MCP_INSTRUCTIONS.md == 0, reworded to "desktop web build"
15. `q6_test_coverage.sh` — 6 Q6 @Test funcs present, QwenAgentSupportTests (13 tests) green

Plus all 47 prior scripts re-run green (full regression, not compressed).

## Gap hunt: closed (see QA/COVERAGE.md)

All checklist items covered: happy path, error/invalid, .cliMissing, .notLoggedIn + token-env-only,
MCP integration (ephemeral config / no silent fallback), isolation (vaniscript_embedded),
concurrency/cancel/idempotency (process-group kill, no zombie, async-safe lock),
backward compat (Codex/Grok unchanged, no UI changes). Per-symbol aggression: every new public
Q6 symbol has a dedicated assert.

## run_all: PASS

- Build gate AS: swift build OK; swift test = **267 tests / 40 suites / 0 failures**
- Build gate Electron: `tsc --noEmit` OK
- App Store native compliance suite: green (BUG-002 fix confirmed at test level)
- MCP SSE: AS :19790, Electron :19789 — up
- Settings decode / routes selector / security / isolation: green
- BUG-002 (prereq): verified fixed — 0 "Electron" occurrences in AS MCP_INSTRUCTIONS.md

## Bugs found this run: 0

No new bugs detected. BUG-002 (the only open bug) is verified fixed by `q6_bug002_electron.sh`
and by the green AppStoreNativeComplianceTests suite.

## Observations (non-blocking, informational only)

- `QwenStreamingProvider.send()` yields `.done(QwenAgentRun())` with an *empty* run on normal
  completion (incremental text is already streamed via `.text` chunks). This satisfies the
  documented invariant (".done exactly once") and all unit tests; flagged only as a possible
  future ergonomics improvement, NOT a defect.

## Next: зови оркестратора

QA green — orchestrator required to close Q6 and advance the QWEN_MCP track.
