# Coverage notes — Blaboom 1.0.3 train

Living checklist of automated vs manual coverage for the bilingual + Canary train.
Full matrices live in `BLABOOM_1.0.3_IMPLEMENTATION_PLAN.md` §12.

## Automated (target by B11)

| Area | Status |
|------|--------|
| Language pair migration | pending B1 |
| Picker order invariants | pending B1 |
| Onboarding/settings/help keys × 15 | pending B5 |
| Canary capabilities.supportsAuto == false | pending B8–B9 |
| HUD cycle primary↔additional | pending B9 |
| ASR/AST routing matrix | pending B9 |
| Archive stats format regression | existing (keep green) |
| No Python in Sources | pending B11 qa script |

## Manual (B12)

M1–M10 per plan §12.2.

## Commands

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"
swift test
./script/qa/run_all.sh
```
