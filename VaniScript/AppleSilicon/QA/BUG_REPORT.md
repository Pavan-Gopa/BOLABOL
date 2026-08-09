# QA BUG REPORT — closed after product remediation

- **Дата:** 2026-08-02
- **Suite final:** **150 PASS / 0 FAIL** → **GREEN**
- **Bugs open:** **0**

## Closed product bugs

| ID | Fix |
|----|-----|
| BUG-CPS-001 | Restored exact A6 disclaimer in `UsageStatisticsView` |
| BUG-CPS-002 | Anthropic restored to catalog order/providers + Settings `anthropicCard` |
| BUG-CPS-003 | A6 markers restored (Last Transaction Details, Transcribing, transactions, usageCard, remaining) |
| BUG-CPS-004 | `realBalanceSection` + `CloudBalanceRow(descriptor:…)` in body |

## Remaining product debt (not suite-blocking)

- Anthropic **workflow translation route** (engine/CloudChatRouter) still not fully wired — card + key save only. Track under CPS / OBS-005 coding steps.
- Dual provider ids (`gemini-cloud` vs `gemini`) still present — structural cleanup deferred.
- Capability-by-keyword heuristics remain — CPS model-capability work.

These do not fail current QA scripts; they are next CPS implementation items.
