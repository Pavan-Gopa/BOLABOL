#!/usr/bin/env bash
# LASR-01: independent review approval and coherent workflow state without step/post-tag advancement.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

python3 - <<'PY'
from pathlib import Path
import re

state_path = Path("AI_Workflow_Kit/docs/AI/STATE.yaml")
feedback_path = Path("AI_Workflow_Kit/docs/AI/FEEDBACK.md")
for path in (state_path, feedback_path):
    if not path.is_file():
        raise SystemExit(f"FAIL: {path} missing")
state = state_path.read_text(encoding="utf-8")
feedback = feedback_path.read_text(encoding="utf-8")

def scalar(key: str) -> str:
    match = re.search(rf"^{re.escape(key)}:\s*['\"]?([^'\"\n]+?)['\"]?\s*$", state, re.M)
    if not match:
        raise SystemExit(f"FAIL: STATE scalar missing: {key}")
    return match.group(1).strip()

def nested_scalar(section: str, key: str) -> str:
    match = re.search(rf"^{re.escape(section)}:\s*$\n(?P<body>(?:^[ \t]+.*\n?)*)", state, re.M)
    if not match:
        raise SystemExit(f"FAIL: STATE section missing: {section}")
    value = re.search(rf"^[ \t]+{re.escape(key)}:\s*['\"]?([^'\"\n]+?)['\"]?\s*$", match.group("body"), re.M)
    if not value:
        raise SystemExit(f"FAIL: STATE {section}.{key} missing")
    return value.group(1).strip()

if scalar("current_step") != "LASR-01":
    raise SystemExit("FAIL: STATE current_step must remain LASR-01")
if scalar("track") != "LOCAL_ASR_COREML":
    raise SystemExit("FAIL: STATE track must be LOCAL_ASR_COREML")
if nested_scalar("implementation", "status") != "approved":
    raise SystemExit("FAIL: STATE implementation.status is not approved")
if nested_scalar("review", "status") != "approved":
    raise SystemExit("FAIL: STATE review.status is not approved")
if nested_scalar("checkpoint", "last_post_tag") != "local-asr-coreml/ASR-ARCH-done":
    raise SystemExit("FAIL: LASR-01 QA must not advance checkpoint.last_post_tag")

report_start = feedback.find("# Verification Report — LASR-01")
if report_start < 0:
    raise SystemExit("FAIL: FEEDBACK LASR-01 Verification Report missing")
report = feedback[report_start:]
if not re.search(r"\*\*RESULT:\*\*\s*\[APPROVED\]", report):
    raise SystemExit("FAIL: LASR-01 reviewer RESULT is not [APPROVED]")

expected_targets = [
    "Package.swift",
    "Package.resolved",
    "Sources/VaniScriptCore/NativeModelCatalog.swift",
    "Sources/VaniScriptCore/AppSettings.swift",
    "Sources/VaniScriptCore/SharedModelsRoot.swift",
    "Sources/VaniScript/Services/SettingsDiskStore.swift",
    "Tests/VaniScriptCoreTests/NativeModelCatalogTests.swift",
    "Tests/VaniScriptCoreTests/SharedModelsRootTests.swift",
    "Tests/VaniScriptCoreTests/UniversalSettingsTests.swift",
    "AI_Workflow_Kit/docs/AI/FEEDBACK.md",
]
target_match = re.search(r"^target_files:\s*$\n(?P<body>(?:^  - .*\n)+)", state, re.M)
if not target_match:
    raise SystemExit("FAIL: STATE target_files missing")
actual_targets = re.findall(r"^  - (.+)$", target_match.group("body"), re.M)
if actual_targets != expected_targets:
    raise SystemExit(f"FAIL: STATE LASR-01 target_files mismatch: {actual_targets}")

qa_status = nested_scalar("qa", "status")
bugs_open = int(nested_scalar("qa", "bugs_open"))
next_actor = scalar("next_actor")
coherent = (
    (qa_status == "pending" and bugs_open == 0 and next_actor == "qa")
    or (qa_status == "green" and bugs_open == 0 and next_actor == "orchestrator")
    or (qa_status == "red" and bugs_open > 0 and next_actor == "orchestrator")
)
if not coherent:
    raise SystemExit(
        f"FAIL: incoherent QA transition status={qa_status}, bugs_open={bugs_open}, next_actor={next_actor}"
    )

print("PASS: LASR-01 review is APPROVED and STATE remains on LASR-01 with coherent QA ownership.")
PY
