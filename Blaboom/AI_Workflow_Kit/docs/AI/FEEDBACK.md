# FEEDBACK — Blaboom 1.0.3

> Workers fill sections on handoff. Orchestrator reads this every «статус».

---

## Meta

| Field | Value |
|-------|--------|
| Step | B1 |
| Actor | coder (reviewed by reviewer) |
| Timestamp | 2026-08-02 |
| RESULT | `approved` |

---

## §1 — Build / commands (Coder)

Commands run and outcomes:

```
cd "/Users/pavan/Documents/AI Projects/Blaboom"
swift test   # ✔ 449 tests in 4 suites passed
swift build  # ✔ Build complete (mlx-swift identity warning pre-existing, unrelated)
```

Graphify used first: query on transcription-language preference / GeneralSettingsStore storage + explain on TranscriptionLanguagePreference.

---

## §2 — Step compliance (Coder)

- [x] Only `target_files` touched (8 modified + 4 new files from the B1 list; graphify cache stamps reverted)
- [x] No future step work (no onboarding/settings/help/canary UI, no HUD changes, no AppText i18n keys)
- [x] No Python / forbidden runtime
- [x] primary + additional terminology respected (no "target always output" anywhere)

Notes: `HotkeySettings.swift` (model) left unchanged — no language-pair concern lives in the hotkey model itself; the pair is wired into `HotkeySettingsStore` (read accessor) instead. `TranscriptionLanguageMode` got `CaseIterable`/`Identifiable` only (stable-order test added).

---

## §3 — Invariants (Coder)

What must stay true (engines, HUD A for non-Canary, version, etc.):

- Auto-detect behavior untouched: `TranscriptionModelSettings.languagePreference` and `TranscriptionLanguageRouter` unchanged; pair is seeded/mirrored, never replaces auto (plan §4.1).
- `GeneralSettings` legacy payloads without `speechLanguages` still decode (decodeIfPresent → fresh-install defaults), then store runs best-effort migration once and persists it (durable).
- All 449 existing + new tests green; `swift build` complete.
- Version line stays 1.0.3 (no version-train changes in this step).
- Terminology: additional ≠ "always output"; same-as-primary policy supported but not forced.

---

## §4 — Comments / structure (Coder)

New modules headers, non-obvious why-comments:

- `Sources/NativeBlaboomCore/Models/UserSpeechLanguages.swift` (NEW) — B1 header with plan refs (§3.1/§3.3/§3.4); `makeDefaults(systemLocale:)`, `migrating(legacyTranscriptionCode:legacyTargetLanguageName:)`, `settingAdditionalSameAsPrimary()`; custom Codable normalizes codes and defaults empty/missing to `en`.
- `Sources/NativeBlaboomCore/Models/LanguagePickerOrder.swift` (NEW) — B1 header with plan §5 refs; canonical order en → Europe (fr,de,it,pl,pt,ru,es,tr,uk) → Asia/other (ar,zh,hi,ja,ko); `SpeechLanguage` struct (endonym display per §5.2); `uiLanguages` keeps `.system` sentinel first, never between en/fr; `englishNamesByCode` exists only to resolve legacy string values (UI stays endonym).
- `GeneralSettingsStore` — `settingsDefaultsKey` made internal so sibling stores read the same blob (single source of truth, §3.3); migration runs only when payload lacks `speechLanguages`, persists the migrated blob immediately.
- `TranscriptionModelStore` / `HotkeySettingsStore` — read-only `speechLanguages` accessors decoding the shared GeneralSettings blob (canonical), legacy `languagePreference` routing untouched.
- `TranscriptionLanguagePreference.resolvedSpeechLanguageCode` — extracts the explicit code used by migration (`.auto` → nil).
- Why no store unit tests: `NativeBlaboomCoreTests` depends on Core only; migration logic lives in Core `UserSpeechLanguages.migrating` and is fully tested there; store glue is thin.

---

## §5 — Reviewer findings (Reviewer)

**Verdict:** [APPROVED]

### Must fix

None.

### Nice to have

1. `Blaboom/graphify-out/.graphify_root` still shows a trailing-newline stamp change vs B1-pre (cosmetic; content identical).
2. 219 untracked `graphify-out/cache/ast/…` JSON files are tool artifacts and not gitignored — consider adding `graphify-out/cache/` to `.gitignore` or cleaning before checkpoint.
3. Workspace monorepo has pre-existing uncommitted changes in other projects (SmartScribe deletions, VaniScript CPS track, DialGent) — outside B1 scope; orchestrator should handle separately so a B1 checkpoint does not sweep them.

### Notes (what was verified)

Re-ran the full suite from `Blaboom`: **449 tests in 4 suites — green** (matches Coder claim), incl. 21 new B1 tests (14 `UserSpeechLanguagesTests` + 7 `LanguagePickerOrderTests`) and 6 additions in `GeneralSettingsTests` / `TranscriptionLanguageModeTests`.

Checklist: 1) Diff limited to B1 `target_files` (10 modified + 4 new; `HotkeySettings.swift` model untouched as documented) — no onboarding/settings/Help/Canary/AppText bulk. 2) `UserSpeechLanguages`: primary + additional, may be equal, custom Codable with `decodeIfPresent` → `en` defaults + code normalization. 3) Migration best-effort: `GeneralSettings.decodeIfPresent` keeps legacy payloads decodable; store seeds the pair from `transcription.modelSettings` (`languagePreference.resolvedSpeechLanguageCode`, `.auto` → nil) + `translation.targetLanguage` AppStorage and persists once. 4) `LanguagePickerOrder`: en first → Europe (fr…uk) → Asia (ar…ko); ru at index 5 (not 1); ru before zh; System sentinel first in `uiLanguages`, never between en/fr — all covered by order-invariant tests. 5) Terminology primary/additional only; the sole “always output” mention is a code comment stating additional is *not* that (directive, not API/UI copy). 6) Auto-detect path intact: `TranscriptionLanguageRouter`/`languagePreference` unchanged; the pair is seeded/mirrored, never replaces auto. 7) 449/449 green (re-run). 8) B1 headers + plan refs on both new modules, English comments. 9) No Python/forbidden runtime in B1 code.
---

## §6 — QA summary (Tester)

- Suite: B1 — Language pair store + picker order
- Pass / fail: **449/449 tests green** (run twice); QA gate `./script/qa/run_all.sh` **14/14 passed** — `qa_green`, 0 bugs
- B1 coverage: 21 new tests (14 `UserSpeechLanguagesTests` + 7 `LanguagePickerOrderTests`) + 6 additions (5 `GeneralSettingsTests` + 1 `TranscriptionLanguageModeTests`)
- Invariants verified: `en` first excluding System; `ru` not index 1 (index 1 = `fr`); Europe before Asia (`ru` before `zh`); System sentinel never between `en`/`fr`; additional may equal primary; migration + legacy-payload decode pass
- No Python / forbidden runtime in B1 Sources (new files import only `Foundation`)
- Diff scope matches `target_files` (6 modified + 4 new)
- Report file: `REPORT.md` (green)

---

## Handoff line (all)

> Готово. Вернись к оркестратору и скажи «статус» или «приступай».
