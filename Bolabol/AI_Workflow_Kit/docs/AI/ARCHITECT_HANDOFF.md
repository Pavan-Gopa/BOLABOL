# Architect Handoff - Bolabol 1.0.4 Code Hygiene

> Design-only packet. The Architect did not edit product Sources, Tests,
> product/runtime scripts, package dependencies, UserData, model assets, or git
> history.

## Meta

| Field | Value |
|---|---|
| Campaign | `CODE-HYGIENE-RELEASE` |
| Actor | Architect (design-only) |
| Date | 2026-08-09 |
| Baseline | `bolabol/pre-CODE-HYGIENE-RELEASE` at `1a8bf3d` |
| Product | Bolabol 1.0.4, macOS, Apple Silicon |
| Graphify | Required queries ran first against `graphify-out/graph.json`; no rebuild was requested |
| Security | SEC-001...004 remain closed; SEC-005 was not reopened and is unrelated to this packet |
| RESULT | `design_complete` |

This packet is Architect-approved design, but Coder remains blocked until the
Human/Orchestrator accepts the exact HYG list and places the accepted files in
the live scope.

## Decision

The release-hygiene pass must be subtractive and mechanically verifiable. It may
remove code only when the repository has no runtime caller and Graphify has no
external inbound reference, move only an already-isolated internal type without
changing its declaration or lifecycle, correct comments/copy/metadata, and
remove compiler-neutral noise. It may not reinterpret product behavior.

No broad cleanup is authorized. Persisted names, Codable values, UserDefaults
keys, Application Support paths, Keychain services, public library APIs, ASR
runtime code, HUD geometry, and concurrency/timing seams require their own
decision and tests even when their current names look untidy.

## Evidence Summary

The two required Graphify traversals established the broad surface before
source reads:

| Evidence | Result |
|---|---|
| `dead code unused symbols SmartScribe rename residue legacy migration UI polish structure hygiene` | 152-node traversal. Former-brand hits resolved to rename/history/UserData evidence rather than current product Swift; it also exposed current migration and settings seams that must not be deleted. |
| `ContentView HotkeySessionOverlayManager TranscriptionLanguageRouting SharedModelsRoot large god files` | 614-node traversal. `ContentView` is a degree-100 orchestration node; `HotkeySessionOverlayManager` is connected to live ContentView/HUD state; `SharedModelsRoot` is a live trust boundary. |
| `graphify explain AppleSpeechTranscriptionEngine` | Only containment, protocol inheritance, and its own methods; no factory, view, workflow, test, or QA caller. |
| `graphify explain StatisticsSettingsView` | Only containment and its own dependencies/methods; no `SettingsView` edge. |
| `graphify explain BolabolFullLogoView` | Only containment and its own body/loader; repository references outside the file merely require its existence. |
| `graphify explain ContentView` | Degree 100 and 99 reported connections, confirming that a broad split is not a hygiene patch. |
| `graphify explain HotkeySessionOverlayManager` | Live ContentView caller plus panel/state/layout relationships, confirming that executable HUD cleanup is outside this pass. |

Direct repository references narrow the evidence:

- Current `Sources/**/*.swift`, `Tests/**/*.swift`, and `script/**/*.sh` have no
  `SmartScribe`, `NativeSmartScribe`, `Scribex`, `Blaboom`,
  `com.smartscribe`, or `com.blaboom` text residue.
- Three current source comments still say `VaniScript`; they are attribution
  residue, not behavior.
- `ContentView.settingsWindow`, `lastSettingsToggleTime`,
  `updateRawText(noteID:text:)`, `toggleSettingsWindow`,
  `triggerSettingsMenuItem`, and `findOfficialSettingsWindow` have no caller in
  `ContentView`. The live settings-window implementation is in
  `NativeBolabolApp.swift`.
- `TranscriptionModelStore.downloadedModel(for:)` has only its declaration. Its
  comment also contradicts ADR-022 by saying Translation can select Canary.
- `StatisticsSettingsView` is absent from the eight real tabs in
  `SettingsView`; statistics are rendered by `UsageInlineCard` in
  `APIProvidersSettingsView`.
- `BolabolFullLogoView` has no product caller. The onboarding test explicitly
  requires the standalone `BolabolLogoView`; the full SVG asset remains useful
  release artwork and is not dead.
- Eleven tracked `.pyc` files and three tracked `scratch/test_*` ad hoc fixtures
  are repository hygiene, not release runtime inputs. Scratch is keep-local by
  default and is not a Coder deletion target.
- Measured large files are `AppText.swift` 9,990 lines, `ContentView.swift`
  2,184, `HotkeySessionOverlayManager.swift` 2,164,
  `CanaryCoreMLEngine.swift` 1,426, `NoteDetailView.swift` 1,317,
  `APIProvidersSettingsView.swift` 1,255, `PolishingEngineStore.swift` 1,137,
  `OnboardingView.swift` 1,023, `TranscriptionLanguageRouting.swift` 955, and
  `TranscriptionModelStore.swift` 906. Size alone is not proof that a split is
  safe.

## Classified Inventory

`Behavior change?` means product logic, persistence, timing, routing, geometry,
or engine output. Copy and release metadata corrections are marked `NO`.

| ID | Area | Action | Risk | Behavior change? | Files / evidence | Verify |
|---|---|---|---|---|---|---|
| HYG-001 | Former-brand visual residue | Recapture current product screenshots; do not edit pixels or ship old captures | medium | NO | `docs/screenshots/01_main_window.png`, `02_app_overview.png`, `07_hotkeys.png`, `09_translation.png`, `11_raw_tab.png`, `12_variant1.png`, `14_help.png`, `17_quick_translation.png`; duplicate old captures under `Screenshots for GITHUB/` visibly contain SmartScribe | Human visual review; release-media checklist |
| HYG-002 | Foreign-project comments | Replace three VaniScript attributions with product-neutral invariant descriptions | low | NO | `APIProvidersSettingsView.swift:4`; `GeminiCloudDictationEngine.swift:346,422` | Negative source scan; `swift test` |
| HYG-003 | Dead private ContentView code | Delete the unused state, raw-text wrapper, and duplicate settings-window cluster | low | NO | `ContentView.swift:124-125,318-320,536-596`; live implementation is `NativeBolabolApp.swift:366-472` | Exact symbol absence; `swift test`; app settings hotkey smoke |
| HYG-004 | Incremental ContentView structure | Move `PopoverDelegate` and `LanguagePickerPopoverController` unchanged to one role-headed module | low | NO | `ContentView.swift:8-90`; existing `HUDLanguagePickerPopoverTests` instantiate the controller | Focused popover tests; `swift test`; no visibility change |
| HYG-005 | Dead ADR-022-stale helper | Delete `downloadedModel(for:)` and its wrong Translation/Canary comment | low | NO | `TranscriptionModelStore.swift:390-404`; declaration-only reference | Exact symbol absence; `swift test` |
| HYG-006 | Dead Apple Speech/legacy Help fallback | Delete unreachable engine, its dead AppText surface, and stale generated-plist Speech permission declarations | low | NO | `AppleSpeechTranscriptionEngine.swift`; declaration/map-only keys `helpWelcomeBody`, `helpOfflineModelStep`, `helpOfflineActivateStep`, `helpPrivacyLocalStep`, `appleSpeech`, `speechPermissionDisabled`, `appleSpeechUnavailableForLocale`, `appleSpeechOnDeviceUnavailableForLocale`, `appleSpeechReturnedEmptyTranscript`; `build_and_run.sh:175-176`; `build_release_dmg.sh:177-178`; product contract rejects fallback in `TranscriptionBackend.swift:8-9` | Negative `SFSpeech`/`import Speech`/key scan; localization tests; inspect built plist; full gate |
| HYG-007 | Dead Settings view | Delete unreachable Statistics view, remove `.settingsStatistics`, and correct guards/tests that currently pin a nonexistent tab | low | NO | `StatisticsSettingsView.swift`; `AppText.swift`; `FinalMaxCoverageMatrixTests.swift:953`; `check_settings_surface.sh:17,29-35`; real stats UI is `APIProvidersSettingsView.swift:1008-1169` | Settings guard; localization tests; `swift test`; manual API Providers stats card smoke |
| HYG-008 | Dead logo wrapper | Delete unused `BolabolFullLogoView`, remove file-existence assertions, retain `BOLABOL_LOGO_Full.svg` | low | NO | `BolabolFullLogoView.swift`; `ReleaseIdentityTests.swift:79-89`; `check_workspace_ui_surface.sh:36-42`; onboarding already rejects this wrapper at test line 126 | Release identity tests; workspace UI guard; built resource inspection |
| HYG-009 | Obsolete destructive restructure tooling | Delete inert `restructure.sh`; turn `RESTRUCTURE_README.md` into a historical completed/do-not-run note; preserve `RENAME_REPORT.md` | low | NO | Script expects absent `NativeAppleSilicon` and contains destructive removals; repository is already flat | File absence; docs link check; `swift test` |
| HYG-010 | Local/generated junk | Add ignore coverage for `__pycache__/` and `*.pyc`; Orchestrator may untrack caches. Keep `scratch/test_*` local unless Human explicitly approves removal | low | NO | 11 tracked root `.pyc`; `scratch/test_didset.swift`, `test_persistence.swift`, `test_input_v1.json` have zero refs | `git ls-files`; no product/source/package change |
| HYG-011 | Comment hygiene | Correct wrong/duplicated comments; replace incident IDs with durable why-comments; add narrowly scoped security/ADR invariants | low | NO | `ContentView.swift:904-907,1543-1555`; `TranscriptionLanguageRouting.swift:573-579,885-907`; `TranscriptionModelStore.swift:19-27`; `SharedModelsRoot.swift:216-225`; `HUDQuickSwitcherLayout.swift:399-401`; GigaAM/Canary `BLOCK-*` test-seam comments only | Diff review proves comment-only; no executable line changes; full gate |
| HYG-012 | Imports/access-control warnings | Remove seven redundant `public` modifiers in a `public extension`; remove only the enumerated unused imports | low | NO | `HUDQuickSwitcherLayout.swift:301,304,311,316,331,379,401`; import list in Approved Scope below | Compiler is proof: `swift test`, Release build; restore any import if compilation requires it |
| HYG-013 | Notification name duplication | Move the one notification name to Core and use the typed name in both publisher/subscriber | low | NO | `GeneralSettingsStore.swift:7-9,25,32`; `NoteStore.swift:347-359` repeats the raw string because Core cannot import the app target | Focused retention tests; exact raw string defined once; `swift test` |
| HYG-014 | Logging identity residue | Align unified-log subsystem with canonical bundle id `com.bolabol.app`; update its exact test | low | NO (diagnostics only) | `NativeBolabolLog.swift:5`; `DomainModelsExhaustiveTests.swift:404`; build telemetry already queries `com.bolabol.app` | Focused test; `--telemetry` smoke; log export smoke |
| HYG-015 | Active 1.0.4 release identity/docs | Update active version defaults and current release-facing docs only; correct current engine/hotkey/provider/privacy/permissions statements | low | NO | `Info.plist:14`; build script defaults; `README.md`; `docs/RELEASE.md`; `docs/RELEASE_NOTES.md` | Static 1.0.3 scan limited to active files; built plist inspection; Release verify; links |
| HYG-016 | Help/Onboarding copy | Separate tiny string-only batch across all 15 locale maps; make model, privacy, GigaAM, Canary, HUD, and translation wording match current source/ADR-022; remove visible plan citations | low | NO | Exact AppText keys in Approved Copy Scope below; no view/layout change | `SettingsLocalizationTests`; all locale maps complete; manual Help/Onboarding review |
| HYG-017 | Persistent/internal `NativeBolabol` names | Future migration campaign; do not blind-rename paths, Keychain fallback, defaults keys, Codable values, or module names | high | YES if mishandled | `GeneralSettingsStore.swift`, `NoteStore.swift`, `GlossaryStore.swift`, `AudioRecorder.swift`, model stores, credential store, README local paths | Migration fixtures, old-install smoke, no data loss; explicit Human decision |
| HYG-018 | God files | Defer all broad splits; after HYG-004, extract one independent presenter/component per campaign | medium/high | Intended NO, regression risk high | Large-file measurements above; `ContentView` degree 100; HUD manager is live geometry/state bridge | Dedicated focused tests and manual UI checks per extraction |
| HYG-019 | Dead-looking public API/package surface | Future API decision, not batch deletion | medium | API change | `LocalModelDescriptor`; test-only `PolishingEngineRegistry`; `TranscriptionModelSettings.resolvedModel`; legacy public `RecordingTranscriptionWorkflow` overloads; redundant-looking package dependencies | Decide whether `NativeBolabolCore` is external API; consumer/build matrix |
| HYG-020 | Engine/HUD/warning cleanup | Defer async/await rewrites, deprecated AVAsset migration, HUD bookkeeping/hit regions, dependency warnings, and Package.swift changes | medium/high | Possibly YES | Canary private async chain; `AudioPlaybackModalView` duration; `HotkeySessionOverlayManager.languageTapHandler`, `targetTapHandler`, `layoutGeneration`, ignored `animated`, and `CGPoint.init(origin:)`; SwiftPM identity/resource warnings | Separate campaign with runtime, timing, geometry, and release tests |
| HYG-021 | Stale local release artifacts | Never ship old Blaboom/NativeBlaboom bundles; clean generated staging before Release verify, without treating `dist/**` as source | low | NO | Local `dist/Blaboom*`, `dist/NativeBlaboom*`, and stale handoff assets; not tracked in current source inventory | Clean Release build; exact bundle/plist/handoff inventory; codesign verification |
| HYG-022 | Workflow docs contradict 1.0.4 | Orchestrator-owned doc follow-up, not Coder batch | low | NO | `TEAM_CONTRACT.md`, `PROJECT_CONTEXT.md`, `DECISIONS.md:4`, kick/orchestrator docs, `BOLABOL_ASR_COREML_INTEGRATION_PLAN.md`, and `ASR_COREML_STEPS.md` retain 1.0.3/proposal-era authority or criteria; `ARCHITECT_REPORT_ADR021_CLEANUP.md` needs a pre-acceptance/historical banner | Orchestrator review; source-of-truth links resolve; historical ADR bodies remain unchanged |
| HYG-023 | Graphify artifacts/tooling scope | Separate Graphify hygiene campaign; do not delete graph, caches, UserData, or spike evidence here | medium | NO product change | Generated graph/cache tracks local/private scopes; existing tooling evaluation already recommends separation | Orchestrator-owned rebuild/manifest policy |

## Future Incremental Structure Plan - Not Approved Now

1. Complete only HYG-004 in this campaign. It removes 83 lifecycle-focused
   lines from `ContentView` without creating a new state owner.
2. In a later structure-only campaign, extract the static quick-switch menu
   presenter at `ContentView.swift:1346-1444`. Keep hotkey session state,
   provider selection, callbacks, and timing in `ContentView` for that step.
3. Do not create a hotkey session controller until frozen-session tests cover
   engine identity, focused AX element, source PID, humor snapshot, target,
   picker lifetime, cancellation, and finish ordering. That extraction is high
   risk and must stand alone.
4. For `HotkeySessionOverlayManager`, first add capsule/tech hit-grid and drag
   arbitration tests. Only then consider extracting the drawing-only spectrum
   views at lines 1706-2146. Panel state, anchoring, hit regions, and animation
   stay together until those tests exist.
5. Split `TranscriptionLanguageRouting.swift` only in this order: HUD menu policy,
   legacy Whisper router, then resolver/DTOs. Before the first move, replace
   source-string tests that pin unrelated symbols to this file and resolve the
   `fileprivate` plan initializer with the narrowest non-public access.
6. `NoteDetailView` may later release its result panel, prompt-slot selector,
   variant control, and spectrum meter along existing component boundaries.
   `APIProvidersSettingsView` may later release provider detail, model picker,
   and usage card along existing MARK boundaries. Each file gets its own
   structure-only diff and focused UI tests.
7. `AppText` locale maps may move one locale per file while preserving the
   current `AppText` API and completeness tests. Do not combine that mechanical
   move with copy rewrites.
8. Do not split `CanaryCoreMLEngine`, `PolishingEngineStore`, or downloader/path
   code under a hygiene label. Those require runtime/security-specific gates.

## Approved For Coder - Batch 1

Only these low-risk items are approved for the first implementation batch:

`HYG-002`, `HYG-003`, `HYG-004`, `HYG-005`, `HYG-006`, `HYG-007`,
`HYG-008`, `HYG-009`, `HYG-011`, `HYG-012`, `HYG-013`, `HYG-014`, and
`HYG-015`.

`HYG-016` is approved only as a separate tiny string/localization batch after
Batch 1 is reviewed or as a separately accepted Coder attempt. Do not mix it
with structural deletes because localization review needs an isolated diff.

`HYG-010`, `HYG-021`, and `HYG-022` are Orchestrator/release-workflow actions,
not Coder product scope. `HYG-001` requires fresh Human-approved captures.
`HYG-017` through `HYG-020` and `HYG-023` are not approved for this campaign.

## Exact Ordered Coder Scope - Batch 1

The order is mandatory so moves and guard corrections remain reviewable.

| Order | HYG | Files | Exact action | Explicitly out of scope |
|---:|---|---|---|---|
| 1 | HYG-004 | `Sources/NativeBolabol/Views/LanguagePickerPopoverController.swift` (new), `Sources/NativeBolabol/Views/ContentView.swift` | Move lines 8-90 unchanged into the new role-headed module; keep actor isolation and internal visibility exactly; update no API | Popover behavior, animation, identity, callbacks, tests, or picker UI |
| 2 | HYG-003/HYG-011 | `Sources/NativeBolabol/Views/ContentView.swift` | Delete only the proven dead state/method cluster; correct the two identified translation/target-language comment blocks | Hotkey/session orchestration, translation logic, settings-window implementation in `NativeBolabolApp`, state timing |
| 3 | HYG-005/HYG-011 | `Sources/NativeBolabol/Stores/TranscriptionModelStore.swift` | Delete `downloadedModel(for:)`; add/replace only the documented remote-path why-comment | Download behavior, path policy predicate, destinations, model state, ADR-022 routing |
| 4 | HYG-006 | `Sources/NativeBolabol/Services/AppleSpeechTranscriptionEngine.swift` (delete), `Sources/NativeBolabolCore/Services/AppText.swift`, `script/build_and_run.sh`, `script/build_release_dmg.sh` | Remove unreachable Apple Speech implementation; remove the nine exact declaration/map-only keys listed in HYG-006 and all 15 map entries; remove only `NSSpeechRecognitionUsageDescription` generated-plist entries | Microphone/Accessibility/Apple Events behavior or entitlements; any live ASR engine |
| 5 | HYG-007 | `Sources/NativeBolabol/Views/Settings/StatisticsSettingsView.swift` (delete), `Sources/NativeBolabolCore/Services/AppText.swift`, `Tests/NativeBolabolCoreTests/FinalMaxCoverageMatrixTests.swift`, `script/qa/check_settings_surface.sh` | Remove dead view/key; make guard assert the eight real Settings tabs and retain the real usage-statistics model/card contract | `UsageInlineCard`, statistics persistence/reset/cost behavior, Settings redesign |
| 6 | HYG-008 | `Sources/NativeBolabol/Views/Components/BolabolFullLogoView.swift` (delete), `Tests/NativeBolabolCoreTests/ReleaseIdentityTests.swift`, `script/qa/check_workspace_ui_surface.sh` | Remove wrapper-only existence assertions; retain and continue packaging `BOLABOL_LOGO_Full.svg` | Current standalone/wordmark/status-bar logo components or branding assets |
| 7 | HYG-009 | `restructure.sh` (delete), `RESTRUCTURE_README.md` | Replace runnable instructions with a short historical completed/do-not-run note; point to `RENAME_REPORT.md` | Rewriting or deleting rename history; moving any repository directory |
| 8 | HYG-002 | `Sources/NativeBolabol/Views/Settings/APIProvidersSettingsView.swift`, `Sources/NativeBolabol/Services/GeminiCloudDictationEngine.swift` | Replace three VaniScript attributions with product-neutral role/invariant comments | Provider request ordering, payload shape, sampling, UI layout |
| 9 | HYG-011 | `Sources/NativeBolabolCore/Services/TranscriptionLanguageRouting.swift`, `Sources/NativeBolabolCore/Services/SharedModelsRoot.swift`, `Sources/NativeBolabolCore/Services/HUDQuickSwitcherLayout.swift`, `Sources/NativeBolabol/Engines/CanaryCoreMLEngine.swift`, `Sources/NativeBolabol/Engines/GigaAMCoreMLEngine.swift` | Comment-only: replace review/step IDs with durable invariants; add the specified ADR-022/path/root/defense why-comments; remove the rejected-width history | Any executable token, routing case, path validation, engine math/decode/chunking, HUD geometry/hit testing |
| 10 | HYG-012 | `Sources/NativeBolabolCore/Services/HUDQuickSwitcherLayout.swift` | Remove only seven redundant `public` modifiers inside the existing public extension | Signatures, values, layout math, visibility, hit regions |
| 11 | HYG-012 | Import-only files listed below | Remove only the named import at line 1/3; if the compiler needs one, retain it and report the exception rather than adding a workaround | Any declaration or formatting rewrite |
| 12 | HYG-013 | `Sources/NativeBolabolCore/Support/NotificationNames.swift` (new), `Sources/NativeBolabol/Stores/GeneralSettingsStore.swift`, `Sources/NativeBolabolCore/Stores/NoteStore.swift` | Move the exact notification-name constant to Core; use `.didChangeAudioRetentionSettings` at both ends; preserve raw value | Notification delivery, scheduling, settings persistence, retention policy |
| 13 | HYG-014 | `Sources/NativeBolabolCore/Support/NativeBolabolLog.swift`, `Tests/NativeBolabolCoreTests/DomainModelsExhaustiveTests.swift` | Change only subsystem identity to `com.bolabol.app` and its assertion | Categories, message content, PII policy, log retention/export implementation |
| 14 | HYG-015 | `Sources/NativeBolabol/Resources/Info.plist`, `script/build_and_run.sh`, `script/build_release_dmg.sh`, `README.md`, `docs/RELEASE.md`, `docs/RELEASE_NOTES.md` | Set active 1.0.4 version defaults; update only current release sections/links/commands; make engine, hotkey, provider, permissions, privacy, and repository-root claims match current source and ADR-022; retain historical 1.0.3 evidence separately | Build number allocation, release publication, git/GitHub operations, historical ADR/plan/report rewrites, new product claims |
| 15 | all approved | Approved tests/guards only | Add no speculative tests; update only tests/guards directly invalidated by a deletion or identity correction | New QA framework, broad guard rewrites, Package.swift |

### Exact Import-Only List

- Remove `Combine` only from
  `Sources/NativeBolabol/Views/AudioPlaybackModalView.swift`.
- Remove `Foundation` only from:
  `AccessibilityPermissionPromptState.swift`, `GlossaryEntry.swift`,
  `LocalModelDescriptor.swift`, `PolishingStatus.swift`,
  `ProcessingVariant.swift`, `TranscriptionBackend.swift`,
  `TranscriptionLanguageMode.swift`, `TranscriptionStatus.swift`, and
  `UsageStatisticsSettings.swift` under `Sources/NativeBolabolCore/Models/`.
- Remove `Foundation` only from:
  `HUDProviderListComposer.swift`, `LocalMLXModelCompatibility.swift`,
  `PolishingEngineRegistry.swift`, `PolishingModelOptionsProvider.swift`, and
  `PolishingModelPromptControl.swift` under
  `Sources/NativeBolabolCore/Services/`.

The compiler is the acceptance proof. This list is not permission to remove
`Foundation`, `Combine`, `UniformTypeIdentifiers`, or any other import from an
unlisted file.

## Exact Approved Copy Scope - Separate Batch 2

Only `Sources/NativeBolabolCore/Services/AppText.swift`, directly corresponding
localization tests in
`Tests/NativeBolabolCoreTests/SettingsLocalizationTests.swift`, and a Coder
FEEDBACK update are allowed in this batch.

Update all 15 concrete locale maps for these exact keys, preserving placeholders
and supplying real locale text rather than English fallback:

- `helpHeroSubtitle`, `helpStart2`, `helpModelsIntro`, `helpModelsCatalog`,
  `helpModelsUse`, `helpPrivacyLocal`, `helpPrivacyCloud`, `helpTipDisk`, and
  `helpCloudProviders`.
- `onboardingLocalTitle` and `onboardingSetupLocalBody`.
- `transcriptionLanguageHint`.
- `helpBilingualPrimary`, `helpBilingualAdditional`,
  `helpBilingualOnboarding`, `helpBilingualCanary`, and `helpBilingualHUD` as
  one coherent model-aware HUD section. Remove all visible `plan §...` text.
- `localModelsCanaryLanguageBlock` and `localModelsGigaAMRussianTip` so copy
  describes the current resolver without claiming that GigaAM requires a saved
  Russian preference.

Do not change `localModelsCanary1BSubtitle`: the current 25-language explicit
ASR catalog is source- and test-backed. Do not change any view, key name,
placeholder count, routing behavior, model capability, or layout. Raw picker
literals in `HUDLanguagePickerPopoverView.swift` are not in this tiny batch.

## Product-Facing Docs Contract

Active docs may be corrected; historical evidence may only receive an archival
banner or be linked, not rewritten.

Current 1.0.4 docs must state:

- Local ASR includes WhisperKit, Parakeet/FluidAudio, Canary Core ML, and GigaAM
  Core ML. Canary 1B requires macOS 15+.
- Canary and GigaAM are ASR-only under ADR-022. No Canary speech-translation
  control or generic target request exists.
- Whisper alone retains its native X-to-English path where supported. Other
  translation is post-ASR text through existing local MLX or cloud providers.
- Current default hotkeys are the values pinned by `HotkeySettingsTests`:
  Option+S dictation, Option+1 full translation, Option+2 quick translation,
  and Option+~ settings.
- Cloud Google transcription sends audio to Google; cloud polishing/translation
  sends text/prompts to the selected provider. Local model paths stay local.
- Anthropic is migration-compatible but not in the visible provider order.
- Do not claim 1.0.4 is published/notarized until Release verification and Human
  release action actually occur.

Preserve `BOLABOL_1.0.3_IMPLEMENTATION_PLAN.md`, ADR bodies, spike reports,
historical FEEDBACK/REPORT/BUG_REPORT evidence, `RENAME_REPORT.md`, UserData, and
Graphify memory as history.

## Comment Policy For Coder

1. English only.
2. Add a 1-5 line role header to every new or moved module. State layer,
   ownership, and a must-not invariant when one exists.
3. Write why-comments only for non-obvious invariants: security path policy,
   ADR-022 ASR-only routing, persisted migration compatibility, and HUD hit
   geometry/drag arbitration.
4. Do not narrate obvious assignments, getters, branches, or framework calls.
5. Replace incident IDs (`BLOCK-*`, attempt numbers, rejected dimensions) with
   durable invariant language. Historical evidence belongs in FEEDBACK/ADRs.
6. No SmartScribe/VaniScript residue, stale plan-section citations in visible
   copy, TODO spam, or comments that promise future behavior.
7. Preserve useful engine/path/migration why-comments. Comment cleanup is not
   permission to change adjacent code.

## Forbidden For Coder

- ASR engine decode, Core ML frontend/state/token work, chunking, VAD, model
  math, model loading, or smoke criteria changes. Comment-only edits listed in
  HYG-011 are the sole engine-file exception.
- ADR-022, session operation, language routing, source selection, translation,
  or fallback behavior changes.
- HUD geometry, hit testing, drag arbitration, panel anchoring, animation, or
  accessibility behavior changes. The HYG-011 comment and HYG-012 redundant
  modifier edits are the only HUD-layout exceptions.
- Persistence key, Codable case/raw value, Application Support path, Keychain
  service, bundle identifier, or legacy decode-path renames without an accepted
  migration design.
- Dependency upgrades, resolver changes, `Package.swift` edits, or lockfile
  churn.
- Deleting or moving `UserData/**`, `AI_LOCAL_MODELS`, installed models, model
  assets, accepted spike evidence, or local recovery data.
- Mass file moves or target reshaping. HYG-004 is the only approved extraction.
- Visual redesign, new UI features, new controls, layout changes, or raw picker
  localization. Listed copy corrections are allowed only in their own batch.
- Clever rewrites that alter timing, task/actor boundaries, cancellation,
  continuation, ordering, or notification scheduling.
- Reopening SEC-001...004 or implementing SEC-005 policy in this campaign.
- Git commit, amend, tag, push, release publication, or forceful git cleanup.

## Verification Matrix For Later Coder

| Gate | Required result |
|---|---|
| Scope | Only accepted HYG IDs and exact files are changed; no unrelated cleanup |
| Dead symbols | Approved deleted symbols/files have zero references; no forbidden brand in current product text |
| Focused | Popover lifecycle, release identity, Settings localization/surface, retention, and domain identity tests green where touched |
| Full tests | `swift test` green |
| QA | `./script/qa/run_all.sh` green |
| Warnings | No new warning; redundant-public warning removed; no warning hidden or suppressed |
| Release | Clean `./script/build_and_run.sh --verify`; built plist is 1.0.4 / `com.bolabol.app`; codesign verification green |
| Output | Active `dist/release` and `dist/handoff` contain only current Bolabol identities; no Blaboom/SmartScribe artifact ships |
| Diff | `git diff --check` green; product diff contains no executable engine/HUD/routing/persistence change outside exact scope |
| Handoff | Coder appends FEEDBACK with each applied/skipped HYG ID, before/after evidence, exact commands/results, and `RESULT: waiting_review` |

Architect did not run tests or release builds because this turn is design-only.

## Done Definition For Later Coder

1. Only Human/Orchestrator-accepted HYG IDs are applied.
2. `swift test` is green.
3. `./script/qa/run_all.sh` is green.
4. No new warning hides a real issue; no warning is silenced by flags or broad
   suppression.
5. A clean Release verify is green and the resulting bundle has current Bolabol
   1.0.4 identity.
6. FEEDBACK is `waiting_review` with exact before/after notes and skipped-item
   explanations.
7. No commit, tag, push, publication, UserData/model deletion, or product
   behavior change occurred.

## Handoff Status

**RESULT: `design_complete`**

Готово. Вернись к оркестратору и скажи статус.
