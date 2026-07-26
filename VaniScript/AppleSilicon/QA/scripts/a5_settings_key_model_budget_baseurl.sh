#!/usr/bin/env bash
# A5: CloudKeyModelRow + budget (Qwen/OpenRouter) + Base URL (Ollama); no Ollama budget.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
start = text.find("private var cloudProviderCard")
if start < 0:
    raise SystemExit("FAIL: cloudProviderCard missing")
# Take a generous window of the A5 card helpers
chunk = text[start:start + 9000]

if "CloudKeyModelRow" not in chunk:
    raise SystemExit("FAIL: cloudProviderCard missing CloudKeyModelRow")
if "ollamaCloudBaseUrl" not in chunk and r"\.ollamaCloudBaseUrl" not in chunk:
    # binding(\.ollamaCloudBaseUrl)
    if "ollamaCloudBaseUrl" not in text[start:start+12000]:
        raise SystemExit("FAIL: Ollama Base URL binding missing")
if "Base URL" not in chunk:
    raise SystemExit("FAIL: Base URL row label missing for Ollama")

# budget paths: qwen + openrouter only
budget_start = text.find("private var budgetPath")
budget = text[budget_start:budget_start+400] if budget_start > 0 else ""
if "qwenBudgetUsd" not in budget:
    raise SystemExit("FAIL: budgetPath missing qwenBudgetUsd")
if "openrouterBudgetUsd" not in budget:
    raise SystemExit("FAIL: budgetPath missing openrouterBudgetUsd")
if "ollama" in budget.lower() and "ollamaBudget" in budget:
    raise SystemExit("FAIL: Ollama must not have a budget slider (plan-based A7)")

# text model paths
model_start = text.find("private var textModelPath")
models = text[model_start:model_start+500] if model_start > 0 else ""
for f in ("qwenCloudModel", "openrouterModel", "ollamaCloudModel"):
    if f not in models:
        raise SystemExit(f"FAIL: textModelPath missing {f}")

print("PASS: CloudKeyModelRow + Qwen/OpenRouter budget + Ollama Base URL (no Ollama budget).")
PY
