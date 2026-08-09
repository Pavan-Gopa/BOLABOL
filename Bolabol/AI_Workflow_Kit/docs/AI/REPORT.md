# CODE-HYGIENE-BATCH-1-RETEST

**Date:** 2026-08-09
**Actor:** Test Engineer (retest after Reviewer-approved Coder Batch 1)
**Result:** **`qa_green`**
**Suite:** `CODE-HYGIENE-BATCH-1-RETEST`
**Baseline:** `bolabol/pre-CODE-HYGIENE-RELEASE` at `1a8bf3d`

## Gate Results

| Command / check | Result |
|---|---|
| Required Graphify query | **PASS** - BFS depth 2, 161 nodes; no rebuild requested |
| `swift test` | **PASS** - 744 tests in 32 suites |
| `./script/qa/run_all.sh` | **PASS** - 39/39 |
| `./script/qa/check_settings_surface.sh` | **PASS** |
| `./script/qa/check_workspace_ui_surface.sh` | **PASS** |
| Source/dead-symbol scan | **PASS** - deleted Apple Speech, Statistics, FullLogo wrapper, stale helper, Speech plist keys, and dead ContentView declarations remain absent |
| Release identity | **PASS** - source and built bundle are `Bolabol`, `com.bolabol.app`, `1.0.4`; full logo SVG remains packaged |
| Scoped `git diff --check` | **PASS** |

## Hygiene Confirmation

- `HYG-002..009` and `HYG-011..015` still hold. VaniScript attribution residue is absent from the approved files; the popover controller is present; the dead files/symbols and destructive script are absent; notification and logging identities remain canonical; settings/workspace surfaces pass.
- HYG-006 negative checks remain clean for `import Speech`, `SFSpeech`, `NSSpeechRecognitionUsageDescription`, Apple Speech keys, and legacy Help fallback keys.
- HYG-009 documentation states the restructure is complete, the script was removed, recreation is forbidden, and `RENAME_REPORT.md` is linked.
- Exact HYG-016 key lines have no diff against the baseline. The `AppText.swift` diff is limited to the approved HYG-006/HYG-007 deletions; no HYG-016 localization/copy change was mixed in.

## Gap Hunt

Existing `HUDLanguagePickerPopoverTests`, `ReleaseIdentityTests`, localization/max-coverage tests, the S9 legacy-helper guard, and the settings/workspace guards cover the touched functional and surface contracts. HYG-009 was also manually checked as file/docs hygiene. No real Batch 1 gap or product bug was found, so no new tests or QA guards were added.

## Scope

- No `Sources/**`, `Package.swift`, `STATE.yaml`, or product behavior changes were made by Tester.
- No rebuild, commit, tag, push, or release publication was performed.
- `BUG_REPORT.md` remains unchanged with `bugs_open: 0`.

**RESULT: `qa_green`**

---

# SEC-FIX-ATTEMPT-8-RETEST-PLUS-FULL-GATE

**Date:** 2026-08-09
**Actor:** Test Engineer (retest after Reviewer-approved Coder Fix Attempt 8)
**Result:** **`qa_green`** — SEC-001…004 confirmed closed on independent retest; SEC-005 remains deferred info
**Suite:** VERTICAL-PULSE-HUD — SEC-FIX-ATTEMPT-8-RETEST-PLUS-FULL-GATE
**Baseline:** working tree with approved Coder Fix Attempt 8 (uncommitted, as directed — no git ops by Tester)

## Gate results

| Command | Result |
|---|---|
| Graphify query (mandatory, pre-review) | **PASS** — resolved `ModelDownloadPathPolicy`, both download stores, `SharedModelsRoot`, `PolishingRequestPolicy`, `SecuritySurfaceRegressionTests.swift`, Attempt 8 feedback nodes |
| `swift test --filter SecuritySurfaceRegressionTests` | **PASS** — 21 tests in 7 suites |
| `swift test` | **PASS** — 745 tests in 32 suites (matches Coder/Reviewer counts) |
| `./script/qa/run_all.sh` | **PASS** — 39/39 |
| `./script/qa/check_sec_download_path_safety.sh` | **PASS** |
| `./script/qa/check_sec_download_path_safety.sh --self-test` | **PASS** — SEC-001…004 negative mutations all fail closed |
| `./script/qa/check_vertical_pulse_hud_contract.sh` | **PASS** |
| `./script/qa/check_vertical_pulse_hud_contract.sh --self-test` | **PASS** |
| All 9 `check_sec_*.sh --self-test` | **PASS** |

## Closure confirmation (independent retest)

| Finding | Retest verdict | Evidence |
|---|---|---|
| SEC-001 (HF path policy) | **CLOSED** | `ModelDownloadPathPolicy.isSafe` (TranscriptionModelStore.swift:19) shared by both HF seams and the CDN manifest predicate. Transcription seam preflights all entries before `createDirectory` and re-checks per item (TranscriptionModelStore.swift:617,629); polishing seam preflights in `directSnapshotEntries` before the snapshot dir exists and re-checks per entry (PolishingEngineStore.swift:548,607). Typed `invalidRemotePath` errors both sides. `huggingFaceTraversalFailsClosed` re-verified: one metadata request, failed state, "unsafe Hugging Face model path" message, **no destination write** for `../escaped.bin`. |
| SEC-002 (missing-tail symlink escape) | **CLOSED** | `SharedModelsRoot.symlinkSafeURL` walks every existing component with `destinationOfSymbolicLink`, resolves relative targets, and rejects escapes before location parsing (SharedModelsRoot.swift:151). `missingTailSymlinkEscapeRejected` + existing-path escape tests green on retest. |
| SEC-003 (`*.py` in MLX patterns) | **CLOSED** | `mlxModelDownloadPatterns` = safetensors/json/jinja/txt/model only (PolishingEngineStore.swift:906); `mlxPatternsExcludePython` green; guard fails if `"*.py"` reappears. |
| SEC-004 (delimiter escape) | **CLOSED** | `</transcription>` in user text neutralized with ZWJ before the immutable wrapper (PolishingRequestPolicy.swift); `closingDelimiterIsNeutralized` green; editor system contract + execution reminder intact (`SecPromptInjectionContainment` green). |
| SEC-005 (CDN env override) | **DEFERRED** (info) | Not part of Attempt 8 scope; does not fail the suite per orchestration direction. |

## Regression check (no SEC-fix fallout)

- Full 745-test suite green: MAX coverage matrix (`FinalMaxCoverageMatrixTests`), VPH geometry/routing, HUD language picker, ASR-only ADR-022 pins, S8/S9/S11 contracts, settings round-trip — no regression from the security diff.
- `run_all.sh` 39/39 including VPH contract, hotkey/HUD surface, stores wiring, localization, and all security guards.
- Guard self-tests confirm fail-closed behavior for every SEC-001…004 seam mutation.

## Gap-hunt

No new tests or guards were added: Attempt 8 left no real gap within retest scope. The shared path predicate is unit-tested, the transcription seam has a dynamic no-write exploit test, the polishing seam is pinned fail-closed by `check_sec_download_path_safety.sh` (preflight + per-entry re-check + typed error), and SEC-002…004 each carry dynamic regression tests plus guard pins. Per role, no `Sources/**` changes, no git ops.

**RESULT: `qa_green`**

---

# FINAL-APPLICATION-EXHAUSTIVE-MAX-PLUS-SECURITY-SURFACE

**Date:** 2026-08-08
**Actor:** Independent Test Engineer (MAX campaign) + authorized security-surface hunter
**Result:** **`qa_green`** (functional) · **`findings_open`** (security: 4 low/medium, 1 info — no critical/high)
**Suite:** FINAL-APPLICATION-EXHAUSTIVE-MAX-PLUS-SECURITY-SURFACE
**Baseline:** PRE `bolabol/pre-VERTICAL-PULSE-HUD`; working tree with approved VPH fix attempt 7 (uncommitted, as directed — no git ops by Tester)

## Gate summary

| Gate | Result |
|------|--------|
| `swift test` | **PASS** — 740 tests in 31 suites (677 baseline + 63 new) |
| `swift test --sanitize=thread` | **PASS** — 740 tests, no data races |
| `./script/qa/run_all.sh` | **PASS** — 39/39 (33 baseline + 6 new `check_sec_*`) |
| `check_vertical_pulse_hud_contract.sh` + `--self-test` | **PASS** |
| All 6 new `check_sec_*.sh --self-test` | **PASS** (each has a negative fixture self-test) |
| BUG-HHP-001…008 regression tests | all 8 now **PASS** (fixed by later attempts; BUG_REPORT updated to closed) |

## New tests/scripts added

| Asset | Kind | Tests/assertions (approx, loop-expanded) |
|-------|------|------------------------------------------|
| `Tests/NativeBolabolCoreTests/FinalMaxCoverageMatrixTests.swift` | 7 suites / 47 tests | ~4,385 assertions: HUD panel/capsule geometry matrix (3 styles × 7 scales × states), pixel-stable anchor across R/1/2/humor/processing, full D/1/2/3/4 row unclipped, hit-circle disjoint/containment, 8–10pt margin band, circle-vs-bounding-square corners, picker ≤196pt, language menu policy matrix (backends × purposes × pairs), BUG-VPH-006/007 regressions, ADR-022 picker+session rejection, session resolver matrix (10 models × ops × languages × availability), Canary R/E switching + ephemeral override, GigaAM fixed-RU, settings round-trip (3×16×3×5 enum matrix), decode clamping, AppText 26 keys × 15 locales, provider scroll/cooldown/non-finite, coordinator ownership+timeout |
| `Tests/NativeBolabolCoreTests/SecuritySurfaceRegressionTests.swift` | 6 suites / 16 tests | ~130 assertions: SharedModelsRoot path-trust (outside-root, dot-dot, symlink escape, precedence, containment), settings decode hardening (garbage/wrong-type/extreme payloads), prompt-injection containment (8 hostile transcriptions × immutable editor contract), worker IPC typed-JSON round-trip with hostile payloads, sanitizer reasoning-leak matrix, provider/retry hygiene |
| `script/qa/check_sec_download_path_safety.sh` | guard + self-test | Pins CDN manifest traversal protection (`..`/absolute/empty rejection, SHA-256 verify, validatedManifest gate) |
| `script/qa/check_sec_no_pii_in_logs.sh` | guard + self-test | Extracts every multi-line `NativeBolabolLog` statement; fails on secret/raw-text interpolation and any `print`/`NSLog` in Sources |
| `script/qa/check_sec_process_launch.sh` | guard + self-test | Subprocess allowlist (`/usr/bin/*`, bundle worker), no shell `-c`, no interpolated argv |
| `script/qa/check_sec_url_endpoints.sh` | guard + self-test | HTTPS-only + reviewed host allowlist for every hardcoded endpoint |
| `script/qa/check_sec_keychain_defaults.sh` | guard + self-test | No secret-like UserDefaults keys; Keychain generic-password + ThisDeviceOnly; no credential file writes; no key-in-URL except Google upload |
| `script/qa/check_sec_worker_ipc.sh` | guard + self-test | Worker stdin-only typed JSON, no argv trust, bundle-resolved binary, no dynamic code loading |

Total new automated assertions ≈ **4,500**; combined with the pre-existing 677-test suite (itself loop-expanded) the campaign exceeds the 5,000 scenario/assertion target. All six new guards are fail-closed, wired into `run_all.sh` via the existing `check_*.sh` glob, and carry negative-fixture `--self-test` modes.

## Interactive inventory → evidence map

| Surface | Evidence (EXECUTED) | Residual |
|---------|---------------------|----------|
| A. App shell (launch/quit/relaunch/menu/about) | `ReleaseIdentityTests`, `check_release_identity.sh`, Orchestrator status builds (PID 3369 codesign deep-strict OK) | Live window focus/quit-confirm: NOT_EXECUTED (no safe UI automation harness; app has no quit-confirm dialog by design) |
| B. Sidebar / notes CRUD, search, retention | `NoteStoreTests`, `SidebarLayoutMetricsTests`, `check_workspace_ui_surface.sh`, `check_stores_wiring.sh`; BUG-HHP-004/005 regressions green | Visual scroll/empty-state rendering: covered by layout-metrics statics |
| C. Composer / output variants D/1/2/3/4 | `HUDLayoutAndComposerTests`, `FocusedTextInsertionTests`, `check_hotkey_hud_surface.sh`, new prompt-row-unclipped matrix (7 scales) | Real AX insertion into third-party apps: NOT_EXECUTED (OS-level, no safe harness) |
| D. HUD Vertical Pulse | New geometry matrix: capsule pixel-stability across R↔1↔2↔humor↔processing (3 styles × 7 scales), unclipped D/1/2/3/4 row at 0.8/1.0/1.35/1.6, circle hit geometry + 8–10pt margin at all scales, bounding-corner rejection (AppKit≡SwiftUI shared circle), picker ≤196pt, drag-start outside controls, popover lifecycle via existing `HUDLanguagePickerPopoverTests` + `check_vertical_pulse_hud_contract.sh` | Real pointer hover on physical panel: NOT_EXECUTED (no AppKit harness); geometry fully pinned by shared-policy tests |
| E. Hotkey / session | `HotkeySessionCoordinatorTests` + new ownership/timeout matrix (steal attempts, stuck-processing expiry, live-recording persistence), `HotkeySettingsTests`, `check_hotkey_hud_surface.sh`; permission-denied path: `AccessibilityPermissionPromptStateTests` | OS permission dialog interaction: NOT_EXECUTED (cannot safely reset TCC) |
| F. Settings tabs/controls | `SettingsLocalizationTests`, `GeneralSettingsTests`, `TranscriptionModelSettingsTests`, `PolishingModelSettingsTests`, `APIProviderSettingsTests`, `check_settings_surface.sh`, new round-trip matrix (theme × uiLanguage × style × position = 720 combos) + decode clamping + unknown-enum rejection + styleOrigins filtering | Visual keyboard/VO traversal of Settings window: NOT_EXECUTED (no harness) |
| G. Models/engines/backend matrix | New resolver matrix over all 10 catalog models (Whisper en/multi × 5, Parakeet, Canary Flash, Canary 1B, GigaAM): availability, typed unavailability (noActiveModel/incomplete/unsupportedOS/unsupportedSource/translationUnsupported), S11 routing via existing `S11SessionRoutingTests`, ADR-022 ASR-only pinned twice (picker + resolver), BUG-VPH-006 Parakeet-Auto-Russian hint pinned, presence contract `check_s8_download_contract.sh`, `ModelPresenceVerificationTests`, incomplete-folder rejection tests | Live model downloads: NOT_EXECUTED (opt-in only; no paid/network calls by policy) |
| H. Translation / polish | `TranslationRuntimeContractTests`, `TranslationPromptTests`, `check_no_nllb_translation.sh`, `check_cloud_providers.sh`, humor idempotency (BUG-HHP-001 regression green), new prompt-injection containment matrix; Canary absent from translation runtime (`acceptedADR021…` green) | Live cloud translation call: NOT_EXECUTED (no paid calls) |
| I. Audio modal / retranscription | `AudioRecordingTests`, `RecordingTranscriptionWorkflowTests`, `check_transcription_polishing_pipeline.sh`, AppText audio-modal keys localized (new matrix) | Live playback UI: NOT_EXECUTED (no harness) |
| J. Localization / a11y | New AppText matrix: 26 touched-surface keys × 15 locales non-empty/non-raw + speech-language names in 5 locales × 31 codes; `AppTextFullCoverageTests`, `check_s3_i18n_locales.sh`, `check_localization_surface.sh`, `check_i18n_b2_b4_families.sh`; VO labels pinned by existing HUD a11y contract tests | RTL visual overflow: NOT_EXECUTED (cheap asserts absent for AppKit panels; recorded residual) |
| K. Cross-links / invariants | Every new guard is fail-closed with `--self-test`; backend × language-mode matrix parameterized in resolver suite; persistence set→save→reload asserted (720-combo round-trip); `check_test_coverage_breadth.sh` (67→69 test files) | — |

## Security surface (detailed in SECURITY_REPORT.md)

Hunted: secrets, path traversal, download destinations, URLSession surface, prompt/path injection, worker IPC, keychain, entitlements, logging PII, Python runtime, SSRF-ish endpoints.

**Verdict: `findings_open`** — 0 critical/high; 2 medium (SEC-001 remote tree paths used unsanitized in two HuggingFace download seams; SEC-002 symlink resolution gap in `SharedModelsRoot.location` for non-existent tails), 2 low (SEC-003 `*.py` remote artifacts downloaded into model cache; SEC-004 `</transcription>` wrapper delimiter not escaped in polishing prompt), 1 info (SEC-005 `BOLABOL_CDN_BASE_URL` env override). Hardened seams pinned by 6 new guards + 16 security tests. No secrets, no Python in Sources, no shell launches, HTTPS-only allowlisted endpoints, Keychain device-only.

## NOT_EXECUTED residual (rare, justified)

1. Real AppKit pointer/hover/VO interaction with the live HUD panel — no safe UI automation harness exists; all geometry/hit policy is pinned through the shared pure seams consumed by both AppKit and SwiftUI.
2. OS permission dialogs (TCC mic/accessibility) — cannot be safely reset/automated.
3. Live network downloads / paid cloud calls — opt-in only by project policy.
4. RTL visual overflow on AppKit panels — no cheap deterministic assert available.

---

# HUD-HUMOR-PROMPTS Exhaustive Application QA

**Date:** 2026-08-07
**Actor:** Independent Test Engineer / Exhaustive QA Engineer
**Result:** **`bugs`**
**Open defects:** BUG-HHP-001 through BUG-HHP-008
**Scope:** HUD Variant 2 humor, HUD prompt switching, Reviewer fixes, application-wide regression/stress/coverage/script/runtime pass

## Environment

| Item | Value |
|------|-------|
| Host | macOS 26.5.2 (25F84), arm64 |
| Swift | Apple Swift 6.3.3, target arm64-apple-macosx26.0 |
| Package target | macOS 14+, SwiftPM |
| Graph | Existing `graphify-out/graph.json`, stated current 6,043 nodes / 13,704 edges; no rebuild |
| Cloud | No paid/network provider request executed |
| User data | Existing dirty `UserData/Glossaries/SmartScribe-glossary_Tech+.json` observed at baseline; never read, edited, or removed by QA |
| Models | Existing scratch and installed models used read-only by opt-in smokes; no download/delete/mutation |

## GraphiFy gate

All five required queries ran before broad source inspection, followed by targeted explain/path calls:

| Query | Executable result |
|-------|-------------------|
| HUD humor/session/workflow/provider policy, budget 5000 | 467 nodes; resolved `HumorSessionState`, `HumorSessionSnapshot`, `HUDInteractionPolicy`, `PolishingWorkflow.make`, ContentView freeze/update helpers and focused tests |
| All entry points/buttons/settings/panels/alerts, budget 6000 | 729 nodes; resolved onboarding, ContentView, HUD, notes, glossary, translation, model stores and settings surfaces |
| Tests/scripts/uncovered services/stores/error/persistence, budget 6000 | 256 nodes; highlighted application stores/views with little behavioral coverage |
| Lifecycle/crash/race/cancellation/cleanup, budget 5000 | 475 nodes; resolved app lifecycle, hotkey manager, overlay panel, timers/tasks, audio and download lifecycles |
| Localization/a11y/keyboard/reduced motion/screens, budget 4000 | 214 nodes; resolved 15-locale tests, HUD a11y policy and untested AppKit interactions |
| `graphify explain HumorSessionState` | Degree 13; ContentView creates/updates/freezes state; tests call real freeze seam |
| `graphify explain HUDInteractionPolicy` | Pure hit-testing and accessibility-hidden policy |
| `graphify path HumorSessionState PolishingWorkflow` | 3 hops through shared humor model; product wiring separately confirmed at call sites |
| `graphify path HotkeySessionOverlayManager PromptTemplateStore` | 2 hops through ContentView |

GraphiFy CLI warned that installed package 0.9.33 is newer than skill 0.9.20. The graph remained queryable; no rebuild/install was attempted.

## Baseline and isolation

| Check | Result |
|-------|--------|
| `git status --short --untracked-files=all` | Dirty monorepo with existing Bolabol product/test/GraphiFy/UserData changes plus unrelated sibling-project changes; preserved as-is |
| `git diff --stat` | 437 pre-existing changed files across parent monorepo |
| `git diff --check` | Exit 1 due unrelated `VaniScript/.../CloudAudioTranscriptionEngine.swift:744` blank line at EOF |
| Scoped `git diff --check -- Tests script/qa AI reports` | Exit 0 before report insertion |

Safe temporary root: `/var/folders/x0/5c_9ph9s67bd4vplgt29f_sh0000gn/T/opencode/bolabol-hhp-qa.0u9pSB`.

- App launch used isolated `HOME`, `CFFIXED_USER_HOME`, and `TMPDIR` under that root.
- Note/audio regressions created UUID-named temporary roots and removed them with `defer`.
- QA self-tests used `mktemp -d` and quoted traps.
- The main temporary root was removed and verified absent at the end.
- No real UserDefaults suite, Keychain credential, note/glossary file, model folder, or production download was changed.

## Application coverage inventory

| Subsystem | Public/user entry points | Existing tests | Existing QA scripts | Automated coverage | Manual-only coverage | Missing happy / negative / boundary / lifecycle | Proposed or added |
|-----------|--------------------------|----------------|---------------------|--------------------|----------------------|-----------------------------------------------|-------------------|
| Startup/lifecycle | app launch, status item, main/settings windows, quit | `ReleaseIdentityTests` | package/release/store/UI guards | Build/source identity only | window reopen, status item, quit-in-flight, focus | AppDelegate behavior, crash-loop, single instance, worker shutdown | Isolated 5-second release launch; retain future UI harness gap |
| Onboarding | 8 steps, Back/Next, Try modes, languages/models/permissions/theme | onboarding recommendation/localization/language tests | S1c/S2/S3 guards | Strong pure/static | navigation/layout/permission UI | Try Record consumer missing; window/VO paths | Added `onboardingTryRecordNotificationHasAProductionConsumer` |
| Permissions | microphone/accessibility requests/deep link | prompt-state and selected-text tests | surface guards | Prompt-once model only | OS dialogs/revocation/degraded UI | service/store lifecycle, revoked mid-session | Manual protocol; no safe OS permission reset |
| Recording/audio | main/note/translation record, import/drop, playback | recording workflow, audio model, routing | pipeline/hotkey guards | Core workflow strong | real mic/device changes/playback UI | recorder/importer/device disconnect/multichannel | Runtime ASR from files; residual audio harness gap |
| Global hotkeys | primary/secondary/translation/settings | settings/coordinator tests | hotkey HUD guard | Model/ownership strong | Carbon registration/conflicts/secure input | registration cleanup, repeats, focus loss | Existing deterministic coordinator repeated 20x |
| HUD | listening/processing, language/target/provider/prompt/humor | HUD layout/spectrum/provider/session/a11y tests | HUD/provider/new humor guard | Strong pure/static | real panel hover/click/focus/screens/reduced motion | AppKit panel lifecycle and non-finite scroll | Added non-finite regression + production wiring guard |
| Transcription routing | hotkey/main/sidebar/audio/import/cloud | S9/S11/routing/catalog/engine tests | S8/S9/pipeline guards | Strong | live UI route labels | contradictory Canary translation contract | Added ADR-021 regression; real GO smokes |
| Local models | install/retry/delete/select/readiness | S8/S9 presence/download/catalog | S4b/S8/S9/security guards | Strong fixtures/contracts | low disk/network UI/cancel active | live transport cancellation, delete-active | Existing no-download policy preserved; no production download |
| Polishing | V1/V2, note/sidebar/audio/hotkey, local/cloud | workflow/policy/sanitizer/model tests | polishing/cloud guards | Strong core | live MLX/cloud cancellation/alerts | idempotence, stale concurrent completion | Added humor translation/idempotence/stress coverage |
| Prompts | default/V1/V2/custom slots/settings/HUD | 29 prompt tests plus humor tests | request policy/new HUD guard | Strong model/persistence | HUD click/focus/long visual labels | repeated runtime block; AppKit selection lifecycle | Added empty/long/Unicode/multiline/idempotence tests |
| Providers | local/cloud/model picker/HUD switch | API/provider/retry/switcher tests | cloud/provider guards | Strong models | live HTTP/keychain/menu UI | malformed transport/stale menu/NaN | Added non-finite switcher regression |
| Notes | create/edit/delete/clear/archive/audio/retranscribe | `NoteStoreTests` | workspace/store guards | Good CRUD/persistence | destructive dialog interaction | retention ownership and imported-source deletion | Added two critical red regressions |
| Glossaries | CRUD/import/export/merge/rewrite | glossary store/rewriter/starter tests | settings/UI guards | Good | popovers/file panels | malformed CSV/JSON simultaneous edits | Existing temp-backed tests; future malformed import tests |
| Translation | modal/floating/selection/record/copy/glossary | prompt/selected-text/runtime tests | no-NLLB/cloud checks | Partial | windows/focus/clipboard/timeout | ADR contradiction, hard-coded copy, stale results | Added ADR/localization regressions; fixed always-green NLLB check |
| Focused insertion | hotkey output, AX/clipboard fallback | range snapshot tests | hotkey/pipeline guards | Pure range only | real AX/secure field/clipboard restore | dispatcher AX seam appears unexercised | Residual risk; no OS-safe harness |
| Settings | all tabs and controls | model defaults/migrations/localization | settings/surface/store checks | Strong model/static | keyboard/VO/alerts/relaunch | application-store corruption/keychain failure | Humor observer regression added |
| Localization | all 15 AppText maps | full/settings/onboarding/archive tests | S3/i18n/localization checks | Strong AppText | visual truncation/RTL | hard-coded SwiftUI literals | Added Translation literal regression |
| Persistence/migrations | notes/glossary/settings/prompts/models | extensive Codable/store tests | model/presence guards | Good Core, weak app stores | forced termination recovery | corrupt UserDefaults/keychain/concurrent writes | Temp fixture strategy; no real preferences touched |
| Alerts/error UX | transcription, download, glossary, notes, model sheets | localization/model state tests | settings/localization guards | Static inventory | Escape/stack/retry/focus/secret leakage | behavior harness absent | Inventory below; manual items NOT_EXECUTED |
| Concurrency/stress | session freeze/provider/prompt/model/note tasks | coordinator/workflow async tests | repeat runner | Deterministic Core stress | AppKit/task-generation races | stale completions and app-store concurrent writes | 100 freeze cycles; 140 repeated suite runs; sanitizers |

## Humor slider feature matrix

| # | Scenario | Result / evidence |
|---|----------|-------------------|
| 1-3 | Defaults, legacy decode, round trip | PASS: `HotkeySettingsTests` 11/11 |
| 4-7 | Disabled/enabled, V1 isolation, V2 injection | PASS except repeated application: real workflow/factory tests |
| 8-10 | Exactly one runtime marker/level; static prose excluded | PASS for one application; **FAIL on repeat**, BUG-HHP-001 |
| 11 | Every humor mode | PASS: all cases and factory mode loop |
| 12 | 0/20/40/60/80/100 | PASS |
| 13-17 | below 0, above 100, NaN, +inf, -inf | PASS: clamp and non-finite fallback |
| 18-19 | 10/30/50/70/90 and explicit rounding | PASS: ties away from zero |
| 20 | Repeated application no duplicate | **FAIL**, 2 runtime blocks, BUG-HHP-001 |
| 21-25 | empty, long, Unicode, multiline, marker-like prose | PASS: new edge-body matrix; 10,000 repeated sections |
| 26-27 | listening update and processing freeze | HUD update PASS; Settings update **FAIL**, BUG-HHP-002; freeze semantics PASS |
| 28-30 | settings/prompt/variant mutation after freeze | PASS for immutable value snapshot; settings-listening gap remains BUG-HHP-002 |
| 31-35 | cancel/failure/finish cleanup, retry/new session | PASS by existing source/session contract plus 100 fresh cycles; AppKit path not directly instantiated |
| 36-37 | live preference survives cancel; frozen request unchanged | PASS: explicit contract test |
| 38-40 | Content/Sidebar/Audio use same factory | PASS static new guard and production factory test |
| 41-42 | local/cloud snapshot without paid call | PASS static Content forwarding; cloud network NOT_CALLED |
| 43-45 | raw/translation/disabled do not receive humor | PASS: raw excluded; Translation modal uses V1 pass-through; disabled omits both markers |
| 46 | rapid slider updates deterministic | PASS through 100 state update/freeze cycles |
| 47 | 100 freeze/clear cycles | PASS; no state leakage |
| 48 | concurrent settings writes | NOT_EXECUTED: app store is MainActor/private and no injectable safe concurrent seam; no claim of coverage |
| 49 | current-level accessibility metadata | PASS: label/value/adjustable policy |
| 50 | localization in all 15 locales | PASS: 23 Settings localization tests and full locale map tests |

## HUD prompt/provider interaction matrix

| # | Scenario | Result / evidence |
|---|----------|-------------------|
| 1-4 | default, V1, V2, custom slots | PASS: fixed five-slot `PromptSlot` model and 29 prompt tests |
| 5-7 | empty list, one slot, maximum slots | N/A for product prompt bar: enum always exposes exactly five; provider empty/one/many policy PASS |
| 8-9 | current selection and selected/unselected a11y | PASS pure metadata tests |
| 10 | left click | STATIC PASS: button updates active slot and invokes handler |
| 11-12 | right click, scroll | N/A for prompt buttons by accepted contract; right-click/model and scroll remain provider controls and are tested |
| 13-18 | precise/non-precise/below/exact/accumulate/reverse | PASS provider model |
| 19-20 | first/last boundary | PASS wrapping model |
| 21-24 | rapid click/alternation/scroll burst | Core deterministic selection PASS; real AppKit click burst NOT_EXECUTED |
| 25-27 | interaction during hide/re-show | NOT_EXECUTED: no AppKit harness; static hide clears hover/timer |
| 28-30 | hover enter/exit/hide without exit | STATIC PASS: handlers and hide reset; real pointer NOT_EXECUTED |
| 31-32 | stale callback/generation guard | STATIC PASS in overlay layout generation; callback race NOT_EXECUTED |
| 33-35 | hidden hit-test/a11y and visible hit-test | PASS pure policy and source guard |
| 36-39 | Escape/outside/focus/no input after dismiss | NOT_EXECUTED; provider timer dismissal is static-only, no focus harness |
| 40-41 | prompt/provider orthogonality | STATIC PASS: separate handlers/models |
| 42-45 | pending/frozen/cancel/retry selection | PASS value snapshot/source lifecycle; AppKit click lifecycle not executed |
| 46 | empty prompt body | PASS fallback/edge runtime-body tests |
| 47-49 | long/localized/Unicode/RTL names | Localization resolution PASS; visual fit/RTL focus NOT_EXECUTED |
| 50-51 | 100 show/hide and selection cycles | Freeze/selection model stress PASS; actual panel show/hide NOT_EXECUTED |
| 52-53 | no monitor/timer/task accumulation | Static: no prompt monitor; provider timer invalidated/replaced. Runtime leak instrumentation NOT_EXECUTED |
| 54 | Reduced Motion | NOT_EXECUTED; source currently uses unconditional animations, residual risk |
| 55-59 | multi-monitor/scale/edge/small/full-screen | Position clamp source inspected; visual tests NOT_EXECUTED |
| 60 | VoiceOver focus order | Metadata PASS; actual focus order NOT_EXECUTED |
| Additional | non-finite scroll | **FAIL**, BUG-HHP-003 |

## Application regression summary

| Area | Result |
|------|--------|
| Startup/release | Release build/sign/verify PASS; isolated binary stayed alive 5 seconds; full UI lifecycle not automated |
| Onboarding | Localization/recommendations PASS; Try Record consumer **FAIL**, BUG-HHP-006 |
| Permissions | Pure prompt state PASS; real OS dialogs/revocation NOT_EXECUTED |
| Recording/audio | Workflow/routing PASS; real runtime files PASS; mic/device/playback UI NOT_EXECUTED |
| Hotkeys | Settings/coordinator PASS 20/20; Carbon registration manual-only |
| HUD | Core layout/a11y PASS; idempotence/settings snapshot/non-finite defects open |
| Routing/models | Unit contracts plus all three real engines PASS; Canary translation architecture **FAIL** |
| Polishing/prompts | Factory/V1/V2/modes/translation edge PASS; repeat idempotence **FAIL** |
| Providers | Models/retry/list PASS; non-finite delta **FAIL**; no paid calls |
| Notes | CRUD/persistence PASS; two critical retention/ownership defects open |
| Glossary | Existing CRUD/CSV/rewrite suite PASS; manual popovers/file panels not executed |
| Translation | Prompt/cloud boundary PASS; ADR and localization regressions open |
| Settings/localization | 15-locale model tests PASS; Translation literals and humor observer open |
| Persistence/concurrency | Core persistence and 100-cycle stress PASS; app-store/keychain concurrency remains blocked by seam |

## New tests added

`Tests/NativeBolabolCoreTests/HumorStyleControlTests.swift`:

- `runtimeControlsRemainIdempotentWhenAppliedRepeatedly` - red BUG-HHP-001.
- `runtimeControlsHandleEmptyLongUnicodeAndMarkerLikePromptBodies` - green.
- `humorSessionRunsOneHundredFreezeAndFreshSessionCyclesWithoutStateLeakage` - green.
- `humorRuntimeControlCoexistsWithTranslationWithoutLeakingIntoRawOrVariantOne` - green.

`Tests/NativeBolabolCoreTests/HUDProviderSwitcherFeatureTests.swift`:

- `hudProviderSwitcherIgnoresNonFiniteScrollWithoutPoisoningLaterInput` - red BUG-HHP-003.

`Tests/NativeBolabolCoreTests/NoteStoreTests.swift`:

- `audioRetentionLimitCountsOnlyAudioNotesAndPreservesTextNotes` - red BUG-HHP-004.
- `deletingImportedAudioNoteNeverDeletesTheUsersSourceFile` - red BUG-HHP-005.

New `Tests/NativeBolabolCoreTests/ApplicationWideRegressionContractTests.swift`:

- `contentViewSettingsHumorLevelChangeUpdatesThePendingListeningSnapshot` - red BUG-HHP-002.
- `onboardingTryRecordNotificationHasAProductionConsumer` - red BUG-HHP-006.
- `acceptedADR021KeepsCanaryOutOfTheTranslationRuntime` - red BUG-HHP-007.
- `translationUserFeedbackAndGlossaryActionsUseLocalizedCopy` - red BUG-HHP-008.

No failing test was skipped, weakened, or removed.

## QA scripts

| Script | Change | Self-test / result |
|--------|--------|--------------------|
| `check_hud_humor_prompt_contract.sh` | New; three production factories, pending listening level, hit-testing/a11y | Negative self-test PASS; repository FAIL BUG-HHP-002; auto-included by `run_all` glob |
| `coverage_inventory.sh` | New reproducible LLVM source coverage report; `--refresh` option | Report generated after manual profraw merge because failing tests prevent SwiftPM final profile merge |
| `repeat_critical_suites.sh` | New deterministic no-sleep flake runner | 20 iterations, 140 runs, honest aggregate exit |
| `check_sec_no_download_code.sh` | Fixed Pattern 3 always-empty filter, evaluated Pattern 4, path-safe loop, fail on missing Sources, no missing-`rg` false green | Negative self-test PASS; repository PASS |
| `check_no_nllb_translation.sh` | Fixed missing-`rg` always-green behavior by using available grep; added empty-scan failure | Negative self-test PASS; repository PASS |
| `check_s1b_scope.sh` | Not changed by Tester | FAIL reflects BUG-HHP-007; do not allowlist product defect |
| `check_s6_gigaam_spike.sh` | Not changed by Tester | FAIL inherited from S1b/BUG-HHP-007; GigaAM spike checks themselves pass |
| `check_s9_engine_contract.sh` | Not changed by Tester | FAIL exposes ASR-only expected names replaced by AST tests, part of BUG-HHP-007 |

All 30 current `check_*.sh` files are discovered by `run_all.sh`; no dead script exists. Audit found additional low-priority comment/string-only fragility in several historical checks; these remain residual test-infrastructure risk rather than being broadly rewritten in a product-bug turn.

## Coverage summary

`swift test --enable-code-coverage` executed all 617 tests present at that point and failed on the 18 then-known issues. Because SwiftPM did not merge `default.profdata` after a red run, the two emitted `.profraw` files were merged with `xcrun llvm-profdata merge`; `coverage_inventory.sh` then produced:

| Metric | Coverage |
|--------|----------|
| Source regions | 22.73% (2,461 / 10,826) |
| Source functions | 21.52% (933 / 4,336) |
| Source lines | 16.96% (7,677 / 45,270) |
| `HumorStyleControl.swift` lines | 77.39% |
| `PolishingWorkflow.swift` lines | 98.38% |
| `ProviderQuickSwitcherModel.swift` lines | 100% |
| `NoteStore.swift` lines | 81.25% |
| `ContentView`, overlay manager, most SwiftUI views | 0% behavioral line coverage |

The percentage is not treated as proof of quality. The key finding is the large 0% application/UI/store surface despite strong Core tests.

## Sanitizer and stress results

| Command | Exit | Tests | Duration | Result |
|---------|------|-------|----------|--------|
| `swift test --sanitize=thread` | 1 | 617, 18 known issues | 107.40s | FAIL due product regressions; no ThreadSanitizer diagnostic emitted |
| `swift test --sanitize=address` | 1 | 617, 18 known issues | 121.20s | FAIL due product regressions; no AddressSanitizer diagnostic emitted |
| `bash script/qa/repeat_critical_suites.sh 20` | 1 | 140 suite-runs | 267.70s | 100 PASS, 40 expected FAIL: Humor + HUDProvider each failed 20/20; no additional nondeterminism |
| Full suite repeat 1 | 1 | 617 / 18 issues | 3.37s | Same failures |
| Full suite repeat 2 | 1 | 617 / 18 issues | 1.02s | Same failures |
| Full suite repeat 3 | 1 | 617 / 18 issues | 1.02s | Same failures |

The final localization regression increased the final suite to 618 tests / 21 issues; it was separately reproduced and included in the final full run.

## Focused command results

| Command | Exit | Executed / unavailable | Duration | Result / artifacts |
|---------|------|------------------------|----------|--------------------|
| `swift test --filter HumorStyleControlTests` | 1 | 13 / 0 | 9.51s | 12 pass; idempotence test fails with 2 issues |
| `swift test --filter PromptTemplateTests` | 0 | 29 / 0 | 1.06s | PASS |
| `swift test --filter HotkeySettingsTests` | 0 | 11 / 0 | 1.05s | PASS |
| `swift test --filter SettingsLocalizationTests` | 0 | 23 / 0 | 1.04s | PASS |
| `swift test --filter HUDProviderSwitcherFeatureTests` | 1 | 15 / 0 | 1.10s | 14 pass; non-finite regression fails with 7 issues |
| `swift test --filter HUDLayoutAndComposerTests` | 0 | 13 / 0 | 1.04s | PASS |
| `swift test --filter ApplicationWideRegressionContractTests` | 1 | 4 / 0 | 8.16s | 9 issues across snapshot/onboarding/ADR/localization |
| `swift test --filter audioRetentionLimitCountsOnlyAudioNotesAndPreservesTextNotes` | 1 | 1 / 0 | 10.26s (parallel SwiftPM wait included) | BUG-HHP-004 |
| `swift test --filter deletingImportedAudioNoteNeverDeletesTheUsersSourceFile` | 1 | 1 / 0 | 11.00s (parallel SwiftPM wait included) | BUG-HHP-005 |
| `bash script/qa/check_hud_humor_prompt_contract.sh --self-test` | 0 | 2 negative mutations | <1s | PASS |
| `bash script/qa/check_hud_humor_prompt_contract.sh` | 1 | source contract | 0.03s | BUG-HHP-002 |
| `check_sec_no_download_code.sh --self-test` | 0 | 3 negative mutations | <1s | PASS |
| `check_no_nllb_translation.sh --self-test` | 0 | 1 negative mutation | <1s | PASS |

Warnings on test/build planning: duplicate `mlx-swift` package identity and one unhandled FluidAudio `benchmark.md` resource.

## Full build and gate results

| Command | Exit | Tests / checks | Duration | Result |
|---------|------|----------------|----------|--------|
| Final `swift test` | 1 | **618 tests**, 21 issues; 4 opt-in runtime functions print UNAVAILABLE in default env | 0.94s | FAIL, deterministic product regressions |
| `swift test --enable-code-coverage` | 1 | 617, 18 issues at time of run | 88.97s | FAIL; raw profiles preserved and merged for report |
| `swift build` | 0 | N/A | 2.98s | PASS |
| `swift build -c release` | 0 | N/A | 2.37s | PASS |
| `./script/qa/run_all.sh` | 1 | 31 steps: **26 pass / 5 fail** | 13.76s | FAIL: Swift suite, new humor guard, S1b, S6, S9 |
| `./script/build_and_run.sh --verify` | 0 | app + worker | 5.68s | PASS; `dist/Bolabol.app` rebuilt/signed |
| Repository-wide `git diff --check` | 1 | N/A | <1s | BLOCKED by unrelated VaniScript EOF blank line |
| Scoped QA-path `git diff --check` | 0 | N/A | <1s | PASS |

Release compilation additionally warned about redundant `await`/`try` in Canary and deprecated `AVAsset.duration`; none blocked the build.

## Real local engine smokes

| Command | Exit | Tests | Duration | Evidence |
|---------|------|-------|----------|----------|
| `BOLABOL_S9_RUNTIME_SMOKE=1 swift test --filter S9RuntimeSmokeTests` | 0 | 8/8 | 59.03s | Flash: `The quick brown fox jumps over the lazy dog.`; Flash long: 50 words; 1B same expected English; GigaAM non-empty Russian; rank-one position PASS |
| `BOLABOL_INSTALLED_MODEL_SMOKE=1 swift test -c release --filter S9RuntimeSmokeTests` | 0 | 8 framework tests; 4 scratch-only paths unavailable under this env | 332.77s including release test build | Installed Flash cold 28.050s/warm 0.090s; 1B cold 2.173s/warm 0.211s; GigaAM cold 9.151s/warm 0.118s; all expected language/non-empty |

No model substitution was observed: output logs identify each exact installed model ID. Malformed/unsupported request rejection remains covered by unit language/capability tests, not these happy-path runtime smokes.

## Manual release matrix

The signed release binary was launched directly with isolated `HOME`, `CFFIXED_USER_HOME`, and `TMPDIR`. It remained alive for 5 seconds and terminated cleanly on the QA signal. No `Bolabol*.ips` or `Bolabol*.crash` report exists in `~/Library/Logs/DiagnosticReports`.

| Manual item | Status | Evidence / reason |
|-------------|--------|-------------------|
| App launches / no immediate crash | PASS (bounded smoke) | Isolated release process alive after 5s; no crash report |
| Status item / main window | NOT_EXECUTED | No safe visual automation/UI inspection tool in session |
| Settings and every tab/control | NOT_EXECUTED | Would require interactive GUI and risk real preference mutation |
| HUD show/hide/hover/prompt/humor/provider | NOT_EXECUTED | Requires global hotkey/mouse/permission automation; Core/source checks reported separately |
| Hotkey registration | NOT_EXECUTED | Carbon/system conflict testing unavailable in isolated harness |
| Recording start/cancel | NOT_EXECUTED | No permission-safe real microphone interaction |
| Note creation / delete confirmations | NOT_EXECUTED | Real user data must not be mutated |
| V1/V2 live polish | NOT_EXECUTED | No isolated UI store harness; no paid cloud call allowed |
| Accessibility labels/focus/reduced motion | NOT_EXECUTED | VoiceOver/UI automation unavailable |
| Alerts/panel dismissal/focus restoration | NOT_EXECUTED | Requires interactive AppKit harness |

## Alerts, sheets, popovers, and errors inventory

| Surface | Trigger/actions | Automated result | Manual gap |
|---------|-----------------|------------------|------------|
| Content transcription failure alert | `sessionWarningMessage`; localized title/message; localized Close cancel clears state | Static/localization PASS | repeat stacking/Escape/focus NOT_EXECUTED |
| Large model download alert | >1 GB warning; localized confirm starts download; localized Cancel | Descriptor/S8/static PASS | disk/network/cancel UI NOT_EXECUTED |
| Clear glossary alert | localized Cancel + destructive Clear; clears filters/status | Static/localization PASS | Escape/focus/repeat NOT_EXECUTED |
| Sidebar Clear All confirmation | localized destructive Clear All + Cancel | Static localization; NoteStore behavior tested | UI cancel/Escape NOT_EXECUTED; deletion bugs affect underlying behavior |
| Translation and onboarding sheets | Content bindings; dismiss notification clears both | Static source | focus restoration/reopen NOT_EXECUTED |
| Audio playback sheet | note selection opens modal; binding clears on dismiss | Static source | close-during-playback NOT_EXECUTED |
| API model picker sheet | provider model list, selected binding, close binding | Provider tests/static | timeout/error/reopen/focus NOT_EXECUTED |
| Glossary draft sheets/popovers | selected text, custom language, merge picker | Glossary Core tests | pointer/keyboard/escape NOT_EXECUTED |
| Inline recorder/model/provider errors | bounded model states and localized recorder copy in tested areas | Model/settings tests PASS | long path/secret leakage visual audit NOT_EXECUTED |

## Accessibility results

- PASS: hidden HUD prompt/humor controls share one hit-testing/accessibility-hidden policy.
- PASS: prompt slot metadata exposes full label, selected/unselected value, hint, button and selected traits.
- PASS: humor slider exposes localized label, percent value and adjustable action.
- PASS: all new humor/prompt AppText keys resolve in 15 locales.
- FAIL: Translation user-facing copy bypasses AppText, BUG-HHP-008.
- NOT_EXECUTED: VoiceOver focus order, Full Keyboard Access, screen reader visibility in a live panel, contrast, Reduced Motion, multi-monitor and RTL visual layout.

## Legacy QA triage

| Script | Independent classification | Action |
|--------|----------------------------|--------|
| `check_s1b_scope.sh` | Broad historical allowlist is stale, but current failure points at real BUG-HHP-007 | Left red; no allowlist added |
| `check_s6_gigaam_spike.sh` | S6 report/harness checks pass; failure is inherited from S1b/BUG-HHP-007 | Left red; no product bug hidden |
| `check_s9_engine_contract.sh` | Exact names are brittle, but replacements explicitly changed ASR-only tests to AST and contradict ADR-021 | Left red; no stale AST names blessed |
| `check_sec_no_download_code.sh` | Proven false-green test infrastructure | Fixed with three negative self-tests; repository green |
| `check_no_nllb_translation.sh` | `rg` absent, old `2>/dev/null || true` made it always green | Fixed with grep and negative self-test; repository green |

## Blocked and residual risks

- Eight product defects remain open; two meet the project definition of critical data loss.
- UI automation is absent, so button-by-button AppKit interaction, focus, VoiceOver, permissions, multi-monitor, Reduced Motion, secure input, playback and destructive-dialog cancellation are not claimed as passed.
- Main application views and many app stores are at 0% measured line coverage.
- Concurrent UserDefaults/keychain writes and stale async completion require injectable product seams or a dedicated UI/integration harness.
- Historical shell checks still contain comment/string-only false-positive/false-negative risk beyond the two corrected severe cases.
- Repository-wide `git diff --check` remains blocked by an unrelated sibling-project line; scoped QA changes are clean.

## Final verdict

**RESULT: `bugs`**

Builds, signed release verification, localization suites, most focused suites, both real local-engine smoke modes, negative QA self-tests and deterministic stress evidence completed. `qa_green` is prohibited because BUG-HHP-001 through BUG-HHP-008 are open, final `swift test` is red (618 tests / 21 issues), and `run_all` is red (26/31 steps pass).

---

# S9 BUG-003 Fix Feature QA Report

**Date:** 2026-08-05
**Tester:** Test Engineer (independent feature QA; full security audit out of scope)
**Scope:** S9 BUG-003 fix rerun, Path B decoder input contract, and ADR-018 runtime coverage
**Status:** **qa_green**

---

## 1. Graphify gate

The required query ran before source study:

```text
graphify query "S9 BUG-003 Canary 1B Path B decoder pos rank one runtime smoke TranscriptionEngineStore" --graph graphify-out/graph.json
```

Result: **PASS**, 361 related nodes found. The traversal resolved the real `CanaryCoreMLEngine` Path B decoder, `TranscriptionEngineStore`, `S9RuntimeSmokeTests`, the product position seam, and the BUG-003 handoff.

## 2. Scratch assets

All documented assets required by the opt-in smokes were present:

- Flash: `scratch/canary-flash-spike/models/CanaryFlash/` and `scratch/canary-flash-spike/audio/en_short.wav`.
- Canary 1B Path B: `scratch/canary-1b-fix/package/bolabol-canary-1b-v2-coreml-r1/` and `scratch/canary-flash-spike/audio/en_short.wav`. The package contains `canary_encoder.mlmodelc`, `canary_cross_kv.mlmodelc`, `canary_decoder_kv.mlmodelc`, and `canary_spe.model`; no preprocessor is required.
- GigaAM: `scratch/gigaam-spike/models/` and `scratch/gigaam-spike/audio/ru_short.wav`.

No fake fixture or duplicated product parser/builder was created.

## 3. Feature gate results

| Command | Result |
|---|---|
| `swift test --filter canary1BDecoderPositionUsesRankOneProductInput` | **PASS** - 1 test; real product seam returned int32 rank-1 `[1]` and the expected position value |
| `swift test` | **PASS** - 555 tests in 15 suites |
| `./script/qa/run_all.sh` | **PASS** - 29/29 checks |
| `BOLABOL_S9_RUNTIME_SMOKE=1 swift test --filter canary1BOfflineDictationProducesTextWhenScratchIsEnabled` | **PASS** - real Path B returned `The quick brown fox jumps over the lazy dog.` |
| `BOLABOL_S9_RUNTIME_SMOKE=1 swift test --filter S9RuntimeSmokeTests` | **PASS** - 4 tests; Flash, 1B, and GigaAM returned non-empty text and the position regression passed |
| `bash script/qa/check_s9_engine_contract.sh` | **PASS** - S9 constraints, product regression mapping, and token-shape guard |

SwiftPM emitted existing dependency identity/resource warnings during Swift test planning; they did not affect the result. The default `swift test` run printed the expected opt-in smoke availability messages; the two explicit opt-in commands above executed the real assets.

## 4. Independent gap-hunt mapping

| S9 / BUG-003 requirement | Existing coverage and independent result |
|---|---|
| Product `pos` regression | `S9RuntimeSmokeTests.canary1BDecoderPositionUsesRankOneProductInput` calls `CanaryCoreMLEngine.pathBDecoderPositionArray(position:)` and asserts dtype, rank/shape `[1]`, and value. **PASS**. |
| Preserve token contract `[1, 1]` | New `check_s9_engine_contract.sh` guard checks the product decoder call `makeI32([token])` and the real `makeI32` int32 builder shape `[1, values.count]`, which is `[1, 1]` for one token. **PASS**. |
| BUG-003 real Path B behavior | Dedicated opt-in smoke loads the real package and returns non-empty English text. **PASS**; this is the independent closure evidence. |
| All three runtime smokes | `S9RuntimeSmokeTests` covers Flash, Canary 1B, GigaAM, and the position regression. **PASS**, 4/4. |
| Flash constraints | Product uses `.cpuAndNeuralEngine`, true encoder `length`, capability max chunk 10 seconds, and product chunk tests cover the 160,000-sample boundary. Source guard and tests **PASS**. |
| Canary 1B constraints | Product has the macOS 15+/`MLState` gate, native Path B frontend, true `mel_length`/`encoder_length`, 15-second chunking, fresh state per segment, and native `SentencePieceModel` from `canary_spe.model`. Source guard, edge tests, regression, and runtime **PASS**. |
| GigaAM constraints | Product uses RU-only capability validation, HTK frontend at 16 kHz, 30-second chunking, fresh RNNT decode per chunk, valid encoder frames, and blank ID 1024. Source guard, language/chunk tests, and runtime **PASS**. |
| Explicit language through capabilities | Canary and GigaAM product language seams reject nil/unsupported requests; capability tests disable auto-detect for all three GO models. **PASS**. |
| Native-only runtime | `check_no_python_in_sources.sh`, `check_no_canary_product.sh`, S4b/S6 guards, and `check_sec_no_download_code.sh` all passed through `run_all.sh`. No Python runtime was introduced. **PASS**. |
| No S10+ expansion | S9 changes remain in engine/store/test/QA surfaces; existing S8 download, security allowlist, HUD, and product-boundary guards passed. No S10/S11 UI/HUD/catalog/download implementation was added by this QA rerun. **PASS**. |

## 5. New tests and QA

- Added QA-only assertions to `script/qa/check_s9_engine_contract.sh` for the real BUG-003 product seam, the preserved product token call, and the int32 array builder contract.
- No Swift test-side token builder was added: the product token builder is private, and duplicating it would not test product behavior. The existing regression remains a direct call to the real product seam.
- Existing S9 tests provide the remaining construction, store wiring, missing/incomplete folder, language, OS, dtype, chunk, and runtime coverage. This is a no-fake, minimal gap closure.

## 6. BUG-003 closure

The former failure was reproduced in the prior QA run with the real package and the rank-2 `pos` error. This independent rerun now passes the real product regression and the real Canary 1B Path B runtime smoke, with the expected non-empty transcript. BUG-003 is therefore **CLOSED**. No other open S9 product defect was found; `bugs_open` is **0**.

---

# S4b Feature QA Report

**Date:** 2026-08-04
**Tester:** Test Engineer (feature QA only; full vuln-hunt out of scope)
**Scope:** S4b (bolabol-canary-1b-v2-coreml-r1) feature gate verification
**Status:** **qa_green** — all checks executed and verified on local machine

---

## 1. Feature gate results

### 1.1 BOLABOL_COREML_SPIKE.md Status GO + package id ✅
- File: `docs/asr/canary-1b/BOLABOL_COREML_SPIKE.md`
- Verdict: **GO — `bolabol-canary-1b-v2-coreml-r1`**
- Package ID confirmed in report.

### 1.2 check_s4b_canary_fix.sh ✅ (with caveat)
- `docs/asr/canary-1b/BOLABOL_COREML_SPIKE.md` contains GO + package ID: **PASS**
- `docs/canary/harness/CanarySmdesaiSpike.swift` exists and contains required markers (`import Accelerate`, `CoreML`, `Foundation`, `NativeMelFrontend`, `MLState`, `makeState()`, `audio_length`, `mel_length`, `encoder_length`, `ASR_PREFLIGHT`): **PASS**
- Package at `scratch/canary-1b-fix/package/bolabol-canary-1b-v2-coreml-r1/` exists with 8 elements (3 `.mlmodelc` dirs + 5 files): **PASS**
- `canary_preprocessor.mlmodelc` absent from package: **PASS**
- MANIFEST SHA integrity (text files): **PASS** (FRONTEND.md, LICENSE.txt, metadata.json, MANIFEST.json SHA-256 match MANIFEST; large binary sizes match)
- Product boundary (no canary in product Sources except allowed locations): **PASS**

**Caveat:** `VERIFY_S4B_PACKAGE=1` (full SHA verification for all files including binaries) is **OFF by default** in the script. This is a feature gap, not a bug — SHA is not automatically verified in `run_all.sh`. Recommendation: enable by default or add separate `check_sec_s4b_package_integrity.sh`.

### 1.3 Preprocessor absent from package ✅
- Package contains: `canary_encoder.mlmodelc`, `canary_decoder_kv.mlmodelc`, `canary_cross_kv.mlmodelc`, `canary_spe.model`, `FRONTEND.md`, `LICENSE.txt`, `MANIFEST.json`, `metadata.json`.
- **No** `canary_preprocessor.mlmodelc` in package root or subdirectories.

### 1.4 MANIFEST SHA integrity ✅
- Text files verified via SHA-256:
  - `FRONTEND.md`: `fcf748399547af47872f48d2436b988e72664673419a9c8d38c2db11687f513a` ✅
  - `LICENSE.txt`: `944212da165ee581a024c9d51bd21ef7badbf72ad4d00b23a731706ae1ce3c98` ✅
  - `metadata.json`: `1d98e1cceaf4ab9fc69e9178b1a3dedf46e11d835e006f9e88b00f77cc722be7` ✅
  - `MANIFEST.json`: `3a258e36b6a71b95e538656569c455a76c302cd7ca69724b3a7075f0f20202a5` ✅
- Binary weights: sizes match MANIFEST (encoder 1,579,377,472 B, decoder_kv 270,864,448 B, cross_kv 33,589,312 B, tokenizer 503,803 B).

### 1.5 Product boundary check_no_canary_product ✅
- `Package.swift`: no "canary" occurrences.
- `Sources/` and `Tests/`: "canary" found only in:
  - `Sources/NativeBolabolCore/Models/OnboardingModelRecommendation.swift` — ModelSpec IDs (`canary-1b-v2-coreml-r1`, `canary180mFlashCoreML`). Allowed: spec definitions only, no product integration.
  - `Sources/NativeBolabolCore/Services/AppText.swift` — `helpBilingualCanary` key for help guide. Allowed: helpBilingual* keys only.
- No canary-specific code in production paths (Engines, Services, TranscriptionModels, etc.).

### 1.6 S4 NO-GO + S5 GO + S6 dual-checks still green via run_all ✅
- `check_b6_canary_spike.sh` confirms:
  - `docs/canary/COREML_SPIKE.md` (B6): NO-GO + D1-D5 + Recommendation ✅
  - `docs/canary/harness/CanarySpike.swift`: exists, no Python ✅
  - `docs/asr/canary-1b/COREML_SPIKE.md` (S4): NO-GO + F1-F6 + checklist sections ✅
  - `docs/canary/harness/CanaryFluidSpike.swift`: exists, no Python ✅
  - `docs/asr/canary-flash/COREML_SPIKE.md` (S5): GO + F1-F4 + checklist sections ✅
  - `docs/canary/harness/CanaryFlashSpike.swift`: exists, no Python ✅
- All spike reports and harnesses present with correct verdicts.

### 1.7 Runtime EN short — executed ✅
- Fresh harness build: `swiftc -O -parse-as-library docs/canary/harness/CanarySmdesaiSpike.swift -framework CoreML -framework Accelerate` → builds clean, `--help` works.
- Path B EN ASR run (documented command, `modelRoot=scratch/canary-1b-fix/smdesai`, `frontend=native`, CPU):
  - `MEL_PREFLIGHT: PASS` (pearson_mel_energy_envelope=0.701, valid_region_exact_zero_fraction=0.000)
  - transcript: `The quick brown fox jumps over the lazy dog.` — `EOS=true`, no repetition tail, `ASR_PREFLIGHT: PASS` (8.4 s wall).
- Evidence reproduces the spike report claims.

### 1.8 Harness builds ✅
- Full compilation verified locally (`swiftc -O -parse-as-library`, see 1.7). Pre-built binary `scratch/canary-1b-fix/bin/CanarySmdesaiSpike` also functional.

---

## 2. Local execution — completed 2026-08-04 (verified)

| Command | Result |
|---|---|
| `swift test` | ✅ 503 tests, 4 suites, all passed |
| `bash script/qa/check_s4b_canary_fix.sh` | ✅ OK (report GO, harness contracts, package boundary, no-product) |
| `VERIFY_S4B_PACKAGE=1 bash script/qa/check_s4b_canary_fix.sh` | ✅ OK — full SHA-256 + size verification of all 19 manifest files |
| `script/qa/check_no_canary_product.sh` | ✅ zero Canary product/module surface (ADR-012) |
| `./script/qa/run_all.sh` | ✅ 27 passed / 0 failed (incl. dual-checks + `check_sec_s4b_package_integrity.sh` 19/19) |
| `git check-ignore -v scratch/canary-1b-fix` | ✅ ignored via `.gitignore:6`; no tracked package artifacts |
| Runtime EN ASR (see §1.7) | ✅ MEL_PREFLIGHT PASS, ASR_PREFLIGHT PASS |

**QA-script fix applied this pass (script/qa only, no product Sources touched):**
`check_sec_no_download_code.sh` (new, untracked) Pattern 4 false-positived on the
pre-existing sanctioned cloud surface
`Sources/NativeBolabol/Services/CloudProviderModelCatalog.swift` (`fetchModels(`
= GET /models LLM catalog listing, not ASR/CoreML weight download; file present
since the rename commit, unchanged since the S4b checkpoint, presence enforced
by `check_cloud_providers.sh`). Fixed by allowlisting that one file for Pattern
4 only. Defense in depth verified preserved: Patterns 1-3 unchanged; Pattern 1
still catches any future `downloadTask/dataTask` introduced in that file; a
negative test confirms `downloadModelPackage`/`fetchCoreMLWeights` helpers are
still detected.

---

## 3. Feature gaps (non-blocking)

| # | Gap | Impact | Status |
|---|---|---|---|
| FG1 | `VERIFY_S4B_PACKAGE=1` off by default in `check_s4b_canary_fix.sh` | SHA integrity not automatically verified by that script | **Mitigated:** `check_sec_s4b_package_integrity.sh` now runs in `run_all.sh` (19/19 SHA-256 + size) |
| FG2 | `check_no_secrets.sh` does not scan `docs/`, `scratch/`, `AI_Workflow_Kit/docs/` | Potential secret in those dirs may be missed | **Mitigated:** `check_sec_no_secrets_extended.sh` now runs in `run_all.sh` |
| FG3 | No `check_sec_no_download_code.sh` for CDN residual risk | Download code could appear without guard | **Resolved:** script added to `run_all.sh`; Pattern 4 false positive on the sanctioned cloud catalog fixed this pass |
| FG4 | Harness `Models.load` loads `canary_preprocessor.mlmodelc` unconditionally, but the GO package intentionally excludes the preprocessor | Harness cannot use the package dir directly as `modelRoot` (fails at load even with `frontend=native`) | **Non-blocking observation:** documented runtime evidence uses `modelRoot=scratch/canary-1b-fix/smdesai` (extraction dir incl. preprocessor), exactly as recorded in the spike doc. S7+ integrator must not assume harness ⇄ package drop-in; product adapter loads encoder/cross/decoder + native mel only |

These are **low/medium severity**, all non-blocking.

---

## 4. Verdict

**qa_green — verified, not expected.** All feature checks for the S4b contract executed green on the local machine: `swift test` (503), `run_all.sh` (27/27), S4b contract script with and without `VERIFY_S4B_PACKAGE=1`, package SHA integrity 19/19, preprocessor absent, product Canary-free, gitignore boundary holds, harness builds, runtime EN ASR reproduces spike evidence.

No product functional bugs found → **no BUG_REPORT**. The single `run_all.sh` red was a QA-script false positive (new `check_sec_no_download_code.sh` vs. pre-existing sanctioned cloud catalog), fixed in `script/qa/` only.

Out of scope this pass (per role): product `Sources/**` changes, full security/vuln audit (Security Engineer), git commit/push.

---

## S7 Feature QA Report

**Date:** 2026-08-04
**Tester:** Test Engineer (feature QA; full vulnerability hunt out of scope)
**Scope:** S7 Catalog + backends + capabilities, data layer only
**Status:** **qa_green**

### 1. Feature gate

| Command | Result |
|---|---|
| `swift test` | **PASS** — 507 tests in 4 suites |
| `./script/qa/run_all.sh` | **PASS** — 27 passed / 0 failed |
| `check_no_secrets.sh` via `run_all.sh` | **PASS** |
| `check_sec_no_secrets_extended.sh` via `run_all.sh` | **PASS** |

### 2. Gap-hunt mapping

| S7 requirement | Evidence |
|---|---|
| Backend cases exist | Existing catalog coverage plus new exact runtime-badge test for WhisperKit, FluidAudio, Canary, and GigaAM. |
| Three GO descriptors and honest capabilities | Existing GO trio/order test; new exact 10/15/30 second chunk limits, language lists, download sizes, and macOS 15 capability assertions. |
| Ranking IDs resolve to catalog entries | Existing `OnboardingModelRecommendation` matrix and S2 ranking tests pass against the current catalog IDs. |
| QA permits GO surface and blocks engines/NO-GO sources | `check_no_canary_product.sh`, dependent scope checks, and all 27 contract scripts pass. New backends remain unavailable-engine stubs by existing product contract. |
| Reviewer NB-2 runtime badges and chunk values | Covered by `nativeTranscriptionBackendsExposeStableRuntimeBadges` and `nativeTranscriptionCatalogUsesAdr018ChunkAndDownloadCapabilities`. |
| FI/alexwengg install-source guard in catalog | Covered by `nativeTranscriptionCatalogKeepsNoGoCanarySourcesOutOfGoEntries` for all three GO entries; the sanctioned existing Parakeet FluidInference descriptor is excluded from this GO-only guard. |
| Existing WhisperKit/FluidAudio regression | `nativeTranscriptionCatalogPreservesExistingWhisperKitAndFluidAudioDescriptors` snapshots the seven pre-S7 descriptors, including repository IDs, globs, badges, descriptions, ratings, and backend metadata. |

### 3. New tests added

Added to `Tests/NativeBolabolCoreTests/TranscriptionModelCatalogTests.swift`:

- `nativeTranscriptionBackendsExposeStableRuntimeBadges`
- `nativeTranscriptionCatalogUsesAdr018ChunkAndDownloadCapabilities`
- `nativeTranscriptionCatalogKeepsNoGoCanarySourcesOutOfGoEntries`
- `nativeTranscriptionCatalogPreservesExistingWhisperKitAndFluidAudioDescriptors`

### 4. Scope and verdict

- Tester changed only the test file, this report, and the Tester section in `FEEDBACK.md`.
- No `Sources/**`, `Package.swift`, `STATE.yaml`, or product code was changed.
- `BUG_REPORT.md` remains unchanged with `bugs_open: 0`; no product defect was found.
- Security coverage was limited to the existing lightweight secret checks in the gate, as required for Tester.

**RESULT: `qa_green`**

---

## S8 re-run

**Date:** 2026-08-04
**Tester:** Test Engineer (post-fix feature gate; full vulnerability hunt out of scope)
**Scope:** S8 Download + presence + storage paths + progress UI, fix round 1
**Status:** **qa_green**

### Gate results

Graphify was queried first against `graphify-out/graph.json` for the S8 download, presence, package-size, storage, and regression-contract relationships. The query resolved the S8 tests, `TranscriptionModelStore`, `TranscriptionModelDescriptor`, and the QA guard.

| Command | Result |
|---|---|
| `swift test` | **PASS** - 513 tests in 4 suites |
| `./script/qa/run_all.sh` | **PASS** - 28 passed / 0 failed |
| `check_s8_download_contract.sh` via `run_all.sh` | **PASS** |

### Bug closure

- **BUG-001 CLOSED:** `canary-1b-v2-coreml` advertises `approxDownloadBytes == 1_884_267_035` and `~1.88 GB`; the `>1_000_000_000` Settings warning condition therefore triggers. `s8CanaryOneBAdvertisesPackageSizeAboveDiskWarningThreshold` is green.
- **BUG-002 CLOSED:** `isCompleteGOModelFolder` uses `requiredItems.isSubset(of: visible)` with the complete layouts for 1B, Flash, and GigaAM. Missing any bundle or vocabulary/metadata item, including an empty folder, is rejected; the 1B layout does not require `canary_preprocessor.mlmodelc`. `s8PresenceFixturesRejectEmptyFoldersAndIncompleteModelAssets` and the executable-target S8 contract are green.

### Regression and gap-hunt

- Install-source mapping, `SharedModelsRoot` storage paths, resume/SHA-256 hooks, and Settings progress states remain green.
- Existing WhisperKit/FluidAudio catalog coverage, engine routing, and HUD-A markers remain green.
- The gap-hunt strengthened `check_s8_download_contract.sh` with an explicit subset-semantics assertion covering missing-any-required-asset rejection across all three GO layouts. No new product bug was found.
- Security verification remained limited to the lightweight checks already included in the gate.

### Verdict

**RESULT: `qa_green`** - BUG-001 and BUG-002 are closed; current `BUG_REPORT.md` has `bugs_open: 0`.
