#!/usr/bin/env bash
# A7 (§11): catalog balanceKind mapping — OpenRouter=.openrouterCredits, Ollama Cloud=.ollamaPlan,
# Gemini/OpenAI/Anthropic/Qwen/Custom=.estimated (no fake $ providers).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/CloudProviderCatalog.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re
text = Path("Sources/VaniScriptCore/CloudProviderCatalog.swift").read_text(encoding="utf-8")
# BalanceKind enum cases
for n in ("case none", "case openrouterCredits", "case ollamaPlan", "case estimated"):
    if n not in text:
        raise SystemExit(f"FAIL: BalanceKind missing case: {n}")

def kind_for(pid):
    # find the descriptor block starting at `id: <pid>ID,` and read its balanceKind
    m = re.search(r"id:\s*" + pid + r"ID,.*?balanceKind:\s*\.([A-Za-z]+)", text, re.S)
    return m.group(1) if m else None

expect = {
    "gemini": "estimated",
    "openai": "estimated",
    "anthropic": "estimated",
    "qwen": "estimated",
    "openrouter": "openrouterCredits",
    "ollamaCloud": "ollamaPlan",
    "custom": "estimated",
}
for pid, want in expect.items():
    got = kind_for(pid)
    if got != want:
        raise SystemExit(f"FAIL: {pid} balanceKind = {got}, expected {want}")
print("PASS: catalog balanceKind mapping correct (OpenRouter credits, Ollama plan, rest estimated).")
PY
