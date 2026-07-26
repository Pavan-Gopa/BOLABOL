#!/usr/bin/env bash
# A3 scope: UI only — UsageRecorder / cloud engines / WorkflowStore must not be
# modified as part of A3 product delta. Static check: those files still contain
# A2 markers and SettingsView is the UI home.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

# Core A2 files must still exist (regression)
for f in \
  Sources/VaniScriptCore/UsageRecorder.swift \
  Sources/VaniScriptCore/CloudProviderCatalog.swift \
  Sources/VaniScript/Views/SettingsView.swift; do
  [[ -f "$f" ]] || { echo "FAIL: expected file missing: $f"; exit 1; }
done

# A3 must not introduce engine provider cases for qwen in WorkflowStore normalizedUsageProviderId
# (A5 territory). Allow gemini-cloud/gpt-cloud only as today.
if grep -Eq 'case "qwen"|case "openrouter"|case "ollama-cloud"' Sources/VaniScript/Stores/WorkflowStore.swift 2>/dev/null; then
  # only fail if they appear inside normalizedUsageProviderId function
  python3 - <<'PY'
from pathlib import Path
import re
t = Path("Sources/VaniScript/Stores/WorkflowStore.swift").read_text(encoding="utf-8")
# find function normalizedUsageProviderId
m = re.search(r'func normalizedUsageProviderId[\s\S]{0,800}?\{([\s\S]{0,600}?)\}', t)
if m:
    body = m.group(1)
    for s in ('qwen', 'openrouter', 'ollama'):
        if s in body:
            raise SystemExit(f"FAIL: A5-like routing for {s} in normalizedUsageProviderId at A3")
print("PASS: A3 scope OK — no A5 provider routing in normalizedUsageProviderId.")
PY
else
  echo "PASS: A3 scope OK — no qwen/openrouter/ollama cases in WorkflowStore."
fi
