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
