#!/usr/bin/env bash
# A7 (ADR §3): Ollama Cloud is plan-based (GPU time), never a fake "$".
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudBalanceService.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScriptCore/CloudBalanceService.swift").read_text(encoding="utf-8")
if "public struct OllamaCloudBalanceProvider: BalanceProvider" not in text:
    raise SystemExit("FAIL: OllamaCloudBalanceProvider missing")
if 'Plan-based (GPU time)' not in text:
    raise SystemExit("FAIL: Ollama must surface the honest 'Plan-based (GPU time)' label")
if ".planLimits(label:" not in text:
    raise SystemExit("FAIL: Ollama must return .planLimits")
# The Ollama provider must NOT fabricate a USD amount.
ollama = text.split("public struct OllamaCloudBalanceProvider", 1)[1]
ollama = ollama.split("// MARK: - CloudBalanceService", 1)[0]
if ".usd(" in ollama:
    raise SystemExit("FAIL: Ollama provider must never return a .usd amount")
print("PASS: Ollama Cloud → .planLimits('Plan-based (GPU time)'), never a fake $.")
PY
