# Feature QA Report

> **Owner:** Main Orchestrator.  
> Written from verified Tester output. Green feature gate only.

---

| Field | Value |
|-------|-------|
| Step | S13 — conditional project deletion |
| Date | 2026-08-17T23:13:09Z |
| Status | qa_green |
| Candidate | `S13ProjectDeletionCoder2` |
| Suite | S13 project archive/import/deletion focused suites |

---

## 1. Gate results

| Command | Result |
|---|---|
| Tester result: focused deletion/import gap-hunt | PASS — 54 tests / 0 failures |
| `swift test --filter ProjectArchiveTests` | PASS — 22/22 |
| `swift test --filter WorkflowStoreProjectImportTests` | PASS — 14/14 |
| `swift test --filter ProjectBundleImporterTests` | PASS — 9/9 |
| `swift test --filter ProjectMigrationTests` | PASS — 3/3 |
| `swift test --filter McpProjectVersioningTests` | PASS — 2/2 |
| `swift build` | PASS |
| `swift test` | PASS — 904 tests / 110 suites / 0 failures |
| `QA/scripts/s13_import_hardening.sh` | PASS |
| `bash script/build_and_run.sh --verify` | PASS — signed app built and launched |

---

## 2. Verified behavior

- Clean imported projects remove from the library without mutating their
  originating archive.
- Dirty imported projects offer save, discard, or export-as-new semantics;
  failed save/export retains the project and source data.
- Local-created projects retain destructive confirmation and reject imported
  save/remove semantics without an originating archive.
- Raw multi-record JSON overwrite updates only the selected record and keeps
  sibling records byte-valid.
- Open-project deletion resets the active workflow session.
- Persisted project-directory cleanup is contained under the managed Projects
  directory; traversal-like IDs cannot delete external files.
- Multi-file Finder import reports unsupported, partial, and full failures
  honestly and keeps renamed archive stems separate from source metadata.

---

## 3. Tester changes

- Added `Tests/VaniScriptTests/WorkflowStoreProjectImportTests.swift`.
- Main inspected every assertion; no weakened test or product-source changes
  were introduced by Tester.

---

## 4. Scope notes

- The S13-specific hardening contract passed.
- Aggregate `QA/run_all.sh` was also executed and returned **134 PASS / 24
  FAIL**. All 24 failures are historical Q7/A2–A7/CPS/LASR-01 acceptance,
  ADR, or state-contract checks outside this S13 feature; they do not overlap
  the S13-specific product/tests above.
- Conditional deletion is green.
- The repaired S13 DOCX import-tier candidate passed Human acceptance,
  Reviewer approval, and Tester QA; S13 remains open only for any separate
  unchecked hardening gates not covered by this candidate.
---

| Field | Value |
|-------|-------|
| Step | S13 — DOCX Refresh Source hardening |
| Date | 2026-08-17T18:49:29Z |
| Status | qa_green |
| Candidate | `S13DocxRefreshFix1` |
| Reviewer | `S13DocxRefreshReviewer1` — approved |
| Tester | `S13DocxRefreshTester1` — qa_green |
| Suite | DOCX reader and WorkflowStore Refresh Source focused contract |

## 5. Gate results

| Command | Result |
|---|---|
| `swift test --filter 'DOCXPackageReaderTests|WorkflowStoreRefreshSourceTests|DocumentSourceRefreshTests'` | PASS — 19 tests / 0 failures |
| `bash QA/scripts/s13_import_hardening.sh` | PASS |
| `swift test` | PASS — 908 tests / 110 suites / 0 failures |
| `bash script/build_and_run.sh --verify` | PASS — signed app built and launched |
| Fresh app accessibility smoke | PASS — one native 1920×1050 window |

## 6. Verified behavior

- Prefixed DOCX ZIP streams now resolve central-directory and local-header
  offsets relative to the embedded archive while standard packages remain
  supported.
- EOCD comments, false EOCD signatures, trailing bytes, size limits, unsafe
  paths, encryption, unsupported compression, and malformed central-directory
  cases remain covered and fail closed.
- A full WorkflowStore refresh test imports a prefixed DOCX, preserves the
  matching translation and block identity, realigns its source hash, rebuilds
  chunks, and publishes the targeted retranslate summary.
- The accepted `/usr/bin/unzip` status-1 path is limited to prefixed archives
  whose decompressed output still matches the declared uncompressed size.

## 7. Tester changes

- Added `Tests/VaniScriptTests/WorkflowStoreRefreshSourceTests.swift` coverage
  for the complete prefixed-DOCX refresh chain.
- Main inspected the added assertions and confirmed the test uses a throwaway
  managed project ID with cleanup; no product source was changed by Tester.

## 8. Scope notes

- The fresh-app smoke launched and exposed the native surface; the Tester did
  not click Refresh Source live and made no fabricated UI-path claim.
- The Human accepted the repaired Refresh Source behavior before Reviewer
  dispatch. The focused DOCX refresh candidate is green through QA.
