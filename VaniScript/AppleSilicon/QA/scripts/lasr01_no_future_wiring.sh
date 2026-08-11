#!/usr/bin/env bash
# LASR-01 negative gate: no LASR-02+ downloader, engine, pipeline or Models UI wiring.
# Step-aware: LASR-02 owns downloader/storage/presence, while engines and direct model UI remain future work.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

python3 - <<'PY'
from pathlib import Path
import re

sources = Path("Sources")
if not sources.is_dir():
    raise SystemExit("FAIL: Sources directory missing")

state_path = Path("AI_Workflow_Kit/docs/AI/STATE.yaml")
state = state_path.read_text(encoding="utf-8") if state_path.is_file() else ""
step_match = re.search(r"^current_step:\s*([A-Za-z0-9_-]+)", state, re.M)
current_step = step_match.group(1) if step_match else ""
lasr_match = re.fullmatch(r"LASR-(\d+)", current_step)
lasr_step = int(lasr_match.group(1)) if lasr_match else None

model_ids = (
    "parakeet-tdt-06b-v3",
    "canary-180m-flash-coreml",
    "canary-1b-v2-coreml",
)
catalog_and_settings_files = {
    Path("Sources/VaniScriptCore/NativeModelCatalog.swift"),
    Path("Sources/VaniScriptCore/AppSettings.swift"),
}
app_sources = Path("Sources/VaniScript")
if not app_sources.is_dir():
    raise SystemExit(f"FAIL: {app_sources} directory missing")


def model_id_locations(model_id: str) -> set[Path]:
    return {
        path
        for path in sources.rglob("*.swift")
        if model_id in path.read_text(encoding="utf-8", errors="replace")
    }


def assert_lasr01_scope() -> None:
    for model_id in model_ids:
        locations = model_id_locations(model_id)
        if locations != catalog_and_settings_files:
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


def assert_lasr02_scope() -> None:
    downloader = Path("Sources/VaniScript/Services/ModelDownloadManager.swift")
    installer = Path("Sources/VaniScript/Services/RemoteModelPackageInstaller.swift")
    for path in (downloader, installer):
        if not path.is_file():
            raise SystemExit(f"FAIL: LASR-02 downloader/storage surface missing: {path}")

    allowed_id_files = catalog_and_settings_files | {downloader}
    for model_id in model_ids:
        unexpected = model_id_locations(model_id) - allowed_id_files
        if unexpected:
            rendered = ", ".join(str(path) for path in sorted(unexpected))
            raise SystemExit(f"FAIL: {model_id} wiring exceeds LASR-02 catalog/download scope: {rendered}")

    downloader_text = downloader.read_text(encoding="utf-8", errors="replace")
    for snippet in (
        "NativeModelCatalog.installDescriptor(for: id)",
        "NativeModelCatalog.isModelPresent",
        "RemoteModelPackageInstaller",
    ):
        if snippet not in downloader_text:
            raise SystemExit(f"FAIL: LASR-02 downloader lost catalog/presence contract: {snippet}")

    future_engine_files = (
        "LocalASREngine.swift",
        "LocalASRAudioPreprocessor.swift",
        "ParakeetASREngine.swift",
        "ParakeetTranscriptionEngine.swift",
        "CanaryCoreMLEngine.swift",
        "LocalASREngineRouter.swift",
    )
    for name in future_engine_files:
        matches = list(sources.rglob(name))
        if matches:
            raise SystemExit(f"FAIL: LASR-03+ engine wiring exists during LASR-02: {matches[0]}")

    for path in (
        Path("Sources/VaniScript/Services/NativeProcessingPipeline.swift"),
        Path("Sources/VaniScript/Views/SettingsView.swift"),
        Path("Sources/VaniScript/Views/ConfigWorkspaceView.swift"),
        Path("Sources/VaniScript/Stores/WorkflowStore.swift"),
    ):
        if not path.is_file():
            raise SystemExit(f"FAIL: expected future-wiring regression surface missing: {path}")
        text = path.read_text(encoding="utf-8", errors="replace")
        leaked = [model_id for model_id in model_ids if model_id in text]
        if leaked:
            raise SystemExit(f"FAIL: LASR-03+/UI model wiring leaked into {path}: {leaked}")

    allowed_backend_symbols = {
        downloader: {"LocalASRInstallSource", "import FluidAudio"},
    }
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
            if symbol in text and symbol not in allowed_backend_symbols.get(path, set()):
                raise SystemExit(
                    f"FAIL: LASR-03+/engine backend wiring '{symbol}' escaped LASR-02 downloader scope: {path}"
                )


if lasr_step == 2:
    assert_lasr02_scope()
    print("PASS: LASR-02 downloader/storage/presence wiring is allowed; engines, pipeline and direct model UI remain absent.")
elif lasr_step is not None and lasr_step >= 3:
    print(f"NOTE: current_step='{current_step}' owns LASR-03+ wiring; LASR-01 no-future gate is regression-history N/A.")
    print("RESULT: PASS (lasr01_no_future_wiring, step-aware N/A)")
else:
    assert_lasr01_scope()
    print("PASS: no downloader, engine, pipeline or Models UI wiring leaked into LASR-01.")
PY
