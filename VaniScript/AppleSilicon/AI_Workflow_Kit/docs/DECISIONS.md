# ADR Log

> Architecture Decision Records. Format: **ADR-NNN — Title**.  
> Architect proposes; Human / Orchestrator marks **Accepted** / **Rejected** / **Superseded**.

---

## Template

```markdown
## ADR-001 — Title

**Status:** Proposed | Accepted | Rejected | Superseded by ADR-00N  
**Date:** YYYY-MM-DD  
**Decision:** …
**Rationale:** …
**Consequences:** …
```

---

## Records

## ADR-001 — Automatic batch versus targeted chunk retranslation

**Status:** Accepted  
**Date:** 2026-08-14  
**Decision:** Document translation has two explicit execution modes. When the
session's Auto-approve option is enabled, the initial translation queue processes
pending chunks sequentially through the end and auto-approves only locally valid
results. `Retranslate Current` always processes exactly the selected chunk,
never starts the next chunk, and leaves the replacement pending manual
`Approve & Next`, regardless of the session's Auto-approve setting. A failed or
invalid targeted replacement preserves the last valid translation.  
**Rationale:** Batch translation needs unattended completion; editorial
correction needs isolated, user-controlled replacement without restarting
already completed work.  
**Consequences:** Coordinator requests carry an explicit batch/targeted intent;
queue chaining is forbidden for targeted requests; approval disposition and
autosave are persisted after every successful chunk.

---

## ADR-002 — Adopt editorial workspace architecture for Document Review

**Status:** Accepted  
**Date:** 2026-08-15  
**Decision:** Adopt `docs/PRD-Editorial-Review-Workspace.md` as the source of
truth for turning Document Review into an editorial workspace. Map its slices
E1–E6 to steps S14–S19. `DocumentState` remains the single canonical document
source; all programmatic edits (formatting, AI selection replacement, Replace
Everywhere) flow through one pure rich-text mutation engine; the existing
AppKit `NSTextView` editor is extended, never replaced; AI never supplies
trusted formatting or structural metadata; Replace Everywhere is one atomic
transaction; DOCX export must reflect editor overrides including explicit
trait removal.  
**Rationale:** The PRD was verified against local source before adoption: the
private editor attributes, `RichTextSpan`/`InlineTrait` model, separate
source/translated update paths, `editingProviderID`, and Unicode-aware
glossary matching all already exist. The architecture extends proven contracts
instead of creating a second editor or a chunk-based document mutation path —
the failure mode behind the earlier S13 corruption findings.  
**Consequences:** S13 is parked by Human instruction with candidate 24 still
awaiting acceptance on resume. Media search/replace and glossary paths stay
untouched. Each slice ships with its PRD §26 test layer.

---

## ADR-003 — Replace custom formatting commands with AI selection retranslation in S14

**Status:** Accepted
**Date:** 2026-08-15
**Decision:** Drop the custom formatting command layer from S14 (Formatting
submenu, ⌘B/⌘I/⌘U trait shortcuts, Clear Manual Formatting). Standard macOS
right-click/system formatting already provides full formatting in the Document
Review editor. Redefine S14 to deliver the single editorial command the Human
requires: `Retranslate Selection with AI…` in the translated pane — AI
retranslation of only the selected phrase with trusted structural source
context (PRD §10, slice E4). The selection bridge, the pure
`DocumentRichTextMutation` replace path, and paste sanitization remain as the
canonical mutation foundation for this command and later slices.
**Rationale:** Human acceptance testing of candidate 02 showed the custom
formatting items inactive and judged them unnecessary because the system
formatting menu already works. AI selection retranslation is the feature the
editorial workflow actually needs now.
**Consequences:** Slice E4 moves from S17 into S14; the S17 card carries a
re-scope note. Custom formatting UI is removed; the pure mutation engine's
replace path is retained and consumed by the AI replacement. PRD §7
formatting-command requirements are superseded for v1 by system formatting.

## ADR-004 — TranslatedBlock.sourceHash stores the source block hash, not the plan hash

**Status:** Accepted
**Date:** 2026-08-15
**Decision:** `DocumentTranslationCoordinator.commit` must store the source
block's `sourceHash` (the block text hash) into each committed
`TranslatedBlock.sourceHash`, matching the manual edit path
(`WorkflowStore.updateCurrentDocumentTranslated`). The composite
`DocumentChunkPlan.sourceHash` stays in `ChunkQualityReport` and plan
identity, but is no longer written into per-block translations.
**Rationale:** PRD §9.1 defines freshness as
`fresh ⇔ translated.sourceHash == sourceBlock.sourceHash`. The plan hash is a
composite of block fingerprints, slices, text, profile, modelID, and
promptVersion, so it never equals any single block's text hash. Storing it
would mark every AI-translated block permanently stale and make the S15
freshness feature unusable. The round-trip and package export tests already
construct translations with `sourceHash: block.sourceHash`, confirming the
block-hash convention; the AI commit path was the outlier. Export writers
compare `originalAsset.sha256` (file bytes), not `TranslatedBlock.sourceHash`,
so this change does not affect export validation.
**Consequences:** One-line fix in `DocumentTranslationCoordinator.commit`
(authorized as an S15 dependency; the file joins the S15 target list).
Existing AI-translated projects keep their stored plan hashes until the next
retranslation or manual edit of a block; such blocks correctly report stale
until refreshed, which is the honest behavior.

## ADR-005 — Migrate legacy plan-hash translations to the block hash on load

**Status:** Accepted
**Date:** 2026-08-15
**Decision:** When a project session is loaded/normalized, any
`TranslatedBlock` whose `sourceHash` equals the `sourceHash` of a
`DocumentChunkPlan` containing its source block (the pre-ADR-004 legacy
convention) is rewritten to the current `DocumentBlock.sourceHash`. The
migration runs in `SessionState.normalizeTranslationArchive()` (or an
equivalent load-time normalization point) so every open/save cycle converges
existing archives to the block-hash convention.
**Rationale:** Verified on the Human's real `projects.json`: the KF_Voyage
document project has 872 AI-translated blocks, 872/872 carrying the legacy
plan hash and 0 carrying the block hash. Under the ADR-004 freshness
derivation every one of them is falsely flagged stale, so the "Source
changed — translation needs review" banner burns in every chunk of every
pre-existing project and can never clear without retranslating the whole
book — exactly the defect the Human reported. The legacy marker is exact: a
SHA-256 block text hash colliding with a composite plan hash is
cryptographically impossible, so `translated.sourceHash == plan.sourceHash`
unambiguously identifies the old convention. The old app never tracked
staleness at all (the plan hash was inert), so rewriting to the current
block hash preserves the old behavior for past translations while making
future source edits trackable. ADR-004's consequence "legacy blocks report
stale until refreshed" is superseded: that reading made the feature unusable
on all existing projects.
**Consequences:** One normalization pass over `translationsByLanguage` for
document sessions; slice-keyed entries (`#slice_`, `:slice:`) resolve their
base block the same way. Blocks whose stored hash matches neither the plan
nor the block hash are left untouched (genuinely stale). New translations
already follow ADR-004 and are unaffected.

---

## ADR-006 — Re-scope S17 from feature work to E4 test hardening

**Status:** Accepted
**Date:** 2026-08-16
**Decision:** S17 is re-scoped from its original slice E4 feature scope to a
test-hardening step for the already-shipped E4 implementation (Retranslate
Selection with AI, delivered in S14 by ADR-003). The Human confirmed on
2026-08-16 that the feature works and must not be rebuilt, and asked for more
tests on it. S17 therefore adds a deterministic test battery over the
validator, strict wire-contract decoding, and engine edge gates, with zero
product-code changes.
**Rationale:** Slice E4 was pulled into S14 by ADR-003, leaving S17 without
its original scope. The Human explicitly rejected both rebuilding the working
feature and the earlier "Source-pane Translate Selection" re-scope direction,
choosing additional verification instead. Existing coverage is 16 tests /
3 suites; the validator warning paths, strict-decode field errors, engine
pre-provider gates, stale-formatting gate, cancellation propagation, outcome
metrics, request context bounds, and glossary/protected-token enrichment are
not yet pinned by tests.
**Consequences:** S17 target files are test-only
(`Tests/VaniScriptCoreTests/DocumentSelectionTranslationValidatorTests.swift`
new, `Tests/VaniScriptTests/DocumentSelectionTranslationEngineTests.swift`
extended). Any bug discovered while writing tests is reported to Main, not
fixed in this step. The S17 stop-gate remains Human ACCEPTED + Reviewer
APPROVED + Tester qa_green.

---

## ADR-007 — Refresh Source on existing document projects

**Status:** Accepted
**Date:** 2026-08-16
**Decision:** Add step **S20 — Refresh Source** for document projects. The user
may pick a replacement source file (path/name may differ) for an already-open
or selected project. Import reuses `DocumentImportService` into the project's
existing source asset directory. Old and new blocks are matched by
**text-only identity**: SHA-256 of NFC-normalized joined span text (not the
DOCX `sourceHash`, which also fingerprints formatting). Matched blocks keep
their stable block IDs and existing translations in every language; source
spans/colors/style/`sourceHash` are replaced from the new import, and each
kept translation's `sourceHash` is updated to the new block hash so
formatting-only refreshes stay fresh (PRD §9). Unmatched new blocks arrive
without translation; unmatched old translations are dropped. Chunk plans and
aggregate `ChunkData.original` are rebuilt from the refreshed document.
Chunks that gained unmatched/new/missing translation material become
`needsReview`. After a successful refresh the UI shows a summary and offers
**Retranslate N changed chunks** (targeted/stale-only), never a silent full
retranslate. Media projects are out of scope.
**Rationale:** Human needs to upgrade old colorless projects to colored
manuscripts and to absorb publisher source revisions without rebuilding the
whole translation memory. Text-hash matching matches the accepted product
intent; reusing block IDs preserves `translationsByLanguage` maps; offering
(not auto-running) retranslate keeps cost and control with the user.
**Consequences:** New pure merge helper + WorkflowStore entry point + sidebar/
Review affordance + deterministic tests. S13 remains open for its remaining
import-tier/media items; S18 stays parked. Color-fidelity work is
Human-accepted and continues separately through Reviewer/Tester if still
required for the S13 card stop-gate.

