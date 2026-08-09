#!/usr/bin/env bash
# LASR-01 negative gate: no LASR-02+ downloader, engine, pipeline or Models UI wiring.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

python3 - <<'PY'
from pathlib import Path

sources = Path("Sources")
if not sources.is_dir():
    raise SystemExit("FAIL: Sources directory missing")

model_ids = (
    "parakeet-tdt-06b-v3",
    "canary-180m-flash-coreml",
    "canary-1b-v2-coreml",
)
allowed_id_files = {
    Path("Sources/VaniScriptCore/NativeModelCatalog.swift"),
    Path("Sources/VaniScriptCore/AppSettings.swift"),
}
for model_id in model_ids:
    locations = {
        path
        for path in sources.rglob("*.swift")
        if model_id in path.read_text(encoding="utf-8", errors="replace")
    }
    if locations != allowed_id_files:
        rendered = ", ".join(str(path) for path in sorted(locations)) or "none"
        raise SystemExit(f"FAIL: {model_id} references escaped LASR-01 catalog/settings scope: {rendered}")

future_files = (
    "RemoteModelPackageInstaller.swift",
    "LocalASREngine.swift",
    "LocalASRAudioPreprocessor.swift",
    "ParakeetASREngine.swift",
    "CanaryCoreMLEngine.swift",
    "LocalASREngineRouter.swift",
)
for name in future_files:
    matches = list(sources.rglob(name))
    if matches:
        raise SystemExit(f"FAIL: future-step file exists during LASR-01: {matches[0]}")

app_sources = Path("Sources/VaniScript")
for path in app_sources.rglob("*.swift"):
    text = path.read_text(encoding="utf-8", errors="replace")
    for symbol in (
        "LocalASRBackend",
        "LocalASRInstallSource",
        "LocalASRModelDescriptor",
        "canaryCoreML",
        "fluidAudioCoreML",
        "import FluidAudio",
    ):
        if symbol in text:
            raise SystemExit(f"FAIL: future backend wiring '{symbol}' leaked into {path}")

for path in (
    Path("Sources/VaniScript/Services/ModelDownloadManager.swift"),
    Path("Sources/VaniScript/Services/NativeProcessingPipeline.swift"),
    Path("Sources/VaniScript/Views/SettingsView.swift"),
    Path("Sources/VaniScript/Views/ConfigWorkspaceView.swift"),
    Path("Sources/VaniScript/Stores/WorkflowStore.swift"),
):
    if not path.is_file():
        raise SystemExit(f"FAIL: expected regression surface missing: {path}")
    text = path.read_text(encoding="utf-8", errors="replace")
    leaked = [model_id for model_id in model_ids if model_id in text]
    if leaked:
        raise SystemExit(f"FAIL: LASR-02+ wiring leaked into {path}: {leaked}")

print("PASS: no downloader, engine, pipeline or Models UI wiring leaked into LASR-01.")
PY
