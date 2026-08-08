# Campaign — FINAL-APPLICATION-EXHAUSTIVE-MAX-PLUS-SECURITY-SURFACE (Tester-authorized)

**Date:** 2026-08-08
**Actor:** Tester with Human-granted security-surface authority (folded into MAX QA campaign per SECURITY.md exception)
**Scope:** secrets, path traversal / model-path trust, download destinations, URLSession surface, prompt/filename injection, PolishWorker IPC, keychain storage, entitlements/codesign (verify-only), PII logging, Python runtime, endpoint allowlist
**RESULT: `findings_open`** — SEC-001…004 closed by Coder Fix Attempt 8; SEC-005 remains deferred (0 critical · 0 high · 0 open medium/low · 1 info)

## Findings

| # | Severity | Finding | Evidence (suspect file:line) | Fix direction for Coder |
|---|----------|---------|------------------------------|-------------------------|
| SEC-001 | **medium** | Remote HuggingFace tree paths are used unsanitized as local destination components. `item.path` / `entry.path` from the HF tree API flow into `destination.appendingPathComponent(...)` with no `..`/absolute-path rejection. A compromised repo API or TLS MITM could write files outside the model folder. The Bolabol CDN seam is already hardened (`isSafeManifestFile`), the two HF seams are not. | `Sources/NativeBolabol/Stores/TranscriptionModelStore.swift:615,629` (`downloadHuggingFaceModel`); `Sources/NativeBolabol/Stores/PolishingEngineStore.swift:548,562` (`downloadSnapshotDirectly`) | Apply the same predicate as `isSafeManifestFile`: reject empty paths, leading `/`, and any `..` component before `appendingPathComponent`; refuse the download on violation. |
| SEC-002 | **medium** | `SharedModelsRoot.location(for:)` resolves symlinks via `resolvingSymlinksInPath()`, which only resolves paths that physically exist. A not-yet-existing path through a symlink inside the models root passes the textual prefix check and resolves to a location. Verified empirically (probe script). Impact limited: `location(for:)` feeds installation-state labeling, not delete decisions — but the documented "symlink-safe" invariant does not hold for missing tails. | `Sources/NativeBolabolCore/Services/SharedModelsRoot.swift:119-123` | After the prefix check, additionally reject any path component that is a symlink (`FileManager.attributesOfItem` / `realpath` walk on the existing prefix), or document the existing-path precondition in the contract. |
| SEC-003 | **low** | Polishing model download patterns include `*.py`, so remote Python artifacts are fetched into the model cache. They are never executed by the product (MLX loads weights/config), but this conflicts with the project's no-Python-in-product posture and widens the blast radius of a repo compromise. | `Sources/NativeBolabol/Stores/PolishingEngineStore.swift:896-903` (`mlxModelDownloadPatterns`) | Drop `*.py` from the pattern list unless a concrete MLX runtime need is demonstrated. |
| SEC-004 | **low** | The polishing prompt wrapper uses literal `<transcription>` delimiters; user dictation containing `</transcription>` can close the wrapper early (classic delimiter escape). The immutable editor system contract and execution reminder still apply, so this is defense-in-depth, not a live break. | `Sources/NativeBolabolCore/Services/PolishingRequestPolicy.swift:42-49` | Escape/neutralise the delimiter sequence in user text (e.g. insert a zero-width joiner or use a per-request random delimiter) before wrapping. |
| SEC-005 | **info** | `BOLABOL_CDN_BASE_URL` env override redirects Canary 1B package downloads to an arbitrary host. Documented test hook; env control implies local privilege, and the manifest SHA contract still applies — but against an attacker-controlled host the manifest is self-attesting. | `Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift:292-298` | Keep for dev/test; consider restricting to `localhost`/`file:` schemes in release builds or logging a loud warning when set. |

## Coder Fix Attempt 8 Status

**Status:** SEC-001, SEC-002, SEC-003, and SEC-004 are closed. SEC-005 remains deferred and the overall report is not `security_clean`.

- **SEC-001 closed:** `ModelDownloadPathPolicy` mirrors `isSafeManifestFile` and rejects empty, absolute, dot-dot, and empty path components. Both Hugging Face tree seams preflight every remote entry before creating a destination, re-check immediately before `appendingPathComponent`, and throw typed unsafe-path errors. The regression test injects `../escaped.bin`, confirms one metadata request, failed state, typed error text, and no destination write.
- **SEC-002 closed:** `SharedModelsRoot.location(for:)` now walks existing components with `destinationOfSymbolicLink`, resolves each target, and rejects escapes before parsing the location. The missing-tail symlink regression covers an escaping directory link followed by a non-existent model path.
- **SEC-003 closed:** `*.py` was removed from `mlxModelDownloadPatterns`; the regression test pins its absence.
- **SEC-004 closed:** wrapped transcription content neutralizes `</transcription>` with a zero-width joiner while preserving the immutable editor system contract. The regression test verifies the literal closing delimiter cannot appear inside the wrapped user payload.
- **Guard evidence:** `check_sec_download_path_safety.sh` and `--self-test` pass; the self-test mutates each SEC-001…004 seam and fails closed.

### Tester retest confirmation (2026-08-09, SEC-FIX-ATTEMPT-8-RETEST-PLUS-FULL-GATE)

**SEC-001, SEC-002, SEC-003, SEC-004 confirmed CLOSED on independent Tester retest.** Reviewer-approved Coder Fix Attempt 8 re-verified under the full gate: `SecuritySurfaceRegressionTests` 21/21, `swift test` 745/745 (32 suites), `run_all.sh` 39/39, `check_sec_download_path_safety.sh` + `--self-test` green (all SEC-001…004 negative mutations fail closed), all 9 `check_sec_*.sh --self-test` green. No gap found; no new tests required. **SEC-005 remains deferred (info) and does not block POST.** Overall status stays `findings_open`-to-`security_clean-pending-SEC-005-decision`; this retest does not claim global `security_clean`.

## Clean surfaces (verified)

| Area | Result | Evidence |
|------|--------|----------|
| Secrets in Sources/Tests/script/docs/scratch | clean | `check_no_secrets.sh`, `check_sec_no_secrets_extended.sh` |
| Python in product Sources | clean | `check_no_python_in_sources.sh` (root `__pycache__/` is historical spike tooling, not shipped; noted) |
| Download code review gate | clean | `check_sec_no_download_code.sh` + new `check_sec_download_path_safety.sh` |
| CDN package integrity | clean | SHA-256 manifest verify, traversal predicate, `check_sec_s4b_package_integrity.sh` (19/19 files) |
| Subprocess launches | clean | allowlisted `/usr/bin/curl|log|afplay` + bundle worker; argument arrays/stdin only; no shell; new `check_sec_process_launch.sh` |
| Worker IPC | clean | stdin-only typed JSON; no argv trust; bundle-resolved binary; hostile-payload round-trip tests; new `check_sec_worker_ipc.sh` |
| Keychain | clean | generic passwords, `AfterFirstUnlockThisDeviceOnly`, no UserDefaults secrets, no file writes; new `check_sec_keychain_defaults.sh` |
| Network endpoints | clean | 100% HTTPS, all hosts on reviewed allowlist; new `check_sec_url_endpoints.sh` |
| PII in logs | clean | log statements interpolate lengths/IDs only; no raw text/keys; no print/NSLog; new `check_sec_no_pii_in_logs.sh` |
| Prompt injection | guarded | immutable editor contract outranks transcription; hostile-input matrix green; SEC-004 delimiter neutralized in Coder Fix Attempt 8 |
| Entitlements/codesign | verify-only | `audio-input` + `apple-events`, no sandbox (required for global hotkey/AX dictation — accepted product posture); `codesign --verify --deep --strict dist/Bolabol.app` OK (Orchestrator status build PID 3369) |
| Sanitizer reasoning leaks | clean | `<think>` dumps never reach notes verbatim; empty-output fails loudly in worker |

## Guards added this campaign (all fail-closed, `--self-test`, wired into run_all.sh)

`check_sec_download_path_safety.sh`, `check_sec_no_pii_in_logs.sh`, `check_sec_process_launch.sh`, `check_sec_url_endpoints.sh`, `check_sec_keychain_defaults.sh`, `check_sec_worker_ipc.sh` — plus 21 Swift security regression tests in `Tests/NativeBolabolCoreTests/SecuritySurfaceRegressionTests.swift`.

## Verification commands run

```bash
swift test                                   # 740 tests PASS
swift test --sanitize=thread                 # 740 tests PASS, no races
./script/qa/run_all.sh                       # 39/39 PASS
./script/qa/check_no_secrets.sh              # PASS
./script/qa/check_no_python_in_sources.sh    # PASS
for s in script/qa/check_sec_*.sh; do bash "$s" --self-test; done   # all PASS
```

No weaponized exploits, no live secrets, no paid calls, no UserData mutation. Findings SEC-001…SEC-005 are descriptive; Coder fix kicks remain the Orchestrator's decision.

---

# SECURITY REPORT — Bolabol

> **Owner (policy from 2026-08-04):** **Security Engineer** only (`KICK_SECURITY.md`).  
> Not part of every Tester turn. Orchestrator schedules Security rarely (pre-release / Human).  
> Findings → Orchestrator → Coder fix kicks. **No product patches by Security/Tester.**

---

# Campaign note — S4b interim (historical)

**Date:** 2026-08-04  
**Actor:** interim combined QA+Security pass (policy later split — do not repeat every step)  
**Scope:** S4b (bolabol-canary-1b-v2-coreml-r1)  
**Status:** **findings_open** (3 low/medium gaps — treat as backlog until formal Security campaign or Coder fix)

---

## 1. Baseline checks

### 1.1 check_no_secrets.sh ✅ (green)
- Scanned: `Sources/`, `Tests/`, `script/`, `Package.swift`
- Result: **no secrets detected** in these directories.
- **Note:** This baseline script does **not** scan `docs/`, `scratch/`, `AI_Workflow_Kit/docs/`. Extended scan performed manually (see §2.1).

### 1.2 check_no_canary_product.sh ✅ (green)
- `Package.swift`: no "canary" occurrences.
- `Sources/` and `Tests/`: "canary" found only in allowed locations:
  - `Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift` — ModelSpec IDs (spec definitions, no product integration).
  - `Sources/NativeBolabolCore/Services/AppText.swift` — `helpBilingualCanary` key (help guide only).
- **Product Sources remain Canary-production-free.**

### 1.3 check_b6_canary_spike.sh ✅ (green)
- All spike reports present with correct verdicts (B6 NO-GO, S4 NO-GO, S5 GO).
- All harness files exist and contain no Python.
- S4 NO-GO + S5 GO + S6 dual-checks intact.

### 1.4 check_s4b_canary_fix.sh ✅ (green, with caveat)
- All feature checks pass (SPIKE.md, harness, package layout, preprocessor absence, product boundary).
- **Caveat:** `VERIFY_S4B_PACKAGE=1` (SHA integrity check) is OFF by default. See §3 Finding F2.

---

## 2. Step-scoped security checks

### 2.1 Model package paths ✅
- Package location: `scratch/canary-1b-fix/package/bolabol-canary-1b-v2-coreml-r1/`
- **No path traversal risk:** no install helpers in `script/qa/` accept user-supplied paths. `check_s4b_canary_fix.sh` hardcodes `PACKAGE_ROOT`.
- **No secret in package:** inspected `FRONTEND.md`, `LICENSE.txt`, `metadata.json`, `MANIFEST.json` — no API keys, tokens, or passwords.
- **No secret in docs:** inspected `docs/canary/COREML_SPIKE.md`, `docs/asr/canary-1b/COREML_SPIKE.md`, `docs/asr/canary-flash/COREML_SPIKE.md`, `docs/canary/harness/CanarySpike.swift`, `docs/canary/harness/CanaryFluidSpike.swift`, `docs/canary/harness/CanaryFlashSpike.swift`, `docs/canary/harness/CanarySmdesaiSpike.swift` — no secrets.
- **Extended scan (manual):** reviewed `AI_Workflow_Kit/docs/AI/` files (AI_WORKFLOW_KIT.md, REPORT.md, BUG_REPORT.md, SECURITY.md, SECURITY_REPORT.md, FEEDBACK) — no secrets.

### 2.2 Download-ready layout ✅
- Package is a directory on local disk, not a downloadable artifact.
- **No download code exists** in `Sources/` or `script/` that would fetch this package from a remote location.
- **Future CDN surface:** documented as residual risk in `docs/asr/canary-1b/BOLABOL_COREML_SPIKE.md` (§7: "Human CDN upload checklist", no download code). **Finding F3** addresses this gap.

### 2.3 Path traversal ✅
- No install helpers accept user-supplied paths (see §2.1).
- Package path is hardcoded in `check_s4b_canary_fix.sh`.
- **No risk.**

### 2.4 No secrets in package/docs ✅
- Manual review confirmed (see §2.1).
- Package contains only: Core ML models (binary weights), tokenizer (SentencePiece), metadata files (JSON/Markdown/TXT), license.
- Docs contain only: spike reports (Markdown), harness code (Swift).

### 2.5 Integrity (SHA) ✅ (with caveat)
- Text files: SHA-256 verified against MANIFEST (FRONTEND.md, LICENSE.txt, metadata.json, MANIFEST.json all match).
- Binary weights: sizes verified against MANIFEST (encoder 1,579,377,472 B, decoder_kv 270,864,448 B, cross_kv 33,589,312 B, tokenizer 503,803 B).
- **Caveat:** Full SHA verification requires `VERIFY_S4B_PACKAGE=1`, which is OFF by default. **Finding F2** addresses this gap.

### 2.6 No product Canary surface ✅
- `check_no_canary_product.sh` green (see §1.2).
- Product Sources contain no Canary-specific code except spec IDs and help keys.

### 2.7 Gitignore ✅
- `scratch/canary-1b-fix/` is in `.gitignore` — large model blobs not tracked.
- Other spike artifacts (`scratch/canary-spike/`, `scratch/canary-flash-spike/`) also gitignored.

### 2.8 Residual risk: CDN download surface ✅ (documented)
- **Current state:** no download code exists. Package is local-only.
- **Future risk:** if CDN upload happens, download code will need security review (path traversal, signature verification, integrity check).
- **Documented:** `docs/asr/canary-1b/BOLABOL_COREML_SPIKE.md` §7 mentions "Human CDN upload checklist" but no automated download.
- **Finding F3** proposes an automated guard.

---

## 3. Findings (findings_open)

| # | Severity | Finding | Impact | Recommendation |
|---|---|---|---|---|
| F1 | **Medium** | `check_no_secrets.sh` does not scan `docs/`, `scratch/`, `AI_Workflow_Kit/docs/` | A secret accidentally committed to these directories may not be detected by baseline QA. | Extend `check_no_secrets.sh` to include these directories, or add `script/qa/check_sec_no_secrets_extended.sh`. |
| F2 | **Low** | `check_s4b_canary_fix.sh` has `VERIFY_S4B_PACKAGE=1` (SHA integrity check) OFF by default | Package integrity is not automatically verified in `run_all.sh`. A tampered package could pass feature checks. | Enable `VERIFY_S4B_PACKAGE=1` by default, or add `script/qa/check_sec_s4b_package_integrity.sh` that always verifies SHA. |
| F3 | **Low** | No automated guard against CDN download code appearing in production | Residual risk documented in BOLABOL_COREML_SPIKE.md, but no script prevents download code from being added to Sources/ without review. | Add `script/qa/check_sec_no_download_code.sh` that scans Sources/ for download/install patterns (e.g., `URLSession`, `downloadTask`, `install` in model context). |

**All findings are low/medium severity and do not block POST.** They are documented for future hardening.

---

## 4. Verification matrix

| Check | Result | Evidence |
|---|---|---|
| Baseline secrets | ✅ Green | `check_no_secrets.sh` |
| Product Canary-free | ✅ Green | `check_no_canary_product.sh` |
| Spike contracts | ✅ Green | `check_b6_canary_spike.sh` |
| S4b feature | ✅ Green (with F2 caveat) | `check_s4b_canary_fix.sh` |
| Package paths | ✅ Green | Manual review (§2.1) |
| Download-ready layout | ✅ Green (no download code) | Manual review (§2.2) |
| Path traversal | ✅ Green | No user-supplied paths (§2.3) |
| Secrets in package/docs | ✅ Green | Manual review (§2.4) |
| SHA integrity | ✅ Green (with F2 caveat) | Text SHA + binary sizes (§2.5) |
| Product Canary surface | ✅ Green | §2.6 |
| Gitignore | ✅ Green | §2.7 |
| CDN residual risk | ✅ Documented | §2.8 |

---

## 5. Critical/high findings

**None.** All findings are low/medium severity (F1, F2, F3). No critical or high security issues detected.

---

## 6. Verdict

**findings_open** — security baseline is clean, but 3 low/medium gaps (F1, F2, F3) prevent full green status. These gaps do not block POST but should be addressed in future hardening.

**Not full green** because:
- F1 (medium): secrets scan coverage incomplete.
- F2 (low): SHA integrity not automatic.
- F3 (low): no guard against download code.

**Recommended actions:**
1. Address F1: extend `check_no_secrets.sh` or add extended script.
2. Address F2: enable `VERIFY_S4B_PACKAGE=1` by default or add dedicated integrity script.
3. Address F3: add `check_sec_no_download_code.sh`.

After these fixes, status can be upgraded to **security_clean**.

---

**Next step:** Address findings in future iteration, or accept as-is for POST with documented residual risk.
