# QA REPORT — VaniScript Apple Silicon / LASR-02

- **Дата:** 2026-08-11
- **Трек/шаг:** `LOCAL_ASR_COREML` / `LASR-02`
- **Scope:** Download, storage, exact presence, reconciliation, and remote package installation
- **Swift:** **362 tests / 49 suites / 0 failures**
- **QA:** **158 scripts → 158 PASS / 0 FAIL**
- **Bugs open:** 0
- **QA verdict:** **GREEN**
- **Step status:** **BLOCKED — Human Canary 1B release metadata**

## Прогоны

| Прогон | Результат |
|---|---|
| `swift build` | PASS |
| `swift test` | **362 tests / 49 suites / 0 failures** |
| Первый `QA/run_all.sh` | 155 PASS / 3 FAIL — три stale LASR-01 QA gate не распознавали LASR-02 |
| После QA-only step-awareness maintenance | **158 PASS / 0 FAIL — GREEN** |
| Targeted Tester-diff review | 1 QA-only blocking finding |
| После узкого fix + re-review | **APPROVED — 0 findings** |

```bash
cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"
QA/scripts/lasr01_review_state.sh
# RESULT: PASS (lasr01_review_state, step-aware N/A)

QA/run_all.sh
# PASS: 158   FAIL: 0
# RESULT: GREEN
```

## LASR-02 contract evidence

1. Catalog-driven download routing covers FluidAudio, Hugging Face, and generic remote packages.
2. Canonical shared-model destinations are validated before staging or replacement.
3. Remote installation rejects traversal, symlink, archive/hash/layout, HTML, disk-space, and cancellation failures without producing Ready.
4. Failed replacement preserves an existing verified destination.
5. Presence is exact: required files, allowlist, finite byte sizes, and SHA-256 manifests are enforced.
6. Scan, Locate, reconciliation, registry lookup, and completion use the same presence policy.
7. Tester coverage uses tiny local fixtures and mocked URL loading; no network or model weights.
8. Three historical LASR-01 QA gates are step-aware without broad skipping.
9. The final Tester-authored diff received targeted independent review and was approved.

## Human blocker

The authoritative plan requires concrete Canary 1B release URL, archive layout,
per-file sizes, and SHA-256 hashes. Those values were not supplied. The catalog
therefore remains honestly unbound; no fake URL, digest, or Bolabol CDN reference
was introduced. LASR-02 cannot close and LASR-03 is not opened until Human input.
