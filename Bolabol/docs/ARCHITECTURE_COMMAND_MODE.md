# BOLABOL Voice Command Architecture

**Status:** Draft architecture proposal  
**Scope:** Native macOS voice-command mode for BOLABOL  
**Primary goal:** Add a dedicated voice-control pipeline that can execute safe, structured actions on macOS without turning the LLM into an unrestricted shell by default.

---

## 1. Product idea

BOLABOL currently turns speech into text, polished text, or translated text. Command Mode adds a fourth destination:

```text
Voice -> ASR -> Command Understanding -> Action Plan -> Policy -> Execution -> Verification
```

A dedicated configurable global hotkey (for example `Option+Q`) tells BOLABOL that the utterance is a **computer command**, not text to insert into the active application.

Examples:

- "Open Safari"
- "Set volume to 30 percent"
- "Move this window to the right half of the screen"
- "Remind me tomorrow morning to call Georgii"
- "Move this file to Trash"
- "Open the BOLABOL project in VS Code and Terminal"

The Command HUD should look visually distinct from normal dictation and make the current phase obvious: listening, understanding, executing, waiting for confirmation, verifying, done, or failed.

---

## 2. Design principles

### 2.1 LLM decides **what**, BOLABOL decides **how**

The LLM should not normally emit shell commands such as:

```text
osascript -e 'tell application "Safari" to activate'
rm ~/Downloads/file.dmg
```

Instead, it emits typed actions:

```json
{
  "type": "open_application",
  "application": "Safari"
}
```

or:

```json
{
  "type": "move_to_trash",
  "path": "~/Downloads/file.dmg"
}
```

The native BOLABOL executor chooses the appropriate macOS API, Accessibility action, EventKit call, AppleScript fallback, or shell fallback.

This keeps the system testable, auditable, and safer than exposing a single unrestricted terminal tool as the primary control surface.

### 2.2 Native first, shell last

Prefer native macOS APIs and well-defined adapters:

1. `NSWorkspace` / AppKit
2. Accessibility (`AXUIElement`)
3. EventKit / native frameworks
4. Apple Shortcuts
5. AppleScript / `osascript`
6. Shell fallback only when no structured action exists

### 2.3 Fast commands should not require an LLM

Common commands should be handled by a deterministic local parser first:

- open/activate/quit app
- volume/mute
- play/pause/next
- close/minimize/maximize window
- open URL
- run named Shortcut

Only ambiguous or multi-step requests should go to the agent planner.

### 2.4 Risk is assigned by code, not by the model

Each action has an explicit risk class defined in BOLABOL. The model cannot mark a destructive action as safe.

### 2.5 Verification is part of execution

A command is not considered successful merely because an API call returned. Executors should verify resulting state whenever practical.

---

## 3. Lessons from FluidVoice

FluidVoice has a useful Command Mode concept: it keeps a command conversation, supports multi-step execution, distinguishes checking/executing/verifying, asks for confirmation on some destructive shell commands, and can control native applications using generated `osascript` commands.

The part worth adopting is the **agent loop and explicit verification**.

The part BOLABOL should improve is the execution boundary. Instead of making `execute_terminal_command` the universal tool, BOLABOL should expose a registry of typed native actions and reserve shell execution for a restricted fallback path.

Target distinction:

```text
FluidVoice approach:
LLM -> shell command -> zsh / osascript -> result -> LLM

BOLABOL approach:
LLM -> typed ActionPlan -> PolicyEngine -> Native Action Executor -> verifier
                                      \-> restricted shell fallback
```

---

## 4. High-level architecture

```text
                       +----------------------+
                       | GlobalHotkeyManager  |
                       +----------+-----------+
                                  |
                         Command hotkey event
                                  |
                       +----------v-----------+
                       | VoiceSessionRouter   |
                       +----------+-----------+
                                  |
                              microphone
                                  |
                       +----------v-----------+
                       | Shared ASR Pipeline  |
                       +----------+-----------+
                                  |
                         recognized command
                                  |
                +-----------------v-----------------+
                | CommandPipelineCoordinator         |
                +-----------+------------------------+
                            |
             +--------------+--------------+
             |                             |
    +--------v---------+          +--------v---------+
    | FastIntentParser |          | CommandPlanner   |
    | deterministic    |          | LLM / local LLM  |
    +--------+---------+          +--------+---------+
             |                             |
             +--------------+--------------+
                            |
                    +-------v--------+
                    | ActionPlan     |
                    +-------+--------+
                            |
                    +-------v--------+
                    | PolicyEngine   |
                    +---+---------+--+
                        |         |
                auto execute   confirmation
                        |         |
                        +----+----+
                             |
                    +--------v---------+
                    | ActionExecutor   |
                    +--------+---------+
                             |
                    +--------v---------+
                    | ActionVerifier   |
                    +--------+---------+
                             |
                    +--------v---------+
                    | Command HUD      |
                    +------------------+
```

---

## 5. Session model

The existing hotkey recording coordinator should be generalized so normal dictation and command recording cannot race each other.

Suggested model:

```swift
enum VoiceSessionKind: Sendable {
    case dictation
    case command
}

enum VoiceSessionPhase: Equatable {
    case idle
    case recording(kind: VoiceSessionKind, ownerID: UUID)
    case processing(kind: VoiceSessionKind, ownerID: UUID)
    case awaitingConfirmation(kind: VoiceSessionKind, ownerID: UUID)
}
```

Requirements:

- only one microphone session at a time;
- Command Mode cannot steal an active dictation session;
- cancellation always returns the system to a clean idle state;
- processing timeout remains separate from live recording duration;
- command execution can outlive microphone capture, but must remain associated with the same command session.

---

## 6. Hotkey integration

Extend `HotkeySettings` with a dedicated configurable command hotkey:

```swift
public var commandHotkey: String
```

Suggested default for discussion:

```text
Option+Q
```

`GlobalHotkeyManager` gets a fifth global hotkey registration and emits:

```swift
.nativeBolabolCommandHotkeyTriggered
.nativeBolabolCommandHotkeyKeyDown
.nativeBolabolCommandHotkeyKeyUp
```

The implementation should reuse the same parsing, duplicate-detection, keyboard-layout normalization, and hold/toggle semantics already used by other BOLABOL hotkeys.

---

## 7. Command context snapshot

Before or immediately after command recording starts, capture a minimal local context snapshot.

Suggested structure:

```swift
struct CommandContextSnapshot: Sendable {
    let frontmostApplication: ApplicationContext?
    let focusedWindow: WindowContext?
    let focusedElement: AccessibilityElementContext?
    let selectedText: String?
    let clipboardSummary: ClipboardContext?
    let currentScreen: ScreenContext?
    let capturedAt: Date
}
```

Possible fields:

- frontmost app name, bundle ID and PID;
- focused window title;
- selected text if accessible;
- focused element role/type;
- current screen and window geometry;
- clipboard **type/summary**, not automatically full sensitive contents;
- currently selected Finder item, when explicitly available and useful.

The context enables natural commands such as:

- "Close this window"
- "Open this in Chrome"
- "Move this file to Trash"
- "Make a reminder from this"
- "Send the selected text to Notes"

Privacy rule: capture only context needed for command resolution, keep it local where possible, and avoid dumping arbitrary screen/application contents into a cloud model.

---

## 8. Fast Intent Path

Create a deterministic `FastIntentParser` for common commands.

Example intents:

```swift
enum FastCommandIntent {
    case openApplication(name: String)
    case activateApplication(name: String)
    case quitApplication(name: String)
    case setVolume(percent: Int)
    case mute(Bool)
    case media(MediaCommand)
    case window(WindowCommand)
    case openURL(URL)
    case runShortcut(name: String)
}
```

Benefits:

- near-instant response;
- zero model cost;
- no hallucination for trivial commands;
- works fully offline;
- predictable behavior and easy tests.

The parser should return either:

```swift
.matched(ActionPlan)
```

or:

```swift
.needsPlanner
```

It should not attempt heroic natural-language understanding. Ambiguous language belongs in the LLM planner.

---

## 9. Command Planner

For complex requests, `CommandPlanner` converts natural language plus safe context into a structured `ActionPlan`.

Suggested protocol:

```swift
protocol CommandPlanning: Sendable {
    func plan(
        request: String,
        context: CommandContextSnapshot,
        capabilities: CommandCapabilityManifest
    ) async throws -> ActionPlan
}
```

The planner receives a manifest of available actions and their schemas. It must not invent arbitrary tool names.

Example plan:

```json
{
  "summary": "Open the BOLABOL project in VS Code and Terminal",
  "steps": [
    {
      "id": "1",
      "action": "resolve_project_path",
      "arguments": { "name": "BOLABOL" }
    },
    {
      "id": "2",
      "action": "open_path_in_application",
      "arguments": { "stepPath": "1", "application": "Visual Studio Code" }
    },
    {
      "id": "3",
      "action": "open_terminal_at_path",
      "arguments": { "stepPath": "1" }
    }
  ]
}
```

Planner output must be decoded into strongly typed Swift models and schema-validated before execution.

---

## 10. Action Registry

The central registry defines every capability available to the planner.

Suggested categories:

```text
ApplicationActions
WindowActions
SystemActions
MediaActions
FileActions
TextActions
AppleAppActions
ShortcutActions
BrowserActions
ShellActions (restricted fallback)
```

Suggested initial action protocol:

```swift
protocol CommandAction: Sendable {
    associatedtype Input: Codable & Sendable
    associatedtype Output: Codable & Sendable

    static var id: String { get }
    static var risk: ActionRisk { get }

    func execute(
        input: Input,
        context: CommandExecutionContext
    ) async throws -> Output

    func verify(
        input: Input,
        output: Output,
        context: CommandExecutionContext
    ) async -> VerificationResult
}
```

A type-erased wrapper can be used by the runtime registry.

---

## 11. Initial action set

A useful MVP can be built with approximately 15–20 actions.

### Applications

- `open_application`
- `activate_application`
- `quit_application`
- `open_path_in_application`

Preferred backend: `NSWorkspace` / `NSRunningApplication`.

### Windows

- `close_window`
- `minimize_window`
- `maximize_window`
- `move_window_left_half`
- `move_window_right_half`
- `center_window`

Preferred backend: Accessibility API.

### System / media

- `set_volume`
- `set_mute`
- `media_play_pause`
- `media_next`
- `media_previous`
- `take_screenshot`
- `lock_screen`

### Files

- `reveal_file`
- `open_file`
- `rename_file`
- `move_file`
- `move_to_trash`

Prefer `FileManager` / `NSWorkspace`. Permanent delete should not be part of the first MVP.

### Text

- `copy_text`
- `paste_text`
- `replace_selected_text`

Reuse existing BOLABOL Accessibility/clipboard infrastructure where possible.

### Apple apps

- `create_reminder`
- `create_calendar_event`
- `create_note`

Prefer native frameworks where feasible; use AppleScript only where needed.

### Shortcuts

- `run_shortcut`

This provides an extension bridge to user-defined automation without BOLABOL needing to implement every macOS integration itself.

---

## 12. Risk model and policy engine

Suggested risk classes:

```swift
enum ActionRisk: Int, Sendable {
    case safe
    case reversible
    case externalCommit
    case destructive
    case privileged
}
```

### Safe

Usually execute immediately:

- open/activate app;
- switch window;
- volume;
- play/pause;
- reveal file;
- open URL.

### Reversible

Execute automatically or confirm depending on settings:

- move/rename file;
- move to Trash;
- create note;
- create reminder;
- change window geometry.

### External commit

Require confirmation by default:

- send message;
- send email;
- publish/post content;
- submit form;
- make external API mutation.

### Destructive

Always require explicit confirmation:

- permanent deletion;
- clearing Trash;
- overwriting important files;
- destructive bulk operations.

### Privileged

Always require explicit confirmation and preferably remain disabled in v1:

- `sudo`;
- security/privacy settings changes;
- package installation requiring elevation;
- low-level system modifications.

The `PolicyEngine` decides whether the next step is:

```swift
.allow
.requireConfirmation(ConfirmationRequest)
.deny(reason: String)
```

Policy decisions are deterministic code, not LLM judgment.

---

## 13. Confirmation UX

Confirmation should normally happen inside the compact BOLABOL HUD, not by opening a large command window.

Examples:

```text
Move 14 files to Trash?
[Cancel] [Move]
```

```text
Send to Georgii?
"I'll be there in an hour."
[Cancel] [Send]
```

For a multi-step plan, confirmation should describe the **actual pending effect**, not merely "execute command?".

The user should be able to cancel the entire plan at any time.

---

## 14. Execution and verification

Create a central `ActionExecutor` that runs validated plan steps sequentially.

Suggested state machine:

```text
prepared
-> executing(step)
-> verifying(step)
-> completed(step)
-> next step
```

On failure:

```text
failed(step)
-> planner may receive structured failure
-> optionally propose one safe alternative
-> otherwise stop
```

Avoid infinite autonomous loops. Initial maximum should be small, for example 8 action steps per spoken command, configurable internally.

Verification examples:

- application open -> verify process exists/active;
- file moved -> verify destination exists and source no longer exists;
- move to Trash -> verify original path disappeared;
- volume changed -> read back system volume if API permits;
- window moved -> read back AX frame;
- reminder created -> verify EventKit object ID or returned object.

---

## 15. Restricted shell fallback

Shell support can exist, but should not be the default universal action.

Suggested rules:

- disabled by default in the first release, or enabled behind an Advanced toggle;
- planner must choose a dedicated `run_shell_command` action;
- risk is at least `.externalCommit`, often `.destructive` or `.privileged` depending on parsed command;
- command should run through a restricted executor with timeout, bounded output, sanitized environment, and explicit working directory;
- no automatic `sudo`;
- shell output is returned as structured data;
- commands affecting filesystem/system state require confirmation unless known-safe read-only operations.

Long-term, shell capability may be exposed as an advanced power-user feature, not as the foundation of Command Mode.

---

## 16. Command HUD states

Suggested HUD mode indicator:

```text
COMMAND
```

or a compact symbol such as `⌘`, `⚡`, or another BOLABOL-specific mark.

States:

```text
Listening…
Understanding…
Planning…
Opening Safari…
Waiting for confirmation…
Verifying…
Done
Failed
```

The HUD should show only concise status. Detailed history can live in an optional Command History panel later.

The visual language should remain consistent with the existing BOLABOL capsule rather than introducing a large separate overlay.

---

## 17. Conversation and follow-up commands

The first implementation can be single-shot. Architecture should nevertheless allow an optional `CommandConversationSession` later.

Example:

```text
User: Open the BOLABOL repository.
User: Now open it in Terminal.
User: And start VS Code too.
```

The second and third requests should be able to refer to resolved entities from the previous command session without re-reading the entire computer state.

Suggested bounded memory:

- recent user command;
- resolved files/apps/entities;
- recent successful action outputs;
- current context snapshot;
- expiration after inactivity.

Do not reuse general dictation history as command-agent memory.

---

## 18. Voice Skills

A later feature can turn successful command plans into reusable named automations.

Example:

```text
Voice Skill: "Start working"

1. Open VS Code
2. Open BOLABOL repository
3. Open Terminal at repository
4. Run a named Apple Shortcut
5. Start Focus mode
```

Creation flow:

```text
spoken command -> successful ActionPlan -> "Save as Voice Skill…"
```

A skill stores typed actions, not arbitrary LLM prose. That makes it deterministic and editable.

This can eventually become a major differentiator from ordinary AI dictation tools.

---

## 19. Suggested source layout

```text
Sources/NativeBolabol/
  Commands/
    CommandPipelineCoordinator.swift
    CommandContextSnapshot.swift
    FastIntentParser.swift
    CommandPlanner.swift
    CommandCapabilityManifest.swift
    ActionPlan.swift
    ActionRegistry.swift
    ActionExecutor.swift
    ActionVerifier.swift
    CommandPolicyEngine.swift
    CommandConfirmationCoordinator.swift

    Actions/
      ApplicationActions.swift
      WindowActions.swift
      SystemActions.swift
      MediaActions.swift
      FileActions.swift
      TextActions.swift
      AppleAppActions.swift
      ShortcutActions.swift
      ShellActions.swift

  Views/
    HUD/
      CommandHUDState.swift
      CommandHUDControls.swift
```

Core pure models/policies that do not require AppKit should live in `NativeBolabolCore` where practical so they are easy to unit test.

---

## 20. Testing strategy

### Unit tests

- hotkey settings encoding/decoding and duplicate detection;
- deterministic FastIntentParser;
- ActionPlan schema decoding/validation;
- PolicyEngine risk decisions;
- confirmation requirements;
- path canonicalization and filesystem scope checks;
- action registry capability lookup;
- context minimization/redaction;
- conversation/session state machine;
- cancellation and timeout behavior.

### Executor tests

Use protocol-backed system adapters and mocks rather than controlling the developer's real Mac in unit tests.

Examples:

- `MockWorkspaceAdapter`
- `MockAccessibilityAdapter`
- `MockFileSystemAdapter`
- `MockEventKitAdapter`
- `MockShortcutAdapter`

### Integration tests

A small opt-in macOS integration suite can verify:

- opening a harmless test app;
- manipulating a dedicated test window;
- moving a temporary file to Trash/test directory;
- running a dedicated test Shortcut if present.

Never make destructive integration tests the default CI path.

---

## 21. Observability

Log structured command events without storing sensitive user utterances by default.

Useful fields:

```text
session id
planner used: fast / LLM
plan step count
action id
risk class
confirmation requested/accepted/denied
execution duration
verification result
error category
```

Avoid logging full selected text, clipboard contents, message bodies, passwords, tokens, or arbitrary model prompts unless explicit debug logging is enabled.

---

## 22. Implementation phases

### Phase 1 — Command foundation

- configurable command hotkey;
- command session type;
- dedicated HUD state;
- shared ASR routing into `CommandPipelineCoordinator`;
- `FastIntentParser`;
- ActionPlan models;
- ActionRegistry;
- PolicyEngine;
- confirmation HUD.

### Phase 2 — Native MVP actions

Implement approximately 15–20 actions:

- apps;
- windows;
- volume/media;
- file reveal/open/move-to-trash;
- clipboard/text;
- reminders/notes;
- Apple Shortcuts.

No unrestricted shell required.

### Phase 3 — LLM planner

- structured tool/action schema;
- local or cloud planner selection;
- multi-step ActionPlans;
- bounded replanning after failures;
- verification loop;
- concise command history.

### Phase 4 — Power-user layer

- restricted shell fallback;
- follow-up command sessions;
- Voice Skills;
- editable saved automations;
- richer application-specific actions.

---

## 23. MVP acceptance criteria

Command Mode v1 is ready when all of the following are true:

- a dedicated configurable global hotkey starts command recording;
- normal dictation and command sessions cannot conflict;
- recognized command text is never pasted into the active app by accident;
- common commands can execute without an LLM;
- complex commands can be converted to schema-validated typed actions;
- the LLM cannot directly bypass the action registry in normal mode;
- every action has a deterministic risk class;
- destructive/external effects require confirmation according to policy;
- actions are verified when practical;
- Command HUD displays understandable state and confirmations;
- cancellation is safe at every stage;
- tests cover planning validation, policy decisions, session races, and executor failures;
- no unrelated dictation/translation/polishing behavior regresses.

---

## 24. Recommended first milestone

The first genuinely useful slice should support these spoken commands end-to-end:

```text
Open Safari.
Open Telegram.
Set volume to 30 percent.
Mute the Mac.
Close this window.
Move this window to the right half.
Reveal this file in Finder.
Move this file to Trash.
Create a reminder tomorrow morning to call Georgii.
Create a note called BOLABOL Idea with this selected text.
Run the Shortcut "Work Mode".
```

If these commands feel fast, predictable, safe, and native, the foundation is correct. Multi-step agent behavior can then be layered on without turning the core of BOLABOL into a terminal roulette wheel.

---

## 25. Final architecture decision

The recommended direction is:

> **BOLABOL Command should be a native macOS action engine assisted by an agent — not a terminal agent that happens to control macOS.**

That distinction should guide the implementation.
