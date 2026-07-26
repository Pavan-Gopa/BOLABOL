#!/usr/bin/env bash
# A6: UI only — UsageStatisticsView is view layer; no engine/registry/UsageRecorder rewrite in A6 targets.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

USAGE="Sources/VaniScript/Views/UsageStatisticsView.swift"
SETTINGS="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$USAGE" ]] || { echo "FAIL: $USAGE missing"; exit 1; }
[[ -f "$SETTINGS" ]] || { echo "FAIL: $SETTINGS missing"; exit 1; }

# UsageStatisticsView must not define engines / recorder / registry
python3 - <<'PY'
from pathlib import Path
import re
usage = Path("Sources/VaniScript/Views/UsageStatisticsView.swift").read_text(encoding="utf-8")
for forbidden in (
    r"class\s+CloudAudioTranscriptionEngine",
    r"class\s+CloudTextTranslationEngine",
    r"struct\s+UsageRecorder",
    r"enum\s+UsageRecorder",
    r"struct\s+ProviderRegistry",
    r"enum\s+ProviderRegistry",
    r"CloudChatRouter",
):
    if re.search(forbidden, usage):
        raise SystemExit(f"FAIL: A6 UI-only violated in UsageStatisticsView: {forbidden}")
# Must stay UI/data-from-settings
if "WorkflowStore" not in usage and "EnvironmentObject" not in usage:
    raise SystemExit("FAIL: UsageStatisticsView should bind to store/settings")
# Core product files still exist (not deleted by A6)
for f in (
    "Sources/VaniScriptCore/UsageRecorder.swift",
    "Sources/VaniScriptCore/ProviderRegistry.swift",
    "Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift",
    "Sources/VaniScript/Services/CloudTextTranslationEngine.swift",
):
    if not Path(f).is_file():
        raise SystemExit(f"FAIL: expected product file missing: {f}")
print("PASS: A6 is UI-only; engines/registry/UsageRecorder still present, not redefined in UsageStatisticsView.")
PY
