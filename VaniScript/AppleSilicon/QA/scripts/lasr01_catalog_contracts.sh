#!/usr/bin/env bash
# LASR-01: descriptor/install-source contracts and exactly three new ASR IDs.
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

required_declarations = (
    "public enum LocalASRBackend",
    "public enum LocalASRInstallSource",
    "public struct LocalASRModelDescriptor",
    "public struct LocalASRCapabilities",
    "public struct LocalASRRequiredLayout",
    "public struct RemoteModelPackageRelease",
)
for declaration in required_declarations:
    if declaration not in text:
        raise SystemExit(f"FAIL: missing catalog contract: {declaration}")

backend_match = re.search(r"public enum LocalASRBackend[^\{]*\{(?P<body>.*?)\n\}", text, re.S)
if not backend_match:
    raise SystemExit("FAIL: LocalASRBackend body not found")
backend_cases = re.findall(r"\bcase\s+([A-Za-z][A-Za-z0-9_]*)", backend_match.group("body"))
expected_backends = ["whisperKitCoreML", "fluidAudioCoreML", "canaryCoreML"]
if backend_cases != expected_backends:
    raise SystemExit(f"FAIL: LocalASRBackend cases {backend_cases}, expected {expected_backends}")

source_match = re.search(r"public enum LocalASRInstallSource[^\{]*\{(?P<body>.*?)(?:\n\s*public enum Kind)", text, re.S)
if not source_match:
    raise SystemExit("FAIL: LocalASRInstallSource body not found")
for source_case in ("whisperKit", "fluidAudio", "huggingFace", "remotePackage"):
    if not re.search(rf"\bcase\s+{source_case}\b", source_match.group("body")):
        raise SystemExit(f"FAIL: LocalASRInstallSource missing case {source_case}")

start = text.find("public static let newLocalASRModelDescriptors")
end = text.find("public static let whisperKitModelDescriptors", start)
if start < 0 or end < 0:
    raise SystemExit("FAIL: newLocalASRModelDescriptors catalog boundary missing")
new_catalog = text[start:end]
actual_ids = re.findall(r'\bid:\s*"([^"]+)"', new_catalog)
expected_ids = [
    "parakeet-tdt-06b-v3",
    "canary-180m-flash-coreml",
    "canary-1b-v2-coreml",
]
if actual_ids != expected_ids:
    raise SystemExit(f"FAIL: LASR-01 IDs {actual_ids}, expected exactly {expected_ids}")
if len(set(actual_ids)) != len(actual_ids):
    raise SystemExit("FAIL: duplicate LASR-01 catalog ID")
if "localASRModelDescriptors = whisperKitModelDescriptors + newLocalASRModelDescriptors" not in text:
    raise SystemExit("FAIL: new descriptors are not merged with existing WhisperKit descriptors")

print("PASS: LASR-01 catalog exposes the required contracts and exactly three new ASR IDs.")
PY
