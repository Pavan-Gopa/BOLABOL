# FEEDBACK — Blaboom 1.0.3

> Workers fill sections on handoff. Orchestrator reads this every «статус».

---

## Meta

| Field | Value |
|-------|--------|
| Step | B4 |
| Actor | reviewer |
| Timestamp | 2026-08-02 |
| RESULT | `approved` |

---

## §1 — Build / commands (Coder)

Commands run and outcomes:

```bash
cd "/Users/pavan/Documents/AI Projects/Blaboom"
graphify query "HelpSettingsView helpBilingual helpLang" --graph graphify-out/graph.json
swift build   # ✔ Build complete
swift test    # ✔ 465 tests in 4 suites passed (461 at B3 + 4 new B4 tests)
```

---

## §2 — Step compliance (Coder)

- [x] Only `target_files` touched / inspected:
  - `Sources/NativeBlaboom/Views/Settings/HelpSettingsView.swift`
  - `Sources/NativeBlaboomCore/Services/AppText.swift`
  - `Tests/NativeBlaboomCoreTests/SettingsLocalizationTests.swift`
  - `Tests/NativeBlaboomCoreTests/OnboardingLocalizationTests.swift`
  - `Tests/NativeBlaboomCoreTests/AppTextFullCoverageTests.swift`
  - `AI_Workflow_Kit/docs/AI/FEEDBACK.md` (handoff only)
- [x] Help section «Your languages» (`helpBilingualTitle` … `helpBilingualPolishNote`) added/verified in `HelpSettingsView.swift` (section ID "bilingual" placed after "lang", included in default expanded sections).
- [x] All 12 EN keys for the Help bilingual section present in `AppText.swift` with full plan §8 content:
  - Primary vs additional language model explained
  - Onboarding and Settings path (`Settings → Hotkey → Your Languages`)
  - Auto-detect engines (Parakeet/Whisper) vs Canary (no A mode, HUD letter cycles primary ↔ additional)
  - Polish note (polishing MLX/cloud runs after transcription, not on Canary; improves text in spoken language without changing language)
- [x] Ensure EN keys resolve in tests (no raw-key fallback) via `helpBilingualKeysResolveInEnglish()` and `settingsKeys`.
- [x] Terminology tests added: `helpBilingualCopyAvoidsUnnegatedTargetAlwaysOutputTerminology()` asserts that "target always output" or "always output" appears ONLY when explicitly negated (e.g., "not a 'target always output'"), ensuring no false product promise.
- [x] `SettingsLocalizationTests.swift`, `OnboardingLocalizationTests.swift`, and `AppTextFullCoverageTests.swift` updated and all tests green with EN fallback for new keys.
- [x] `swift test` GREEN (465 tests passed).
- [x] No Python / forbidden runtime; no out-of-scope work (no B5 15-locale bulk, no Canary engine implementation, no Settings UI redesign).
- [x] No `git commit` / `git push`.

---

## §3 — Invariants (Coder)

- `AppText` EN keys resolve cleanly for all `helpBilingual*` cases without falling back to raw keys.
- Terminology invariant intact: additional language is framed as a second language for quick switching, NEVER as an unnegated "target always output" promise.
- `HelpSettingsView` maintains existing layout and design, rendering the bilingual section in proper order and hierarchy.
- Full test suite remains green across all test files (`465/465` tests passed).
- Version stays `1.0.3`.

---

## §4 — Comments / structure (Coder)

- `SettingsLocalizationTests.swift`: Added `b4HelpBilingualKeys` list containing all 12 Help bilingual keys. Updated `settingsKeys` to include them for localization checks. Added 3 new unit tests: `helpBilingualKeysResolveInEnglish`, `helpBilingualCopyAvoidsUnnegatedTargetAlwaysOutputTerminology`, and `helpBilingualCopyDescribesPrimaryAndAdditionalModel`.
- `AppTextFullCoverageTests.swift`: Added `appTextBilingualHelpKeysExistAndDocumentLanguages` test verifying EN resolution and documentation of primary language in `helpBilingualIntro`.
- `HelpSettingsView.swift`: Inspected guide section "bilingual" containing paragraph and bullet list of 10 items.
- `AppText.swift`: Confirmed all 12 `helpBilingual*` enum cases and their EN translations.

---

## §5 — Reviewer findings (Reviewer)

**Verdict: [APPROVED]**

Checklist:

1. **Scope** — ✅ Diff touches only B4 target files: `HelpSettingsView.swift` (+25), `AppText.swift` (+46/−4), `SettingsLocalizationTests.swift` (+76), `AppTextFullCoverageTests.swift` (+11), plus AI workflow docs (FEEDBACK/STATE). No B5 15-locale bulk, no Canary engine code, no Settings redesign. `OnboardingLocalizationTests.swift` listed in handoff was not modified (not required — no onboarding copy changes in B4).
2. **Section «Your languages»** — ✅ `guideSection(id: "bilingual")` inserted after `lang` / before `models` (HelpSettingsView.swift:141) and added to default expanded sections. All plan §8.1 items present across 10 bullets: primary, additional, not-always-output (explicit negation), onboarding, exact Settings path (Hotkey → Your Languages), Canary no-A / primary↔additional letter cycle, Parakeet/Whisper auto-detect, polish note (MLX/cloud, after transcription, does not change language).
3. **helpLang*/helpHUD alignment (EN)** — ✅ EN copy for `helpLangIntro/Auto/Forced/EnglishNote/Where` and `helpHUDLeftA/Letter/Tap/ControlLanguage` rewritten to the primary+additional model; no internal EN contradictions (e.g., HUD letter defaults to additional language, Hotkey override, Glossary fallback chain preserved).
4. **Keys / terminology** — ✅ All 12 `helpBilingual*` EN strings resolve (fallback `translations["en"]` authoritative, never raw key). "target always output" appears exactly twice, both negated ("not a 'target always output'"); grep of AppText.swift confirms no unnegated occurrence.
5. **Tests** — ✅ 4 new tests: `helpBilingualKeysResolveInEnglish`, `helpBilingualCopyAvoidsUnnegatedTargetAlwaysOutputTerminology` (all 15 locales), `helpBilingualCopyDescribesPrimaryAndAdditionalModel`, `appTextBilingualHelpKeysExistAndDocumentLanguages`; `b4HelpBilingualKeys` also added to `settingsKeys` (all-locale no-raw-key guard).
6. **swift test** — ✅ GREEN: 465 tests in 4 suites passed (matches coder claim of 461 + 4 new).
7. **Comments/structure** — ✅ Clean; section reference comments match plan §8.1.

Non-blocking notes (tracked for B5):
- Non-EN maps (ru/es/de/fr/it/pt/zh/ja/ko/ar/hi/uk/tr/pl) still carry the old single-target `helpLang*`/`helpHUD*` wording (e.g., ru: «Hotkey → Язык транскрибации», «принудительный целевой язык»), now inconsistent with the new EN model. Expected per train plan — 15-locale pass belongs to B5 (§9).
- `helpBilingualSettingsPath` bullet repeats the path already in `helpBilingualWhere` — fine, plan §8.1 item 5 asks for the exact path.
- Working tree also shows graphify-out/cache deletions — tooling artifacts, not product code; no action needed.

---

## §6 — QA summary (Tester)

**RESULT: `qa_green`**

- `swift test` — 467/467 (B3 461 + 4 Coder B4 + **2 Tester gap-hunt tests**)
- `./script/qa/run_all.sh` — 14/14
- **New tests (Tester):** `helpBilingualSettingsPathMentionsHotkeyAndYourLanguages`, `helpLangHelpHUDConsistentWithBilingualModel`
- Gap-hunt checklist plan §8.1 all green (REPORT B4 section)
- Report: `AI_Workflow_Kit/docs/AI/REPORT.md` Step B4

---

## Handoff line (all)

> Готово. Вернись к оркестратору и скажи «статус».

