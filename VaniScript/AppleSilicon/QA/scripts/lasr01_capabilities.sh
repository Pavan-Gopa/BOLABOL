#!/usr/bin/env bash
# LASR-01: backend, source, language, auto-detect, layout and OS capability matrix.
# Step-aware: LASR-01 keeps its original SDK-layout spelling; LASR-02+ validates the explicit required SDK layout.
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

state_path = Path("AI_Workflow_Kit/docs/AI/STATE.yaml")
state = state_path.read_text(encoding="utf-8") if state_path.is_file() else ""
step_match = re.search(r"^current_step:\s*([A-Za-z0-9_-]+)", state, re.M)
current_step = step_match.group(1) if step_match else ""
lasr_match = re.fullmatch(r"LASR-(\d+)", current_step)
is_lasr02_or_later = lasr_match is not None and int(lasr_match.group(1)) >= 2

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

parakeet_segment = segments[ids[0]]
if is_lasr02_or_later:
    layout_match = re.search(
        r"requiredLayout:\s*LocalASRRequiredLayout\(\s*"
        r"requiredRelativePaths:\s*\[(?P<paths>.*?)\],\s*"
        r"isSDKManaged:\s*true\s*\)",
        parakeet_segment,
        re.S,
    )
    if not layout_match:
        raise SystemExit(
            "FAIL: parakeet-tdt-06b-v3 must retain its explicit SDK-managed required layout in LASR-02+"
        )
    expected_parakeet_layout = [
        "Preprocessor.mlmodelc",
        "Encoder.mlmodelc",
        "Decoder.mlmodelc",
        "JointDecisionv3.mlmodelc",
        "parakeet_vocab.json",
    ]
    actual_parakeet_layout = re.findall(r'"([^"]+)"', layout_match.group("paths"))
    if actual_parakeet_layout != expected_parakeet_layout:
        raise SystemExit(
            "FAIL: parakeet-tdt-06b-v3 required SDK layout no longer matches the LASR-02 presence contract"
        )
else:
    if "LocalASRRequiredLayout(isSDKManaged: true)" not in parakeet_segment:
        raise SystemExit(
            "FAIL: parakeet-tdt-06b-v3 missing capability/source contract: LocalASRRequiredLayout(isSDKManaged: true)"
        )

for canary_id in ids[1:]:
    if "supportsAutoLanguageDetect: true" in segments[canary_id]:
        raise SystemExit(f"FAIL: {canary_id} must not support auto language detection")
if "minimumMacOSMajor:" in segments[ids[1]]:
    raise SystemExit("FAIL: Canary Flash unexpectedly has a macOS 15+ gate")

revision = re.search(r'canaryFlashRevision\s*=\s*"([0-9a-f]+)"', text)
if not revision or len(revision.group(1)) != 40:
    raise SystemExit("FAIL: Canary Flash Hugging Face revision is not an immutable 40-hex commit")

if is_lasr02_or_later:
    print("PASS: LASR-02+ capabilities retain the Parakeet SDK-managed required layout and source matrix.")
else:
    print("PASS: LASR-01 capabilities, install sources, layouts and OS gates match the contract.")
PY
