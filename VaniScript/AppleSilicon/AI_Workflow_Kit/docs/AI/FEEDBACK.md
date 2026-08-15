# FEEDBACK

> **Owner: Main Orchestrator.** Main writes a canonical entry only after
> verifying a worker's structured result against repository/test evidence.

---

## Template (copy for each handoff)

### Meta

| Field | Value |
|-------|-------|
| Step | |
| Actor | coder \| reviewer \| tester \| security \| architect |
| Timestamp | |
| RESULT | waiting_review \| approved \| changes_requested \| qa_green \| bugs \| security_clean \| findings_open \| advice_ready \| design_ready \| runtime_interrupted \| recovered_result |

### Summary

- …

### Verification (commands + results)

| Command | Result |
|---------|--------|
| | |

### Blocking / remaining

- …

### Verified attempt memory (retry only)

- Approach:
- Observed result:
- Verified evidence:
- Why rejected:
- Do not repeat without new evidence:

### Runtime reconciliation (when applicable)

- Classification: `still_active` | `recovered_result` | `interrupted_no_changes` | `interrupted_partial` | `indeterminate`
- Runtime evidence:
- Repository evidence:
- Recovered changed files:
- Unverified remainder:

### Review section (Reviewer only)

Verdict: `APPROVED` | `CHANGES_REQUESTED`

Blocking:

1. …

Non-blocking:

1. …

---

## Log

### S1 Coder — Parakeet engine

| Field | Value |
|-------|-------|
| Step | S1 |
| Actor | coder |
| Timestamp | 2026-08-11T06:33:39Z |
| RESULT | waiting_review |

#### Summary

- Added the app-target local ASR request/result/error/unload contract.
- Ported BOLABOL’s loudest-channel 16 kHz mono PCM WAV preparation.
- Ported Parakeet v3/int8 model loading, resident session, per-request decoder state, safe language hints, cleanup, and unload.
- Added focused audio and Parakeet behavior tests.
- Corrected two pre-existing test-only blockers without changing product behavior.

#### Verification

| Command | Result |
|---------|--------|
| `swift build` | PASS (Coder) |
| `swift test --filter 'LocalASRAudioPreprocessorTests|ParakeetTranscriptionEngineTests'` | PASS — 7 tests / 2 suites |
| `swift test` | PASS — 369 tests / 51 suites |
| LSP diagnostics for the three new service files | PASS — no issues |

#### Runtime reconciliation

- Classification: `recovered_result`
- Runtime evidence: two initial Coder launches exited before execution because the live task runtime did not resolve the project model alias; the same Human-selected primary model succeeded through a direct live-session binding.
- Repository evidence: the failed launches changed no files; the successful Coder and two test-only fixes changed only their authorized targets.
- Recovered changed files: `LocalASREngine.swift`, `LocalASRAudioPreprocessor.swift`, `ParakeetTranscriptionEngine.swift`, two focused S1 tests, and two pre-existing test corrections.
- Unverified remainder: Reviewer Judgment Gates and Tester QA.

### S1 Reviewer — primary runtime failure

| Field | Value |
|-------|-------|
| Step | S1 |
| Actor | reviewer |
| Timestamp | 2026-08-11T06:35:43Z |
| RESULT | runtime_interrupted |

#### Runtime reconciliation

- Classification: `interrupted_no_changes`
- Runtime evidence: `xai-oauth/grok-4.5:high` returned HTTP 403 `personal-team-blocked:spending-limit` before review execution.
- Repository evidence: Reviewer was read-only and produced no source inspection or verdict.
- Recovered changed files: none.
- Unverified remainder: both S1 Reviewer Judgment Gates.

### S1 Reviewer backup — Parakeet engine

| Field | Value |
|-------|-------|
| Step | S1 |
| Actor | reviewer |
| Timestamp | 2026-08-11T06:49:22Z |
| RESULT | approved |

#### Summary

- Human-authorized `workflow-reviewer-backup` completed the review on the configured Claude Opus 4.6 backup after the primary Grok spending-limit failure.
- BOLABOL behavior is ported without BOLABOL product-module imports.
- Engine residency, per-request decoder state, cleanup/cancellation, language filtering, and error semantics are bounded.
- The two test-only unblock changes correct stale assertions without weakening them.

#### Review section

Verdict: `APPROVED`

Blocking:

1. None.

Non-blocking:

1. None.

### S1 Tester — primary runtime failure

| Field | Value |
|-------|-------|
| Step | S1 |
| Actor | tester |
| Timestamp | 2026-08-11T06:50:57Z |
| RESULT | runtime_interrupted |

#### Runtime reconciliation

- Classification: `interrupted_no_changes`
- Runtime evidence: `google-antigravity/claude-sonnet-4-5:high` returned Cloud Code Assist HTTP 404 `NOT_FOUND` before QA execution.
- Repository evidence: no test or product file was changed and no focused gate ran in this Tester session.
- Recovered changed files: none.
- Unverified remainder: independent Tester QA for S1.

### S1 Tester — Parakeet QA

| Field | Value |
|-------|-------|
| Step | S1 |
| Actor | tester |
| Timestamp | 2026-08-11T06:57:11Z |
| RESULT | qa_green |

#### Summary

- Human-selected `google-antigravity/gemini-3.6-flash:high` completed targeted QA after the previous primary’s pre-execution 404.
- Added deterministic boundary coverage for invalid audio paths, source/destination identity, missing request audio, and unavailable model directories.
- No product code changed.

#### Verification

| Command | Result |
|---------|--------|
| `swift test --filter 'LocalASRAudioPreprocessorTests|ParakeetTranscriptionEngineTests'` | PASS — 9 tests / 2 suites / 0 failures |

#### Blocking / remaining

- None for S1. Human requested a pause after Tester completion so the workflow can be updated before further product work.


### S2 Coder — Canary Flash and Canary 1B engines

| Field | Value |
|-------|-------|
| Step | S2 |
| Actor | coder |
| Timestamp | 2026-08-11T10:10:32Z |
| RESULT | waiting_review |

#### Summary

- Added the exact Canary Flash and Canary 1B Path B Core ML execution paths behind the existing local-ASR contract.
- Enforced ASR-only requests, explicit supported source languages, exact variant/layout validation, `.cpuAndNeuralEngine`, macOS 15 Path B gating, cancellation cleanup, and resident unload behavior.
- Added deterministic pure and lifecycle coverage without model weights or network access.
- Changed only the three S2-authorized product/test paths.

#### Verification

| Command | Result |
|---------|--------|
| `swift build` | PASS — Main verified; one FluidAudio dependency resource warning |
| `swift test --filter CanaryCoreMLEngineTests` | PASS — 7 tests / 1 suite / 0 failures |
| `swift test` | PASS — 378 tests / 52 suites / 0 failures |

#### Blocking / remaining

- Reviewer-owned S2 Judgment Gate remains: verify `.cpuAndNeuralEngine`, ASR-only, OS, window, model-layout, and scope invariants against BOLABOL.

### S2 Reviewer — primary model failure

| Field | Value |
|-------|-------|
| Step | S2 |
| Actor | reviewer |
| Timestamp | 2026-08-11T10:11:31Z |
| RESULT | runtime_interrupted |

#### Runtime reconciliation

- Classification: `interrupted_no_changes`
- Runtime evidence: `xai-oauth/grok-4.5:high` returned HTTP 403 `personal-team-blocked:spending-limit` before review execution: "You have run out of credits or need a Grok subscription."
- Repository evidence: the read-only Reviewer produced no source/test changes and no Judgment Gate verdict.
- Recovered changed files: none.
- Unverified remainder: the S2 Reviewer Judgment Gate.

#### Blocking / remaining

- Workflow paused pending explicit Human authorization to retry the Reviewer role with `workflow-reviewer-backup`.

### S2 Reviewer backup — runtime failure

| Field | Value |
|-------|-------|
| Step | S2 |
| Actor | reviewer |
| Timestamp | 2026-08-11T10:57:26Z |
| RESULT | runtime_interrupted |

#### Runtime reconciliation

- Classification: `interrupted_no_changes`
- Runtime evidence: Human-authorized `workflow-reviewer-backup` read the full S2 implementation, tests, workflow sources, and BOLABOL reference, then exited with status 1 without returning the required structured verdict.
- Repository evidence: the read-only backup Reviewer changed no files.
- Recovered changed files: none.
- Unverified remainder: the S2 Reviewer Judgment Gate.

#### Blocking / remaining

- The failed backup run pauses routing again. Another Reviewer run requires fresh Human direction; no product attempt or repeated-failure counter was incremented.

### S2 Reviewer backup — quota failure

| Field | Value |
|-------|-------|
| Step | S2 |
| Actor | reviewer |
| Timestamp | 2026-08-11T11:20:07Z |
| RESULT | runtime_interrupted |

#### Runtime reconciliation

- Classification: `interrupted_no_changes`
- Runtime evidence: `google-antigravity/claude-opus-4-6:high` returned Cloud Code Assist HTTP 429 `RESOURCE_EXHAUSTED` before review execution. Individual quota reset: `2026-08-15T05:51:28Z`.
- Repository evidence: the read-only Reviewer produced no source/test changes and no Judgment Gate verdict.
- Recovered changed files: none.
- Unverified remainder: the S2 Reviewer Judgment Gate.

#### Blocking / remaining

- Routing is paused. The Human must configure a different Reviewer pair through `Alt+M` or wait for quota reset, then explicitly resume. Product attempts and repeated-failure counters remain unchanged.

### Workflow policy — single Reviewer and Tester pass

| Field | Value |
|-------|-------|
| Step | S2 / workflow-wide |
| Actor | main |
| Timestamp | 2026-08-11T11:46:34Z |
| RESULT | routing_policy_updated |

#### Summary

- Human set the default to one completed Reviewer verdict and one completed Tester verdict per unchanged Coder candidate.
- Main now verifies Tester-authored test diffs directly; `qa_green` cannot trigger a second targeted Reviewer pass.
- A changed candidate after a real `changes_requested` or `bugs` result must pass the normal Reviewer and Tester gates again.
- Provider/launch failures without a verdict do not consume the candidate's single review or test pass.

#### Runtime reconciliation

- `hub jobs`: no background jobs.
- `hub list`: no registered worker agents.
- `agent://LASR04CanaryReviewer2`: no recoverable artifact.
- Classification: `interrupted_no_changes`; the S2 Judgment Gate remains pending.

### S2 Reviewer — single product review

| Field | Value |
|-------|-------|
| Step | S2 |
| Actor | reviewer |
| Timestamp | 2026-08-11T11:56:22Z |
| RESULT | changes_requested |
| Candidate | LASR04CanaryCoder1 |

#### Verified finding

- `CanaryCoreMLEngine.loadedSession()` checks `session == nil`, then suspends in
  `sessionLoader`; actor reentrancy lets concurrent calls start multiple loads
  and overwrite a resident session without unloading the superseded one.
- `unload()` returns immediately while that load is pending, so the late loader
  can install a resident Core ML session after unload.
- `residentSessionLifecycle()` covers only sequential loads and unload after
  completion; it cannot detect either interleaving.

#### Required fix

- Coordinate one in-flight load across concurrent callers.
- Invalidate or dispose of any load that completes after unload.
- Preserve cancellation cleanup.
- Add deterministic suspended-loader tests for concurrent transcription and
  unload-during-load behavior without model weights or network access.

#### Main verification

- Confirmed against `CanaryCoreMLEngine.swift` lines 199–241 and
  `CanaryCoreMLEngineTests.swift` lines 120–163.
- No second Reviewer will run for this unchanged candidate. The required code
  change creates a new candidate that must pass the normal gates.

### S2 Coder fix — session load/unload reentrancy

| Field | Value |
|-------|-------|
| Step | S2 |
| Actor | coder |
| Timestamp | 2026-08-11T12:18:07Z |
| RESULT | waiting_review |
| Candidate | S2CanaryLifecycleFix1 |

#### Summary

- Added a generation-tagged in-flight load shared by concurrent waiters.
- `unload()` invalidates the generation, clears ownership, and ensures a
  late-loaded or pending uninstalled session is unloaded.
- Preserved cancelled-waiter cleanup and prevents a new load from overlapping
  an invalidated load that has not completed.
- Added suspended-loader regression coverage for concurrent transcription and
  unload during a pending load.

#### Main verification

| Check | Result |
|-------|--------|
| LSP diagnostics for both edited Swift files | PASS |
| `swift test --filter CanaryCoreMLEngineTests` | PASS — 9 tests / 1 suite / 0 failures |
| `swift test` | PASS |
| Changed paths | `CanaryCoreMLEngine.swift`, `CanaryCoreMLEngineTests.swift` only in this fix |

#### Remaining

- The changed candidate requires its single normal Reviewer verdict.
- Tester remains pending and will run once only after Reviewer approval.

### S2 Reviewer — lifecycle-fix candidate

| Field | Value |
|-------|-------|
| Step | S2 |
| Actor | reviewer |
| Timestamp | 2026-08-11T12:24:41Z |
| RESULT | changes_requested |
| Candidate | S2CanaryLifecycleFix1 |

#### Verified result

- The generation-tagged source state machine fixes the concurrent-load and
  unload-during-load resource race.
- The new unload-during-load test deterministically gates the interleaving.
- `concurrentTranscriptionsShareOneLoad()` opens `secondReady` after spawning an
  `async let`, not after that child joins the in-flight load. The first loader
  may be released before the child runs, so the test can pass against the old
  broken implementation.

#### Required fix

- Add a deterministic acknowledgement after the second request registers as an
  in-flight waiter, or an equivalent bounded test seam.
- Release the suspended loader only after that acknowledgement.
- Keep the one-load assertion; the test must fail against the former
  check-then-await implementation.

#### Main verification

- Confirmed against `CanaryCoreMLEngineTests.swift` lines 165–211.
- Source implementation does not need redesign for this finding.

### S2 Coder fix — deterministic waiter acknowledgement

| Field | Value |
|-------|-------|
| Step | S2 |
| Actor | coder |
| Timestamp | 2026-08-11T12:31:35Z |
| RESULT | waiting_review |
| Candidate | S2CanaryDeterministicTestFix1 |

#### Summary

- Added an optional internal load observer; production leaves it unset.
- The observer emits `waiterRegistered` only after the actor commits the
  in-flight generation and waiter set.
- The concurrency test now waits for `waiterCount == 2` before releasing the
  suspended loader, removing the prior scheduling gap.

#### Main verification

| Check | Result |
|-------|--------|
| LSP diagnostics for source and test | PASS |
| `swift test --filter CanaryCoreMLEngineTests` | PASS — 9 tests / 1 suite / 0 failures |
| `swift test` | PASS |

#### Remaining

- Candidate S2CanaryDeterministicTestFix1 requires its one Reviewer verdict.
- Tester remains pending and will run once after approval.

### S2 Reviewer — deterministic-test candidate

| Field | Value |
|-------|-------|
| Step | S2 |
| Actor | reviewer |
| Timestamp | 2026-08-11T12:36:50Z |
| RESULT | approved |
| Candidate | S2CanaryDeterministicTestFix1 |

#### Verified judgment

- Observer events are optional, `@Sendable`, and emitted synchronously only
  after the actor commits the generation-tagged waiter set.
- The concurrency test waits for two committed waiters before releasing the
  loader and retains one-load, two-result, shared-session, and final-unload
  assertions.
- The strengthened test closes the former scheduling gap.
- Generation/unload behavior and the original S2 ASR-only, OS, layout,
  windowing, model-variant, and `.cpuAndNeuralEngine` invariants remain intact.

#### Remaining

- Reviewer gate is approved.
- Candidate advances to its single Tester pass.

### S2 Tester — single QA pass

| Field | Value |
|-------|-------|
| Step | S2 |
| Actor | tester |
| Timestamp | 2026-08-11T12:38:43Z |
| RESULT | qa_green |
| Candidate | S2CanaryDeterministicTestFix1 |

#### Verification

| Command | Result |
|---------|--------|
| `swift test --filter CanaryCoreMLEngineTests` | PASS — 9 tests / 1 suite / 0 failures |

#### Gap hunt

- Coverage maps to Flash chunk/silence behavior, Path B shapes, explicit
  language and ASR-only rejection, model layout/variant failure, macOS gate,
  resident lifecycle, cancellation, two-waiter shared loading, and unload
  during a pending load.
- Concurrency coverage uses explicit actor-state acknowledgement; no sleeps,
  model weights, network, or source-text assertions.
- Tester added or modified no files.

#### Stop-gate

- Reviewer: approved.
- Tester: qa_green.
- S2 Stop-gate satisfied without a second Reviewer or Tester pass.

### S2 Tester rerun — configured model failure

| Field | Value |
|-------|-------|
| Step | S2 |
| Actor | tester |
| Timestamp | 2026-08-11T12:41:47Z |
| RESULT | runtime_interrupted |
| Candidate | S2CanaryDeterministicTestFix1 |

#### Runtime reconciliation

- Human explicitly requested another Tester pass after changing the primary
  Tester model.
- OMP accepted `S2CanaryTesterRerunGLM1`, then returned
  `401 Invalid API Key` before the worker could read source or run the focused
  command.
- Classification: `interrupted_no_changes`.
- No Tester verdict, test execution, or file change exists for this rerun.

#### Blocking / remaining

- Product attempts and repeated-failure counters are unchanged.
- Routing is paused under `omp.model_failure.status: awaiting_human`.
- Continue only after the Human fixes the primary mapping/credential or
  explicitly authorizes `workflow-tester-backup`.

### S2 Tester rerun — second synthetic provider failure

| Field | Value |
|-------|-------|
| Step | S2 |
| Actor | tester |
| Timestamp | 2026-08-11T12:47:49Z |
| RESULT | runtime_interrupted |
| Candidate | S2CanaryDeterministicTestFix1 |

#### Runtime reconciliation

- Human changed primary Tester to `synthetic/hf:moonshotai/Kimi-K3:high` and
  confirmed it was connected.
- OMP accepted `S2CanaryTesterRerunKimi1`, then returned the same
  `401 Invalid API Key` before source reads or test execution.
- Classification: `interrupted_no_changes`; no Tester verdict or file changes.

#### Blocking / remaining

- Two different `synthetic/hf` primary models failed with the same credential
  error, isolating the blocker to provider authentication rather than the model.
- Product attempts and repeated product-failure counters remain unchanged.
- `workflow-tester-backup` maps to `openai-codex/gpt-5.6-terra:xhigh` and needs
  explicit Human authorization before dispatch.

### S2 Tester backup — Human-requested QA rerun

| Field | Value |
|-------|-------|
| Step | S2 |
| Actor | tester |
| Timestamp | 2026-08-11T12:51:07Z |
| RESULT | qa_green |
| Candidate | S2CanaryDeterministicTestFix1 |

#### Authorization

- `human_backup_authorization: true`
- Exact Human instruction: `Разрешаю backup Tester`
- Agent: `S2CanaryTesterBackup1`

#### Verification

| Command | Result |
|---------|--------|
| `swift test --filter CanaryCoreMLEngineTests` | PASS — 9 tests / 1 suite / 0 failures |

- Backup Tester independently gap-checked all S2 observable contracts.
- Tester added or modified no files.
- Main verified the real transcript and exact command.

#### Stop-gate

- Reviewer: approved.
- Human-requested backup Tester rerun: qa_green.
- S2 is complete; no post-Tester Reviewer pass is required.

### S3 Coder — Canary shared-root discovery candidate 1

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | coder |
| Timestamp | 2026-08-11T13:24:59Z |
| RESULT | changes_requested |
| Candidate | S3CanaryDiscoveryFix1 |

#### Verified approach

- Added exact BOLABOL `MANIFEST.json` recognition while retaining the catalog
  allowlist, size, SHA-256, symlink, required-layout, and extra-file checks.
- Moved Locate and model-state reconciliation toward detached work with
  generation guards, and added deterministic legacy-manifest tests.

#### Main rejection

- `Sources/VaniScript/Stores/WorkflowStore.swift:144-148` has a malformed
  initializer: the `buildIdentifier` parameter and closing `) {` were removed.
  `swift build` exits 1, beginning with `static methods may only be declared on
  a type` and an eventual extraneous top-level brace.
- `Sources/VaniScript/Services/SettingsDiskStore.swift` accidentally removed
  `StarterGlossary.mergeStarterGlossary`; removing synchronous model
  reconciliation must not remove unrelated settings migration behavior.
- LSP diagnostics reported `OK` despite the parser break, so the next candidate
  must use the compiler result as the acceptance gate.

#### Required correction

- Restore the initializer signature and starter-glossary merge without
  discarding the intended S3 integrity/concurrency changes.
- Keep the diff within the existing S3 target files. A changed candidate must
  pass Main build/tests, then its single Reviewer and single Tester gates.

### S3 Coder — Canary shared-root discovery candidate 2

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | coder |
| Timestamp | 2026-08-11T13:30:19Z |
| RESULT | changes_requested |
| Candidate | S3CanaryDiscoveryFix2 |

#### Verified correction

- Restored the `WorkflowStore` initializer signature and
  `StarterGlossary.mergeStarterGlossary` migration exactly as requested.

#### Main rejection

- `swift build` still exits 1. In `startMcpModelDownload`, candidate 1 removed
  `let isTranslation = reference.isTranslation` while leaving every downstream
  branch and closure capture dependent on `isTranslation`.
- The compiler reports `cannot find 'isTranslation' in scope` at
  `WorkflowStore.swift:6136`, `6142`, `6160`, `6162`, `6176`, `6183`, `6188`,
  and `6196`.

#### Required correction

- Restore the missing local binding before the operation generation is created.
- Reinspect every deletion in the full candidate diff against its use sites;
  do not alter the accepted integrity/concurrency design or unrelated behavior.
- Main must observe a successful `swift build` before Reviewer dispatch.

### S3 Coder — Canary shared-root discovery candidate 3

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | coder |
| Timestamp | 2026-08-11T13:36:20Z |
| RESULT | waiting_review |
| Candidate | S3CanaryDiscoveryFix3 |

#### Main verification

- Restored the missing MCP model-kind binding; `swift build`: **PASS**.
- `swift test --filter NativeModelCatalogTests`: **PASS** — 17 tests.
- `swift test --filter RemoteModelPackageInstallerTests`: **PASS** — 10 tests.
- `swift test --filter UniversalSettingsTests`: **PASS** — 13 tests.
- Full `swift test`: **PASS** — 383 tests / 52 suites.
- `./script/build_and_run.sh --verify`: **PASS**; fresh app launched.
- Before the fix, MCP reported Canary 1B `failed` / not configured.
- Fresh-app background scan completed in 41 seconds while MCP remained
  responsive, found 7 models, and MCP then reported Canary 1B `downloaded`,
  configured, progress 1, with no error.

#### Candidate invariants

- The real package remains at its user-owned shared-root path; it was not moved,
  copied, or made app-owned.
- Legacy BOLABOL manifest acceptance still requires exact package identity,
  catalog file metadata, full SHA-256/size checks, required layout, no symlinks,
  and no unexpected files.
- Reviewer remains pending. Tester runs once only after Reviewer approval.

### S3 Reviewer — Canary shared-root discovery candidate 3

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | reviewer |
| Timestamp | 2026-08-11T13:45:28Z |
| RESULT | changes_requested |
| Candidate | S3CanaryDiscoveryFix3 |

#### Approved invariants

- Exact BOLABOL legacy manifest authenticity and full catalog
  hash/size/layout/symlink/extra-file validation remain fail-closed.
- Settings migration, provider snapshot merging, shared-path ownership, build,
  focused tests, full tests, and the real background discovery smoke are sound.

#### Required changes

1. `WorkflowStore.swift:6098-6110` and `6202-6242` still call full
   `isModelPresent` synchronously from MainActor MCP status/Locate paths. MCP
   status must use reconciled state, and MCP Locate must validate through
   background job/state flow with an operation guard.
2. `WorkflowStore.swift:3651-3714` has no scan generation, so two scans may
   publish out of order or clear `isScanning` incorrectly. MCP Locate and
   translation Locate also do not advance the per-model generation, allowing a
   pre-Locate scan to overwrite the newer selected path.
3. Add deterministic behavior tests for two-scan completion reordering and a
   scan finishing after a newer Locate operation.

#### Main confirmation

- Main inspected each cited path and confirmed both findings. This is a new,
  materially different failure after discovery/integrity progress, so the
  no-progress counter restarts at 1 and a fresh Coder fix is permitted.

### S3 Human crash — Canary-selected native processing

| Field | Value |
|-------|-------|
| Step | S3 |
| Reporter | Human |
| Timestamp | 2026-08-11T13:44:39Z |
| RESULT | changes_requested |
| Candidate | S3CanaryDiscoveryFix3 |
| Incident | B03A6D52-4873-4BE1-A51C-E4178E24E8D7 |

#### Reproduction and root cause

- Fresh build `20260811133359`: select Canary 1B, open the existing project,
  start native re-transcription for chunk 1; app exits with `SIGTRAP`.
- App log ends immediately after `Starting native processing for current
  segment`; the faulting thread is
  `SmartAudioAnalyzer.readEnergyProfile` at line 64, before any ASR engine.
- The no-range overload passes `Double.greatestFiniteMagnitude`. It is finite,
  so `endSec * sampleRate` overflows to infinity and
  `AVAudioFramePosition(...)` traps before `min(file.length, ...)` can clamp it.
- Main reproduced the same libswiftCore assertion and exit 133 with that exact
  conversion. Background Canary hashing visible on another thread is not the
  crashing operation.

#### Required correction

- Clamp in floating-point space before converting to `AVAudioFramePosition`;
  unbounded/non-finite ranges must resolve to `file.length`.
- Add a real audio-file regression test through `SmartAudioAnalyzer.planChunks`
  or equivalent observable API. It must fail by trap on the old code and
  complete normally after the fix.
- Candidate 4 must also satisfy the existing candidate-3 Reviewer corrections
  before a fresh single Reviewer and single Tester pass.

### S3 Coder — Canary crash and ordering candidate 4

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | coder |
| Timestamp | 2026-08-11T14:16:37Z |
| RESULT | changes_requested |
| Candidate | S3CanaryCrashFix4 |

#### Verified progress

- `SmartAudioAnalyzerTests`: **PASS** — 1 test; the old full-file conversion
  trap is now a permanent real-AVAudioFile regression.
- `WorkflowStoreLocalModelTests`: **PASS** — 3 deterministic continuation
  tests for two-scan order, scan-after-Locate, and stale MCP Locate completion.
- Native catalog 17 tests and remote package installer 10 tests: **PASS**.
- `swift build`: **PASS**; full `swift test`: **PASS** — 387 tests / 54 suites.
- Candidate 4 removes synchronous MCP status/Locate hashing, queues MCP Locate
  validation, and guards scan/Locate completion ordering.

#### Main runtime rejection

- Fresh app PID 57266 launched, but MCP model-status calls timed out twice and
  Accessibility exposed no app window.
- A live debugger trace found the main thread in
  `LocalASRPresencePolicy.sha256` while hashing Canary 1B through
  `ProviderRegistry.downloadedLocalProviders` at
  `ProviderRegistry.swift:154-179`, called by
  `ConfigWorkspaceView.transcriptionProviders`.
- This is the remaining user-visible wait-cursor source: provider-list
  rendering still revalidates the 1.58 GB encoder synchronously even though
  detached reconciliation already owns full integrity.
- Candidate 4 is rejected before Reviewer. Preserve its verified changes;
  candidate 5 must make ProviderRegistry consume reconciled model state with
  cheap reference checks and add a behavior regression.

### S3 Coder — Provider-list MainActor correction candidate 5

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | coder |
| Timestamp | 2026-08-11T14:29:36Z |
| RESULT | waiting_review |
| Candidate | S3CanaryProviderFix5 |

#### Main verification

- Changed only `ProviderRegistry.swift` and `NativeModelRoutingTests.swift`.
- Provider listing no longer reaches `NativeModelCatalog.isModelPresent`; it
  checks downloaded/runtime/OS state and the persisted directory reference.
  Detached reconciliation still owns package layout, hashes, and failure state.
- New provider-boundary test: **PASS**. It proves a stale downloaded state is
  cheap to list, then excluded after authoritative synchronization marks it
  failed.
- Focused S3 gates: **PASS** — SmartAudioAnalyzer 1, WorkflowStore local-model
  concurrency 3, native catalog 17, native routing 6, provider registry 4,
  remote installer 10, universal settings 13.
- `swift build`: **PASS**. Full `swift test`: **PASS** — 387 tests / 54 suites.
- Fresh `dist/VaniScript.app` PID 60802 launched with two accessible windows.
  A live debugger trace found MainActor idle in the AppKit event loop rather
  than hashing package contents.
- VaniScript MCP mounted calls still timed out despite the idle MainActor; this
  is transport-level evidence, not a reproduced UI stall, and remains for
  Reviewer judgment.

### S3 Reviewer — candidate 5

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | reviewer |
| Timestamp | 2026-08-11T14:41:50Z |
| RESULT | changes_requested |
| Candidate | S3CanaryProviderFix5 |

#### Approved findings

- Candidate 5 removed full package hashing from ProviderRegistry without
  weakening detached reconciliation or exact active-model preflight.
- BUG-001's floating-point clamp is numerically safe and covered by a real
  AVAudioFile regression.

#### Required corrections accepted by Main

1. `AppSettings.isDownloadedLocalASRModelActive` reports a selected,
   downloaded ASR state with no path as active. A missing source must be
   immediately inactive; background reconciliation must retain authority for
   detailed validation/failure state.
2. Candidate 3/4 changed direct translation Locate to suppress synchronous
   reconciliation but persisted the picker path as downloaded without using
   the existing detached validator. Validate asynchronously, guard the
   completion generation/path, and cover invalid and stale completions.

#### Reviewer finding rejected by Main

- The Reviewer assignment incorrectly described alternate Canary metadata.
  Main read the real shared package at
  `/Users/pavan/AI_LOCAL_MODELS/whisperkit/canary/1b-v2/MANIFEST.json`.
  Its `packageId` is `bolabol-canary-1b-v2-coreml-r1`; its exact 20-entry file
  allowlist/hashes/sizes match the current catalog and positive/negative tests.
  Do not replace that verified real contract with the erroneous assignment
  values.

### S3 Coder — Reviewer remediation candidate 6

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | coder |
| Timestamp | 2026-08-11T14:52:45Z |
| RESULT | changes_requested |
| Candidate | S3CanaryReviewFix6 |

#### Main verification

- Product fixes match both accepted Reviewer requirements; LSP diagnostics
  are clean.
- Native routing: **PASS** — 7 tests.
- WorkflowStore local-model operations: **PASS** — 4 tests, including invalid
  direct translation Locate and stale MCP/direct-Locate ordering.
- SmartAudioAnalyzer 1, native catalog 17, provider registry 4, and remote
  installer 10: **PASS**.
- `UniversalSettingsTests`: **FAIL** — its pre-existing active-badge test still
  expects a pathless downloaded Whisper state to be active. The product
  contract intentionally changed; the test must assert pathless inactive and
  existing-directory active without weakening its other assertions.
- Candidate 6 is rejected before re-review; candidate 7 is test-only.

### S3 Coder — test alignment candidate 7

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | coder |
| Timestamp | 2026-08-11T14:55:51Z |
| RESULT | waiting_review |
| Candidate | S3CanaryTestAlignmentFix7 |

#### Main verification

- Candidate 7 changed only
  `Tests/VaniScriptCoreTests/UniversalSettingsTests.swift`.
- The existing active-badge test now preserves both sides of the changed
  contract: pathless downloaded is inactive; downloaded with a real existing
  temporary directory is active. Wrong-provider and translation assertions
  remain.
- `UniversalSettingsTests`: **PASS** — 13 tests.
- Candidate 6 focused gates remain **PASS**: native routing 7,
  WorkflowStore local-model operations 4, SmartAudioAnalyzer 1, native catalog
  17, provider registry 4, remote installer 10.
- Full `swift test`: **PASS** — 389 tests / 54 suites.

### S3 Reviewer — candidate 7 remediation

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | reviewer |
| Timestamp | 2026-08-11T15:01:32Z |
| RESULT | approved |
| Candidate | S3CanaryTestAlignmentFix7 |

- Pathless downloaded local ASR is inactive via cheap checks while detached
  reconciliation remains the exact failure authority.
- Direct translation Locate validates off MainActor, guards
  generation/status/path, preserves canonical success paths, and records
  honest failure state.
- Deterministic tests cover scan and MCP/direct stale ordering; candidate 7
  preserves the existing-directory positive branch, wrong-provider negative,
  and translation assertions.

### S3 Tester — candidate 7 primary model failure

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | tester |
| Timestamp | 2026-08-11T15:03:05Z |
| RESULT | runtime_interrupted |
| Candidate | S3CanaryTestAlignmentFix7 |

- `S3CanaryFinalTester1` returned `401 Invalid API Key` before source reads or
  any QA command.
- Classification: persistent model/provider authentication failure; no product
  files or tests changed and no Tester verdict exists.
- Routing is paused. Product/retry counters remain unchanged. A backup Tester
  requires a new explicit Human authorization for this recorded S3 failure.

### S3 Human runtime — WhisperKit-only readiness

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | human |
| Timestamp | 2026-08-11T15:13:01Z |
| RESULT | changes_requested |
| Candidate | S3CanaryTestAlignmentFix7 |

- Fresh candidate 7 UI had Canary Flash 180M selected and active.
- `Initialize Engine` failed with: `Core ML transcription requires a
  downloaded or located WhisperKit model.`
- Source verification: `NativeProcessingReadiness.evaluate` calls
  `NativeModelCatalog.activeWhisperKitModel` and hard-codes the WhisperKit
  failure message. The catalog already exposes `activeLocalASRModel`.
- Persisted settings confirm `transcriptionProvider` is
  `canary-180m-flash-coreml`; this is not a stale UI selection.
- BUG-002 is a new product failure. Candidate 8 must implement the remaining
  S3 readiness policy without pretending S4 engine dispatch is complete.

### S3 Coder — local ASR readiness candidate 8

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | coder |
| Timestamp | 2026-08-11T15:30:06Z |
| RESULT | waiting_review |
| Candidate | S3LocalASRReadinessFix8 |

- Changed only `NativeProcessingReadiness.swift`,
  `NativeProcessingPipeline.swift`, and
  `NativeProcessingReadinessTests.swift`.
- Concrete local provider IDs now resolve through their catalog descriptor,
  apply OS/source/state/path checks, and use `activeLocalASRModel` for final
  presence validation. Unknown providers fail closed; cloud behavior and the
  legacy WhisperKit alias remain supported.
- Both processing entry points pass `session.sourceLang`. Translation fallback
  no longer invokes the combined evaluator and therefore cannot repeat Canary
  package hashing.
- Main verification: LSP diagnostics **OK** for all three files; readiness
  **11/11**, routing **7/7**, universal settings **13/13**, analyzer **1/1**,
  WorkflowStore local model **4/4**, catalog **17/17**, remote installer
  **10/10**; `swift build` **PASS**; full `swift test` **394 tests / 54 suites
  PASS**.
- S4 engine instantiation remains intentionally unimplemented in candidate 8;
  S3 now needs its single independent Reviewer judgment.

### S3 Reviewer — local ASR readiness candidate 8

| Field | Value |
|-------|-------|
| Step | S3 |
| Actor | reviewer |
| Timestamp | 2026-08-11T15:35:30Z |
| RESULT | approved |
| Candidate | S3LocalASRReadinessFix8 |

- The single Reviewer pass approved descriptor-first local classification,
  cheap-to-expensive OS/source/state/path/presence checks, model-specific
  failures, cloud and generic WhisperKit compatibility, fail-closed unknown
  providers, and both pipeline source-language callsites.
- Translation fallback no longer re-enters ASR readiness.
- The still-WhisperKit-only execution branch is an explicit S4 concern, not an
  S3 readiness blocker.
- Final S3 QA cannot start until the Human authorizes
  `workflow-tester-backup`, reconfigures the primary Tester model, or explicitly
  skips QA.

### S3 Main — fresh candidate 8 app

- `./script/build_and_run.sh --verify` **PASS** after stopping candidate 7.
- Fresh `dist/VaniScript.app` is open as PID `73167` with a `VaniScript`
  window.
- End-to-end Parakeet/Canary transcription is not claimed: S3 fixes readiness;
  the exact-engine execution router remains S4 and cannot open until the S3
  Tester Stop-gate is satisfied or explicitly skipped by the Human.

### Workflow preference — Human acceptance before review

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-11T16:26:33Z |
| Actor | human |
| Applies from | S4 |

- New order: Coder → Main source/tests/build/fresh app → Human acceptance test
  → one Reviewer → one Tester.
- A Human-rejected candidate returns directly to Coder. Reviewer and Tester are
  not spent before the app behavior works for the Human.
- Human explicitly declined S3 Tester now. S3 QA is recorded as skipped for its
  Stop-gate; BUG-001/BUG-002 remain carried into S4 end-to-end acceptance.
- Candidate 8's already-completed Reviewer approval is preserved and not rerun.

### S4 Human requirement — independent source and target languages

- Screenshot evidence: Canary Flash 180M is selected, Target Language is
  `English`, but initialization fails because `workflow.sourceLang` remains
  `auto` and ConfigWorkspaceView exposes no source control.
- `Source Language` is the explicit ASR input language and must be filtered by
  the selected descriptor (`en/de/fr/es` for Canary Flash; `auto` only where
  capabilities allow it).
- `Target Language` is independent. If normalized source and target are equal,
  run transcription directly and do not load or invoke translation. If they
  differ, preserve the existing downstream translation route.
- The UI should mirror BOLABOL's `Language` / `Secondary Language` semantics,
  while using clear VaniScript labels.

### S4 Architect advisory — primary model failure

| Field | Value |
|-------|-------|
| Step | S4 |
| Actor | architect |
| Timestamp | 2026-08-11T16:33:37Z |
| RESULT | model_failure |
| Run | S4LanguageRouterAdvisory1 |

- The optional advisory did not read source or return design advice.
- Cloud Code Assist returned HTTP 429 `RESOURCE_EXHAUSTED` for
  `claude-opus-4-6-thinking`; reported reset is
  `2026-08-15T05:51:28Z`.
- No product attempt or retry counter changed. Routing awaits an explicit Human
  choice: authorize `workflow-architect-backup` or skip this optional advisory
  and proceed with the already bounded S4 contract.

### S4 Architect backup authorization

- At `2026-08-11T16:37:30Z`, the Human explicitly selected:
  `Запустить backup Architect`.
- This authorizes one `workflow-architect-backup` advisory retry for the
  recorded S4 Architect model failure. Normal source verification still applies.

### S4 Architect backup — model failure

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-11T16:38:16Z |
| Run | S4LanguageRouterAdvisoryBackup1 |
| RESULT | model_failure |

- The authorized backup also failed before reading source or returning advice.
- OpenRouter returned HTTP 402: the request allowed up to 65,536 tokens while
  available credits supported 43,055.
- No product attempt changed. Per failover contract, routing pauses again; the
  Human may explicitly skip this optional advisory and let Main send the bounded
  contract directly to Coder, or reconfigure the Architect pair.

### S4 Architect advisory — explicitly skipped

- At `2026-08-11T16:39:16Z`, after the authorized backup also failed before
  source reads, the Human selected `Пропустить Architect`.
- The optional advisory is closed. Main will route the already bounded S4
  source/target-language and local-ASR-router contract directly to Coder.

### S4 Coder candidate 1 — Main build failure

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-11T17:03:25Z |
| Run | S4LocalASRRouterCoder1 |
| RESULT | changes_requested |

- Coder returned the complete ten-file S4 candidate; no build/tests were run by
  the worker per assignment.
- Main LSP diagnostics reported `OK`, but `swift build` failed before tests.
- Exact product regression:
  `Sources/VaniScript/Views/ChatSidebarView.swift:127` changed valid
  `} label: {` to invalid `} label {`, producing “consecutive statements on a
  line must be separated by ';'” and “cannot find 'label' in scope”.
- Required fix: restore the missing colon only. Preserve all S4 router/language
  changes. No Reviewer, Tester, or Human acceptance has run.

### S4 Coder candidate 2 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-11T17:05:59Z |
| Candidate | S4LocalASRRouterFix2 |
| RESULT | waiting_human_acceptance |

- Exact compile fix verified at `ChatSidebarView.swift:127`: `} label: {`.
- LSP diagnostics reported `OK` for all ten S4 source/test paths before the
  compiler exposed candidate 1's syntax issue.
- `swift build` **PASS** after candidate 2. Existing unrelated deprecation,
  unused-local, and FluidAudio resource warnings remain; no new S4 diagnostic
  blocked the build.
- Focused suites **PASS**:
  - Native processing readiness: 14 tests
  - Local ASR router: 2 tests
  - Native processing local ASR: 2 tests
- Full `swift test` **PASS**: 401 tests / 56 suites.
- Source verification: descriptor-derived Source Language options, independent
  Target Language, same-language translation bypass, exact resident router,
  Whisper cue preservation, local-MLX unload, and active-local-ASR dictation
  are present. Fresh-app UI and real-model behavior remain the Human gate.

### S4 candidate 2 — fresh-app Main smoke

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-11T17:28:30Z |
| Candidate | S4LocalASRRouterFix2 |
| RESULT | waiting_human_acceptance |

- `./script/build_and_run.sh --verify` rebuilt and opened candidate 2; the new
  VaniScript process was running.
- After locating the verified Canary Flash package and selecting it, a clean
  relaunch opened Engine Configuration with:
  - Source Language: `Choose Source Language`
  - Target Language: `Russian`
  - Transcription Model: `Canary Flash 180M`
  - Translation Model: `MLX Swift Local`
- The Canary Flash Source Language menu contained exactly `English`, `German`,
  `French`, `Spanish`, plus the explicit placeholder. Selecting `English` and
  Target Language `Keep Original` changed Translation Model to
  `Disabled for Same Language`.
- Starting the session entered real native processing. `app.log` records
  `Loading local ASR model Canary Flash 180M (canary-180m-flash-coreml)` from
  `/Users/pavan/AI_LOCAL_MODELS/canary/180m-flash` and transcription of the
  generated chunk.
- The input was macOS `Ping.aiff`, a 1.5-second non-speech sound. Processing
  completed with the honest UI result `Local transcription returned no text`;
  this proves real engine dispatch but is not meaningful-speech acceptance.
- Human acceptance remains required on a speech recording. Reviewer and Tester
  remain blocked until the Human accepts this unchanged candidate.

### S4 candidate 2 — Human acceptance changes requested

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-11T18:52:35Z |
| Candidate | S4LocalASRRouterFix2 |
| RESULT | changes_requested |

- Four Human screenshots document a meaningful 10-minute speech run.
- Parakeet and Canary Flash return one `00:00-10:00` review cue containing the
  entire transcript. This violates the requested timestamp segmentation and
  differs materially from the Whisper Large v3 review output.
- Source inspection confirms both engines return text-only `LocalASRResult`
  values. `NativeProcessingPipeline.transcriptCues` then creates one fallback
  cue spanning the entire planned chunk. The changed candidate must produce
  review-ready timed cues from real engine/chunk timing rather than rely on an
  unsupported prompt-formatting claim.
- The processing screen says only `with local ASR`; the Human cannot verify
  whether Canary or Parakeet is actually running. Loading and transcription
  progress must include the exact selected model label.
- Scan Local Models does not discover the verified Canary 1B package and leaves
  the model on `Download`. The current package remains at
  `/Users/pavan/AI_LOCAL_MODELS/whisperkit/canary/1b-v2`; the scanner's default
  roots do not include that local-model root.
- The Human wants Canary 1B distributed from cloud storage later. No release
  endpoint was supplied, so this changed candidate must preserve the explicit
  environment-override contract and must not fabricate a URL.
- Human acceptance is rejected. Reviewer and Tester did not run. Route these
  findings directly to a fresh Coder.

### S4 Coder candidate 3 — Main compile failure

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-11T19:15:23Z |
| Run | S4TimedCuesModelDiscoveryCoder3 |
| RESULT | changes_requested |

- The Coder implemented timed Parakeet/Canary cues, active-model progress text,
  conventional `~/AI_LOCAL_MODELS` discovery, and focused behavior tests in
  nine authorized files. It ran no validation as assigned.
- Main's focused gate failed during compilation before tests executed.
- Exact error:
  `Sources/VaniScriptCore/NativeModelCatalog.swift:1292:30: cannot find
  'newLocalASRModelDescriptors' in scope`.
- `LocalModelScanner.scanForLocalModels(searchPaths:maxVisitedItems:)` is
  outside `NativeModelCatalog`; it must qualify the existing catalog property
  as `NativeModelCatalog.newLocalASRModelDescriptors`.
- This is a new, exact compile failure signature. Preserve every candidate 3
  behavior change and route only the qualification fix to a fresh Coder.

### S4 Coder candidate 4 — Main compile failure

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-11T19:17:14Z |
| Run | S4TimedCuesCompileFix4 |
| RESULT | changes_requested |

- The exact candidate 3 catalog qualification was applied correctly.
- Main's focused gate compiled past `VaniScriptCore`, then failed in
  `ParakeetTranscriptionEngine.swift:124` because `language` is not in scope.
- Candidate 3 preserved `mappedLanguage(from:)` but dropped the local binding
  that existed before its session call. Restore
  `let language = mappedLanguage(from: request.languageHint)` before invoking
  `session.transcribe`.
- This is a materially different compiler failure exposed by the first fix.
  Preserve every candidate 3/4 behavior change and route only this local-binding
  repair to a fresh Coder.

### S4 changed candidate 5 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-11T19:22:55Z |
| Candidate | S4ParakeetLanguageFix5 |
| RESULT | waiting_human_acceptance |

- Candidate 5 restored the missing Parakeet language binding after candidate 4
  fixed the catalog qualification. Main verified both exact repairs in source.
- Focused gate **PASS**: 37 tests / 4 suites covering NativeModelCatalog,
  Parakeet local ASR, Canary Core ML local ASR, and native pipeline local ASR.
- `swift build` **PASS**. Existing FluidAudio resource and unrelated
  deprecation warnings remain non-blocking.
- Full `swift test` **PASS**: 405 tests / 56 suites.
- Source and focused tests verify:
  - FluidAudio token timings become bounded word-bearing Parakeet cues;
  - non-empty Canary inference windows become ordered relative timed cues;
  - the pipeline applies the planned-chunk absolute offset exactly once and
    does not replace authoritative timed output with a whole-chunk fallback;
  - local loading/transcription progress names `activeModel.label`;
  - scanner roots include `~/AI_LOCAL_MODELS` and its nested `whisperkit`
    layout without hardcoding a username, with incomplete packages rejected.
- `./script/build_and_run.sh --verify` rebuilt, signed, and opened the fresh
  `dist/VaniScript.app`; Main confirmed the changed process running as PID 8930.
- Human acceptance remains required on the same meaningful 10-minute speech
  path and Scan Local Models workflow. Reviewer and Tester remain blocked.

### S4 candidate 5 — Human acceptance changes requested

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-12T03:04:12Z |
| Candidate | S4ParakeetLanguageFix5 |
| RESULT | changes_requested |

- Human screenshot: Models marks Canary Flash 180M `Active`, while the
  processing screen explicitly says `Whisper Large v3 local ASR`.
- `app.log` confirms the exact route at `2026-08-12 08:25:05`: the reopened
  project loaded `Whisper Large v3 (whisper-large-v3)`.
- Persisted `settings.json` selects `canary-180m-flash-coreml`, while the newest
  persisted project session selects `whisper-large-v3`.
- Source cause: `openProject` restores the archived session provider into the
  workflow, while Models computes `Active` from global settings. Its glossary-
  only `updateSettings` call sees no provider change, so it does not synchronize
  the reopened session. The UI and actual processing route therefore disagree.
- Human screenshot: Canary 1B remains unavailable after scanning.
- `app.log` reports six scanned models / four ASR models; Canary 1B is absent.
  The verified package remains at
  `/Users/pavan/AI_LOCAL_MODELS/whisperkit/canary/1b-v2`.
- Main independently verified every one of its 19 MANIFEST-listed files:
  existence, byte count, and SHA-256 all match. There are no symlinks.
  `.DS_Store` is the only unexpected regular file. Strict
  `extractedRegularFiles - allowlist` validation rejects this harmless Finder
  metadata, preventing scanner discovery.
- Required changed candidate: make the Models Active state, opened session, and
  processing route share one selected ASR source of truth; ignore only bounded
  platform metadata such as `.DS_Store` during remote-package extra-file
  validation, preserving the manifest allowlist for all model/package files.
- Human acceptance is rejected. Reviewer and Tester did not run.

### S4 candidate 6 Coder — model/provider failure

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T05:11:19Z |
| Run | S4SelectionFinderMetadataCoder6 |
| RESULT | awaiting_human |

- The primary `workflow-coder` read source and evidence but made no product or
  test edit.
- It exited with: `Your authentication token has been invalidated. Please try
  signing in again.`
- This is a model/provider authentication failure, not an implementation
  attempt. `implementation.attempts` remains 5.
- Routing is paused. Main will not launch `workflow-coder-backup` unless the
  Human explicitly authorizes that backup retry. Alternatively, the Human may
  restore the primary model authentication and request a fresh primary Coder.

### S4 candidate 6 — backup Coder authorization

- At `2026-08-13T05:12:38Z`, the Human explicitly selected
  `Запустить backup Coder`.
- Main may dispatch `workflow-coder-backup` once for the recorded
  `S4SelectionFinderMetadataCoder6` authentication failure.

### S4 changed candidate 6 — Main compile failure

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T05:18:43Z |
| Candidate | S4SelectionFinderMetadataBackup7 |
| RESULT | changes_requested |

- The Human-authorized backup Coder changed provider selection, project-open
  reconciliation, Models `Active`/`Use`, bounded `.DS_Store` handling, and
  behavior tests.
- Main LSP diagnostics reported the changed product sources as clean.
- The focused S4 gate failed while compiling
  `WorkflowStoreLocalModelTests.swift`. All three new provider-selection tests
  use stale constructors: `label` after `path`, nonexistent runtime `.coreml`,
  `AudioMetadata()` without required values, missing `currentChunkIndex`, and
  `Date` where `ProjectRecord` requires ISO strings.
- No test executed. This is a new objective-gate failure signature. Preserve
  candidate 6 product behavior and route only fixture-constructor repairs to a
  fresh Coder.

### S4 changed candidate 7 — Main focused behavior failure

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T05:23:08Z |
| Candidate | S4ProviderFixtureCompileCoder8 |
| RESULT | changes_requested |

- Candidate 7 repaired every compile error in the three new
  `WorkflowStoreLocalModelTests`; LSP diagnostics are clean.
- Focused gate compiled and ran 45 tests across the router/timed-cue,
  provider-selection, and catalog suites.
- 44 tests passed. `stale async refresh does not rollback selected provider`
  failed because its alleged available Canary fixture is an empty directory.
  `reconcileLocalModelStates()` correctly fails full Canary layout validation,
  then provider refresh selects Whisper.
- The implementation must not preserve an invalid model. Repair the test to
  create the minimal valid Canary Flash required layout
  (`CanaryEncoder.mlmodelc`, `CanaryPrefill.mlmodelc`,
  `CanaryDecoder.mlmodelc`, `config.json`, `vocab.json`) before reconciliation.
  Keep the stale-refresh assertions and product behavior unchanged.

### S4 changed candidate 8 — Main full-suite compile failure

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T05:28:02Z |
| Candidate | S4ValidCanaryFixtureCoder9 plus recovered primary edits |
| RESULT | changes_requested |

- The corrected focused S4 gate passes all 45 tests across five suites.
- `swift build` passes.
- During verification, the previously failed primary Coder delivered late
  recovered edits: a bounded
  `WorkflowState.applySelectedTranscriptionProviderIfAvailable()` helper,
  project-open application/persistence, effective Models state, guarded async
  reconciliation, nested `.DS_Store` coverage, and two WorkflowState tests.
  Main preserved and inspected these repository changes.
- Full `swift test` fails compiling the two recovered WorkflowState tests:
  Swift Testing's `#expect` macro cannot call a mutating method on its immutable
  captured `$0`. Product sources are not implicated.
- Required repair: call the mutating helper into a local `Bool`, then assert
  that value. Preserve both scenarios and state assertions exactly.

### S4 changed candidate 9 — Main verification and fresh-app smoke

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T05:34:33Z |
| Candidate | S4MutatingExpectCompileCoder10 |
| RESULT | waiting_human_acceptance |

- Focused S4 gate: **PASS**, 45 tests across timed-cue/router,
  provider-selection, and native-model catalog suites.
- `swift build`: **PASS**.
- Full `swift test`: **PASS**, 411 tests in 56 suites.
- `./script/build_and_run.sh --verify`: **PASS**; fresh signed
  `dist/VaniScript.app` is running as PID 17461.
- Fresh runtime scan logged `Found 8 total models on disk (ASR Connected: 6,
  Translation Connected: 2)`.
- Persisted `settings.json` now contains `canary-1b-v2-coreml` with
  `status: downloaded`, proving the real manifest-valid package with its
  Finder metadata is discovered.
- Meaningful-speech runtime smoke loaded `Canary Flash 180M
  (canary-180m-flash-coreml)` and completed segment 1/5 with 3382 characters.
- Persisted global settings and the active project both select
  `canary-180m-flash-coreml`; the prior Active-Canary/processing-Whisper split
  is not present in this run.
- Human acceptance remains required on the opened candidate. Reviewer and
  Tester have not run.

### S4 candidate 9 — Human testing extended

- At `2026-08-13T05:38:56Z`, the Human requested more time for testing and
  asked Main to reopen the verified build.
- Main opened `dist/VaniScript.app`; the changed candidate is running as
  PID 19828.
- Human acceptance remains `pending`. Reviewer and Tester remain blocked.

### S4 candidate 9 — Human rejection and verified MLX packaging failure

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T05:46:52Z |
| Candidate | S4MutatingExpectCompileCoder10 |
| RESULT | changes_requested |

- Human report: the build disappeared while processing with Canary Flash.
- Main verified that Canary Flash did not fail: `app.log` records segment 1/5
  transcription completing with 3382 characters at
  `2026-08-13 11:09:26.023`.
- macOS then reported PID 19828 terminated at `11:09:26.339`, immediately
  after source transcription and before a downstream result was persisted.
- `./script/build_and_run.sh --verify` had emitted
  `warning: mlx.metallib not found in cache. MLX text operations might crash.`
  The built app contains no `mlx.metallib`.
- MLX Swift 0.31.1 documents that command-line SwiftPM cannot build its Metal
  shaders. Its runtime first searches for colocated `mlx.metallib`, then
  bundled `default.metallib`, and throws if neither can be loaded.
- Root fix: make the fresh-app build deterministically produce or bundle the
  required MLX Metal library and fail the build if that artifact is absent.
  Do not rely on one hard-coded cache path and do not ship a warning-only app.
- Reviewer and Tester did not run. Route the changed candidate through Main
  build/runtime verification and Human acceptance first.

### S4 changed candidate 10 — Main metallib build-path failure

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T06:02:28Z |
| Candidate | S4MLXMetallibCoder11 |
| RESULT | changes_requested |

- Coder replaced the hard-coded cache probe with the pinned MLX checkout's
  official CMake Metal target and hard-failure checks.
- Main ran `./script/build_and_run.sh --verify`.
- CMake compiled the complete official kernel set and reported
  `Built target mlx-metallib`.
- The script then exited 1 because it expected
  `.build/mlx-metallib/kernels/mlx.metallib`.
- The real generated artifact is
  `.build/mlx-metallib/mlx/backend/metal/kernels/mlx.metallib`.
- This is a new, exact objective-gate failure. Required repair is limited to
  deriving or checking the real CMake output path without weakening any hard
  failure, copy-integrity, signing, or launch behavior.
- The app was not launched. Reviewer, Tester, and Human acceptance did not run.

### S4 changed candidate 11 — Main metallib runtime verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T06:13:04Z |
| Candidate | S4MLXOutputPathCoder12 |
| RESULT | waiting_human_acceptance |

- The exact candidate 10 output-path mismatch was repaired; no other candidate
  behavior changed.
- `./script/build_and_run.sh --verify`: **PASS**. The pinned MLX 0.31.1
  checkout's official CMake target compiled the complete kernel set and linked
  `mlx.metallib`; the signed arm64 app launched.
- The generated file, `Contents/MacOS/mlx.metallib`, and
  `Contents/Resources/mlx.metallib` have the identical SHA-256
  `a97b9b2bd352af9b6281bc29a207a1edc440ca3e96776d81321346ee815a6e35`.
- `/usr/bin/codesign --verify --deep --strict dist/VaniScript.app`: **PASS**.
- Focused S4 gate: **PASS**, 45 tests in five suites.
- Full `swift test`: **PASS**, 411 tests in 56 suites.
- Main attached LLDB to the packaged app process and evaluated a real MLX array
  operation. `(MLXArray([1, 2, 3]) + 1).asArray(Float.self)` returned
  `[2, 3, 4]`. This directly proves that the packaged executable can find and
  load the Metal library at the prior crash boundary.
- Main ended the debug session and opened a clean candidate process, PID 32591.
- Human acceptance remains required on the same meaningful-speech Canary Flash
  plus local-MLX translation scenario. Reviewer and Tester have not run.

### S4 candidate 11 — Human accepted; Tester explicitly skipped

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T08:03:06Z |
| Candidate | S4MLXOutputPathCoder12 |
| RESULT | accepted |

- Human repeated meaningful-speech processing with Canary Flash and confirmed
  that transcription works and the application remains stable.
- Human noted poor Sanskrit recognition across the tested models, but explicitly
  classified that as model quality rather than a VaniScript defect; Whisper
  Large V3 currently gives the best result for this material.
- Human requested one quick code-review pass.
- Human explicitly opted out of the S4 Tester pass to avoid spending additional
  time and tokens. Main's 45 focused tests, all 411 tests, signed fresh-app
  build, packaged MLX operation, and Human runtime test remain the QA evidence.
- Reviewer is authorized on this unchanged accepted candidate. No Tester will
  be launched.

### S4 candidate 11 — Reviewer changes requested

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T08:13:49Z |
| Candidate | S4MLXOutputPathCoder12 |
| Reviewer | S4AcceptedCandidateReviewer1 |
| VERDICT | changes_requested |

- Main verified the first finding in real source. `ChatSidebarView` invokes
  `NativeModelCatalog.activeLocalASRModel` from `onAppear` and the record
  button, and `WorkflowStore.transcribeDictation` repeats it on `@MainActor`.
  For Canary 1B, that path reaches `isRemotePackagePresent`, which hashes every
  allowlisted file, including the large encoder. `AppSettings` already exposes
  `isDownloadedLocalASRModelActive` as the cheap persisted-state/UI predicate;
  the actor-isolated router remains the authoritative integrity gate.
- Main verified the second finding. `NativeProcessingPipeline` unloads ASR only
  inside its two local-translation branches. Direct `WorkflowStore` calls to
  `reviewMLXEngine`, `documentMLXEngine`, and `shortsMLXEngine` lack an ASR
  release preflight, and transcription provider/local-ASR path changes do not
  explicitly invalidate the resident engine.
- Required fix: use the cheap predicate only for dictation presentation and
  early UX, preserve authoritative router validation, release resident ASR
  before every direct local-MLX workload, and invalidate it on ASR provider or
  configured path/state changes while preserving same-binding reuse.
- The accepted candidate is invalidated. After the changed candidate passes
  Main gates it returns to Human acceptance and a fresh Reviewer verdict.
  Human's explicit Tester opt-out remains recorded.

### S4 changed candidate 12 — lifecycle fixes pass; full-suite test race

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T08:47:14Z |
| Candidate | S4LifecycleReviewerFixCoder13 |
| RESULT | changes_requested |

- Main verified the two requested product fixes in source. Dictation now uses
  `isDownloadedLocalASRModelActive` for its cheap UI predicate while the router
  retains authoritative integrity validation. WorkflowStore releases resident
  ASR before review, document, and Shorts MLX paths and invalidates it after
  local-ASR provider or state/path changes.
- The new lifecycle test passed and observed `asr-unload` immediately before
  review translation, document formatting, and Shorts planning, plus an unload
  after an ASR path change. Existing router reuse/path-change coverage passed
  in its isolated suite.
- `swift build` passed.
- The combined focused run and `swift test` each exposed an existing
  process-global `LocalModelVerification.skipVerificationForTesting` race.
  One suite resets the flag to `false` while `LocalASREngineRouterTests` is
  resolving an empty-directory fixture, causing intermittent
  `unsupportedModel("no complete active local ASR binding ...")`. The isolated
  `WorkflowStoreLocalModelTests` rerun passed all 8 tests, including the new
  lifecycle test; the full run completed 413 tests with this one race failure.
- Required repair is test-isolation only: remove cross-suite mutation/reset
  races without weakening production integrity validation or router behavior.
  Human acceptance and Reviewer remain blocked until the full suite is green.

### S4 changed candidate 13 — deterministic lifecycle gates green

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T08:54:37Z |
| Candidate | S4VerificationFlagIsolationCoder14 |
| RESULT | waiting_human_acceptance |

- The test-only repair established one convention for
  `LocalModelVerification.skipVerificationForTesting`: all seven fixture suites
  enable it and no suite resets the process-global value while another suite is
  running. Production still defaults to full integrity validation.
- Corrected focused gate passed 27 tests across WorkflowStore lifecycle,
  NativeProcessingPipeline ASR, LocalASREngineRouter, and Universal settings.
- `swift build` passed.
- Two consecutive `swift test` runs passed all 413 tests in 56 suites.
- `./script/build_and_run.sh --verify` rebuilt the signed app, compiled and
  bundled the pinned MLX `mlx.metallib`, opened the fresh candidate, and Main
  confirmed PID 77328 running from `dist/VaniScript.app`.
- Human acceptance must repeat meaningful-speech Canary Flash transcription
  plus one local-MLX operation. Reviewer and Tester have not run on this changed
  candidate; the prior explicit Tester opt-out remains in force.

### S4 candidate 13 — Human rejected shared MLX catalog state

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T09:43:50Z |
| Candidate | S4VerificationFlagIsolationCoder14 |
| RESULT | changes_requested |

- Human acceptance found the previously used Qwen 3.5 4B entry displayed as
  `Fixture MLX`, making the installed model appear to have been replaced.
- Main verified the exact contamination path: the lifecycle test constructs
  `qwen35-4b-4bit` with label `Fixture MLX`, while injected `WorkflowStore`
  settings still use production `SettingsDiskStore.save`. The persisted user
  settings now contain that label and the test fixture location.
- The complete shared Qwen 3.5 4B MLX snapshot exists under
  `AI_LOCAL_MODELS/mlx/Direct`, and the app log records it being discovered and
  used as `qwen35-4b-4bit`. This is a catalog-label/test-persistence defect, not
  a missing 4B package.
- BOLABOL's active model is the same stable ID, `qwen35-4b-4bit`, with canonical
  display name `Qwen 3.5 4B 4-bit` and the same
  `mlx-community/Qwen3.5-4B-4bit` repository. VaniScript must use those
  canonical labels and continue discovering BOLABOL's shared Direct layout.
- The Nemotron snapshot directory is empty, so it must remain unavailable until
  a complete package is downloaded. The `parakeet` directory is the runtime
  container for the single `parakeet-tdt-0.6b-v3` catalog model, not a second
  Parakeet model.
- Required repair: prevent injected/test stores from writing production
  settings, normalize supported model labels/runtime metadata from the catalog
  without changing valid user selections, and add regression coverage for the
  BOLABOL/Hugging Face Direct snapshot layout.
- Candidate 13 is invalidated. Reviewer remains blocked until the repair passes
  Main verification, a fresh app rebuild, and Human acceptance.

### S4 changed candidate 14 — shared MLX repair compile rejection

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T10:06:23Z |
| Candidate | S4SharedMLXCatalogCoder15 |
| RESULT | changes_requested |

- The repair added the intended persistence seam, canonical model metadata,
  Direct-layout scan coverage, and strict scan verification without running
  validation as assigned.
- Main's SourceKit diagnostic rejected
  `NativeModelCatalog.settingsRuntime(for:)`: its switch over
  `SharedModelRuntime` omits `.gguf` and `.ggml` and is not exhaustive.
- No build or tests ran after this deterministic compile failure. Required fix
  is limited to making the runtime mapping exhaustive without assigning either
  unsupported runtime to a local ASR/MLX settings runtime.

### S4 changed candidate 15 — persistence seam test expectation stale

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T10:09:49Z |
| Candidate | S4SharedMLXCompileFixCoder16 |
| RESULT | changes_requested |

- Main verified SourceKit diagnostics green after the exhaustive runtime fix.
- The 35-test shared-model focused gate passed, `swift build` passed, and the
  production `settings.json` checksum remained unchanged across the focused
  test run, directly confirming fixture settings no longer leak.
- Full `swift test` ran 415 tests and failed one source-contract assertion:
  `AppStoreNativeComplianceTests` still requires the obsolete direct text
  `SettingsDiskStore.save(workflow.settings)`.
- Production now intentionally persists onboarding through the injected
  `settingsPersistence` seam, which defaults to `SettingsDiskStore.save`; the
  test must assert that seam rather than force the superseded direct call.

### S4 changed candidate 16 — shared MLX catalog repair green

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T10:28:06Z |
| Candidate | S4ComplianceSeamTestCoder17 |
| RESULT | waiting_human_acceptance |

- Known local model labels and runtimes now normalize from the canonical
  catalog while preserving valid install state and the user's selected
  translation provider. Qwen labels exactly match BOLABOL's `4-bit` spelling.
- `WorkflowStore` production persistence still defaults to
  `SettingsDiskStore.save`; injected test stores use explicit isolated
  persistence. Ordered asynchronous saves remain intact.
- Scanner results and scan merges use canonical catalog metadata. The new
  regression fixture mirrors BOLABOL/Hugging Face
  `mlx/Direct/models--mlx-community--Qwen3.5-4B-4bit/snapshots/<revision>` and
  rejects an empty Nemotron snapshot even when another suite enables the
  process-global verification bypass.
- Main's focused shared-model gate passed 35 tests across
  `WorkflowStoreLocalModelTests`, `SharedModelsRootTests`, and
  `NativeModelCatalogTests`. The production `settings.json` SHA-256 remained
  `6cf0e03db3033d86082e4837b4c869380c190694b838f6a0c8b8ad1e13e059d9`
  before and after the focused tests.
- `swift build` passed. The focused App Store compliance suite passed 54 tests.
  Full `swift test` passed all 415 tests in 56 suites; the production-settings
  checksum again remained unchanged.
- `./script/build_and_run.sh --verify` rebuilt, signed, and opened the fresh app
  as PID 97382. On load, stale `Fixture MLX` became
  `Qwen 3.5 4B 4-bit` without changing the valid active provider.
- The live startup scan completed with eight models found: six ASR and two MLX
  translation packages. It repaired Qwen 3.5 4B to the complete shared path
  `mlx/Direct/models--mlx-community--Qwen3.5-4B-4bit/snapshots/main`;
  Qwen 2B is also connected. Nemotron remains `not_downloaded` because its
  snapshots directory is empty.
- Human acceptance should confirm the Models screen shows
  `Qwen 3.5 4B 4-bit` instead of `Fixture MLX`; Reviewer remains blocked until
  the unchanged candidate is accepted. The prior explicit Tester opt-out
  remains in force.

### S4 candidate 16 — Human rejected blank MLX translation

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T11:15:51Z |
| Candidate | S4ComplianceSeamTestCoder17 |
| RESULT | changes_requested |

- Human acceptance confirmed that transcription is fast and correct and
  `Qwen 3.5 4B 4-bit` is present, selected, and actually invoked, but the
  translated field remains completely blank.
- Main verified two identical runtime reproductions in `app.log`. In each run,
  MLX cue batches one and two returned 2192 and 1836 sanitized characters.
  Batch three returned nine raw characters and zero sanitized characters, then
  raised `MLX returned no usable translation text`.
- `MLXTextGenerationEngine.translateCues` accumulates successful batches only
  in a local array and throws when a later batch is empty.
  `NativeProcessingPipeline.translateCurrentChunkIfNeeded` catches that error
  for the whole chunk and explicitly writes `translated = ""`, so all earlier
  successful batch output is lost.
- Required repair: retain timed-cue alignment and every successful batch,
  recover a failed/empty batch with a bounded smaller-input fallback, and never
  report success with an empty translation. Cover the exact late-batch failure
  deterministically without loading a real model.
- Candidate 16 is invalidated. Reviewer remains blocked until the changed
  candidate passes focused tests, `swift build`, `swift test`, a fresh app
  launch, and Human translation acceptance. The existing Tester opt-out remains
  recorded.

### S4 changed candidate 17 — MLX recovery test compile rejection

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T11:27:06Z |
| Candidate | S4MLXBatchRecoveryCoder18 |
| RESULT | changes_requested |

- Product code introduced bounded binary-split recovery for only the failed cue
  batch and a deterministic generation seam; parser validation rejects empty
  and source-equivalent cue output.
- Main's first focused test command failed at compile time in
  `NativeProcessingPipelineASRTests`: Swift could not type-check the inline
  six-cue fixture, then could not infer key-path and CharacterSet contexts.
- Required repair was test-only: explicit typed fixture/intermediate values,
  with no removal or weakening of output, timing, and request-bound assertions.

### S4 changed candidate 18 — bounded recovery expectation rejected

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T11:37:40Z |
| Candidate | S4MLXBatchRecoveryCompileCoder19 |
| RESULT | changes_requested |

- Main verified the compile repair: both focused suites built and 23 of 24 tests
  passed. The exact late-empty-batch recovery, single-cue terminal failure, and
  source-text rejection tests passed.
- The remaining 2n-1 bound test executed all seven requests correctly but its
  expected source lengths were wrong. The four source strings have character
  counts `3, 3, 5, 4`; therefore the observed binary tree is
  `[15, 6, 3, 3, 9, 5, 4]`, not `[12, 6, 3, 3, 6, 3, 3]`.
- Required repair is one test-only correction to the exact expected character
  lengths. Product behavior and assertions remain unchanged.

### S4 changed candidate 19 — bounded MLX cue recovery green

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T11:41:16Z |
| Candidate | S4MLXRecoveryAssertionCoder20 |
| RESULT | waiting_human_acceptance |

- `MLXTextGenerationEngine.translateCues` now retains successful cue batches
  and retries only a failed batch through a bounded binary split. A failed
  single-cue leaf throws; it never returns partial success, source text, or an
  empty aggregate.
- The parser validates complete nonempty output aligned to each source cue and
  preserves the source cue's start/end timing and order.
- Deterministic generation-seam coverage reproduces the Human's exact shape:
  two successful 1400-character batches, one nine-character sentinel-only
  response that sanitizes empty, then two successful 700-character recovery
  leaves. The result contains all six translated cues and exactly five
  generation requests.
- Focused `NativeProcessingPipelineASRTests|NativeLLMPromptTests` passed all 24
  tests. `swift build` passed. Full `swift test` passed all 419 tests in 56
  suites.
- `./script/build_and_run.sh --verify` rebuilt, signed, and opened the fresh
  candidate as PID 11770.
- Human acceptance must retry translation of the existing meaningful-speech
  project with `Qwen 3.5 4B 4-bit` and confirm the translated field is populated.
  Reviewer remains blocked until this unchanged candidate is accepted; the
  prior explicit Tester opt-out remains in force.

### S4 candidate 19 — Human rejected terminal single-cue sentinel

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T12:30:18Z |
| Candidate | S4MLXRecoveryAssertionCoder20 |
| RESULT | changes_requested |

- Human retest of the fresh candidate again left the translated field blank.
- Fresh runtime evidence proves candidate 19's binary recovery executes. The
  first two batches return 2192 and 1836 sanitized characters; the failed third
  batch splits repeatedly. One recovery branch returns 347 characters, while
  the remaining branch and its single-cue leaf return only the nine-character
  `<<<END>>>` sentinel and sanitize to empty.
- The terminal single-cue throw still rejects the complete `translateCues`
  call. `NativeProcessingPipeline` catches that error and writes an empty
  translation, so valid translated cues remain invisible.
- Required repair: use a distinct bounded terminal strategy for one failed cue
  rather than repeating the same cue-XML request, preserve every valid cue
  result, and never fill a missing cue with source text or report a blank
  translation as success. Test the exact mixed recovery tree deterministically.
- At Human request, the primary `workflow_coder` alias is now
  `google-antigravity/gemini-3.6-flash:high`; the next fresh Coder run uses that
  configured primary model. This is a manual primary-alias change, not backup
  failover.

### S4 changed candidate 20 — distinct terminal MLX recovery green

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T12:36:55Z |
| Candidate | S4MLXTerminalRecoveryGemini21 |
| RESULT | waiting_human_acceptance |

- The Gemini 3.6 Flash Coder added a distinct single-cue terminal strategy. If
  the normal XML request sanitizes empty, the same cue receives one plain-text
  request with `<<<TRANSLATION>>>...<<<END>>>`, not another XML retry.
- Terminal output is accepted only when nonempty and not source-equivalent.
  Reassembly preserves all prior successful batches, exact cue order, and
  source timings. Terminal failure stays explicit; no cloud/source-text/partial
  fallback exists.
- Deterministic coverage reproduces the real mixed tree and confirms six total
  requests: five XML requests plus one distinguishable terminal request.
  Separate failure coverage proves the terminal path remains finite.
- Focused `NativeProcessingPipelineASRTests|NativeLLMPromptTests` passed all 29
  tests. `swift build` passed. Full `swift test` passed all 424 tests in 56
  suites.
- `./script/build_and_run.sh --verify` rebuilt, signed, and opened the fresh app
  as PID 17849.
- Human acceptance must retry the same meaningful-speech Qwen 3.5 4B
  translation and confirm a substantive translated field. Reviewer remains
  blocked until this unchanged candidate is accepted; the prior explicit Tester
  opt-out remains in force.

### S4 candidate 20 — Human accepted

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T12:49:41Z |
| Candidate | S4MLXTerminalRecoveryGemini21 |
| RESULT | accepted |

- Human repeated the same meaningful-speech Qwen 3.5 4B translation that had
  produced a blank field in candidates 16 and 19.
- Candidate 20 populated the translated field and was explicitly accepted.
- Candidate source is unchanged since Main's focused 29-test gate,
  `swift build`, full 424-test suite, and fresh signed app launch as PID 17849.
- One independent Reviewer pass is authorized for this accepted candidate.
  The prior explicit S4 Tester opt-out remains in force.

### S4 candidate 20 — Reviewer changes requested

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T12:59:24Z |
| Candidate | S4MLXTerminalRecoveryGemini21 |
| Reviewer | S4AcceptedGeminiCandidateReviewer22 |
| VERDICT | changes_requested |

- **Critical — partial cue fabrication:** `NativeLLMPromptBuilder` accepts
  incomplete-ID or unstructured MLX batch output and proportionally splits its
  words across every source cue. This can turn one translated cue into false
  timed output for the whole batch. Require a complete unique cue-ID mapping;
  reject missing, duplicate, partial, and unstructured batch responses.
- **High — retries operational failures:** `MLXTextGenerationEngine` catches
  every non-cancellation error and enters binary recovery. Model-load,
  filesystem, timeout, and unknown errors must propagate after one request;
  only explicit cue-output validation errors are recoverable.
- **Critical — blank review-ready error:** `NativeProcessingPipeline` clears
  translated text but leaves the chunk `.done` after terminal MLX failure.
  `WorkflowStore` then opens Review and announces readiness. Preserve the source
  transcript, mark `.error`, retain a nonblank failure state, and do not report
  ready-for-review.
- **Medium — marker case mismatch:** marker detection is case-insensitive but
  extraction uses case-sensitive ranges. Use one case-insensitive boundary
  parser and reject malformed/unpaired markers; sentinel text must never enter
  a cue.
- **High — Parakeet whole-chunk flattening:** a nonempty Parakeet result without
  token timings returns `cues: nil`, and the pipeline converts it to one cue
  spanning the full planned chunk. Produce bounded review cues from available
  segmentation or fail explicitly; never flatten a long transcript into one
  full-chunk cue.
- Main rebuilt the stale Graphify code graph after the verdict. Candidate 20 is
  invalidated despite prior Human runtime acceptance. The changed candidate
  must pass Main gates and return through Human acceptance before one fresh
  Reviewer pass. The prior Tester opt-out remains in force.

### S4 changed candidate 21 — Reviewer repair rejected by Main

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T13:07:46Z |
| Candidate | S4ReviewerFindingsGeminiCoder23 |
| RESULT | changes_requested |

- Source inspection confirmed the repair addresses the five Reviewer areas in
  principle, but the candidate is not executable evidence.
- Focused compilation failed before tests:
  `NativeProcessingPipelineASRTests` constructs `AppSettings`, `SessionState`,
  and `ChunkData` with nonexistent defaults; `WorkflowStoreLocalModelTests`
  repeats those constructor errors, uses nonexistent `.importMedia`, and calls
  nonexistent `finishCurrentChunkProcessing`.
- The untimed Parakeet segmentation also does not enforce its claimed
  five-second bound. It clamps each nonfinal cue but forces the last cue to
  `endSec`; sparse text or a long residual window can still produce one
  full-chunk or oversized final cue.
- Required repair: use real domain initializers and a real public
  `WorkflowStore` processing path with its injected pipeline; add an observable
  store regression without product-only test hooks. Split untimed text/timeline
  so every cue is bounded, including sparse text and the final interval, while
  preserving all text exactly once. Add assertions for maximum duration and no
  full-chunk cue when the request window exceeds that maximum.

### S4 changed candidate 22 — repeated test API compile failure

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T13:13:05Z |
| Candidate | S4ReviewerFindingsCompileGeminiCoder24 |
| RESULT | changes_requested |

- The Parakeet source now removes final-cue stretching and caps every emitted
  cue duration at five seconds. Main's source inspection accepted that bounded
  timing correction pending executable tests.
- SourceKit still rejects the changed tests before execution. Both pipeline and
  store tests use nonexistent `AppSettings.sourceLang` / `.targetLang`; the
  real fields are `defaultSourceLang` / `defaultTargetLang`.
- The store test also uses nonexistent `settings.localModels` and
  `LocalModelRuntime.nativeMLX`; the real translation collection is
  `localTranslationModels` and its runtime is `.mlx`.
- This is the second materially same test-compilation failure. One focused,
  mechanical API correction remains before the retry guard stops the approach.

### S4 changed candidate 23 — focused behavior failures

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T13:16:06Z |
| Candidate | S4ReviewerTestAPIGeminiCoder25 |
| RESULT | changes_requested |

- SourceKit diagnostics are clean for the corrected store test; the pipeline
  test has only a nonblocking immutable-variable warning.
- The focused run compiled and executed 58 tests, then failed with five issues.
- `extractMarkerBody` accepts duplicate `<<<END>>>` markers by taking the first
  close and ignoring the second, so sentinel leakage/malformed-boundary
  rejection is incomplete.
- The preexisting pipeline mapping assertion still expects the removed
  full-30-second text-only fallback. It must assert the new bounded cue and
  word timing contract instead.
- The new MLX pipeline failure test never reaches MLX because local ASR
  readiness fails. Configure a real installed test ASR descriptor and injected
  deterministic ASR router/result, plus the installed translation model, so
  the assertion observes the intended translation-failure path rather than a
  readiness error.

### S4 changed candidate 24 — one focused fixture failure remains

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T13:20:14Z |
| Candidate | S4ReviewerBehaviorGeminiCoder26 |
| RESULT | changes_requested |

- Marker cardinality and the bounded text-only fallback now pass.
- The rerun reduced the focused gate from five issues to one: 57 of 58 tests
  pass.
- The remaining MLX failure test incorrectly calls the ASR-only
  `NativeModelCatalog.descriptor(for:)` with `qwen35-4b-4bit`, yielding `nil`
  before the behavior executes.
- Required fixture correction: use the known MLX ID directly, mark its existing
  `AppSettings.defaults.localTranslationModels` entry downloaded with a test
  path, and retain the injected ASR/MLX execution and assertions.

### S4 changed candidate 25 — ASR fixture still blocks MLX test

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T13:22:11Z |
| Candidate | S4MLXTestFixtureGeminiCoder27 |
| RESULT | changes_requested |

- The MLX catalog fixture is corrected, but the focused gate still reports one
  failed test (four assertions); the other 57 tests pass.
- The test chooses Parakeet with an empty directory. Its package-layout
  readiness correctly rejects the fixture before the injected router or MLX
  override runs.
- Use the existing passing pipeline-test pattern:
  `whisper-small-multilingual` with testing verification bypass and the same
  injected router result. Preserve the MLX model setup and all assertions.
- This is the second materially same fixture/readiness failure. A further
  failure of the same approach reaches the automatic retry limit.

### S4 changed candidate 26 — fixture retry guard triggered

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T13:23:58Z |
| Candidate | S4ASRFixtureGeminiCoder28 |
| RESULT | blocked |

- Switching to the known Whisper descriptor cleared model readiness, but the
  test still fails before the injected ASR call. The pipeline reports
  `Native segment processing failed: The operation could not be completed`;
  the MLX request count remains zero.
- Main traced the remaining distinction from the suite's direct-router test:
  this end-to-end path performs audio preprocessing, while the fixture writes
  a one-byte fake `.wav`. Existing engine/preprocessor tests create valid CAF
  audio with `AVAudioFile`.
- Three consecutive fixture attempts have failed to reach the intended MLX
  path. Automatic Coder retries stop here. One bounded Architect advisory is
  routed to define the smallest new executable approach; no product edit is
  authorized.

### S4 fixture Architect advisory — valid audio is the new approach

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T13:29:31Z |
| Run | S4MLXFailureFixtureArchitect29 |
| Mode | advisory |
| RESULT | advice_ready |

- Root cause confirmed: `AudioChunkExporter` must load and export the test
  source before the injected ASR router runs; a one-byte `.wav` cannot satisfy
  that path.
- New approach: write an exact two-second, 16 kHz, mono Float32 LinearPCM WAV
  using `AVAudioFile` and `AVAudioPCMBuffer` (32,000 frames), matching the
  existing `ChunkData` duration. Keep router, MLX override, and assertions
  unchanged.
- This is materially different evidence and clears the retry guard for one
  focused Coder repair.

### S4 changed candidate 27 — valid fixture exposes false ready report

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T13:32:16Z |
| Candidate | S4ValidAudioFixtureGeminiCoder30 |
| RESULT | changes_requested |

- The new valid WAV approach works: the focused 58-test gate passes and the
  trace proves export, injected Whisper ASR, ASR release, and terminal MLX
  failure all execute.
- Main then inspected the successful trace and found a remaining Reviewer
  contract violation: after MLX marks the chunk `.error`,
  `processCurrentChunk` unconditionally logs and emits
  `Segment … is ready for review.` Both cloud-ASR and local-ASR branches share
  this false-success behavior.
- Required source fix: after `translateCurrentChunkIfNeeded`, branch on the
  chunk status. Error must emit the existing nonblank failure and return
  without any ready-for-review log/progress; only a non-error chunk may emit
  readiness. Extend the executable integration test to capture progress and
  prove no ready message.

### S4 changed candidate 29 — Main gates green, awaiting Human retest

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T13:41:43Z |
| Candidate | S4ReviewerFindingsCandidate29 |
| RESULT | waiting_human_acceptance |

- All five candidate-20 Reviewer findings are repaired:
  strict complete/unique MLX cue IDs; recovery only for explicit output
  validation; terminal translation `.error` with no false ready report;
  case-insensitive well-formed marker boundaries; and bounded untimed Parakeet
  cues with no whole-chunk flattening.
- Focused gate: 74 tests in 6 suites passed.
- `swift build` passed.
- Full gate: 437 tests in 56 suites passed.
- The real integration fixture exported a two-second WAV, reached the injected
  Whisper ASR, released ASR, invoked MLX, preserved source text/cues on terminal
  MLX failure, emitted explicit failure progress, and emitted no
  ready-for-review message.
- `./script/build_and_run.sh --verify` rebuilt and opened the signed app.
  Process PID 32320 is running. Fresh startup scan found 8 local models
  (6 ASR, 2 translation).
- Final cleanup changed only an immutable test local from `var` to `let`; its
  10-test pipeline suite passed with no introduced warning.
- Human must now repeat the meaningful-speech Qwen 3.5 4B translation. A fresh
  Reviewer pass is blocked until this unchanged candidate is accepted. The
  prior explicit Tester opt-out remains in force.

### S4 candidate 29 — Human rejected terminal continuation regression

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T14:14:59Z |
| Candidate | S4ReviewerFindingsCandidate29 |
| RESULT | changes_requested |

- Human screenshot shows `Transcription Failed: MLX translation failed: MLX
  returned no usable translation text.`
- Two meaningful-speech attempts produced the same deterministic trace. Each
  translated the first two batches (2192 and 1836 sanitized characters), then
  followed bounded recovery and failed on the terminal single-cue output.
- Candidate 20 previously completed this exact source/model run. Its terminal
  parser accepted generation output containing translated continuation text
  followed by `<<<END>>>`.
- Root cause: `singleCueTerminalTranslationPrompt` already ends with
  `<<<TRANSLATION>>>`, so MLX generation returns only the continuation body and
  closing `<<<END>>>`. Candidate 29's strict parser now requires the opening
  marker to be repeated inside generated output and rejects the valid
  continuation. This also explains why the same 68-character terminal output
  completed candidate 20 but fails candidate 29.
- Required bounded repair: explicitly support the typed prompt-prefixed
  continuation contract (one nonempty body plus exactly one closing marker),
  while retaining strict rejection of duplicate closers, unknown sentinels,
  empty/source-equivalent text, malformed full envelopes, and sentinel leakage.
  Do not restore batch fabrication or broaden sanitizer behavior.

### S4 changed candidate 30 — focused terminal envelope test failed

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T14:18:43Z |
| Candidate | S4TerminalContinuationGeminiCoder33 |
| RESULT | changes_requested |

- The terminal parser now correctly models full envelopes and prompt-prefixed
  continuation output; LSP diagnostics are clean and its direct parser tests
  pass.
- Main's 38-test prompt/pipeline gate found one failure:
  `recoversSingleCueXMLFailureThroughTerminalStrategy` throws `emptyOutput`.
- Root cause: `MLXTextGenerationEngine.generate` globally sanitizes output
  before returning it. A full terminal envelope is reduced to plain body text
  before the strict terminal parser sees it, so the parser cannot distinguish
  valid structured output from unstructured model output.
- Required source fix: preserve raw generated text only for the distinct
  single-cue terminal call, while retaining existing sanitization for every
  other generation caller. The terminal parser then validates either the full
  envelope or the real prompt-prefixed continuation itself.

### S4 changed candidate 31 — terminal continuation repair green

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T14:22:57Z |
| Candidate | S4TerminalRawOutputCandidate31 |
| RESULT | waiting_human_acceptance |

- The terminal parser now explicitly accepts both valid shapes: a complete
  marker envelope, or generation continuation text followed by one
  case-insensitive `<<<END>>>` after the prompt supplied the opener.
- Duplicate/malformed/unknown sentinels, empty text, and source-equivalent text
  remain rejected. Strict complete cue-ID batch parsing is unchanged.
- Only `translateSingleCueTerminalWithRecovery` receives raw generated output.
  Every other MLX generation caller retains the existing sanitizer by default.
- Focused prompt/pipeline gate: 38 tests in 2 suites passed.
- `swift build` passed.
- Full gate: 438 tests in 56 suites passed.
- Graphify was refreshed. `./script/build_and_run.sh --verify` rebuilt, signed,
  and opened the fresh app as PID 38639.
- Human acceptance is limited to repeating the same meaningful-speech
  Whisper Large v3 + Qwen 3.5 4B translation once. Reviewer remains blocked
  until this unchanged candidate is accepted; the prior Tester opt-out remains
  in force.

### S4 candidate 31 — Human rejected marker-free terminal output

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T14:37:05Z |
| Candidate | S4TerminalRawOutputCandidate31 |
| RESULT | changes_requested |

- Human reported the same `MLX returned no usable translation text` error.
- Fresh candidate-31 trace reached the terminal request at prompt length 1259,
  received seven raw characters, and failed immediately.
- The Human-accepted candidate-20 trace reached the same prompt length 1259,
  received the same seven-character marker-free result, accepted it, and
  continued translating later cues.
- Exact rejection branch: `extractSingleCueTerminalBody` requires one
  `<<<END>>>` even when generated output contains no sentinel at all. Qwen can
  return a plain terminal translation despite the requested marker contract.
- Required bounded repair: accept nonempty marker-free terminal text as a third
  valid terminal shape, then apply the existing target-language sanitation and
  source-equivalence checks. If any sentinel is present, retain strict envelope
  or continuation validation. Batch parsing and recovery routing remain
  unchanged.

### S4 changed candidate 32 — marker-free terminal output restored

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T14:41:58Z |
| Candidate | S4MarkerFreeTerminalCandidate32 |
| RESULT | waiting_human_acceptance |

- Candidate 31 exposed the exact remaining compatibility shape: Qwen returned
  seven nonempty raw characters with no sentinel. Candidate 20 had accepted
  the same prompt-length/output-length shape and continued.
- `extractSingleCueTerminalBody` now accepts marker-free terminal text only
  when opener, closer, and total sentinel counts are all zero. Any sentinel
  still requires the strict full-envelope or `body + <<<END>>>` validation.
- Existing sanitation, target-language reasoning rejection, nonempty
  validation, and source-equivalence rejection still run after extraction.
  Batch cue-ID parsing, MLX recovery routing, and pipeline failure status are
  unchanged.
- Main verified clean LSP diagnostics for both changed files.
- Focused prompt/pipeline gate: 39 tests in 2 suites passed.
- `swift build` passed.
- Full gate: 439 tests in 56 suites passed.
- Graphify was refreshed. `./script/build_and_run.sh --verify` rebuilt, signed,
  and opened candidate 32 as PID 42708.
- Human acceptance is limited to repeating the same meaningful-speech
  Whisper Large v3 + Qwen 3.5 4B translation. Reviewer remains blocked until
  this unchanged candidate is accepted; the prior Tester opt-out remains in
  force.

### S4 candidate 32 — Human rejected malformed terminal END fence

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T15:04:04Z |
| Candidate | S4MarkerFreeTerminalCandidate32 |
| RESULT | changes_requested |

- Human reported the same visible `MLX returned no usable translation text`
  failure.
- The candidate-32 trace proves the marker-free repair worked: recovery passed
  the prior prompt-length 1259 response and continued through several later
  terminal requests before failing at prompt length 1253 with 68 raw
  characters.
- Main attached LLDB to the unchanged packaged candidate, reprocessed the same
  current segment, and stopped immediately before terminal parsing. The exact
  raw shape was one valid `<<<TRANSLATION>>>` opener, a nonempty Russian
  translation body, and the suffix `>>>END>>`.
- Exact rejection branch: `extractSingleCueTerminalBody` sees one recognized
  opener but no canonical `<<<END>>>`, so it rejects before sanitation. This
  is distinct from candidate 31's marker-free output.
- Required bounded repair: recognize one unambiguous END-like fence only when
  it is the sole terminal suffix after one valid opener, normalize it for body
  extraction, and retain rejection of missing/embedded/duplicate END-like
  fences, unknown sentinels, malformed openers, leaked markers, empty output,
  and source-equivalent output. Batch parsing and MLX recovery routing remain
  unchanged.

### S4 changed candidate 33 — terminal END fence typo recovered

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T15:16:07Z |
| Candidate | S4MalformedEndFenceCandidate33 |
| RESULT | waiting_human_acceptance |

- LLDB on the packaged candidate 32 process captured the exact remaining
  failure shape: source cue `So therefore whatever transpires is also good.`,
  raw `<<<TRANSLATION>>> Поэтому всё, что произойдет, тоже хорошо. >>>END>>`
  (68 characters). Marker-free acceptance from candidate 32 had already moved
  the failure later in the same segment.
- `extractSingleCueTerminalBody` now accepts one bounded END-like fence only
  when there is exactly one recognized opener, zero canonical closers, exactly
  one END-like suffix match ending at the trimmed string end, and no unknown
  exact sentinel. Body extraction stays between opener and that suffix; the
  existing sanitation, leaked-marker, nonempty, and source-equivalence checks
  still run afterward.
- Marker-free acceptance now also requires zero END-like matches, so
  opener-free `>>END>>` / `>>>END>>` suffixes cannot bypass rejection.
- Exact captured-response regression plus opener-free, embedded, duplicate, and
  unknown-sentinel negatives were added. Batch cue-ID parsing, MLX recovery
  routing, and pipeline failure status are unchanged.
- Main verified clean LSP diagnostics for both changed files.
- Focused prompt/pipeline gate: 39 tests in 2 suites passed.
- `swift build` passed.
- Full gate: 439 tests in 56 suites passed.
- Graphify was refreshed. `./script/build_and_run.sh --verify` rebuilt, signed,
  and opened candidate 33 as PID 51362.
- Human acceptance is limited to repeating the same meaningful-speech
  Whisper Large v3 + Qwen 3.5 4B translation. Reviewer remains blocked until
  this unchanged candidate is accepted; the prior Tester opt-out remains in
  force.

### S4 candidate 33 — Human rejected empty terminal END-only reply

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T15:28:48Z |
| Candidate | S4MalformedEndFenceCandidate33 |
| RESULT | changes_requested |

- Human reported the same visible `MLX returned no usable translation text`
  failure.
- Candidate-33 log shows recovery progressed past the earlier malformed-END
  path, then failed at prompt length 1259 with only 7 raw characters and no
  sanitized body.
- Main attached LLDB to the packaged candidate, reprocessed the same current
  segment, and stopped immediately before terminal parsing. Exact capture:
  source cue `Hare Hare Hare Rama Hare Rama Rama Rama Hare Hare`, raw
  `<<END>>` (7 characters).
- Exact rejection branch: `parseSingleCueTerminalTranslationOutput` correctly
  rejects END-only/empty terminal output, and
  `translateSingleCueTerminalWithRecovery` has no second attempt. That throw
  aborts the whole segment, discarding any earlier successful cues.
- Required bounded repair: when a single-cue terminal leaf returns an empty
  END-only/empty-body shape, retry that same cue once with a stricter terminal
  prompt or generation settings; if the second attempt still yields empty
  output, keep the explicit failure. Do not invent a translation body, do not
  weaken marker validation, and do not change batch cue-ID parsing.

### S4 changed candidate 34 — empty terminal END-only retry restored

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T15:37:40Z |
| Candidate | S4EmptyTerminalRetryCandidate34 |
| RESULT | waiting_human_acceptance |

- LLDB on packaged candidate 33 captured the next exact failure: source cue
  `Hare Hare Hare Rama Hare Rama Rama Rama Hare Hare`, raw terminal output
  `<<END>>` (7 characters). The parser correctly rejected the empty body, but
  one terminal leaf abort discarded the whole segment.
- `translateSingleCueTerminalWithRecovery` now keeps the first raw terminal
  attempt unchanged. Only a parser `emptyOutput` path triggers exactly one
  second attempt with a stricter recovery prompt that forbids END-only answers
  and requires a nonempty target-language body.
- If the second attempt parses as a complete translation, it is kept. If it is
  still empty, the existing explicit `CueBatchTranslationError.emptyOutput`
  remains. Marker validation, fuzzy END recovery, marker-free acceptance, and
  batch cue-ID parsing are unchanged.
- Pipeline tests now cover first-empty/second-valid recovery with prior batch
  preservation, two empty terminal attempts that still fail explicitly, and the
  adjusted finite binary-split request counts.
- Main verified clean LSP diagnostics for both changed files.
- Focused prompt/pipeline gate: 39 tests in 2 suites passed.
- `swift build` passed.
- Full gate: 439 tests in 56 suites passed.
- Graphify was refreshed. `./script/build_and_run.sh --verify` rebuilt, signed,
  and opened candidate 34 as PID 56507. The previous LLDB-held candidate 33
  process was terminated so only this fresh app remains.
- Human acceptance is limited to repeating the same meaningful-speech
  Whisper Large v3 + Qwen 3.5 4B translation. Reviewer remains blocked until
  this unchanged candidate is accepted; the prior Tester opt-out remains in
  force.

### S4 candidate 34 — Human rejected double empty terminal END-only leaf

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T17:14:53Z |
| Candidate | S4EmptyTerminalRetryCandidate34 |
| RESULT | changes_requested |

- Human reported the same visible `MLX returned no usable translation text`
  failure.
- Candidate-34 logs show the new retry path is live: first terminal attempt at
  prompt length 1259 returned 7 raw characters, second attempt at prompt length
  1510 also returned 7 raw characters, then the segment failed.
- Main attached LLDB and captured both attempts for the same cue:
  source `Hare Hare Hare Rama Hare Rama Rama Rama Hare Hare`, first raw
  `<<END>>`, retry raw `<<END>>`. No translation body was present on either
  attempt.
- Exact rejection branch: both empty END-only leaves are correctly rejected by
  the terminal parser, and after the second empty attempt the whole
  `translateCues` call still aborts. Retry alone is insufficient when Qwen
  returns END-only twice for this mantra cue.
- Required bounded repair: after the existing first attempt and one empty
  retry both yield empty/END-only output, keep a non-blank leaf for that cue
  without inventing a free-form translation and without discarding earlier
  successful cues. Prefer a conservative source-preserving placeholder that
  remains reviewable and fails only if the entire segment has no usable
  translations. Marker validation and batch cue-ID parsing remain unchanged.

### S4 changed candidate 35 — empty terminal END-only leaf fallback restored

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T17:25:23Z |
| Candidate | S4EmptyTerminalFallbackCandidate35 |
| RESULT | waiting_human_acceptance |

- LLDB on packaged candidate 34 captured both attempts for the mantra leaf:
  first raw `<<END>>` (prompt length 1259), retry raw `<<END>>` (prompt length
  1510). Retry alone is insufficient when Qwen returns END-only twice.
- After the existing first terminal attempt and one empty retry both fail,
  multi-cue recovery now keeps a source-preserving fallback leaf with original
  timings/text instead of aborting the whole segment. Sibling real translations
  remain intact.
- Top-level `translateCues` still requires at least one real translated cue.
  Single-cue empties and all-empty multi-cue results still throw explicit
  `CueBatchTranslationError.emptyOutput`. Marker validation, fuzzy END
  recovery, marker-free acceptance, and batch cue-ID parsing are unchanged.
- Pipeline tests now cover double-empty fallback with prior batch preservation,
  all-empty explicit failure, adjusted finite binary-split recovery, and the
  previous retry recovery path.
- Main verified clean LSP diagnostics for both changed files.
- Focused prompt/pipeline gate: 40 tests in 2 suites passed.
- `swift build` passed.
- Full gate: 440 tests in 56 suites passed.
- Graphify was refreshed. `./script/build_and_run.sh --verify` rebuilt, signed,
  and opened candidate 35 as PID 68425.
- Human acceptance is limited to repeating the same meaningful-speech
  Whisper Large v3 + Qwen 3.5 4B translation. Reviewer remains blocked until
  this unchanged candidate is accepted; the prior Tester opt-out remains in
  force.

### S4 candidate 35 — Human accepted empty-leaf fallback path

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T17:49:02Z |
| Candidate | S4EmptyTerminalFallbackCandidate35 |
| RESULT | accepted |

- Human retested the same meaningful-speech Whisper Large v3 + Qwen 3.5 4B
  translation on the unchanged packaged candidate and reported that translation
  works.
- One fresh Reviewer pass is now authorized on this accepted candidate. The
  prior explicit Tester opt-out remains in force, so Tester is not launched
  after an APPROVED review.

### S4 candidate 35 — Reviewer changes_requested for trailing canonical END

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T17:54:52Z |
| Candidate | S4EmptyTerminalFallbackCandidate35 |
| RESULT | changes_requested |
| Reviewer | S4EmptyTerminalFallbackGeminiReviewer40 |

- Judgment Gate 1 failed. `extractSingleCueTerminalBody` accepts one canonical
  `<<<END>>>` without requiring `NSMaxRange(closeMatch.range) == nsText.length`.
- Consequence: a shape such as
  `<<<TRANSLATION>>>\\nvalid translation\\n<<<END>>>\\n<<<FOO>>` or ordinary
  trailing prose after END can pass and silently drop the suffix. The fuzzy
  END-like path already enforces terminal position; the canonical full-envelope
  and continuation paths do not.
- Gates 2–4 otherwise have source evidence: one empty terminal retry, multi-cue
  source-preserving fallback, all-empty explicit failure, strict batch cue-ID
  parsing, and scoped S4 terminal/recovery changes.
- Required bounded repair: require the sole canonical `<<<END>>>` to be the
  absolute trimmed suffix before extracting full-envelope or body+END
  continuation bodies. Add focused negatives for canonical END followed by
  trailing prose and by malformed/unknown marker fragments, for both opener
  envelope and opener-free continuation. Preserve all proven acceptance shapes.

### S4 changed candidate 36 — canonical END absolute suffix enforced

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T17:59:26Z |
| Candidate | S4CanonicalEndSuffixCandidate36 |
| RESULT | waiting_human_acceptance |

- Reviewer rejected candidate 35 because the canonical END path accepted one
  closer without requiring it to end the trimmed response, so trailing prose or
  malformed fragments after END could be silently discarded.
- `extractSingleCueTerminalBody` now requires
  `NSMaxRange(closeMatch.range) == nsText.length` immediately after selecting
  the sole canonical closer. This covers both full-envelope and opener-free
  continuation paths. Fuzzy END-like recovery and marker-free acceptance are
  unchanged.
- Focused negatives reject trailing prose and malformed trailing marker
  fragments after END for both envelope and continuation forms. Proven
  acceptance shapes remain: full envelope, body+END continuation, marker-free
  text, and the captured fuzzy `>>>END>>` suffix.
- Empty-terminal retry/fallback, batch cue-ID parsing, and recovery routing are
  unchanged.
- Main verified clean LSP diagnostics for both changed files.
- Focused prompt/pipeline gate: 41 tests in 2 suites passed.
- `swift build` passed.
- Full gate: 441 tests in 56 suites passed.
- Graphify was refreshed. `./script/build_and_run.sh --verify` rebuilt, signed,
  and opened candidate 36 as PID 72886.
- Human acceptance is required again because this is a changed candidate after
  Reviewer rejection. Reviewer remains blocked until acceptance; the prior
  Tester opt-out remains in force.

### S4 candidate 36 — Human accepted absolute END suffix path

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T18:05:48Z |
| Candidate | S4CanonicalEndSuffixCandidate36 |
| RESULT | accepted |

- Human retested the same meaningful-speech Whisper Large v3 + Qwen 3.5 4B
  translation on the unchanged packaged candidate and reported that translation
  works.
- One fresh Reviewer pass is now authorized on this accepted candidate. The
  prior explicit Tester opt-out remains in force, so Tester is not launched
  after an APPROVED review.

### S4 candidate 36 — Reviewer APPROVED

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T18:08:07Z |
| Candidate | S4CanonicalEndSuffixCandidate36 |
| RESULT | approved |
| Reviewer | S4CanonicalEndSuffixGeminiReviewer42 |

- All four Judgment Gates satisfied.
- Prior trailing-END finding is resolved: `extractSingleCueTerminalBody`
  requires the sole canonical `<<<END>>>` to end the trimmed response.
- Proven shapes remain accepted; trailing prose/malformed fragments after END
  remain rejected. Empty-terminal retry/fallback, batch cue-ID parsing, and
  recovery routing remain intact.
- Scope stayed inside the S4 MLX terminal/recovery path.

### S4 stop-gate complete

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T18:08:07Z |
| Candidate | S4CanonicalEndSuffixCandidate36 |
| RESULT | complete |

- Human ACCEPTED candidate 36.
- Reviewer APPROVED candidate 36.
- Tester remains explicitly skipped by prior Human opt-out; that opt-out
  satisfies the S4 stop-gate Tester term.
- S4 is complete. Next step is S5 — Models UI and local Canary 1B workflow.
- Awaiting Human direction before dispatching S5 Coder.

### Cloud multi-key + translation fallback — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T19:18:20Z |
| Candidate | CloudGeminiKeyRotationCandidate37 |
| RESULT | waiting_human_acceptance |

- Post-S4 Human-requested maintenance candidate for Gemini multi-key rotation and
  cloud translation reliability. Not an S5 Models UI implementation.
- Added `GeminiAPIKeyBank` (max 10 keys, `#DISABLED#` markers, primary-key sync)
  and wired Gemini transcription/translation/chat through enabled-key rotation.
- Rotation covers quota/`429` and capacity/`502-504`/`UNAVAILABLE` high-demand,
  with short backoff and a second pass over the key bank for transient capacity.
- Cloud cue translation no longer hard-fails when Gemini/OpenRouter omit the
  MLX `<<<BEGIN>>>` cue-XML envelope: freeform/timestamped parse falls back, then
  blob translate + realign. Failures now write an explicit provider error into the
  chunk instead of silent empty `done`.
- Settings UI exposes Add Key / enable-disable / Test Only Key N. ProviderRegistry
  and MCP readiness use enabled keys, not only the legacy primary string.
- Focused gates:
  - `GeminiAPIKeyBankTests` 7/7 PASS
  - `NativeLLMPromptTests` + `NativeProcessingPipelineASRTests` 43/43 PASS
  - related cloud/settings/MCP suites 39/39 PASS earlier in the candidate
- Fresh packaged app rebuilt and opened (`pid 87693`).
- Human acceptance is required before Reviewer/Tester on this candidate.

### Cloud multi-key + translation fallback — Human accepted

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T19:18:20Z |
| Candidate | CloudGeminiKeyRotationCandidate37 |
| RESULT | accepted |

- Human verified Gemini and OpenRouter cloud translation after the fix and
  reported both paths work.
- Human explicitly authorized Reviewer and then Tester on this accepted
  candidate ("запускаем код-ревью и отдаём проект на растерзание тестеру").
- One fresh Reviewer pass is authorized now. Tester follows only if Reviewer
  returns APPROVED on this unchanged candidate.

### Cloud multi-key + translation fallback — Reviewer APPROVED

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T19:21:30Z |
| Candidate | CloudGeminiKeyRotationCandidate37 |
| RESULT | approved |
| Reviewer | CloudGeminiKeyRotationReviewer43 |

- All five Judgment Gates satisfied on source evidence.
- Gemini multi-key bank filters enabled keys; quota/`429` and capacity/`503`
  high-demand rotate with backoff; auth failures stay non-rotatable.
- Legacy `geminiKey` remains coherent via bank sync; Settings multi-key UI and
  Provider/MCP readiness use enabled keys without logging raw secrets.
- Cloud cue translation falls back from MLX cue-XML to freeform/timestamped and
  blob realign; provider translation failures write explicit chunk errors.
- Scope stayed on cloud key/translation reliability. One Tester pass is now
  authorized on this unchanged accepted candidate.

### Cloud multi-key + translation fallback — Tester qa_green

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T19:27:40Z |
| Candidate | CloudGeminiKeyRotationCandidate37 |
| RESULT | qa_green |
| Tester | CloudGeminiKeyRotationTester44 |

- Tester returned `qa_green` with 161 focused passes / 0 fails.
- Main re-ran the claimed focused suites after verifying the test diff:
  `GeminiAPIKeyBankTests`, `McpSecurityContractTests`, `NativeLLMPromptTests`,
  ProviderRegistry*, and AppSettings cloud fields — **69/69 PASS**.
- Added/extended coverage pins enabled-key MCP readiness, multi-key migration,
  capacity rotation detection, and freeform/timestamped cloud cue parse.
- No assertion weakening observed. Product source unchanged by Tester.

### Cloud multi-key + translation fallback — stop-gate complete

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-13T19:27:40Z |
| Candidate | CloudGeminiKeyRotationCandidate37 |
| RESULT | complete |

- Human ACCEPTED after Gemini + OpenRouter translation worked.
- Reviewer APPROVED (`CloudGeminiKeyRotationReviewer43`).
- Tester `qa_green` (`CloudGeminiKeyRotationTester44`); Main verified focused
  suites green.
- Post-S4 maintenance candidate closed. Resume S5 when Human directs.

### Document literary translation — plan intake

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | Architect PR 9891897 |
| RESULT | plan_ready |

- Read `docs/PRD-Document-Literary-Translation.md` in full (935 lines).
- Grounded reuse claims: `UniversalWorkflow`, `WorkflowStore`, `CloudTextTranslationEngine`,
  `MLXTextGenerationEngine`, `DefaultPrompts`, `ReviewWorkspaceView` (dual),
  `ProjectArchive` / bundle v3 (`schemaVersion: 3`), `OutputFormat` is media-only.
- Wrote STEPS S7–S13 from PRD §20. S5 is still the open current_step.
- GitHub `Pavan-Gopa/VaniScript` `main` fast-forwarded to `9891897`.

### S7 opened — S5/S6 parked

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| RESULT | step_opened |

- Human: start S7; freeze S5 and S6.
- `current_step: S7`. S5/S6 recorded under `parked_steps`, not skipped.
- First work item: document contracts (`WorkflowSourceKind` / `SourceAnchor` / `DocumentState`).
- Next actor: `workflow-coder` candidate `S7DocumentContractsCandidate01`.

### S7 candidate 01 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14T10:59:00Z |
| Candidate | S7DocumentContractsCandidate01 |
| RESULT | waiting_human_acceptance |

- Structured result: `waiting_review`. Scope matched assignment target files.
- Additive Codable: missing `sourceKind` → media; missing `sourceAnchor` from
  `startSec`/`endSec`; `approved` stays synchronized with `ReviewDisposition`.
- Bundle write is schema 4 with typed `assetManifest`. Importer still reads
  v1/v2/v3 via `ProjectMigrator`; schema 99 is rejected.
- `DocumentOutputFormat` is a separate enum. Media `OutputFormat` unchanged.
- Synthetic fixture is 2382 bytes; `unzip -t` OK. No publisher manuscript.
- Main re-ran: focused DocumentModel/ProjectMigration **6/6 PASS**;
  `swift build` PASS; `swift test` **461/461 PASS**.
- Human acceptance required. Reviewer/Tester not started.

### S7 candidate 01 — Human rejected

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentContractsCandidate01 |
| RESULT | changes_requested |

- Human screenshot: first card still "Upload Audio / Video"; `.docx`/`.txt`
  cannot attach; "what can I verify if I cannot attach anything?"
- Contracts layer verified correct, but S7 acceptance requires a visible
  document attach. Scope expanded (STEPS S7): upload card copy + drag-and-drop,
  `chooseSourceFile` media/document classification, `DocumentImportService`
  copy + SHA-256 + `DocumentState` for docx/txt/md, `DOCXPackageReader` `w:p`
  walk, security rejects, document `canStartSession` without transcription.
- Deep IR (tables/headers/NFC/preflight) moved to S8.
- Prior attempt memory: candidate 01 contracts/migration work is verified and
  stays; do not redo it. The missing piece is the visible attach path.

### S7 candidate 02 — dispatched

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentAttachCandidate02 |
| RESULT | dispatched |

### S7 candidate 02 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14T11:47:00Z |
| Candidate | S7DocumentAttachCandidate02 |
| RESULT | waiting_human_acceptance |

- Structured result: `waiting_review`. Scope matched expanded target files.
- Upload card now "Upload Media / Document"; detail names DOCX/TXT/MD/RTF/PDF;
  real `.dropDestination(for: URL.self)`.
- `chooseSourceFile` classifies media vs document; documents skip
  `MediaDurationReader`/`SourceMediaInspector`.
- `DocumentImportService` copies into project store, records SHA-256, sets
  `sourceKind`, builds `DocumentState` for docx/txt/md.
- `DOCXPackageReader` walks `w:p`, preserves `w:pPr`; rejects `.docm`, zip-slip,
  external rels, XXE, oversized packages.
- Document projects pass `canStartSession` without a transcription provider.
- Main re-ran: focused SourceClassifier/DocumentImport/DOCXReader **7/7 PASS**;
  `swift test` **469/469 PASS**; fresh app built/opened (pid 4903).
- Human acceptance required. Reviewer/Tester not started.

### S7 candidate 02 — Human rejected

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentAttachCandidate02 |
| RESULT | changes_requested |

- Human confirmed document attach now works.
- Human screenshot: document Config still asks for audio Date/Location/Lecturer/
  Participants, Transcription Model, Chunk Duration, and Slice Mode.
- Required document Config: no audio metadata, no transcription selector, no
  duration/slice controls; show document title/author, source `Auto (detect)`,
  target language, and Translation Model. Structure must branch on source kind
  without a manual mode switch.
- `startSession` must not run media `ChunkPlanner` for documents. It must build
  honest reviewable chunks from `DocumentState` blocks with document anchors.
- Prior attempt memory: candidate 02 attach/classifier/import/reader is verified
  (focused 7/7; full 469/469) and stays. Do not redo it.

### S7 candidate 03 — dispatched

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentConfigCandidate03 |
| RESULT | dispatched |

### S7 candidate 03 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14T12:18:30Z |
| Candidate | S7DocumentConfigCandidate03 |
| RESULT | waiting_human_acceptance |

- Structured result: `waiting_review`; changed files match Config/start targets.
- Document Config is selected solely by `workflow.sourceKind`.
- Document mode hides audio metadata, Transcription Model, Chunk Duration, and
  Slice Mode. It shows document Title/Author, fixed `Auto (detect)` source,
  Target Language, and Translation Model.
- Document `startSession` branches before media `ChunkPlanner`; it creates
  ordered source chunks from `DocumentState.blocks` with `.document` anchors.
- Media Config and media start remain on the existing path.
- Main re-ran focused `DocumentConfigWorkflowTests`: **4/4 PASS**.
- Main re-ran full `swift test`: **473/473 PASS**.
- Fresh app built/opened (pid 14079). Human acceptance required; Reviewer/Tester
  not started.

### S7 candidate 03 — Human rejected

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentConfigCandidate03 |
| RESULT | changes_requested |

- Human confirmed document Config now looks correct.
- Human screenshots after Initialize Engine: no visible useful result; Sessions
  contains 872 chunks for the single manuscript.
- Main verified root cause in `WorkflowState.documentChunks`: direct
  `documentState.blocks.enumerated().map`, one ChunkData per DocumentBlock.
- This violates PRD §8: 872 paragraph positions must be grouped into semantic,
  deterministic, provider-budgeted plans; the analysed manuscript should be
  roughly 24–30 cloud-profile chunks, not hardcoded but bounded by content.
- Review must render document source text from the planned blocks and hide
  media-only waveform/timecode surfaces. Initialize must visibly land there.
- Prior attempt memory: candidate 03 document Config/start branching is verified
  (focused 4/4; full 473/473) and stays. Do not revert it.
- Failure signature is new (`document_one_block_per_chunk_empty_review`);
  repeated_failure_count = 1. Retry safeguard does not block candidate 04.
- PRD Slice 3 / STEPS S9 is absorbed into S7 for this vertical slice.

### S7 candidate 04 — dispatched

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7SemanticPlannerReviewCandidate04 |
| RESULT | dispatched |

### S7 candidate 04 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14T13:36:30Z |
| Candidate | S7SemanticPlannerReviewCandidate04 |
| RESULT | waiting_human_acceptance |

- Structured result: `waiting_review`; changed files match planner/Review targets.
- Added provider-capability `TranslationBudgetPlanner` with deterministic
  estimator fallback and explicit prompt/glossary/context/output/safety budgets.
- `SemanticChunkPlanner` enforces chapter boundaries, atomic paragraphs,
  quote/verse groups, blank-block no-budget mapping, stable hashes, and readonly
  neighbor context.
- `WorkflowState.startSession` persists `DocumentChunkPlan` and aggregates each
  plan's block IDs into one `ChunkData` with first/last document anchor; the
  direct one-block-per-chunk map is removed.
- Document Review uses visible source fallback, document labels/roles, and hides
  audio bar/waveform/timecode; media Review remains on its existing path.
- Generated 872-block regression asserts a deterministic bounded plan far below
  872 without hardcoding the publisher manuscript or an exact count.
- Main re-ran focused planner/budget/Review/Config: **17/17 PASS**.
- Main re-ran full `swift test`: **486/486 PASS**.
- Fresh app built/opened (pid 32384). Human must verify the real manuscript's
  semantic count and visible Review; Reviewer/Tester not started.

### S7 candidate 04 — Human rejected

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7SemanticPlannerReviewCandidate04 |
| RESULT | changes_requested |

- Human confirmed semantic planning is now normal: approximately 32 chunks for
  the real manuscript; source text is visible in document Review.
- Missing requirement: no translation output yet, no Auto-approve control, and
  no explicit action to retranslate one selected chunk.
- Accepted behavior is recorded in ADR-001:
  - Initial batch with Auto-approve enabled translates pending chunks
    sequentially through the end, autosaving and auto-approving only valid output.
  - `Retranslate Current` translates exactly the selected chunk, never starts
    another chunk, leaves the replacement pending manual `Approve & Next`, and
    preserves the previous valid translation if the replacement fails.
  - Manual `Approve & Next` navigates to an already ready next chunk without
    calling the provider again.
- Prior attempt memory: candidate 04 planner/Review is verified (focused 17/17,
  full 486/486) and stays. Do not replace semantic planning or regress Review.
- Failure signature is new
  (`document_translation_not_wired_missing_auto_targeted`), count 1.
- PRD S10/S11 are absorbed into S7 for the next coherent vertical slice.

### S7 candidate 05 — dispatched

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentTranslationCoordinatorCandidate05 |
| RESULT | dispatched |

### S7 candidate 05 — Main changes requested

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14T14:21:00Z |
| Candidate | S7DocumentTranslationCoordinatorCandidate05 |
| RESULT | changes_requested |

- Candidate implemented strict contracts/validator, document cloud+MLX engine,
  sequential coordinator, Auto-approve Config toggle, processing UI, translated
  Review, `Retranslate Current`, and document-specific `Approve & Next`.
- Main re-ran focused translation/coordinator/Review/Config: **16/16 PASS**.
- Main found a pre-Human provider-contract gap: `translateDocument` enters
  Gemini through the shared generator whose generationConfig still uses
  `responseMimeType: text/plain`; strict downstream decoder rejects fences and
  non-JSON. PRD requires structured output when supported.
- Main found deterministic test gaps from the candidate assignment / ADR-001:
  targeted-success manual-pending/no-chain, ready-next zero provider calls,
  active-session approval snapshot, and automatic continuation past Needs Review.
- Candidate 05 implementation stays. Fresh candidate 06 is a targeted transport
  + coverage fix; failure signature is new, count 1.

### S7 candidate 06 — dispatched

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentStructuredProviderCandidate06 |
| RESULT | dispatched |

### S7 candidate 06 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14T14:38:30Z |
| Candidate | S7DocumentStructuredProviderCandidate06 |
| RESULT | waiting_human_acceptance |

- Candidate changed only authorized structured-provider/coordinator/store/state
  and focused test targets.
- Gemini document body uses `responseMimeType: application/json`.
- Known supported OpenAI-compatible document routes use
  `response_format: {type: json_object}`; Ollama/unknown routes omit it.
- Existing media Gemini mode remains `text/plain`; media OpenAI mode omits
  `response_format`.
- Deterministic tests pin targeted success/failure isolation, ready-next zero
  calls, untranslated-next one manual call, session approval snapshot, and
  automatic continuation past Needs Review.
- Main focused suite: **25/25 PASS**.
- Main full `swift test`: **506/506 PASS**.
- Main fresh `./script/build_and_run.sh`: exit 0; app opened at pid 49628.
- Human live Gemini Auto-approve batch + isolated middle-chunk retranslation
  required. Reviewer/Tester not started.

### S7 candidate 06 — Human rejected

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentStructuredProviderCandidate06 |
| RESULT | changes_requested |

- Human tested document translation with local MLX, OpenRouter, Gemini, and the
  current-chunk editor/retranslation path. No translated text appeared.
- Main traced the live `.targetedCurrent` path: Review calls WorkflowStore,
  which calls the document coordinator with the selected chunk index.
- Live persisted project: 32 chunks; chunk 1 contains 33 planned block IDs and
  636 source characters. Its project glossary has 105 entries / 41,747 JSON
  characters.
- Live app log: local MLX received a 150,022-character prompt and returned zero
  output twice. The request repeats the project glossary through profile and
  rolling memory instead of sending bounded relevant terminology once.
- Live chunk quality report after Gemini: provider error
  `The document translation provider returned truncated JSON.`
- Coordinator converts provider/parse failure into a normal result. WorkflowStore
  then unconditionally reports `Current chunk retranslated; approve it manually.`,
  causing a false-success no-op in Review.
- New failure signature: oversized document request + swallowed runtime failure.
  This is runtime evidence absent from candidate 06 mock/request-builder tests.

### S7 candidate 07 — dispatched

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentLiveTranslationRuntimeCandidate07 |
| RESULT | dispatched |

### S7 candidate 07 — runtime interruption, partial recovered

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentLiveTranslationRuntimeCandidate07 |
| RESULT | interrupted_partial |

- Worker reported the runtime fix complete, including a live-shaped prompt
  reduction from 150,022 to 5,030 characters, then hit the 30-minute task limit
  before structured yield.
- Main inspected the authorized diff and found the bounded request, exact response
  template, prompt budget, explicit coordinator outcome, Review error panel, and
  runtime regression tests present.
- Main `swift build` found an interrupted final edit in
  `DocumentTranslationCoordinator.process`: duplicated `terminalOutcome` and a
  missing `return ProcessOutcome(...)`. Build fails at lines 395–404.
- This is runtime `interrupted_partial`, not another implementation attempt or
  repeated product failure. All useful candidate 07 edits are preserved.

### S7 candidate 07 recovery B — dispatched

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentLiveRuntimeRecovery07B |
| RESULT | dispatched |

### S7 candidate 07 recovery B — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14T15:45:00Z |
| Candidate | S7DocumentLiveTranslationRuntimeCandidate07 |
| RESULT | waiting_human_acceptance |

- Recovery repaired only the interrupted coordinator terminal return.
- Main focused runtime/engine/coordinator/Review/cloud/budget/contract suites:
  **PASS**. Runtime test logs a 630-character selected source as a 5,030-character
  prompt, down from the live 150,022-character failure.
- Regression proves full 105-entry glossary is filtered/deduplicated, unrelated
  document sentinel text is absent, exact response shape is present, and a
  provider-budget preflight failure makes zero provider calls.
- Explicit terminal outcomes now distinguish success, needs-review, validation,
  provider, and cancellation. WorkflowStore uses result message and never emits
  retranslation success for a failed request. Review renders quality errors.
- First Main full-suite run reported one transient issue without retained detail;
  immediate unabridged rerun: **510/510 PASS**.
- Main fresh `./script/build_and_run.sh`: exit 0; app opened at pid 66143.
- Human must retry the existing failed chunk. Expected result is translated text
  or a precise visible provider/validation error—not a silent no-op.

### S7 candidate 07 — Human rejected

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentLiveTranslationRuntimeCandidate07 |
| RESULT | changes_requested |

- Human's live OpenRouter response reached the local validator and displayed
  Needs Review instead of a silent no-op.
- Provider diagnostics: one selected chunk, 33 planned blocks / 636–700 source
  characters; initial output 16,379 characters. Two repair calls resent the full
  chunk and returned 18,463 then 16,222 characters.
- Main mapped every reported issue to the persisted source:
  - 11 `emptyBlock` errors correspond exactly to 11 source-empty blocks;
  - `duplicateText` corresponds to the second source-authored
    `All rights reserved.`;
  - `modelExplanation` corresponds to source-authored `Translation: [NAME]`;
  - residue warnings correspond to `kadambafoundation.com` and two copyright
    lines, not ordinary untranslated prose.
- Root cause: validator is output-only for emptiness/duplicate/explanation
  checks, despite having source blocks; repair metadata identifies invalid IDs
  but the engine retains and re-requires every original block.
- Candidate 08 must make structural blanks/source labels/repeated source
  deterministic and source-aware, narrow each repair to invalid translatable
  IDs, merge it into the prior candidate, then revalidate the full response.
  Genuine empty translation of non-empty source, duplicate output for different
  source paragraphs, and unsolicited model wrappers remain blocking.

### S7 candidate 08 — dispatched

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentFrontMatterValidatorCandidate08 |
| RESULT | dispatched |

### S7 candidate 08 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14T16:42:30Z |
| Candidate | S7DocumentFrontMatterValidatorCandidate08 |
| RESULT | waiting_human_acceptance |

- Source-empty and protected blocks are partitioned from provider work and
  reconstructed deterministically in original full response order.
- Validator allows empty output only for empty source, allows duplicate output
  only for identical source, and allows a translated label only when the source
  is itself a recognized label. Negative empty/different-source duplicate/
  unsolicited-wrapper tests remain blocking.
- URL/domain, copyright, placeholder-only front matter, and protected literals
  no longer emit misleading source-residue warnings; copied ordinary prose still
  does.
- Repair provider request requires only invalid translatable IDs. The repaired
  subset is merged into the prior candidate and the reconstructed full response
  is revalidated; valid blocks remain byte-for-byte unchanged.
- Main focused validator/engine/coordinator/runtime/contract: **33/33 PASS**.
- Synthetic live shape: 33 full blocks, 11 source-empty; provider receives only
  translatable blocks, one call commits all 33 pending manual approval.
- Main full `swift test`: **522/522 PASS**.
- Main fresh `./script/build_and_run.sh`: exit 0; app opened at pid 79770.
- Human must retry the existing first chunk. The previous invalid candidate was
  never committed, so the button should issue one fresh targeted provider call.

### S7 candidate 08 — Human changes requested

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentFrontMatterValidatorCandidate08 |
| RESULT | changes_requested |

- Human confirmed document translation through cloud APIs now works.
- New Review UX failure from live Dual View screenshot:
  - source and translated panes scroll independently, forcing two manual scrolls;
  - on chunk 7 the translated pane jumps and cannot be scrolled to its real end.
- Main source trace: document Review renders two independent SwiftUI `TextEditor`
  instances, each owning a separate AppKit `NSScrollView`. No shared document
  scroll position or scroll coordinator exists.
- Raw offsets cannot be mirrored because translated/source content heights differ.
  Required invariant is normalized progress: top `0`, bottom `1`, with exact
  per-pane mapping.
- `TextEditor` binding/caret/layout updates can mutate one internal scroll offset;
  synchronization must observe user live-scroll leadership and suppress
  programmatic follower notifications to prevent feedback loops/jumps.
- Candidate 09 is bounded to Document Dual View. Source-only, Translated-only,
  media timed/cue Review, translation contracts, and provider behavior stay
  unchanged.

### S7 candidate 09 — dispatched

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentDualScrollCandidate09 |
| RESULT | dispatched |

### S7 candidate 09 — Coder result

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentDualScrollCandidate09 |
| RESULT | waiting_review |

- Changed `ReviewWorkspaceView.swift`, `ThinScrollbarTuner.swift`, and added
  `DocumentReviewScrollSyncTests.swift`.
- Added one shared document-only coordinator with normalized `0...1` progress,
  bidirectional live-scroll leadership, programmatic follower suppression,
  relayout reapplication, and document/chunk/language scope reset.
- Coder reported focused scroll/workflow/coordinator tests, `swift build`,
  full `swift test`, and `./script/build_and_run.sh --verify` green.

### S7 candidate 09 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentDualScrollCandidate09 |
| RESULT | waiting_human_acceptance |

- Main inspected the coordinator, AppKit notification lifecycle, `TextEditor`
  bridge attachment/detachment, normalized flipped/unflipped geometry, and the
  real `NSScrollView` harness.
- Focused `DocumentReviewScrollSyncTests`, `DocumentReviewWorkflowTests`, and
  `DocumentCoordinatorTests`: **21/21 PASS**.
- AppKit harness covers source leadership, translated leadership, unequal
  heights, exact mapped offsets, and stale notification suppression after
  detach.
- Full `swift test`: **530/530 PASS** across 73 suites.
- Fresh `./script/build_and_run.sh`: exit 0; app opened at pid 92982.
- Human must verify the actual document Dual View: scroll each pane in turn,
  confirm the other follows immediately, confirm chunk 7 reaches bottom in both
  panes, and confirm there are no jumps after changing chunks and returning.

### S7 candidate 09 — Human changes requested

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7DocumentDualScrollCandidate09 |
| RESULT | changes_requested |

- Human confirmed the prior translated-pane jumps are gone.
- Human rejected the candidate because the source and translated panes still do
  not scroll together in the real document Dual View.
- Human also reported that direct Google Gemini document translation returns to
  failure almost immediately while OpenRouter translates the same content.
- Main inspected persisted settings without reading or printing credentials:
  **5 configured, 5 enabled Gemini keys**.
- Runtime evidence:
  - chunk 7 direct Gemini 3.7 Flash: key #1 returned HTTP 503 after 9.7 seconds;
    runtime logged rotation, then ended after 20.0 seconds with only 153 output
    characters and `truncated-json`;
  - chunk 8 direct Gemini 3.6 Flash calls ended after 12.0–13.7 seconds with
    172–183 characters and `invalid-json`/`truncated-json`;
  - OpenRouter returned 15,807 characters for chunk 7 and 31,855 characters for
    chunk 8; the later Luna request returned 13,388 characters and committed.
- Rotation currently continues only after rotatable HTTP failures. A nonempty
  HTTP-success response returns from `generateGemini` before document JSON
  decoding/validation, so a tiny malformed response from key #2 prevents keys
  #3–#5 from being observed. This does not mean those keys were exhausted.
- Direct Gemini receives `prompt.budget.reservedOutputTokens` as
  `maxOutputTokens`; the OpenAI-compatible request builder does not send an
  equivalent cap. The provider paths therefore have materially different output
  ceilings for the same live-shaped document request.
- Scroll harness directly attaches two known `NSScrollView` instances and
  therefore does not test the production bridge. The bridge searches ancestor
  descendants for the first scroll view without pane ownership. [INFERENCE] Both
  anchors can resolve the same left-hand TextEditor scroll view, matching the
  observed no-op synchronization.
- Non-live `boundsDidChange` is currently classified as relayout. Scrollbar and
  keyboard-driven user scrolling therefore need explicit coverage even after
  bridge ownership is corrected.

### S7 candidate 10 — dispatched

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7GeminiScrollRecoveryCandidate10 |
| RESULT | dispatched |

- Scope combines the two Human-rejected S7 runtime boundaries: production
  document scroll bridge ownership/user-scroll coverage and direct Gemini
  structured-output/key-attempt behavior.
- Official current Gemini structured-output documentation is supplied to Coder.
- Real keys and manuscript text are excluded from the assignment and tests.

### S7 candidate 10 — Main Objective Gate failure

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7GeminiScrollRecoveryCandidate10 |
| RESULT | changes_requested |

- Coder changed six authorized product/test files and intentionally skipped
  validation per assignment.
- Main SourceKit diagnostics failed before tests:
  - `CloudTextTranslationEngine.swift:677`: recursive value-type property
    `GeminiSchema.items: GeminiSchema?`;
  - `CloudTextTranslationEngine.swift:711`: `GeminiGenerationConfig` has
    infinite size.
- Candidate 10 is not runnable. Candidate 11 is a narrow compile recovery;
  scroll, rotation, output-budget, and diagnostics behavior remains unchanged.

### S7 candidate 11 — Main Objective Gate failure

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7GeminiScrollCompileRecoveryCandidate11 |
| RESULT | changes_requested |

- SourceKit diagnostics for `CloudTextTranslationEngine.swift` became green.
- Main focused test command then failed during compilation:
  `ThinScrollbarTuner.swift:705: expected '}' in class`, matching the opening
  declaration of `DocumentScrollSyncAnchorView` at line 548.
- No test executed. Candidate 12 is the bounded second compile recovery; retry
  safeguard repeated-failure count is 2/3.

### S7 candidate 12 — Main Objective Gate failure

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7ScrollParserRecoveryCandidate12 |
| RESULT | changes_requested |

- Missing class delimiter is repaired.
- Main SourceKit diagnostics now reach a new Swift 6 concurrency error:
  `ThinScrollbarTuner.swift:392: sending 'notification' risks causing data races`.
- The observer closure forwards non-Sendable `Notification` into
  `MainActor.assumeIsolated` only to distinguish clip-view bounds from
  document-view relayout. Candidate 13 will pass preclassified Sendable event
  metadata instead; no scroll policy redesign.

### S7 candidate 13 — Main focused gate changes requested

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7ScrollConcurrencyRecoveryCandidate13 |
| RESULT | changes_requested |

- SourceKit diagnostics are green and focused suites compile.
- Gemini schema/rotation tests all pass, including ordered five-key fallback,
  all-key exhaustion, auth stop, malformed-success stop, and media invariance.
- Existing coordinator scroll harness passes.
- New bridge test used 400-point viewports but retained expectations derived
  from 100-point viewports. Observed normalized mappings are mathematically
  correct for the actual geometry; five assertions are stale.
- Synthetic 37-block text is 722 characters outside its declared live-shape
  tolerance. Candidate 14 is test-only and must not change product behavior.

### S7 candidate 14 — Main automated gates and live Gemini rejection

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7FocusedFixtureRecoveryCandidate14 |
| RESULT | changes_requested |

- Focused Gemini/scroll/budget/runtime: **36/36 PASS**.
- Full `swift test`: **536/536 PASS** across 73 suites.
- Fresh `./script/build_and_run.sh`: exit 0; app opened at pid 4625.
- The fresh app immediately supplied real provider evidence from the active
  document:
  - provider `gemini-cloud`, model `gemini-3.6-flash`, key 1/5;
  - HTTP 200 after 36,992 ms;
  - 7,455 response characters;
  - finish reason `MAX_TOKENS`;
  - document terminal class `truncated-json`.
- The key is healthy; no rotation is correct for this outcome. The remaining
  failure is the request strategy: document generation still uses 8,192 output
  tokens and default medium thinking.
- Current official GenerateContent reference supports `thinkingConfig` /
  `thinkingLevel`, prefers `responseJsonSchema` over deprecated
  `responseSchema`, and states model-dependent output limits. Official Gemini
  3.6 Flash limits are 1,048,576 input and 65,536 output tokens.
- Candidate 15 is Gemini-document-only: current JSON Schema, low thinking,
  larger bounded output, and `MAX_TOKENS` must be actionable rather than logged
  as successful. Scroll/product behavior remains frozen.

### S7 candidate 15 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7GeminiMaxTokensRecoveryCandidate15 |
| RESULT | waiting_human_acceptance |

- Direct Gemini 3.x document requests now send:
  - current `responseJsonSchema` with lower-case JSON Schema types;
  - `thinkingConfig.thinkingLevel = LOW`;
  - `maxOutputTokens = 32768`;
  - no deprecated `responseSchema`.
- Earlier Gemini models preserve the prior 8,192 bound and omit Gemini-3-only
  thinking level. Media remains text/plain with no schema or thinking config.
- HTTP 200 `MAX_TOKENS`, `SAFETY`, and other non-success finish reasons now
  terminate as visible non-rotatable output failures before document decoding;
  case-insensitive `STOP` succeeds.
- SourceKit diagnostics: green.
- Focused Gemini/scroll/runtime/coordinator: **34/34 PASS**.
- Full `swift test`: **540/540 PASS** across 73 suites.
- Fresh `./script/build_and_run.sh`: exit 0; app opened at pid 7988.
- Human live acceptance remains:
  1. retry direct Gemini 3.6 on the current document chunk and confirm complete
     translation instead of `MAX_TOKENS`/truncated JSON;
  2. scroll each Dual View pane by trackpad/wheel and scrollbar/keyboard and
     confirm the opposite pane follows without jumps.

### S7 candidate 15 — Human live rejection (chunk 30 + transient scroll)

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7GeminiMaxTokensRecoveryCandidate15 |
| RESULT | changes_requested |

- Human confirmed Gemini translation and dual-pane scroll work on chunks 1-29.
- Display chunk 30 (index 29) never commits on Gemini or OpenRouter although
  providers are paid: app.log shows repeated `HTTP 200 ... finishReason: STOP`
  with 1.2k-6.6k chars, every attempt ending `failureClass=validation`.
- Persisted `qualityReport` for chunk 29 proves the local causes:
  `duplicateBlockID` on the three empty blocks, `blockOrder`, and
  `numbersChanged` for the decade paragraph ("the late 1970s" vs "1970-х").
- Root cause 1: providers are instructed to echo every block ID including
  empty deterministic blocks, while `reconstructedResponse` also inserts
  deterministic outputs and appends the provider echoes of empty IDs as
  extras; repair cannot fix structural errors, so every click burns three
  paid attempts and commits nothing.
- Root cause 2: number token regex backtracks on "1970s" (yields "197") but
  matches "1970-х" (yields "1970"), so a correct Russian translation fails.
- Root cause 3: validator issue codes are never logged; only
  `failureClass=validation` appears, hiding the diagnosis.
- No 30-chunk limit exists anywhere in Sources; the book has 32 chunks and
  chunks 30-31 remain pending, not blocked by code.
- Transient dual-pane desync after chunk switch self-heals on re-entry;
  layout-race re-synchronization needed.

### S7 candidate 16 — dispatch

- Fresh workflow-coder run `S7Chunk30ValidatorRecoveryCandidate16`.
- Scope: deterministic echo dedupe in reconstruction, decade-safe number
  parity, validation issue logging, chunk-change scroll re-sync, regression
  tests, no provider/prompt/scroll-behavior changes beyond the named fixes.

### S7 candidate 16 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7Chunk30ValidatorRecoveryCandidate16 |
| RESULT | waiting_human_acceptance |

- `reconstructedResponse` now consumes at most one provider echo per
  deterministic block, validates it (`isDeterministicSafe`), synthesizes the
  deterministic output otherwise, and drops duplicate deterministic echoes in
  both ordered and malformed branches; translatable duplicates still reach
  the validator.
- Validator number parity tokenizes decade/ordinal suffixes
  (`1970s`, `1970-х`, `1970‑х`) and compares numeric cores in order; genuine
  changed numbers still fail.
- `Document translation end ... failureClass=validation` lines now append
  `validationIssues=<code:blockHash>` metadata only; no manuscript text or
  credentials are logged.
- Dual-pane scroll: chunk/language change re-applies the stored normalized
  position to both panes after layout stabilizes, without animation and
  without stealing an in-flight user scroll.
- Focused suites: 52/52 PASS (engine 10, validator 7, coordinator 10, scroll
  10, runtime 2, structured output 13).
- Full `swift test`: 546/546 PASS, 73 suites.
- Fresh `./script/build_and_run.sh`: exit 0; app pid 61918.
- Human live acceptance remains:
  1. retry chunk 30 on Gemini or OpenRouter and confirm the paid translation
     commits and displays;
  2. switch chunks repeatedly and confirm both panes stay synchronized
     without bottom jumps.

### S7 candidate 17 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-14 |
| Candidate | S7EmptyChunkExportChooserCandidate17 |
| RESULT | waiting_human_acceptance |

- `DocumentApprovalAdvancePolicy.isSourceEmptyChunk` + store wiring: source-
  empty chunks approve to done/manuallyApproved without translation and
  advance; non-empty untranslated chunks keep the guard.
- Document sessions show a DOCX / PDF / TXT chooser; media keeps the
  OutputFormat grid.
- `DocumentExportWriters`: TXT UTF-8; PDF CoreText A4 pagination; DOCX
  rewrites translated paragraph runs inside the imported package preserving
  properties, styles, and other entries; honest errors, no partial files.
- Focused suites: 48/48 PASS. Full `swift test`: 556/556 PASS, 76 suites.
- Fresh `./script/build_and_run.sh`: exit 0; app pid 71025.
- Human live acceptance remains: pass the empty chunk with Approve & Next,
  translate/approve the final chunk, then export via DOCX, PDF, and TXT.

### S7 review preparation — Reviewer held by Human

- Human requested full review preparation but NO Reviewer dispatch until an
  explicit go-ahead after the Human's experiment.
- `AI_Workflow_Kit/docs/AI/REVIEW_PACKAGE_S7.md` contains the complete
  KICK_REVIEWER assignment, gate evidence, judgment gates, and Main's
  pre-review observations. Main stops here; dispatch happens only on
  Human instruction.

### S7 candidate 18 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-15 |
| Candidate | S7ReviewerIssuesCandidate18 |
| RESULT | waiting_human_acceptance |

- Reviewer issues fixed:
  1. Block-slice support: engine now carries sliced source text when
     plan.blockSlices is present; archive stores slice translations under
     compound keys and merges them for display/export. Long paragraphs no
     longer skip the hard limit.
  2. hasReadyTranslation: mixed chunks (translatable + empty structural
     blocks) skip deterministic blocks in the allSatisfy check; empty
     blocks no longer block recognition of a completed translation.
  3. Export honesty: DocumentTranslationExportBuilder returns empty for
     untranslated blocks (no original-text substitution); export guard
     checks that all translatable blocks have translations.
- Focused suites: 39/39 PASS. Full swift test: 561/561 PASS, 76 suites.
- Fresh ./script/build_and_run.sh: exit 0; app pid 27010.

### S7 Tester — QA result

| Field | Value |
|-------|-------|
| Run | S7TesterCandidate18 |
| Verdict | qa_green |

- 564/564 tests, 0 failures, 76 suites.
- 3 new coverage tests added in DocumentCoordinatorTests.swift and
  DocumentTranslationExportTests.swift.

### S7 stop-gate — CLOSED

- Human ACCEPTED + Reviewer APPROVED + Tester qa_green.
- Implementation complete. Next: S8 (Document IR depth and preflight).

## S8 — Document IR depth and preflight

### S8 candidate 1 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-15 |
| Candidate | S8DocumentIRDepth |
| RESULT | waiting_human_acceptance |

- DOCX IR deepened: tables (w:tbl), text boxes (w:txbxContent), headers,
  footers, footnotes, endnotes all parsed with DocumentPart location.
- Visually identical consecutive runs merged; italic/bold/small-caps/
  hyperlink boundaries preserved.
- NFC normalization without diacritic stripping; field instructions,
  bookmarks, drawing data dropped from translatable text.
- Preflight counts: pages, words, sections, blocks, protected groups,
  font warnings exposed in document metadata.
- Focused: 10/10 PASS. Full: 569/569 PASS, 76 suites.
- Fresh build: app pid 14247.

### S13 hardening candidate — Human changes requested

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-15 |
| Candidate | S13Hardening |
| RESULT | changes_requested |

- Human source screenshot contains red placeholder text; the translated output
  renders every run black. Foreground color must remain an explicit source-span
  property and survive translation, Review editing, persistence, and every rich
  output format. Plain-text formats must remain honestly plain.
- Human light-theme screenshot shows unreadable top-toolbar icons, status/action
  text, and dark-mode chrome reused against light surfaces. The document editor
  must remain visibly editable in Light mode; all app chrome and interaction
  states require a semantic light/dark contrast audit.
- Main source verification: `DOCXPackageReader` reads `w:color` into run
  formatting/style XML and the coordinator persists provider output spans, but
  `DocumentExportWriters.rewriteParagraph` writes the full translation into the
  first run and clears every later run. `ReviewWorkspaceView` uses a plain
  `TextEditor` plus fixed dark bars and `Color.white.opacity(...)`. RTF and PDF
  reconstruction currently flatten attributed source text to unstyled spans.
- This changed candidate requires a bounded Architect advisory because one
  contract must cover cross-format color representation, styled translation
  editing, export fidelity, and backward-compatible project decoding without
  creating a second formatting convention.
- Reviewer and Tester did not run. Human acceptance is rejected; the changed
  candidate returns through Coder, Main verification/fresh app, and Human
  acceptance before formal review.

### S13 foreground-color and appearance advisory

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-15 |
| Run | S13ColorThemeArchitect19 |
| RESULT | advice_ready |

- Keep the existing `RichTextSpan`/`styleKey` convention. Add one optional
  `foregroundColorHex` mirror on that same span; missing data decodes as `nil`,
  so no bundle-schema or ProjectMigrator bump is required.
- `styleKey` remains the lossless trusted DOCX run template. Explicit color is
  populated by rich importers and re-anchored from known source span/style IDs;
  provider output never becomes arbitrary OOXML or trusted color data.
- Document Review needs an attributed AppKit editor so per-range color survives
  rendering and manual edits. DOCX/PDF writers consume translated spans;
  TXT/Markdown remain plain and make no rich-format claim.
- Light/Dark fixes extend the existing `Color.dynamic` convention with semantic
  chrome/editor/status tokens. Fixed dark bars and translucent-white text are
  migrated on primary workflow surfaces; intentional media-preview dimming is
  not application chrome and remains out of this sweep.
- Main accepted the bounded advice and persisted it in the PRD and S13 card.
  Implementation proceeds as two sequential Coder work items on one changed
  candidate: foreground-color fidelity first, then the full appearance audit.

### S13 foreground-color Coder 20 — Main changes requested

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-15 |
| Run | S13ForegroundColorCoder20 |
| RESULT | changes_requested |

- Focused suites reported green and import/coordinator/DOCX/PDF paths now carry
  `foregroundColorHex`, but Main rejected the editor persistence boundary.
- `DocumentAttributedTextView.serializeSpans` replaces every span ID with a
  UUID, clears every `styleKey`, resets every policy to `.translate`, and derives
  color from the rendered `.foregroundColor`. Therefore an unset theme-default
  span becomes an explicit black/white export override and a manual edit destroys
  the trusted `w:rPr` template needed by DOCX round-trip.
- `WorkflowStore.currentDocumentSourceSpans` / translated equivalent flatten
  every block in the current plan without boundary metadata. Both update methods
  then assign the same full edited span array and full text to every block ID.
  Editing one multi-block chunk corrupts block identity, hashes, and export.
- Required repair: carry block/span identity, styleKey, policy, traits, and
  explicit-color metadata as custom `NSTextStorage` attributes; treat semantic
  display color separately from explicit document color; serialize edits per
  original block and update each block independently. Add a real attributed
  round-trip test with two blocks and nil+red spans. Theme work remains blocked
  behind this repair.

### S13 foreground-color Coder 21 — Main targeted fix

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-15 |
| Run | S13ForegroundColorFix21 |
| RESULT | changes_requested |

- The exact block/style/policy/default-color corruption is repaired and the new
  two-block attributed-storage round-trip passes.
- Main source verification found one remaining metadata loss:
  `DocumentAttributedTextView` reconstructs traits only from bold/italic font
  flags plus underline/strikethrough presentation attributes. Existing
  `.smallCaps`, `.superscript`, and `.subscriptText` are dropped after any edit.
- Required bounded fix: persist the canonical `InlineTrait.rawValue` set as a
  custom text-storage attribute and serialize it directly; presentation
  attributes may augment rendering but must not redefine document metadata.

### S13 foreground-color work item — Main verified

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-15 |
| Candidate | S13ForegroundColorCandidate22 |
| RESULT | waiting_next_work_item |

- Main verified the source contract, direct DOCX/RTF/PDF color capture,
  trusted translation-span mapping, block-aware attributed editing, additive
  decoding, DOCX run reconstruction, PDF color output, and plain TXT behavior.
- The editor now carries block/span identity, styleKey, translation policy,
  canonical InlineTrait values, and explicit foreground override independently
  of semantic display color. Multi-block edits update blocks separately.
- Main focused gate: **42 tests in 7 suites passed** with zero failures.
- S13 remains open for the second Human-rejected requirement: the complete
  Light/Dark primary-workflow appearance audit. No Human acceptance, Reviewer,
  or Tester runs before that changed candidate is complete.

### S13 Light/Dark Coder 23 — Main changes requested

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-15 |
| Run | S13LightThemeCoder23 |
| RESULT | changes_requested |

- The dark-only Review bars and translucent-white primary chrome are migrated;
  five focused dynamic-appearance tests and the six Review workflow tests pass.
- Main source verification rejected the stated disabled-state acceptance:
  `disabledText` is only 32% black/white, is not covered by contrast assertions,
  and is consumed only by the chat send icon. Custom styles used by disabled
  Review, Upload, Config, Export, and Settings controls ignore `isEnabled`, so
  they continue to render as enabled instead of a readable distinct state.
- Required bounded fix: make disabled text meet at least 3:1 against its actual
  surfaces; test that resolved pair in Aqua/Dark Aqua; use
  `@Environment(\\.isEnabled)` in the custom styles that are actually attached
  to disabled controls and branch to `disabledText` / `disabledSurface`.

### S13 foreground-color + Light/Dark candidate 24 — Main verification

| Field | Value |
|-------|-------|
| Timestamp | 2026-08-15 |
| Candidate | S13ForegroundColorLightThemeCandidate24 |
| RESULT | waiting_human_acceptance |

- Source foreground color is explicit additive span metadata. DOCX, RTF and
  text-layer PDF capture represented colors; provider output re-anchors only to
  trusted source span/style data; attributed edits preserve block/span/style/
  policy/trait/color identity; TXT/Markdown remain plain.
- DOCX export writes translated runs separately with their trusted `w:rPr` and
  direct color override; PDF uses attributed colored spans. The old
  first-run-only/blank-later-runs path is removed.
- Primary Upload, Config, Processing, Review, Export, Settings/Usage, project
  sidebar, chat sidebar and root chrome consume the existing dynamic semantic
  palette. Review toolbar/action/status controls and disabled custom button
  styles have readable Aqua/Dark Aqua roles.
- Main gates:
  - rich-color focused gate: **42 tests in 7 suites passed**;
  - final theme/editor gate: **12 tests in 2 suites passed**;
  - full `swift test`: **674 tests in 90 suites passed**;
  - fresh `./script/build_and_run.sh`: exit 0, signed app launched.
- Fresh-app Light Review smoke visibly showed the source `[YEAR]`, `[NUMBER]`,
  `[PRINTER, COUNTRY]`, and `[NAME]` spans in red and the translated Bengali
  counterparts in the same red. Top toolbar icons, document editor text,
  status/action bar, disabled Previous button, and Approve button were readable.
  Processing and Settings surfaces were also readable in Light mode.
- Aqua/Dark Aqua tests resolve the real dynamic NSColors and verify primary,
  secondary, tertiary, editor, status/error, on-accent, control, border, and
  disabled contrast. The temporary Dark smoke changed no project data; the
  user's persisted theme was restored to `light` and the smoke app was stopped
  so the Auto-approve queue would not continue unattended.
- Remaining Human gate: open the fresh candidate, inspect Review in both themes,
  edit one red translated span, export DOCX and PDF, and confirm the red run is
  preserved in the actual files. Reviewer and Tester remain blocked until Human
  acceptance.