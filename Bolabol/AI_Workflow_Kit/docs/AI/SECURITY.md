# Security Engineer policy — Bolabol workflow

## Principle

Security review is **expensive** (tokens, time, depth). It is **not** part of every
coding step. Feature QA stays with **Tester** on every step; **Security Engineer**
is a **separate agent**, invoked **rarely** by Orchestrator (usually late train /
pre-release).

**Security finds and describes. Coder fixes product. Orchestrator routes.**  
Neither Security nor Tester patches `Sources/**` product code.

## Roles

| Role | Frequency | Owns |
|------|-----------|------|
| **Tester** | **Every** step after Reviewer APPROVED | Feature coverage, `swift test`, `run_all.sh`, gap-hunt tests, functional `BUG_REPORT.md` / `REPORT.md` |
| **Security Engineer** | **Periodic / final** only (Human or Orchestrator schedule) | Threat modeling, vuln hunt, `SECURITY_REPORT.md`, optional `check_sec_*.sh` / security unit tests |
| **Orchestrator** | Always | Decides when to kick Security; turns SEC-* into Coder fix kicks |
| **Coder** | On fix | Only role that patches product for SEC-* |
| **Reviewer** | Per step | May note smells; does not own security campaign |

## When to run Security (Orchestrator / Human)

Kick Security **only** when one of:

| Trigger | Example |
|---------|---------|
| Human asks | «security audit», «прогони security» |
| Pre-release / train close | Before S15 / release build / notarize |
| After large attack-surface change | First CDN download path, new OAuth, new worker IPC, secrets storage redesign |
| STATE flag | `security.next_run: pending` set by Orchestrator |

**Do not** attach full Security to every Tester kick.  
Cheap existing gates (`check_no_secrets.sh` via `run_all.sh`) stay on the normal Tester path as **baseline hygiene**, not a full audit.

## Security Engineer duties (when kicked)

1. Graphify + scoped read of attack surfaces (network, keys, downloads, paths, workers).  
2. Run baseline + deeper probes; add `script/qa/check_sec_*.sh` / tests if useful as **guards**.  
3. Fill `SECURITY_REPORT.md` (`security_clean` | `findings_open`).  
4. Hand off to Orchestrator only — no Coder prompts, no product patches.

Threat areas (full pass when kicked): downloads/CDN integrity & path traversal; API key storage/redaction; network host validation; subprocess/worker injection; sensitive file I/O; privacy entitlements notes.

## Severity → workflow (after Security handoff)

| Severity | Orchestrator |
|----------|----------------|
| **critical / high** | Coder fix kick before release/next major POST; then Reviewer → Tester (feature re-gate); optional Security re-pass if Human wants |
| **medium** | Coder fix or Human accepts residual risk |
| **low / info** | Note / backlog |

## Forbidden

- Merging Security into every Tester turn  
- Security or Tester editing `Sources/**` to “fix” findings  
- Live secrets in reports  
- Weaponized exploit PoCs beyond minimal local assert  

## Assets

- Policy: this file  
- Kick: `KICK_SECURITY.md`  
- Report: `SECURITY_REPORT.md`  
- Baseline QA (Tester every step via run_all): `script/qa/check_no_secrets.sh`  
