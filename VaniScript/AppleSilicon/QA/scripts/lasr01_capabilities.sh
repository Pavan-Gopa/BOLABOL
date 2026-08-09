#!/usr/bin/env bash
# LASR-01: backend, source, language, auto-detect, layout and OS capability matrix.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

python3 - <<'PY'
from pathlib import Path
import re

path = Path("Sources/VaniScriptCore/NativeModelCatalog.swift")
if not path.is_file():
    raise SystemExit(f"FAIL: {path} missing")
text = path.read_text(encoding="utf-8")

expected_25 = [
    "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de",
    "el", "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro", "sk",
    "sl", "es", "sv", "ru", "uk",
]

def array_values(name: str) -> list[str]:
    match = re.search(rf"(?:public|private) static let {name}\s*=\s*\[(.*?)\]", text, re.S)
    if not match:
        raise SystemExit(f"FAIL: language array {name} missing")
    return re.findall(r'"([a-z]{2})"', match.group(1))

if array_values("parakeetLanguageCodes") != expected_25:
    raise SystemExit("FAIL: Parakeet/Canary-1B language catalog is not the required 25-code set")
if array_values("canaryFlashLanguageCodes") != ["en", "de", "fr", "es"]:
    raise SystemExit("FAIL: Canary Flash languages must be exactly en/de/fr/es")

catalog_start = text.find("public static let newLocalASRModelDescriptors")
catalog_end = text.find("public static let whisperKitModelDescriptors", catalog_start)
catalog = text[catalog_start:catalog_end]
ids = [
    "parakeet-tdt-06b-v3",
    "canary-180m-flash-coreml",
    "canary-1b-v2-coreml",
]
positions = [catalog.find(f'id: "{model_id}"') for model_id in ids]
if any(position < 0 for position in positions):
    raise SystemExit("FAIL: one or more LASR-01 descriptors missing")
segments = {}
for index, model_id in enumerate(ids):
    finish = positions[index + 1] if index + 1 < len(ids) else len(catalog)
    segments[model_id] = catalog[positions[index]:finish]

required = {
    ids[0]: (
        "backend: .fluidAudioCoreML",
        'installSource: .fluidAudio(version: "v3", encoderPrecision: "int8")',
        "supportsAutoLanguageDetect: true",
        "supportedLanguageCodes: parakeetLanguageCodes",
        "maxEngineWindowSeconds: 30",
        "LocalASRRequiredLayout(isSDKManaged: true)",
    ),
    ids[1]: (
        "backend: .canaryCoreML",
        "installSource: .huggingFace(",
        'repositoryID: "aufklarer/Canary-180M-Flash-CoreML"',
        "revision: canaryFlashRevision",
        "supportsAutoLanguageDetect: false",
        "supportedLanguageCodes: canaryFlashLanguageCodes",
        "maxEngineWindowSeconds: 10",
        '"CanaryEncoder.mlmodelc"',
        '"CanaryPrefill.mlmodelc"',
        '"CanaryDecoder.mlmodelc"',
        '"config.json"',
        '"vocab.json"',
    ),
    ids[2]: (
        "backend: .canaryCoreML",
        "installSource: .remotePackage(.canaryOneBPlaceholder)",
        "supportsAutoLanguageDetect: false",
        "supportedLanguageCodes: parakeetLanguageCodes",
        "maxEngineWindowSeconds: 15",
        "minimumMacOSMajor: 15",
        '"canary_encoder.mlmodelc"',
        '"canary_cross_kv.mlmodelc"',
        '"canary_decoder_kv.mlmodelc"',
        '"canary_spe.model"',
    ),
}
for model_id, snippets in required.items():
    for snippet in snippets:
        if snippet not in segments[model_id]:
            raise SystemExit(f"FAIL: {model_id} missing capability/source contract: {snippet}")

for canary_id in ids[1:]:
    if "supportsAutoLanguageDetect: true" in segments[canary_id]:
        raise SystemExit(f"FAIL: {canary_id} must not support auto language detection")
if "minimumMacOSMajor:" in segments[ids[1]]:
    raise SystemExit("FAIL: Canary Flash unexpectedly has a macOS 15+ gate")

revision = re.search(r'canaryFlashRevision\s*=\s*"([0-9a-f]+)"', text)
if not revision or len(revision.group(1)) != 40:
    raise SystemExit("FAIL: Canary Flash Hugging Face revision is not an immutable 40-hex commit")

print("PASS: LASR-01 capabilities, install sources, layouts and OS gates match the contract.")
PY
