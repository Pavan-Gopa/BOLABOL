# BOLABOL Command Mode Architecture

**Status:** Proposed architecture, revision 2  
**Scope:** Native macOS voice-command mode for BOLABOL  
**Decision:** Build Command Mode as a typed, policy-controlled macOS action engine. An LLM may interpret a request, but it is never an execution authority.

The words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are normative in this document.

---

## 1. Decision summary

BOLABOL currently turns speech into text, polished text, or translated text. Command Mode adds an explicitly selected fourth destination:

```text
Voice
  -> ASR
  -> command interpretation
  -> untrusted CommandProposal
  -> deterministic plan compilation
  -> immutable ExecutableCommandPlan
  -> policy and confirmation
  -> serialized execution
  -> verification
  -> CommandReceipt
```

The architecture is based on ten rules:

1. Normal dictation remains text. A sentence that sounds like a command MUST NOT execute outside explicit Command Mode.
2. ASR output, selected text, window titles, clipboard data, model output, tool output, and application content are all untrusted input.
3. A parser or LLM produces only a `CommandProposal`; it cannot produce an executable object.
4. Only deterministic BOLABOL code can compile a proposal into an `ExecutableCommandPlan`.
5. Every action is versioned, registered, schema-validated, capability-scoped, and assigned a code-defined risk floor.
6. Plans are immutable, expire, bind to an exact target snapshot, and carry an exactly-once execution identifier.
7. Confirmation binds to the exact normalized effects of one plan. Any plan or target change invalidates it.
8. Execution is serialized. Multi-step plans are not assumed to be atomic, and partial effects are reported honestly.
9. Verification is a first-class result. “The API call returned” is not equivalent to “the requested state exists.”
10. Raw model-generated shell commands and AppleScript are outside the trusted execution path.

The product goal is not to create a general-purpose terminal agent. It is to provide fast, native, understandable macOS actions with a narrow and inspectable authority boundary.

---

## 2. Product boundary

A dedicated configurable global hotkey starts Command Mode. The Command HUD MUST be visually distinct from normal dictation and MUST show the current phase.

Examples of supported requests:

- “Open Safari.”
- “Set volume to 30 percent.”
- “Move this window to the right half of the screen.”
- “Remind me tomorrow morning to call Georgii.”
- “Move this selected file to Trash.”
- “Open the BOLABOL project in VS Code and Terminal.”

### 2.1 Explicit mode boundary

The command hotkey is a security boundary, not merely a convenience.

Normal dictation MUST preserve the existing BOLABOL contract: questions, instructions, shell snippets, and imperative sentences inside a transcript are source text to transform or insert, not actions to perform.

A wake phrase MAY be added later as an additional UX signal, but it MUST NOT be the only boundary between dictation and execution.

### 2.2 Non-goals for v1

Command Mode v1 does not provide:

- unrestricted terminal access;
- model-generated AppleScript or shell scripts;
- autonomous browsing through arbitrary UI until a goal appears complete;
- unbounded retry or replanning loops;
- permanent file deletion;
- `sudo` or privilege escalation;
- generic coordinate-based mouse automation;
- silent sending, posting, purchasing, or form submission;
- a promise that every macOS application is controllable.

---

## 3. Trust and threat model

### 3.1 Trusted components

The trusted computing base for Command Mode is intentionally small:

- action registry and versioned schemas;
- plan compiler and validators;
- target resolver and freshness checks;
- policy engine;
- confirmation coordinator;
- native action handlers and adapters;
- execution ledger and receipt store.

The HUD presents decisions but does not make policy decisions.

### 3.2 Untrusted components and data

The following MUST be treated as untrusted:

- speech transcription, including ASR mistakes;
- LLM planner output, regardless of provider or whether the model is local;
- selected text, clipboard contents, filenames, window titles, web pages, and document contents;
- outputs and error messages returned by applications, Shortcuts, AppleScript adapters, or future shell adapters;
- values returned by one plan step and consumed by another;
- persisted command history imported from an older application version.

Untrusted content MUST NOT be able to define an action ID, risk class, required capability, confirmation policy, executable path, script body, or verification rule outside the local registry.

### 3.3 Threats explicitly addressed

The design MUST defend against:

- a normal dictation being misrouted into Command Mode;
- prompt injection embedded in selected text or application content;
- hallucinated action names or malformed arguments;
- ambiguous application or file resolution;
- stale focused-window or focused-element targets;
- path traversal, symlink replacement, and time-of-check/time-of-use races;
- duplicate callbacks and repeated execution;
- a confirmation being reused for a modified plan;
- a failed step causing an unsafe automatic fallback;
- partial completion being reported as complete success;
- sensitive text leaking into model requests or logs.

---

## 4. High-level architecture

```text
+----------------------+       +--------------------------+
| GlobalHotkeyManager  | ----> | VoiceCaptureCoordinator  |
+----------------------+       +------------+-------------+
                                            |
                                            v
                                  +---------+---------+
                                  | Shared ASR path   |
                                  +---------+---------+
                                            |
                                  CommandRequest + local
                                  CommandContextSnapshot
                                            |
                         +------------------+------------------+
                         |                                     |
                 +-------v--------+                    +-------v-------+
                 | FastIntentParser|                    | CommandPlanner|
                 | deterministic   |                    | local / cloud |
                 +-------+--------+                    +-------+-------+
                         |                                     |
                         +------------------+------------------+
                                            |
                                 untrusted CommandProposal
                                            |
                                  +---------v----------+
                                  | CommandPlanCompiler|
                                  | strict validation  |
                                  +---------+----------+
                                            |
                                immutable ExecutableCommandPlan
                                            |
                                  +---------v----------+
                                  | CommandPolicyEngine|
                                  +----+-----------+---+
                                       |           |
                                    allow      confirmation
                                       |           |
                                       +-----+-----+
                                             |
                                  +----------v-----------+
                                  | CommandExecutionActor|
                                  | exactly-once ledger   |
                                  +----------+-----------+
                                             |
                                  +----------v-----------+
                                  | Action verification  |
                                  +----------+-----------+
                                             |
                                  +----------v-----------+
                                  | CommandReceipt + HUD |
                                  +----------------------+
```

Both the fast parser and the LLM planner enter the same validation, policy, confirmation, execution, and verification pipeline. A deterministic parser is faster; it is not more privileged.

---

## 5. Separate voice capture from command execution

The current hotkey coordinator protects microphone recording and transcription processing. Command execution has a longer and different lifecycle, so the two concerns MUST NOT be combined into one enum.

### 5.1 Voice capture state

```swift
public enum VoiceSessionKind: Sendable, Equatable {
    case dictation
    case command
}

public enum VoiceCapturePhase: Sendable, Equatable {
    case idle
    case recording(kind: VoiceSessionKind, ownerID: UUID)
    case processing(kind: VoiceSessionKind, ownerID: UUID)
}
```

The voice coordinator owns only the microphone/ASR lease:

- only one capture session exists at a time;
- Command Mode cannot steal an active dictation session;
- active recording never expires merely because it is long;
- stuck processing may expire independently;
- cancellation releases the capture lease exactly once.

### 5.2 Command run state

A separate actor owns planning and execution:

```swift
public enum CommandRunState: Sendable, Equatable {
    case idle
    case interpreting(sessionID: UUID)
    case clarifying(sessionID: UUID, request: ClarificationRequest)
    case compiling(sessionID: UUID)
    case awaitingPermission(sessionID: UUID, capability: CommandCapability)
    case awaitingConfirmation(sessionID: UUID, planID: UUID)
    case executing(sessionID: UUID, planID: UUID, stepID: String)
    case verifying(sessionID: UUID, planID: UUID, stepID: String)
    case completed(CommandReceipt)
    case failed(CommandFailure)
    case cancelled(sessionID: UUID, receipt: CommandReceipt?)
    case expired(sessionID: UUID)
}
```

Command execution can outlive audio capture. In v1, only one command run may be non-terminal at a time. The UI may also reject a new voice interaction while a confirmation is visible, even though the microphone lease has already ended.

`awaitingConfirmation` belongs to the command run, not to the voice capture phase.

---

## 6. Hotkey integration

Command Mode needs a dedicated configurable binding. `Option+Q` is a reasonable suggested default, but registration MUST reject collisions and MUST NOT silently replace another binding.

Instead of continuing to add unrelated stored strings and hard-coded Carbon IDs, the hotkey layer SHOULD move toward typed bindings:

```swift
public enum GlobalHotkeyAction: UInt32, CaseIterable, Codable, Sendable {
    case dictation = 1
    case fullTranslation = 2
    case quickTranslation = 3
    case settings = 4
    case command = 5
}

public struct GlobalHotkeyBinding: Codable, Equatable, Sendable {
    public let action: GlobalHotkeyAction
    public var combination: String
    public var enabled: Bool
}
```

During migration, existing notification names may remain as compatibility bridges. New command code SHOULD consume a typed event carrying the action and key phase rather than creating three more unrelated notifications.

The implementation MUST reuse existing normalization, keyboard-layout handling, duplicate detection, and hold/toggle semantics. Persistence decoding must remain backward compatible when the new binding is absent.

---

## 7. Context and target ownership

Natural commands need local context, but a context snapshot is not itself an executable target.

### 7.1 Portable context snapshot

`NativeBolabolCore` may contain only portable, `Sendable`, serializable metadata:

```swift
public struct CommandContextSnapshot: Codable, Sendable, Equatable {
    public let snapshotID: UUID
    public let capturedAt: Date
    public let frontmostApplication: ApplicationContext?
    public let focusedWindow: WindowContext?
    public let focusedElement: AccessibilityElementMetadata?
    public let selectedText: SensitiveTextReference?
    public let finderSelection: [FileReference]
    public let currentScreen: ScreenContext?
    public let targetToken: CommandTargetToken?
}
```

A snapshot may include:

- application name, bundle ID, and PID;
- focused-window metadata and geometry;
- focused-element role and accessibility identifier when available;
- selected-text length/hash and an opaque local reference;
- Finder selection as locally resolved file references;
- current screen and display geometry;
- capture timestamp.

Clipboard contents MUST NOT be copied into every snapshot. Clipboard type, size, or hash may be recorded locally; full content is fetched only for an action that explicitly needs it.

### 7.2 Ephemeral native handles

Raw `AXUIElement`, `NSRunningApplication`, `NSWindow`, pasteboard objects, security-scoped URLs, and other AppKit handles MUST stay in the `NativeBolabol` target.

A `@MainActor` `CommandTargetHandleStore` maps an opaque `CommandTargetToken` to short-lived native handles. Tokens expire and are never serialized or sent to a model.

### 7.3 Target binding policy

Every action that uses “this”, “selected”, or “current” declares a binding policy:

```swift
public enum CommandTargetBinding: Codable, Sendable, Equatable {
    case capturedAtInvocation(snapshotID: UUID, token: CommandTargetToken)
    case currentAtExecution
    case explicitApplication(bundleID: String)
    case explicitFile(FileReference)
}
```

Rules:

- “Close this window” binds to the window captured when Command Mode started.
- “Move this selected file to Trash” binds to the captured Finder selection.
- “Open Safari” uses an explicit resolved bundle ID and needs no focused target.
- A stale captured target MUST cause rejection or renewed confirmation; the executor MUST NOT silently switch to whichever window is focused later.
- Target freshness is checked before confirmation and again immediately before execution.

### 7.4 Planner context is smaller than local context

The local snapshot and the model payload are different objects. A `PlannerContextMinimizer` constructs the smallest context needed for the request.

For a cloud planner:

- local opaque IDs are preferred over raw content;
- selected text is included only when the request explicitly refers to it;
- secrets, passwords, tokens, clipboard contents, and unrelated window content are removed;
- the user must explicitly enable cloud command planning.

All application and document content is labeled as data, never as planner instructions.

---

## 8. Interpretation result: proposal, clarification, or rejection

A request is not always resolvable. The interpreter MUST be allowed to ask instead of guessing.

```swift
public enum CommandInterpretationResult: Sendable, Equatable {
    case proposal(CommandProposal)
    case clarification(ClarificationRequest)
    case noMatch
    case rejected(CommandRejection)
}
```

Examples that require clarification:

- two installed applications have the same display name;
- “move the file” when multiple files are selected;
- “send this” without a recipient or destination;
- a relative date such as “tomorrow morning” when no default time policy exists;
- a URL or custom scheme whose effect cannot be previewed safely.

The HUD gains a `Clarifying…` state and presents a bounded question. Clarification answers join the existing command session; they do not create an open-ended general chat.

---

## 9. Fast intent path

Common commands SHOULD use a deterministic local parser first:

```swift
public enum FastCommandIntent: Sendable, Equatable {
    case openApplication(name: String)
    case activateApplication(name: String)
    case setVolume(percent: Int)
    case mute(Bool)
    case moveWindow(WindowPlacement)
    case openURL(URL)
    case revealFile(FileReference)
    case runShortcut(name: String)
}
```

The parser returns `CommandInterpretationResult`, not `ActionPlan`.

```swift
protocol FastCommandParsing: Sendable {
    func interpret(
        request: String,
        locale: Locale,
        context: CommandContextSnapshot
    ) -> CommandInterpretationResult
}
```

The fast parser MUST:

- emit the same versioned action IDs used by the registry;
- avoid fuzzy selection when several applications or files match;
- clamp numeric values only when the product contract explicitly defines clamping;
- fall through to the planner or clarification instead of attempting heroic language understanding;
- pass every proposal through the normal compiler and policy engine.

---

## 10. Command planner

The planner converts natural language and minimized context into an untrusted proposal.

```swift
public protocol CommandPlanning: Sendable {
    func interpret(
        request: String,
        context: PlannerContext,
        manifest: CommandCapabilityManifest
    ) async throws -> CommandInterpretationResult
}
```

The planner receives only the action manifest exposed for the current application version and operating environment. It cannot invent new actions, schemas, permissions, risk classes, backends, or script bodies.

A proposal envelope is generic because the model produces JSON, but each step’s arguments are decoded into the registered action-specific `Input` type before a plan exists:

```swift
public struct CommandProposal: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let requestID: UUID
    public let summary: String
    public let steps: [ProposedCommandStep]
}

public struct ProposedCommandStep: Codable, Sendable, Equatable {
    public let localID: String
    public let actionID: String
    public let actionVersion: Int
    public let arguments: JSONValue
    public let inputBindings: [CommandValueBinding]
}
```

The model MUST NOT supply fields such as `risk`, `requiresConfirmation`, `executable`, `script`, `shellCommand`, `workingDirectory`, `verificationSucceeded`, or `targetHandle`.

---

## 11. Deterministic plan compilation

`CommandPlanCompiler` is the only component allowed to create an executable plan.

It performs, at minimum:

- strict proposal-envelope decoding;
- action ID and action-version lookup;
- action-specific argument decoding and validation;
- rejection of unknown or forbidden fields where the schema requires strictness;
- bounded string, collection, and payload sizes;
- application-name resolution to an exact bundle ID;
- URL scheme validation;
- date/time resolution using an explicit locale and time zone;
- file-reference canonicalization and identity capture;
- output-reference type checking;
- dependency-order validation and cycle rejection;
- target freshness validation;
- step-count and total-effect limits;
- capability and backend availability checks;
- risk and effect calculation from local code;
- generation of a deterministic effect preview;
- plan expiry and digest calculation.

V1 plans are sequential and contain at most four steps. A step may reference only a declared typed output from an earlier step. Arbitrary JSONPath, loops, recursion, and dynamic action construction are not supported.

```swift
public struct ExecutableCommandPlan: Sendable {
    public let planID: UUID
    public let executionID: UUID
    public let requestID: UUID
    public let createdAt: Date
    public let expiresAt: Date
    public let registryVersion: String
    public let policyVersion: String
    public let contextSnapshotID: UUID
    public let steps: [PreparedCommandStep]
    public let aggregateRisk: ActionRisk
    public let effectPreview: CommandEffectPreview
    public let planDigest: String
}
```

The plan is immutable. The executor receives only prepared, locally validated steps, never raw model JSON.

If the registry, policy version, relevant target, permissions, or prepared effect changes before execution, the plan is recompiled and any prior confirmation becomes invalid.

---

## 12. Action registry and handlers

Every executable capability is represented by a versioned action descriptor and a native handler.

Stable IDs include the schema version, for example:

```text
application.open.v1
application.activate.v1
window.tile.v1
file.reveal.v1
file.trash.v1
reminder.create.v1
shortcut.run.v1
```

A handler has an action-specific input/output type. Preparation is side-effect-free.

```swift
public protocol CommandActionHandler: Sendable {
    associatedtype Input: Codable & Sendable
    associatedtype Prepared: Sendable
    associatedtype Output: Codable & Sendable

    static var descriptor: CommandActionDescriptor { get }

    func prepare(
        input: Input,
        context: CommandPreparationContext
    ) async throws -> Prepared

    func execute(
        prepared: Prepared,
        context: CommandExecutionContext
    ) async throws -> Output

    func verify(
        prepared: Prepared,
        output: Output,
        context: CommandVerificationContext
    ) async -> VerificationResult
}
```

`CommandActionDescriptor` defines:

- stable action ID and version;
- argument and output schemas;
- static risk floor;
- required capabilities;
- target-binding rules;
- availability requirements;
- whether the action is idempotent;
- whether an explicit compensation action exists;
- effect-preview builder;
- dynamic risk evaluator.

Risk may increase based on arguments and context. It can never fall below the descriptor’s risk floor.

A type-erased registry wrapper is used at runtime, but each action keeps typed validation internally.

---

## 13. Capability and permission model

The planner manifest is derived at runtime from registered handlers, operating-system availability, user settings, and available adapters.

```swift
public enum CommandCapability: Hashable, Codable, Sendable {
    case accessibility
    case clipboardRead
    case clipboardWrite
    case fileRead(scope: FileScope)
    case fileMutation(scope: FileScope)
    case reminders
    case calendar
    case appleEvents(targetBundleID: String)
    case shortcuts
    case network
}
```

Rules:

- The model never requests an entitlement or TCC permission directly.
- Permission prompts are initiated by deterministic UI code after policy approval.
- Missing permission produces `awaitingPermission` or a structured denial; it does not trigger a different backend silently.
- An action is not advertised when no stable backend is available on the current system.
- Apple Events permissions are target-specific and MUST be represented as such.
- Usage descriptions and entitlements MUST accurately describe real automation behavior before the feature ships.
- The polishing worker receives no computer-control capabilities.

### 13.1 Candidate backend matrix

| Category | Preferred backend | Notes |
|---|---|---|
| Open/activate applications and resources | `NSWorkspace`, `NSRunningApplication` | Resolve application names to exact bundle IDs before planning. |
| Window geometry and focus | Accessibility API | Revalidate PID/window identity immediately before execution. |
| File reveal/open/Trash | `NSWorkspace`, `FileManager` | Use canonical URLs and captured file identity; no permanent delete in v1. |
| Reminders and calendar | EventKit where supported | Requires explicit permission and returned object identifiers. |
| Notes and app-specific automation | Named Shortcut or pre-authored adapter | Do not claim a native framework when none is implemented. |
| Volume/media/system actions | Stable public adapter, named Shortcut, or predefined automation | Expose the action only when the chosen backend is present and tested. |
| AppleScript | Pre-authored, parameterized adapter only | The model never generates script text. |
| Shell | Not exposed to the planner in v1 | See Section 20. |

---

## 14. Risk and policy model

“Reversible” is not a sufficient safety category: a file move, app quit, or Trash operation may not be reliably reversible. Risk is classified by observable effect.

```swift
public enum ActionRisk: Int, Codable, Sendable, Comparable {
    case readOnly
    case transient
    case localMutation
    case externalCommit
    case destructive
    case privileged
}
```

### Read-only

Examples:

- inspect local state;
- reveal a file in Finder;
- read current volume;
- resolve an installed application.

### Transient

Examples:

- activate/open an application;
- change window geometry;
- play/pause media;
- set volume;
- open a normal `https` URL.

### Local mutation

Examples:

- create a reminder or calendar event;
- rename or move a file;
- move an item to Trash;
- replace selected text;
- quit an application that may have unsaved work.

### External commit

Examples:

- send a message or email;
- publish content;
- submit a form;
- mutate a remote API;
- run a Shortcut whose declared effects leave the Mac.

### Destructive

Examples:

- permanent deletion;
- clearing Trash;
- overwriting an existing file;
- bulk destructive operations.

### Privileged

Examples:

- `sudo`;
- privacy/security settings changes;
- package installation requiring elevation;
- low-level system modification.

`CommandPolicyEngine` returns:

```swift
public enum CommandPolicyDecision: Sendable, Equatable {
    case allow
    case requirePermission(CommandCapability)
    case requireConfirmation(ConfirmationRequest)
    case deny(CommandRejection)
}
```

Policy rules for v1:

- explicit Command Mode is a precondition for every action;
- read-only and selected transient actions may execute automatically after target validation;
- file mutations, app quit, selected-text replacement, reminders, calendar events, and unknown-effect Shortcuts require confirmation by default;
- external commits always require confirmation;
- destructive actions are disabled or require a dedicated high-friction flow not present in the initial MVP;
- privileged actions are denied;
- a plan uses the maximum risk of its steps plus any dynamic escalation;
- file count, protected paths, overwrite behavior, URL scheme, target application, and Shortcut declaration may raise risk;
- user preferences may reduce prompts only for explicitly allowlisted transient actions, never for external, destructive, or privileged effects.

The model cannot lower risk or choose the confirmation policy.

---

## 15. Confirmation contract

Confirmation describes the exact pending effect, not the user’s original sentence and not a model-written summary.

Examples:

```text
Move “installer.dmg” from Downloads to Trash?
[Cancel] [Move]
```

```text
Create reminder “Call Georgii” for 09:00 tomorrow?
[Cancel] [Create]
```

For a multi-step plan, the preview lists all material effects and identifies any steps that have already completed.

A confirmation token is:

- bound to `planID`, `planDigest`, effect digest, target identity, and policy version;
- single-use;
- short-lived;
- invalidated by any plan, target, permission, registry, or effect change;
- consumed atomically when execution starts.

```swift
public struct CommandConfirmationToken: Sendable, Equatable {
    public let tokenID: UUID
    public let planID: UUID
    public let planDigest: String
    public let effectDigest: String
    public let expiresAt: Date
}
```

A replan, changed argument, changed target, or newly introduced action always requires a fresh policy decision and, when applicable, fresh confirmation.

---

## 16. Serialized and exactly-once execution

A dedicated `CommandExecutionActor` serializes plan execution.

Each plan has a unique `executionID`. An execution ledger records:

```text
prepared
awaiting_permission
awaiting_confirmation
executing(step)
verifying(step)
completed
completed_unverified
failed
cancelled
expired
```

Rules:

- the same `executionID` MUST NOT cause a side effect twice;
- duplicate hotkey callbacks, UI taps, WebSocket events, or task resumptions return the existing state/receipt;
- side-effecting actions are not retried automatically unless their handler explicitly declares and proves idempotency;
- plan expiry is checked before execution and before every delayed confirmed step;
- target freshness is checked immediately before each target-sensitive action;
- the executor stops at the first unhandled failure;
- completed steps remain completed and appear in the receipt;
- multi-step plans are not described as transactions;
- rollback occurs only through a separately registered and policy-checked compensation action;
- cancellation before an action starts prevents it; cancellation during a non-cancellable OS call is best-effort and the resulting effect is verified and reported.

A command is never reported simply as “cancelled” when one or more effects may already have happened.

---

## 17. Verification and receipts

Verification has three outcomes:

```swift
public enum VerificationResult: Codable, Sendable, Equatable {
    case verified(evidence: VerificationEvidence)
    case unverified(reason: String)
    case failed(reason: String)
}
```

Examples:

- application open -> verify exact bundle ID is running;
- application activate -> verify it is frontmost when practical;
- file moved -> verify destination identity and absence of the original entry;
- move to Trash -> verify the original reference no longer resolves at its prior location;
- window moved -> read back AX frame;
- reminder/calendar event -> retain and verify the returned object identifier;
- volume changed -> read back value when the chosen backend supports it.

Verification MUST be read-only and MUST NOT perform a new effect in order to prove the first one.

Every terminal command state produces a redacted `CommandReceipt`:

```swift
public struct CommandReceipt: Codable, Sendable, Equatable {
    public let sessionID: UUID
    public let planID: UUID
    public let executionID: UUID
    public let planDigest: String
    public let startedAt: Date
    public let finishedAt: Date
    public let steps: [CommandStepReceipt]
    public let terminalState: CommandTerminalState
}
```

The receipt distinguishes:

- full verified success;
- completed but unverified;
- failure before any effect;
- partial completion;
- cancellation before or after effects;
- expiry.

---

## 18. Failure and replanning policy

V1 does not run an open-ended agent loop.

After a failure:

1. the executor records a structured, redacted failure;
2. no fallback action runs automatically;
3. the HUD explains what completed and what did not;
4. the user may retry, cancel, or request a new plan.

A later version MAY support one bounded replan, subject to all of these rules:

- the failure and tool output are treated as untrusted data;
- a new `CommandProposal` is created and passes through the full compiler and policy path;
- completed effects are included in context so they are not repeated;
- risk cannot increase silently;
- target binding cannot change silently;
- a new side effect requires new confirmation when policy requires it;
- no replan occurs after an external, destructive, or privileged effect without explicit user initiation.

---

## 19. File, URL, text, and application safety rules

### 19.1 Files

- Raw model strings such as `~/Downloads/file.dmg` are never executable file targets by themselves.
- Paths are expanded and canonicalized locally, with symlinks resolved according to action policy.
- A prepared file reference SHOULD include file resource identity in addition to path.
- Identity and destination are rechecked immediately before mutation.
- Traversal components, escaping symlinks, protected roots, device files, and unsupported URL schemes are denied.
- Rename/move actions never overwrite by default.
- Bulk file actions have strict item and byte-count limits.
- Trash is the most destructive file operation in the initial release; permanent delete is absent.

### 19.2 URLs

- `http` and `https` are handled separately from custom schemes.
- Custom schemes are dynamically elevated because opening them may trigger application-specific mutations.
- Credentials and tokens are removed from previews and logs.
- The planner cannot synthesize a URL that bypasses an action-specific allowlist.

### 19.3 Applications

- Display names are resolved locally to exact installed bundle IDs.
- Multiple matches require clarification.
- The plan stores the resolved bundle ID, not only the spoken name.
- Quit/terminate is not classified as a harmless application action because unsaved work may exist.

### 19.4 Text insertion

- “Paste text” and “send/submit text” are separate actions.
- Inserting text into a field MUST NOT implicitly press Return, click Send, or submit a form.
- Targeted insertion binds to the captured application/element and revalidates it before mutation.
- Existing clipboard and Accessibility infrastructure may be reused behind a typed handler, but the handler chooses one insertion strategy per execution to prevent duplicate insertion.

---

## 20. AppleScript and shell boundary

### 20.1 AppleScript

AppleScript may be used only behind a registered, pre-authored, parameterized adapter.

The model may choose a typed action such as `notes.create.v1`; it may not provide AppleScript source. Parameters are encoded through a safe adapter rather than interpolated into script text.

### 20.2 Shell

Raw shell execution is not exposed to the planner in v1.

A future power-user layer SHOULD prefer:

- named Apple Shortcuts;
- user-authored named automations;
- registered executable templates with typed arguments;
- absolute executable allowlists;
- direct process invocation with an argument array.

It MUST NOT treat a model-generated string as `sh -c`, `zsh -c`, or `osascript -e` input.

If an advanced raw-terminal feature is ever added, it is a separate user-facing mode with literal command preview and explicit approval for every invocation. It is not a fallback selected autonomously by the command planner.

---

## 21. Initial action set

The first milestone should be smaller than a broad 15–20-action promise. Each action needs target semantics, permissions, preview, risk, cancellation behavior, verification, and tests.

Recommended foundation set:

### Applications and resources

- `application.open.v1`
- `application.activate.v1`
- `url.open.v1` for validated `http`/`https`
- `file.reveal.v1`

### Windows

- `window.minimize.v1`
- `window.tile.v1` with left/right/center placements

### System

- `system.volume.set.v1`
- `system.mute.set.v1`

These system actions are exposed only when a stable, tested adapter is available.

### Mutating actions requiring confirmation

- `file.trash.v1`
- `reminder.create.v1`
- `shortcut.run.v1`

A named Shortcut is not automatically safe; its declared or user-approved effect profile determines policy.

Actions deferred until the foundation is proven:

- app quit;
- file rename/move;
- selected-text replacement;
- calendar events;
- Notes integration;
- media transport across arbitrary apps;
- message/email sending;
- browser form interaction;
- shell or raw AppleScript.

---

## 22. HUD and confirmation UX

The HUD remains compact and visually consistent with the current BOLABOL capsule.

Suggested states:

```text
COMMAND · Listening…
COMMAND · Understanding…
COMMAND · Clarifying…
COMMAND · Preparing…
COMMAND · Permission required…
COMMAND · Confirmation required…
COMMAND · Executing 1/3…
COMMAND · Verifying…
COMMAND · Done
COMMAND · Done, not verified
COMMAND · Partially completed
COMMAND · Failed
COMMAND · Cancelled
COMMAND · Expired
```

UX requirements:

- distinguish command recording from normal dictation before speech begins;
- show the resolved target for target-sensitive actions;
- show exact material effects for confirmation;
- prevent double confirmation taps;
- keep Cancel available before every not-yet-started effect;
- explain partial completion rather than collapsing it into a generic failure;
- never show model prose as if it were a trusted effect preview.

Detailed history may live in a later Command History panel. The HUD displays only the current bounded interaction.

---

## 23. Conversation and Voice Skills

### 23.1 Follow-up commands

V1 is single-shot. A later `CommandConversationSession` may retain bounded references:

- recent request;
- resolved application/file/entity IDs;
- prior receipts;
- current context snapshot ID;
- expiration time.

It does not reuse general dictation history, raw application content, or an unbounded chat transcript.

A follow-up request still creates a new proposal and plan. Previous confirmation never authorizes a new effect.

### 23.2 Voice Skills

A successful verified plan may later be saved as a Voice Skill.

A Voice Skill stores versioned typed actions and explicit bindings, not LLM prose, scripts, or a replay of the original model response.

On load, every action version, target binding, capability, policy, and confirmation requirement is revalidated. A saved skill cannot freeze old permissions or bypass newer policy.

---

## 24. Source layout and target boundaries

```text
Sources/NativeBolabolCore/
  Commands/
    Models/
      CommandRequest.swift
      CommandProposal.swift
      ExecutableCommandPlan.swift
      CommandReceipt.swift
      CommandRisk.swift
      CommandContextSnapshot.swift
    Planning/
      FastIntentParser.swift
      CommandPlanCompiler.swift
      CommandCapabilityManifest.swift
      PlannerContextMinimizer.swift
    Policy/
      CommandPolicyEngine.swift
      CommandConfirmationContract.swift
    Registry/
      CommandActionDescriptor.swift
      CommandActionRegistry.swift

Sources/NativeBolabol/
  Commands/
    CommandPipelineCoordinator.swift
    CommandRunCoordinator.swift
    CommandExecutionActor.swift
    CommandTargetHandleStore.swift
    CommandContextCaptureService.swift
    CommandConfirmationCoordinator.swift
    Adapters/
      WorkspaceAdapter.swift
      AccessibilityAdapter.swift
      FileSystemAdapter.swift
      EventKitAdapter.swift
      ShortcutAdapter.swift
      AppleEventAdapter.swift
    Actions/
      ApplicationActions.swift
      WindowActions.swift
      SystemActions.swift
      FileActions.swift
      ReminderActions.swift
      ShortcutActions.swift
    HUD/
      CommandHUDState.swift
      CommandHUDControls.swift
```

Hard target boundary:

- `NativeBolabolCore` contains no AppKit, Accessibility, `AXUIElement`, `NSWorkspace`, Carbon, EventKit object handles, or process execution.
- `NativeBolabol` owns OS adapters, permissions, native handles, and UI.
- `NativeBolabolPolishWorker` has no command registry, target store, or execution adapters.

---

## 25. Testing strategy

### 25.1 Pure unit tests

- backward-compatible hotkey settings decoding;
- binding collision detection and keyboard-layout normalization;
- voice-capture and command-run state machines;
- deterministic fast parser by locale;
- strict proposal decoding and size limits;
- unknown action/version rejection;
- action-specific input validation;
- output-reference type checking and cycle rejection;
- plan expiry and digest stability;
- dynamic risk escalation;
- policy decisions and confirmation-token binding;
- planner-context minimization/redaction;
- receipt construction for success, failure, cancellation, and partial completion.

### 25.2 Security regression tests

At minimum:

1. Normal dictation containing “delete the file” never enters the command pipeline.
2. Selected text containing planner instructions remains data.
3. An LLM proposal with an unknown action or extra forbidden field is rejected.
4. A proposal cannot set its own risk or confirmation policy.
5. Ambiguous application names require clarification.
6. A focused-window change invalidates a captured-target plan.
7. A symlink swap between preparation and execution is detected.
8. Reusing one confirmation token fails.
9. Changing one argument changes the plan digest and invalidates confirmation.
10. Delivering one `executionID` twice produces one effect.
11. Cancellation after one completed step produces a partial receipt.
12. A failed side effect is not retried automatically.
13. A Shortcut or adapter output containing prompt injection cannot create a new action.
14. Logs and receipts omit selected text, clipboard content, secrets, and model prompts by default.
15. Raw shell or AppleScript text cannot appear in a planner-executable action.

### 25.3 Adapter and integration tests

Use protocol-backed adapters and mocks for default tests:

- `MockWorkspaceAdapter`
- `MockAccessibilityAdapter`
- `MockFileSystemAdapter`
- `MockEventKitAdapter`
- `MockShortcutAdapter`
- `MockPermissionAdapter`

An opt-in macOS integration suite may:

- open a harmless test application;
- manipulate a dedicated test window;
- reveal or Trash a temporary test file;
- create and remove a test reminder in a dedicated list;
- run a dedicated no-op test Shortcut.

Destructive integration tests are never part of the default CI path.

---

## 26. Privacy and observability

Command telemetry is structured and redacted by default.

Useful fields:

```text
session ID
request route: fast / local planner / cloud planner
context fields disclosed to planner
plan ID and digest
registry and policy version
step count and action IDs
risk class
permission/confirmation decision
execution duration
verification result
terminal receipt category
error category
```

Do not log by default:

- full utterances;
- selected text or clipboard contents;
- message bodies;
- window/document contents;
- filenames when a hash or category is sufficient;
- passwords, API keys, tokens, URL credentials;
- complete model prompts or raw model responses;
- shell, script, or adapter output that may contain secrets.

Debug logging that includes sensitive content requires a separate explicit opt-in and clear retention behavior.

---

## 27. Implementation phases

### Phase 0 — Contracts and threat tests

- finalize action IDs and schema-version rules;
- implement proposal/plan/receipt models;
- implement plan compiler, digest, expiry, and strict validation;
- implement policy and confirmation-token contracts;
- add security regression tests before OS actions exist.

### Phase 1 — Session and HUD foundation

- typed command hotkey binding and persistence migration;
- separate voice capture and command run coordinators;
- distinct Command HUD states;
- context snapshot and ephemeral target store;
- cancellation, expiry, and exactly-once execution ledger.

### Phase 2 — Narrow native MVP without an LLM

- deterministic fast parser;
- application open/activate;
- validated URL open;
- window minimize/tile;
- file reveal and confirmed Trash;
- volume/mute when a stable adapter is present;
- confirmed reminder and named Shortcut actions;
- verification and receipts.

### Phase 3 — Structured planner

- local/cloud planner selection;
- minimized planner context;
- structured proposal schema;
- clarification flow;
- up to four sequential typed steps;
- no autonomous side-effecting replan in the first planner release.

### Phase 4 — Carefully bounded extensions

- bounded follow-up sessions;
- Voice Skills;
- additional application-specific adapters;
- explicit compensation actions;
- optional one-shot replan under Section 18 rules;
- advanced user-authored automation registry.

Raw model-authored shell and AppleScript remain outside the architecture.

---

## 28. MVP acceptance criteria

Command Mode v1 is ready only when all of the following are true:

- a dedicated configurable hotkey starts an unmistakable Command Mode session;
- normal dictation cannot execute actions, even when its text is imperative;
- dictation and command capture cannot race or steal ownership;
- fast parsing produces proposals, not executable plans;
- model output cannot reach an executor without strict local compilation;
- unknown actions, versions, fields, references, and oversized payloads fail closed;
- every action has a registered risk floor, required capabilities, effect preview, and verifier contract;
- target-sensitive actions bind to an exact snapshot and fail on stale or changed targets;
- confirmation is single-use and bound to the exact plan/effect digest;
- one `executionID` produces at most one side effect;
- multi-step partial completion is visible in receipts and HUD state;
- file operations resist traversal, symlink escape, overwrite, and stale-target races;
- cloud planning is opt-in and receives minimized context;
- no planner-accessible raw shell or generated AppleScript exists;
- cancellation and expiry are safe at every pre-effect stage;
- verification distinguishes verified, unverified, and failed outcomes;
- tests cover prompt injection, plan tampering, confirmation replay, duplicate execution, stale targets, permissions, and partial failure;
- existing dictation, translation, polishing, and hotkey behavior does not regress.

---

## 29. Recommended first end-to-end milestone

The first release candidate should prove a small set deeply rather than a large set superficially:

```text
Open Safari.
Activate Telegram.
Open https://github.com/Pavan-Gopa/BOLABOL.
Move this window to the right half.
Minimize this window.
Reveal this selected file in Finder.
Move this selected file to Trash.          # confirmation required
Set volume to 30 percent.                  # only with stable adapter
Mute the Mac.                              # only with stable adapter
Create a reminder tomorrow at 09:00.       # confirmation + permission
Run the Shortcut “Work Mode”.              # confirmation/policy based on declaration
```

For each command, the milestone is complete only when target resolution, policy, confirmation, exactly-once execution, verification, cancellation, and tests are all implemented.

---

## 30. Final architecture decision

> **BOLABOL Command Mode is a native macOS action engine assisted by language models. It is not a language model with ambient authority over the computer.**

The durable boundary is:

```text
untrusted interpretation
        -> deterministic compilation
        -> immutable plan
        -> policy-bound authority
        -> exact confirmed effects
        -> serialized native execution
        -> verification and receipt
```

Any future feature that bypasses this boundary is a separate architecture decision and must not be introduced as a convenient fallback.