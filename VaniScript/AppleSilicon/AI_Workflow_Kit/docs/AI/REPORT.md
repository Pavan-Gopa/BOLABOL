# Feature QA Report

> **Owner:** Main Orchestrator.  
> Written from verified Tester output. Green feature gate only.

---

## Meta

| Field | Value |
|-------|-------|
| Step | S2 — Canary Flash and Canary 1B engines |
| Date | 2026-08-11T12:51:07Z |
| Status | qa_green |
| Candidate | `S2CanaryDeterministicTestFix1` |
| Suite | `CanaryCoreMLEngineTests` |
| Human-requested rerun | `S2CanaryTesterBackup1` (`workflow-tester-backup`) |

---

## 1. Gate results

| Command | Result |
|---------|--------|
| Initial Tester: `swift test --filter CanaryCoreMLEngineTests` | PASS — 9 tests / 1 suite / 0 failures |
| Human-authorized backup rerun: `swift test --filter CanaryCoreMLEngineTests` | PASS — 9 tests / 1 suite / 0 failures |
| `swift test` | PASS — Main full-suite verification |
| `./script/build_and_run.sh --verify` | PASS — fresh `dist/VaniScript.app` built, signed, launched, and detected running |

---

## 2. Gap-hunt mapping

| Requirement (from S2) | Coverage | Result |
|-----------------------|----------|--------|
| Bounded Flash chunks and sustained-silence boundaries | `chunksRespectWindowAndSilenceBoundaries` | PASS |
| Path B mask/position shapes and macOS 15 gate | `pathBMaskAndPositionContracts`, `earlyRequestFailures` | PASS |
| Explicit source language, ASR-only requests, fail-closed variants/layouts | `requestAndLanguageValidation`, `modelLayoutValidation`, `earlyRequestFailures` | PASS |
| One resident session, shared concurrent load, unload/cancellation cleanup | `residentSessionLifecycle`, `concurrentTranscriptionsShareOneLoad`, `unloadDuringPendingLoadDisposesLateSession`, `cancellationCleansTemporaryAudio` | PASS |

---

## 3. Tester changes

- None. Tester added or modified no files.

---

## 4. Notes

- Initial Tester returned `qa_green`. The Human then explicitly requested a
  second verification after changing the Tester model.
- Two `synthetic/hf` primary launches failed before execution with
  `401 Invalid API Key`; neither produced a verdict or file change.
- Human authorized `workflow-tester-backup`; it ran the focused gate and
  returned 9/9 with no test diff.
- Main verified the backup transcript and exact command. No post-Tester
  Reviewer pass was launched.
