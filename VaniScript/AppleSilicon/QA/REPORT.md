# QA REPORT — VaniScript Apple Silicon / LASR-01

- **Дата:** 2026-08-09
- **Трек/шаг:** `LOCAL_ASR_COREML` / `LASR-01`
- **Scope:** Catalog + install-source contracts
- **Suite:** **158 scripts → 158 PASS / 0 FAIL**
- **Swift:** **338 tests / 47 suites / 0 failures**
- **Electron regression compile:** `npm run compile` GREEN
- **Bugs open:** 0
- **Вердикт:** **GREEN**

## Прогоны

| Прогон | Результат |
|---|---|
| Первый полный прогон | 146 PASS / 12 FAIL — устаревшие QA-гейты прошлых A3–A7/CPS шагов не распознавали новый LASR-трек; LASR-01 delta и 338 Swift tests прошли |
| После QA-only step-awareness maintenance | **158 PASS / 0 FAIL — GREEN** |

```bash
cd "/Users/pavan/Documents/AI Projects/VaniScript/AppleSilicon"
QA/run_all.sh
# PASS: 158   FAIL: 0
# RESULT: GREEN
```

## LASR-01 contract evidence

1. В каталоге ровно три новых ID: `parakeet-tdt-06b-v3`, `canary-180m-flash-coreml`, `canary-1b-v2-coreml`.
2. `LocalASRBackend`, `LocalASRInstallSource`, `LocalASRModelDescriptor`, capability/layout и `remotePackage` contracts присутствуют.
3. FluidAudio закреплён exact `0.15.5` в `Package.swift` и `Package.resolved` (`19600a485baa4998812e4654b70d2bab8f2c9949`).
4. Parakeet: auto, v3/int8, 25 языков. Canary: no-auto. Flash: `en/de/fr/es`. Canary 1B: `ru/uk`, macOS 15+.
5. Canary 1B остаётся unbound placeholder: нет concrete URL, Google Drive URL, digest, archive metadata или Bolabol CDN.
6. `LocalModelRuntime.canary`, shared Parakeet/Canary runtimes и canonical `SharedModelsRoot` paths проверены.
7. Legacy settings decode сохраняет WhisperKit selection/path/status и MLX path/status, добавляя новые defaults.
8. Новые backends не подключены к download manager, engines, pipeline, `WorkflowStore` или Models UI; LASR-02+ source files отсутствуют.
9. `FEEDBACK.md` содержит LASR-01 `RESULT: [APPROVED]`; `STATE.yaml` остаётся на `current_step: LASR-01`, post-tag не изменён.

## QA suite maintenance

Исторические A3–A7 FEEDBACK/STATE/UI gates и CPS STATE gate сделаны step-aware для последующего `LASR-*` трека. Product-код не менялся. Также исправлен shell-вывод `a2_tokenusage_type.sh`, где backticks запускали `+` как команду, не меняя exit code.

## Наблюдение

SwiftPM выдаёт существующее non-blocking warning FluidAudio о неописанном checkout-файле `benchmark.md`; сборка и тесты завершились успешно.
