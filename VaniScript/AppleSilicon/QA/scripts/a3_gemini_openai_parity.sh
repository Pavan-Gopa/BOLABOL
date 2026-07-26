#!/usr/bin/env bash
# A3: Gemini/OpenAI cards — key + ReadOnlyRow model + budget Slider + Transcribing/Translation toggles 1:1.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
start = text.find("private struct ProviderCardView")
end = text.find("private struct ApiKeyInputRow", start)
card = text[start:end if end > 0 else None]
checks = {
    "gemini": [
        r'binding(\\.geminiKey)',
        'ReadOnlyRow(title: "Text Model"',
        r'binding(\\.geminiBudgetUsd)',
        "gemini-cloud",
        "coreml-whisperkit",
        "mlx-native",
        "Use for Transcribing",
        "Use for Translation",
    ],
    "openai": [
        r'binding(\\.openaiKey)',
        'ReadOnlyRow(title: "Text Model"',
        r'binding(\\.openaiBudgetUsd)',
        "gpt-cloud",
        "Use for Transcribing",
        "Use for Translation",
    ],
}
import re
for name, needles in checks.items():
    for n in needles:
        if n.startswith("r'") or n.startswith('r"'):
            continue
        # plain
        if n.startswith("binding(") or "\\" in n:
            if not re.search(n.replace("\\\\", "\\") if False else re.escape(n) if "binding" in n else n, card):
                # try raw contains
                plain = n.replace(r'\.', '.')
                if plain not in card and n not in card:
                    # special for binding paths
                    if "geminiKey" in n and "geminiKey" not in card:
                        raise SystemExit(f"FAIL: Gemini card missing geminiKey binding")
                    if "openaiKey" in n and "openaiKey" not in card:
                        raise SystemExit(f"FAIL: OpenAI card missing openaiKey binding")
                    if "geminiBudgetUsd" in n and "geminiBudgetUsd" not in card:
                        raise SystemExit(f"FAIL: Gemini budget Slider binding missing")
                    if "openaiBudgetUsd" in n and "openaiBudgetUsd" not in card:
                        raise SystemExit(f"FAIL: OpenAI budget Slider binding missing")
            continue
        if n not in card:
            raise SystemExit(f"FAIL: {name} card missing: {n}")
# SliderRow for budgets
if 'SliderRow(title: "Gemini Budget"' not in card:
    raise SystemExit("FAIL: Gemini Budget SliderRow missing")
if 'SliderRow(title: "OpenAI Budget"' not in card:
    raise SystemExit("FAIL: OpenAI Budget SliderRow missing")
# ApiKey rows
if 'ApiKeyInputRow(title: "Gemini Key"' not in card:
    raise SystemExit("FAIL: Gemini Key ApiKeyInputRow missing")
if 'ApiKeyInputRow(title: "OpenAI Key"' not in card:
    raise SystemExit("FAIL: OpenAI Key ApiKeyInputRow missing")
print("PASS: Gemini/OpenAI cards have key + ReadOnlyRow + budget Slider + toggles.")
PY
