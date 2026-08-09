#!/usr/bin/env bash
# LASR-01: old settings merge new defaults without resetting WhisperKit/MLX state or selection.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

python3 - <<'PY'
from pathlib import Path

app_path = Path("Sources/VaniScriptCore/AppSettings.swift")
test_path = Path("Tests/VaniScriptCoreTests/UniversalSettingsTests.swift")
for path in (app_path, test_path):
    if not path.is_file():
        raise SystemExit(f"FAIL: {path} missing")
app = app_path.read_text(encoding="utf-8")
tests = test_path.read_text(encoding="utf-8")

required_app = (
    "let decodedLocalASRModels = try container.decodeIfPresent([String: LocalModelState].self, forKey: .localAsrModels) ?? [:]",
    "self.localAsrModels = Self.mergeLocalASRDefaults(decodedLocalASRModels)",
    "self.localTranslationModels = try container.decodeIfPresent([String: LocalModelState].self, forKey: .localTranslationModels) ?? AppSettings.defaults.localTranslationModels",
    "self.transcriptionProvider = try container.decodeIfPresent(String.self, forKey: .transcriptionProvider) ?? \"coreml-whisperkit\"",
    "for (id, defaultModel) in AppSettings.defaults.localAsrModels where merged[id] == nil",
)
for snippet in required_app:
    if snippet not in app:
        raise SystemExit(f"FAIL: migration-safe AppSettings contract missing: {snippet}")

required_tests = (
    'legacy settings gain new ASR defaults without resetting selection',
    'legacySettings.transcriptionProvider = "whisper-large-v3"',
    'path: "/legacy/whisper-large-v3"',
    'runtime: .whisper',
    'path: "/legacy/qwen35-4b-4bit"',
    'runtime: .mlx',
    'decoded.transcriptionProvider == "whisper-large-v3"',
    'decoded.localAsrModels["whisper-large-v3"]?.status == .downloaded',
    'decoded.localAsrModels["whisper-large-v3"]?.path == "/legacy/whisper-large-v3"',
    'decoded.localTranslationModels["qwen35-4b-4bit"]?.status == .downloaded',
    'decoded.localAsrModels["parakeet-tdt-06b-v3"]?.status == .notDownloaded',
    'decoded.localAsrModels["canary-180m-flash-coreml"]?.runtime == .canary',
    'decoded.localAsrModels["canary-1b-v2-coreml"]?.runtime == .canary',
)
for snippet in required_tests:
    if snippet not in tests:
        raise SystemExit(f"FAIL: migration regression test missing assertion/setup: {snippet}")

print("PASS: settings decode merges LASR defaults while preserving WhisperKit/MLX state and provider selection.")
PY
