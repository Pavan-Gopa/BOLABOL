# Graph Context Tooling Evaluation

Evaluation date: 2026-08-05

Decision status: Research complete; workflow change requires a measured pilot.

## 1. Executive Decision

Choose **Option D: native-first retrieval with Graphify as a scoped fallback**.
Do not adopt Graft for Bolabol, and do not add Graphify and Graft together.

The decision is based on the current Swift/macOS repository, not on generic
vendor claims:

- Graft `0.8.2` has no structural Swift parser. Its zero-cost graph indexed zero
  of Bolabol's 188 Swift files in a disposable experiment.
- Graphify `0.9.33` has real Swift tree-sitter extraction and can provide useful
  `explain` and exact-symbol `path` results. Its broad Bolabol queries were noisy,
  truncated, and inconsistent enough that source reads remained mandatory.
- Native `Glob`, `Grep`, and targeted `Read` found the expected S8-S11 product,
  test, and contract paths directly without a generated graph or rebuild.
- Neither tool has produced trustworthy evidence that it reduces total model
  tokens for this Swift repository. Tool-output estimates are not session token
  telemetry.

This is not a recommendation to delete Graphify immediately. Keep it available
locally during a 5-10-turn A/B pilot, remove the unconditional Graphify-first
rule only if correctness is preserved, and retain a one-command rollback.

## 2. Question, Scope, and Constraints

The evaluation asks whether Bolabol should:

- **Option A:** keep the current Graphify-first and frequent rebuild workflow;
- **Option B:** replace Graphify with NanoNets Graft;
- **Option C:** run Graphify and Graft together; or
- **Option D:** use native repository tools first and invoke Graphify only for
  specific cross-file questions.

The relevant workload is a local Swift/SwiftUI/macOS application with fresh,
stateless worker sessions. Typical work includes exact symbol lookup, request
flow tracing, architecture/ADR verification, regression-test discovery, diff
review, and targeted source edits.

Research constraints were intentionally strict:

- no product or test edits;
- no package installation, global configuration, hooks, MCP registration, or
  agent wiring;
- no `graft init`, `graphify install`, credentials, or remote LLM calls over
  private Bolabol source;
- Graft pinned to published npm `@nanonets/graft@0.8.2` and run only in a
  disposable snapshot;
- Graphify update tested only in a disposable snapshot;
- Graft deep mode was not run because it sends source-derived content to a
  configured model provider;
- no commit, tag, or push.

## 3. Evidence Standard and Pinned Revisions

Conclusions are classified as follows:

| Evidence class | Meaning |
|---|---|
| Observed | Measured locally against the Bolabol working tree or a disposable copy |
| Source-confirmed | Verified in pinned upstream implementation or package metadata |
| Vendor claim | Reported by the project author; not independently reproduced here |
| Unknown | The current tools or host did not expose a defensible measurement |

Pinned revisions:

| Tool | Evaluated revision | Publication state |
|---|---|---|
| Graphify | `graphifyy 0.9.33`, commit `4e7e6b1f7e0df10ed07d5f28f9189bbde42940f1` | PyPI/release published 2026-08-05 |
| Installed Graphify skill | `.graphify_version` = `0.9.20` | Older than the CLI |
| Graft | npm `@nanonets/graft 0.8.2`, commit `d4ec9d7c7ba321d6cde5e3ec892739126930a69b` | npm published 2026-07-30 |
| Graft upstream main | commit `740faf8cb10cd34a66ecaf115f9b8405f94171d3` | Observed 2026-08-05; not the tested npm release |

The version mismatch between Graphify's installed skill and CLI matters because
the skill is a large, model-visible instruction surface and documents behavior
that can drift independently from the executable. The report does not assume
that unreleased Graft main behavior exists in npm `0.8.2`.

## 4. Bolabol Baseline

The current Graphify corpus is broad and mixes product code, tests, workflow
documents, generated output, scratch files, and user data:

| Item | Observed value |
|---|---:|
| Manifest files | 322 |
| `Sources/**` | 134 |
| `Tests/**` | 62 |
| `docs/**` | 34 |
| `script/**` | 34 |
| `AI_Workflow_Kit/**` | 22 |
| `UserData/**` | 11 |
| `graphify-out/**` | 5 |
| `scratch/**` | 3 |
| Graph nodes / edges | 5,727 / 12,952 |
| `graphify-out` disk use | about 32 MB |
| `graph.json` size | 7,447,941 bytes |

`GRAPH_REPORT.md` is not a reliable freshness indicator. It still names
`/Users/pavan/Documents/AI Projects/Blaboom`, reports 243 nodes / 476 edges, and
was modified on 2026-08-01. The actual `graph.json` was modified on 2026-08-05
and contains fresh S11 symbols. The current output is therefore mixed-age: the
code graph contains recent material while the plain-language report is stale.

The graph also indexes some of its own generated memory. In the ADR query, a
historical Blaboom query-memory file became a seed. This self-indexing and the
inclusion of `scratch` and `UserData` broaden retrieval without helping most
product tasks and increase the privacy and relevance surface.

## 5. Current Graphify Workflow Cost

The current contract requires Graphify before large exploration, when a new
Orchestrator starts, after each Coder handoff before Reviewer, and again after a
green POST cycle. The rebuild script executes:

```bash
graphify update "$BOLABOL_ROOT" --no-cluster
```

A disposable incremental update completed in 3.59 seconds, processed 7 uncached
files, and changed the copied graph from 5,727 / 12,952 to 5,728 / 12,958. It
retained about 32 MB of generated data and created a dated backup of four curated
files. It did not make the stale semantic report current.

This cost must be separated correctly:

- local update CPU and disk I/O are operational cost, not model tokens;
- query output becomes model-visible tool input and can consume context;
- generated-file diffs can invalidate prompt caches or consume review attention,
  but no exact cache-charge telemetry was available;
- semantic extraction of documents can consume model tokens depending on the
  Graphify execution path, while code AST extraction is local and deterministic;
- a no-change rebuild may be unnecessary latency, but the current workflow does
  not literally require a rebuild on every status-only message.

The generated graph is also a repository-maintenance burden. Git tracks 297
`graphify-out` files, including 278 cache files and 17,838,112 tracked bytes. The
current graph-only diff spans four files with 9,544 insertions and 2,895
deletions; `graph.json` alone contributes about 1.08 MB of raw diff. The earlier
cache migration commit `845a9ed` changed 954 files, 950 of them AST cache files.

## 6. Graphify Swift and SwiftUI Capability

Graphify `0.9.33` has genuine structural Swift support:

- its package declares `tree-sitter-swift>=0.7,<0.9`;
- its Swift extractor recognizes class-like declarations, protocols,
  conformances, extensions, imports, functions, and computed Swift properties;
- upstream tests cover SwiftUI-style computed properties and selected
  cross-file relationships;
- local output resolves current symbols such as `TranscriptionSessionResolver`,
  `TranscriptionSessionPlan`, and methods in the S11 request path.

That is useful but not equivalent to Swift compiler semantics. Tree-sitter does
not type-check the program. Property wrappers, generated SwiftUI behavior,
protocol witness selection, overload resolution, extension dispatch, actor
isolation, async execution, and dynamic dispatch can be incomplete or
ambiguous. Every architectural conclusion still needs verification in the
actual Swift source and, where behavior matters, tests/build evidence.

Useful local results:

- `graphify explain "TranscriptionSessionResolver"` returned the exact symbol
  and methods in 0.29 seconds. Its 1,946-byte output is roughly 487 tokens using
  a simple 4-bytes-per-token estimate.
- `graphify path "ContentView" "RecordingTranscriptionWorkflow"` found a useful
  two-hop route through `.transcribeForTranslation()`.
- a path between `TranscriptionModelStore` and `TranscriptionEngineStore`
  produced a weak architectural connection through shared `ObservableObject`
  conformance. A shortest graph path is therefore not automatically a causal or
  ownership path.

Graphify is strongest here when seeded with exact symbols and used for a narrow
`explain` or `path`. It is weakest when a broad natural-language query produces
generic seeds and a depth-2 neighborhood.

## 7. Graft Swift and SwiftUI Capability

Graft `0.8.2` is structurally unsuitable for Bolabol.

The pinned source defines:

```typescript
export type Language = "typescript" | "tsx" | "python" | "go";
```

`languageOf()` recognizes JavaScript/TypeScript, Python, and Go extensions only.
`listSourceFiles()` drops every path for which `languageOf()` returns `null`.
The package dependencies include TypeScript, Python, and Go tree-sitter grammars
but no Swift grammar. Consequently `.swift` files cannot produce file nodes,
symbols, signatures, call edges, callers, skeletons, maps, or indexed grep hits
in the normal zero-cost structural graph.

Graft's deep context builder lists `.swift` among generic code extensions, but
that path reads each file and asks a configured LLM to write prose summaries,
then asks the LLM to synthesize concept nodes. It clips a file at 24,000
characters and is not a Swift AST parser. Deep mode therefore cannot repair the
missing structural Swift graph. It changes the product into remote or
provider-backed summarization with additional cost, privacy, and correctness
questions.

No pinned Graft source or benchmark demonstrates SwiftUI property wrappers,
extensions, protocols, actors, async flows, or Swift cross-file call resolution.
This is a disqualifying capability gap, not a tuning problem.

## 8. Disposable Graft Experiment

A code-only Bolabol snapshot was created outside the repository. It excluded
`.git`, `graphify-out`, `.build`, `dist`, `scratch`, `UserData`, and model assets.
No agent integration, hook, MCP registration, or deep LLM pass was used.

| Measurement | Observed result |
|---|---:|
| Snapshot size | about 14 MB |
| Swift files | 188 |
| Graft-supported source files | 0 |
| Build time | 1.32 seconds |
| Nodes / edges / cards | 0 / 0 / 0 |
| Generated data | about 20 KB |
| `ask` | empty, 1.22 seconds |
| `map` | 0 files / 0 symbols / 0 edges, 1.23 seconds |
| `skeleton` | no definitions indexed, 1.40 seconds |
| `callers` | symbol not found, 1.26 seconds |
| `grep` | 0 indexed files / 0 hits, 0.81 seconds |
| `check` | reported the empty graph fresh, 1.30 seconds |

The build changed only the disposable snapshot's ignore metadata: it added
`graft/` to `.gitignore` and created `.ignore` rules that make generated cards
searchable. A fresh empty graph being reported as healthy is expected from
freshness logic but proves nothing about repository coverage.

Published `0.8.2` walks the filesystem, skips dot directories, selected build
directories, and files above 1 MB, but does not use Git's ignore rules for source
selection. Upstream main commit `740faf8...` adds `git ls-files` based ignore
behavior. That improvement is unreleased relative to the tested package and
does not add Swift parsing.

## 9. Retrieval Evaluation Method

Eight representative S8-S11 questions were evaluated against the existing
Graphify graph. They covered request propagation, unknown entry-point lookup,
routing implementation/tests, selected-model-to-engine wiring, Canary 1B
download behavior, S11 regression coverage, ContentView-to-workflow flow, and
ADR-020 scope.

Each broad query was run twice:

- Graphify default budget: approximately 2,000 renderer tokens;
- a task-sized arm using budgets `600, 600, 1000, 1000, 1000, 1500, 1500,
  1500`.

Expected paths were established from `STATE.yaml`, ADR-020, exact native search,
and targeted source reads. Precision and recall were hand-scored at the expected
file/path level. This small purposive sample is a routing experiment, not a
general benchmark. It is sufficient to identify failure modes but not to claim
universal percentages.

Output-token estimates use output bytes divided by four. Graphify's own budget
renderer uses an approximate three characters per token. Neither value is an
exact tokenizer count, and neither measures the rest of the agent session.

Native spot checks used exact `Glob`, `Grep`, and targeted `Read` operations:

- `TranscriptionRequest|forcedLanguageCode` found request construction, routing,
  workflow, and engine paths;
- `TranscriptionSessionResolver|TranscriptionLanguageRouter` found the routing
  implementation and focused tests;
- `activeModelID|activeEngine|makeSession` found the model and engine stores,
  though the generic `activeEngine` term needed path scoping to remove polishing
  noise;
- exact test globs returned all eight S8/S9/S11 regression files;
- targeted reads confirmed the immutable session plan and all re-transcription
  entry points.

## 10. Retrieval Results

| Task | Default precision / recall | Budget precision / recall |
|---|---:|---:|
| Q1 request propagation | 20.0% / 100.0% | 22.2% / 50.0% |
| Q2 unknown transcription entry path | 0.0% / 0.0% | 0.0% / 0.0% |
| Q3 routing implementation and tests | 81.8% / 100.0% | 50.0% / 22.2% |
| Q4 selected model and engine wiring | 0.0% / 0.0% | 0.0% / 0.0% |
| Q5 Canary 1B download flow | 16.7% / 42.9% | 20.0% / 42.9% |
| Q6 S11 regression coverage | 35.7% / 62.5% | 35.7% / 62.5% |
| Q7 ContentView to workflow | 16.0% / 100.0% | 18.2% / 100.0% |
| Q8 ADR-020 scope | 25.0% / 4.3% | 25.0% / 4.3% |
| **Macro average** | **24.4% / 51.2%** | **21.4% / 35.2%** |

Default output averaged about 1,714 estimated tool-output tokens. The budget arm
averaged about 1,036, a reduction of roughly 40%, but macro recall fell from
51.2% to 35.2%. Every arm was truncated before edges were displayed. A smaller
budget reduced context volume but could not repair poor seed selection and in
some cases removed relevant files that appeared later in the traversal.

The historical workflow shows the same pattern at larger scale. Recorded worker
queries returned 405, 336, 323, and 382 nodes, after which workers still opened
`STATE.yaml`, ADRs, `FEEDBACK.md`, and target source/test files. No current S7-S11
worker result is labelled useful or dead-end through Graphify's feedback
mechanism, so the repository has no closed-loop evidence that these mandatory
queries improved outcomes.

## 11. Token, Cost, and Latency Analysis

The defensible finding is **no proven end-to-end token saving for Bolabol**.

What is measurable:

- broad Graphify query output is model-visible and averaged about 1,714
  estimated tokens at default settings in this sample;
- task budgets reduced that output to about 1,036 estimated tokens but also
  reduced recall;
- `explain` on an exact symbol was much smaller and useful;
- each Graphify CLI command emitted about 285 bytes of repeated warning text in
  this environment;
- the installed Graphify skill is 38,427 bytes, with `query.md` at 13,456 bytes
  and `update.md` at 9,143 bytes. Host loading and prompt-cache behavior were not
  observable precisely;
- local structural graph builds do not use model credits, but they still cost
  CPU, disk, latency, and generated-file churn.

What is not measurable from this run:

- exact model input/output tokens per worker turn;
- prompt-cache reads, writes, or invalidation caused by generated graph changes;
- native tool output token counts reported by the host;
- the counterfactual number of source reads an agent would have made without a
  graph;
- correctness-adjusted dollars per Bolabol task.

Graphify's official code benchmark is a vendor-owned harness over six questions
on the approximately 1M-line Python ERPNext repository. It reports key-fact
coverage rising from 70.8% to 82.0% with a fixed Claude Opus 4.8 agent, at most
14 turns, baseline grep/read/list tools, and one Graphify tool, with about 140K
tokens per query. This is evidence that graph retrieval can help some large
Python tasks, but it is not evidence of lower Swift session tokens and is not an
independent benchmark.

Graft's pinned README reports a 162-run author-owned study using Claude Sonnet 5
and an Opus 4.8 judge over Graft itself and a Node/Express auth service, three
trials, and cold/push/pull variants. The headline comparison reports uncached
input tokens falling from 8,070 to 4,650 (-42%), tool calls from 4.2 to 2.3
(-46%), latency from 39.8 seconds to 15.8 (-60%), and equal 93% correctness. The
popular-repo section reports PocketBase Go results, including 5/5 implementation
tasks touching the maintainer files. None of these corpora is Swift, and the
tested context injection/tool setup is not Bolabol's OpenCode workflow. The
claims should not be transferred to this repository.

## 12. Freshness, Determinism, and Repository Hygiene

Graphify's code extraction and query traversal are deterministic local
operations, but the complete generated product is not one freshness unit:

- `graph.json` can contain current symbols while `GRAPH_REPORT.md` is old;
- broad semantic/docs content can have a different extraction age from code;
- the current update script uses `--no-cluster`, so it should not be treated as
  regenerating all analysis/report surfaces;
- query logging is opt-in and was not enabled, leaving no current retrieval
  outcome ledger;
- Graphify's deterministic BFS depth is fixed at two in the observed query path,
  so budget affects rendering rather than which neighborhood is traversed.

Generated artifacts should not dominate source review. The present repository
tracks mutable AST cache and a multi-megabyte graph, while ignore rules only
cover dated backup directories. If Graphify remains, the preferred eventual
shape is a local regenerable cache excluded from normal diffs, with any curated
human-authored decision/report content stored separately. Removing already
tracked artifacts is a distinct migration and must not be bundled into a product
change.

Graft's structural graph is also deterministic for supported languages and is
designed as a local cache in its current quick-start flow. That operational
design does not compensate for zero Swift coverage.

## 13. Correctness, Privacy, and Security

Correctness controls:

- graph nodes and paths are navigation hints, never source-of-truth evidence;
- cite and read the exact Swift source before making a behavior claim;
- use native exhaustive search for all occurrences, forbidden-source checks,
  localization key coverage, target-file verification, and review scope;
- rely on Swift tests/builds for type, protocol, actor, and runtime semantics;
- reject a graph path that connects only through generic framework protocols or
  other semantically weak hubs.

Privacy controls:

- Graphify's code AST path is local, but document semantic extraction can use a
  host model or configured Gemini backend;
- the current manifest includes `UserData`, `scratch`, workflow logs, and
  generated memories. Future builds should explicitly scope or exclude them;
- Graft deep mode sends clipped source content and source-derived summaries to
  the selected provider. It was not run and should not be enabled for Bolabol
  without a separate privacy review and approved provider policy;
- do not place secrets, model assets, private user content, or credentials in a
  graph corpus;
- leave Graphify query logging disabled unless a reviewed retention policy
  defines what may be written.

No external API call containing Bolabol source was made during this evaluation.
Official GitHub, PyPI, and npm material was read remotely; local source and
snapshots remained on this machine.

## 14. Option Scorecard and Recommendation

| Option | Swift structural support | Bolabol retrieval evidence | Operational cost | Privacy surface | Decision |
|---|---|---|---|---|---|
| A. Graphify-first | Yes, syntactic | Mixed; narrow exact-symbol useful, broad queries noisy | Rebuilds, context output, 32 MB cache, large diffs | Current corpus too broad | Do not keep as unconditional policy |
| B. Graft-only | **No** in `0.8.2` | Zero indexed Swift files | Small empty build; deep mode adds LLM cost | Deep mode sends source to provider | **Disqualified** |
| C. Graphify + Graft | Only Graphify contributes Swift structure | No incremental Swift benefit from Graft | Highest complexity and duplicate cache/instructions | Largest surface | Reject |
| D. Native-first + Graphify fallback | Native text/source plus Graphify syntactic fallback | Native found all expected paths; Graphify retains narrow value | Lowest default overhead; fallback is budgeted | Smallest if corpus is scoped | **Recommend** |

Option D best matches the actual task distribution. Most worker prompts already
contain step IDs, target files, symbols, and acceptance contracts. These are
high-information lexical anchors for native search. A persistent graph is most
valuable only when the path is genuinely unknown or a relationship spans files
that exact search cannot identify efficiently.

## 15. Deterministic Native-First Routing Policy

Use the following route in order. Stop as soon as the task is grounded in exact
source paths.

| Question shape | First tool | Graphify fallback |
|---|---|---|
| Known file or path pattern | `Glob`, then targeted `Read` | None |
| Known symbol, string, model id, setting key, or error | scoped `Grep`, then `Read` | `explain` only if ownership remains unclear |
| Exhaustive occurrences, prohibited references, localization, scope review | scoped `Grep` | Never substitute graph retrieval |
| Contract or workflow status | read `STATE.yaml`, ADR/plan, and latest handoff directly | None |
| Exact symbol relationship with both endpoints known | native search around definitions/call sites | `path`, then verify every hop in source |
| Unknown subsystem or cross-file ownership | narrow native terms first | `query --budget 600`; raise to 1000 only when the first result contains useful seeds |
| Large architecture question with weak vocabulary | inspect repo map/docs and derive identifiers | one budgeted query, then exact source reads |

Additional rules:

1. Do not run a broad default-budget query merely to satisfy a footer.
2. Do not report node count as evidence of usefulness.
3. Prefer `explain` or `path` over broad `query` when exact symbols are known.
4. Treat truncation before edges as a signal to narrow, not automatically to
   raise the budget.
5. Never use Graphify output as the only evidence for Swift behavior or review
   completeness.
6. Rebuild only at a defined handoff boundary when a fallback query needs the
   latest changed source. Do not rebuild for status-only turns.
7. Record why fallback was used and whether it found a path that native search
   had not already found.

## 16. Pilot, Migration, Rollback, Risks, and Sources

### Reversible 5-10-turn pilot

Run two arms over comparable real worker turns without changing product scope:

| Arm | Retrieval policy |
|---|---|
| Control | Current Graphify-first workflow and current rebuild boundaries |
| Candidate | Section 15 native-first routing with budgeted Graphify fallback |

Capture per turn:

- task type and whether exact symbols/files were already supplied;
- wall time to the first correct source path and to a completed answer/handoff;
- native and Graphify tool calls;
- Graphify output bytes, budget, truncation, and fallback reason;
- source files read after retrieval;
- host-reported model input/output/cache tokens when available;
- reviewer/tester correctness, missed files, rework, and hallucinated links;
- rebuild time and generated diff bytes.

Do not claim token savings unless host telemetry is available for both arms.
Adopt Option D only if there is no correctness regression, no increase in missed
target files or review rework, and median time-to-grounding is no worse. A useful
secondary target is at least 50% less Graphify tool-output volume across the
pilot. Any critical missed dependency or repeated native search failure pauses
the rollout and returns that task class to Graphify-first while routing is
refined.

### Migration after a successful pilot

1. Change `TEAM_CONTRACT.md`, `ORCHESTRATOR.md`, and worker kick footers from
   unconditional Graphify-first wording to the routing table above.
2. Keep the existing Graphify command and rebuild script available as fallback.
3. Align the Graphify skill and CLI versions before depending on documented
   flags; pin the accepted version in one workflow location.
4. Scope future graph builds to approved code/tests/docs and exclude `UserData`,
   `scratch`, model assets, and `graphify-out` itself.
5. In a separate repository-hygiene change, decide whether generated graph/cache
   files become local ignored artifacts. Review the deletion of the 297 tracked
   files explicitly rather than hiding it inside feature work.
6. Do not install or integrate Graft unless a future published release adds and
   demonstrates structural Swift support; re-evaluate from source at that time.

### Rollback

Rollback is policy-only: restore the current Graphify-first footer and existing
rebuild boundaries, run `AI_Workflow_Kit/script/graphify_rebuild.sh`, and resume
queries against the regenerated graph. No product schema, persisted user state,
or package dependency changes are involved.

### Residual risks

- Native lexical search can miss a relationship expressed only through generic
  protocol/type behavior; compiler tests and targeted Graphify fallback mitigate
  this.
- Graphify can produce stale, noisy, or semantically weak paths; exact source
  verification mitigates this.
- A 5-10-turn pilot is small and task mix can bias results; retain raw logs and
  avoid broad percentage claims.
- Removing tracked graph artifacts can disrupt workers that assume the files
  exist; make that a separately reviewed migration with the rollback above.
- Future Graphify or Graft releases can change the conclusion. Re-test pinned
  published code rather than relying on README headlines.

### Sources

Official sources accessed 2026-08-05:

- Graphify repository at the evaluated commit:
  <https://github.com/Graphify-Labs/graphify/tree/4e7e6b1f7e0df10ed07d5f28f9189bbde42940f1>
- Graphify package metadata and Swift dependency:
  <https://github.com/Graphify-Labs/graphify/blob/4e7e6b1f7e0df10ed07d5f28f9189bbde42940f1/pyproject.toml>
- Graphify vendor benchmark methodology:
  <https://github.com/Graphify-Labs/graphify/blob/4e7e6b1f7e0df10ed07d5f28f9189bbde42940f1/BENCHMARKS.md>
- Graphify PyPI release:
  <https://pypi.org/project/graphifyy/0.9.33/>
- Graft repository at published `0.8.2`:
  <https://github.com/NanoNets/Graft/tree/d4ec9d7c7ba321d6cde5e3ec892739126930a69b>
- Graft structural language dispatch:
  <https://github.com/NanoNets/Graft/blob/d4ec9d7c7ba321d6cde5e3ec892739126930a69b/src/graph/extract.ts>
- Graft source-file filtering:
  <https://github.com/NanoNets/Graft/blob/d4ec9d7c7ba321d6cde5e3ec892739126930a69b/src/graph/source-files.ts>
- Graft deep extension list and LLM pipeline:
  <https://github.com/NanoNets/Graft/blob/d4ec9d7c7ba321d6cde5e3ec892739126930a69b/src/context/build.ts>
- Graft package grammars and version:
  <https://github.com/NanoNets/Graft/blob/d4ec9d7c7ba321d6cde5e3ec892739126930a69b/package.json>
- Graft benchmark description:
  <https://github.com/NanoNets/Graft/blob/d4ec9d7c7ba321d6cde5e3ec892739126930a69b/README.md#benchmark>
- Graft npm release:
  <https://www.npmjs.com/package/@nanonets/graft>

Local evidence:

- `AI_Workflow_Kit/docs/AI/ORCHESTRATOR.md`
- `AI_Workflow_Kit/docs/AI/TEAM_CONTRACT.md`
- `AI_Workflow_Kit/docs/AI/STATE.yaml`
- `AI_Workflow_Kit/docs/DECISIONS.md` (ADR-020)
- `AI_Workflow_Kit/docs/AI/FEEDBACK.md`
- `AI_Workflow_Kit/script/graphify_rebuild.sh`
- `graphify-out/GRAPH_REPORT.md`
- `graphify-out/manifest.json`
- `graphify-out/graph.json`

The disposable experiment directories and raw temporary benchmark outputs were
removed after the report was verified. The measurements above are retained here
as the durable evidence record.
