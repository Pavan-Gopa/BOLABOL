# VaniScript QA Bug Report

> Generated: 2026-07-25 20:54
> Suite: 37 scripts | 36 PASS | 1 FAIL | 0 SKIP
> Swift tests: 257/257 green (39 suites)
> Build gates: AS ✅ | Electron ✅

---

## BUG-001: Electron MCP Server Has No Token Authentication

**Severity:** Medium
**Category:** Security
**Script:** `QA/scripts/mcp_security_electron.sh`
**Component:** `Electron/electron/main.js` → `startMcpServer()`

### Description

The Electron MCP server at `:19789` accepts **any** SSE connection and JSON-RPC
message without verifying an access token. The Apple Silicon MCP server at `:19790`
requires a valid token via `Authorization: Bearer <token>` or
`x-vaniscript-mcp-token` header, returning **401 Unauthorized** on missing/invalid
token.

### Evidence

**AS server (McpServer.swift:282-284):**
```swift
if request.path == "/sse" {
    // ... returns 401 Unauthorized if not isAuthorized
}
```

**Electron server (main.js:3033-3044):**
```javascript
if (pathname === '/sse' && req.method === 'GET') {
    res.writeHead(200, { ... });  // No auth check!
    const sessionId = crypto.randomUUID();
    activeSseConnections.set(sessionId, res);
}
```

**Electron /message endpoint (main.js:3055+):**
```javascript
if (pathname === '/message' && req.method === 'POST') {
    // No auth check!
}
```

### Impact

- Any local process can connect to `:19789` and invoke MCP tools
- The `mcp_bridge.py` sends `x-vaniscript-mcp-token` header, but the server
  never validates it
- Parity gap with AS server which enforces token auth

### Mitigating Factors

- Server binds to `127.0.0.1` only (loopback)
- Not exposed to network

### Recommended Fix

Add token verification to both `/sse` and `/message` endpoints in
`startMcpServer()`, matching the AS `McpServerConfiguration.isAuthorized()` logic:
1. Read `VANISCRIPT_MCP_TOKEN` from env or `settings.json`
2. Check `Authorization: Bearer <token>` or `x-vaniscript-mcp-token` header
3. Return 401 on missing/invalid token

---

## WARN-001: Electron MCP CORS Wildcard

**Severity:** Low
**Script:** `QA/scripts/electron_mcp_cors.sh`

The Electron MCP server sets `Access-Control-Allow-Origin: *` while the AS server
restricts to loopback origins only. Low severity since server is loopback-only.

---

## BUG-002: Q5 doc added "Electron" to AS MCP_INSTRUCTIONS.md → App Store compliance test fails

**Severity:** Medium
**Category:** Compliance / Doc regression
**Script:** `QA/scripts/regression_swift_test.sh` → swift test `"MCP server is token gated and loopback only"`
**Component:** `AppleSilicon/MCP_INSTRUCTIONS.md` (introduced by Q5 commit `50ebb06`)
**Found:** 2026-07-26 (Q5 QA pass, 46/47 scripts green)

### Description

The Q5 doc-only commit `50ebb06` added an "External Qwen CLI" section to
`AppleSilicon/MCP_INSTRUCTIONS.md` that mentions the word **"Electron"** twice
(line 264 port note, line 283 tool-catalog note). This violates the App Store
native compliance invariant that the Apple Silicon app's MCP instructions must
not reference the Electron build.

### Evidence

**Compliance test (AppStoreNativeComplianceTests.swift:1339):**
```swift
#expect(!instructions.localizedCaseInsensitiveContains("Electron"))
```

**Offending lines added by Q5 (AppleSilicon/MCP_INSTRUCTIONS.md):**
```
264: > **Port note:** the example above uses `19789` (the Electron build). ...
283:   full 120-tool catalog; the Electron build exposes the same tools ...
```

**Git proof (count of "Electron", case-insensitive):**
```
git show 50ebb06^:.../AppleSilicon/MCP_INSTRUCTIONS.md | grep -ci electron  → 0
git show 50ebb06:.../AppleSilicon/MCP_INSTRUCTIONS.md  | grep -ci electron  → 2
```

**swift test result:** `Test run with 261 tests in 40 suites failed ... with 1 issue.`

### Impact

- `swift test` is RED → `regression_swift_test.sh` fails → `QA/run_all.sh` is RED.
- App Store compliance invariant broken for the native AS app documentation.

### Recommended Fix (product/doc — NOT a QA script change)

Reword the AS `MCP_INSTRUCTIONS.md` "External Qwen CLI" section to avoid the
literal token "Electron", e.g. reference "the other build / port 19789" without
naming Electron, and keep Electron-specific wording in `Electron/MCP_INSTRUCTIONS.md`
only. Then re-run `QA/run_all.sh` (expect 47/47 + swift test green).

---

## Summary

| # | Type | Severity | Script | Status |
|---|------|----------|--------|--------|
| BUG-001 | Electron MCP no token auth | Medium | mcp_security_electron.sh | OPEN |
| WARN-001 | Electron MCP CORS wildcard | Low | electron_mcp_cors.sh | NOTED |
| BUG-002 | Q5 doc "Electron" breaks AS compliance test | Medium | regression_swift_test.sh | OPEN |

**Зови оркестратора** — BUG-001 requires product-code fix in `Electron/electron/main.js`.
