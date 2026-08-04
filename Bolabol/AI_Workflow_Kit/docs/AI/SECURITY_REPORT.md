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
