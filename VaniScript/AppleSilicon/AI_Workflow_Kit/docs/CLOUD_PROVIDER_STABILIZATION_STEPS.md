# CLOUD_PROVIDER_STABILIZATION — Mitigation Steps

> Atomic implementation plan for `OBS-001…OBS-005`.
>
> **Scope:** native Apple Silicon only.
>
> **Architecture:** `CLOUD_PROVIDER_STABILIZATION_ARCHITECTURE.md`
>
> **State:** plan only; no implementation has started.

## Global execution rules

1. Execute strictly in order unless a step explicitly allows parallel work.
2. CPS-01 is a hard evidence gate. Do not change role-selection product behavior
   while `OBS-002` root cause remains `UNKNOWN`.
3. Every coding step must finish with `swift build` and `swift test`.
4. No real API key may enter source, tests, logs, screenshots or git.
5. Network tests use injected fetchers and fixtures. Real-key checks are manual,
   opt-in black-box acceptance only.
6. Do not recreate:
   - `CloudProviderCatalog`;
   - `CloudModelCatalog`;
   - `CloudKeyValidator`;
   - `ProviderRegistry`;
   - `UsageRecorder`;
   - `CloudBalanceService`;
   - the existing Gemini/OpenAI engines;
   - MCP server/config/scopes.
7. `STATE.yaml` changes are orchestrator-only and are not part of any target list.
8. Each step gets its own pre-step checkpoint and rollback tag during execution;
   this document does not create them.

## Dependency order

```text
CPS-01 evidence gate
  └─ CPS-02 endpoint profile foundation
      ├─ CPS-03 Qwen API surfaces
      └─ CPS-04 embedded Qwen profile reuse

CPS-03
  └─ CPS-05 rich model metadata
      └─ CPS-06 unified role policy / OBS-002 fix
          ├─ CPS-07 OpenRouter transcription
          ├─ CPS-08 Anthropic translation
          └─ CPS-09 Custom translation
              └─ CPS-10 compact metadata and role UI
                  └─ CPS-11 acceptance closeout
```

---

## CPS-01 — Evidence gate: reproduce role no-op and freeze provider contracts

### Goal

Convert `OBS-002` from `UNKNOWN` to `VERIFIED`, and record the exact current
contracts for Qwen profiles, OpenRouter audio and embedded Qwen model/auth before
any behavioral change.

### Related OBS

- `OBS-001`
- `OBS-002`
- `OBS-003`

### Confirmed reason

The source currently says generic translation is enabled for a non-empty key, but
Human observes a no-op. There is no black-box test covering Settings click →
persisted settings → workflow/session → executable route. The evidence gap itself
is verified; the product defect location is not.

### Requirements

1. Build and open the fresh native app; do not use an older `.app`.
2. Reproduce with OpenRouter:
   - valid key;
   - target language not `Same`;
   - selected model `google/gemini-2.5-flash`;
   - record settings/workflow/session provider ids before and after click;
   - record whether the click is ignored, momentarily selected then reset, or
     selected but not used by runtime.
3. Repeat with Qwen Pay-as-you-go or a safe mock-backed profile to determine
   whether the defect is generic or OpenRouter-specific.
4. Inspect logs only for provider ids/status; redact secrets and Authorization.
5. Record the exact symbol and branch that reverses/ignores the selection.
6. Verify current official contracts:
   - Qwen Pay-as-you-go base URL and key kind;
   - Qwen Token Plan base URL, exact model allowlist and intended-use limits;
   - Qwen CLI environment names and selected model availability;
   - OpenRouter transcription endpoint and discovery filter.
7. Update the evidence table in the acceptance document. No product fix in CPS-01.

### target_files

```yaml
target_files:
  - AI_Workflow_Kit/docs/CLOUD_PROVIDER_STABILIZATION_ACCEPTANCE.md  # NEW, evidence section only
  - AI_Workflow_Kit/docs/DECISIONS.md                                # MODIFY with verified contract evidence
```

### Existing — do not recreate

- `SettingsView.cloudProviderToggles`
- `WorkflowStore.updateSettings`
- `WorkflowStore.refreshProviderSelections`
- `WorkflowState.synchronizeProviderSelections`
- `ProviderRegistry`

### Out of scope

- Product-code changes.
- Enabling any new provider role.
- Storing a real key in a fixture.

### Risks and dependencies

- Requires a fresh native build and a safe real-key smoke supplied outside repo.
- Token Plan rules are drift-prone; capture URLs and access date.
- Blocks CPS-02 and CPS-06.

### Unit/integration tests

- No new unit test in this diagnostic step.
- Existing `WorkflowStateTests` and provider registry suites must remain green.
- Record the missing regression seam that CPS-06 must add.

### QA black-box

- Click `Use for Translation` once.
- Observe button, header badge and usage summary.
- Close/reopen Settings.
- Restart app and inspect persisted selection.
- Start one minimal translation and confirm actual route id.

### Required screenshot state

One before/after pair with:

- selected provider and model visible;
- key masked;
- role buttons visible;
- header badge and Cloud API Usage summary visible;
- no secret or log authorization value.

### Done

- [ ] `OBS-002` root cause is `VERIFIED` with exact symbol/path.
- [ ] Qwen/OpenRouter contracts and access date recorded.
- [ ] No product file changed.
- [ ] Existing build/test baseline recorded.

### Rollback/checkpoint

- Pre-step checkpoint: `cloud-provider-stabilization/pre-CPS-01`
- Rollback: revert only diagnostic documentation.
- Next: CPS-02. CPS-06 remains blocked until the OBS-002 result is explicit.

---

## CPS-02 — Qwen endpoint profile foundation

### Goal

Make credential kind/region/billing profile a first-class Core value without
changing runtime behavior yet.

### Related OBS

- `OBS-001`

### Confirmed reason

Qwen models and chat endpoints are duplicated literals tied to the general
DashScope endpoint. Token Plan uses a different base URL and key contract.

### Requirements

1. Add `CloudEndpointProfile`, `CloudCredentialKind` and a resolver in Core.
2. Define only verified profiles:
   - `qwen-payg-international`;
   - `qwen-token-plan-singapore`.
3. Add migration-safe `AppSettings.qwenEndpointProfileID`.
4. Legacy settings decode to `qwen-payg-international`.
5. Keep provider id `qwen` unchanged.
6. Profile resolution returns typed models/text endpoint components; callers must
   not append incompatible paths ad hoc.
7. Automatic UI detection may suggest a profile, but the resolved profile must be
   explicit and persisted before network use.
8. Never store or log a key inside the profile object.

### target_files

```yaml
target_files:
  - Sources/VaniScriptCore/CloudEndpointProfile.swift                 # NEW
  - Sources/VaniScriptCore/CloudProviderCatalog.swift                 # MODIFY
  - Sources/VaniScriptCore/AppSettings.swift                          # MODIFY
  - Tests/VaniScriptCoreTests/CloudEndpointProfileTests.swift         # NEW
  - Tests/VaniScriptCoreTests/AppSettingsCloudFieldsTests.swift       # MODIFY
```

### Existing — do not recreate

- Provider catalog order and ids.
- Existing Qwen key/model/budget fields.
- `CloudHTTPFetcher`.

### Out of scope

- Network requests.
- Settings UI.
- Embedded Qwen environment.
- Model metadata enrichment.

### Risks and dependencies

- Depends on CPS-01 contract table.
- Wrong migration default could break existing Qwen PAYG users.

### Unit/integration tests

- Legacy decode → PAYG profile.
- Round-trip of both profile ids.
- Correct verified base URLs by profile.
- Unknown profile id fails closed or normalizes to documented legacy default.
- Profile values never contain API key material.

### QA black-box

- None beyond confirming an existing settings file still opens.

### Required screenshot state

- Not required; data-model-only step.

### Done

- [ ] One Core resolver owns Qwen profile definitions.
- [ ] Existing settings migrate without key/model loss.
- [ ] No runtime endpoint changed.
- [ ] `swift build` and `swift test` green.

### Rollback/checkpoint

- Pre-step checkpoint: `cloud-provider-stabilization/pre-CPS-02`
- Rollback tag: `cloud-provider-stabilization/CPS-02`
- Next: CPS-03; CPS-04 may start only after CPS-02 approval.

---

## CPS-03 — Wire Qwen profile through validation, models and translation

### Goal

Use the selected Qwen profile consistently for key validation, model discovery
and translation/editing.

### Related OBS

- `OBS-001`

### Confirmed reason

`CloudModelCatalog` and `CloudChatRouter` independently use the general DashScope
URL, so a Token Plan key is tested and executed against the wrong endpoint.

### Requirements

1. `CloudModelCatalog` requests the models URL from
   `CloudEndpointProfileResolver`.
2. `CloudKeyValidator` preserves structured HTTP/provider errors:
   - incompatible profile/key;
   - unauthorized;
   - unsupported model;
   - plan/region mismatch.
3. `CloudChatRouter` builds Qwen text route from the same profile.
4. Add a compact Qwen `API Profile` control:
   - Automatic suggestion;
   - Pay-as-you-go;
   - Token Plan;
   - resolved profile visible.
5. A profile change cancels stale validation/model tasks and starts a fresh one.
6. Do not silently try a second endpoint after failure.
7. Translation uses only a model returned/allowed by the selected profile, unless
   the user explicitly uses existing manual model entry and accepts a clear
   provider rejection.
8. Token Plan text-only status must not enable transcription.

### target_files

```yaml
target_files:
  - Sources/VaniScriptCore/CloudModelCatalog.swift                   # MODIFY
  - Sources/VaniScriptCore/CloudKeyValidator.swift                   # MODIFY
  - Sources/VaniScriptCore/ProviderRegistry.swift                    # MODIFY
  - Sources/VaniScript/Views/SettingsView.swift                      # MODIFY
  - Sources/VaniScript/Services/CloudTextTranslationEngine.swift    # MODIFY
  - Tests/VaniScriptCoreTests/CloudModelCatalogTests.swift           # MODIFY
  - Tests/VaniScriptCoreTests/CloudKeyValidatorTests.swift           # MODIFY
  - Tests/VaniScriptCoreTests/CloudProviderRoutingTests.swift        # MODIFY
```

### Existing — do not recreate

- Debounced `CloudKeyModelRow`.
- `CloudHTTPFetcher` injection and memory cache.
- OpenAI-compatible translation response/usage parser.
- Qwen usage aggregation.

### Out of scope

- Embedded Qwen CLI.
- Qwen transcription.
- Pricing UI.

### Risks and dependencies

- Depends on CPS-02.
- Profile must participate in model-cache key; otherwise lists can leak across
  PAYG/Token Plan.
- Manual model entry must not be presented as verified compatibility.

### Unit/integration tests

- Request URL for each profile.
- Same key + different profile creates distinct cache entries.
- Profile change cancels/ignores stale model result.
- Structured 401/profile mismatch mapping.
- Translation route URL and headers for both profiles.
- Key redaction in error descriptions.

### QA black-box

- Select Token Plan, paste key, observe `Valid`, load allowlisted models.
- Select a returned text model and activate Translation.
- Run a short translation and confirm profile/model in non-secret diagnostics.
- Switch to PAYG with the Token Plan key and verify a clear mismatch error.

### Required screenshot state

- Qwen card with masked key, selected API Profile, `Valid`, model list and active
  Translation button.

### Done

- [ ] Validation, models and translation use one profile resolver.
- [ ] Token Plan key is no longer tested against PAYG URL.
- [ ] No endpoint fallback.
- [ ] `swift build` and `swift test` green.

### Rollback/checkpoint

- Pre-step checkpoint: `cloud-provider-stabilization/pre-CPS-03`
- Rollback tag: `cloud-provider-stabilization/CPS-03`
- Next: CPS-04, then CPS-05.

---

## CPS-04 — Reuse Qwen profile in embedded native chat

### Goal

Honor Human’s “universal” requirement by making the same Qwen credential/profile
available to embedded Qwen CLI chat, without changing MCP isolation.

### Related OBS

- `OBS-001`

### Confirmed reason

API & Usage Qwen key/profile and embedded Qwen CLI auth/model selection are
separate paths. `QwenAgentService` currently injects only the MCP access token.

### Requirements

1. Resolve embedded auth environment from the selected Qwen endpoint profile.
2. Pass Qwen provider secret only in child environment:
   - never argv;
   - never generated `.qwen/settings.json`;
   - never log output.
3. Keep `VANISCRIPT_MCP_TOKEN` separate from the Qwen provider credential.
4. Preserve ephemeral MCP workspace, server id, scopes and no-silent-fallback.
5. Filter/select the embedded Qwen model against the profile’s exact allowlist.
6. If the currently saved chat model is unavailable:
   - do not silently substitute an unrelated model;
   - show a blocking, actionable error or require explicit compatible selection.
7. Existing CLI-managed auth remains an explicit alternative profile/state; do
   not overwrite the user’s global Qwen configuration.
8. Cancellation and streaming behavior remain unchanged.

### target_files

```yaml
target_files:
  - Sources/VaniScriptCore/QwenAgentSupport.swift                    # MODIFY
  - Sources/VaniScript/Services/QwenAgentService.swift               # MODIFY
  - Sources/VaniScript/Views/ChatSidebarView.swift                    # MODIFY
  - Sources/VaniScript/Views/SettingsView.swift                       # MODIFY only for compatible model state
  - Tests/VaniScriptCoreTests/QwenAgentSupportTests.swift             # MODIFY
```

### Existing — do not recreate

- `QwenAgentService`.
- `QwenStreamingProvider`.
- `QwenAgentOutputParser`.
- Ephemeral MCP configuration.
- `QwenMcpConfig`.

### Out of scope

- MCP tools/scopes/ports.
- Codex/Grok.
- Direct API fallback from CLI chat.

### Risks and dependencies

- Depends on CPS-02 and CPS-01 model/auth contract evidence.
- Two Qwen service paths currently duplicate some process setup; do not refactor
  unrelated streaming code.

### Unit/integration tests

- Profile → child environment mapping.
- Provider secret and MCP token remain distinct.
- No secret in arguments or generated config.
- Unsupported saved model yields explicit error.
- Existing cancellation/parser tests remain green.

### QA black-box

- Select Qwen route in embedded chat.
- Send one short prompt with MCP enabled.
- Confirm selected compatible model in visible UI.
- Confirm explicit error for incompatible model/profile.
- Confirm no fallback to Gemini/API chat.

### Required screenshot state

- Embedded chat route set to Qwen, compatible model visible, successful response;
  no credential values visible.

### Done

- [ ] One Qwen profile can serve API translation and embedded Qwen CLI.
- [ ] MCP invariants unchanged.
- [ ] Unsupported model is explicit, not silently replaced.
- [ ] `swift build` and `swift test` green.

### Rollback/checkpoint

- Pre-step checkpoint: `cloud-provider-stabilization/pre-CPS-04`
- Rollback tag: `cloud-provider-stabilization/CPS-04`
- Next: CPS-05.

---

## CPS-05 — Rich cloud model metadata foundation

### Goal

Represent context, pricing, modalities and transcription route eligibility
without changing Settings layout yet.

### Related OBS

- `OBS-003`
- `OBS-004`

### Confirmed reason

`CloudModel` stores only `id`, and current decoders discard all other provider
metadata.

### Requirements

1. Introduce `CloudModelDescriptor`, `CloudModelCapabilities`,
   `CloudTranscriptionRouteKind` and `CloudModelMetadataSource`.
2. Preserve source compatibility where practical; do not duplicate model catalogs.
3. Parse OpenRouter:
   - `context_length`;
   - `top_provider.max_completion_tokens`;
   - input/output modalities;
   - prompt/completion pricing.
4. Parse Gemini limits and supported methods returned by Models API.
5. Add a versioned bundled official metadata catalog only for providers/fields
   missing from list APIs.
6. Store price in `USD / 1M tokens`; test conversion from OpenRouter per-token strings.
7. Keep every enriched field optional.
8. Attach source and `asOf`; no runtime HTML scraping.
9. Token Plan Credits and PAYG USD are different price semantics.
10. Persist only the selected non-secret `CloudModelSelectionSnapshot`; keep the
    full fetched model list in the existing session cache.
11. A manually entered model gets `manualUnknown` metadata and cannot enable
    transcription without a verified route.

### target_files

```yaml
target_files:
  - Sources/VaniScriptCore/CloudModelCatalog.swift                   # MODIFY
  - Sources/VaniScriptCore/CloudModelMetadataCatalog.swift           # NEW
  - Sources/VaniScriptCore/CloudProviderCatalog.swift                # MODIFY
  - Sources/VaniScriptCore/AppSettings.swift                         # MODIFY
  - Sources/VaniScript/Stores/WorkflowStore.swift                    # MODIFY selected snapshot plumbing
  - Sources/VaniScript/Views/SettingsView.swift                      # MODIFY model-row plumbing, no layout redesign
  - Tests/VaniScriptCoreTests/CloudModelCatalogTests.swift           # MODIFY
  - Tests/VaniScriptCoreTests/CloudModelMetadataCatalogTests.swift   # NEW
  - Tests/VaniScriptCoreTests/AppSettingsCloudFieldsTests.swift      # MODIFY
```

### Existing — do not recreate

- `CloudModelCatalog` fetch/cache machinery.
- Provider-specific list endpoint definitions.
- Existing custom provider pricing fields.

### Out of scope

- Settings presentation.
- Role selection.
- Usage-cost calculation rewrite.

### Risks and dependencies

- Depends on CPS-03 because Qwen model metadata is profile-specific.
- Decimal conversion must not use locale-sensitive parsing.
- Bundled price snapshots can become stale; `asOf` is mandatory.

### Unit/integration tests

- OpenRouter rich fixture including missing/null fields.
- `$0.30/M` and `$2.50/M` conversion from per-token strings.
- Gemini context/method fixture.
- Bundled metadata merge precedence.
- Unknown fields remain nil.
- Token Plan Credits are not formatted as PAYG USD.
- Selected snapshot migration/round-trip; no full model list or key persisted.

### QA black-box

- No required UI change in this step.
- Optional debug-only inspection must not be shipped.

### Required screenshot state

- Not required; data foundation only.

### Done

- [ ] Model metadata is typed, optional and source-attributed.
- [ ] Existing model selection still works by id.
- [ ] No fabricated price/capability.
- [ ] `swift build` and `swift test` green.

### Rollback/checkpoint

- Pre-step checkpoint: `cloud-provider-stabilization/pre-CPS-05`
- Rollback tag: `cloud-provider-stabilization/CPS-05`
- Next: CPS-06.

---

## CPS-06 — Unified role policy and generic role-button stabilization

### Goal

Make Settings, registry, workflow synchronization and runtime preflight consume
one role-availability decision, and close `OBS-002`.

### Related OBS

- `OBS-002`
- `OBS-003`
- `OBS-005`

### Confirmed reason

The architectural cause is verified: five layers independently decide role state.
The concrete no-op branch must be the verified CPS-01 finding and must be cited in
the implementation diff/feedback before code changes.

### Requirements

1. Add pure `ProviderRolePolicy`.
2. Inputs include profile, key/validation, selected model descriptor, registered
   routes and target language.
3. Output includes enabled state, reason, effective model and route kind.
4. Use the same policy in:
   - generic and dedicated provider cards;
   - `ProviderRegistry`;
   - workflow/session selection synchronization;
   - runtime preflight.
5. Replace duplicated string/Boolean gating only where needed for this policy.
6. A click must be atomic:
   - update settings;
   - update workflow;
   - update active session when applicable;
   - persist;
   - retain selection after registry refresh.
7. Disabled roles remain visible with a reason.
8. If target language is `Same`, translation is disabled without destroying the
   user’s saved preferred translation provider.
9. Fix the exact CPS-01 no-op cause with a regression test.

### target_files

```yaml
target_files:
  - Sources/VaniScriptCore/ProviderRolePolicy.swift                 # NEW
  - Sources/VaniScriptCore/ProviderRegistry.swift                   # MODIFY
  - Sources/VaniScriptCore/WorkflowState.swift                      # MODIFY
  - Sources/VaniScript/Stores/WorkflowStore.swift                   # MODIFY
  - Sources/VaniScript/Views/SettingsView.swift                     # MODIFY
  - Tests/VaniScriptCoreTests/ProviderRolePolicyTests.swift         # NEW
  - Tests/VaniScriptCoreTests/ProviderRegistryCloudTests.swift      # MODIFY
  - Tests/VaniScriptCoreTests/WorkflowStateTests.swift              # MODIFY
```

### Existing — do not recreate

- `WorkflowStore.updateSettings`.
- Settings persistence.
- `WorkflowState.synchronizeActiveSessionProviders`.
- Provider ids and usage ids.

### Out of scope

- New provider protocol implementation.
- OpenRouter audio requests.
- Price/context layout.

### Risks and dependencies

- Depends on CPS-01, CPS-03 and CPS-05.
- Selection changes can affect active sessions; tests must distinguish settings
  preference from current workflow target.

### Unit/integration tests

- Truth table for key/profile/model/route/target language.
- Settings selection survives registry refresh.
- Active session updates only when role selection changes.
- `Same` disables runtime translation but preserves preferred settings provider.
- Exact CPS-01 regression.
- Unsupported model produces stable reason code.

### QA black-box

- Repeat CPS-01 OpenRouter click.
- Select/deselect translation across Gemini, Qwen and OpenRouter.
- Change selected model and observe role availability immediately.
- Close/reopen Settings and restart app.
- Run one translation and confirm actual route.

### Required screenshot state

- OpenRouter card after click: orange `Used for Translation`, header badge and
  Cloud API Usage summary all agree.
- Disabled transcription example with its reason visible.

### Done

- [ ] `OBS-002` is closed by a verified regression.
- [ ] UI/registry/runtime use one role policy.
- [ ] Selection persists and active workflow is coherent.
- [ ] `swift build` and `swift test` green.

### Rollback/checkpoint

- Pre-step checkpoint: `cloud-provider-stabilization/pre-CPS-06`
- Rollback tag: `cloud-provider-stabilization/CPS-06`
- Next: CPS-07, CPS-08, CPS-09 in that order.

---

## CPS-07 — Model-aware OpenRouter transcription

### Goal

Enable `Use for Transcribing` only for an OpenRouter model with a verified audio
route, while keeping incompatible models disabled.

### Related OBS

- `OBS-003`

### Confirmed reason

OpenRouter is hardcoded provider-wide `supportsTranscription=false`, and
`CloudAudioTranscriptionEngine` has no OpenRouter route. OpenRouter now exposes
audio/STT contracts and model metadata, but support varies by model.

### Requirements

1. Add a typed OpenRouter transcription route plan in Core.
2. Choose route from `CloudTranscriptionRouteKind`:
   - dedicated `/api/v1/audio/transcriptions`; or
   - verified audio-input chat route.
3. Do not infer support from provider id alone.
4. Build request using the selected/effective model and existing chunk audio.
5. Map response text, usage and structured errors.
6. Reuse existing cue parsing/prompt rules where the route returns unstructured text.
7. Enforce provider limits before reading/sending oversized audio where documented.
8. Keep Qwen/Ollama transcription disabled until their own routes are verified.

### target_files

```yaml
target_files:
  - Sources/VaniScriptCore/CloudTranscriptionRoute.swift             # NEW
  - Sources/VaniScriptCore/ProviderRegistry.swift                    # MODIFY
  - Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift  # MODIFY
  - Tests/VaniScriptCoreTests/CloudTranscriptionRouteTests.swift     # NEW
  - Tests/VaniScriptCoreTests/ProviderRegistryCloudTests.swift       # MODIFY
```

### Existing — do not recreate

- Audio chunking.
- Gemini/OpenAI transcription implementations.
- `TokenUsage` and cue parsing.
- `ProviderRolePolicy`.

### Out of scope

- Generic arbitrary audio protocol for Custom.
- Enabling Qwen Token Plan transcription.
- Changing chunking defaults.

### Risks and dependencies

- Depends on CPS-05 and CPS-06.
- OpenRouter routes/capabilities are model-specific and may drift.
- Audio upload cost/size differs from text token pricing.

### Unit/integration tests

- Eligible and ineligible model fixtures.
- Correct endpoint/headers/model/body plan.
- Dedicated STT and chat-audio response mapping.
- 401/413/unsupported-model error mapping.
- No route for text-only model.

### QA black-box

- Select a verified OpenRouter STT/audio model; activate Transcribing.
- Process a short non-sensitive audio fixture.
- Confirm transcript and usage record.
- Switch to a text-only model; button becomes disabled with reason.

### Required screenshot state

- One enabled OpenRouter transcription model with orange role button.
- One text-only model with disabled role and explanation.

### Done

- [ ] OpenRouter transcription works for a verified eligible model.
- [ ] Text-only models cannot be selected for transcription.
- [ ] Existing Gemini/OpenAI transcription remains green.
- [ ] `swift build` and `swift test` green.

### Rollback/checkpoint

- Pre-step checkpoint: `cloud-provider-stabilization/pre-CPS-07`
- Rollback tag: `cloud-provider-stabilization/CPS-07`
- Next: CPS-08.

---

## CPS-08 — Complete Anthropic text translation routing

### Goal

Turn Anthropic from a key-only card into a real translation/editing provider.

### Related OBS

- `OBS-005`

### Confirmed reason

Anthropic is declared translation-capable in the provider catalog but is absent
from model discovery UI, `ProviderRegistry` translation options and runtime text
routing.

### Requirements

1. Use Anthropic `/v1/models` with required version/auth headers.
2. Replace hardcoded read-only model with the existing model-selection flow.
3. Add typed Anthropic Messages API route/request/response adapter.
4. Add Anthropic to translation registry only when key/profile/model/route pass
   `ProviderRolePolicy`.
5. Add `Use for Translation`; transcription remains disabled with reason.
6. Parse Anthropic input/output usage into existing `TokenUsage`.
7. Preserve structured provider error messages without exposing request headers.
8. No OpenAI-compatible shim for Anthropic.

### target_files

```yaml
target_files:
  - Sources/VaniScriptCore/CloudProviderCatalog.swift                # MODIFY
  - Sources/VaniScriptCore/CloudModelCatalog.swift                   # MODIFY
  - Sources/VaniScriptCore/CloudTextRoute.swift                      # NEW
  - Sources/VaniScriptCore/ProviderRegistry.swift                    # MODIFY
  - Sources/VaniScript/Services/CloudTextTranslationEngine.swift    # MODIFY
  - Sources/VaniScript/Views/SettingsView.swift                      # MODIFY
  - Tests/VaniScriptCoreTests/CloudModelCatalogTests.swift           # MODIFY
  - Tests/VaniScriptCoreTests/CloudTextRouteTests.swift              # NEW
  - Tests/VaniScriptCoreTests/ProviderRegistryCloudTests.swift       # MODIFY
  - Tests/VaniScriptCoreTests/UsageRecorderTests.swift               # MODIFY if Anthropic parser belongs there
```

### Existing — do not recreate

- Anthropic key field.
- Generic model row UX.
- `UsageRecorder`.
- Role policy.

### Out of scope

- Anthropic transcription.
- Anthropic balance.
- Batch API/prompt caching controls.

### Risks and dependencies

- Depends on CPS-05 and CPS-06.
- Anthropic request/usage schema differs from OpenAI-compatible providers.

### Unit/integration tests

- Models request headers and response parser.
- Messages request plan and response text extraction.
- Usage parsing.
- Registry role enabled/disabled matrix.
- 401/rate-limit/error redaction.

### QA black-box

- Paste safe Anthropic key, load models, select one.
- Activate Translation.
- Translate a short text.
- Restart app and confirm selection persists.
- Confirm Transcribing remains disabled.

### Required screenshot state

- Anthropic card with masked valid key, selected model, metadata line and orange
  `Used for Translation`.

### Done

- [ ] Anthropic performs real translation/editing.
- [ ] Model is not hardcoded.
- [ ] No transcription promise.
- [ ] `swift build` and `swift test` green.

### Rollback/checkpoint

- Pre-step checkpoint: `cloud-provider-stabilization/pre-CPS-08`
- Rollback tag: `cloud-provider-stabilization/CPS-08`
- Next: CPS-09.

---

## CPS-09 — Complete Custom provider text translation routing

### Goal

Allow each compatible existing Custom provider to be selected for
translation/editing without claiming unsupported audio behavior.

### Related OBS

- `OBS-005`

### Confirmed reason

`CustomCloudProvider` already stores base URL, key, model, price and budget, but
the settings list is CRUD-only and no runtime/registry translation route exists.

### Requirements

1. Add migration-safe protocol kind, initially only
   `openAIChatCompletions`.
2. Normalize and validate base URL without accepting non-HTTP(S) schemes.
3. Define unambiguously whether stored URL is API base or full endpoint; migrate
   existing values without double-appending paths.
4. Add per-card `Use for Translation`.
5. Provider selection id must remain stable and include the custom UUID without
   colliding with built-in ids.
6. Route through existing OpenAI-compatible text parser.
7. Use existing user-entered price/budget metadata with `User supplied` source.
8. Transcription remains disabled in this track.
9. Deleting an active custom provider safely falls back to a valid local/text
   provider and updates active session consistently.

### target_files

```yaml
target_files:
  - Sources/VaniScriptCore/AppSettings.swift                         # MODIFY
  - Sources/VaniScriptCore/ProviderRegistry.swift                    # MODIFY
  - Sources/VaniScriptCore/CloudTextRoute.swift                      # EXTEND
  - Sources/VaniScript/Services/CloudTextTranslationEngine.swift    # MODIFY
  - Sources/VaniScript/Stores/WorkflowStore.swift                    # MODIFY
  - Sources/VaniScript/Views/SettingsView.swift                      # MODIFY
  - Tests/VaniScriptCoreTests/AppSettingsCloudFieldsTests.swift      # MODIFY
  - Tests/VaniScriptCoreTests/CloudTextRouteTests.swift              # MODIFY
  - Tests/VaniScriptCoreTests/ProviderRegistryCloudTests.swift       # MODIFY
  - Tests/VaniScriptCoreTests/WorkflowStateTests.swift               # MODIFY
```

### Existing — do not recreate

- `CustomCloudProvider`.
- Custom provider add/delete UI.
- User-entered pricing/budget.
- OpenAI-compatible text/usage parser.

### Out of scope

- Arbitrary vendor-specific protocols.
- Custom audio transcription.
- Custom balance APIs.

### Risks and dependencies

- Depends on CPS-06 and CPS-08 route abstraction.
- Existing saved base URLs may use inconsistent suffixes.
- SSRF/network-policy behavior must remain within current app rules.

### Unit/integration tests

- Legacy decode default protocol.
- Base vs full endpoint normalization.
- Reject non-HTTP(S), empty host and malformed URLs.
- Stable custom provider id.
- Delete-active-provider fallback.
- Translation request/response/usage fixture.

### QA black-box

- Configure a safe OpenAI-compatible test endpoint.
- Activate Translation and run one short request.
- Restart app.
- Delete active custom provider and observe safe fallback.
- Confirm Transcribing remains unavailable.

### Required screenshot state

- Custom provider row/card showing model, user-supplied pricing and active
  Translation role; key remains masked/not visible.

### Done

- [ ] Compatible Custom provider can translate.
- [ ] URL/protocol validation is explicit.
- [ ] Delete-active fallback is safe.
- [ ] `swift build` and `swift test` green.

### Rollback/checkpoint

- Pre-step checkpoint: `cloud-provider-stabilization/pre-CPS-09`
- Rollback tag: `cloud-provider-stabilization/CPS-09`
- Next: CPS-10.

---

## CPS-10 — Compact price/context/capability presentation

### Goal

Show useful model economics and capability information without making provider
cards materially taller or duplicating provider logic.

### Related OBS

- `OBS-003`
- `OBS-004`
- `OBS-005`

### Confirmed reason

Current model row renders only `model.id`; rich fields are unavailable to UI and
role buttons do not explain model-level compatibility.

### Requirements

1. Add a small reusable metadata presentation component.
2. Maximum two compact lines below model picker:
   - context;
   - input/output `$ / 1M`;
   - concise modality/capability labels.
3. Format context as `32K`, `128K`, `1M` without rounding a smaller value upward.
4. Price uses locale-stable currency formatting and source unit.
5. Unknown fields show `—` or are omitted; never zero.
6. Tooltip/details show source and `asOf`.
7. Token Plan Credits do not show as PAYG USD.
8. Role button enabled/disabled state updates immediately after model selection.
9. A different effective transcription model is labelled next to the role.
10. Verify light/dark theme, minimum window size and VoiceOver labels.

### target_files

```yaml
target_files:
  - Sources/VaniScriptCore/CloudModelPresentation.swift              # NEW
  - Sources/VaniScript/Views/CloudModelMetadataView.swift            # NEW
  - Sources/VaniScript/Views/SettingsView.swift                      # MODIFY
  - Tests/VaniScriptCoreTests/CloudModelPresentationTests.swift      # NEW
```

### Existing — do not recreate

- `CloudKeyModelRow`.
- Provider card theme/button styles.
- Role policy.
- Custom provider pricing fields.

### Out of scope

- Settings redesign.
- Price history/chart.
- Runtime scraping or automatic billing reconciliation.

### Risks and dependencies

- Depends on CPS-05 through CPS-09.
- Long model ids and localized numbers can overflow compact layout.

### Unit/integration tests

- Context formatting boundaries.
- Decimal price formatting.
- Unknown and Token Plan Credits states.
- Source/as-of accessibility text.
- Effective audio model label.

### QA black-box

- Open each provider card at minimum supported window width.
- Verify no clipping in light/dark themes.
- Change models and observe metadata + roles.
- Verify OpenRouter selected Gemini 2.5 Flash displays values from live metadata,
  subject to current API response.
- VoiceOver reads model, context, prices and disabled reason coherently.

### Required screenshot state

- OpenRouter card at minimum window size showing:
  - selected model;
  - context;
  - input/output price;
  - translation state;
  - transcription state/reason.
- One provider with unknown price showing honest `—`.

### Done

- [ ] Compact metadata appears without card bloat/clipping.
- [ ] Values include provenance/freshness.
- [ ] Role state reacts to model selection.
- [ ] Accessibility labels and both themes verified.
- [ ] `swift build` and `swift test` green.

### Rollback/checkpoint

- Pre-step checkpoint: `cloud-provider-stabilization/pre-CPS-10`
- Rollback tag: `cloud-provider-stabilization/CPS-10`
- Next: CPS-11.

---

## CPS-11 — Acceptance closeout

### Goal

Run the complete native black-box matrix, update documentation and close only the
observations proven fixed.

### Related OBS

- `OBS-001`
- `OBS-002`
- `OBS-003`
- `OBS-004`
- `OBS-005`

### Confirmed reason

The previous `API_USAGE` acceptance relied mainly on mocked tests and documented
manual checks; the reported regressions require real UI and route verification.

### Requirements

1. Complete `CLOUD_PROVIDER_STABILIZATION_ACCEPTANCE.md`.
2. Record build/test counts and real command output.
3. Run provider matrix:
   - Gemini;
   - OpenAI;
   - Anthropic;
   - Qwen PAYG;
   - Qwen Token Plan;
   - OpenRouter;
   - Ollama Cloud;
   - Custom.
4. For each provider record:
   - key validation;
   - model list;
   - metadata state;
   - Translation selection and one real request where supported;
   - Transcription selection and one short audio request where supported;
   - disabled reason where unsupported;
   - persistence after restart.
5. Run embedded Qwen chat with the selected Qwen profile.
6. Verify existing usage/balance behavior did not regress.
7. Update README behavior description.
8. Add closing ADR only after all applicable observations pass.
9. Do not mark an observation fixed when it remains hypothesis/manual-only.

### target_files

```yaml
target_files:
  - AI_Workflow_Kit/docs/CLOUD_PROVIDER_STABILIZATION_ACCEPTANCE.md  # COMPLETE
  - AI_Workflow_Kit/docs/DECISIONS.md                                # closing ADR/status
  - README.md                                                        # MODIFY native behavior only
```

### Existing — do not recreate

- `API_USAGE_ACCEPTANCE.md` remains historical evidence.
- Existing build scripts and QA contour.

### Out of scope

- Product fixes discovered during closeout; they become explicit follow-up steps.
- Electron acceptance.
- State transition.

### Risks and dependencies

- Depends on CPS-01…CPS-10.
- Some providers require paid credentials; unsupported/unavailable credentials
  must be reported honestly, not simulated as PASS.

### Unit/integration tests

- Full `swift test`.
- All new provider suites.
- Existing usage, balance, workflow, Qwen agent and runtime policy suites.

### QA black-box

- Full matrix above on a fresh native build.
- Restart persistence.
- One active-session provider change.
- Minimum window size, light/dark mode, VoiceOver spot check.
- Logs checked for secret leakage.

### Required screenshot state

1. Qwen Token Plan valid + active Translation.
2. Embedded Qwen successful with compatible model.
3. OpenRouter rich metadata + translation.
4. OpenRouter eligible and ineligible transcription states.
5. Anthropic active Translation.
6. Custom active Translation.
7. Cloud API Usage summary matching selected providers.

### Done

- [ ] All applicable OBS acceptance criteria pass.
- [ ] Remaining hypotheses/open external constraints are listed.
- [ ] Build/test/black-box evidence is real and current.
- [ ] No secret in artifacts.
- [ ] No `STATE.yaml` or Electron change in this step.

### Rollback/checkpoint

- Pre-step checkpoint: `cloud-provider-stabilization/pre-CPS-11`
- Completion tag after approval: `cloud-provider-stabilization/CPS-11-done`
- Rollback: docs only; any failed behavior reopens the owning implementation step.

---

## OBS → step mapping

| OBS | Primary mitigation | Verification |
|---|---|---|
| `OBS-001` | CPS-02, CPS-03, CPS-04 | CPS-01, CPS-11 |
| `OBS-002` | CPS-06 | CPS-01, CPS-10, CPS-11 |
| `OBS-003` | CPS-05, CPS-06, CPS-07 | CPS-10, CPS-11 |
| `OBS-004` | CPS-05, CPS-10 | CPS-11 |
| `OBS-005` | CPS-06, CPS-08, CPS-09 | CPS-10, CPS-11 |

## Root cause status at plan handoff

| Root cause | Status |
|---|---|
| Qwen fixed PAYG endpoint used for Token Plan | `VERIFIED` |
| Provider-wide transcription Boolean is insufficient | `VERIFIED` |
| Model metadata discarded except id | `VERIFIED` |
| Anthropic/Custom missing runtime translation routes | `VERIFIED` |
| Exact OpenRouter translation button no-op branch | `UNKNOWN` — CPS-01 hard gate |
