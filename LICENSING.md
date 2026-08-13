# BOLABOL Licensing

## Five people are free. The sixth goes commercial. Every release opens with time.

BOLABOL uses the **Business Source License 1.1 (BSL 1.1)** with a custom Five-Person Additional Use Grant and a three-year **Freedom Clock**.

The legal terms are in [`LICENSE`](LICENSE). This document explains the model in plain language. If this guide and the LICENSE ever disagree, the LICENSE controls.

## The simple version

**Up to 5 active human users in one organization:** free production use.

**6 or more active human users in one organization:** a commercial license is required.

**Non-production use:** permitted under BSL 1.1 regardless of team size.

**Commercial redistribution / OEM / hosted service / white-label / embedding BOLABOL as a material part of a product or service for third parties:** requires a commercial license even below five users.

**Every specific BOLABOL version becomes Open Source three years after its first public release**, under **GNU GPL v3 or later**.

---

## The Five-Person Grant

The free production-use threshold is based on **people actually using BOLABOL**, not company revenue, valuation, device count, or total headcount.

Examples:

| Scenario | License |
|---|---|
| One person using BOLABOL for personal work | Free |
| Freelancer using BOLABOL for paid client work | Free |
| Company with 100 employees but only 3 people actively using BOLABOL | Free |
| Team with 5 active BOLABOL users | Free |
| Team adds a 6th active BOLABOL user | Commercial license required |
| One-person company reselling a modified BOLABOL as its own product | Commercial license required |
| Company offering BOLABOL functionality as a hosted or managed service | Commercial license required |
| Large organization evaluating BOLABOL in a non-production test environment | Permitted under BSL 1.1 |

### What counts as an Active User?

An **Active User** is a natural person who uses, operates, or accesses BOLABOL in production at least once during a rolling 30-day period.

AI agents, bots, automated workflows, local models, cloud models, devices, and other software do **not** count as separate users when they are acting solely on behalf of a human Active User.

So: five people with fifty AI agents are still five people.

### What counts as one Organization?

Employees and contractors working for the same organization are counted together. Entities under common control are treated as one organization for the five-user threshold.

This keeps the rule simple: splitting a team across subsidiaries or contractors does not create extra free five-user pools.

---

## The Freedom Clock

Fresh BOLABOL code is protected while it is young. Old BOLABOL code does not stay locked forever.

For every specific publicly released version:

**Release date → 3 years of BSL 1.1 → automatic transition to GPL v3-or-later**

There is no discretionary extension hidden behind the rule. The three-year Change Date is part of the license itself.

This creates a deliberate balance:

- current development can support the people building BOLABOL;
- individuals and small teams can use the current product without asking permission;
- larger deployments help fund continued development;
- every released version has a guaranteed path to true Open Source.

### The principle

> **Free for people. Sustainable for builders. Open with time.**

Or even shorter:

> **Five humans free. The sixth funds the future.**

---

## When a commercial license is required

A commercial license is required when either of these applies:

1. **Six or more Active Users** use BOLABOL in production on behalf of the same Organization.
2. You want rights outside the Five-Person Grant, including commercial OEM use, resale, white-labeling, hosted/managed service use, or embedding BOLABOL or a derivative as a material part of a commercial product or service offered to third parties.

Commercial licensing can also provide alternative redistribution or deployment terms where the standard BSL grant is not a fit.

See [`COMMERCIAL.md`](COMMERCIAL.md).

---

## Is BOLABOL Open Source?

**Before a version reaches its Freedom Date:** no. BSL 1.1 is source-available, not an OSI Open Source license.

**After that version reaches its Freedom Date:** yes. That specific version becomes available under GNU GPL v3 or later.

This distinction is intentional and should be stated clearly whenever the project is described.

---

## Future releases

Each specific BOLABOL version receives its own three-year Freedom Clock from the date that version is first publicly distributed.

Changing the licensing model for a future version does not retroactively remove rights already granted to an earlier version.

---

## Contributions

If BOLABOL begins accepting substantial third-party code contributions, contribution terms should be kept compatible with the project's BSL/commercial licensing model. Contributors should retain clear attribution while granting rights broad enough for BOLABOL to continue offering both the public BSL release and separate commercial licenses.

Until formal contribution terms are published, contributors should open an issue before submitting substantial code intended for inclusion in the core product.
