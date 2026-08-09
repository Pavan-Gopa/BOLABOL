#!/usr/bin/env bash
# LASR-01: migration-safe runtime values and canonical Parakeet/Canary storage paths.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

python3 - <<'PY'
from pathlib import Path
import re

app_path = Path("Sources/VaniScriptCore/AppSettings.swift")
root_path = Path("Sources/VaniScriptCore/SharedModelsRoot.swift")
catalog_path = Path("Sources/VaniScriptCore/NativeModelCatalog.swift")
for path in (app_path, root_path, catalog_path):
    if not path.is_file():
        raise SystemExit(f"FAIL: {path} missing")
app = app_path.read_text(encoding="utf-8")
root = root_path.read_text(encoding="utf-8")
catalog = catalog_path.read_text(encoding="utf-8")

def enum_cases(source: str, declaration: str) -> list[str]:
    match = re.search(rf"{re.escape(declaration)}[^\{{]*\{{(?P<body>.*?)\n\}}", source, re.S)
    if not match:
        raise SystemExit(f"FAIL: {declaration} body missing")
    return re.findall(r"\bcase\s+([A-Za-z][A-Za-z0-9_]*)", match.group("body"))

local_cases = enum_cases(app, "public enum LocalModelRuntime")
if local_cases != ["whisper", "parakeet", "canary", "mlx"]:
    raise SystemExit(f"FAIL: LocalModelRuntime raw-value cases changed: {local_cases}")
shared_cases = enum_cases(root, "public enum SharedModelRuntime")
if shared_cases != ["mlx", "gguf", "ggml", "whisperkit", "parakeet", "canary"]:
    raise SystemExit(f"FAIL: SharedModelRuntime cases changed unexpectedly: {shared_cases}")

expected_paths = {
    "parakeet-tdt-06b-v3": "parakeet/parakeet-tdt-0.6b-v3",
    "canary-180m-flash-coreml": "canary/180m-flash",
    "canary-1b-v2-coreml": "canary/1b-v2",
}
for model_id, relative_path in expected_paths.items():
    pattern = rf'id:\s*"{re.escape(model_id)}".*?relativeStorageSubpath:\s*"{re.escape(relative_path)}"'
    if not re.search(pattern, catalog, re.S):
        raise SystemExit(f"FAIL: {model_id} canonical path is not {relative_path}")

if "for descriptor: LocalASRModelDescriptor" not in root:
    raise SystemExit("FAIL: SharedModelsRoot lacks descriptor-backed modelURL overload")
if ".appendingPathComponent(descriptor.relativeStorageSubpath, isDirectory: true)" not in root:
    raise SystemExit("FAIL: descriptor modelURL does not resolve below SharedModelsRoot")

runtime_defaults = {
    "parakeet-tdt-06b-v3": ".parakeet",
    "canary-180m-flash-coreml": ".canary",
    "canary-1b-v2-coreml": ".canary",
}
for model_id, runtime in runtime_defaults.items():
    if not re.search(rf'"{re.escape(model_id)}"\s*:\s*LocalModelState\(.*?runtime:\s*\{runtime}', app, re.S):
        raise SystemExit(f"FAIL: AppSettings default {model_id} does not use runtime {runtime}")

print("PASS: Local/Shared runtimes preserve existing values and resolve canonical ASR paths.")
PY
